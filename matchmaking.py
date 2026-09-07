# -*- coding: utf-8 -*-
"""
랭크 매칭 대기열 — 로그인 회원끼리 레이팅이 가까운 순으로 자동 매칭.

  join(session, user, now)          대기열 등록(같은 세션이면 갱신)
  status(session, now, make_room)   폴링: 대기 정보 or 매칭 결과(방 코드·좌석 토큰·색·상대). 매칭 시도도 여기서.
  cancel(session)                   대기열 이탈
  window(waited)                    대기 시간에 따라 넓어지는 레이팅 검색 범위

순수 로직(방 생성은 make_room 콜백에 위임)이라 서버 없이 테스트할 수 있다. 서버는 락 안에서만 호출한다.
"""
import time

WINDOW_START, WINDOW_STEP, WINDOW_EVERY, WINDOW_MAX = 100, 50, 10.0, 400   # ±100에서 10초마다 +50, 최대 ±400
ANY_AFTER = 60.0        # 이만큼(초) 기다리면 레이팅 무관하게 매칭
STALE = 8.0             # 클라이언트 폴링이 이 시간(초) 이상 끊기면 대기열에서 제거(탭 닫음 등)
MATCHED_TTL = 120.0     # 매칭 결과를 클라가 가져가지 않아도 이 시간 뒤 정리
QUEUE = {}              # session -> {'session','uid','name','rating','since','seen','matched','matched_at'}


def window(waited):
    """대기 시간(초) → 허용 레이팅 차. 60초 이후는 무제한."""
    if waited >= ANY_AFTER:
        return float('inf')
    return min(WINDOW_MAX, WINDOW_START + WINDOW_STEP * int(waited // WINDOW_EVERY))


def join(session, user, now=None):
    now = time.time() if now is None else now
    e = QUEUE.get(session)
    if e and e.get('matched'):
        return e
    if not e:
        e = QUEUE[session] = {'session': session, 'uid': user['id'], 'name': user['name'], 'rating': user['rating'],
                              'since': now, 'seen': now, 'matched': None, 'matched_at': None}
    e['seen'] = now
    return e


def cancel(session):
    QUEUE.pop(session, None)


def prune(now):
    for s, e in list(QUEUE.items()):
        if e.get('matched'):
            if now - (e.get('matched_at') or now) > MATCHED_TTL:
                QUEUE.pop(s, None)
        elif now - e['seen'] > STALE:
            QUEUE.pop(s, None)


def try_match(now, make_room):
    """오래 기다린 순으로, 다른 계정 중 레이팅 차가 (둘 중 넓은) 검색 범위 안인 가장 가까운 상대와 짝짓는다.
    make_room(a, b) -> (room_code, tok_a, color_a, tok_b, color_b)"""
    waiting = sorted([e for e in QUEUE.values() if not e.get('matched')], key=lambda e: e['since'])
    used, pairs = set(), []
    for a in waiting:
        if a['session'] in used:
            continue
        best, bgap = None, None
        for b in waiting:
            if b is a or b['session'] in used or b['uid'] == a['uid']:
                continue
            gap = abs(a['rating'] - b['rating'])
            lim = max(window(now - a['since']), window(now - b['since']))
            if gap <= lim and (bgap is None or gap < bgap):
                best, bgap = b, gap
        if best:
            used.add(a['session']); used.add(best['session']); pairs.append((a, best))
    for a, b in pairs:
        code, ta, ca, tb, cb = make_room(a, b)
        a['matched'] = {'room': code, 'token': ta, 'color': ca, 'opp': {'name': b['name'], 'rating': b['rating']}}
        b['matched'] = {'room': code, 'token': tb, 'color': cb, 'opp': {'name': a['name'], 'rating': a['rating']}}
        a['matched_at'] = b['matched_at'] = now
    return pairs


def status(session, now, make_room):
    """폴링 응답. 대기 중이면 seen 갱신 + 정리 + 매칭 시도. 매칭됐으면 결과를 넘기고 대기열에서 뺀다."""
    e = QUEUE.get(session)
    if not e:
        return {'state': 'idle'}
    if not e.get('matched'):
        e['seen'] = now
        prune(now)
        try_match(now, make_room)
    if e.get('matched'):
        QUEUE.pop(session, None)
        return dict(state='matched', **e['matched'])
    waited = now - e['since']
    w = window(waited)
    return {'state': 'waiting', 'waited': int(waited), 'window': None if w == float('inf') else int(w),
            'queue': sum(1 for x in QUEUE.values() if not x.get('matched'))}
