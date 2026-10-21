# -*- coding: utf-8 -*-
"""
봇 대 봇 검증 아레나 (QA 실험용 — 배포 코드 아님).

목적: hard 봇에서 'mm_remembered'(미니맥스 상대 모델에 기억한 적 포함) ON vs OFF 의
      상대 강도를 같은 조건에서 승률로 비교한다. 안개 규칙은 그대로 지킨다(치트 없음).

CPU 주의: 미니맥스를 로컬에서 돌리므로 CPU를 쓴다. 기본 예산을 짧게(0.15초) 두고,
          판 수도 작게 시작한다. 예산/판수는 아래 인자로 조절.

실행:
  python QA/2026-10-19/bot_arena.py --games 30 --budget 0.15
"""
import argparse
import random
import sys
import time
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))  # QA/<날짜>/ → 저장소 루트

import pieces
import bot


# ── 두 '두뇌': hard 결정 엔진을 mm_remembered만 다르게 ─────────────────────
def brain_off(st, me, budget):
    """현재 hard와 동일: 상대 모델 = 보이는 적만."""
    return bot._decide(st, me, hunt=True, abilities=True,
                       mm_budget=budget, mm_quiesce=bot.QUIESCENCE_DEPTH,
                       mm_remembered=False)


def brain_on(st, me, budget):
    """제안: 상대 모델 = 보이는 적 + 기억한 적(안 보이는 위협에도 대비)."""
    return bot._decide(st, me, hunt=True, abilities=True,
                       mm_budget=budget, mm_quiesce=bot.QUIESCENCE_DEPTH,
                       mm_remembered=True)


def apply_action(st, me, action):
    """bot.act의 액션 적용부만 분리(두뇌 선택은 바깥에서 주입)."""
    if st.get('promote') and st['promote']['color'] == me:
        pieces.apply_promote(st, me, 'R')
        return True
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


def play_one(brain_W, brain_B, budget, max_turns=300):
    """한 판. brain_W/brain_B: (st, me, budget)->action. 반환: 'W'|'B'|'draw'."""
    st = pieces.new_game()
    # 배치: 양쪽 다 봇 기본 포진 + 킹 은신
    bot.setup_and_ready(st, 'W')
    bot.setup_and_ready(st, 'B')
    st['phase'] = 'play'
    st['turn'] = 'W'
    brains = {'W': brain_W, 'B': brain_B}
    turns = 0
    while st['phase'] == 'play' and turns < max_turns:
        me = st['turn']
        guard = 0
        while st['phase'] == 'play' and st['turn'] == me and guard < 8:
            action = brains[me](st, me, budget)
            if not apply_action(st, me, action):
                pieces.advance_turn(st)
                break
            guard += 1
        turns += 1
    if st['phase'] != 'over':
        return 'draw'                 # 수 제한 도달 = 무승부 취급
    w = st.get('winner')
    return w if w in ('W', 'B') else 'draw'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--games', type=int, default=30, help='총 판 수(색 교대)')
    ap.add_argument('--budget', type=float, default=0.15, help='미니맥스 예산(초) — 작을수록 CPU 적게')
    ap.add_argument('--seed', type=int, default=1234)
    args = ap.parse_args()

    random.seed(args.seed)
    # ON = 제안(기억 포함), OFF = 현재 hard. 색을 번갈아 배정해 선공 이점 상쇄.
    on_wins = off_wins = draws = 0
    t0 = time.time()
    for g in range(args.games):
        if g % 2 == 0:
            res = play_one(brain_on, brain_off, args.budget)   # ON=백, OFF=흑
            if res == 'W':
                on_wins += 1
            elif res == 'B':
                off_wins += 1
            else:
                draws += 1
        else:
            res = play_one(brain_off, brain_on, args.budget)   # OFF=백, ON=흑
            if res == 'W':
                off_wins += 1
            elif res == 'B':
                on_wins += 1
            else:
                draws += 1
        done = g + 1
        print(f'[{done}/{args.games}] ON {on_wins} - OFF {off_wins} - draw {draws}'
              f'  ({time.time()-t0:.1f}s)', flush=True)

    total = args.games
    decisive = on_wins + off_wins
    print('\n===== 결과 =====')
    print(f'총 {total}판, 예산 {args.budget}s/수')
    print(f'ON(기억 포함)  승: {on_wins}')
    print(f'OFF(현재 hard) 승: {off_wins}')
    print(f'무승부: {draws}')
    if decisive:
        print(f'ON 승률(무승부 제외): {on_wins/decisive*100:.1f}%')


if __name__ == '__main__':
    main()
