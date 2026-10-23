# -*- coding: utf-8 -*-
"""
기물 / 규칙 엔진 — 기물 정의, 행마(합법수), 이동/포격/돌파사격, 킬로그,
안개(포그) 시야 계숲, 플레이어별 뷰(player_view)를 담당한다.
게임 상태 st(dict) 하나를 인자로 받아 조작한다(방/네트워크는 server.py).
"""
import time
import random

from config import (N, VISION, KING_LIVES, ROOK_RANGE, ROOK_FIRE, BISHOP_MOVE,
                    BISHOP_RANGE, QUEEN_MOVE, SCAN_RANGE, SCAN_DUR, MUZZLE,
                    ZONE, TURN_LIMIT, TURN_SECONDS, SETUP_SECONDS, MAX_MISSES)
from game_map import FORESTS, RIVERS, BUSHES, IMPASSABLE, in_board, los_clear

# 비숍 X자 5칸 착탄 / 폰 전진 방향 / 한글 이름
SPLASH = [(0, 0), (-1, -1), (-1, 1), (1, -1), (1, 1)]
DIRS4 = [(-1, 0), (1, 0), (0, -1), (0, 1)]  # 룩 십자(상하좌우) 사격
DIRS8 = DIRS4 + [(-1, -1), (-1, 1), (1, -1), (1, 1)]  # 퀸 8방향 이동
FORWARD = {'W': -1, 'B': 1}
PIECE_KR = {'K': '킹', 'R': '전차', 'B': '비숍', 'N': '나이트', 'P': '폰', 'Q': '퀸'}
SIDE_KR = {'W': '백', 'B': '흑'}


# ------------------------- 상태 생성 -------------------------
def default_pieces():
    """기본 포진(백): 룩2 나이트2 비숍2 퀸1 폰8 킹1 = 16. 흑은 180도 대칭."""
    p = {}
    counter = {}

    def add(t, owner, r, c):
        counter[(owner, t)] = counter.get((owner, t), 0) + 1
        pid = f'{owner}_{t}{counter[(owner, t)]}'
        p[pid] = {'id': pid, 't': t, 'o': owner, 'r': r, 'c': c,
                  'alive': True, 'lives': KING_LIVES if t == 'K' else 1,
                  'moved': False}

    back = [('R', 2), ('N', 3), ('B', 4), ('Q', 5), ('K', 6), ('B', 7), ('N', 8), ('R', 9)]
    for (t, c) in back:
        add(t, 'W', 11, c)
        add(t, 'B', 0, N - 1 - c)
    for c in range(2, 10):  # 폰 8개
        add('P', 'W', 10, c)
        add('P', 'B', 1, N - 1 - c)
    return p


def new_game():
    return {
        'phase': 'setup',           # setup -> play -> over
        'turn': 'W',
        'turnCount': 0,
        'pieces': default_pieces(),
        'ready': {'W': False, 'B': False},
        'deadline': None,           # 배치 마감 시각(epoch)
        'turn_deadline': None,      # 현재 턴 마감 시각(epoch) — 플레이 중 TURN_SECONDS
        'started_at': None,         # 전투 시작 시각(epoch) — 경과 시간 표시
        'misses': {'W': 0, 'B': 0}, # 연속 미행동(시간초과 자동 넘김) 횟수 — 자기 수를 두면 0으로 리셋
        'reveals': [],              # {pid, viewer, until}
        'feed': [],                 # 킬로그 {seq, actor, atype, method, victim, vtype}
        'feedseq': 0,
        'fx': None,                 # {seq, type, cells, actor}
        'fxseq': 0,
        'log': ['방 생성됨 — 친구가 접속하면 배치가 시작됩니다.'],
        'winner': None,             # 'W'/'B' 승자, 또는 'draw'
        'promote': None,            # 승격 대기 {pid, color} — 폰이 끝줄 도달 시
        'scans': [],                # 활성 퀸 스캔 [{viewer, cells, until}] — 그 2×2를 감시
    }


# ------------------------- 유틸 -------------------------
def piece_at(st, r, c):
    for p in st['pieces'].values():
        if p['alive'] and p['r'] == r and p['c'] == c:
            return p
    return None


def count_alive(st, color):
    return sum(1 for p in st['pieces'].values() if p['alive'] and p['o'] == color)


DEAD_ORDER = 'KQRBNP'


def dead_types(st, color):
    """color 쪽에서 죽은 기물의 종류 목록(가치 순). 상대가 잡은 내 기물 = 상대의 전리품 표시에 쓴다."""
    return sorted([p['t'] for p in st['pieces'].values() if p['o'] == color and not p['alive']], key=DEAD_ORDER.index)


