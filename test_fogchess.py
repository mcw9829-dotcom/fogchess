# -*- coding: utf-8 -*-
"""
규칙 엔진 회귀 테스트 (pytest).

실행:  fogchess 폴더에서  ->  python -m pytest -q
지형(FORESTS/BUSHES/RIVERS)은 서버 시작 시 무작위 생성되므로, 각 테스트는
clean_terrain 픽스처로 '빈 지형'에서 시작하고 필요할 때만 지형을 심는다.
"""
import os, re
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
        assert len(types) == 16
        assert Counter(types) == Counter({'P': 8, 'R': 2, 'N': 2, 'B': 2, 'Q': 1, 'K': 1})
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
    assert (5, 7) in m and (3, 5) in m and (5, 8) not in m    # ROOK_RANGE=2(이동)
    put(st, 'W_P1', 'W', 'P', 5, 6)
    m = set(pieces.legal_moves(st, 'W_R1'))
    assert (5, 6) not in m and (5, 7) not in m                # 아군 앞 막힘


def test_queen_moves_8dir_range2():
    st = bare()
    put(st, 'W_Q1', 'W', 'Q', 6, 6)
    m = set(pieces.legal_moves(st, 'W_Q1'))
    assert {(6, 8), (8, 8), (4, 6), (4, 4)} <= m              # 직선·대각 2칸
    assert (6, 9) not in m and (9, 9) not in m                # 3칸 불가


def test_queen_scan_reveals_bush_no_muzzle():
    _set_terrain(bushes={(5, 5)})
    st = bare(); st['turn'] = 'W'
    put(st, 'W_Q1', 'W', 'Q', 7, 7)                           # 사거리 안(맨해튼 4)
    put(st, 'B_N1', 'B', 'N', 5, 5)                           # 부쉬 속 숨은 적
    assert pieces.player_view(st, 'W')['grid'][5][5]['p'] is None
    ok, _ = pieces.apply_scan(st, 'W', 'W_Q1', 5, 5)          # (5,5) 기준 2×2 감시
    assert ok
    assert pieces.player_view(st, 'W')['grid'][5][5]['p'] is not None   # 스캔으로 노출
    assert not pieces.revealed(st, 'B', 'W_Q1')              # 퀸은 머즐 플래시 없음(위치 노출 X)
    # 감시 지역은 양쪽 뷰의 scanTiles에 뜸(상대도 인지)
    assert len(pieces.player_view(st, 'W')['scanTiles']) == 4
    assert len(pieces.player_view(st, 'B')['scanTiles']) == 4
    assert st['turn'] == 'B'                                  # 스캔은 턴 소모


def test_queen_scan_range_limit():
    st = bare()
    put(st, 'W_Q1', 'W', 'Q', 0, 0)
    assert not pieces.apply_scan(st, 'W', 'W_Q1', 11, 11)[0]  # 맨해튼 22 > 4


# ------------------------- 지형: 이동/시야 -------------------------
def test_forest_blocks_move():
    _set_terrain(forests={(9, 5)})
    st = bare()
    put(st, 'W_P1', 'W', 'P', 10, 5, moved=False)
    assert (9, 5) not in set(pieces.legal_moves(st, 'W_P1'))


def test_knight_vision_is_3():
    st = bare()
    put(st, 'W_N1', 'W', 'N', 5, 5)
    vis = pieces.visible_cells(st, 'W')
    assert (5, 8) in vis and (2, 2) in vis and (8, 8) in vis      # 체비셰프 거리 3까지
    assert (5, 9) not in vis and (1, 5) not in vis                # 4칸은 안 보임
    assert len(vis) == 7 * 7                                      # 7×7 시야(장애물 없음)


def test_los_blocked_by_forest():
    _set_terrain(forests={(5, 6)})
    st = bare()
    put(st, 'W_N1', 'W', 'N', 5, 5)                # 시야 3
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


def test_turn_timeout_passes_turn_not_lose():
    st = pieces.new_game(); st['phase'] = 'play'; st['turn'] = 'W'
    pieces.time_out(st)                                  # W 시간초과
    assert st['turn'] == 'B'                             # 패배 아니라 턴만 넘어감
    assert st['misses']['W'] == 1 and st['phase'] == 'play'


