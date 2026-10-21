import copy
import json
import threading
import time
from urllib.request import Request, urlopen
from urllib.error import HTTPError

import pytest
import server
import spectator


@pytest.fixture
def room(monkeypatch):
    monkeypatch.setattr(server, 'ROOMS', {})
    r = server.new_room('WATCHQA')
    r['tokens'] = {'white': 'W', 'black': 'B', 'watcher': 'spectator'}
    r['seats'] = {'W': 'white', 'B': 'black'}
    r['seen'] = dict.fromkeys(r['tokens'], time.time())
    r['names'] = {'W': 'White', 'B': 'Black'}
    server.ROOMS[r['code']] = r
    server.use_terrain(r)
    return r


def test_delay_boundary_and_no_live_metadata(room):
    spectator.capture(room, 1000)
    room['names']['B'] = 'FUTURE NAME'
    room['state']['phase'] = 'over'
    room['state']['winner'] = 'W'
    spectator.capture(room, 1050)
    wait = spectator.view(room, 1179.99)
    assert wait['spectatorWaiting']
    assert wait['names'] == {} and not wait['feed']
    assert all(c['p'] is None and c['f'] == 1 for row in wait['grid'] for c in row)
    view = spectator.view(room, 1180)
    assert not view['spectatorWaiting'] and view['phase'] == 'setup'
    assert view['names']['B'] == 'Black'
    assert all(c['f'] == 0 for row in view['grid'] for c in row)
    assert all('id' not in c['p'] for row in view['grid'] for c in row if c['p'])
    assert spectator.view(room, 1229)['winner'] is None
    assert spectator.view(room, 1230)['winner'] == 'W'


def test_live_presence_expiry_and_clock(room):
    room['seen']['watcher'] = 1180
    st = room['state']
    st.update(phase='play', turn_deadline=1030, started_at=1000)
    spectator.capture(room, 1000)
    assert spectator.view(room, 1181)['spectatorCount'] == 1
    assert spectator.view(room, 1181)['turnSecondsLeft'] == 29
    assert spectator.view(room, 1190)['spectatorCount'] == 0
    assert spectator.view(room, 1181)['elapsed'] == 1


def test_rematch_retains_old_map_and_finished_board(room):
    room['state'].update(phase='over', winner='B')
    spectator.capture(room, 1000)
    old_grid = spectator.view(room, 1180)['grid']
    room['state'] = server.new_game()
    room['terrain'] = server.game_map.generate_terrain(9876)
    server.use_terrain(room)
    spectator.capture(room, 1060)
    v = spectator.view(room, 1210)
    assert v['phase'] == 'over' and v['grid'] == old_grid
    assert spectator.view(room, 1240)['phase'] == 'setup'


def test_history_and_captures_are_delayed_and_copy_safe(room):
    spectator.capture(room, 1000)
    room['state']['move_history'] = {'W': ['1. move'], 'B': ['2. scan']}
    room['state']['captured'] = {'W': ['P', 'N'], 'B': ['R']}
    spectator.capture(room, 1020)
    assert spectator.view(room, 1199)['moveHistory'] == []
    v = spectator.view(room, 1200)
    assert v['moveHistory'] == ['백 1. move', '흑 2. scan']
    v['capturedBy']['W'].clear()
    assert spectator.view(room, 1200)['capturedBy']['W'] == ['P', 'N']


def test_timeline_pruning_preserves_cutoff(room):
    for at in range(1000, 1500):
        room['state']['turnCount'] = at
        spectator.capture(room, at)
    assert len(room['_broadcast']) <= 181
    assert spectator.view(room, 1499)['turnCount'] == 1319


def test_http_explicit_watch_never_takes_seat_or_mutates(room):
    room['seats']['B'] = None
    httpd = server.ThreadingServer(('127.0.0.1', 0), server.Handler)
    t = threading.Thread(target=httpd.serve_forever, daemon=True)
    t.start()
    def req(path, body=None):
        with urlopen(Request(f'http://127.0.0.1:{httpd.server_port}'+path,
                             data=json.dumps(body).encode() if body is not None else None,
                             headers={'Content-Type': 'application/json'})) as r:
            return json.load(r)
    try:
        assert not req('/watch/join', {'room': 'MISSING'})['ok']
        assert 'MISSING' not in server.ROOMS
        joined = req('/watch/join', {'room': ' watchqa '})
        assert joined['color'] == 'spectator'
        assert room['seats']['B'] is None
        token = joined['token']
        assert req('/watch/join', {'room': 'WATCHQA', 'token': token})['token'] == token
        assert req(f'/state?room=WATCHQA&token={token}')['spectatorWaiting']
        before = copy.deepcopy(room['state'])
        for action in ('move', 'scan', 'ready', 'resign', 'rematch', 'autoplace'):
            assert not req('/action', {'room': 'WATCHQA', 'token': token, 'type': action})['ok']
        assert before == room['state']
        with pytest.raises(HTTPError) as exc:
            req('/state?room=WATCHQA&token=unknown')
        assert exc.value.code == 403
        assert req('/state?room=WATCHQA&token=white')['spectatorCount'] >= 1
        assert req('/watch/leave', {'room': 'WATCHQA', 'token': token})['ok']
        assert token not in room['tokens']
    finally:
        httpd.shutdown()
        httpd.server_close()
        t.join(2)