# ------------------------- 안개(시야) -------------------------
def bush_cluster(r, c):
    """(r,c)가 속한 부쉬 덤불(상하좌우로 붙은 부쉬 칸 전체). 부쉬가 아니면 빈 집합."""
    if (r, c) not in BUSHES:
        return set()
    seen, stack = {(r, c)}, [(r, c)]
    while stack:
        cr, cc = stack.pop()
        for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (cr + dr, cc + dc)
            if n in BUSHES and n not in seen:
                seen.add(n); stack.append(n)
    return seen


def bush_shared_cells(st, color):
    """롤식 부쉬: color의 기물이 서 있는 덤불 전체 — 그 안의 기물은 서로 보인다(밖에서는 여전히 안 보임)."""
    out = set()
    for p in st['pieces'].values():
        if p['alive'] and p['o'] == color and (p['r'], p['c']) in BUSHES:
            out |= bush_cluster(p['r'], p['c'])
    return out


def visible_cells(st, color):
    vis = set()
    srcs = []
    for p in st['pieces'].values():
        if p['alive'] and p['o'] == color:
            srcs.append((p['r'], p['c'], VISION[p['t']]))
    for rv in st['reveals']:                   # 공격으로 노출된 적: 그 기물 '칸'만 보인다(반경 0).
        if rv['viewer'] == color and st['turnCount'] < rv['until']:   #  예전엔 반경 1이라 적 주변 칸·숲 뒤까지 밝아져 '시야 버그'처럼 보였음
            q = st['pieces'].get(rv['pid'])
            if q and q['alive']:
                srcs.append((q['r'], q['c'], 0))
    for (pr, pc, rad) in srcs:
        for dr in range(-rad, rad + 1):
            for dc in range(-rad, rad + 1):
                r, c = pr + dr, pc + dc
                if in_board(r, c) and los_clear(pr, pc, r, c):
                    vis.add((r, c))
    for s in st.get('scans', []):              # 스캔 감시 지역(레이더 — 시야차단 무시)
        if s['viewer'] == color and st['turnCount'] < s['until']:
            for (r, c) in s['cells']:
                if in_board(r, c):
                    vis.add((r, c))
    vis |= bush_shared_cells(st, color)       # 내가 들어가 있는 덤불 안은 전부 보임(롤식)
    return vis



def revealed(st, color, pid):
    for rv in st['reveals']:
        if rv['pid'] == pid and rv['viewer'] == color and st['turnCount'] < rv['until']:
            return True
    return False


def scanning(st, color, r, c):
    """color가 지금 (r,c)를 퀸 스캔으로 감시 중이면 True."""
    for s in st.get('scans', []):
        if s['viewer'] == color and st['turnCount'] < s['until'] and (r, c) in s['cells']:
            return True
    return False


def enemy_visible_at(st, color, r, c, vis=None):
    """(r,c)에 color가 '실제로 볼 수 있는' 적 기물이 있으면 반환, 아니면 None.
    부쉬 은폐·안개·숲 시야차단을 적용하되, 스캔 감시 지역은 부쉬도 뚫어본다."""
    q = piece_at(st, r, c)
    if q is None or q['o'] == color:
        return None
    if revealed(st, color, q['id']) or scanning(st, color, r, c):
        return q                               # 노출됐거나 내가 스캔 중이면 보임(부쉬 무시)
    if (r, c) in BUSHES and (r, c) not in bush_shared_cells(st, color):   # 부쉬 속 적: 같은 덤불에 있지 않으면 저격 불가
        return None
    if vis is None:
        vis = visible_cells(st, color)
    return q if (r, c) in vis else None


def add_reveal(st, pid, viewer, dur):
    st['reveals'].append({'pid': pid, 'viewer': viewer, 'until': st['turnCount'] + dur})


def set_fx(st, ftype, cells, actor):
    st['fxseq'] += 1
    st['fx'] = {'seq': st['fxseq'], 'type': ftype, 'cells': cells, 'actor': actor}


