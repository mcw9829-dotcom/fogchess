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
        if self.path not in ('/test-age', '/test-end'):
            return super()._post()
        data = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        with server.lock:
            room = server.ROOMS[data['room']]
            server.use_terrain(room)
            if self.path == '/test-end':
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
                '--path', str(ROOT/'godot'), '--script', 'res://tests/watch_smoke.gd']
        if '--capture' not in sys.argv: args.append('--headless')
        args += ['--', '--smoke']
        if '--capture' in sys.argv: args.append('--capture')
        try:
            p = subprocess.run(args, env=env, timeout=60, capture_output=True)
            text = p.stdout.decode(errors='replace') + p.stderr.decode(errors='replace')
            print(text)
            return int(p.returncode != 0 or 'WATCH_FAILURES=0' not in text or 'ERROR:' in text)
        finally:
            httpd.shutdown()
            httpd.server_close()


if __name__ == '__main__':
    raise SystemExit(main())
