# -*- coding: utf-8 -*-
"""
규칙 엔진 회귀 테스트 (pytest).

실행:  fogchess 폴더에서  ->  python -m pytest -q
지형(FORESTS/BUSHES/RIVERS)은 서버 시작 시 무작위 생성되므로, 각 테스트는
clean_terrain 픽스처로 '빈 지형'에서 시작하고 필요할 때만 지형을 심는다.
"""
import pytest

import config
import game_map
import pieces
import bot

_TERR = ['FORESTS', 'BUSHES', 'RIVERS', 'IMPASSABLE']


def _set_terrain(forests=frozenset(), bushes=frozenset(), rivers=frozenset()):
    """세 모듈(game_map/pieces/bot)의 지형 전역을 동시에 덮어쓴다(임포트가 값 복사라서)."""
    impass = set(forests) | set(rivers)
    vals = {'FORESTS': set(forests), 'BUSHES': set(bushes),
            'RIVERS': set(rivers), 'IMPASSABLE': impass}
    for m in (game_map, pieces, bot):
        for a, v in vals.items():
            if hasattr(m, a):
                setattr(m, a, v)


@pytest.fixture(autouse=True)
def clean_terrain():
    saved = [(m, a, getattr(m, a)) for m in (game_map, pieces, bot)
             for a in _TERR if hasattr(m, a)]
    _set_terrain()                      # 기본: 빈 지형
    yield
    for m, a, v in saved:
        setattr(m, a, v)


def bare():
    """모든 기물을 죽인 play 단계 상태 — 테스트가 필요한 기물만 살려서 놓는다."""
    st = pieces.new_game()
    for p in st['pieces'].values():
        p['alive'] = False
    st['phase'] = 'play'
    return st


def put(st, key, o, t, r, c, moved=True, lives=1):
    st['pieces'][key].update(alive=True, o=o, t=t, r=r, c=c, moved=moved, lives=lives)
    return st['pieces'][key]


# ------------------------- 포진 / 기본 -------------------------
def test_default_composition():
    from collections import Counter
    p = pieces.default_pieces()
    for side in ('W', 'B'):
        types = [v['t'] for v in p.values() if v['o'] == side]
        assert len(types) == 14
        assert Counter(types) == Counter({'P': 7, 'R': 2, 'N': 2, 'B': 2, 'K': 1})
    king = next(v for v in p.values() if v['t'] == 'K')
    assert king['lives'] == config.KING_LIVES


# ------------------------- 폰 -------------------------
def test_pawn_moves_and_no_retreat():
    st = bare()
    p = put(st, 'W_P1', 'W', 'P', 10, 5, moved=False)
    m = set(pieces.legal_moves(st, 'W_P1'))
    assert {(9, 5), (8, 5), (10, 4), (10, 6), (9, 4), (9, 6)} <= m  # 전진1·2, 좌우, 앞대각
    assert (11, 5) not in m                                         # 후퇴 불가
    p['moved'] = True
    assert (8, 5) not in set(pieces.legal_moves(st, 'W_P1'))        # 이동 후 2칸 불가


def test_pawn_forward_blocked_no_capture():
    st = bare()
    put(st, 'W_P1', 'W', 'P', 10, 5, moved=False)
    put(st, 'B_P1', 'B', 'P', 9, 5)
    m = set(pieces.legal_moves(st, 'W_P1'))
    assert (9, 5) not in m and (8, 5) not in m       # 정면 캡처·관통 불가


def test_pawn_diagonal_capture():
    st = bare()
    put(st, 'W_P1', 'W', 'P', 10, 5)
    put(st, 'B_N1', 'B', 'N', 9, 4)
    assert (9, 4) in set(pieces.legal_moves(st, 'W_P1'))


# ------------------------- 나이트 / 킹 -------------------------
def test_knight_moves():
    st = bare()
    put(st, 'W_N1', 'W', 'N', 5, 5)
    assert set(pieces.legal_moves(st, 'W_N1')) == {
        (3, 4), (3, 6), (7, 4), (7, 6), (4, 3), (6, 3), (4, 7), (6, 7)}


def test_knight_blocked_by_own():
    st = bare()
    put(st, 'W_N1', 'W', 'N', 5, 5)
    put(st, 'W_P1', 'W', 'P', 3, 4)
    assert (3, 4) not in set(pieces.legal_moves(st, 'W_N1'))