def test_three_consecutive_timeouts_lose():
    st = pieces.new_game(); st['phase'] = 'play'; st['turn'] = 'W'
    for _ in range(3):
        pieces.time_out(st)
        if st['phase'] == 'play':
            pieces.advance_turn(st)                      # 사이에 상대(B)가 한 수 둠
    assert st['phase'] == 'over' and st['winner'] == 'B' and st['misses']['W'] == config.MAX_MISSES


def test_move_resets_miss_counter():
    st = pieces.new_game(); st['phase'] = 'play'; st['turn'] = 'W'
    pieces.time_out(st)                                  # W miss1 → turn B
    assert st['misses']['W'] == 1
    st['turn'] = 'W'                                     # 다시 W 차례로
    pieces.advance_turn(st, real_move=True)             # W가 실제로 둠 → 리셋
    assert st['misses']['W'] == 0


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


def test_bot_snipes_visible_enemy():
    st = bare()
    st['turn'] = 'W'
    put(st, 'W_B1', 'W', 'B', 5, 5)                 # 비숍
    put(st, 'W_N1', 'W', 'N', 5, 7)                 # 정찰(시야3)로 (5,8)을 봄
    put(st, 'B_R1', 'B', 'R', 5, 8)                 # 사거리 안 + 보이는 값진 적
    assert bot.choose_action(st, 'W') == ('fire', 'W_B1', 5, 8)


def test_bot_hard_returns_legal_action():
    st = bare(); st['turn'] = 'W'
    put(st, 'W_K1', 'W', 'K', 10, 5)
    put(st, 'W_N1', 'W', 'N', 8, 5)
    put(st, 'B_K1', 'B', 'K', 1, 5)
    put(st, 'B_R1', 'B', 'R', 6, 5)                  # 보이는 값진 적
    act = bot.choose_action_hard(st, 'W', budget=0.2)
    assert act and act[0] in ('move', 'fire', 'barrage')
    if act[0] == 'move':                             # 이동이면 합법수여야
        assert (act[2], act[3]) in pieces.legal_moves(st, act[1])


def test_bot_easy_returns_action():
    st = bare(); st['turn'] = 'W'
    put(st, 'W_N1', 'W', 'N', 8, 5)
    put(st, 'B_R1', 'B', 'R', 6, 4)
    act = bot.choose_action_easy(st, 'W')
    assert act and act[0] == 'move'


def test_bot_setup_hides_king_in_bush():
    _set_terrain(bushes={(2, 5)})                   # 흑 진영(0~2)에 부쉬
    st = pieces.new_game()
    bot.setup_and_ready(st, 'B')
    k = next(p for p in st['pieces'].values() if p['o'] == 'B' and p['t'] == 'K')
    assert (k['r'], k['c']) == (2, 5) and st['ready']['B'] is True


def test_bot_queen_scans_unsearched_enemy_bush():
    """퀸 스캔(능력)을 실제로 쓴다: 적진의 미수색 부쉬(왕 은신 후보)를 2×2로 감시."""
    _set_terrain(bushes={(2, 4), (2, 5)})           # 적진 부쉬 2칸 — 이동(2칸)으론 못 들어가는 거리
    st = bare(); st['turn'] = 'W'; st['turnCount'] = 20
    put(st, 'W_K1', 'W', 'K', 11, 5)
    put(st, 'W_Q1', 'W', 'Q', 6, 5)                 # 부쉬까지 맨해튼 4~5 ≤ SCAN_RANGE(6)
    act = bot.choose_action_hard(st, 'W', budget=0.05)   # 실수 없는 경로(결정적)
    assert act[0] == 'scan' and act[1] == 'W_Q1'
    r, c = act[2], act[3]
    area = {(r, c), (r, c + 1), (r + 1, c), (r + 1, c + 1)}
    assert area & {(2, 4), (2, 5)}                  # 2×2가 부쉬를 덮음
    assert st['botscan']['W'] == 20                 # 스캔 시각 기록(재스캔 쿨다운)
    assert pieces.apply_scan(st, 'W', 'W_Q1', r, c)[0]   # 규칙상 유효한 스캔


