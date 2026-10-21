"""Persistent Fog Chess notation plus exact board frames, independent of rules changes."""
import copy
from contextlib import contextmanager
import gzip
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import uuid
import accounts
import pieces
from config import APP_VERSION


def digest(token):
    return hashlib.sha256(str(token).encode()).hexdigest()


@contextmanager
def database():
    path = Path(os.environ.get('FOG_REPLAY_DB', str(Path(accounts.DB_PATH).with_name('replays.sqlite3'))))
    path.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(path)
    try:
        with db:
            db.execute('CREATE TABLE IF NOT EXISTS replays (id TEXT PRIMARY KEY, ended REAL, access TEXT, payload BLOB)')
            yield db
    finally:
        db.close()


def save(room):
    rec = room.get('_replay')
    if not rec or rec['saved'] or rec['state']['phase'] != 'over':
        return
    payload = rec['data']
    payload['ended'] = rec['state'].get('ended_at', payload['frames'][-1]['at'])
    payload['winner'] = rec['state']['winner']
    access = {'tokens': [digest(t) for t, c in room['tokens'].items() if c in ('W', 'B', 'solo') and t != '__bot__'],
              'users': list(room.get('users', {}).values())}
    with database() as db:
        db.execute('INSERT OR REPLACE INTO replays VALUES (?, ?, ?, ?)',
                   (payload['id'], payload['ended'], json.dumps(access),
                    gzip.compress(json.dumps(payload, ensure_ascii=False).encode('utf-8'))))
    rec['saved'] = True


def record(room, view, now):
    st = room['state']
    rec = room.get('_replay')
    if rec is None or rec['state'] is not st:
        rec = room['_replay'] = {'state': st, 'saved': False, 'signature': None,
                                'data': {'id': uuid.uuid4().hex, 'format': 'fogchess-replay-v1',
                                         'rulesVersion': APP_VERSION, 'room': room['code'],
                                         'names': dict(room['names']), 'frames': []}}
    view['replayId'] = rec['data']['id'] if st['phase'] == 'over' else None
    signature = copy.deepcopy((st['pieces'], st['phase'], st['turnCount'], st['turn'],
                               st.get('promote'), st.get('notation'), st.get('misses'), st.get('scans'), st['winner']))
    if rec['signature'] == signature:
        save(room)
        return
    rec['signature'] = signature
    frame = copy.deepcopy(view)
    for key in list(frame):
        if key.startswith('_'):
            del frame[key]
    frame.update(replay=True, spectatorWaiting=False, turnSecondsLeft=None,
                 secondsLeft=None, elapsed=None, spectatorCount=0)
    notation = st.get('notation', [])
    previous = rec.get('notation_count', 0)
    label = '초기 배치'
    action = None
    if len(notation) > previous:
        action = copy.deepcopy(notation[-1])
        label = ('백' if action.get('actor') == 'W' else '흑') + ' · ' + {'move':'이동', 'fire':'저격', 'barrage':'돌파 사격', 'scan':'스캔', 'promote':'승격', 'resign':'기권'}.get(action.get('action'), '행동')
    elif rec['data']['frames'] and st['phase'] == 'play':
        label = '턴 전환 / 시간 초과'
    if st['phase'] == 'over':
        label += ' · 대국 종료'
    rec['notation_count'] = len(notation)
    item = {'at': now, 'label': label, 'action': action, 'view': frame,
            'pieces': copy.deepcopy(st['pieces']), 'promotion': copy.deepcopy(st.get('promote')),
            'misses': copy.deepcopy(st.get('misses', {})),
            'perspectives': {side: copy.deepcopy(pieces.player_view(st, side)) for side in ('W', 'B')}}
    frames = rec['data']['frames']
    if frames and frames[-1]['view']['phase'] == 'setup':
        frames[-1] = item
    else:
        frames.append(item)
    rec['data']['names'] = dict(room['names'])
    save(room)


def load(replay_id, token, session, now):
    with database() as db:
        row = db.execute('SELECT ended, access, payload FROM replays WHERE id=?', (replay_id,)).fetchone()
    if not row:
        return {'ok': False, 'msg': '저장된 리플레이를 찾을 수 없습니다.'}
    ended, access, payload = row
    access = json.loads(access)
    user = accounts.user_by_token(session) if session else None
    participant = (bool(token) and digest(token) in access['tokens']) or (user and user['id'] in access['users'])
    if not participant and now < ended + 180:
        return {'ok': False, 'msg': '관전 중계가 끝난 뒤 리플레이를 볼 수 있습니다.'}
    return {'ok': True, 'replay': json.loads(gzip.decompress(payload))}
