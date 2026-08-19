# -*- coding: utf-8 -*-
"""
AI 봇 상대 — 서버가 '봇 차례'에 이 모듈을 불러 자동으로 응수한다.

설계 원칙: 봇은 '자기 안개 시야(player_view) + 기억'만 보고 판단한다(포그 오브 워 준수).
전체 보드를 훔쳐보지 않는다. 규칙 판정·적용은 pieces.py에 위임한다.

우선순위(choose_action):
  1) 보이는 적 킹을 잡는/포격하는 수 → 무조건(게임 끝)
  2) 내 킹이 위협받으면 → 위협 기물 제거 or 안전한 칸(부쉬)으로 회피
  3) 그 외 공격(멜리 캡처 / 비숍 곡사 / 전차 돌파사격, 값진 표적 우선)
     + 기억한 적 킹 위치를 비숍으로 포격 수색
  4) 표적 없음 → 전진·정찰(기억한 적 위치로 추격, 나이트 우선, 킹은 숨김)

기억(st['botmem']): {(r,c): {'t':종류,'seen':턴}} — 시야에 든 칸은 매 턴 갱신·삭제.
"""
from config import BISHOP_RANGE, ROOK_RANGE, ZONE
from game_map import FORESTS, BUSHES, in_board
import pieces

VALUE = {'K': 1000, 'R': 5, 'B': 4, 'N': 3, 'P': 1}
KNIGHT = [(-2, -1), (-2, 1), (2, -1), (2, 1), (-1, -2), (-1, 2), (1, -2), (1, 2)]
MEM_TTL = 6          # 기억 유효 턴 수(이보다 오래되면 잊음)
WIN_SCORE = 9500     # 이 점수 이상 = '보이는 적 킹을 잡는 수'


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


def _splash_safe(st, me, tr, tc):
    """비숍 곡사 착탄(X자 5칸)에 아군이 없으면 True — 자책 방지."""
    for dr, dc in pieces.SPLASH:
        q = pieces.piece_at(st, tr + dr, tc + dc)
        if q is not None and q['o'] == me:
            return False
    return True


def _first_piece_in_line(st, p, dr, dc):
    """전차 사격 방향으로 처음 만나는 기물 (r, c, piece). 숲/보드밖이면 None."""
    for dist in range(1, ROOK_RANGE + 1):
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
        elif t == 'B':                                 # 곡사: 반경 BISHOP_RANGE 원 안
            R = BISHOP_RANGE
            for dr in range(-R, R + 1):
                for dc in range(-R, R + 1):
                    if dr * dr + dc * dc <= R * R:
                        danger.add((r + dr, c + dc))
        elif t == 'R':                                 # 돌파사격: 4방향 직선(숲에 막힘)
            for dr, dc in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
                for d in range(1, ROOK_RANGE + 1):
                    rr, cc = r + dr * d, c + dc * d
                    if not in_board(rr, cc) or (rr, cc) in FORESTS:
                        break
                    danger.add((rr, cc))
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
        s = 3.0 if (r, c) in BUSHES else 0.0                     # 부쉬로 숨으면 최고(적이 못 봄)
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
        if et == 'K' or val >= 3:                        # 값진 표적만 노출 감수하고 곡사
            for p in mine:
                if p['t'] == 'B' and (er - p['r']) ** 2 + (ec - p['c']) ** 2 <= BISHOP_RANGE ** 2 \
                        and _splash_safe(st, me, er, ec):
                    cands.append((val * 9 + kbonus, 'fire', p['id'], er, ec))
    for p in mine:                                       # 전차 돌파사격(방향 첫 기물이 보이는 적)
        if p['t'] != 'R':
            continue
        for dr, dc in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
            hit = _first_piece_in_line(st, p, dr, dc)
            if hit:
                r, c, q = hit
                if q['o'] != me and (r, c) in vis_enemy:
                    v = VALUE.get(q['t'], 1)
                    if q['t'] == 'K' or v >= 3:
                        cands.append((v * 9 + (500 if q['t'] == 'K' else 0),
                                      'barrage', p['id'], r, c))
    return cands


def _memory_king_shots(st, me, remembered):
    """기억한 적 킹 위치(신선한 것)를 비숍 곡사로 수색 포격 — 부쉬에 숨은 킹 노림."""
    out = []
    now = st['turnCount']
    for (r, c, t, seen) in remembered:
        if t != 'K' or now - seen > MEM_TTL:
            continue
        for p in _mine(st, me):
            if p['t'] == 'B' and (r - p['r']) ** 2 + (c - p['c']) ** 2 <= BISHOP_RANGE ** 2 \
                    and _splash_safe(st, me, r, c):
                out.append((1000 * 8, 'fire', p['id'], r, c))   # 승리수(9500)보단 낮게(빗나갈 수 있음)
    return out


def _best(cands):
    cands.sort(key=lambda x: -x[0])
    _, kind, pid, r, c = cands[0]
    return (kind, pid, r, c)


# ------------------------- 통합 결정 -------------------------
def choose_action(st, me):
    view = pieces.player_view(st, me)
    _update_memory(st, me, view)
    enemies = _enemies_from_view(view, me)          # 지금 보이는 적
    remembered = _remembered(st, me)                # 기억한 적(안 보이는 것 포함)
    known = enemies + [(r, c, t) for (r, c, t, _) in remembered]

    cands = _attack_candidates(st, me, enemies) + _memory_king_shots(st, me, remembered)

    # 1) 보이는 적 킹을 잡는 수 → 무조건
    win = [x for x in cands if x[0] >= WIN_SCORE]
    if win:
        return _best(win)

    # 2) 내 킹이 위협받으면 → 위협 제거 or 회피
    king = _my_king(st, me)
    if king:
        danger = _threat_cells(known, me)
        if (king['r'], king['c']) in danger:
            threateners = _threateners(known, me, king)
            kill_threat = [x for x in cands if (x[3], x[4]) in threateners]
            if kill_threat:
                return _best(kill_threat)           # 위협하는 놈을 잡아 해소
            ev = _evade_king(st, me, king, danger, known)
            if ev:
                return ev                           # 안전한 칸(부쉬)으로 대피

    # 3) 그 외 공격
    if cands:
        return _best(cands)

    # 4) 표적 없음 → 전진/정찰(기억 추격)
    return _advance(st, me, enemies, remembered)


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
                s += 0.3                            # 나이트 정찰 선호(시야 2)
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


# ------------------------- 실행 -------------------------
def act(st, me):
    """봇이 한 수 둔다(적용은 pieces.apply_*에 위임). 둔 수가 있으면 True."""
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
    else:
        ok = False
    return ok