# ------------------------- 합법수(행마) -------------------------
def legal_moves(st, pid):
    p = st['pieces'].get(pid)
    if not p or not p['alive']:
        return []
    t, o, r, c = p['t'], p['o'], p['r'], p['c']
    out = []

    def own_at(rr, cc):
        q = piece_at(st, rr, cc)
        return q is not None and q['o'] == o

    if t == 'P':
        fr = FORWARD[o]
        r1 = r + fr
        if in_board(r1, c) and (r1, c) not in IMPASSABLE and piece_at(st, r1, c) is None:
            out.append((r1, c))
            r2 = r + 2 * fr
            if (not p['moved'] and in_board(r2, c) and (r2, c) not in IMPASSABLE
                    and piece_at(st, r2, c) is None):
                out.append((r2, c))
        for dc in (-1, 1):
            nr, nc = r, c + dc
            if in_board(nr, nc) and (nr, nc) not in IMPASSABLE and not own_at(nr, nc):
                out.append((nr, nc))
        for dc in (-1, 1):
            nr, nc = r + fr, c + dc
            if in_board(nr, nc) and (nr, nc) not in IMPASSABLE and not own_at(nr, nc):
                out.append((nr, nc))
    elif t == 'N':
        for dr, dc in [(-2, -1), (-2, 1), (2, -1), (2, 1), (-1, -2), (-1, 2), (1, -2), (1, 2)]:
            nr, nc = r + dr, c + dc
            if in_board(nr, nc) and (nr, nc) not in IMPASSABLE and not own_at(nr, nc):
                out.append((nr, nc))
    elif t == 'K':
        for dr in (-1, 0, 1):
            for dc in (-1, 0, 1):
                if dr or dc:
                    nr, nc = r + dr, c + dc
                    if in_board(nr, nc) and (nr, nc) not in IMPASSABLE and not own_at(nr, nc):
                        out.append((nr, nc))
    elif t == 'B':
        for dr, dc in [(-1, -1), (-1, 1), (1, -1), (1, 1)]:
            for dist in range(1, BISHOP_MOVE + 1):
                nr, nc = r + dr * dist, c + dc * dist
                if not in_board(nr, nc) or (nr, nc) in IMPASSABLE:
                    break
                q = piece_at(st, nr, nc)
                if q is None:
                    out.append((nr, nc))
                    continue
                if q['o'] != o:
                    out.append((nr, nc))
                break
    elif t == 'R':
        for dr, dc in DIRS4:
            for dist in range(1, ROOK_RANGE + 1):
                nr, nc = r + dr * dist, c + dc * dist
                if not in_board(nr, nc) or (nr, nc) in IMPASSABLE:
                    break
                q = piece_at(st, nr, nc)
                if q is None:
                    out.append((nr, nc))
                    continue
                if q['o'] != o:
                    out.append((nr, nc))
                break
    elif t == 'Q':
        for dr, dc in DIRS8:                          # 8방향 최대 QUEEN_MOVE칸
            for dist in range(1, QUEEN_MOVE + 1):
                nr, nc = r + dr * dist, c + dc * dist
                if not in_board(nr, nc) or (nr, nc) in IMPASSABLE:
                    break
                q = piece_at(st, nr, nc)
                if q is None:
                    out.append((nr, nc))
                    continue
                if q['o'] != o:
                    out.append((nr, nc))
                break
    return out


def observed_state(st, color):
    """Decision input containing own pieces and currently observed enemies only.
    Unknown pieces are omitted, not marked dead. Terrain and own memory are public/owned.
    Never pass this prediction state back to the authoritative room.
    """
    vis = visible_cells(st, color)
    result = dict(st)
    result['pieces'] = {pid: dict(p) for pid, p in st['pieces'].items()
                        if p['alive'] and (p['o'] == color or
                           enemy_visible_at(st, color, p['r'], p['c'], vis))}
    result['reveals'] = [dict(rv) for rv in st['reveals'] if rv['pid'] in result['pieces']]
    result['_prediction'] = True
    return result


def move_candidates(st, pid):
    """UI/bot requests must not disclose unknown occupancy through missing destinations."""
    p = st['pieces'].get(pid)
    if not p or not p['alive'] or st.get('promote'):
        return []
    return legal_moves(st if st.get('_prediction') else observed_state(st, p['o']), pid)


def is_reloading(st, pid):
    """A shot blocks the next own turn; movement or timeout advances reload.

    Shot at ply n -> opponent n+1 -> own n+2 (blocked) -> opponent n+3 (ready).
    The piece carries this state through bot copies and replay snapshots.
    """
    p = st['pieces'].get(pid)
    return bool(p and p['alive'] and p['t'] in ('B', 'R')
                and st['turnCount'] < p.get('reload_until', 0))


def fire_cells(st, pid):
    """비숍이 지금 저격할 수 있는 '표적 칸' 목록 — 사거리 BISHOP_RANGE 안 + 시야에 든 적만.
    (원형 전 범위가 아니라, 실제로 명중 가능한 적 위치만 하이라이트)."""
    p = st['pieces'].get(pid)
    if not p or p['t'] != 'B' or not p['alive'] or is_reloading(st, pid):
        return []
    color = p['o']
    R2 = BISHOP_RANGE ** 2
    vis = visible_cells(st, color)
    out = []
    for q in st['pieces'].values():
        if q['alive'] and q['o'] != color:
            if (q['r'] - p['r']) ** 2 + (q['c'] - p['c']) ** 2 <= R2 \
                    and enemy_visible_at(st, color, q['r'], q['c'], vis):
                out.append((q['r'], q['c']))
    return out


