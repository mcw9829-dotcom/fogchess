"""Isolated development host for the unchanged Fog Chess engine and Godot Web export.

Run with Python 3. No production database or Fly configuration is used.
"""
import json
import mimetypes
import os
from pathlib import Path
import sys
import threading
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parent
DATA = ROOT / '.dev-data'
DATA.mkdir(exist_ok=True)
os.environ['FOG_DB'] = str(DATA / 'fogchess-dev.db')
os.environ['PORT'] = os.environ.get('FOG_DEV_PORT', '7556')
sys.path.insert(0, str(ROOT))
import server  # noqa: E402 -- environment must be set before importing config/accounts
from web_server import WebHandler


class DevHandler(WebHandler):
    def _get(self):
        path = unquote(urlsplit(self.path).path)
        if path == '/dev-health':
            self._json({'ok': True, 'service': 'fogchess-godot-development',
                        'version': server.APP_VERSION})
            return
        super()._get()


if __name__ == '__main__':
    host = os.environ.get('FOG_DEV_HOST', '127.0.0.1')
    server.accounts.init_db()
    server.LAN_URL = f'http://{host}:{server.PORT}'
    httpd = server.ThreadingServer((host, server.PORT), DevHandler)
    threading.Thread(target=server.sweeper, daemon=True).start()
    print(f'Development server: {server.LAN_URL}', flush=True)
    print(f'Isolated database: {DATA / "fogchess-dev.db"}', flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()
