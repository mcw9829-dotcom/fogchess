# -*- coding: utf-8 -*-
"""
랭크 매칭 대기열 — 로그인 회원끼리 레이팅이 가까운 순으로 자동 매칭. (v1.36: 수락 단계 추가)

  join(session, user, now)              대기열 등록(같은 세션이면 갱신)
  status(session, now, make_room)       폴링: waiting / found(수락 대기) / matched(방 정보) / idle
  accept(session, now)                  짝 제안 수락 — 둘 다 수락하면 다음 status 에서 방 생성 → matched
  decline(session, now)                 거절: 나는 대기열에서 나가고(idle), 상대는 다시 대기(waiting)
  cancel(session, now)                  대기열 이탈(수락 대기 중이었으면 상대는 다시 대기)
  window(waited)                        대기 시간에 따라 넓어지는 레이팅 검색 범위

흐름: 둘이 짝지어지면 양쪽 'found'(ACCEPT_SECONDS 안에 수락) → 둘 다 수락 → 방 생성 → 'matched'(방 코드·좌석 토큰·색).
시간 안에 수락하지 않은 쪽은 대기열에서 빠지고, 수락했던 상대는 다시 'waiting'(대기 시간을 유지해 넓은 검색 범위 그대로).
matched 결과는 MATCHED_TTL 동안 폴링마다 반복 전달(응답을 한 번 놓쳐도 됨). 순수 로직(방 생성은 make_room 콜백)이라
서버 없이 테스트할 수 있다. 서버는 락 안에서만 호출한다.
"""
import time

WINDOW_START, WINDOW_STEP, WINDOW_EVERY, WINDOW_MAX = 100, 50, 10.0, 400   # ±100에서 10초마다 +50, 최대 ±400
ANY_AFTER = 60.0        # 이만큼(초) 기다리면 레이팅 무관하게 매칭
STALE = 8.0             # 클라이언트 폴링이 이 시간(초) 이상 끊기면 대기열에서 제거(탭 닫음 등)
MATCHED_TTL = 120.0     # 매칭 결과는 이 시간 동안 폴링마다 반복 전달(한 번 놓쳐도 됨) 후 정리
REJOIN_KEEP = 30.0      # 매칭 직후 이 시간 안에 다시 join 하면(응답 유실 등) 새 대기가 아니라 같은 결과를 다시 준다
ACCEPT_SECONDS = 15.0   # 짝이 잡힌 뒤 수락 제한 시간
QUEUE = {}              # session -> {'session','uid','name','rating','since','seen','pending','matched','matched_at'}
_pair_seq = 0