def fire_range(st, pid):
    """비숍의 저격 '사거리 원' 전체(반경 BISHOP_RANGE, 숲 제외) — 표시용.
    실제 명중은 이 안에서 '보이는 적'(fire_cells)만. 사거리는 늘 보여주되,
    표적이 없으면 '사거리 안에 보이는 적이 없다'는 걸 직관적으로 알린다."""
    p = st['pieces'].get(pid)
    if not p or p['t'] != 'B' or not p['alive']:
        return []
    R2 = BISHOP_RANGE ** 2
    out = []
    for dr in range(-BISHOP_RANGE, BISHOP_RANGE + 1):
        for dc in range(-BISHOP_RANGE, BISHOP_RANGE + 1):
            if (dr or dc) and dr * dr + dc * dc <= R2:
                r, c = p['r'] + dr, p['c'] + dc
                if in_board(r, c) and (r, c) not in FORESTS:
                    out.append((r, c))
    return out


def _orth(dr, dc):
    """상하좌우 직선이면 단위 방향, 아니면 None(대각 불가)."""
    if (dr == 0) == (dc == 0):
        return None
    return (0 if dr == 0 else (1 if dr > 0 else -1),
            0 if dc == 0 else (1 if dc > 0 else -1))


def barrage_reach(st, pid):
    p = st['pieces'].get(pid)
    if not p or p['t'] != 'R' or not p['alive'] or is_reloading(st, pid):
        return []
    cells = []
    for dr, dc in DIRS4:                          # 십자 4방향 × ROOK_FIRE칸(숲에 막힘)
        for dist in range(1, ROOK_FIRE + 1):
            r, c = p['r'] + dr * dist, p['c'] + dc * dist
            if not in_board(r, c) or (r, c) in FORESTS:
                break
            cells.append((r, c))
    return cells


def scan_cells(st, pid):
    """퀸이 스캔을 지정할 수 있는 칸(맨해튼 SCAN_RANGE 안) — 하이라이트용."""
    p = st['pieces'].get(pid)
    if not p or p['t'] != 'Q' or not p['alive']:
        return []
    out = []
    for dr in range(-SCAN_RANGE, SCAN_RANGE + 1):
        for dc in range(-SCAN_RANGE, SCAN_RANGE + 1):
            if abs(dr) + abs(dc) <= SCAN_RANGE:
                r, c = p['r'] + dr, p['c'] + dc
                if in_board(r, c):
                    out.append((r, c))
    return out


# ------------------------- 액션 적용 -------------------------
def advance_turn(st, real_move=True):
    if real_move:                                         # 실제로 수를 둔 사람은 미행동 카운터 리셋
        st.setdefault('misses', {'W': 0, 'B': 0})[st['turn']] = 0
    st['turnCount'] += 1
    st['turn'] = 'B' if st['turn'] == 'W' else 'W'
    if st.get('scans'):                                   # 만료된 스캔 감시 정리
        st['scans'] = [s for s in st['scans'] if st['turnCount'] < s['until']]
    if st['phase'] == 'play' and st['turnCount'] >= TURN_LIMIT:
        st['phase'] = 'over'
        st['winner'] = 'draw'
        st['log'].append(f"턴 한도({TURN_LIMIT}) 도달 — 무승부!")
    # 다음 턴 제한시간 세팅(게임이 계속될 때만)
    st['turn_deadline'] = (time.time() + TURN_SECONDS) if st['phase'] == 'play' else None


def time_out(st):
    """턴 제한시간 초과 — 그 턴은 자동으로 상대에게 넘긴다(기물은 그대로).
    연속 MAX_MISSES회(=TURN_SECONDS*MAX_MISSES초) 미행동이면 패배(상대 자동 승리)."""
    if st['phase'] != 'play':
        return False
    if st.get('promote'):
        st['log'].append('승격 선택 시간 초과 — 전차로 자동 승격합니다.')
        return apply_promote(st, st['turn'], 'R')[0]
    loser = st['turn']
    st['misses'][loser] = st['misses'].get(loser, 0) + 1
    n = st['misses'][loser]
    st['log'].append(f"⏳ {SIDE_KR[loser]} 시간 초과 — 턴을 넘깁니다 ({n}/{MAX_MISSES}).")
    if n >= MAX_MISSES:                                   # 1분간 미행동 → 상대 자동 승리
        st['phase'] = 'over'
        st['winner'] = 'B' if loser == 'W' else 'W'
        st['turn_deadline'] = None
        st['log'].append(f"⌛ {SIDE_KR[loser]} 미행동 {MAX_MISSES}회 — {SIDE_KR[st['winner']]} 자동 승리!")
        return True
    advance_turn(st, real_move=False)                    # 미행동자 카운터는 유지한 채 턴만 넘김
    return True


