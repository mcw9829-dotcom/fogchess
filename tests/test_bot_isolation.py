"""HTTP authorization and asynchronous AI regression tests (isolated rooms/DB)."""
import copy
import json
import threading
import time
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

import pytest
import server


@pytest.fixture
def http_world(monkeypatch, tmp_path):
    monkeypatch.setattr(server, 'ROOMS', {})
    monkeypatch.setattr(server.accounts, 'user_by_token', lambda _: None)
    monkeypatch.setenv('FOG_REPLAY_DB', str(tmp_path / 'replays.sqlite3'))
    http = server.ThreadingServer(('127.0.0.1', 0), server.Handler)
    thread = threading.Thread(target=http.serve_forever, daemon=True)
    thread.start()

    def request(path, data=None, **query):
        if query:
            path += '?' + urlencode(query)
        req = Request(f'http://127.0.0.1:{http.server_port}{path}',
                      data=json.dumps(data).encode() if data is not None else None,
                      headers={'Content-Type': 'application/json'})
        try:
            response = urlopen(req, timeout=8)
        except HTTPError as error:
            response = error
        with response:
            return response.status, json.load(response)

    yield request
    http.shutdown()
    http.server_close()
    thread.join()


@pytest.mark.parametrize('legacy', [False, True])
def test_internal_bot_seat_cannot_authenticate(http_world, legacy):
    request = http_world
    _, joined = request('/join', {'vs_bot': True, 'level': 'easy'})
    code, token = joined['room'], joined['token']
    room = server.ROOMS[code]
    assert server.BOT_TOKEN not in room['tokens']
    if legacy:
        room['tokens'][server.BOT_TOKEN] = 'B'
    original = copy.deepcopy(room['state'])
    seen = dict(room['seen'])
    for path in ('/state', '/moves'):
        status, result = request(path, room=code, token=server.BOT_TOKEN, pid='B_P1')
        assert status == 403 and result['ok'] is False
        assert 'grid' not in result
    for action in ('resign', 'ready', 'autoplace', 'move', 'fire', 'scan', 'barrage', 'rematch'):
        status, result = request('/action', {'room': code, 'token': server.BOT_TOKEN, 'type': action})
        assert status == 403 and result['ok'] is False
    status, _ = request('/join', {'room': code, 'token': server.BOT_TOKEN})
    assert status == 403
    assert room['state'] == original and room['seen'] == seen
    assert server.effective_color(room, server.BOT_TOKEN) == 'spectator'
    status, view = request('/state', room=code, token=token)
    assert status == 200 and view['yourColor'] == 'W'
    _, reconnect = request('/join', {'room': code, 'token': token})
    assert reconnect['token'] == token and reconnect['color'] == 'W'
    _, observer = request('/watch/join', {'room': code})
    _, view = request('/state', room=code, token=observer['token'])
    assert view['spectator'] and view['spectatorWaiting']


@pytest.mark.parametrize('invalid', [None, '', 'unknown', [], {}])
def test_invalid_action_does_not_refresh_presence(http_world, invalid):
    _, joined = http_world('/join', {'vs_bot': True})
    room = server.ROOMS[joined['room']]
    before = dict(room['seen'])
    status, result = http_world('/action', {'room': joined['room'], 'token': invalid, 'type': 'resign'})
    assert status == 403 and not result['ok']
    assert room['seen'] == before and room['state']['phase'] == 'setup'


class ControlledWorker:
    def __init__(self):
        self.jobs = []
        self.accept = True

    def submit(self, *args):
        if self.accept:
            self.jobs.append(args)
        return self.accept

    def close(self):
        pass


@pytest.fixture
def controlled(monkeypatch):
    worker = ControlledWorker()
    monkeypatch.setattr(server, '_bot_worker', worker)
    return worker


def bot_turn(request):
    _, joined = request('/join', {'vs_bot': True, 'level': 'easy'})
    room = server.ROOMS[joined['room']]
    with server.lock:
        room['terrain'] = {'seed': 1, 'forests': set(), 'rivers': set(), 'bushes': set(), 'impassable': set()}
        room['state'].update(phase='play', turn='B', turn_deadline=time.time() + 30)
        room['state']['pieces'] = server.new_game()['pieces']
        server.use_terrain(room)
        server.schedule_bot(room)
    return joined, room


def decision():
    return {'action': ('move', 'B_P1', 2, 9), 'memory': {'botmem': {'B': {(5, 5): {'t': 'P', 'seen': 0}}}}}


def test_bot_scheduled_once_and_applied_once_with_fresh_clock(http_world, controlled):
    joined, room = bot_turn(http_world)
    for _ in range(3):
        http_world('/state', **joined)
    assert len(controlled.jobs) == 1
    state_copy, terrain_copy, *_ = controlled.jobs[0]
    assert state_copy is not room['state'] and terrain_copy is not room['terrain']
    finish = controlled.jobs[0][-1]
    room['state']['turn_deadline'] = time.time() - 20
    before = time.time()
    finish(decision(), None)
    assert room['state']['turn'] == 'W' and room['state']['turnCount'] == 1
    assert room['state']['turn_deadline'] >= before + server.TURN_SECONDS
    assert room['state']['botmem'] == decision()['memory']['botmem']
    assert room['_replay']['data']['frames'][-1]['action']['actor'] == 'B'
    after = copy.deepcopy(room['state'])
    finish(decision(), None)
    assert room['state'] == after


