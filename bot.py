# -*- coding: utf-8 -*-
"""
AI 봇 상대 — 서버가 '봇 차례'에 이 모듈을 불러 자동으로 응수한다.

설계 원칙: 봇은 '자기 안개 시야(player_view) + 기억'만 보고 판단한다(포그 오브 워 준수).
전체 보드를 훔쳐보지 않는다. 규칙 판정·적용은 pieces.py에 위임한다.

우선순위(choose_action):
  1) 보이는 적 킹을 잡는/포격하는 수 → 무조건(게임 끝)
  2) 내 킹이 위협받으면 → 위협 기물 제거 or 안전한 칸(부쉬)으로 회피
  3) 그 외 공격(멜리 캡처 / 비숍 단일 저격 / 전차 8방향 돌파사격, 값진 표적 우선)
  4) 표적 없음 → 전진·정찰(기억한 적 위치로 추격, 나이트 우선, 킹은 숨김)

기억(st['botmem']): {(r,c): {'t':종류,'seen':턴}} — 시야에 든 칸은 매 턴 갱신·삭제.
"""
import time
import random

from config import (N, VISION, BISHOP_RANGE, BISHOP_MOVE, ROOK_FIRE, QUEEN_MOVE,
                    SCAN_RANGE, SCAN_DUR, ZONE, BOT_HARD_BUDGET, BOT_NORMAL_BUDGET,
                    BOT_EASY_BUDGET, BOT_EASY_BLUNDER)
from game_map import FORESTS, BUSHES, in_board
import pieces
from pieces import DIRS4, DIRS8

VALUE = {'K': 1000, 'Q': 6, 'R': 5, 'B': 4, 'N': 3, 'P': 1}
KNIGHT = [(-2, -1), (-2, 1), (2, -1), (2, 1), (-1, -2), (-1, 2), (1, -2), (1, 2)]
MEM_TTL = 6          # 기억 유효 턴 수(이보다 오래되면 잊음)
WIN_SCORE = 9500     # 이 점수 이상 = '보이는 적 킹을 잡는 수'

# ── 강화 파라미터(정당한 실력 강화용 노브) ──
KING_GUARD = 2           # 정찰 때 킹 근처에 남겨둘 수비 기물 수
KING_DANGER_RADIUS = 3   # 알려진 적이 킹의 이 반경 안에 오면 미리 방어/대피
KING_SAFE_W = 0.2        # 평가함수의 킹 안전 가중(너무 크면 '거북이'가 됨 — 이 게임은 공격이 이김)
MINIMAX_MAX_DEPTH = 8    # 미니맥스 최대 탐색 깊이 상한
QUIESCENCE_DEPTH = 3     # 깊이 끝에서 캡처만 더 보는 정지탐색 깊이(호라이즌 완화)


# ------------------------- 배치 단계 -------------------------
def setup_and_ready(st, me):
    """기본 포진 + (가능하면) 킹을 자기 진영 부쉬에 숨기고 준비 완료."""
    pieces.autoplace(st, me, 'default')
    _hide_king(st, me)
    st['ready'][me] = True


def _hide_king(st, me):
    z0, z1 = ZONE[me]
    king = _my_king(st, me)
    if not king:
        return
    for (r, c) in BUSHES:                      # 내 진영 안의 빈 부쉬로 킹 이동(매복)
        if z0 <= r <= z1 and pieces.piece_at(st, r, c) is None:
            king['r'], king['c'] = r, c
            return


# ------------------------- 소도구 -------------------------
def _mine(st, me):
    return [p for p in st['pieces'].values() if p['alive'] and p['o'] == me]


def _my_king(st, me):
    return next((p for p in st['pieces'].values()
                 if p['o'] == me and p['t'] == 'K' and p['alive']), None)


def _first_piece_in_line(st, p, dr, dc):
    """전차 사격 방향으로 처음 만나는 기물 (r, c, piece). 숲/보드밖이면 None."""
    for dist in range(1, ROOK_FIRE + 1):
        r, c = p['r'] + dr * dist, p['c'] + dc * dist
        if not in_board(r, c) or (r, c) in FORESTS:
            return None
        q = pieces.piece_at(st, r, c)
        if q is not None:
            return (r, c, q)
    return None