def test_bot_queen_scan_waits_while_previous_scan_active():
    """직전 스캔이 살아있는 동안(SCAN_DUR)은 재스캔으로 턴을 낭비하지 않는다."""
    _set_terrain(bushes={(2, 4), (2, 5)})
    st = bare(); st['turn'] = 'W'; st['turnCount'] = 20
    put(st, 'W_K1', 'W', 'K', 11, 5)
    put(st, 'W_Q1', 'W', 'Q', 6, 5)
    st['botscan'] = {'W': 18}                       # 2턴 전 스캔 → 아직 감시 중(SCAN_DUR=5)
    act = bot.choose_action_hard(st, 'W', budget=0.05)
    assert act and act[0] != 'scan'


# ------------------------- 계정 / 레이팅 -------------------------
import accounts


@pytest.fixture
def tmp_db(tmp_path):
    """테스트마다 빈 임시 DB(실제 fogchess.db 건드리지 않음)."""
    accounts.init_db(str(tmp_path / 'test.db'))
    accounts._fails.clear()
    return accounts


def test_login_lockout_after_repeated_failures(tmp_db):
    accounts.signup('pin_user', '1234')
    for _ in range(5):
        assert accounts.login('pin_user', '0000')[0] is None
    res, err = accounts.login('pin_user', '1234')              # 맞는 PIN이어도 잠금 중
    assert res is None and '잠겼' in err
    accounts._fails['pin_user']['until'] = 0                   # 잠금 시간 경과 시뮬레이션
    assert accounts.login('pin_user', '1234')[0] is not None


def test_elo_delta_depends_on_rating_gap():
    assert accounts.expected(1000, 1000) == pytest.approx(0.5)
    assert accounts.elo_delta(1000, 1000, 1) == 16                                   # 동급 승리 = K/2
    assert accounts.elo_delta(1000, 1000, 0) == -16
    assert accounts.elo_delta(1000, 1000, 0.5) == 0
    assert accounts.elo_delta(1000, 1400, 1) > accounts.elo_delta(1400, 1000, 1)     # 약자가 이기면 더 많이
    assert accounts.elo_delta(1000, 1400, 1) + accounts.elo_delta(1400, 1000, 0) == 0  # 영합(반올림 포함)


def test_rating_tiers():
    assert [accounts.tier(r) for r in (500, 999, 1000, 1200, 1500, 1700, 1900, 2400)] == \
        ['P', 'P', 'N', 'R', 'B', 'Q', 'K', 'K']


def test_signup_login_session(tmp_db):
    res, err = accounts.signup('초코비', '1234')
    assert err is None and res['user']['rating'] == 1000 and res['user']['tier'] == 'N'
    assert accounts.signup('초코비', 'x')[1]                    # 짧은 비밀번호 거부
    assert accounts.signup('새이름', '12345')[1]                # 5자리 거부(숫자 4자리 PIN만)
    assert accounts.signup('새이름', '12ab')[1]                 # 숫자 아님 거부
    assert accounts.signup('ChocoBi', '1234')[1] is None      # 다른 이름은 OK
    assert accounts.signup('chocobi', '1234')[1]              # 대소문자만 다른 중복은 거부
    assert accounts.signup('a', '1234')[1]                    # 1글자 거부
    assert accounts.login('초코비', 'wrong')[0] is None
    me = accounts.user_by_token(res['session'])
    assert me and me['name'] == '초코비'
    accounts.logout(res['session'])
    assert accounts.user_by_token(res['session']) is None


def test_record_result_and_floor(tmp_db):
    a = accounts.signup('a_1', '1234')[0]['user']['id']
    b = accounts.signup('b_1', '1234')[0]['user']['id']
    r = accounts.record_result(a, b, 1.0)
    assert r['a'] == {'delta': 16, 'rating': 1016} and r['b'] == {'delta': -16, 'rating': 984}
    assert accounts.user_by_id(a)['wins'] == 1 and accounts.user_by_id(b)['losses'] == 1
    assert accounts.elo_delta(984, 3000, 0.0) == 0               # 훨씬 강한 상대에게 진 건 잃는 게 거의 없음
    for _ in range(25):                                          # 이겨야 할 약한 상대(300)에게 계속 지면 크게 잃되 바닥 500에서 멈춤
        accounts.record_vs_fixed(b, 300, 0.0)
        assert accounts.user_by_id(b)['rating'] >= 500
    assert accounts.user_by_id(b)['rating'] == 500