def kill(st, target, actor_color, atype, method):
    """target 제거 + 킬로그 기록. atype=공격 기물, method=melee/artillery/barrage."""
    target['alive'] = False
    if target['o'] != actor_color:
        st.setdefault('captured', {}).setdefault(actor_color, []).append(target['t'])
    st['feedseq'] += 1
    st['feed'].append({
        'seq': st['feedseq'], 'actor': actor_color, 'atype': atype,
        'method': method, 'victim': target['o'], 'vtype': target['t'],
    })
    st['feed'] = st['feed'][-14:]
    if target['t'] == 'K':
        st['phase'] = 'over'
        st['winner'] = 'B' if target['o'] == 'W' else 'W'
        st['turn_deadline'] = None
        st['log'].append(
            f"☠ {SIDE_KR[actor_color]} {PIECE_KR[atype]}(으)로 "
            f"{SIDE_KR[target['o']]} 킹 처치 — {SIDE_KR[st['winner']]} 승리!")


def apply_move(st, color, pid, tr, tc):
    if st.get('promote'):
        return False, '승격할 기물을 먼저 선택하세요.'
    p = st['pieces'].get(pid)
    if not p or p['o'] != color or not p['alive']:
        return False, '내 기물이 아닙니다.'
    if (tr, tc) not in move_candidates(st, pid):
        return False, '이동할 수 없는 칸입니다.'
    # Candidate rays ignore unknown occupancy; authoritative travel captures the first encounter.
    if p['t'] in ('B', 'R', 'Q') or (p['t'] == 'P' and tc == p['c']):
        dr, dc = tr - p['r'], tc - p['c']
        distance = max(abs(dr), abs(dc))
        sr, sc = (0 if dr == 0 else (1 if dr > 0 else -1)), (0 if dc == 0 else (1 if dc > 0 else -1))
        for step in range(1, distance + 1):
            rr, cc = p['r'] + sr * step, p['c'] + sc * step
            if piece_at(st, rr, cc) is not None:
                tr, tc = rr, cc
                break
    origin = (p['r'], p['c'])
    target = piece_at(st, tr, tc)
    captured = target is not None and target['o'] != color
    if captured:
        kill(st, target, color, p['t'], 'melee')
    p['r'], p['c'], p['moved'] = tr, tc, True
    set_fx(st, 'kill' if (captured and st['phase'] == 'over') else
           ('capture' if captured else 'move'), [(tr, tc)], color)
    if st['phase'] == 'over':
        return True, None
    last = 0 if color == 'W' else N - 1        # 폰이 끝줄 도달 → 승격 대기(턴 안 넘김)
    if p['t'] == 'P' and tr == last:
        st['promote'] = {'pid': p['id'], 'color': color}
        st['log'].append(f"{SIDE_KR[color]} 폰 승격! — 비숍/나이트/전차 중 선택하세요.")
        return True, None
    advance_turn(st)
    return True, None


def apply_fire(st, color, pid, tr, tc):
    """비숍 단일 타일 저격 — 사거리 안 + '내가 볼 수 있는 적'만 명중. 발사하면 내 위치 노출."""
    if st.get('promote'):
        return False, '승격할 기물을 먼저 선택하세요.'
    p = st['pieces'].get(pid)
    if not p or p['o'] != color or not p['alive'] or p['t'] != 'B':
        return False, '저격할 비숍이 아닙니다.'
    if is_reloading(st, pid):
        return False, '재장전 중입니다. 이번 내 차례에는 이동하거나 다른 기물을 사용하세요.'
    if not in_board(tr, tc):
        return False, '보드 밖입니다.'
    if (tr - p['r']) ** 2 + (tc - p['c']) ** 2 > BISHOP_RANGE ** 2:
        return False, '사거리 밖입니다.'
    q = enemy_visible_at(st, color, tr, tc)
    if q is None:
        return False, '저격할 적이 보이지 않습니다(숨은 적은 못 맞힘).'
    p['reload_until'] = st['turnCount'] + 3
    st['log'].append(f"{SIDE_KR[color]} 비숍 저격! → ({tr},{tc})")
    king_hit = q['t'] == 'K'
    kill(st, q, color, 'B', 'artillery')
    enemy = 'B' if color == 'W' else 'W'
    add_reveal(st, pid, enemy, MUZZLE)             # 저격 후 비숍 위치 노출(카운터)
    set_fx(st, 'kill' if king_hit else 'fire', [(tr, tc)], color)
    if st['phase'] != 'over':
        advance_turn(st)
    return True, None