@pytest.mark.parametrize('invalidate', ['resign', 'rematch', 'deleted', 'turn'])
def test_old_bot_result_cannot_change_a_new_or_finished_game(http_world, controlled, invalidate):
    joined, room = bot_turn(http_world)
    finish = controlled.jobs[0][-1]
    if invalidate == 'resign':
        _, res = http_world('/action', dict(joined, type='resign'))
        assert res['ok']
    elif invalidate == 'rematch':
        _, res = http_world('/action', dict(joined, type='rematch'))
        assert res['ok'] and room['state']['phase'] == 'setup'
    elif invalidate == 'deleted':
        del server.ROOMS[joined['room']]
    else:
        room['state']['turnCount'] += 2
    before = copy.deepcopy(room['state'])
    finish(decision(), None)
    assert room['state'] == before


def test_timeout_queues_bot_without_searching_in_room_lock(http_world, controlled):
    _, joined = http_world('/join', {'vs_bot': True})
    room = server.ROOMS[joined['room']]
    st = room['state']
    st.update(phase='play', turn='W', turn_deadline=time.time() - 1)
    with server.lock:
        server.use_terrain(room)
        server.enforce_clock(room, time.time())
    assert st['turn'] == 'B' and st['misses']['W'] == 1
    assert len(controlled.jobs) == 1


def test_queue_full_and_worker_failure_preserve_turn_and_can_retry(http_world, controlled):
    controlled.accept = False
    joined, room = bot_turn(http_world)
    assert '_bot_job' not in room and room['state']['turn'] == 'B'
    controlled.accept = True
    http_world('/state', **joined)
    assert len(controlled.jobs) == 1
    before = copy.deepcopy(room['state'])
    controlled.jobs[0][-1](None, 'BrokenProcessPool')
    assert room['state'] == before and '_bot_job' not in room
    http_world('/state', **joined)
    assert len(controlled.jobs) == 1  # Failure backoff prevents a tight retry loop.
    room['_bot_retry_at'] = 0
    http_world('/state', **joined)
    assert len(controlled.jobs) == 2


def test_promotion_and_no_legal_action_finish_bot_turn(http_world, controlled):
    joined, room = bot_turn(http_world)
    # Set up a promotion decision as if the preceding move reached the final rank.
    st = room['state']
    st['pieces']['B_P1'].update(r=11, c=0)
    st['promote'] = {'pid': 'B_P1', 'color': 'B'}
    controlled.jobs[0][-1]({'action': ('promote', None, 'R', None), 'memory': {}}, None)
    assert st['pieces']['B_P1']['t'] == 'R' and st['turn'] == 'W'
    st['turn'] = 'B'
    with server.lock:
        server.schedule_bot(room)
    controlled.jobs[-1][-1]({'action': None, 'memory': {}}, None)
    assert st['turn'] == 'W'


def test_real_bot_process_does_not_block_other_room_requests(http_world, monkeypatch):
    # Keep a real subprocess job pending long enough to exercise concurrent HTTP.
    monkeypatch.setattr(server, 'BOT_MIN_THINK', {'hard': 2.0})
    _, joined = http_world('/join', {'vs_bot': True, 'level': 'hard'})
    http_world('/action', dict(joined, type='ready'))
    _, moves = http_world('/moves', **joined, pid='W_P1')
    r, c = moves['moves'][0]
    start = time.monotonic()
    status, moved = http_world('/action', dict(joined, type='move', pid='W_P1', r=r, c=c))
    assert status == 200 and moved['ok'] and time.monotonic() - start < 1.0
    bot_room = server.ROOMS[joined['room']]
    assert bot_room['state']['turn'] == 'B' and '_bot_job' in bot_room
    _, other = http_world('/join', {'solo': True})
    latencies = []
    for _ in range(5):
        start = time.monotonic()
        status, view = http_world('/state', **other)
        latencies.append(time.monotonic() - start)
        assert status == 200 and view['phase'] == 'play'
    _, moves = http_world('/moves', **other, pid='W_P1')
    r, c = moves['moves'][0]
    start = time.monotonic()
    _, moved = http_world('/action', dict(other, type='move', pid='W_P1', r=r, c=c))
    latencies.append(time.monotonic() - start)
    assert moved['ok'] and max(latencies) < 1.0
    print('other-room max request seconds:', round(max(latencies), 4))
    deadline = time.monotonic() + 15
    while bot_room['state']['turn'] == 'B' and time.monotonic() < deadline:
        time.sleep(.05)
    assert bot_room['state']['turnCount'] == 2 and bot_room['state']['turn'] == 'W'
    assert bot_room['state']['turn_deadline'] > time.time() + server.TURN_SECONDS - 1


def test_completed_decision_reinstalls_its_own_terrain(http_world, controlled):
    _, room = bot_turn(http_world)
    other = server.new_room('OTHER')
    other['terrain'] = {'seed': 2, 'forests': set(), 'rivers': set(), 'bushes': {(2, 9)}, 'impassable': {(2, 9)}}
    server.use_terrain(other)
    other_before = copy.deepcopy(other['state'])
    controlled.jobs[0][-1](decision(), None)
    assert room['state']['pieces']['B_P1']['r'] == 2
    assert room['state']['turn'] == 'W' and other['state'] == other_before


def test_duration_contract_in_player_spectator_and_replay(http_world):
    _, joined = http_world('/join', {'vs_bot': True})
    room = server.ROOMS[joined['room']]
    status, view = http_world('/state', **joined)
    assert status == 200
    assert view['setupSeconds'] == server.SETUP_SECONDS == 70
    assert view['turnSeconds'] == server.TURN_SECONDS == 30
    assert 68 <= view['secondsLeft'] <= 70
    at = room['_broadcast'][-1][0]
    delayed = server.spectator.view(room, at + server.spectator.DELAY)
    frame = room['_replay']['data']['frames'][-1]
    for result in (delayed, frame['view'], frame['perspectives']['W'], frame['perspectives']['B']):
        assert result['setupSeconds'] == 70 and result['turnSeconds'] == 30