def test_king_moves():
    st = bare()
    put(st, 'W_K1', 'W', 'K', 5, 5)
    assert len(pieces.legal_moves(st, 'W_K1')) == 8


# ------------------------- 비숍 / 룩 -------------------------
def test_bishop_move_range_and_block():
    st = bare()
    put(st, 'W_B1', 'W', 'B', 5, 5)
    m = set(pieces.legal_moves(st, 'W_B1'))
    assert (4, 4) in m and (3, 3) in m and (2, 2) not in m    # BISHOP_MOVE=2
    put(st, 'B_P1', 'B', 'P', 4, 4)
    m = set(pieces.legal_moves(st, 'W_B1'))
    assert (4, 4) in m and (3, 3) not in m                    # 적 캡처 가능, 너머 막힘


def test_rook_range_and_block():
    st = bare()
    put(st, 'W_R1', 'W', 'R', 5, 5)
    m = set(pieces.legal_moves(st, 'W_R1'))
    assert (5, 8) in m and (2, 5) in m and (5, 9) not in m    # ROOK_RANGE=3
    put(st, 'W_P1', 'W', 'P', 5, 7)
    m = set(pieces.legal_moves(st, 'W_R1'))
    assert (5, 7) not in m and (5, 8) not in m                # 아군 앞 막힘


# ------------------------- 지형: 이동/시야 -------------------------
def test_forest_blocks_move():
    _set_terrain(forests={(9, 5)})
    st = bare()
    put(st, 'W_P1', 'W', 'P', 10, 5, moved=False)
    assert (9, 5) not in set(pieces.legal_moves(st, 'W_P1'))


def test_los_blocked_by_forest():
    _set_terrain(forests={(5, 6)})
    st = bare()
    put(st, 'W_N1', 'W', 'N', 5, 5)                # 시야 2
    vis = pieces.visible_cells(st, 'W')
    assert (5, 4) in vis and (5, 7) not in vis      # 숲 뒤는 가림


# ------------------------- 비숍 곡사 / 전차 돌파 -------------------------
def test_artillery_kills_king_and_wins():
    st = bare()
    put(st, 'W_B1', 'W', 'B', 5, 5)
    k = put(st, 'B_K1', 'B', 'K', 5, 6)
    ok, _ = pieces.apply_fire(st, 'W', 'W_B1', 5, 6)
    assert ok and not k['alive'] and st['phase'] == 'over' and st['winner'] == 'W'


def test_artillery_range_limit():
    st = bare()
    put(st, 'W_B1', 'W', 'B', 0, 0)
    put(st, 'B_P1', 'B', 'P', 11, 11)
    ok, _ = pieces.apply_fire(st, 'W', 'W_B1', 11, 11)
    assert not ok                                   # 사거리 밖


def test_artillery_reveals_attacker():
    st = bare()
    st['turn'] = 'W'
    put(st, 'W_B1', 'W', 'B', 5, 5)
    put(st, 'B_P1', 'B', 'P', 5, 6)
    ok, _ = pieces.apply_fire(st, 'W', 'W_B1', 5, 6)
    assert ok and pieces.revealed(st, 'B', 'W_B1')  # 공격한 비숍이 적에게 노출


def test_barrage_hits_target():
    st = bare()
    put(st, 'W_R1', 'W', 'R', 5, 5)
    put(st, 'B_P1', 'B', 'P', 5, 7)
    ok, _ = pieces.apply_barrage(st, 'W', 'W_R1', 5, 7)
    assert ok and not st['pieces']['B_P1']['alive']


def test_barrage_blocked_by_forest():
    _set_terrain(forests={(5, 6)})
    st = bare()
    put(st, 'W_R1', 'W', 'R', 5, 5)
    put(st, 'B_P1', 'B', 'P', 5, 7)
    ok, _ = pieces.apply_barrage(st, 'W', 'W_R1', 5, 7)
    assert ok and st['pieces']['B_P1']['alive']     # 숲이 막아 생존