def test_feedback_store_and_validate(tmp_db):
    ok, err = accounts.add_feedback('bug', '킹이 부쉬에서 안 보여요', name='Moon', room='AB12', ua='UA' * 200)
    assert ok and err is None
    assert accounts.add_feedback('bug', 'ab')[1]                         # 3자 미만 거부
    assert accounts.add_feedback('spam', '분류가 이상함')[1]              # 분류 화이트리스트
    assert accounts.add_feedback('idea', 'x' * 1001)[1]                  # 1000자 초과 거부
    rows = accounts.feedback_list()
    assert len(rows) == 1 and rows[0]['message'] == '킹이 부쉬에서 안 보여요' and rows[0]['name'] == 'Moon'
    assert rows[0]['room'] == 'AB12' and len(rows[0]['ua']) <= 200       # 컨텍스트는 길이 제한


def test_terrain_generation_seeded_and_varied():
    import game_map
    a = game_map.generate_terrain(seed=123); b = game_map.generate_terrain(seed=123); c = game_map.generate_terrain(seed=456)
    assert a['forests'] == b['forests'] and a['bushes'] == b['bushes']            # 같은 시드 = 같은 맵
    assert a['forests'] != c['forests'] or a['bushes'] != c['bushes']             # 다른 시드 = 다른 맵
    assert a['impassable'] == (a['forests'] | a['rivers']) and not (a['forests'] & a['bushes'])
    both = game_map.generate_terrain(seed=7, extra='both')
    assert both['rivers'] and both['bushes']                                       # 강+부쉬 동시
    assert not (both['rivers'] & both['bushes']) and not (both['forests'] & both['rivers'])
    r = game_map.generate_terrain()
    assert 1000 <= r['seed'] <= 999999                                             # 무작위 시드


def test_rooms_have_own_terrain_and_use_terrain_switches_globals():
    import server, pieces as P, bot as B, game_map as G
    r1 = server.new_room('MT1'); r2 = server.new_room('MT2')
    assert 'seed' in r1['terrain'] and 'seed' in r2['terrain']
    server.use_terrain(r1)
    assert P.FORESTS is r1['terrain']['forests'] and B.BUSHES is r1['terrain']['bushes']
    assert G.FORESTS is r1['terrain']['forests'] and P.IMPASSABLE is r1['terrain']['impassable']
    server.use_terrain(r2)
    assert P.FORESTS is r2['terrain']['forests']


def test_server_console_prints_are_cp949_safe():
    """Windows 콘솔(cp949)에서 서버 시작 print가 UnicodeEncodeError로 죽지 않게 — em dash·이모지 금지(주석은 무관)."""
    import io as _io, re
    src = _io.open('server.py', encoding='utf-8').read().splitlines()
    bad = [(i + 1, ln.strip()[:60]) for i, ln in enumerate(src)
           if re.match(r"\s*print\(", ln) and not _cp949_ok(ln)]
    assert not bad, f'cp949로 출력 불가한 print 줄: {bad}'


def _cp949_ok(text):
    try:
        text.encode('cp949'); return True
    except UnicodeEncodeError:
        return False


