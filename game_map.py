# -*- coding: utf-8 -*-
"""
맵/지형 — 숲(mountain) 배치와 시야 차단(LOS)을 담당한다.
숲은 펄린 노이즈로 자동 생성하거나(config.USE_PERLIN=True) MAP_ROWS를 그대로 쓴다.
숲은 시야·이동을 막지만 비숍 곡사 포탄은 넘어간다(사거리 판정은 pieces.py).
"""
import math
import random

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


def generate_forests(exclude=frozenset()):
    """USE_PERLIN이면 펄린 노이즈로 숲을 만든다(MAP_SYMMETRY로 대칭/비대칭 선택).
    exclude(강 등)에 든 칸은 숲 후보에서 제외. USE_PERLIN이 False면 MAP_ROWS를 쓴다."""
    if not USE_PERLIN:
        return _parse_map_rows() - set(exclude)
    noise = _perlin(PERLIN_SEED, PERLIN_SCALE)
    score = {(r, c): noise(c / PERLIN_SCALE, r / PERLIN_SCALE)
             for r in _FOREST_ROWS for c in range(N) if (r, c) not in exclude}
    K = max(0, PERLIN_COUNT)
    forest = set()

    if MAP_SYMMETRY == 'free':
        # 완전 랜덤 비대칭: 노이즈 값 상위 K칸
        for cc in sorted(score, key=lambda x: -score[x])[:K]:
            forest.add(cc)

    elif MAP_SYMMETRY == 'balanced':
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
            mir = (N - 1 - r, c) if MAP_SYMMETRY == 'mirror' else (N - 1 - r, N - 1 - c)
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


def generate_rivers():
    if EXTRA_TERRAIN != 'river':
        return set()
    rng = random.Random((PERLIN_SEED if PERLIN_SEED is not None else 0) + 777)
    mode = RIVER_MODE
    if mode == 'random':
        mode = rng.choice(['center', 'sides'])
    return _river_sides(rng) if mode == 'sides' else _river_center(rng)


# ------------------------- 부쉬(매복지) -------------------------
def generate_bushes():
    """펄린 노이즈로 대칭 부쉬 덤불(들어갈 수 있는 은신처)을 만든다. 숲과 별개."""
    if EXTRA_TERRAIN != 'bush':
        return set()
    seed = (PERLIN_SEED if PERLIN_SEED is not None else 0) + 4242
    noise = _perlin(seed, PERLIN_SCALE)
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
    for cell, mir, _ in pairs[:max(0, BUSH_COUNT) // 2]:
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


# 서버 시작 시 한 번 생성(모든 방이 공유 = 공정). 특수지형을 먼저 놓고 숲은 피해서 생성.
RIVERS = generate_rivers()
BUSHES = generate_bushes()
FORESTS = generate_forests(exclude=RIVERS | BUSHES)
IMPASSABLE = FORESTS | RIVERS          # 이동·배치가 막히는 칸(부쉬는 지나갈 수 있음)
