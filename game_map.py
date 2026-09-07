# -*- coding: utf-8 -*-
"""
맵/지형 — 숲(mountain) 배치와 시야 차단(LOS)을 담당한다.
숲은 펄린 노이즈로 자동 생성하거나(config.USE_PERLIN=True) MAP_ROWS를 그대로 쓴다.
숲은 시야·이동·사격을 모두 막는다(LOS 차단). 사거리·명중 판정은 pieces.py.
"""
import math
import random
import sys

from config import (N, MAP_ROWS, USE_PERLIN, PERLIN_COUNT, PERLIN_SCALE, PERLIN_SEED,
                    MAP_SYMMETRY, EXTRA_TERRAIN, BUSH_COUNT, RIVER_MODE)

# 숲 배치는 가운데 8줄(2~9행)에만 — 맨 위/아래 각 2줄(스폰 구역)은 제외
_SPAWN_ROWS = {0, 1, N - 2, N - 1}
_FOREST_ROWS = [r for r in range(N) if r not in _SPAWN_ROWS]  # [2,3,4,5,6,7,8,9]


def in_board(r, c):
    return 0 <= r < N and 0 <= c < N


def los_clear(r0, c0, r1, c1):
    """(r0,c0)~(r1,c1) 사이에 숲이 있으면 시야가 막힌다."""
    dr, dc = r1 - r0, c1 - c0
    steps = max(abs(dr), abs(dc))
    if steps <= 1:
        return True
    for i in range(1, steps):
        rr = r0 + round(dr * i / steps)
        cc = c0 + round(dc * i / steps)
        if (rr, cc) in FORESTS:
            return False
    return True


def _parse_map_rows():
    """수동 지도(MAP_ROWS)에서 숲 좌표를 읽는다."""
    return {
        (r, c)
        for r, row in enumerate(MAP_ROWS) if r < N
        for c, ch in enumerate(row) if c < N and ch in '#^' and r not in _SPAWN_ROWS
    }


def _perlin(seed, scale):
    """표준 2D 펄린 노이즈. 반환한 noise(x, y)는 대략 [-1, 1]."""
    perm = list(range(256))
    random.Random(seed).shuffle(perm)
    perm = perm + perm

    def fade(t):
        return t * t * t * (t * (t * 6 - 15) + 10)

    def lerp(a, b, t):
        return a + t * (b - a)

    def grad(h, x, y):
        h &= 3
        u = x if h < 2 else y
        v = y if h < 2 else x
        return (u if not (h & 1) else -u) + (v if not (h & 2) else -v)

    def noise(x, y):
        xi, yi = int(math.floor(x)) & 255, int(math.floor(y)) & 255
        xf, yf = x - math.floor(x), y - math.floor(y)
        u, v = fade(xf), fade(yf)
        aa, ab = perm[perm[xi] + yi], perm[perm[xi] + yi + 1]
        ba, bb = perm[perm[xi + 1] + yi], perm[perm[xi + 1] + yi + 1]
        x1 = lerp(grad(aa, xf, yf), grad(ba, xf - 1, yf), u)
        x2 = lerp(grad(ab, xf, yf - 1), grad(bb, xf - 1, yf - 1), u)
        return lerp(x1, x2, v)

    return noise