def test_matchmaking_window_and_pairing():
    import matchmaking as M
    M.QUEUE.clear()
    assert M.window(0) == 100 and M.window(25) == 200 and M.window(59) == 350 and M.window(60) == float('inf')
    rooms = []
    def make_room(a, b):
        rooms.append((a['uid'], b['uid'])); return ('R%d' % len(rooms), 'ta', 'W', 'tb', 'B')
    M.join('sA', {'id': 1, 'name': 'A', 'rating': 1000}, now=0)
    M.join('sB', {'id': 2, 'name': 'B', 'rating': 1500}, now=0)              # 차 500 > ±100 → 아직
    assert M.status('sA', 1, make_room)['state'] == 'waiting' and not rooms
    M.join('sC', {'id': 3, 'name': 'C', 'rating': 1080}, now=2)              # 차 80 → A와 매칭
    st = M.status('sA', 3, make_room)
    assert st['state'] == 'matched' and st['room'] == 'R1' and st['opp']['name'] == 'C' and st['color'] == 'W'
    assert M.status('sC', 3, make_room)['state'] == 'matched' and 'sC' not in M.QUEUE
    assert M.status('sB', 3, make_room)['state'] == 'waiting'
    M.join('sD', {'id': 4, 'name': 'D', 'rating': 700}, now=61)              # B는 60초 지나 무제한 → D와
    assert M.status('sB', 61, make_room)['state'] == 'matched' and rooms[-1] == (2, 4)
    M.QUEUE.clear()


def test_matchmaking_no_self_match_and_stale_prune():
    import matchmaking as M
    M.QUEUE.clear()
    mk = lambda a, b: ('R', 'a', 'W', 'b', 'B')
    M.join('s1', {'id': 9, 'name': 'X', 'rating': 1000}, now=0)
    M.join('s2', {'id': 9, 'name': 'X', 'rating': 1000}, now=0)               # 같은 계정(다른 탭) → 서로 안 붙음
    assert M.status('s1', 1, mk)['state'] == 'waiting'
    assert M.status('s1', 19, mk)['state'] == 'waiting'                        # s2는 폴링 끊긴 지 19초 → 정리됨
    assert 's2' not in M.QUEUE and 's1' in M.QUEUE
    M.cancel('s1'); assert M.status('s1', 20, mk)['state'] == 'idle'
    M.QUEUE.clear()


def test_server_match_room_is_rated_pvp(tmp_db):
    import server
    a = accounts.signup('mm_a', '1234')[0]['user']; b = accounts.signup('mm_b', '1234')[0]['user']
    code, ta, ca, tb, cb = server.make_match_room({'uid': a['id'], 'name': 'mm_a', 'rating': 1000},
                                                  {'uid': b['id'], 'name': 'mm_b', 'rating': 1010})
    room = server.ROOMS.pop(code)
    assert {ca, cb} == {'W', 'B'} and room['match'] and server.is_rated(room)
    assert room['users'][ca] == a['id'] and room['tokens'][ta] == ca and room['tokens'][tb] == cb
    assert room['state']['deadline'] is not None                                # 둘 다 앉음 → 배치 타이머 시작


def test_server_settles_bot_game_once(tmp_db):
    import server
    u = accounts.signup('bot_beater', '1234')[0]['user']
    room = server.new_room('T1')
    room['bot'] = 'B'; room['botlevel'] = 'hard'
    room['users'] = {'W': u['id']}; room['ratings'] = {'W': 1000}
    st = room['state']; st['phase'] = 'over'; st['winner'] = 'W'
    assert server.is_rated(room)
    server.settle_rating(room); server.settle_rating(room)        # 두 번 불러도 한 번만 반영
    d = room['rating_result']['W']
    assert d['delta'] == accounts.elo_delta(1000, 1300, 1.0) == 27
    assert accounts.user_by_id(u['id'])['rating'] == 1027 and accounts.user_by_id(u['id'])['wins'] == 1
    assert room['ratings']['W'] == 1027