def apply_barrage(st, color, pid, tr, tc):
    if st.get('promote'):
        return False, '승격할 기물을 먼저 선택하세요.'
    p = st['pieces'].get(pid)
    if not p or p['o'] != color or not p['alive'] or p['t'] != 'R':
        return False, '돌파 사격할 전차(룩)가 아닙니다.'
    if is_reloading(st, pid):
        return False, '재장전 중입니다. 이번 내 차례에는 이동하거나 다른 기물을 사용하세요.'
    d = _orth(tr - p['r'], tc - p['c'])
    if d is None:
        return False, '상하좌우 직선 방향으로만 사격할 수 있습니다.'
    dr, dc = d
    p['reload_until'] = st['turnCount'] + 3
    st['log'].append(f"{SIDE_KR[color]} 전차 돌파 사격!")
    hit = []
    king_hit = False
    for dist in range(1, ROOK_FIRE + 1):
        r, c = p['r'] + dr * dist, p['c'] + dc * dist
        if not in_board(r, c) or (r, c) in FORESTS:
            break
        hit.append((r, c))
        q = piece_at(st, r, c)
        if q is not None:
            if q['t'] == 'K':
                king_hit = True
            kill(st, q, color, 'R', 'barrage')
            if st['phase'] == 'over':
                break
    enemy = 'B' if color == 'W' else 'W'
    add_reveal(st, pid, enemy, MUZZLE)
    set_fx(st, 'kill' if king_hit else 'barrage', hit, color)
    if st['phase'] != 'over':
        advance_turn(st)
    return True, None


def apply_scan(st, color, pid, tr, tc):
    """퀸 스캔 — 지정 지점 기준 2×2를 SCAN_DUR턴 감시(안개·부쉬 뚫음). 퀸은 머즐 플래시 없음(위치 안 노출)."""
    if st.get('promote'):
        return False, '승격할 기물을 먼저 선택하세요.'
    p = st['pieces'].get(pid)
    if not p or p['o'] != color or not p['alive'] or p['t'] != 'Q':
        return False, '스캔할 퀸이 아닙니다.'
    if not in_board(tr, tc):
        return False, '보드 밖입니다.'
    if abs(tr - p['r']) + abs(tc - p['c']) > SCAN_RANGE:
        return False, '스캔 사거리 밖입니다.'
    area = [(tr, tc), (tr, tc + 1), (tr + 1, tc), (tr + 1, tc + 1)]  # 지정칸=좌상단 2×2
    cells = [(r, c) for (r, c) in area if in_board(r, c)]
    found = sum(1 for (r, c) in cells
                if (piece_at(st, r, c) or {}).get('o') not in (None, color))
    st.setdefault('scans', []).append(                 # 그 지역을 SCAN_DUR턴 동안 감시
        {'viewer': color, 'cells': cells, 'until': st['turnCount'] + SCAN_DUR})
    # 퀸은 머즐 플래시 없음 — 스캔해도 자기 위치는 노출되지 않는다(감시 지역만 상대에게 보임).
    st['log'].append(f"{SIDE_KR[color]} 퀸 스캔! → ({tr},{tc}) 2×2 감시 (적 {found}기 포착)")
    set_fx(st, 'scan', cells, color)
    advance_turn(st)
    return True, None


def apply_promote(st, color, choice):
    """승격 대기 중인 폰을 선택 기물로 바꾼다(비숍/나이트/전차). 그 후 턴을 넘긴다."""
    pr = st.get('promote')
    if st['phase'] != 'play' or st['turn'] != color or not pr or pr['color'] != color:
        return False, '승격 대기 중이 아닙니다.'
    if choice not in ('R', 'N', 'B'):
        return False, '비숍(B)·나이트(N)·전차(R) 중에서 선택하세요.'
    p = st['pieces'].get(pr['pid'])
    if p:
        p['t'] = choice
    st['promote'] = None
    st['log'].append(f"{SIDE_KR[color]} 폰 → {PIECE_KR[choice]} 승격!")
    if st['phase'] != 'over':
        advance_turn(st)
    return True, None


def apply_resign(st, color):
    """기권 — 상대 승리 처리."""
    if st['phase'] not in ('setup', 'play'):
        return False, '진행 중인 게임이 아닙니다.'
    st['phase'] = 'over'
    st['winner'] = 'B' if color == 'W' else 'W'
    st['promote'] = None
    st['log'].append(f"🏳 {SIDE_KR[color]} 기권 — {SIDE_KR[st['winner']]} 승리!")
    return True, None


