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
    assert not post('/join', session='a2')['ok']
    assert not server.ROOMS
    assert post('/match/cancel', session='a2')['ok']
    assert not mm.QUEUE


@pytest.mark.parametrize('mode', ['vs_bot', 'solo'])
def test_queue_practice_preserves_queue_and_is_owned(world, mode):
    post, users = world
    post('/match/join', session='a')
    since = mm.QUEUE['a']['since']
    joined = post('/join', session='a', **{mode: True})
    room = server.ROOMS[joined['room']]
    assert room['queue_practice'] and room['queue_owner'] == 1
    assert not server.is_rated(room)
    assert post('/match/status', session='a2')['state'] == 'waiting'
    assert mm.QUEUE['a2']['since'] == since
    assert server.active_account_room(1)[0] == joined['room']
    assert post('/join', session='a2', resume=True, room=joined['room'])['token'] == joined['token']
    assert not post('/join', session='a2', vs_bot=True)['ok']
    assert not post('/practice/leave', session='b', room=joined['room'])['ok']
    assert post('/practice/leave', session='a2', room=joined['room'])['ok']
    assert not server.ROOMS
    assert post('/match/status', session='a2')['state'] == 'waiting'


@pytest.mark.parametrize('mode', ['vs_bot', 'solo'])
def test_both_accept_atomically_replaces_only_owned_practice(world, mode, monkeypatch):
    post, users = world
    post('/match/join', session='a')
    warmup = post('/join', session='a', **{mode: True})
    unrelated = post('/join', session='x', vs_bot=True)
    old_room = server.ROOMS[warmup['room']]
    job = old_room['_bot_job'] = {'state': old_room['state'], 'turn': 0, 'color': 'B'}
    monkeypatch.setattr(server.accounts, 'settle_game', lambda *a, **k: pytest.fail('practice must not settle'))
    assert post('/match/join', session='b')['state'] == 'found'
    assert post('/match/accept', session='a')['state'] == 'found'
    assert warmup['room'] in server.ROOMS
    assert post('/match/status', session='a')['accepted']
    matched = post('/match/accept', session='b')
    assert matched['state'] == 'matched'
    assert warmup['room'] not in server.ROOMS
    assert unrelated['room'] in server.ROOMS
    assert not server.bot_job_current(old_room, job)
    assert '_bot_job' not in old_room
    assert server.ROOMS[matched['room']]['match']
    assert post('/match/status', session='a')['room'] == matched['room']
    assert post('/match/accept', session='a')['room'] == matched['room']
    # Cancel racing after the other player accepted must return the committed room.
    assert post('/match/cancel', session='a')['room'] == matched['room']
    assert len(server.ROOMS) == 2


@pytest.mark.parametrize('outcome', ['cancel', 'decline', 'timeout'])
def test_decline_and_timeout_keep_practice(world, outcome):
    post, users = world
    post('/match/join', session='a')
    warmup = post('/join', session='a', vs_bot=True)
    room = server.ROOMS[warmup['room']]
    before = copy.deepcopy(room['state'])
    post('/match/join', session='b')
    if outcome == 'timeout':
        for e in mm.QUEUE.values(): e['pending']['deadline'] = time.time() - 1
        assert post('/match/status', session='a')['state'] == 'idle'
    else:
        assert post('/match/'+outcome, session='a')['state'] == 'idle'
        assert post('/match/status', session='b')['state'] == 'waiting'
    assert room['state'] == before and server.ROOMS[warmup['room']] is room
    assert not server.is_rated(room)


def test_other_decline_returns_accepted_player_to_waiting_with_practice(world):
    post, _ = world
    post('/match/join', session='a')
    warmup = post('/join', session='a', solo=True)
    post('/match/join', session='b')
    post('/match/accept', session='a')
    post('/match/decline', session='b')
    assert post('/match/status', session='a')['state'] == 'waiting'
    assert warmup['room'] in server.ROOMS


def test_practice_win_and_rematch_never_record_rating_or_history(world, monkeypatch):
    post, _ = world
    post('/match/join', session='a')
    joined = post('/join', session='a', vs_bot=True)
    room = server.ROOMS[joined['room']]
    post('/match/cancel', session='a')
    monkeypatch.setattr(server.accounts, 'settle_game', lambda *a, **k: pytest.fail('practice must not settle'))
    room['state'].update(phase='over', winner=joined['color'])
    assert server.settle_rating(room)
    assert room['rating_result'] == {}
    assert server.start_rematch(room)
    assert room['queue_practice'] and not server.is_rated(room)
    assert post('/match/join', session='a')['state'] == 'waiting'


def test_normal_bot_game_remains_rated_and_blocks_queue(world):
    post, _ = world
    joined = post('/join', session='a', vs_bot=True, queue_practice=True)
    room = server.ROOMS[joined['room']]
    assert not room.get('queue_practice') and server.is_rated(room)
    assert not post('/match/join', session='a')['ok']
    assert not post('/practice/leave', session='a', room=joined['room'])['ok']


def test_cannot_begin_practice_after_match_found(world):
    post, _ = world
    post('/match/join', session='a')
    post('/match/join', session='b')
    assert not post('/join', session='a', solo=True)['ok']
    assert not post('/join', session='a', vs_bot=True)['ok']
    assert not server.ROOMS


def test_expired_or_cancelled_queue_cannot_silently_start_rated_bot(world):
    post, _ = world
    post('/match/join', session='a')
    post('/match/cancel', session='a')
    assert not post('/join', session='a', vs_bot=True, queuePractice=True)['ok']
    assert not server.ROOMS


def test_expired_accept_does_not_interrupt_practice(world):
    post, _ = world
    post('/match/join', session='a')
    warmup = post('/join', session='a', solo=True)
    post('/match/join', session='b')
    post('/match/accept', session='b')
    for entry in mm.QUEUE.values(): entry['pending']['deadline'] = time.time() - 1
    assert post('/match/accept', session='a')['state'] == 'idle'
    assert list(server.ROOMS) == [warmup['room']]


def test_open_lobby_still_accepts_second_player(world):
    post, users = world
    one = post('/join', session='a')
    two = post('/join', room=one['room'], session='b')
    assert {one['color'], two['color']} == {'W', 'B'}
    assert not post('/match/join', session='a2')['ok']