def test_bot_loss_keeps_rating_and_gain_cap(tmp_db):
    """컴퓨터 대국: 져도 0(전적은 기록), 이기면 오르되 난이도 상한(컴퓨터 레이팅+200)에서 멈춤."""
    import server
    from config import BOT_GAIN_CAP
    u = accounts.signup('bot_loser', '1234')[0]['user']
    room = server.new_room('T5'); room['bot'] = 'B'; room['botlevel'] = 'hard'
    room['users'] = {'W': u['id']}; room['ratings'] = {'W': 1000}
    st = room['state']; st['phase'] = 'over'; st['winner'] = 'B'                      # 패배
    server.settle_rating(room)
    assert room['rating_result']['W'] == {'delta': 0, 'rating': 1000}
    me = accounts.user_by_id(u['id']); assert me['rating'] == 1000 and me['losses'] == 1
    # 상한: 어려움(1300)+200 = 1500. 1490에서 이기면 +10까지만, 1500에서는 0
    assert accounts.fixed_delta(1490, 1300, 1.0, True, 1300 + BOT_GAIN_CAP) == 8        # 원래 변동(8)이 남은 여유(10)보다 작음
    assert accounts.fixed_delta(1495, 1300, 1.0, True, 1300 + BOT_GAIN_CAP) == 5        # 상한까지 남은 5만
    assert accounts.fixed_delta(1500, 1300, 1.0, True, 1300 + BOT_GAIN_CAP) == 0
    assert accounts.fixed_delta(1000, 1300, 1.0, True, 1300 + BOT_GAIN_CAP) == 27      # 상한 아래면 그대로
    assert accounts.fixed_delta(1400, 1300, 0.5, True, None) == 0                       # 비겨도 안 떨어짐
    assert server.bot_gain_cap(room) == 1500
    room2 = server.new_room('T6'); room2['bot'] = 'B'; room2['botlevel'] = 'easy'
    room2['users'] = {'W': u['id']}; room2['ratings'] = {'W': 1000}
    assert '더 오르지 않아요' in server.bot_rating_note(room2)                          # 쉬움 상한 1000 도달
    room2['ratings'] = {'W': 900}
    assert server.bot_rating_note(room2).startswith('📈 레이팅 900: 이기면 +')


def test_leaderboard_order(tmp_db):
    a = accounts.signup('lb_a', '1234')[0]['user']['id']
    b = accounts.signup('lb_b', '1234')[0]['user']['id']
    accounts.signup('lb_c', '1234')
    accounts.record_vs_fixed(b, 1000, 1.0)                        # b 1016
    accounts.record_vs_fixed(a, 1000, 0.0)                        # a 984
    lb = accounts.leaderboard()
    assert [u['name'] for u in lb] == ['lb_b', 'lb_c', 'lb_a'] and [u['rank'] for u in lb] == [1, 2, 3]
    assert 'id' not in lb[0] and lb[0]['tier'] == 'N'


def test_session_expires_after_ttl(tmp_db):
    import time
    res, _ = accounts.signup('sess_u', '1234')
    assert accounts.user_by_token(res['session'])
    with accounts._db() as c:                                      # 31일 전 발급으로 조작
        c.execute('UPDATE sessions SET created=? WHERE token=?', (time.time() - 31 * 86400, res['session']))
    assert accounts.user_by_token(res['session']) is None
    accounts.login('sess_u', '1234')                              # 로그인 시 만료 세션 정리
    with accounts._db() as c:
        assert c.execute('SELECT COUNT(*) FROM sessions WHERE token=?', (res['session'],)).fetchone()[0] == 0


def test_account_input_types_are_coerced(tmp_db):
    assert accounts.signup([], {})[1]                              # 이상한 타입도 500 대신 오류 메시지
    assert accounts.login(None, None)[0] is None
    assert accounts.signup('num_pin', 1234)[1] is None            # 숫자로 온 PIN도 문자열로 처리


def test_sweep_forfeits_disconnected_player(tmp_db):
    import server, time as _t
    a = accounts.signup('sw_a', '1234')[0]['user']; b = accounts.signup('sw_b', '1234')[0]['user']
    room = server.new_room('SW1'); now = _t.time()
    room['seats'] = {'W': 'tokW', 'B': 'tokB'}; room['tokens'] = {'tokW': 'W', 'tokB': 'B'}
    room['seen'] = {'tokW': now - 100, 'tokB': now}                 # 백이 100초째 접속 없음
    room['users'] = {'W': a['id'], 'B': b['id']}; room['ratings'] = {'W': 1000, 'B': 1000}
    room['match'] = True                                              # 랭크 매칭 방 = 레이팅전(로비는 비레이팅)
    st = room['state']; st['phase'] = 'play'; st['turn'] = 'B'; st['turn_deadline'] = now + 10
    server.ROOMS['SW1'] = room
    try:
        server.sweep_rooms(now)
        assert st['phase'] == 'over' and st['winner'] == 'B'
        assert any('기권' in line for line in st['log'])
        assert accounts.user_by_id(a['id'])['rating'] == 984 and accounts.user_by_id(b['id'])['rating'] == 1016
    finally:
        server.ROOMS.pop('SW1', None)