def apply_place(st, color, pid, r, c):
    if st['phase'] != 'setup':
        return False, '배치 단계가 아닙니다.'
    p = st['pieces'].get(pid)
    if not p or p['o'] != color:
        return False, '내 기물이 아닙니다.'
    z0, z1 = ZONE[color]
    if not (z0 <= r <= z1):
        return False, '자기 진영 3줄 안에만 배치할 수 있습니다.'
    if (r, c) in IMPASSABLE:
        return False, '숲·강에는 배치할 수 없습니다.'
    q = piece_at(st, r, c)
    if q is not None and q['id'] != pid:
        if q['o'] != color:
            return False, '상대 기물이 있는 칸입니다.'
        q['r'], q['c'] = p['r'], p['c']
    p['r'], p['c'] = r, c
    st['ready'][color] = False
    return True, None


def autoplace(st, color, mode):
    """배치 단계 편의: mode='default' 기본 포진 / 'random' 자기 진영 내 무작위 배치."""
    if st['phase'] != 'setup':
        return False, '배치 단계가 아닙니다.'
    mine = [p for p in st['pieces'].values() if p['o'] == color]
    if mode == 'default':
        d = default_pieces()
        for p in mine:
            dp = d.get(p['id'])
            if dp:
                p['r'], p['c'] = dp['r'], dp['c']
    else:  # random
        z0, z1 = ZONE[color]
        cells = [(r, c) for r in range(z0, z1 + 1) for c in range(N)
                 if (r, c) not in IMPASSABLE]
        random.shuffle(cells)
        for p, (r, c) in zip(mine, cells):
            p['r'], p['c'] = r, c
    st['ready'][color] = False
    return True, None


# ------------------------- 플레이어 뷰(안개 필터) -------------------------
def player_view(st, color, reveal=False):
    """color 시점에서 '보이는 것만' 담은 뷰. reveal=True면 안개를 끈다(혼자 테스트용).
    방/네트워크 필드는 server.py가 덧붙인다."""
    spectator = color not in ('W', 'B')
    if spectator:
        vis = set()
    elif reveal:
        vis = {(r, c) for r in range(N) for c in range(N)}  # 전체 보기(디버그)
    else:
        vis = visible_cells(st, color)
    shared = set() if spectator else bush_shared_cells(st, color)     # 내가 들어가 있는 덤불(롤식: 안에서는 서로 보임)
    grid = []
    for r in range(N):
        row = []
        for c in range(N):
            t = 3 if (r, c) in BUSHES else (2 if (r, c) in RIVERS else (1 if (r, c) in FORESTS else 0))
            cell = {'t': t, 'f': 0 if (r, c) in vis else 1, 'p': None}
            if not spectator:
                q = piece_at(st, r, c)
                if q is not None:
                    if q['o'] == color:
                        cell['p'] = {'t': q['t'], 'o': q['o'], 'id': q['id']}
                    else:
                        rv = revealed(st, color, q['id'])
                        if (r, c) in BUSHES:            # 부쉬 속 적: 밖에서는 인접·시야로도 안 보임.
                            show = rv or reveal or scanning(st, color, r, c) or (r, c) in shared   # 스캔 감시 지역 · 같은 덤불 안이면 보임
                        else:                          #  (rv=공격 노출, reveal=디버그 전체보기, vis에 스캔 지역 포함)
                            show = rv or (r, c) in vis
                        if show:
                            cell['p'] = {'t': q['t'], 'o': q['o']}
            row.append(cell)
        grid.append(row)

    seconds = None
    if st['phase'] == 'setup' and st['deadline']:
        seconds = max(0, int(round(st['deadline'] - time.time())))
    opp = 'B' if color == 'W' else 'W'

    # Intentional player feedback: disclose only which OWN pieces can be seen.
    # Use the opponent's real fog/LOS/bush/scan rules, never the debug reveal flag.
    exposed = []
    if not spectator and st['phase'] in ('play', 'over'):
        opponent_vis = visible_cells(st, opp)
        for p in st['pieces'].values():
            if p['alive'] and p['o'] == color and enemy_visible_at(st, opp, p['r'], p['c'], opponent_vis):
                exposed.append({'pid': p['id'], 'type': p['t'],
                                # Retain the old field for saved clients/records. Zero means
                                # ordinary sight, not a countdown until concealment.
                                'remaining': max(0, max((rv['until'] - st['turnCount'] for rv in st['reveals']
                                                       if rv['pid'] == p['id'] and rv['viewer'] == opp), default=0))})

    fx = None
    if st['fx'] and not spectator:
        cells = st['fx']['cells']
        if st['fx']['actor'] == color or any((r, c) in vis for (r, c) in cells):
            fx = {'seq': st['fx']['seq'], 'type': st['fx']['type'],
                  'cells': [[r, c] for (r, c) in cells if (r, c) in vis or st['fx']['actor'] == color]}

    return {
        'phase': st['phase'],
        'turn': st['turn'],
        'turnCount': st['turnCount'],
        'turnLimit': TURN_LIMIT,
        'yourColor': color,
        'zone': ZONE.get(color, [0, 0]),
        'ready': st['ready'].get(color, False) if not spectator else False,
        'oppReady': st['ready'].get(opp, False) if not spectator else False,
        'secondsLeft': seconds,
        'setupSeconds': SETUP_SECONDS,
        'turnSeconds': TURN_SECONDS,
        'aliveMe': count_alive(st, color) if not spectator else 0,
        'aliveOpp': count_alive(st, opp) if not spectator else 0,
        'deadMe': [] if spectator else dead_types(st, color),     # 내가 잃은 기물(상대의 전리품)
        'deadOpp': [] if spectator else dead_types(st, opp),      # 내가 잡은 상대 기물(적의 죽음은 전부 내 공격이므로 정보 누출 없음)
        'winner': st['winner'],
        'promote': (st['promote']['pid'] if (st.get('promote') and not spectator
                                             and st['promote']['color'] == color) else None),
        'scanTiles': [[r, c] for s in st.get('scans', [])       # 활성 스캔 감시 타일(양쪽 다 봄)
                      if st['turnCount'] < s['until'] for (r, c) in s['cells']],
        'log': st['log'][-9:],
        'moveHistory': [] if spectator else st.get('move_history', {}).get(color, [])[-24:],
        'captured': [] if spectator else list(st.get('captured', {}).get(color, [])),
        'reloading': [] if spectator else [
            {'pid': p['id'], 'type': p['t'], 'remaining': 1}
            for p in st['pieces'].values() if p['o'] == color and is_reloading(st, p['id'])],
        'exposed': exposed,
        'feed': [] if spectator else [e for e in st['feed'] if color in (e['actor'], e['victim'])][-8:],
        'grid': grid,
        'fx': fx,
    }