# ------------------------- 시야 & 기억 -------------------------
def _update_memory(st, me, view):
    """시야에 든 칸은 기억을 갱신(적 있으면 기록, 없으면 삭제). 오래된 기억은 만료."""
    opp = 'B' if me == 'W' else 'W'
    mem = st.setdefault('botmem', {}).setdefault(me, {})   # 색깔별 기억(양쪽 봇이어도 안 섞임)
    now = st['turnCount']
    for r, row in enumerate(view['grid']):
        for c, cell in enumerate(row):
            if cell['f'] == 0:                 # 이 칸이 지금 내 시야면
                p = cell.get('p')
                if p and p['o'] == opp:
                    mem[(r, c)] = {'t': p['t'], 'seen': now}
                elif (r, c) in mem:
                    del mem[(r, c)]            # 보이는데 적 없음 → 기억 삭제(추적 정확도↑)
    for k in [k for k, v in mem.items() if now - v['seen'] > MEM_TTL]:
        del mem[k]


def _enemies_from_view(view, me):
    """지금 실제로 보이는 적 [(r, c, type)]."""
    opp = 'B' if me == 'W' else 'W'
    return [(r, c, cell['p']['t'])
            for r, row in enumerate(view['grid'])
            for c, cell in enumerate(row)
            if cell.get('p') and cell['p']['o'] == opp]


def _remembered(st, me):
    """기억된 적 [(r, c, type, seen)] — 현재 안 보이는 것 포함."""
    return [(r, c, v['t'], v['seen'])
            for (r, c), v in st.get('botmem', {}).get(me, {}).items()]


# ------------------------- 왕 사냥(정찰 · 부쉬 수색) -------------------------
# 안개 규칙 준수: 실제 왕 위치를 훔쳐보지 않는다. '아직 확인 못 한 적 진영 칸'을
# 후보 은신처(특히 부쉬)로 두고 — 시야로 훑거나, 직접 들어가거나, 룩 돌파사격/퀸 스캔으로
# 좁혀 들어간다. (부쉬는 시야로 못 뚫음 → 진입/포격/스캔으로만 확인)
SCOUT_TTL = 5           # 비-부쉬 적진 칸을 이 턴 수 안에 봤으면 '확인됨'으로 침
SWEEP_COOLDOWN = 8      # 포격/스캔으로 훑은 칸은 이 턴 수 동안 후보에서 제외(반복 낭비 방지)
SCAN_SWEEP_TTL = 24     # 퀸 스캔으로 들여다본 칸(부쉬 포함)은 이 턴 수 동안 '수색 완료' — 같은 군락 되풀이 스캔 방지