def test_sweep_ignores_bot_seat_and_short_gaps(tmp_db):
    import server, time as _t
    room = server.new_room('SW2'); now = _t.time()
    room['bot'] = 'B'; room['seats'] = {'W': 'tokW', 'B': server.BOT_TOKEN}
    room['tokens'] = {'tokW': 'W', server.BOT_TOKEN: 'B'}
    room['seen'] = {'tokW': now - 30, server.BOT_TOKEN: now - 500}  # 봇 좌석은 오래돼도 무시, 사람 30초는 아직
    st = room['state']; st['phase'] = 'play'; st['turn'] = 'W'; st['turn_deadline'] = now + 10
    server.ROOMS['SW2'] = room
    try:
        server.sweep_rooms(now)
        assert st['phase'] == 'play'
        room['seen']['tokW'] = now - 95                                # 95초 → 기권
        server.sweep_rooms(now)
        assert st['phase'] == 'over' and st['winner'] == 'B'
    finally:
        server.ROOMS.pop('SW2', None)


def test_server_guest_and_solo_games_unrated(tmp_db):
    import server
    room = server.new_room('T2'); room['bot'] = 'B'               # 게스트(비회원) 봇전
    assert not server.is_rated(room)
    room2 = server.new_room('T3'); room2['solo'] = True
    room2['users'] = {'W': 1, 'B': 1}
    assert not server.is_rated(room2)



def test_server_lobby_pvp_unrated(tmp_db):
    """로비(친구) 대전: 양쪽 다 회원이어도 비레이팅. 같은 두 회원이 랭크 매칭 방이면 레이팅전."""
    import server
    room = server.new_room('T4'); room['users'] = {'W': 1, 'B': 2}       # match=False (기본)
    assert not server.is_rated(room)
    room['match'] = True
    assert server.is_rated(room)


def test_bush_hidden_enemy_capturable_by_move():
    """부쉬에 숨은 적 칸도 legal_moves에 포함(수색 이동) — 클라 표식은 z-index로 부쉬 잎 위에 그린다."""
    import sys
    mods = tuple(sys.modules[n] for n in ('pieces', 'game', 'bot') if n in sys.modules)
    t = game_map.generate_terrain(seed=7, extra='bush'); assert t['bushes']
    saved = game_map.TERRAIN
    game_map.apply_terrain(t, *mods)
    try:
        st = bare()
        found = None
        for br, bc in sorted(t['bushes']):                                       # 부쉬 옆 빈 칸(장애물 아님) 하나
            for dr, dc in ((0, 1), (0, -1), (1, 0), (-1, 0)):
                r, c = br + dr, bc + dc
                if 0 <= r < 12 and 0 <= c < 12 and (r, c) not in t['impassable'] and (r, c) not in t['bushes']:
                    found = (br, bc, r, c); break
            if found: break
        assert found, 'no bush with a free neighbour'
        br, bc, r, c = found
        put(st, 'W_R1', 'W', 'R', r, c)                                          # 내 룩 옆칸, 부쉬 안에 숨은 적 폰
        put(st, 'B_P1', 'B', 'P', br, bc)
        assert (br, bc) in {tuple(m) for m in pieces.legal_moves(st, 'W_R1')}
    finally:
        game_map.apply_terrain(saved, *mods)
    css = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'style.css'), encoding='utf-8').read()
    assert re.search(r'\.movable::before\s*\{[^}]*z-index:\s*4', css) and re.search(r'\.bushfront\{\s*z-index:3', css)


# ------------------------- 신규 규칙 -------------------------
def test_king_vision_3():
    st = bare()
    put(st, 'W_K1', 'W', 'K', 5, 5)                 # 킹 시야 반경 3
    vis = pieces.visible_cells(st, 'W')
    assert (5, 8) in vis and (2, 5) in vis          # 3칸까지 보임
    assert (5, 9) not in vis                        # 4칸은 안 보임


