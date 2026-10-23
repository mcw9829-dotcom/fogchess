"""Server-owned delayed broadcast. Call with the room lock and terrain installed."""
import copy
import math
import time
from collections import deque
import pieces
import replays

DELAY = 180
PRESENCE_TTL = 10


def count(room, now):
    return sum(c == 'spectator' and now - room['seen'].get(t, 0) < PRESENCE_TTL
               for t, c in room['tokens'].items())


def capture(room, now=None):
    now = time.time() if now is None else now
    st = room['state']
    if st['phase'] == 'over' and not st.get('ended_at'):
        st['ended_at'] = now
    # Equality includes setup, timeout, promotion, rematch, and names, but not presence.
    source = (st, room['terrain'], room['names'], room['ratings'])
    if room.get('_broadcast_source') == source:
        replays.save(room)
        return
    v = pieces.player_view(st, 'W', True)
    for row in v['grid']:
        for cell in row:
            if cell['p']:
                cell['p'].pop('id', None)
    v.update(yourColor='spectator', promote=None, exposed=[], reloading=[], ready=False,
             oppReady=False, captured=[], feed=copy.deepcopy(st['feed'][-8:]),
             capturedBy=copy.deepcopy(st.get('captured', {})),
             names=dict(room['names']), ratings=dict(room['ratings']),
             room=room['code'], bothJoined=True, solo=False,
             mapSeed=room['terrain']['seed'], spectator=True)
    records = []
    for side in ('W', 'B'):
        for line in st.get('move_history', {}).get(side, []):
            records.append((int(line.split('.')[0]), side, line))
    records.sort(key=lambda item: item[0])
    v['moveHistory'] = [('백 ' if s == 'W' else '흑 ') + text for _, s, text in records[-24:]]
    v['_turn_deadline'] = st.get('turn_deadline')
    v['_setup_deadline'] = st.get('deadline')
    v['_started_at'] = st.get('started_at')
    v['_ended_at'] = st.get('ended_at') or (now if st['phase'] == 'over' else None)
    replays.record(room, v, now)
    room['_broadcast_source'] = copy.deepcopy(source)
    timeline = room.setdefault('_broadcast', deque())
    timeline.append((now, v))
    # Retain one predecessor at the cutoff, then every newer event.
    while len(timeline) > 1 and timeline[1][0] <= now - DELAY:
        timeline.popleft()


def view(room, now):
    target = now - DELAY
    timeline = room.get('_broadcast', ())
    selected = next((v for at, v in reversed(timeline) if at <= target), None)
    if selected is None:
        remaining = max(1, math.ceil(timeline[0][0] + DELAY - now)) if timeline else DELAY
        return dict(spectator=True, spectatorWaiting=True, waitSeconds=remaining,
                    spectatorCount=count(room, now), delaySeconds=DELAY, room=room['code'],
                    phase='waiting', yourColor='spectator', turn=None, turnCount=0,
                    grid=[[dict(t=0, f=1, p=None) for _ in range(12)] for _ in range(12)],
                    feed=[], moveHistory=[], capturedBy={}, names={}, winner=None,
                    bothJoined=False, fx=None, log=[], scanTiles=[])
    result = copy.deepcopy(selected)
    result.update(spectatorWaiting=False, delaySeconds=DELAY,
                  spectatorCount=count(room, now))
    turn_end = result.pop('_turn_deadline')
    setup_end = result.pop('_setup_deadline')
    started = result.pop('_started_at')
    ended = result.pop('_ended_at')
    result['turnSecondsLeft'] = max(0, math.ceil(turn_end - target)) if turn_end and result['phase'] == 'play' else None
    result['secondsLeft'] = max(0, math.ceil(setup_end - target)) if setup_end and result['phase'] == 'setup' else None
    result['elapsed'] = max(0, int((ended or target) - started)) if started else None
    return result