def _enemy_half(me):
    return range(0, N // 2) if me == 'W' else range(N // 2, N)


def _update_scout(st, me, view):
    """적 진영에서 '확인한 칸'을 기록 — 시야에 든 비-부쉬 칸 + 내가 밟아본 부쉬."""
    now = st['turnCount']
    seen = st.setdefault('botscout', {}).setdefault(me, {})
    entered = st.setdefault('botenter', {}).setdefault(me, set())
    half = set(_enemy_half(me))
    for p in st['pieces'].values():
        if p['alive'] and p['o'] == me and p['r'] in half and (p['r'], p['c']) in BUSHES:
            entered.add((p['r'], p['c']))          # 내 기물이 올라선 적진 부쉬 = 수색 완료
    for r, row in enumerate(view['grid']):
        if r not in half:
            continue
        for c, cell in enumerate(row):
            if cell['f'] == 0 and (r, c) not in BUSHES:
                seen[(r, c)] = now


def _candidates(st, me):
    """왕이 숨어 있을 법한 '아직 확인 못 한 적 진영 칸' [(r, c, weight)]. 부쉬·뒷줄 가중."""
    now = st['turnCount']
    seen = st.get('botscout', {}).get(me, {})
    entered = st.get('botenter', {}).get(me, set())
    swept = st.get('botswept', {}).get(me, {})
    scanned = st.get('botscanned', {}).get(me, {})
    opp = 'B' if me == 'W' else 'W'
    z0, z1 = ZONE[opp]
    out = []
    for r in _enemy_half(me):
        for c in range(N):
            if (r, c) in FORESTS:
                continue
            if now - swept.get((r, c), -999) <= SWEEP_COOLDOWN:
                continue
            if now - scanned.get((r, c), -999) <= SCAN_SWEEP_TTL:   # 스캔으로 이미 들여다본 칸
                continue
            if (r, c) in BUSHES:
                if (r, c) not in entered:
                    out.append((r, c, 3.0))            # 미수색 부쉬 = 최우선 후보
            elif now - seen.get((r, c), -999) > SCOUT_TTL:
                out.append((r, c, 1.4 if z0 <= r <= z1 else 0.6))
    return out


def _enter_bush(st, me, cands):
    """미수색 후보 부쉬에 들어갈 수 있으면 진입(왕이 있으면 잡아 승리). 싼 기물 우선, 킹 제외."""
    bushes = {(r, c) for (r, c, w) in cands if (r, c) in BUSHES}
    if not bushes:
        return None
    best = None
    for p in _mine(st, me):
        if p['t'] == 'K':
            continue
        for (mr, mc) in pieces.legal_moves(st, p['id']):
            if (mr, mc) in bushes and (best is None or VALUE[p['t']] < best[0]):
                best = (VALUE[p['t']], p['id'], mr, mc)
    return ('move', best[1], best[2], best[3]) if best else None


def _scout_move(st, me, cands):
    """후보(비-부쉬)를 가장 많이 새로 시야에 넣고, 후보 부쉬에 접근하며, 적진으로 전진하는 이동.
    킹 수비대(KING_GUARD명)는 멀리 정찰 보내지 않는다(킹 방어)."""
    if not cands:
        return None
    guards = _guard_pids(st, me)
    open_c = [(r, c, w) for (r, c, w) in cands if (r, c) not in BUSHES]
    bushes = [(r, c) for (r, c, w) in cands if (r, c) in BUSHES]
    best, best_s = None, None
    for p in _mine(st, me):
        if p['t'] == 'K' or p['id'] in guards:
            continue
        rad = VISION.get(p['t'], 1)
        for (mr, mc) in pieces.legal_moves(st, p['id']):
            cover = sum(w for (cr, cc, w) in open_c if max(abs(cr - mr), abs(cc - mc)) <= rad)
            if bushes:
                near = min(abs(mr - br) + abs(mc - bc) for (br, bc) in bushes)
                cover += max(0.0, 3.0 - near * 0.5)          # 후보 부쉬 접근(다음 턴 진입) 보너스
            adv = ((N - 1 - mr) if me == 'W' else mr) * 0.03
            s = cover + adv + (0.3 if p['t'] == 'N' else 0.0)
            s += ((p['r'] * 7 + p['c'] * 13 + mr * 3 + mc) % 5) * 0.01   # 미세 타이브레이크
            if best_s is None or s > best_s:
                best_s, best = s, ('move', p['id'], mr, mc)
    return best


def _barrage_flush(st, me, cands):
    """전차 돌파사격으로 후보(부쉬/뒷줄)를 관통 소탕 — 숨은 왕도 물리적으로 맞힘.
    선상 후보 가중이 충분할 때만(노출·턴 낭비 방지). 아군이 막으면 그 방향 제외."""
    cw = {(r, c): w for (r, c, w) in cands}
    best = None
    for p in _mine(st, me):
        if p['t'] != 'R':
            continue
        for dr, dc in DIRS4:
            reach, swept, blocked = 0.0, [], False
            for dist in range(1, ROOK_FIRE + 1):
                r, c = p['r'] + dr * dist, p['c'] + dc * dist
                if not in_board(r, c) or (r, c) in FORESTS:
                    break
                q = pieces.piece_at(st, r, c)
                if q is not None and q['o'] == me:
                    blocked = True
                    break
                reach += cw.get((r, c), 0.0)
                swept.append((r, c))
            if not blocked and reach >= 6.0 and (best is None or reach > best[0]):   # 부쉬 2곳급일 때만(노출·템포 비용)
                best = (reach, p['id'], p['r'] + dr, p['c'] + dc, swept)
    if best:
        sw = st.setdefault('botswept', {}).setdefault(me, {})   # 쿨다운 기록(반복 포격 방지)
        for cell in best[4]:
            sw[cell] = st['turnCount']
        return ('barrage', best[1], best[2], best[3])
    return None


def _scan_hunt(st, me, cands):
    """퀸 스캔으로 후보 2×2를 감시(부쉬·안개 뚫어 왕 노출 → 다음 턴 저격/포획). 후보 가중 높은 곳 우선.
    템포 보호(예전에 '매 턴 스캔만 하다 소극적'이 되던 원인 제거):
      (1) 미수색 부쉬가 든 2×2만 스캔 — 왕이 숨을 만한 곳이 아니면 턴을 쓰지 않는다.
      (2) 직전 스캔이 아직 살아있는 동안(SCAN_DUR)은 재스캔 안 함 — 감시가 겹치면 낭비."""
    q = next((p for p in _mine(st, me) if p['t'] == 'Q'), None)
    if not q:
        return None
    now = st['turnCount']
    if now - st.get('botscan', {}).get(me, -999) < SCAN_DUR:
        return None
    cw = {(r, c): w for (r, c, w) in cands}
    best = None
    for (tr, tc) in pieces.scan_cells(st, q['id']):
        area = [(tr, tc), (tr, tc + 1), (tr + 1, tc), (tr + 1, tc + 1)]
        if not any(cell in BUSHES and cell in cw for cell in area):    # 미수색 부쉬 없으면 스킵
            continue
        reach = sum(cw.get(cell, 0.0) for cell in area)
        if best is None or reach > best[0]:
            best = (reach, tr, tc, area)
    if best and best[0] >= 4.0:
        st.setdefault('botscan', {})[me] = now                          # 스캔 시각(재스캔 쿨다운)
        sw = st.setdefault('botswept', {}).setdefault(me, {})
        sc = st.setdefault('botscanned', {}).setdefault(me, {})         # 들여다본 칸 = 오래 '수색 완료'
        for cell in best[3]:
            sw[cell] = now
            sc[cell] = now
        return ('scan', q['id'], best[1], best[2])
    return None


# ------------------------- 위협 계산(킹 회피용) -------------------------
def _threat_cells(known, me):
    """알고 있는 적들이 '다음 턴에 닿을 수 있는' 칸 집합. known=[(r,c,type,...)]."""
    fr = pieces.FORWARD['B' if me == 'W' else 'W']   # 적 폰 전진 방향
    danger = set()
    for e in known:
        r, c, t = e[0], e[1], e[2]
        if t == 'P':
            for cc in (c - 1, c + 1):
                danger.add((r + fr, cc)); danger.add((r, cc))
        elif t == 'N':
            for dr, dc in KNIGHT:
                danger.add((r + dr, c + dc))
        elif t == 'K':
            for dr in (-1, 0, 1):
                for dc in (-1, 0, 1):
                    if dr or dc:
                        danger.add((r + dr, c + dc))
        elif t == 'B':                                 # 저격은 시야 필요 → 근접(대각 이동 2칸)만 위협 모델
            for dr, dc in [(-1, -1), (-1, 1), (1, -1), (1, 1)]:
                for d in range(1, BISHOP_MOVE + 1):
                    danger.add((r + dr * d, c + dc * d))
        elif t == 'R':                                 # 돌파사격: 십자 직선(숲에 막힘)
            for dr, dc in DIRS4:
                for d in range(1, ROOK_FIRE + 1):
                    rr, cc = r + dr * d, c + dc * d
                    if not in_board(rr, cc) or (rr, cc) in FORESTS:
                        break
                    danger.add((rr, cc))
        elif t == 'Q':                                 # 퀸 근접 위협(8방향 이동칸)
            for dr, dc in DIRS8:
                for d in range(1, QUEEN_MOVE + 1):
                    danger.add((r + dr * d, c + dc * d))
    return danger


def _threateners(known, me, king):
    """킹 칸을 위협하는 적들의 위치 집합."""
    kc = (king['r'], king['c'])
    return {(e[0], e[1]) for e in known if kc in _threat_cells([e], me)}


def _evade_king(st, me, king, danger, known):
    """킹을 안전한 칸으로 대피. 부쉬(은신) > 적에게서 멂 > 내 진영 쪽. 안전한 수 없으면 None."""
    safe = [m for m in pieces.legal_moves(st, king['id']) if m not in danger]
    if not safe:
        return None
    own_back = 11 if me == 'W' else 0

    def score(m):
        r, c = m
        s = (3.0 if len(pieces.bush_cluster(r, c)) == 1 else 2.2) if (r, c) in BUSHES else 0.0   # 부쉬로 숨으면 최고 — 홀로 떨어진 부쉬가 더 안전(같은 덤불에 들어오면 서로 보이는 롤식 규칙)
        if known:
            s += min(abs(r - e[0]) + abs(c - e[1]) for e in known) * 0.3
        s -= abs(r - own_back) * 0.1
        return s

    safe.sort(key=lambda m: -score(m))
    return ('move', king['id'], safe[0][0], safe[0][1])


# ------------------------- 공격 후보 -------------------------
def _attack_candidates(st, me, enemies):
    """지금 보이는 적을 상대로 한 공격 후보 [(score, kind, pid, r, c)]."""
    mine = _mine(st, me)
    vis_enemy = {(r, c) for (r, c, _) in enemies}
    cands = []
    for (er, ec, et) in enemies:
        val = VALUE.get(et, 1)
        kbonus = 500 if et == 'K' else 0
        for p in mine:                                   # 멜리(값싼 기물 선호, 킹은 회피)
            if (er, ec) in pieces.legal_moves(st, p['id']):
                cands.append((val * 10 + kbonus - VALUE[p['t']] * 0.1,
                              'move', p['id'], er, ec))
        if et == 'K' or val >= 3:                        # 값진 표적을 비숍 저격(사거리5·시야에 든 적)
            for p in mine:
                if p['t'] == 'B' and (er - p['r']) ** 2 + (ec - p['c']) ** 2 <= BISHOP_RANGE ** 2:
                    cands.append((val * 9 + kbonus, 'fire', p['id'], er, ec))
    for p in mine:                                       # 전차 돌파사격(십자 첫 기물이 보이는 적)
        if p['t'] != 'R':
            continue
        for dr, dc in DIRS4:
            hit = _first_piece_in_line(st, p, dr, dc)
            if hit:
                r, c, q = hit
                if q['o'] != me and (r, c) in vis_enemy:
                    v = VALUE.get(q['t'], 1)
                    if q['t'] == 'K' or v >= 3:
                        cands.append((v * 9 + (500 if q['t'] == 'K' else 0),
                                      'barrage', p['id'], r, c))
    return cands


def _best(cands):
    cands.sort(key=lambda x: -x[0])
    _, kind, pid, r, c = cands[0]
    return (kind, pid, r, c)


# ------------------------- 통합 결정 -------------------------
def _core(st, me, view):
    """공통 뇌: (1)보이는 적 킹 즉살 (2)내 킹 위협 해소/회피 (3)보이는 적 공격.
    셋 다 없으면 None(→ 난이도별로 왕 사냥 로직으로)."""
    enemies = _enemies_from_view(view, me)          # 지금 보이는 적
    remembered = _remembered(st, me)                # 기억한 적(안 보이는 것 포함)
    known = enemies + [(r, c, t) for (r, c, t, _) in remembered]
    cands = _attack_candidates(st, me, enemies)

    win = [x for x in cands if x[0] >= WIN_SCORE]   # 1) 보이는 적 킹을 잡는 수
    if win:
        return _best(win)

    king = _my_king(st, me)                          # 2) 내 킹 위협 → 제거 or 회피
    if king:
        danger = _threat_cells(known, me)
        if (king['r'], king['c']) in danger:
            threateners = _threateners(known, me, king)
            kill_threat = [x for x in cands if (x[3], x[4]) in threateners]
            if kill_threat:
                return _best(kill_threat)
            ev = _evade_king(st, me, king, danger, known)
            if ev:
                return ev

    if cands:                                        # 3) 그 외 보이는 적 공격
        return _best(cands)

    if king and (king['r'], king['c']) not in BUSHES:   # 4) 선제 방어: 적이 근처면 미리 부쉬로 은신
        near = any(max(abs(e[0] - king['r']), abs(e[1] - king['c'])) <= KING_DANGER_RADIUS
                   for e in known)
        if near:
            ev = _evade_king(st, me, king, _threat_cells(known, me), known)
            if ev:
                return ev
    return None


def _decide(st, me, *, hunt, abilities, mm_budget, mm_quiesce, mm_remembered, blunder=0.0):
    """난이도 공통 결정 엔진. hunt=부쉬 수색/정찰, abilities=전차·퀸 소탕, mm_*=미니맥스 강도."""
    view = pieces.player_view(st, me)
    _update_memory(st, me, view)
    if hunt:
        _update_scout(st, me, view)
    # All decision paths, including tactical heuristics, get only observable occupancy.
    st.setdefault('botscan', {})
    for key in ('botswept', 'botscanned'):
        st.setdefault(key, {}).setdefault(me, {})
    st = pieces.observed_state(st, me)
    core = _core(st, me, view)                                   # 승리/킹방어/보이는 적 공격
    if core:
        return core                                             # 중요한 수(캡처·승리·방어)는 항상 정확
    if blunder and random.random() < blunder:                   # 그 외(수색·위치잡기)에서만 가끔 무작위 실수
        moves = _gen_moves(st, me)
        if moves:
            mv = random.choice(moves)
            return ('move', mv[0], mv[1], mv[2])
    if not hunt:                                                # 쉬움: 왕 사냥 안 함(무계획 전진)
        return _advance(st, me, _enemies_from_view(view, me), _remembered(st, me))
    kcands = _candidates(st, me)                                 # 왕 사냥
    enter = _enter_bush(st, me, kcands)
    if enter:
        return enter
    if abilities:
        flush = _barrage_flush(st, me, kcands)
        if flush:
            return flush
        scan = _scan_hunt(st, me, kcands)
        if scan:
            return scan
    if mm_budget > 0:                                           # 미니맥스로 위치잡기
        mv = _best_minimax_move(st, me, mm_budget, kcands,
                                quiesce=mm_quiesce, model_remembered=mm_remembered)
        if mv:
            return ('move', mv[0], mv[1], mv[2])
    return (_scout_move(st, me, kcands)
            or _advance(st, me, _enemies_from_view(view, me), _remembered(st, me)))


def choose_action(st, me, budget=BOT_NORMAL_BUDGET):
    """보통(~1500): 왕 사냥 + 킹 방어 + 능력(퀸 스캔·전차 돌파, 템포 보호형) + 중간 깊이 미니맥스(실수 없음)."""
    return _decide(st, me, hunt=True, abilities=True,
                   mm_budget=budget, mm_quiesce=0, mm_remembered=False, blunder=0.0)


def _advance(st, me, enemies, remembered):
    mine = _mine(st, me)
    if enemies:                                     # 보이는 적 무게중심으로
        pts = [(e[0], e[1]) for e in enemies]
    elif remembered:                                # 없으면 기억한 위치로 추격
        pts = [(e[0], e[1]) for e in remembered]
    else:                                           # 그것도 없으면 적 진영으로 전진
        pts = [(0 if me == 'W' else 11, 5)]
    tr = sum(p[0] for p in pts) / len(pts)
    tc = sum(p[1] for p in pts) / len(pts)
    best, best_s = None, None
    for p in mine:
        if p['t'] == 'K':                           # 킹은 숨겨둠 — 전진 안 함
            continue
        for (mr, mc) in pieces.legal_moves(st, p['id']):
            s = (abs(p['r'] - tr) + abs(p['c'] - tc)) - (abs(mr - tr) + abs(mc - tc))
            if p['t'] == 'N':
                s += 0.3                            # 나이트 정찰 선호(시야 3)
            s += ((p['r'] * 7 + p['c'] * 13 + mr * 3 + mc) % 5) * 0.01
            if best_s is None or s > best_s:
                best_s, best = s, ('move', p['id'], mr, mc)
    if best:
        return best
    for p in mine:                                  # 폴백: 아무 합법수(킹 포함)
        lm = pieces.legal_moves(st, p['id'])
        if lm:
            return ('move', p['id'], lm[0][0], lm[0][1])
    return None


# ------------------------- 미니맥스 + 알파베타 (어려움) -------------------------
# 불완전정보라 '내가 보는' 것만 쓴다: 상대 노드에선 '지금 보이는 적'만 움직인다고 가정(공정).
def _clone(st):
    """탐색용 경량 복제(로그·피드 등 장식은 뺌 → deepcopy보다 훨씬 빠름)."""
    return {'pieces': {k: dict(v) for k, v in st['pieces'].items()},
            'phase': st['phase'], 'turn': st['turn'], 'turnCount': st['turnCount'],
            'winner': st['winner'], 'reveals': [dict(x) for x in st['reveals']],
            'feed': [], 'feedseq': st['feedseq'], 'fx': None, 'fxseq': st['fxseq'],
            'log': [], 'ready': dict(st.get('ready', {})), 'deadline': None,
            'promote': st.get('promote'), '_prediction': True,
            'scans': [dict(x) for x in st.get('scans', [])],
            'misses': dict(st.get('misses', {'W': 0, 'B': 0}))}


def _terminal_eval(st, me):
    if st['phase'] != 'over':
        return None
    w = st['winner']
    if w == me:
        return 1e6
    if w and w != 'draw':
        return -1e6
    return 0.0


def _evaluate(st, me, kbush=None, known=None):
    """정적 평가 — 물량 + 왕 사냥 위치 + 킹 안전. 적 실제위치는 '알려진 적(known)'만 사용(치트 방지)."""
    t = _terminal_eval(st, me)
    if t is not None:
        return t
    s = 0.0
    half = set(_enemy_half(me))
    king = None
    for p in st['pieces'].values():
        if not p['alive']:
            continue
        v = VALUE.get(p['t'], 1)
        if p['o'] == me:
            s += v
            if p['t'] == 'K':
                king = p
            else:
                adv = (N - 1 - p['r']) if me == 'W' else p['r']    # 적 진영에 가까울수록 +
                s += adv * 0.03
                if p['r'] in half:
                    s += 0.3                                        # 적진 진입(수색 위치) — 공격적으로
                if kbush:                                           # 미확인 후보 부쉬에 근접(수색 압박)
                    nb = min(abs(p['r'] - br) + abs(p['c'] - bc) for (br, bc) in kbush)
                    s += max(0.0, 1.0 - nb * 0.12)
        else:
            s -= v
    if king:                                                        # ── 킹 안전(은신·수비·이격) ──
        kr, kc = king['r'], king['c']
        if (kr, kc) in BUSHES:
            s += KING_SAFE_W                                        # 부쉬 은신
        guards = sum(1 for p in st['pieces'].values()
                     if p['alive'] and p['o'] == me and p['t'] != 'K'
                     and max(abs(p['r'] - kr), abs(p['c'] - kc)) <= 1)
        s += KING_SAFE_W * 0.25 * min(guards, KING_GUARD)          # 옆 수비 기물
        if known:                                                   # 알려진 적과 멀수록 안전
            ke = [st['pieces'][pid] for pid in known if pid in st['pieces'] and st['pieces'][pid]['alive']]
            if ke:
                nd = min(max(abs(kr - e['r']), abs(kc - e['c'])) for e in ke)
                s += KING_SAFE_W * min(nd, 5) * 0.08
    return s


def _gen_moves(st, side, only_pids=None):
    out = []
    for p in st['pieces'].values():
        if not p['alive'] or p['o'] != side:
            continue
        if only_pids is not None and p['id'] not in only_pids:
            continue
        for (r, c) in pieces.legal_moves(st, p['id']):
            out.append((p['id'], r, c))
    return out


def _capture_value(st, mv):
    q = pieces.piece_at(st, mv[1], mv[2])
    return VALUE.get(q['t'], 0) if q is not None else 0


def _known_enemy_pids(st, me):
    """내가 지금 볼 수 있는 적 기물 id 집합(부쉬·안개 반영). 탐색에서 이들만 움직인다고 가정."""
    vis = pieces.visible_cells(st, me)
    out = set()
    for p in st['pieces'].values():
        if p['alive'] and p['o'] != me and pieces.enemy_visible_at(st, me, p['r'], p['c'], vis):
            out.add(p['id'])
    return out


def _remembered_pids(st, me):
    """기억한 적 위치에 실제로 있는 살아있는 적 기물 id — 미니맥스 상대 모델 확장(위협 응수)."""
    out = set()
    for (r, c) in st.get('botmem', {}).get(me, {}):
        q = pieces.piece_at(st, r, c)
        if q is not None and q['o'] != me and q['alive']:
            out.add(q['id'])
    return out


def _guard_pids(st, me):
    """킹에 가장 가까운 비-킹 기물 KING_GUARD개 = 수비대(정찰하러 멀리 안 보냄)."""
    king = _my_king(st, me)
    if not king:
        return set()
    mine = [p for p in _mine(st, me) if p['t'] != 'K']
    mine.sort(key=lambda p: max(abs(p['r'] - king['r']), abs(p['c'] - king['c'])))
    return {p['id'] for p in mine[:KING_GUARD]}


def _do(st, side, mv):
    """탐색용 이동 적용(승격은 전차 자동)."""
    pieces.apply_move(st, side, mv[0], mv[1], mv[2])
    if st.get('promote') and st['promote']['color'] == side:
        pieces.apply_promote(st, side, 'R')


def _quiesce(st, me, alpha, beta, maximizing, known, deadline, kbush, qdepth):
    """정지 탐색: 깊이 끝에서 '캡처만' 더 봐서 되잡힘(호라이즌 함정) 완화. stand-pat 컷."""
    t = _terminal_eval(st, me)
    if t is not None:
        return t
    stand = _evaluate(st, me, kbush, known)
    if qdepth <= 0 or time.time() > deadline:
        return stand
    side = me if maximizing else ('B' if me == 'W' else 'W')
    caps = [mv for mv in _gen_moves(st, side, None if maximizing else known)
            if _capture_value(st, mv) > 0]
    if not caps:
        return stand
    caps.sort(key=lambda mv: -_capture_value(st, mv))
    if maximizing:
        best = stand
        if best >= beta:
            return best
        alpha = max(alpha, best)
        for mv in caps:
            ns = _clone(st); _do(ns, side, mv)
            best = max(best, _quiesce(ns, me, alpha, beta, False, known, deadline, kbush, qdepth - 1))
            alpha = max(alpha, best)
            if alpha >= beta or time.time() > deadline:
                break
        return best
    best = stand
    if best <= alpha:
        return best
    beta = min(beta, best)
    for mv in caps:
        ns = _clone(st); _do(ns, side, mv)
        best = min(best, _quiesce(ns, me, alpha, beta, True, known, deadline, kbush, qdepth - 1))
        beta = min(beta, best)
        if alpha >= beta or time.time() > deadline:
            break
    return best


def _minimax(st, me, depth, alpha, beta, maximizing, known, deadline, kbush, qdepth):
    t = _terminal_eval(st, me)
    if t is not None:
        return t
    if time.time() > deadline:
        return _evaluate(st, me, kbush, known)
    if depth == 0:                                              # 깊이 끝 → 정지탐색(또는 정적 평가)
        return (_quiesce(st, me, alpha, beta, maximizing, known, deadline, kbush, qdepth)
                if qdepth > 0 else _evaluate(st, me, kbush, known))
    side = me if maximizing else ('B' if me == 'W' else 'W')
    moves = _gen_moves(st, side, None if maximizing else known)
    if not moves:
        return _evaluate(st, me, kbush, known)
    moves.sort(key=lambda mv: -_capture_value(st, mv))          # 잡는 수 먼저 → 가지치기↑
    if maximizing:
        best = -1e9
        for mv in moves:
            ns = _clone(st); _do(ns, side, mv)
            best = max(best, _minimax(ns, me, depth - 1, alpha, beta, False, known, deadline, kbush, qdepth))
            alpha = max(alpha, best)
            if beta <= alpha or time.time() > deadline:
                break
        return best
    best = 1e9
    for mv in moves:
        ns = _clone(st); _do(ns, side, mv)
        best = min(best, _minimax(ns, me, depth - 1, alpha, beta, True, known, deadline, kbush, qdepth))
        beta = min(beta, best)
        if beta <= alpha or time.time() > deadline:
            break
    return best


def _best_minimax_move(st, me, budget, kcands=None, quiesce=0, model_remembered=False):
    """반복심화 미니맥스. quiesce>0=정지탐색 깊이, model_remembered=상대 모델에 기억한 적 포함.
    kcands의 부쉬 좌표를 평가(왕 사냥 위치)에 사용."""
    st = pieces.observed_state(st, me)
    moves = _gen_moves(st, me)
    if not moves:
        return None
    known = _known_enemy_pids(st, me)
    if model_remembered:                                       # 상대가 '기억한 위협'에도 응수한다고 가정
        known = known | _remembered_pids(st, me)
    kbush = [(r, c) for (r, c, w) in (kcands or []) if (r, c) in BUSHES] or None
    deadline = time.time() + budget
    best = moves[0]
    for depth in range(1, MINIMAX_MAX_DEPTH + 1):
        cur_best, cur_mv, alpha = -1e9, None, -1e9
        ordered = sorted(moves, key=lambda mv: -_capture_value(st, mv))
        if best in ordered:                                    # 직전 최선 먼저 탐색(반복심화 정렬)
            ordered.remove(best); ordered.insert(0, best)
        finished = True
        for mv in ordered:
            if time.time() > deadline:
                finished = False; break
            ns = _clone(st); _do(ns, me, mv)
            val = _minimax(ns, me, depth - 1, alpha, 1e9, False, known, deadline, kbush, quiesce)
            if val > cur_best:
                cur_best, cur_mv = val, mv
            alpha = max(alpha, cur_best)
        if cur_mv is not None and finished:
            best = cur_mv
        if not finished:
            break
    return best


# ------------------------- 난이도별 선택 -------------------------
def choose_action_easy(st, me, budget=BOT_EASY_BUDGET):
    """쉬움(~1300): 왕 사냥 + 킹 방어 + 능력 사용 + 가벼운 미니맥스 + 아주 가끔의 실수.
    (예전엔 왕 사냥·탐색을 모두 꺼 왕을 못 찾는 수준이었음 — 하한을 1300급으로 끌어올림.)"""
    return _decide(st, me, hunt=True, abilities=True,
                   mm_budget=budget, mm_quiesce=0, mm_remembered=False,
                   blunder=BOT_EASY_BLUNDER)


def choose_action_hard(st, me, budget=BOT_HARD_BUDGET):
    """어려움(~1800): 공격적 왕 사냥 + 킹 방어 + 능력(퀸 스캔·전차 돌파) + 깊은 미니맥스(시간 많이)
    + 정지탐색(캡처 연쇄를 더 읽어 되잡힘/호라이즌 함정 완화) + 실수 없음.
    (기억한적 상대모델은 봇끼리 검증 결과 소극적이 돼 제외. 능력은 예전엔 매 턴 스캔/포격으로 템포를
    잃어 껐었는데, _scan_hunt/_barrage_flush에 템포 보호를 넣은 뒤 다시 켬 — 토너먼트로 검증.)"""
    return _decide(st, me, hunt=True, abilities=True,
                   mm_budget=budget, mm_quiesce=QUIESCENCE_DEPTH, mm_remembered=False)


# ------------------------- 실행 -------------------------
def act(st, me, level='normal'):
    """봇이 한 수 둔다(적용은 pieces.apply_*에 위임). level: easy|normal|hard."""
    if st.get('promote') and st['promote']['color'] == me:   # 승격 대기면 전차로 승격
        pieces.apply_promote(st, me, 'R')
        return True
    if level == 'easy':
        action = choose_action_easy(st, me)
    elif level == 'hard':
        action = choose_action_hard(st, me)
    else:
        action = choose_action(st, me)
    if not action:
        return False
    kind, pid, r, c = action
    if kind == 'move':
        ok, _ = pieces.apply_move(st, me, pid, r, c)
    elif kind == 'fire':
        ok, _ = pieces.apply_fire(st, me, pid, r, c)
    elif kind == 'barrage':
        ok, _ = pieces.apply_barrage(st, me, pid, r, c)
    elif kind == 'scan':
        ok, _ = pieces.apply_scan(st, me, pid, r, c)
    else:
        ok = False
    return ok
