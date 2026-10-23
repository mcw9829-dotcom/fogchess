"""Production handler tests, isolated fixture assets and SQLite only."""
import gzip
import http.client
import json
import os
import hashlib
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
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

    def test_unchanged_assets_revalidate_without_downloading_a_body(self):
        for encoding in ('identity', 'gzip'):
            request_headers = {'Accept-Encoding':encoding}
            status, first, body = self.request('/godot/index.wasm', headers=request_headers)
            self.assertEqual(status, 200)
            self.assertEqual(first['ETag'], '"'+hashlib.sha256(body).hexdigest()+'"')
            for validator in (first['ETag'], 'W/'+first['ETag'], '"old", '+first['ETag'], '*'):
                for method in ('GET','HEAD'):
                    status, headers, body = self.request('/godot/index.wasm', method, headers={**request_headers, 'If-None-Match':validator})
                    self.assertEqual(status, 304)
                    self.assertEqual(body, b'')
                    self.assertEqual(headers['ETag'], first['ETag'])
                    self.assertEqual(headers['Vary'], 'Accept-Encoding')
                    self.assertNotIn('Content-Length', headers)

    def test_http11_revalidation_keeps_connection_framing_correct(self):
        connection = http.client.HTTPConnection('127.0.0.1', self.httpd.server_port, timeout=5)
        try:
            connection.request('GET','/godot/index.wasm')
            first = connection.getresponse()
            self.assertEqual(first.version, 11)
            etag = first.getheader('ETag')
            self.assertEqual(first.read(), b'fixture-wasm')
            connection.request('GET','/godot/index.wasm', headers={'If-None-Match':etag})
            unchanged = connection.getresponse()
            self.assertEqual(unchanged.status,304)
            self.assertEqual(unchanged.read(), b'')
            connection.request('GET','/healthz')
            self.assertTrue(json.loads(connection.getresponse().read())['ok'])
            with patch.object(web_server.WebHandler, '_get', side_effect=RuntimeError('fixture failure')):
                connection.request('GET','/healthz')
                failed = connection.getresponse()
                self.assertEqual(failed.status,500)
                self.assertFalse(json.loads(failed.read())['ok'])
        finally:
            connection.close()

    def test_oversized_body_closes_connection_instead_of_reusing_unread_input(self):
        with patch.object(web_server.server, 'MAX_BODY', 16):
            status, headers, _ = self.request('/join','POST',{'name':'x'*32})
            self.assertEqual(status,413)
            self.assertEqual(headers['Connection'],'close')

    def test_gzip_etag_cannot_validate_uncompressed_representation(self):
        _, headers, _ = self.request('/godot/index.wasm', headers={'Accept-Encoding':'gzip'})
        status, raw_headers, raw = self.request('/godot/index.wasm', headers={'If-None-Match':headers['ETag']})
        self.assertEqual(status, 200)
        self.assertEqual(raw, b'fixture-wasm')
        self.assertNotEqual(raw_headers['ETag'], headers['ETag'])

    def test_asset_edits_invalidate_cache_but_redeploying_identical_bytes_does_not(self):
        file = self.assets/'index.pck'
        original = file.read_bytes()
        stamp = file.stat().st_mtime_ns
        _, first, _ = self.request('/godot/index.pck')
        try:
            # A new deploy timestamp alone must not redownload the same engine/assets.
            os.utime(file, ns=(stamp+1_000_000,stamp+1_000_000))
            self.assertEqual(self.request('/godot/index.pck', headers={'If-None-Match':first['ETag']})[0], 304)
            file.write_bytes(b'x' * len(original))
            os.utime(file, ns=(stamp+2_000_000,stamp+2_000_000))
            status, updated, body = self.request('/godot/index.pck', headers={'If-None-Match':first['ETag']})
            self.assertEqual(status, 200)
            self.assertNotEqual(updated['ETag'], first['ETag'])
            self.assertEqual(body, b'x' * len(original))
        finally:
            file.write_bytes(original)

    def test_patchnote_revision_follows_latest_notice_content(self):
        notes = self.root/'notes.txt'
        latest = '[2026-10-22] v1.52 — 새 업데이트\n[개선] 테스트 안내\n'
        previous = '[2026-09-10] v1.51 — 이전 기록\n[수정] 이전 내용\n'
        with patch.object(web_server.server, 'NOTES_PATH', str(notes)), patch.object(web_server.server, '_NOTES_CACHE', {'mtime':None, 'data':[]}):
            revisions = []
            for index, text in enumerate((latest+previous, latest+previous+'[기술] 옛 기록 보충\n', latest.replace('테스트 안내','변경된 안내')+previous)):
                notes.write_text(text, encoding='utf-8')
                os.utime(notes, (1_700_000_000+index,1_700_000_000+index))
                response = json.loads(self.request('/patchnotes')[2])
                revisions.append(response['revision'])
                self.assertEqual(len(response['entries']),2)
            self.assertEqual(revisions[0],revisions[1])
            self.assertNotEqual(revisions[0],revisions[2])

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
        # Moving files into web/ must preserve the classic client's public URLs.
        for path, mime in [('/style.css', 'text/css'), ('/game.js', 'application/javascript'),
                           ('/sound.js', 'application/javascript'), ('/fx.js', 'application/javascript'),
                           ('/tutorial.js', 'application/javascript'), ('/img/Chess_klt45.svg', 'image/svg+xml')]:
            with self.subTest(path=path):
                status, headers, body = self.request(path)
                self.assertEqual(status, 200)
                self.assertIn(mime, headers['Content-Type'])
                self.assertTrue(body)
        self.assertTrue(json.loads(self.request('/patchnotes')[2])['entries'])
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
