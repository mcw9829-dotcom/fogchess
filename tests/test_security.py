"""Security boundaries over real HTTP, using only isolated databases and rooms."""
import copy
from concurrent.futures import ThreadPoolExecutor
from email.message import Message
import http.client
import json
import subprocess
import sys
import threading
import time
from urllib.parse import urlencode

import pytest
import accounts
import security
import server
import spectator
import web_server


def test_budgets_are_atomic_persistent_and_expire():
    rule = [('login-name', 'example', 3, 60)]
    with ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(lambda _: security.consume(rule, 1000), range(12)))
    assert results.count(0) == 3
    assert results.count(60) == 9
    check = subprocess.run([sys.executable, '-c',
        "import security; print(security.consume([('login-name','example',3,60)], 1010))"],
        capture_output=True, text=True, check=True)
    assert check.stdout.strip() == '50'  # A fresh process cannot reset a blocked budget.
    assert security.consume(rule, 1059) == 1
    assert security.consume(rule, 1060) == 0


def test_account_budget_is_shared_across_ips_and_denial_does_not_extend_it():
    for i in range(12):
        assert security.consume(security.request_rules('/login', {'name':' User '}, str(i)), 1000) == 0
    assert security.consume(security.request_rules('/login', {'name':'user'}, 'new-ip'), 1001) == 299
    assert security.consume(security.request_rules('/login', {'name':'user'}, 'new-ip'), 1299) == 1
    assert security.consume(security.request_rules('/login', {'name':'user'}, 'new-ip'), 1300) == 0


def test_database_capacity_and_expired_cleanup(monkeypatch):
    monkeypatch.setattr(security, 'MAX_BUCKETS', 2)
    for name in ('a', 'b'):
        assert security.consume([('test', name, 10, 10)], 1000) == 0
    assert security.consume([('test', 'c', 10, 10)], 1001) == 60
    assert security.consume([('test', 'a', 10, 10)], 1001) == 0
    assert security.consume([('test', 'c', 10, 10)], 1010) == 0


def test_admin_failures_survive_restart_and_unicode_is_rejected(monkeypatch):
    monkeypatch.setenv('FOG_ADMIN_KEY', 'Admin-Test-Key')
    assert not server.admin_ok('다른 키')
    for _ in range(5):
        assert server.admin_gate('client', 'wrong', 1000) == 'forbidden'
    check = subprocess.run([sys.executable, '-c',
        "import server; print(server.admin_gate('client','Admin-Test-Key',1001))"],
        capture_output=True, text=True, check=True)
    assert check.stdout.strip() == 'locked'
    assert server.admin_gate('other-client', 'Admin-Test-Key', 1001) == 'ok'
    assert server.admin_gate('client', 'Admin-Test-Key', 1600) == 'ok'


def test_proxy_identity_is_opt_in_and_ignores_spoofed_headers(monkeypatch):
    headers = Message()
    headers['X-Forwarded-For'] = '203.0.113.55'
    headers['Fly-Client-IP'] = '203.0.113.9'
    assert security.client_ip('127.0.0.1', headers) == '127.0.0.1'
    monkeypatch.setenv('FOG_TRUSTED_PROXY_CIDRS', '172.19.21.249/32')
    assert security.client_ip('198.51.100.1', headers) == '198.51.100.1'
    assert security.client_ip('172.19.21.249', headers) == '203.0.113.9'
    headers['Fly-Client-IP'] = '203.0.113.10'
    assert security.client_ip('172.19.21.249', headers) == '172.19.21.249'
    del headers['Fly-Client-IP']
    headers['Fly-Client-IP'] = 'not-an-ip'
    assert security.client_ip('172.19.21.249', headers) == '172.19.21.249'


def test_fly_trust_is_only_current_gateway(monkeypatch):
    monkeypatch.setenv('FOG_TRUST_FLY_PROXY', '1')
    monkeypatch.setenv('FLY_APP_NAME', 'fogchess')
    monkeypatch.setattr(security, 'fly_gateway', lambda: '172.19.21.249')
    headers = {'Fly-Client-IP':'203.0.113.9'}
    assert security.client_ip('172.19.21.249', headers) == '203.0.113.9'
    assert security.client_ip('172.19.21.250', headers) == '172.19.21.250'