def test_bishop_snipe_needs_vision():
    st = bare()
    put(st, 'W_B1', 'W', 'B', 5, 5)                 # 비숍 시야 1
    put(st, 'B_R1', 'B', 'R', 5, 9)                 # 사거리 안(4)이지만 안 보임
    ok, _ = pieces.apply_fire(st, 'W', 'W_B1', 5, 9)
    assert not ok                                   # 못 봐서 저격 불가
    put(st, 'W_N1', 'W', 'N', 5, 8)                 # 정찰이 (5,9)를 봄
    ok, _ = pieces.apply_fire(st, 'W', 'W_B1', 5, 9)
    assert ok and not st['pieces']['B_R1']['alive']  # 이제 저격 성공


def test_fire_range_disc_independent_of_vision():
    st = bare()
    put(st, 'W_B1', 'W', 'B', 5, 5)
    rng = pieces.fire_range(st, 'W_B1')
    R = config.BISHOP_RANGE
    assert rng, '사거리 원은 적이 없어도 표시돼야 함'
    assert (5, 5) not in rng                              # 자기 칸 제외
    assert all((r - 5) ** 2 + (c - 5) ** 2 <= R * R for r, c in rng)  # 반경 안
    assert (5, 5 + R) in rng and (5, 5 + R + 1) not in rng            # 경계
    assert pieces.fire_cells(st, 'W_B1') == []            # 표적(보이는 적)은 없음


def test_fire_range_excludes_forest():
    _set_terrain(forests={(5, 7)})                        # 사거리 안에 숲 한 칸
    st = bare()
    put(st, 'W_B1', 'W', 'B', 5, 5)
    assert (5, 7) not in pieces.fire_range(st, 'W_B1')    # 숲은 원에서 뺌


def test_bishop_snipe_single_tile_only():
    st = bare()
    put(st, 'W_B1', 'W', 'B', 5, 5)
    tgt = put(st, 'B_N1', 'B', 'N', 5, 6)           # 표적(인접·보임)
    near = put(st, 'B_R1', 'B', 'R', 4, 5)          # 옆칸 — 옛 X자였다면 같이 죽었음
    pieces.apply_fire(st, 'W', 'W_B1', 5, 6)
    assert not tgt['alive'] and near['alive']       # 딱 한 칸만 명중


def test_barrage_cross_only_range4():
    st = bare()                                     # 대각선은 사격 불가(십자 전용)
    put(st, 'W_R1', 'W', 'R', 5, 5)
    put(st, 'B_P1', 'B', 'P', 7, 7)
    ok, _ = pieces.apply_barrage(st, 'W', 'W_R1', 7, 7)
    assert not ok and st['pieces']['B_P1']['alive']
    st = bare()                                     # 직선 4칸은 명중
    put(st, 'W_R1', 'W', 'R', 5, 5)
    put(st, 'B_P1', 'B', 'P', 5, 9)
    ok, _ = pieces.apply_barrage(st, 'W', 'W_R1', 5, 9)
    assert ok and not st['pieces']['B_P1']['alive']


def test_pawn_promotion_flow():
    st = bare()
    st['turn'] = 'W'
    put(st, 'W_P1', 'W', 'P', 1, 5, moved=True)
    ok, _ = pieces.apply_move(st, 'W', 'W_P1', 0, 5)   # 끝줄 도달
    assert ok and st['promote'] and st['promote']['color'] == 'W'
    assert st['turn'] == 'W'                            # 승격 전엔 턴 유지
    ok, _ = pieces.apply_promote(st, 'W', 'R')
    assert ok and st['pieces']['W_P1']['t'] == 'R'
    assert st['promote'] is None and st['turn'] == 'B'  # 승격 후 턴 넘어감


def test_promotion_rejects_bad_choice():
    st = bare()
    st['promote'] = {'pid': 'W_P1', 'color': 'W'}
    assert not pieces.apply_promote(st, 'W', 'K')[0]    # 킹으로는 승격 불가
    assert not pieces.apply_promote(st, 'W', 'Q')[0]    # 퀸 없음


def test_resign_gives_win_to_opponent():
    st = pieces.new_game()
    st['phase'] = 'play'
    ok, _ = pieces.apply_resign(st, 'W')
    assert ok and st['phase'] == 'over' and st['winner'] == 'B'
