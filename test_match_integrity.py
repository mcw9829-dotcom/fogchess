import copy
import json
import threading
import time
from urllib.request import Request, urlopen

import pytest
import matchmaking as mm
import server


@pytest.fixture
def world(monkeypatch):
    monkeypatch.setattr(server, 'ROOMS', {})
    monkeypatch.setattr(mm, 'QUEUE', {})
    users = {'a': {'id': 1, 'name': 'A', 'rating': 1000},
             'a2': {'id': 1, 'name': 'A', 'rating': 1000},
             'b': {'id': 2, 'name': 'B', 'rating': 1000},
             'x': {'id': 3, 'name': 'X', 'rating': 1000}}
    monkeypatch.setattr(server.accounts, 'user_by_token', lambda token: users.get(token))
    http = server.ThreadingServer(('127.0.0.1', 0), server.Handler)
    thread = threading.Thread(target=http.serve_forever, daemon=True)
    thread.start()
    def post(path, **data):
        req = Request('http://127.0.0.1:%d%s' % (http.server_port, path),
                      data=json.dumps(data).encode(), headers={'Content-Type': 'application/json'})
        with urlopen(req, timeout=5) as response:
            return json.load(response)
    yield post, users
    http.shutdown(); http.server_close(); thread.join()


def ranked(users):
    code, ta, ca, tb, cb = server.make_match_room(
        {'uid': 1, 'name': 'A', 'rating': 1000},
        {'uid': 2, 'name': 'B', 'rating': 1000})
    return code, ta, ca


@pytest.mark.parametrize('phase,match', [('setup', True), ('play', True), ('play', False), ('over', False)])
def test_stale_seats_cannot_be_taken(world, phase, match):
    post, users = world
    code, token, color = ranked(users)
    room = server.ROOMS[code]
    room['match'] = match
    room['state']['phase'] = phase
    room['seen'] = dict.fromkeys(room['seen'], 0)
    original = copy.deepcopy((room['seats'], room['users'], room['ratings'], room['names']))
    result = post('/join', room=code, session='x')
    assert result['color'] == 'spectator'
    assert (room['seats'], room['users'], room['ratings'], room['names']) == original
    assert room['tokens'][token] == color


def test_token_reconnect_does_not_change_account(world):
    post, users = world
    code, token, color = ranked(users)
    room = server.ROOMS[code]
    original = copy.deepcopy((room['users'], room['ratings'], room['names']))
    assert post('/join', room=code, token=token)['color'] == color
    assert post('/join', room=code, token=token, session='x')['color'] == color
    assert (room['users'], room['ratings'], room['names']) == original
    assert post('/join', room=code, session='a2')['token'] == token


def test_refreshed_session_keeps_one_waiting_and_pending_entry(world):
    post, users = world
    assert post('/match/join', session='a')['state'] == 'waiting'
    assert post('/match/join', session='a2')['state'] == 'waiting'
    assert len(mm.QUEUE) == 1
    assert post('/match/join', session='b')['state'] == 'found'
    assert post('/match/accept', session='a')['state'] == 'found'
    assert len(mm.QUEUE) == 2
    result = post('/match/accept', session='b')
    assert result['state'] == 'matched'
    assert len(server.ROOMS) == 1


def test_active_room_survives_queue_ttl_and_session_refresh(world):
    post, users = world
    code, token, color = ranked(users)
    mm.QUEUE.clear()
    for endpoint in ('/match/join', '/match/accept', '/match/status'):
        result = post(endpoint, session='a2')
        assert result['state'] == 'matched' and result['room'] == code
        assert result['token'] == token and result['color'] == color
    assert not mm.QUEUE and len(server.ROOMS) == 1
    assert not post('/join', session='a2', vs_bot=True)['ok']


def test_waiting_cannot_start_parallel_game(world):
    post, users = world
    post('/match/join', session='a')
    assert not post('/join', session='a2', vs_bot=True)['ok']
    assert not server.ROOMS
    assert post('/match/cancel', session='a2')['ok']
    assert not mm.QUEUE


def test_open_lobby_still_accepts_second_player(world):
    post, users = world
    one = post('/join', session='a')
    two = post('/join', room=one['room'], session='b')
    assert {one['color'], two['color']} == {'W', 'B'}
    assert not post('/match/join', session='a2')['ok']
