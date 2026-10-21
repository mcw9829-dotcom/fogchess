"""Isolated real Godot/HTTP spectator integration, no production or dev database."""
import collections
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
from run_godot_smoke import FixtureHandler, server, ROOT
import spectator
from godot_runtime import default_godot


class WatchFixture(FixtureHandler):
    def _post(self):
        if self.path not in ('/test-age', '/test-end', '/test-brush'):
            return super()._post()
        data = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        with server.lock:
            room = server.ROOMS[data['room']]
            server.use_terrain(room)
            if self.path == '/test-brush':
                room['terrain']['bushes'] = {(6,6),(6,7),(5,7),(4,7),(4,8)}
                room['terrain']['forests'] = {(3,3),(4,3),(4,4),(7,3),(8,3),(8,4)}
                room['terrain']['impassable'] = set(room['terrain']['forests'])
                for pid, r, c in [('W_Q1',8,6),('W_P1',7,7),('B_R1',3,8),('B_N1',5,9),('B_P2',4,8)]:
                    room['state']['pieces'][pid].update(alive=True,r=r,c=c,moved=True)
                server.use_terrain(room)
                spectator.capture(room)
            elif self.path == '/test-end':
                room['state'].update(phase='over', winner='W')
                spectator.capture(room)
            else:
                timeline = room['_broadcast']
                shift = time.time() - 181 - timeline[-1][0]
                room['_broadcast'] = collections.deque((at + shift, view) for at, view in timeline)
            self._json({'ok': True})


def main():
    with tempfile.TemporaryDirectory(prefix='fog-watch-test-') as directory:
        server.accounts.init_db(str(Path(directory)/'test.db'))
        httpd = server.ThreadingServer(('127.0.0.1', 0), WatchFixture)
        threading.Thread(target=httpd.serve_forever, daemon=True).start()
        env = dict(os.environ, FOG_TEST_URL=f'http://127.0.0.1:{httpd.server_port}')
        args = [default_godot(),
                '--path', str(ROOT/'godot'), '--script', 'res://tests/replay_smoke.gd']
        if '--verbose' in sys.argv: args.append('--verbose')
        if '--capture' not in sys.argv: args.append('--headless')
        args += ['--', '--smoke']
        if '--capture' in sys.argv: args.append('--capture')
        try:
            try:
                p = subprocess.run(args, env=env, timeout=35, capture_output=True)
            except subprocess.TimeoutExpired as e:
                print((e.stdout or b'').decode(errors='replace'))
                print((e.stderr or b'').decode(errors='replace'))
                raise
            text = p.stdout.decode(errors='replace') + p.stderr.decode(errors='replace')
            print(text)
            return int(p.returncode != 0 or 'REPLAY_FAILURES=0' not in text or 'ERROR:' in text)
        finally:
            httpd.shutdown()
            httpd.server_close()


if __name__ == '__main__':
    raise SystemExit(main())