# A variant record, not standard PGN: 12x12 terrain and abilities require extra fields.
def _record_action(fn, kind):
    from functools import wraps
    @wraps(fn)
    def wrapped(st, color, *args):
        if st.get('_prediction'):
            return fn(st, color, *args)
        pid = args[0] if kind not in ('promote', 'resign') else (st.get('promote') or {}).get('pid')
        p = st['pieces'].get(pid) or {}
        before = dict(p)
        turn = st['turnCount']
        captured_before = len(st.get('captured', {}).get(color, []))
        ok, msg = fn(st, color, *args)
        if ok:
            after = st['pieces'].get(pid) or {}
            label = {'move':'이동', 'fire':'저격', 'barrage':'돌파', 'scan':'스캔', 'promote':'승격', 'resign':'기권'}[kind]
            def square(r, c):
                return chr(97 + c) + str(r + 1)
            detail = label
            if before:
                detail = PIECE_KR[before['t']] + ' ' + square(before['r'], before['c']) + ' ' + label
            if kind == 'move':
                detail += ' → ' + square(after['r'], after['c'])
            elif kind in ('fire', 'barrage', 'scan'):
                detail += ' → ' + square(args[1], args[2])
            elif kind == 'promote':
                detail += ' → ' + PIECE_KR[after['t']]
            # Compact Fog Chess notation; full coordinates remain in the replay record.
            letter = '' if before.get('t') == 'P' else before.get('t', '')
            destination = square(after['r'], after['c']) if after else ''
            if kind == 'move':
                capture = len(st.get('captured', {}).get(color, [])) > captured_before
                prefix = square(before['r'], before['c'])[0] if capture and not letter else letter
                compact = prefix + ('x' if capture else '') + destination
            elif kind in ('fire', 'barrage', 'scan'):
                compact = letter + {'fire':'!', 'barrage':'>>', 'scan':'?'}[kind] + square(args[1], args[2])
            elif kind == 'promote': compact = destination + '=' + after['t']
            else: compact = 'resign'
            st.setdefault('move_history', {}).setdefault(color, []).append(f'{turn + 1}. {compact}')
            # Full coordinates are never placed in player_view for the opposing side.
            st.setdefault('notation', []).append({
                'turn': turn, 'actor': color, 'action': kind, 'pid': pid,
                'compact': compact, 'description': detail,
                'from': [before.get('r'), before.get('c')],
                'to': [after.get('r'), after.get('c')],
                'target': list(args[1:3]) if kind in ('fire', 'barrage', 'scan') else None,
                'promotion': args[0] if kind == 'promote' else None,
            })
        return ok, msg
    return wrapped


for _action_name in ('move', 'fire', 'barrage', 'scan', 'promote', 'resign'):
    globals()['apply_' + _action_name] = _record_action(globals()['apply_' + _action_name], _action_name)
