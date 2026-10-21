"""Participant chat and ranked first-to-two series. Caller holds server.lock."""
import time
import unicodedata

CHAT_LIMIT = 80
CHAT_LENGTH = 200
CHAT_COOLDOWN = 1.0


def series(room):
    if not room.get('match') or room.get('bot') or room.get('solo'):
        return None
    value = room.setdefault('series', {'wins': {'W': 0, 'B': 0}, 'games': 0, 'draws': 0})
    st = room['state']
    if st['phase'] == 'over' and st.get('winner') in ('W', 'B', 'draw') and not st.get('_series_counted'):
        st['_series_counted'] = True
        value['games'] += 1
        if st['winner'] == 'draw': value['draws'] += 1
        else: value['wins'][st['winner']] += 1
    value['complete'] = max(value['wins'].values()) >= 2
    value['winner'] = next((c for c in ('W', 'B') if value['wins'][c] >= 2), None)
    return value


def series_view(room, color):
    value = series(room)
    if value is None: return None
    opp = 'B' if color == 'W' else 'W'
    return dict(me=value['wins'][color], opp=value['wins'][opp], games=value['games'],
                draws=value['draws'], complete=value['complete'], winner=value['winner'],
                final=value['wins']['W'] == value['wins']['B'] == 1)


def chat_allowed(room, token):
    color = room.get('tokens', {}).get(token)
    return (color in ('W', 'B') and room['seats'].get(color) == token
            and not room.get('solo') and not room.get('bot'))


def send_chat(room, token, text, nonce, now=None):
    now = time.time() if now is None else now
    if not chat_allowed(room, token):
        return {'ok': False, 'msg': '대전 참가자만 채팅할 수 있어요.'}
    if not isinstance(text, str) or not isinstance(nonce, str) or not 1 <= len(nonce) <= 64:
        return {'ok': False, 'msg': '채팅 요청 형식이 올바르지 않아요.'}
    text = unicodedata.normalize('NFC', text)
    text = ' '.join(''.join(c for c in text if unicodedata.category(c) not in ('Cc', 'Cf') or c in '\n\t').split())
    if not text or len(text) > CHAT_LENGTH:
        return {'ok': False, 'msg': '메시지는 1~200자로 입력하세요.'}
    color = room['tokens'][token]
    messages = room.setdefault('chat', [])
    if any(m['nonce'] == nonce and m['side'] == color for m in messages):
        return {'ok': True}
    last = room.setdefault('_chat_last', {})
    if now - last.get(color, float('-inf')) < CHAT_COOLDOWN:
        return {'ok': False, 'msg': '잠시 후에 다시 보내주세요. (1초 간격)'}
    last[color] = now
    seq = room.get('_chat_seq', 0) + 1
    room['_chat_seq'] = seq
    messages.append(dict(id=seq, side=color, name=room.get('names', {}).get(color, color),
                         text=text, at=now, nonce=nonce))
    del messages[:-CHAT_LIMIT]
    return {'ok': True}


def chat_view(room):
    return [{k: v for k, v in message.items() if k != 'nonce'} for message in room.get('chat', [])]