def window(waited):
    """대기 시간(초) → 허용 레이팅 차. 60초 이후는 무제한."""
    if waited >= ANY_AFTER:
        return float('inf')
    return min(WINDOW_MAX, WINDOW_START + WINDOW_STEP * int(waited // WINDOW_EVERY))


def _entry(session, user, now):
    return {'session': session, 'uid': user['id'], 'name': user['name'], 'rating': user['rating'],
            'since': now, 'seen': now, 'pending': None, 'matched': None, 'matched_at': None}


def join(session, user, now=None):
    now = time.time() if now is None else now
    e = QUEUE.get(session)
    if e and e.get('matched'):
        if now - (e.get('matched_at') or 0) < REJOIN_KEEP:     # 방금 성사된 결과를 못 받은 재시도 → 같은 결과
            return e
        QUEUE.pop(session, None); e = None                        # 오래된 결과 → 새 대기
    if not e:
        e = QUEUE[session] = _entry(session, user, now)
    e['seen'] = now                                               # 수락 대기 중(pending)이면 제안은 그대로 유지
    return e


def _release(e, now):
    """e의 짝 제안을 풀어 상대를 다시 대기로 돌린다(상대의 대기 시간은 유지)."""
    p = e.get('pending')
    if not p:
        return
    e['pending'] = None
    o = QUEUE.get(p['opp_session'])
    if o and o.get('pending') and o['pending'].get('opp_session') == e['session']:
        o['pending'] = None
        o['seen'] = now


def cancel(session, now=None):
    now = time.time() if now is None else now
    e = QUEUE.pop(session, None)
    if e:
        _release(e, now)


def decline(session, now=None):
    """거절: 나는 대기열에서 나간다(idle). 상대는 다시 대기."""
    cancel(session, now)


def accept(session, now=None):
    now = time.time() if now is None else now
    e = QUEUE.get(session)
    if e and e.get('pending'):
        e['pending']['accepted'] = True
        e['seen'] = now


def prune(now):
    for s, e in list(QUEUE.items()):
        if e.get('matched'):
            if now - (e.get('matched_at') or now) > MATCHED_TTL:
                QUEUE.pop(s, None)
        elif e.get('pending'):
            pass                                                  # 수락 마감은 _settle_pending 이 처리
        elif now - e['seen'] > STALE:
            QUEUE.pop(s, None)


def _settle_pending(now, make_room):
    """수락 대기 중인 짝들: 둘 다 수락 → 방 생성(matched). 마감 지남 → 미수락자는 제거, 수락자는 다시 대기.
    make_room(a, b) -> (room_code, tok_a, color_a, tok_b, color_b)"""
    done = set()
    for s, e in list(QUEUE.items()):
        p = e.get('pending')
        if not p or p['pair'] in done:
            continue
        done.add(p['pair'])
        o = QUEUE.get(p['opp_session'])
        if not o or not o.get('pending') or o['pending'].get('pair') != p['pair']:
            e['pending'] = None                                   # 상대가 사라짐(취소·거절) → 다시 대기
            continue
        if p['accepted'] and o['pending']['accepted']:
            code, ta, ca, tb, cb = make_room(e, o)
            e['matched'] = {'room': code, 'token': ta, 'color': ca, 'opp': {'name': o['name'], 'rating': o['rating']}}
            o['matched'] = {'room': code, 'token': tb, 'color': cb, 'opp': {'name': e['name'], 'rating': e['rating']}}
            e['matched_at'] = o['matched_at'] = now
            e['pending'] = o['pending'] = None
        elif now > p['deadline']:
            for x in (e, o):
                if x['pending']['accepted']:
                    x['pending'] = None; x['seen'] = now             # 수락했던 쪽: 다시 대기(대기 시간 유지)
                else:
                    QUEUE.pop(x['session'], None)                    # 미수락: 대기열에서 제거


def try_match(now, make_room=None):
    """오래 기다린 순으로, 다른 계정 중 레이팅 차가 (둘 중 넓은) 검색 범위 안인 가장 가까운 상대와 짝짓는다.
    짝은 바로 방이 되지 않고 '수락 대기(pending)'가 된다. (make_room 인자는 호환용)"""
    global _pair_seq
    waiting = sorted([e for e in QUEUE.values() if not e.get('matched') and not e.get('pending')],
                     key=lambda e: e['since'])
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
        _pair_seq += 1
        for x, y in ((a, b), (b, a)):
            x['pending'] = {'pair': _pair_seq, 'opp_session': y['session'],
                            'opp': {'name': y['name'], 'rating': y['rating']},
                            'accepted': False, 'deadline': now + ACCEPT_SECONDS}
    return pairs


def status(session, now, make_room):
    """폴링 응답. 대기 중이면 seen 갱신 + 정리 + 수락 마감 처리 + 매칭 시도."""
    e = QUEUE.get(session)
    if not e:
        return {'state': 'idle'}
    if not e.get('matched'):
        e['seen'] = now
        prune(now)
        _settle_pending(now, make_room)
        if session in QUEUE and not QUEUE[session].get('pending') and not QUEUE[session].get('matched'):
            try_match(now)
    e = QUEUE.get(session)                                        # 마감 처리로 제거됐을 수 있음
    if not e:
        return {'state': 'idle'}
    if e.get('matched'):
        return dict(state='matched', **e['matched'])
    p = e.get('pending')
    if p:
        o = QUEUE.get(p['opp_session'])
        return {'state': 'found', 'opp': p['opp'], 'accepted': p['accepted'],
                'oppAccepted': bool(o and o.get('pending') and o['pending'].get('accepted')),
                'secondsLeft': max(0, int(p['deadline'] - now))}
    waited = now - e['since']
    w = window(waited)
    return {'state': 'waiting', 'waited': int(waited), 'window': None if w == float('inf') else int(w),
            'queue': sum(1 for x in QUEUE.values() if not x.get('matched') and not x.get('pending'))}
