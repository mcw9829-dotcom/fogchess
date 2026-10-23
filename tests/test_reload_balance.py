"""Real-turn reload rules and information boundaries; no production data."""
import copy
import json
import threading
import time
from urllib.request import Request, urlopen

import pytest
import bot
import pieces
import server
import spectator
from test_fogchess import bare, put, clean_terrain, _set_terrain


def position(kind, side='W'):
    st = bare()
    st.update(turn=side, turnCount=0 if side == 'W' else 7)
    enemy = 'B' if side == 'W' else 'W'
    pid = side+'_'+kind+'1'
    put(st, pid, side, kind, 5, 5)
    put(st, enemy+'_N1', enemy, 'N', 5, 6)
    put(st, enemy+'_R1', enemy, 'R', 6, 5)
    return st, pid, enemy


def test_knight_vision_radius_two_preserves_king_and_los():
    st = bare()
    put(st, 'W_N1', 'W', 'N', 5, 5)
    assert pieces.visible_cells(st, 'W') == {(r, c) for r in range(3, 8) for c in range(3, 8)}
    _set_terrain(forests={(5, 6)})
    assert (5, 7) not in pieces.visible_cells(st, 'W')
    _set_terrain()
    st['pieces']['W_N1']['alive'] = False
    put(st, 'W_K1', 'W', 'K', 5, 5)
    assert len(pieces.visible_cells(st, 'W')) == 49


@pytest.mark.parametrize('side', ['W', 'B'])
@pytest.mark.parametrize('kind,shoot,targets', [('B', pieces.apply_fire, pieces.fire_cells), ('R', pieces.apply_barrage, pieces.barrage_reach)])
@pytest.mark.parametrize('reload_action', ['move', 'other_piece', 'timeout'])
def test_reload_blocks_exactly_next_own_turn(side, kind, shoot, targets, reload_action):
    st, pid, enemy = position(kind, side)
    n = st['turnCount']
    assert shoot(st, side, pid, 5, 6)[0]
    assert st['turnCount'] == n+1 and st['turn'] == enemy
    assert pieces.is_reloading(st, pid)
    pieces.advance_turn(st)
    assert st['turn'] == side and st['turnCount'] == n+2
    before = copy.deepcopy(st)
    ok, message = shoot(st, side, pid, 6, 5)
    assert not ok and '재장전' in message and st == before
    assert targets(st, pid) == [] and pieces.move_candidates(st, pid)
    assert pieces.player_view(st, side)['reloading'] == [{'pid': pid, 'type': kind, 'remaining': 1}]
    if reload_action == 'move':
        dest = (4, 4) if kind == 'B' else (4, 5)
        assert pieces.apply_move(st, side, pid, *dest)[0]
    elif reload_action == 'other_piece':
        put(st, side+'_P1', side, 'P', 9, 9)
        assert pieces.apply_move(st, side, side+'_P1', 9, 10)[0]
    else:
        assert pieces.time_out(st)
    pieces.advance_turn(st)
    assert st['turnCount'] == n+4 and st['turn'] == side
    assert not pieces.is_reloading(st, pid)
    # A fresh adjacent target is visible even after the reloading piece moved.
    p = st['pieces'][pid]
    put(st, enemy+'_P1', enemy, 'P', p['r'], p['c']+1)
    assert shoot(st, side, pid, p['r'], p['c']+1)[0]


def test_invalid_shot_does_not_reload_and_empty_rook_shot_does():
    st, pid, _ = position('B')
    assert not pieces.apply_fire(st, 'W', pid, 0, 0)[0]
    assert not pieces.is_reloading(st, pid)
    st, pid, _ = position('R')
    assert not pieces.apply_barrage(st, 'W', pid, 4, 4)[0]
    assert not pieces.is_reloading(st, pid)
    assert pieces.apply_barrage(st, 'W', pid, 5, 4)[0]
    assert pieces.is_reloading(st, pid)


@pytest.mark.parametrize('kind', ['B', 'R'])
def test_cooldown_is_per_piece_and_not_leaked_to_opponent(kind):
    st, pid, enemy = position(kind)
    st['pieces'][pid]['reload_until'] = 3
    second = 'W_'+kind+'2'
    put(st, second, 'W', kind, 7, 7)
    assert not pieces.is_reloading(st, second)
    assert pieces.player_view(st, enemy)['reloading'] == []
    for row in pieces.player_view(st, enemy)['grid']:
        for cell in row:
            if cell['p']: assert 'reload_until' not in cell['p']
    clone = bot._clone(st)
    assert pieces.is_reloading(clone, pid)
    clone['pieces'][pid]['reload_until'] = 0
    assert pieces.is_reloading(st, pid)


def test_bot_does_not_choose_reloading_shots():
    st = bare()
    put(st, 'W_B1', 'W', 'B', 5, 5)['reload_until'] = 3
    put(st, 'W_R1', 'W', 'R', 6, 5)['reload_until'] = 3
    put(st, 'B_N1', 'B', 'N', 5, 6)
    put(st, 'B_K1', 'B', 'K', 6, 8)
    candidates = bot._attack_candidates(st, 'W', [(5, 6, 'N'), (6, 8, 'K')])
    assert all(candidate[1] not in ('fire', 'barrage') for candidate in candidates)
    assert bot._barrage_flush(st, 'W', [(6, 8, 99)]) is None
    for choose in (bot.choose_action_easy, bot.choose_action, bot.choose_action_hard):
        result = choose(copy.deepcopy(st), 'W', budget=.02)
        assert result is None or result[0] not in ('fire', 'barrage')


def test_api_blocks_reload_and_replay_preserves_owner_status(monkeypatch):
    monkeypatch.setattr(server, 'ROOMS', {})
    room = server.new_room('RELOAD')
    room['terrain'] = dict(seed=0, forests=set(), bushes=set(), rivers=set(), impassable=set())
    room.update(tokens={'white':'W', 'black':'B'}, seats={'W':'white', 'B':'black'},
                seen={'white':time.time(), 'black':time.time()})
    st, pid, _ = position('B')
    room['state'] = st
    server.ROOMS['RELOAD'] = room
    assert pieces.apply_fire(st, 'W', pid, 5, 6)[0]
    pieces.advance_turn(st)
    http = server.ThreadingServer(('127.0.0.1', 0), server.Handler)
    thread = threading.Thread(target=http.serve_forever, daemon=True)
    thread.start()
    base = 'http://127.0.0.1:%d' % http.server_port
    try:
        with urlopen(base+'/moves?room=RELOAD&token=white&pid='+pid) as response:
            moves = json.load(response)
        assert moves['reloading'] and not moves['canFire'] and moves['fireCells'] == [] and moves['moves']
        before = copy.deepcopy(st)
        payload = dict(room='RELOAD', token='white', type='fire', pid=pid, r=6, c=5)
        with urlopen(Request(base+'/action', data=json.dumps(payload).encode(), headers={'Content-Type':'application/json'})) as response:
            rejected = json.load(response)
        assert not rejected['ok'] and '재장전' in rejected['msg']
        assert st['turnCount'] == before['turnCount'] and st['pieces'] == before['pieces']
        spectator.capture(room)
        frame = room['_replay']['data']['frames'][-1]
        assert frame['perspectives']['W']['reloading'][0]['pid'] == pid
        assert frame['perspectives']['B']['reloading'] == []
        assert frame['view']['reloading'] == []
    finally:
        http.shutdown()
        http.server_close()
        thread.join()
