"""Production/development Godot Web host over the existing authoritative API."""
import os
import hashlib
from functools import lru_cache
from pathlib import Path
import shutil
import threading
from urllib.parse import urlsplit, unquote
import server

ROOT = Path(__file__).resolve().parent
WEB_ROOT = ROOT / 'godot' / 'build' / 'web'
MIME = {'.html': 'text/html; charset=utf-8', '.js': 'application/javascript',
        '.wasm': 'application/wasm', '.pck': 'application/octet-stream',
        '.png': 'image/png', '.svg': 'image/svg+xml', '.ico': 'image/x-icon'}


@lru_cache(maxsize=128)
def asset_etag(path, modified_ns, changed_ns, size):
    """Hash each file revision once; unchanged assets keep their ETag across deploys."""
    with path.open('rb') as stream:
        return '"' + hashlib.file_digest(stream, 'sha256').hexdigest() + '"'


class WebHandler(server.Handler):
    protocol_version = 'HTTP/1.1'

    def setup(self):
        super().setup()
        # Bound idle keep-alive connections on the threaded game server.
        self.connection.settimeout(30)

    def end_headers(self):
        if self.close_connection:
            self.send_header('Connection', 'close')
        super().end_headers()

    def _redirect(self, destination):
        self.send_response(302)
        self.send_header('Location', destination)
        self.send_header('Content-Length', '0')
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self._sent = True

    def _get(self):
        url = urlsplit(self.path)
        path = unquote(url.path)
        godot = os.environ.get('FOG_CLIENT', 'godot') == 'godot'
        if path == '/healthz':
            ready = not godot or all((WEB_ROOT / f'index.{ext}').is_file() for ext in ('html', 'js', 'wasm', 'pck'))
            self._json({'ok': ready, 'client': 'godot' if godot else 'classic'}, 200 if ready else 503)
            return
        if path in ('/', '/index.html') and godot:
            self._redirect('/godot/' + ('?' + url.query if url.query else ''))
            return
        if path == '/admin' and godot:
            self._redirect('/godot/?admin=1')
            return
        if path == '/classic':
            self._file('client.html', MIME['.html'])
            return
        if path == '/admin-classic':
            self._file('admin.html', MIME['.html'])
            return
        if path == '/godot':
            self._redirect('/godot/' + ('?' + url.query if url.query else ''))
            return
        if path.startswith('/godot/'):
            base = WEB_ROOT.resolve()
            target = (base / (path[len('/godot/'):] or 'index.html')).resolve()
            if not target.is_relative_to(base) or target.suffix not in MIME or not target.is_file():
                self._json({'ok': False, 'msg': 'Godot Web file not found. Run python tools/prepare_release.py before deployment.'}, 404)
                return
            mime = MIME[target.suffix]
            gzip_ok = False
            for item in self.headers.get('Accept-Encoding', '').split(','):
                parts = item.strip().split(';')
                if parts[0].strip().lower() == 'gzip':
                    try:
                        quality = next((float(p.strip()[2:]) for p in parts[1:] if p.strip().startswith('q=')), 1)
                        gzip_ok = quality > 0
                    except ValueError:
                        pass
            compressed = target.with_name(target.name + '.gz')
            encoded = gzip_ok and compressed.is_file() and compressed.stat().st_mtime >= target.stat().st_mtime
            if encoded:
                target = compressed
            stat = target.stat()
            etag = asset_etag(target, stat.st_mtime_ns, stat.st_ctime_ns, stat.st_size)
            # GET/HEAD use weak comparison. Keep gzip and identity representations distinct.
            candidates = [value.strip().removeprefix('W/') for value in self.headers.get('If-None-Match', '').split(',')]
            unchanged = etag in candidates or '*' in candidates
            self.send_response(304 if unchanged else 200)
            self.send_header('Content-Type', mime)
            if not unchanged:
                self.send_header('Content-Length', str(stat.st_size))
            self.send_header('Cache-Control', 'no-cache')
            self.send_header('ETag', etag)
            self.send_header('Vary', 'Accept-Encoding')
            self.send_header('X-Content-Type-Options', 'nosniff')
            if encoded:
                self.send_header('Content-Encoding', 'gzip')
            self.end_headers()
            self._sent = True
            if not unchanged and self.command != 'HEAD':
                with target.open('rb') as stream:
                    shutil.copyfileobj(stream, self.wfile, length=64 * 1024)
            return
        super()._get()

    def do_HEAD(self):
        if urlsplit(self.path).path.startswith('/godot/'):
            self._safe(self._get)
        else:
            self.send_response(405)
            self.send_header('Content-Length', '0')
            self.end_headers()


if __name__ == '__main__':
    server.accounts.init_db()
    server.LAN_URL = f'http://127.0.0.1:{server.PORT}'
    httpd = server.ThreadingServer((os.environ.get('FOG_HOST', '0.0.0.0'), server.PORT), WebHandler)
    threading.Thread(target=server.sweeper, daemon=True).start()
    print(f'Fog Chess: Godot Web + Python API, port {server.PORT}', flush=True)
    try:
        httpd.serve_forever()
    finally:
        httpd.server_close()