# ------------------------- 부쉬 은폐 (회귀 방지: 이 버그를 실제로 겪음) -------------------------
def test_bush_hides_enemy_even_when_adjacent():
    _set_terrain(bushes={(5, 5)})
    st = bare()
    put(st, 'B_P1', 'B', 'P', 5, 5)
    put(st, 'W_N1', 'W', 'N', 5, 6)                 # 백이 부쉬에 인접
    assert (5, 5) in pieces.visible_cells(st, 'W')  # 시야엔 든다
    assert pieces.player_view(st, 'W')['grid'][5][5]['p'] is None   # 그래도 안 보임
    assert pieces.player_view(st, 'B')['grid'][5][5]['p'] is not None            # 주인은 봄
    assert pieces.player_view(st, 'W', reveal=True)['grid'][5][5]['p'] is not None  # 디버그


def test_bush_enemy_visible_when_revealed():
    _set_terrain(bushes={(5, 5)})
    st = bare()
    put(st, 'B_P1', 'B', 'P', 5, 5)
    put(st, 'W_N1', 'W', 'N', 5, 6)
    pieces.add_reveal(st, 'B_P1', 'W', 3)           # 공격 노출됐다고 가정
    assert pieces.player_view(st, 'W')['grid'][5][5]['p'] is not None


def test_fog_hides_distant_enemy():
    st = bare()
    put(st, 'W_N1', 'W', 'N', 0, 0)
    put(st, 'B_P1', 'B', 'P', 11, 11)
    assert pieces.player_view(st, 'W')['grid'][11][11]['p'] is None


# ------------------------- 승패 / 흐름 -------------------------
def test_melee_king_capture_wins():
    st = bare()
    st['turn'] = 'W'
    put(st, 'W_N1', 'W', 'N', 5, 5)
    put(st, 'B_K1', 'B', 'K', 3, 4)
    ok, _ = pieces.apply_move(st, 'W', 'W_N1', 3, 4)
    assert ok and st['phase'] == 'over' and st['winner'] == 'W'


def test_turn_limit_draw():
    st = pieces.new_game()
    st['phase'] = 'play'
    st['turnCount'] = config.TURN_LIMIT - 1
    pieces.advance_turn(st)
    assert st['phase'] == 'over' and st['winner'] == 'draw'


def test_place_rules():
    st = pieces.new_game()                          # setup 단계
    assert pieces.apply_place(st, 'W', 'W_P1', 9, 5)[0]        # 자기 진영 OK
    assert not pieces.apply_place(st, 'W', 'W_P1', 5, 5)[0]    # 진영 밖 불가
    _set_terrain(forests={(10, 4)})
    assert not pieces.apply_place(st, 'W', 'W_P1', 10, 4)[0]   # 숲 위 불가


# ------------------------- 봇 -------------------------
def test_bot_captures_visible_enemy():
    st = bare()
    st['turn'] = 'W'
    put(st, 'W_N1', 'W', 'N', 5, 5)
    put(st, 'B_R1', 'B', 'R', 3, 4)                 # 값진 룩, 나이트 사정+시야
    assert bot.choose_action(st, 'W') == ('move', 'W_N1', 3, 4)


def test_bot_king_evades_threat():
    st = bare()
    st['turn'] = 'B'
    put(st, 'B_K1', 'B', 'K', 5, 5)
    put(st, 'W_N1', 'W', 'N', 3, 6)                 # (5,5) 위협
    st['botmem'] = {'B': {(3, 6): {'t': 'N', 'seen': 0}}}
    act = bot.choose_action(st, 'B')
    danger = bot._threat_cells([(3, 6, 'N')], 'B')
    assert act[0] == 'move' and act[1] == 'B_K1' and (act[2], act[3]) not in danger


def test_bot_memory_king_shot():
    st = bare()
    st['turn'] = 'B'
    put(st, 'B_K1', 'B', 'K', 1, 1)                 # 내 킹 안전
    put(st, 'B_B1', 'B', 'B', 5, 5)                 # 비숍
    put(st, 'W_K1', 'W', 'K', 5, 7)                 # 안 보이는 적 킹
    st['botmem'] = {'B': {(5, 7): {'t': 'K', 'seen': 0}}}
    assert bot.choose_action(st, 'B') == ('fire', 'B_B1', 5, 7)


def test_bot_setup_hides_king_in_bush():
    _set_terrain(bushes={(2, 5)})                   # 흑 진영(0~2)에 부쉬
    st = pieces.new_game()
    bot.setup_and_ready(st, 'B')
    k = next(p for p in st['pieces'].values() if p['o'] == 'B' and p['t'] == 'K')
    assert (k['r'], k['c']) == (2, 5) and st['ready']['B'] is True
