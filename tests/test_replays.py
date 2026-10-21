import copy
import json
import threading
import time
from urllib.request import Request, urlopen
import pytest
import server
import spectator
import replays


@pytest.fixture(autouse=True)
def isolated_store(tmp_path, monkeypatch):
    monkeypatch.setenv('FOG_REPLAY_DB', str(tmp_path/'replays.sqlite3'))
    monkeypatch.setattr(server, 'ROOMS', {})


def room():
    r = server.new_room('REPLAY')
    r['tokens'] = {'player': 'W', 'watch': 'spectator'}
    r['seats'] = {'W': 'player', 'B': None}
    r['names'] = {'W': 'White', 'B': 'Black'}
    server.use_terrain(r)
    return r


def end(r, now=1020):
    r['state'].update(phase='over', winner='W')
    spectator.capture(r, now)
    return r['_replay']['data']['id']


def test_save_only_on_end_and_exact_frames():
    r = room()
    r['state']['phase'] = 'play'
    spectator.capture(r, 1000)
    replay_id = r['_replay']['data']['id']
    assert not replays.load(replay_id, 'player', '', 1001)['ok']
    initial = copy.deepcopy(r['_replay']['data']['frames'][0])
    r['state']['pieces']['W_P1']['r'] = 5
    r['state']['turnCount'] += 1
    r['state']['notation'] = [{'actor':'W', 'action':'move', 'pid':'W_P1', 'to':[5,0]}]
    spectator.capture(r, 1010)
    assert r['_replay']['data']['frames'][0] == initial
    assert end(r) == replay_id
    result = replays.load(replay_id, 'player', '', 1020)['replay']
    assert len(result['frames']) == 3
    assert result['frames'][1]['action']['action'] == 'move'
    assert result['frames'][0]['view']['grid'] != result['frames'][1]['view']['grid']
    assert result['frames'][-1]['view']['winner'] == 'W'


def test_replay_survives_room_removal_and_is_immutable():
    r = room()
    spectator.capture(r, 1000)
    replay_id = end(r)
    saved = replays.load(replay_id, 'player', '', 1020)
    r.clear()
    assert replays.load(replay_id, 'player', '', 1020) == saved


def test_spectator_cannot_bypass_delay():
    r = room()
    replay_id = end(r)
    assert not replays.load(replay_id, 'watch', '', 1199.99)['ok']
    assert not replays.load(replay_id, '', '', 1199.99)['ok']
    assert replays.load(replay_id, '', '', 1200)['ok']
    assert replays.load(replay_id, 'player', '', 1020)['ok']


def test_rematch_gets_distinct_record():
    r = room()
    first = end(r)
    r['state'] = server.new_game()
    spectator.capture(r, 1040)
    second = end(r, 1060)
    assert first != second
    assert replays.load(first, 'player', '', 1060)['ok']
    assert replays.load(second, 'player', '', 1060)['ok']


def test_promotion_timeout_and_metadata_dedup():
    r = room()
    r['state']['phase'] = 'play'
    spectator.capture(r, 1000)
    r['ratings']['W'] = 1500
    spectator.capture(r, 1001)
    assert len(r['_replay']['data']['frames']) == 1
    r['state']['promote'] = {'pid':'W_P1', 'color':'W'}
    spectator.capture(r, 1002)
    r['state']['promote'] = None
    r['state']['pieces']['W_P1']['t'] = 'R'
    r['state']['misses']['W'] += 1
    r['state']['turnCount'] += 1
    spectator.capture(r, 1003)
    replay_id = end(r)
    data = replays.load(replay_id, 'player', '', 1020)['replay']
    assert len(data['frames']) == 4
    assert '시간 초과' in data['frames'][2]['label']


def test_http_saved_replay_after_room_is_gone():
    r = room()
    replay_id = end(r, time.time())
    httpd = server.ThreadingServer(('127.0.0.1', 0), server.Handler)
    t = threading.Thread(target=httpd.serve_forever, daemon=True)
    t.start()
    try:
        with urlopen(f'http://127.0.0.1:{httpd.server_port}/replay?id={replay_id}&token=player') as response:
            assert json.load(response)['replay']['id'] == replay_id
    finally:
        httpd.shutdown()
        httpd.server_close()
        t.join(2)


def test_saved_game_loads_in_fresh_process():
    import subprocess
    import sys
    r = room()
    replay_id = end(r)
    code = "import replays; print(replays.load(%r, 'player', '', 1020)['replay']['id'])" % replay_id
    result = subprocess.run([sys.executable, '-c', code], capture_output=True, text=True, check=True)
    assert result.stdout.strip() == replay_id


def test_failed_save_can_retry_without_losing_end_frame(monkeypatch):
    import sqlite3
    r = room()
    spectator.capture(r, 1000)
    original = replays.save
    def fail(_room):
        raise sqlite3.OperationalError('test write failure')
    monkeypatch.setattr(replays, 'save', fail)
    with pytest.raises(sqlite3.OperationalError):
        end(r)
    monkeypatch.setattr(replays, 'save', original)
    spectator.capture(r, 1021)
    assert r['_replay']['saved']
    assert spectator.view(r, 1201)['phase'] == 'over'


def test_perspectives_preserve_actual_fog_and_brush_rules():
    import pieces
    r = room()
    st = r['state']
    st['phase'] = 'play'
    for piece in st['pieces'].values(): piece['alive'] = False
    st['pieces']['W_K1'].update(alive=True, r=8, c=8)
    st['pieces']['B_K1'].update(alive=True, r=0, c=0)
    st['pieces']['W_P1'].update(alive=True, r=5, c=5)
    st['pieces']['B_P1'].update(alive=True, r=5, c=7)
    r['terrain'] = {'seed':0, 'forests':set(), 'rivers':set(), 'bushes':{(5,5),(5,6),(5,7),(4,8)}, 'impassable':set()}
    server.use_terrain(r)
    assert pieces.bush_cluster(5,5) == {(5,5),(5,6),(5,7)}
    expected = {side: copy.deepcopy(pieces.player_view(st,side)) for side in ('W','B')}
    spectator.capture(r,1000)
    replay_id = end(r)
    frame = replays.load(replay_id,'player','',1020)['replay']['frames'][0]
    for side in ('W','B'):
        assert frame['perspectives'][side]['grid'] == expected[side]['grid']
    assert frame['perspectives']['W']['grid'][0][0]['p'] is None
    assert frame['perspectives']['W']['grid'][5][7]['p']['o']=='B'
    assert frame['view']['grid'][0][0]['p']['o']=='B'
