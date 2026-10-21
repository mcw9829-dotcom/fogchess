"""Real Godot client -> local HTTP -> existing Python rules; temporary account DB.

Usage: python run_godot_smoke.py [--capture]
The fixture endpoints exist only in this test process, never in dev_server.py.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import uuid

from godot_runtime import default_godot

import dev_server

server = dev_server.server
ROOT = Path(__file__).resolve().parent


class FixtureHandler(dev_server.DevHandler):
    def _post(self):
        if self.path not in ('/test-fixture', '/test-return-turn'):
            return super()._post()
        data = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        with server.lock:
            if self.path == '/test-return-turn':
                server.ROOMS[data['room']]['state']['turn'] = 'W'
                self._json({'ok': True})
                return
            scenario = data['scenario']
            code = server.gen_code()
            room = server.new_room(code)
            room['terrain'] = {'seed': 1, 'forests': set(), 'rivers': set(),
                               'bushes': {(3, 4)} if scenario == 'scan' else set(), 'impassable': set()}
            token = uuid.uuid4().hex
            room['solo'] = True
            room['seats'] = {'W': token, 'B': token}
            room['tokens'] = {token: 'solo'}
            room['seen'] = {token: time.time()}
            st = room['state']
            st['phase'] = 'play'
            for p in st['pieces'].values():
                p['alive'] = False
            def place(pid, r, c):
                st['pieces'][pid].update(alive=True, r=r, c=c, moved=True)
            place('W_K1', 11, 11)
            place('B_K1', 3, 4)
            if scenario == 'scan': place('W_Q1', 6, 4)
            if scenario == 'fire': place('W_B1', 4, 4)
            if scenario in ('barrage', 'capture'): place('W_R1', 4, 4)
            if scenario == 'promotion': place('W_P1', 1, 4)
            if scenario.startswith('piece_'):
                kind = scenario.split('_')[1]
                place('B_K1', 0, 0)
                place('W_' + kind + '1', 6, 6)
                target = (4, 7) if kind == 'N' else (5, 7)
                if kind == 'R': target = (5, 6)
                place('B_P1', *target)
            if scenario == 'blocked_bishop':
                place('B_K1', 0, 0)
                place('W_B1', 10, 6)
                for pid, pos in zip(('W_P1','W_P2','W_P3','W_P4'), ((9,5),(9,7),(11,5),(11,7))):
                    place(pid, *pos)

            if scenario == 'trophies':
                import pieces
                for pid in ('B_P1','B_P2','B_P3','B_N1','B_B1','B_R1','B_Q1'):
                    st['pieces'][pid]['alive'] = True
                    pieces.kill(st, st['pieces'][pid], 'W', 'B', 'artillery')
                st['move_history'] = {'W': ['1. 비숍 c7 저격 → d4', '3. 전차 c7 이동 → c5']}

            server.ROOMS[code] = room
            self._json({'room': code, 'token': token, 'color': 'solo'})


def main():
    godot = default_godot()
    with tempfile.TemporaryDirectory(prefix='fogchess-godot-test-') as directory:
        server.accounts.init_db(str(Path(directory) / 'test.db'))
        os.environ['FOG_ADMIN_KEY'] = uuid.uuid4().hex
        server.accounts.add_feedback('bug', 'Godot admin fixture', 'LocalTester', None, None, 'Godot test')
        httpd = server.ThreadingServer(('127.0.0.1', 0), FixtureHandler)
        threading.Thread(target=httpd.serve_forever, daemon=True).start()
        env = dict(os.environ, FOG_TEST_URL=f'http://127.0.0.1:{httpd.server_port}', FOG_TEST_ADMIN_KEY=os.environ['FOG_ADMIN_KEY'])
        log = ROOT / 'godot' / 'tests' / 'smoke.log'
        args = [godot, '--path', str(ROOT / 'godot'), '--script', 'res://tests/smoke.gd', '--log-file', str(log)]
        if '--capture' not in sys.argv and '--social-capture' not in sys.argv: args += ['--headless']
        args += ['--', '--smoke']
        if '--capture' in sys.argv: args += ['--capture']
        if '--social-capture' in sys.argv: args += ['--social-capture']
        try:
            result = subprocess.run(args, env=env, timeout=140, capture_output=True)
            output = log.read_text(encoding='utf-8')
            print(output)
            return int(result.returncode != 0 or 'SCRIPT ERROR' in output or 'ERROR:' in output or 'GODOT_SMOKE_FAILURES=0' not in output)
        finally:
            httpd.shutdown()
            httpd.server_close()


if __name__ == '__main__':
    raise SystemExit(main())
