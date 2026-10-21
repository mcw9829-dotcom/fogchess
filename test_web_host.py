"""Production handler tests, isolated fixture assets and SQLite only."""
import gzip
import http.client
import json
import os
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch
import web_server


class WebHostTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='fogchess-host-test-')
        cls.root = Path(cls.temp.name)
        cls.assets = cls.root / 'web'
        cls.assets.mkdir()
        for extension in ('html', 'js', 'wasm', 'pck'):
            (cls.assets / f'index.{extension}').write_bytes(b'fixture-' + extension.encode())
        (cls.assets / 'index.wasm.gz').write_bytes(gzip.compress(b'fixture-wasm'))
        (cls.root / 'secret.db').write_bytes(b'not-public')
        (cls.assets / 'source.gd').write_bytes(b'not-public')
        cls.patch = patch.object(web_server, 'WEB_ROOT', cls.assets)
        cls.patch.start()
        cls.env = patch.dict(os.environ, {'FOG_CLIENT': 'godot', 'FOG_ADMIN_KEY': 'temporary-admin-test'})
        cls.env.start()
        web_server.server.accounts.init_db(str(cls.root / 'test.db'))
        cls.httpd = web_server.server.ThreadingServer(('127.0.0.1', 0), web_server.WebHandler)
        cls.thread = threading.Thread(target=cls.httpd.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown(); cls.httpd.server_close(); cls.thread.join()
        cls.patch.stop(); cls.env.stop(); cls.temp.cleanup()

    def request(self, path, method='GET', body=None, headers=None):
        connection = http.client.HTTPConnection('127.0.0.1', self.httpd.server_port)
        hdr = dict(headers or {})
        if body is not None:
            body = json.dumps(body)
            hdr['Content-Type'] = 'application/json'
        connection.request(method, path, body, hdr)
        response = connection.getresponse()
        result = response.status, dict(response.getheaders()), response.read()
        connection.close()
        return result

    def test_entry_points(self):
        for path, expected in [('/', '/godot/'),('/?x=1','/godot/?x=1'),('/godot','/godot/'),('/admin','/godot/?admin=1')]:
            with self.subTest(path=path):
                status, headers, _ = self.request(path)
                self.assertEqual(status, 302)
                self.assertEqual(headers['Location'], expected)

    def test_runtime_mime_and_head(self):
        for extension, mime in [('wasm','application/wasm'),('pck','application/octet-stream'),('js','application/javascript')]:
            with self.subTest(extension=extension):
                status, headers, body = self.request('/godot/index.'+extension)
                self.assertEqual(status,200); self.assertEqual(headers['Content-Type'],mime)
                self.assertEqual(body,b'fixture-'+extension.encode())
        status, headers, body = self.request('/godot/index.wasm','HEAD')
        self.assertEqual(status,200); self.assertEqual(body,b'')
        self.assertEqual(int(headers['Content-Length']),len(b'fixture-wasm'))

    def test_gzip_negotiation(self):
        status, headers, body = self.request('/godot/index.wasm',headers={'Accept-Encoding':'gzip'})
        self.assertEqual(status,200); self.assertEqual(headers['Content-Encoding'],'gzip')
        self.assertEqual(gzip.decompress(body),b'fixture-wasm')
        for accept in ['gzip;q=0','br','gzip;q=bad']:
            _, headers, body = self.request('/godot/index.wasm',headers={'Accept-Encoding':accept})
            self.assertNotIn('Content-Encoding',headers); self.assertEqual(body,b'fixture-wasm')

    def test_assets_cannot_escape_root_or_expose_sources(self):
        for path in ['/godot/../secret.db','/godot/%2e%2e%2fsecret.db','/godot/%2e%2e%5csecret.db','/godot/source.gd','/godot/missing.js']:
            with self.subTest(path=path): self.assertEqual(self.request(path)[0],404)

    def test_health_detects_missing_export(self):
        self.assertEqual(self.request('/healthz')[0],200)
        file=self.assets/'index.pck'; file.rename(file.with_suffix('.hold'))
        try: self.assertEqual(self.request('/healthz')[0],503)
        finally: file.with_suffix('.hold').rename(file)

    def test_legacy_fallback_and_api(self):
        self.assertEqual(self.request('/classic')[0],200)
        self.assertEqual(self.request('/admin-classic')[0],200)
        with patch.dict(os.environ, {'FOG_CLIENT':'classic'}):
            self.assertEqual(self.request('/')[0],200)
        self.assertIn('version',json.loads(self.request('/version')[2]))
        self.assertIn('rows',json.loads(self.request('/leaderboard')[2]))

    def test_admin_authorization_and_feedback_lifecycle(self):
        self.assertEqual(self.request('/admin/users')[0],403)
        self.assertEqual(self.request('/feedback')[0],403)
        headers={'X-Admin-Key':'temporary-admin-test'}
        self.assertEqual(self.request('/admin/check',headers=headers)[0],200)
        accounts=web_server.server.accounts
        accounts.add_feedback('bug','temporary integration test','tester',None,None,None)
        rows=json.loads(self.request('/feedback?all=1',headers=headers)[2])['rows']
        fid=rows[0]['id']
        self.assertEqual(self.request('/feedback/done','POST',{'id':fid})[0],403)
        for done in [True,False]:
            result=json.loads(self.request('/feedback/done','POST',{'id':fid,'done':done},headers)[2])
            self.assertTrue(result['ok'])
            self.assertEqual(bool(accounts.feedback_list(include_done=True)[0]['done']),done)
        self.assertTrue(json.loads(self.request('/feedback/delete','POST',{'id':fid},headers)[2])['ok'])
        self.assertEqual(accounts.feedback_list(include_done=True),[])


if __name__=='__main__': unittest.main(verbosity=2)
