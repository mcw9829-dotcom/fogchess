# -*- coding: utf-8 -*-
"""
기물 / 규칙 엔진 — 기물 정의, 행마(합법수), 이동/포격/돌파사격, 킬로그,
안개(포그) 시야 계숲, 플레이어별 뷰(player_view)를 담당한다.
게임 상태 st(dict) 하나를 인자로 받아 조작한다(방/네트워크는 server.py).
"""
import time
import random

from config import (N, VISION, KING_LIVES, ROOK_RANGE, ROOK_FIRE, BISHOP_MOVE,
                    BISHOP_RANGE, MUZZLE, ZONE, TURN_LIMIT)
from game_map import FORESTS, RIVERS, BUSHES, IMPASSABLE, in_board, los_clear

# 비숍 X자 5칸 착탄 / 폰 전진 방향 / 한글 이름
SPLASH = [(0, 0), (-1, -1), (-1, 1), (1, -1), (1, 1)]
DIRS4 = [(-1, 0), (1, 0), (0, -1), (0, 1)]  # 룩 십자(상하좌우) 사격
FORWARD = {'W': -1, 'B': 1}
PIECE_KR = {'K': '킹', 'R': '전차', 'B': '비숍', 'N': '나이트', 'P': '폰'}
SIDE_KR = {'W': '백', 'B': '흑'}


# ------------------------- 상태 생성 -------------------------
def default_pieces():
    """기본 포진(백): 룩2 나이트2 비숍2 폰7 킹1 = 14. 흑은 180도 대칭."""
    p = {}
    counter = {}

    def add(t, owner, r, c):
        counter[(owner, t)] = counter.get((owner, t), 0) + 1
        pid = f'{owner}_{t}{counter[(owner, t)]}'
        p[pid] = {'id': pid, 't': t, 'o': owner, 'r': r, 'c': c,
                  'alive': True, 'lives': KING_LIVES if t == 'K' else 1,
                  'moved': False}

    back = [('R', 3), ('N', 4), ('B', 5), ('K', 6), ('B', 7), ('N', 8), ('R', 9)]
    for (t, c) in back:
        add(t, 'W', 11, c)
        add(t, 'B', 0, N - 1 - c)
    for c in range(3, 10):  # 폰 7개
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
        'reveals': [],              # {pid, viewer, until}
        'feed': [],                 # 킬로그 {seq, actor, atype, method, victim, vtype}
        'feedseq': 0,
        'fx': None,                 # {seq, type, cells, actor}
        'fxseq': 0,
        'log': ['방 생성됨 — 친구가 접속하면 배치가 시작됩니다.'],
        'winner': None,             # 'W'/'B' 승자, 또는 'draw'
        'promote': None,            # 승격 대기 {pid, color} — 폰이 끝줄 도달 시
    }


# ------------------------- 유틸 -------------------------
def piece_at(st, r, c):
    for p in st['pieces'].values():
        if p['alive'] and p['r'] == r and p['c'] == c:
            return p
    return None


def count_alive(st, color):
    return sum(1 for p in st['pieces'].values() if p['alive'] and p['o'] == color)


# ------------------------- 안개(시야) -------------------------
def visible_cells(st, color):
    vis = set()
    srcs = []
    for p in st['pieces'].values():
        if p['alive'] and p['o'] == color:
            srcs.append((p['r'], p['c'], VISION[p['t']]))
    for rv in st['reveals']:
        if rv['viewer'] == color and st['turnCount'] < rv['until']:
            q = st['pieces'].get(rv['pid'])
            if q and q['alive']:
                srcs.append((q['r'], q['c'], 1))
    for (pr, pc, rad) in srcs:
        for dr in range(-rad, rad + 1):
            for dc in range(-rad, rad + 1):
                r, c = pr + dr, pc + dc
                if in_board(r, c) and los_clear(pr, pc, r, c):
                    vis.add((r, c))
    return vis



def revealed(st, color, pid):
    for rv in st['reveals']:
        if rv['pid'] == pid and rv['viewer'] == color and st['turnCount'] < rv['until']:
            return True
    return False


def enemy_visible_at(st, color, r, c, vis=None):
    """(r,c)에 color가 '실제로 볼 수 있는' 적 기물이 있으면 반환, 아니면 None.
    부쉬 은폐·안개·숲 시야차단을 그대로 적용한다(비숍 저격 명중 판정용)."""
    q = piece_at(st, r, c)
    if q is None or q['o'] == color:
        return None
    if revealed(st, color, q['id']):
        return q
    if (r, c) in BUSHES:                       # 부쉬 속 적: 노출 전엔 저격 불가
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
        for dr, dc in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
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
    return out


def fire_cells(st, pid):
    """비숍이 지금 저격할 수 있는 '표적 칸' 목록 — 사거리 BISHOP_RANGE 안 + 시야에 든 적만.
    (원형 전 범위가 아니라, 실제로 명중 가능한 적 위치만 하이라이트)."""
    p = st['pieces'].get(pid)
    if not p or p['t'] != 'B' or not p['alive']:
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