def generate_forests(exclude=frozenset(), seed=None, count=None, symmetry=None):
    """USE_PERLIN이면 펄린 노이즈로 숲을 만든다(MAP_SYMMETRY로 대칭/비대칭 선택).
    exclude(강 등)에 든 칸은 숲 후보에서 제외. USE_PERLIN이 False면 MAP_ROWS를 쓴다.
    seed/count/symmetry를 주면 그 값으로(방마다 다른 맵), 없으면 config 기본값."""
    if not USE_PERLIN:
        return _parse_map_rows() - set(exclude)
    noise = _perlin(PERLIN_SEED if seed is None else seed, PERLIN_SCALE)
    sym = MAP_SYMMETRY if symmetry is None else symmetry
    score = {(r, c): noise(c / PERLIN_SCALE, r / PERLIN_SCALE)
             for r in _FOREST_ROWS for c in range(N) if (r, c) not in exclude}
    K = max(0, PERLIN_COUNT if count is None else count)
    forest = set()

    if sym == 'free':
        # 완전 랜덤 비대칭: 노이즈 값 상위 K칸
        for cc in sorted(score, key=lambda x: -score[x])[:K]:
            forest.add(cc)

    elif sym == 'balanced':
        # 모양은 비대칭, 위/아래 절반에 숲 개수를 똑같이(공정한 엄폐량)
        top = [c for c in score if c[0] < N // 2]      # 2~5행
        bot = [c for c in score if c[0] >= N // 2]     # 6~9행
        for cc in sorted(top, key=lambda x: -score[x])[:K // 2]:
            forest.add(cc)
        for cc in sorted(bot, key=lambda x: -score[x])[:K // 2]:
            forest.add(cc)

    else:
        # 'rotational'(180° 회전) 또는 'mirror'(상하 거울) — 완전 대칭 쌍으로 배치
        seen, pairs = set(), []
        for cell in score:
            r, c = cell
            mir = (N - 1 - r, c) if sym == 'mirror' else (N - 1 - r, N - 1 - c)
            if cell in seen or mir in seen:
                continue
            seen.add(cell)
            seen.add(mir)
            pairs.append((cell, mir, score[cell] + score.get(mir, 0)))
        pairs.sort(key=lambda x: -x[2])
        for cell, mir, _ in pairs[:K // 2]:
            forest.add(cell)
            forest.add(mir)
    return forest


# ------------------------- 강(river) -------------------------
def _river_center(rng):
    """가운데 가로 강(5,6행). 나루터=가운데 + 좌우 대칭 한 쌍의 열."""
    rows = [N // 2 - 1, N // 2]                     # 5, 6
    a = rng.choice([1, 2, 3])
    fords = {N // 2 - 1, N // 2, a, N - 1 - a}      # 열 5,6 + a,11-a 는 뚫음(도하)
    return {(r, c) for r in rows for c in range(N) if c not in fords}


def _river_sides(rng):
    """양쪽 세로 강(0,1 · 10,11열, 3~8행). 나루터=대칭 한 쌍의 행만 뚫음(도하 지점)."""
    cols = [0, 1, N - 2, N - 1]
    band = list(range(3, N - 3))                    # 3..8 (6행)
    fords = set(rng.choice([(3, 8), (4, 7), (5, 6)]))
    return {(r, c) for c in cols for r in band if r not in fords}


def generate_rivers(seed=None, mode=None, extra=None):
    """강 생성(extra가 'river' 또는 'both'일 때만). seed로 나루터 위치가 정해진다."""
    ex = EXTRA_TERRAIN if extra is None else extra
    if ex not in ('river', 'both'):
        return set()
    base = PERLIN_SEED if seed is None else seed
    rng = random.Random((base if base is not None else 0) + 777)
    mode = RIVER_MODE if mode is None else mode
    if mode == 'random':
        mode = rng.choice(['center', 'sides'])
    return _river_sides(rng) if mode == 'sides' else _river_center(rng)


# ------------------------- 부쉬(매복지) -------------------------
def generate_bushes(seed=None, count=None, extra=None):
    """펄린 노이즈로 대칭 부쉬 덤불(들어갈 수 있는 은신처)을 만든다. 숲과 별개. (extra가 'bush'/'both'일 때만)"""
    ex = EXTRA_TERRAIN if extra is None else extra
    if ex not in ('bush', 'both'):
        return set()
    base = PERLIN_SEED if seed is None else seed
    noise = _perlin((base if base is not None else 0) + 4242, PERLIN_SCALE)
    score = {(r, c): noise(c / PERLIN_SCALE, r / PERLIN_SCALE)
             for r in _FOREST_ROWS for c in range(N)}
    seen, pairs = set(), []
    for cell in score:                       # 180° 회전 대칭(공평)
        r, c = cell
        mir = (N - 1 - r, N - 1 - c)
        if cell in seen or mir in seen:
            continue
        seen.add(cell)
        seen.add(mir)
        pairs.append((cell, mir, score[cell] + score.get(mir, 0)))
    pairs.sort(key=lambda x: -x[2])
    b = set()
    for cell, mir, _ in pairs[:max(0, BUSH_COUNT if count is None else count) // 2]:
        b.add(cell)
        b.add(mir)
    return b


def terrain_to_ascii(forests, rivers, bushes=frozenset()):
    def ch(r, c):
        if (r, c) in forests:
            return '#'
        if (r, c) in rivers:
            return '~'
        if (r, c) in bushes:
            return '"'
        return '.'
    return [''.join(ch(r, c) for c in range(N)) for r in range(N)]


def generate_terrain(seed=None, extra=None):
    """한 판(방)의 지형 세트. seed=None이면 무작위 시드 → 방마다 다른 맵. 특수지형 먼저, 숲은 그 칸을 피해 생성.
    반환: {'seed', 'forests', 'bushes', 'rivers', 'impassable'} (impassable = 숲 | 강, 부쉬는 지나갈 수 있음)"""
    if seed is None:
        seed = random.randrange(1000, 999999)
    rivers = generate_rivers(seed, extra=extra)
    bushes = generate_bushes(seed, extra=extra) - rivers          # 강 위에 부쉬는 안 놓음
    forests = generate_forests(exclude=rivers | bushes, seed=seed)
    return {'seed': seed, 'forests': forests, 'bushes': bushes, 'rivers': rivers, 'impassable': forests | rivers}


def apply_terrain(t, *modules):
    """규칙 코드가 읽는 전역(FORESTS/BUSHES/RIVERS/IMPASSABLE)을 이 지형으로 바꾼다 — 이 모듈 + 지정 모듈(pieces, bot).
    서버는 요청을 락으로 하나씩 처리하므로, 방을 다루기 직전에 그 방의 지형을 꽂아 넣으면 방마다 다른 맵이 된다."""
    vals = {'FORESTS': t['forests'], 'BUSHES': t['bushes'], 'RIVERS': t['rivers'], 'IMPASSABLE': t['impassable']}
    for m in (sys.modules[__name__],) + modules:
        for k, v in vals.items():
            if hasattr(m, k):
                setattr(m, k, v)


# 모듈 로드 시 기본 지형(시작 화면 예시·테스트용). 실제 방은 server.new_room이 generate_terrain()으로 따로 만든다.
TERRAIN = generate_terrain(PERLIN_SEED)
RIVERS, BUSHES, FORESTS, IMPASSABLE = TERRAIN['rivers'], TERRAIN['bushes'], TERRAIN['forests'], TERRAIN['impassable']