@pytest.fixture
def http_world(monkeypatch, tmp_path):
    monkeypatch.setenv('FOG_ADMIN_KEY', 'Admin-Test-Key')
    monkeypatch.setattr(server, 'ROOMS', {})
    monkeypatch.setattr(accounts, 'DB_PATH', str(tmp_path/'users.db'))
    monkeypatch.setattr(accounts, '_ready', False)
    accounts.init_db()
    httpd = server.ThreadingServer(('127.0.0.1', 0), web_server.WebHandler)
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    def request(path, body=None, headers=None, raw=None):
        conn = http.client.HTTPConnection('127.0.0.1', httpd.server_port, timeout=5)
        payload = json.dumps(body) if body is not None else raw
        conn.request('POST' if payload is not None else 'GET', path, payload, headers or {})
        response = conn.getresponse()
        result = response.status, dict(response.getheaders()), json.loads(response.read())
        conn.close()
        return result
    yield request
    httpd.shutdown(); httpd.server_close(); thread.join()


def test_only_header_admin_authentication_works(http_world):
    req = http_world
    assert req('/admin/check?key=Admin-Test-Key')[0] == 403
    assert req('/feedback/delete', {'key':'Admin-Test-Key', 'id':1})[0] == 403
    status, headers, body = req('/admin/check', headers={'X-Admin-Key':'Admin-Test-Key'})
    assert status == 200 and body['ok']
    assert headers['Cache-Control'] == 'no-store'
    assert headers['Referrer-Policy'] == 'no-referrer'


@pytest.mark.parametrize('path', ['/signup','/login','/recover/code','/join','/watch/join','/match/join','/feedback','/account/pw','/account/recovery'])
def test_http_rate_limit_blocks_work_and_reports_retry(http_world, path):
    rules = security.request_rules(path, {'name':'Tester'}, '127.0.0.1')
    now = time.time()
    for _ in range(min(item[2] for item in rules)):
        assert security.consume(rules, now) == 0
    status, headers, body = http_world(path, {'name':'Tester'}, headers={'X-Forwarded-For':'203.0.113.9', 'Fly-Client-IP':'203.0.113.9'})
    assert status == 429 and body['error'] == 'rate_limited'
    assert int(headers['Retry-After']) > 0
    assert not server.ROOMS and accounts.user_count() == 0


def test_bad_body_cannot_create_rooms_or_hang(http_world):
    for body in ('not-json', '[]'):
        assert http_world('/join', raw=body)[0] == 400
    assert http_world('/join', raw='', headers={'Content-Length':'-1'})[0] == 400
    assert http_world('/join', raw='', headers={'Transfer-Encoding':'chunked'})[0] == 400
    assert not server.ROOMS


def test_normal_account_and_room_flow_is_unchanged(http_world):
    req = http_world
    status, _, result = req('/signup', {'name':'Tester','pw':'Secure-Test-492!'})
    assert status == 200 and result['ok']
    session = result['session']
    assert req('/login', {'name':'Tester','pw':'Secure-Test-492!'})[2]['ok']
    assert req('/me', {'session':session})[2]['user']['name'] == 'Tester'
    first = req('/join', {'name':'Tester','session':session})[2]
    second = req('/join', {'room':first['room'],'name':'Guest'})[2]
    assert {first['color'], second['color']} == {'W','B'}
    assert req('/state?'+urlencode({'room':first['room'],'token':first['token']}))[0] == 200


def fog_room():
    room = server.new_room('FOGTEST')
    room['terrain'].update(forests=set(), rivers=set(), bushes={(8,9)})
    server.use_terrain(room)
    st = room['state']
    for p in st['pieces'].values():
        p['alive'] = False
    for pid, r, c in [('W_K1',11,11),('W_N1',9,9),('B_K1',0,0),('B_Q1',1,1),('B_P1',8,9)]:
        st['pieces'][pid].update(alive=True,r=r,c=c)
    st.update(phase='play',turn='W',turn_deadline=None)
    room['seats'] = {'W':'white-token','B':'black-token'}
    room['tokens'] = {'white-token':'W','black-token':'B','watch-token':'spectator'}
    room['seen'] = dict.fromkeys(room['tokens'], time.time())
    server.ROOMS[room['code']] = room
    return room