def _orth(dr, dc):
    """상하좌우 직선이면 단위 방향, 아니면 None(대각 불가)."""
    if (dr == 0) == (dc == 0):
        return None
    return (0 if dr == 0 else (1 if dr > 0 else -1),
            0 if dc == 0 else (1 if dc > 0 else -1))


def barrage_reach(st, pid):
    p = st['pieces'].get(pid)
    if not p or p['t'] != 'R' or not p['alive']:
        return []
    cells = []
    for dr, dc in DIRS4:                          # 십자 4방향 × ROOK_FIRE칸(숲에 막힘)
        for dist in range(1, ROOK_FIRE + 1):
            r, c = p['r'] + dr * dist, p['c'] + dc * dist
            if not in_board(r, c) or (r, c) in FORESTS:
                break
            cells.append((r, c))
    return cells


# ------------------------- 액션 적용 -------------------------
def advance_turn(st):
    st['turnCount'] += 1
    st['turn'] = 'B' if st['turn'] == 'W' else 'W'
    if st['phase'] == 'play' and st['turnCount'] >= TURN_LIMIT:
        st['phase'] = 'over'
        st['winner'] = 'draw'
        st['log'].append(f"턴 한도({TURN_LIMIT}) 도달 — 무승부!")


def kill(st, target, actor_color, atype, method):
    """target 제거 + 킬로그 기록. atype=공격 기물, method=melee/artillery/barrage."""
    target['alive'] = False
    st['feedseq'] += 1
    st['feed'].append({
        'seq': st['feedseq'], 'actor': actor_color, 'atype': atype,
        'method': method, 'victim': target['o'], 'vtype': target['t'],
    })
    st['feed'] = st['feed'][-14:]
    if target['t'] == 'K':
        st['phase'] = 'over'
        st['winner'] = actor_color
        st['log'].append(
            f"☠ {SIDE_KR[actor_color]} {PIECE_KR[atype]}(으)로 "
            f"{SIDE_KR[target['o']]} 킹 처치 — {SIDE_KR[actor_color]} 승리!")


def apply_move(st, color, pid, tr, tc):
    p = st['pieces'].get(pid)
    if not p or p['o'] != color or not p['alive']:
        return False, '내 기물이 아닙니다.'
    if (tr, tc) not in legal_moves(st, pid):
        return False, '이동할 수 없는 칸입니다.'
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
    p = st['pieces'].get(pid)
    if not p or p['o'] != color or not p['alive'] or p['t'] != 'B':
        return False, '저격할 비숍이 아닙니다.'
    if not in_board(tr, tc):
        return False, '보드 밖입니다.'
    if (tr - p['r']) ** 2 + (tc - p['c']) ** 2 > BISHOP_RANGE ** 2:
        return False, '사거리 밖입니다.'
    q = enemy_visible_at(st, color, tr, tc)
    if q is None:
        return False, '저격할 적이 보이지 않습니다(숨은 적은 못 맞힘).'
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
    p = st['pieces'].get(pid)
    if not p or p['o'] != color or not p['alive'] or p['t'] != 'R':
        return False, '돌파 사격할 전차(룩)가 아닙니다.'
    d = _orth(tr - p['r'], tc - p['c'])
    if d is None:
        return False, '상하좌우 직선 방향으로만 사격할 수 있습니다.'
    dr, dc = d
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


def apply_promote(st, color, choice):
    """승격 대기 중인 폰을 선택 기물로 바꾼다(비숍/나이트/전차). 그 후 턴을 넘긴다."""
    pr = st.get('promote')
    if not pr or pr['color'] != color:
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
                 if (r, c) not in FORESTS]
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
                        if (r, c) in BUSHES:            # 부쉬 속 적: 완전 은폐 — 인접·시야로는 안 보임.
                            show = rv or reveal        #  들어가서 잡거나(멜리) 룩/비숍 포격으로만 확인.
                        else:                          #  (rv=공격 노출, reveal=디버그 전체보기)
                            show = rv or (r, c) in vis
                        if show:
                            cell['p'] = {'t': q['t'], 'o': q['o']}
            row.append(cell)
        grid.append(row)

    seconds = None
    if st['phase'] == 'setup' and st['deadline']:
        seconds = max(0, int(round(st['deadline'] - time.time())))
    opp = 'B' if color == 'W' else 'W'

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
        'aliveMe': count_alive(st, color) if not spectator else 0,
        'aliveOpp': count_alive(st, opp) if not spectator else 0,
        'winner': st['winner'],
        'promote': (st['promote']['pid'] if (st.get('promote') and not spectator
                                             and st['promote']['color'] == color) else None),
        'log': st['log'][-9:],
        'feed': [] if spectator else [e for e in st['feed'] if color in (e['actor'], e['victim'])][-8:],
        'grid': grid,
        'fx': fx,
    }
