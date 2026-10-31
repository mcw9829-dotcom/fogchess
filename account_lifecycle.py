"""Self-service account removal; caller holds the game-room lock.

Shared match evidence and moderation records remain. Authentication, personal
history and presence are removed; structured player names are anonymized.
"""
import gzip
import json
import os
from pathlib import Path
import time
import accounts
import replays

REMOVED = '탈퇴한 플레이어'


def anonymize(value, name, sides):
    if isinstance(value, list):
        return [anonymize(item, name, sides) for item in value]
    if not isinstance(value, dict):
        return value
    result = {}
    for key, item in value.items():
        if key == 'names' and isinstance(item, dict):
            result[key] = {side: REMOVED if side in sides else label for side, label in item.items()}
        elif key == 'name' and value.get('side') in ('W', 'B'):
            # Chat author identity is the archived seat, independent of later renames.
            result[key] = REMOVED if value['side'] in sides else item
        elif key in ('name', 'opp_name') and item == name:
            result[key] = REMOVED
        else:
            result[key] = anonymize(item, name, sides)
    return result


def delete_account(session, password):
    # Create/locate the existing replay store, then use one attached transaction.
    with replays.database():
        pass
    replay_path = os.environ.get('FOG_REPLAY_DB', str(Path(accounts.DB_PATH).with_name('replays.sqlite3')))
    with accounts._db() as c:
        c.execute('ATTACH DATABASE ? AS replay_store', (replay_path,))
        c.execute('BEGIN IMMEDIATE')
        row = c.execute("SELECT u.* FROM users u JOIN sessions s ON s.user_id=u.id "
                        "WHERE s.token=? AND s.created>? AND s.scope='play'",
                        (session, time.time()-accounts.SESSION_TTL)).fetchone()
        if not row:
            return None, '다시 로그인해 주세요.'
        uid, name = row['id'], row['name']
        error = accounts._verify_pw(c, row, password, 'pw:' + row['name_lc'])
        if error:
            return None, error
        archives = c.execute('SELECT g.*,s.game_id settled FROM admin_games g '
                             'LEFT JOIN game_settlements s ON s.game_id=g.id').fetchall()
        related = [(g, [side for side, player in json.loads(g['users_json']).items() if player == uid]) for g in archives]
        if any(sides and g['request_json'] and not g['settled'] for g, sides in related):
            return None, '대국 결과 정산이 진행 중입니다. 정산 완료 후 다시 시도해 주세요.'
        for g, sides in related:
            if not sides:
                continue
            names = json.loads(g['names_json'])
            for side in sides:
                names[side] = REMOVED
            request = json.loads(g['request_json']) if g['request_json'] else None
            c.execute('UPDATE admin_games SET names_json=?,request_json=?,chat_json=? WHERE id=?',
                      (json.dumps(names, ensure_ascii=False),
                       json.dumps(anonymize(request, name, sides), ensure_ascii=False) if request else None,
                       json.dumps(anonymize(json.loads(g['chat_json']), name, sides), ensure_ascii=False), g['id']))
        for r in c.execute('SELECT id,access,payload FROM replay_store.replays').fetchall():
            access = json.loads(r['access'])
            if uid not in access.get('users', []):
                continue
            payload = json.loads(gzip.decompress(r['payload']))
            sides = [side for side, label in payload.get('names', {}).items() if label == name]
            # Archive ownership also works after a later nickname change.
            for g, owned in related:
                if g['replay_id'] == r['id']:
                    sides = owned
            payload = anonymize(payload, name, sides)
            access['users'] = [player for player in access['users'] if player != uid]
            c.execute('UPDATE replay_store.replays SET access=?,payload=? WHERE id=?',
                      (json.dumps(access), gzip.compress(json.dumps(payload, ensure_ascii=False).encode()), r['id']))
        c.execute('DELETE FROM sessions WHERE user_id=?', (uid,))
        c.execute('DELETE FROM games WHERE user_id=?', (uid,))
        c.execute('UPDATE games SET opp_name=?,opp_user_id=NULL WHERE opp_user_id=?', (REMOVED, uid))
        c.execute('UPDATE feedback SET name=?,user_id=NULL WHERE user_id=?', (REMOVED, uid))
        c.execute('DELETE FROM admin_presence WHERE user_id=?', (uid,))
        c.execute('DELETE FROM users WHERE id=?', (uid,))
        return uid, None