def test_http_fog_does_not_disclose_hidden_pieces_or_internal_state(http_world):
    room = fog_room()
    query = urlencode({'room':room['code'],'token':'white-token','reveal':'1'})
    status, _, view = http_world('/state?'+query)
    assert status == 200
    for r,c in [(0,0),(1,1),(8,9)]:
        assert view['grid'][r][c]['p'] is None
    assert view['grid'][9][9]['p']['id'] == 'W_N1'
    serialized = json.dumps(view)
    for hidden in ['B_Q1','B_K1','B_P1','black-token','white-token','watch-token','_broadcast','_replay','"pieces"','"notation"']:
        assert hidden not in serialized
    for pid in ('B_Q1','B_P1'):
        hints = http_world('/moves?'+query+'&pid='+pid)[2]
        assert hints['moves'] == [] and not hints['canFire'] and hints['scanCells'] == []
    assert view['replayId'] is None


def test_http_spectator_and_replay_cannot_bypass_live_fog(http_world):
    room = fog_room()
    now = time.time()
    spectator.capture(room, now)
    replay_id = room['_replay']['data']['id']
    for token in ('watch-token','white-token','black-token','unknown'):
        assert not http_world('/replay?'+urlencode({'id':replay_id,'token':token}))[2]['ok']
    query = urlencode({'room':room['code'],'token':'watch-token','reveal':'1'})
    view = http_world('/state?'+query)[2]
    assert view['spectatorWaiting']
    assert all(cell['p'] is None for row in view['grid'] for cell in row)
    assert view['feed'] == [] and view['moveHistory'] == []
    # Once a delayed frame is eligible, it must still show the OLD board.
    room['_broadcast'][0] = (now - spectator.DELAY - 1, room['_broadcast'][0][1])
    room['state']['pieces']['B_Q1'].update(r=2,c=2)
    spectator.capture(room, time.time())
    view = http_world('/state?'+query)[2]
    assert not view['spectatorWaiting']
    assert view['grid'][1][1]['p']['t'] == 'Q'
    assert view['grid'][2][2]['p'] is None
    assert all('id' not in cell['p'] for row in view['grid'] for cell in row if cell['p'])


def test_foreign_and_spectator_tokens_cannot_act(http_world):
    room = fog_room()
    before = copy.deepcopy(room['state']['pieces'])
    for token in ('unknown','watch-token','black-token',server.BOT_TOKEN):
        result = http_world('/action', {'room':room['code'],'token':token,'type':'move','pid':'W_N1','r':7,'c':8})
        assert result[0] == 403 or result[2]['ok'] is False
        assert room['state']['pieces'] == before
    # The same request with the owning seat credential must actually work.
    own = {'room':room['code'],'token':'white-token','type':'move','pid':'W_N1','r':7,'c':8}
    assert http_world('/action', own)[2]['ok']
    moved = copy.deepcopy(room['state'])
    assert not http_world('/action', own)[2]['ok']
    assert room['state']['pieces'] == moved['pieces']
    assert room['state']['turnCount'] == moved['turnCount']


def test_hidden_occupancy_does_not_change_move_hints(http_world):
    room = fog_room()
    query = urlencode({'room':room['code'],'token':'white-token','pid':'W_N1'})
    before = http_world('/moves?'+query)[2]
    room['terrain']['bushes'].add((7,8))
    room['state']['pieces']['B_P1'].update(r=7,c=8)
    assert http_world('/moves?'+query)[2] == before
    view = http_world('/state?'+urlencode({'room':room['code'],'token':'white-token'}))[2]
    assert view['grid'][7][8]['p'] is None


def test_rate_storage_failure_fails_closed_without_mutation(http_world, monkeypatch):
    def unavailable(*args):
        raise security.sqlite3.OperationalError('fixture unavailable')
    monkeypatch.setattr(security, 'consume', unavailable)
    assert http_world('/join', {})[0] == 503
    assert not server.ROOMS
    assert http_world('/admin/check', headers={'X-Admin-Key':'Admin-Test-Key'})[0] == 503
