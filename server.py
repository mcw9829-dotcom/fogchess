# -*- coding: utf-8 -*-
"""
안개전장 체스 (WW1 Fog Chess) - 서버 / 네트워크 계층 v4
실행:  python server.py  ->  http://localhost:7555

역할: 방(room) 관리 · 좌석/재접속 · HTTP(정적파일 + /join /state /moves /action).
게임 규칙은 pieces.py, 지형은 game_map.py, 설정은 config.py 에 있다.
서버는 '진짜 상태'를 들고, 각 플레이어에겐 pieces.player_view 로 '보이는 것만' 내려준다.
"""
import http.server
import socketserver
import json
import os
import sys
import re
import socket
import shutil
import subprocess
import uuid
import hmac
import time
import random
import threading
from urllib.parse import urlparse, parse_qs

from config import (PORT, CODE_ALPHABET, SEAT_TIMEOUT, SETUP_SECONDS, USE_PERLIN, ROOM_TTL,
                    TURN_SECONDS, MAX_MISSES, BOT_MIN_THINK, BOT_RATED, BOT_RATING, BOT_NO_LOSS, BOT_GAIN_CAP,
                    DISCONNECT_FORFEIT,
                    PERLIN_SEED, NEW_MAP_ON_REMATCH, RATING_DEFAULT, RATING_FLOOR, ELO_K, RATING_TIERS,
                    APP_VERSION)
from game_map import FORESTS, RIVERS, BUSHES, terrain_to_ascii
from pieces import (new_game, legal_moves, fire_cells, fire_range, barrage_reach,
                    apply_move, apply_fire, apply_barrage, apply_place, autoplace,
                    player_view, advance_turn, apply_promote, apply_resign,
                    scan_cells, apply_scan, time_out, SIDE_KR)
import bot
import accounts
import game_map
import pieces
import matchmaking

BOT_TOKEN = '__bot__'   # 컴퓨터(봇) 좌석 토큰
MAX_BODY = 64 * 1024    # 요청 본문 상한(바이트) — 게임 액션은 수백 바이트면 충분
FB_LAST = {}            # 피드백 도배 방지: ip -> 마지막 전송 시각
FB_COOLDOWN = 10        # 같은 IP는 이 시간(초)에 한 번만
ADMIN_FAILS = {}        # 관리자 비밀번호 틀린 기록: ip -> [횟수, 첫 실패 시각]
ADMIN_MAX_FAILS = 5     # 이만큼 틀리면
ADMIN_LOCK = 600        # 이 시간(초) 동안 그 IP는 관리자 인증을 거부(무차별 대입 방지)


NOTES_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), '패치노트.txt')   # (HERE 는 아래에서 정의됨)
_NOTES_CACHE = {'mtime': None, 'data': []}
_NOTE_HDR = re.compile(r'^\[(\d{4}-\d{2}-\d{2})\]\s+(?:(v[\d.]+)\s*[—-]\s*)?(.*)$')
_NOTE_ITEM = re.compile(r'^\[([^\]]+)\]\s*(.*)$')


def load_patchnotes():
    """패치노트.txt → [{date, version, title, items:[{tag, text}]}] (최신이 앞). 파일 mtime 으로 캐시.
    형식: '[YYYY-MM-DD]  vX.Y — 제목' 헤더, 그 아래 '[태그] 내용' 줄(들여쓴 줄은 앞 항목에 이어붙임). 파일 머리(표기 규칙)는 건너뜀."""
    try:
        mtime = os.path.getmtime(NOTES_PATH)
    except OSError:
        return []
    if _NOTES_CACHE['mtime'] == mtime:
        return _NOTES_CACHE['data']
    entries, cur = [], None
    with open(NOTES_PATH, encoding='utf-8') as f:
        for ln in f.read().split('\n'):
            if ln.startswith('===='):
                continue
            m = _NOTE_HDR.match(ln)
            if m:
                cur = {'date': m.group(1), 'version': m.group(2), 'title': m.group(3).strip(), 'items': []}
                entries.append(cur)
                continue
            if cur is None or not ln.strip():
                continue
            m = _NOTE_ITEM.match(ln)
            if m:
                cur['items'].append({'tag': m.group(1), 'text': m.group(2).strip()})
            elif cur['items']:
                cur['items'][-1]['text'] += ' ' + ln.strip()
    _NOTES_CACHE['mtime'], _NOTES_CACHE['data'] = mtime, entries
    return entries


def admin_ok(key_given):
    """관리자 키(FOG_ADMIN_KEY 환경변수) 일치? 키가 설정되지 않았으면 항상 거부."""
    key = os.environ.get('FOG_ADMIN_KEY')
    return bool(key) and hmac.compare_digest(str(key_given or ''), key)


def admin_gate(ip, key_given, now=None):
    """관리자 인증 판정: 'ok' / 'forbidden' / 'locked'. 같은 IP가 ADMIN_MAX_FAILS번 틀리면 ADMIN_LOCK초 잠금."""
    now = time.time() if now is None else now
    f = ADMIN_FAILS.get(ip)
    if f and f[0] >= ADMIN_MAX_FAILS and now - f[1] < ADMIN_LOCK:
        return 'locked'
    if admin_ok(key_given):
        ADMIN_FAILS.pop(ip, None)
        return 'ok'
    if not f or now - f[1] >= ADMIN_LOCK:
        ADMIN_FAILS[ip] = [1, now]
    else:
        f[0] += 1
    return 'forbidden'

HERE = os.path.dirname(os.path.abspath(__file__))
lock = threading.Lock()
LAN_URL = f"http://localhost:{PORT}/"   # __main__에서 실제 내부IP로 교체

# ------------------------- 방(room) 관리 -------------------------
ROOMS = {}   # code -> {code, state, seats, tokens, seen, created}


def new_room(code):
    return {'code': code, 'state': new_game(),
            'seats': {'W': None, 'B': None},   # color -> token
            'tokens': {},                       # token -> color ('solo'면 양쪽 조작)
            'seen': {},                         # token -> 마지막 응답 시각
            'names': {},                        # color -> 표시 닉네임
            'users': {},                        # color -> 회원 id(로그인한 좌석만 — 레이팅 대상)
            'ratings': {},                      # color -> 현재 레이팅(표시용 캐시)
            'rated_done': False,                # 이 판의 레이팅 정산을 마쳤나(한 번만)
            'rematch': {},                      # 재대결 제안 {color: True} — 사람끼리는 둘 다 눌러야 새 판
            'rating_result': {},                # color -> {'delta', 'rating'} 정산 결과
            'solo': False,                      # 혼자 연습(핫시트) 방인가
            'terrain': game_map.generate_terrain(PERLIN_SEED),   # 이 방만의 지형(숲·부쉬·강 + 시드)
            'created': time.time()}


def make_match_room(a, b):
    """랭크 매칭 성사 → 두 회원을 앉힌 PvP 방 생성(색 무작위). (code, tokA, colorA, tokB, colorB). 락 안에서 호출."""
    now = time.time()
    code = gen_code(); room = new_room(code); use_terrain(room)
    cols = ('W', 'B') if random.random() < 0.5 else ('B', 'W')
    toks = (uuid.uuid4().hex, uuid.uuid4().hex)
    for ent, tok, col in ((a, toks[0], cols[0]), (b, toks[1], cols[1])):
        room['seats'][col] = tok; room['tokens'][tok] = col; room['seen'][tok] = now
        room['users'][col] = ent['uid']; room['ratings'][col] = ent['rating']; room['names'][col] = ent['name']
    room['match'] = True
    room['state']['log'].append(f"랭크 매칭: {room['names']['W']}({room['ratings']['W']}) vs "
                                f"{room['names']['B']}({room['ratings']['B']}) - 기물을 배치하고 [준비 완료]")
    ROOMS[code] = room
    maybe_setup_timer(room)
    return code, toks[0], cols[0], toks[1], cols[1]


def use_terrain(room):
    """이 방의 지형을 규칙/봇 코드가 읽는 전역에 꽂아 넣는다 — 방을 다루는 모든 락 구간의 첫 줄에서 호출."""
    game_map.apply_terrain(room['terrain'], pieces, bot)


def clean_name(s, fallback):
    s = (s or '').strip()[:16]
    return s if s else fallback


def attach_user(room, color, data, fallback):
    """세션 토큰이 유효하면 그 좌석을 회원과 연결(계정 닉네임·레이팅 표시, 레이팅전 대상).
    아니면 게스트 닉네임만 기록."""
    user = accounts.user_by_token(data.get('session'))
    if user:
        room['users'][color] = user['id']
        room['ratings'][color] = user['rating']
        room['names'][color] = user['name']
    else:
        room['users'].pop(color, None)
        room['ratings'].pop(color, None)
        room['names'][color] = clean_name(data.get('name'), fallback)


def game_score(winner, color):
    return 0.5 if winner == 'draw' else (1.0 if winner == color else 0.0)


def is_rated(room):
    """이 판이 레이팅전인가: 봇전=사람이 회원(BOT_RATED) / 사람끼리=랭크 매칭 방(match)이고 양쪽 다 다른 회원.
    로비(친구) 대전·솔로·게스트는 비레이팅 — 친구끼리 점수를 주고받는 걸 막고, 편하게 연습하도록."""
    users = room.get('users', {})
    if room.get('solo'):
        return False
    if room.get('bot'):
        human = 'W' if room['bot'] == 'B' else 'B'
        return bool(BOT_RATED and users.get(human))
    return bool(room.get('match') and users.get('W') and users.get('B') and users['W'] != users['B'])


def game_reason(st):
    """종료 사유(최근 로그로 판단): king(왕 처치) / resign / disconnect / timeout(미행동) / draw(턴 한도)"""
    if st.get('winner') == 'draw':
        return 'draw'
    for ln in reversed(st['log'][-3:]):                      # 가장 최근 줄부터
        if '접속 끊김' in ln:
            return 'disconnect'
        if '미행동' in ln:
            return 'timeout'
        if '기권' in ln:
            return 'resign'
    return 'king'


def record_history(room):
    """게임이 끝나면 회원 좌석마다 전적 한 줄(비레이팅 포함). 솔로·게스트 좌석은 제외. 실패해도 게임 진행은 막지 않음."""
    if room.get('solo'):
        return
    st, users = room['state'], room.get('users', {})
    kind = 'match' if room.get('match') else ('bot' if room.get('bot') else 'lobby')
    reason = game_reason(st)
    for color in ('W', 'B'):
        uid = users.get(color)
        if not uid:
            continue
        opp = 'B' if color == 'W' else 'W'
        if room.get('bot') == opp:
            opp_name, opp_uid = room['names'].get(opp, '컴퓨터'), None
            opp_rating = BOT_RATING.get(room.get('botlevel', 'normal'), 1000)
        else:
            opp_name, opp_uid = room['names'].get(opp, '상대'), users.get(opp)
            ro = room.get('rating_result', {}).get(opp)                          # 정산 전(대국 당시) 상대 레이팅
            opp_rating = (ro['rating'] - ro['delta']) if ro else room['ratings'].get(opp)
        result = 'draw' if st['winner'] == 'draw' else ('win' if st['winner'] == color else 'loss')
        rr = room.get('rating_result', {}).get(color)
        try:
            accounts.add_game(uid, kind, result, reason, opp_name, opp_uid, opp_rating, bool(rr),
                              rr['delta'] if rr else None, rr['rating'] if rr else None, room['code'])
        except Exception as e:
            print('[history] record failed:', e)


def settle_rating(room):
    """게임이 끝났으면 딱 한 번: 레이팅전이면 정산해 room['rating_result'][color] = {'delta', 'rating'} 에 두고,
    회원 좌석의 전적(games)을 기록한다. 정산 실패(DB 오류 등)가 게임 진행을 막지 않도록 예외는 삼킨다."""
    st = room['state']
    if st['phase'] != 'over' or room.get('rated_done') or not st.get('winner'):
        return
    room['rated_done'] = True
    if not is_rated(room):
        record_history(room)
        return
    users = room['users']
    try:
        if room.get('bot'):
            human = 'W' if room['bot'] == 'B' else 'B'
            bot_rating = BOT_RATING.get(room.get('botlevel', 'normal'), 1000)
            res = accounts.record_vs_fixed(users[human], bot_rating, game_score(st['winner'], human),
                                           no_loss=BOT_NO_LOSS, cap=bot_gain_cap(room))   # 져도 안 떨어짐 · 난이도별 상한
            room['rating_result'] = {human: res}
            room['ratings'][human] = res['rating']
        else:
            res = accounts.record_result(users['W'], users['B'], game_score(st['winner'], 'W'))
            room['rating_result'] = {'W': res['a'], 'B': res['b']}
            room['ratings']['W'], room['ratings']['B'] = res['a']['rating'], res['b']['rating']
    except Exception as e:
        print('[rating] settle failed:', e)
    record_history(room)


def bot_gain_cap(room):
    """이 봇 방에서 오를 수 있는 레이팅 상한(컴퓨터 레이팅 + BOT_GAIN_CAP). 상한 없음이면 None."""
    if BOT_GAIN_CAP is None:
        return None
    return BOT_RATING.get(room.get('botlevel', 'normal'), 1000) + BOT_GAIN_CAP


def bot_rating_note(room):
    """봇 방 시작 로그에 붙일 레이팅 안내 한 줄(회원이 아니면 None)."""
    if not room.get('bot') or not is_rated(room):
        return None
    human = 'W' if room['bot'] == 'B' else 'B'
    r = room['ratings'].get(human, RATING_DEFAULT)
    bot_rating = BOT_RATING.get(room.get('botlevel', 'normal'), 1000)
    gain = accounts.fixed_delta(r, bot_rating, 1.0, BOT_NO_LOSS, bot_gain_cap(room))
    loss = accounts.fixed_delta(r, bot_rating, 0.0, BOT_NO_LOSS, bot_gain_cap(room))
    if gain <= 0:
        return f'📈 레이팅 {r}: 이 난이도의 상한({bot_gain_cap(room)})에 닿아 더 오르지 않아요 - 더 어려운 난이도나 랭크 매칭으로!'
    tail = '져도 내려가지 않아요.' if loss == 0 else f'지면 {loss}.'
    return f'📈 레이팅 {r}: 이기면 +{gain}, {tail}'


def start_rematch(room):
    """새 판 시작(같은 방·같은 좌석). 레이팅 정산 상태와 재대결 제안 초기화, 필요하면 새 맵."""
    room['state'] = new_game()
    room['rated_done'] = False; room['rating_result'] = {}; room['rematch'] = {}   # 새 판 = 새 정산
    if NEW_MAP_ON_REMATCH:                                                       # 새 판 = 새 맵
        room['terrain'] = game_map.generate_terrain(PERLIN_SEED); use_terrain(room)
    st = room['state']
    if room.get('solo'):
        st['phase'] = 'play'
        st['turn'] = 'W'
        st['log'] = ['🎯 혼자 연습 - 재시작.']
    elif room.get('bot'):
        bot.setup_and_ready(st, 'B')
        st['deadline'] = time.time() + SETUP_SECONDS
        st['log'] = ['🤖 컴퓨터와 대전 — 재대결! 백 배치 후 [준비 완료].']
        note = bot_rating_note(room)
        if note:
            st['log'].append(note)
    else:
        st['log'] = ['🔁 재대결! 둘 다 수락 — 기물을 배치하고 [준비 완료]']
        maybe_setup_timer(room)


def rematch_request(room, color):
    """재대결 요청. 솔로·봇 방은 즉시 새 판. 사람끼리는 게임이 끝난 뒤 제안으로 기록하고, 양쪽이 다 누르면 새 판.
    → {'ok', 'pending'(상대 대기), 'msg'}"""
    st = room['state']
    if room.get('solo'):
        start_rematch(room); return {'ok': True}
    if color not in ('W', 'B'):
        return {'ok': False, 'msg': '관전자는 재대결을 시작할 수 없어요.'}
    if room.get('bot'):
        start_rematch(room); return {'ok': True}
    if st['phase'] != 'over':
        return {'ok': False, 'msg': '재대결은 게임이 끝난 뒤에 제안할 수 있어요.'}
    offers = room.setdefault('rematch', {})
    opp = 'B' if color == 'W' else 'W'
    if not offers.get(color):
        offers[color] = True
        st['log'].append(f"🔁 {SIDE_KR[color]} 재대결 제안 - 상대의 수락을 기다리는 중")
    if not offers.get(opp):
        return {'ok': True, 'pending': True}
    start_rematch(room)
    return {'ok': True}


def rematch_decline(room, color):
    """재대결 제안 거절/취소 — 제안이 있었으면 지우고 로그로 알린다."""
    if color in ('W', 'B') and room.get('rematch'):
        room['rematch'] = {}
        room['state']['log'].append(f"✋ {SIDE_KR[color]} 재대결을 원하지 않음")
    return {'ok': True}


def effective_color(room, token):
    """실제로 조작 권한이 있는 색. solo 토큰은 '지금 둘 차례'의 색을 갖는다."""
    c = room['tokens'].get(token, 'spectator')
    if c == 'solo':
        return room['state']['turn']
    return c


_last_gc = 0.0


def gc_rooms(now):
    """오래(ROOM_TTL) 활동 없는 방을 삭제해 메모리를 정리한다(최대 60초에 한 번)."""
    global _last_gc
    if now - _last_gc < 60:
        return
    _last_gc = now
    stale = [code for code, room in ROOMS.items()
             if now - (max(room['seen'].values()) if room['seen'] else room['created']) > ROOM_TTL]
    for code in stale:
        del ROOMS[code]


def gen_code():
    while True:
        code = ''.join(random.choice(CODE_ALPHABET) for _ in range(4))
        if code not in ROOMS:
            return code


def both_joined(room):
    s = room['seats']
    return s['W'] is not None and s['B'] is not None


def assign_seat(room, now, new_token):
    """빈 자리에 앉히거나, 오래 응답 없는 자리를 회수해 앉힌다. 없으면 spectator."""
    seats = room['seats']
    for col in ('W', 'B'):
        if seats[col] is None:
            seats[col] = new_token
            return col
    for col in ('W', 'B'):
        old = seats[col]
        if old is None or (now - room['seen'].get(old, 0)) > SEAT_TIMEOUT:
            room['tokens'].pop(old, None)
            seats[col] = new_token
            return col
    return 'spectator'


def maybe_setup_timer(room):
    st = room['state']
    if st['phase'] == 'setup' and st['deadline'] is None and both_joined(room):
        st['deadline'] = time.time() + SETUP_SECONDS
        st['log'].append('상대 접속 완료 — 배치 시작! 기물을 배치하고 [준비 완료]를 누르세요.')


def maybe_start(st):
    if st['phase'] != 'setup' or st['deadline'] is None:
        return
    if (st['ready']['W'] and st['ready']['B']) or time.time() > st['deadline']:
        st['phase'] = 'play'
        st['turn'] = 'W'
        st['turn_deadline'] = time.time() + TURN_SECONDS   # 첫 턴(백) 제한시간 시작
        st['started_at'] = time.time()                     # 경과 시간 표시용
        st['log'].append('배치 완료 — 전투 시작! (백 선공)')


def enforce_clock(room, now):
    """플레이 중 턴 제한시간을 넘겼으면 자동으로 상대 턴으로 넘긴다(time_out).
    솔로(핫시트)는 제외. 봇 차례는 자동 응수가 처리하므로 사람 차례만 검사한다."""
    st = room['state']
    if room.get('solo'):
        return
    if st['phase'] != 'play' or not st.get('turn_deadline'):
        return
    if room.get('bot') and st['turn'] == room['bot']:
        return
    if now <= st['turn_deadline']:
        return
    time_out(st)                                           # 미행동 1회(또는 3회째면 패배)
    if st['phase'] == 'play' and room.get('bot'):          # 넘긴 뒤 봇 차례면 봇이 응수
        guard = 0
        while st['phase'] == 'play' and st['turn'] == room['bot'] and guard < 8:
            if not bot.act(st, room['bot'], room.get('botlevel', 'normal')):
                advance_turn(st); break
            guard += 1


def sweep_rooms(now):
    """주기 점검(아무도 폴링하지 않아도 진행): 턴 시계 강제 → 접속 끊김 DISCONNECT_FORFEIT초 이상이면 기권 → 정산.
    솔로(핫시트)·봇 좌석은 제외. 양쪽 다 끊겼으면 더 오래 끊긴 쪽이 기권."""
    for room in list(ROOMS.values()):
        st = room['state']
        if room.get('solo'):
            continue
        if st['phase'] == 'setup' and room.get('match') and both_joined(room):
            # 랭크 매칭 방은 수락 순간부터 승부 — 배치 단계에서 접속이 끊겨도 DISCONNECT_FORFEIT초면 기권(레이팅 정산)
            for color in ('W', 'B'):
                tok = room['seats'].get(color)
                gap = now - room['seen'].get(tok, room['created']) if tok else 0
                if tok and gap > DISCONNECT_FORFEIT:
                    st['log'].append(f"📵 {SIDE_KR[color]} 접속 끊김 {int(gap)}초 — 기권 처리")
                    apply_resign(st, color)
                    settle_rating(room)
                    break
            continue
        if st['phase'] != 'play':
            continue
        use_terrain(room)
        enforce_clock(room, now)                                # 미행동 3회 패배가 폴링 없이도 진행
        if st['phase'] != 'play':
            settle_rating(room)
            continue
        worst, worst_gap = None, 0.0
        for color in ('W', 'B'):
            tok = room['seats'].get(color)
            if not tok or tok == BOT_TOKEN:
                continue
            gap = now - room['seen'].get(tok, room['created'])
            if gap > DISCONNECT_FORFEIT and gap > worst_gap:
                worst, worst_gap = color, gap
        if worst:
            st['log'].append(f"📵 {SIDE_KR[worst]} 접속 끊김 {int(worst_gap)}초 — 기권 처리")
            apply_resign(st, worst)
            settle_rating(room)


def sweeper():
    """5초마다 sweep_rooms (데몬 스레드). 예외가 나도 스레드는 죽지 않는다."""
    while True:
        time.sleep(5)
        try:
            with lock:
                sweep_rooms(time.time())
        except Exception as e:
            print('[sweep] error:', repr(e))


def state_response(room, color, now, reveal=False):
    """pieces.player_view + 방/네트워크 필드."""
    st = room['state']
    v = player_view(st, color, reveal)
    v['solo'] = room.get('solo', False)
    v['room'] = room['code']
    v['mapSeed'] = room['terrain']['seed']       # 이 방의 맵 시드(방 태그 표시·공유용)
    v['match'] = bool(room.get('match'))         # 랭크 매칭으로 만들어진 방
    v['bot'] = bool(room.get('bot'))             # 컴퓨터 대국(나가기 안내 문구용)
    v['shareBase'] = LAN_URL
    v['bothJoined'] = both_joined(room)
    opp = 'B' if color == 'W' else 'W'
    opp_tok = room['seats'].get(opp) if color in ('W', 'B') else None
    v['oppConnected'] = bool(opp_tok) and (now - room['seen'].get(opp_tok, 0) < 5)
    rm = room.get('rematch') or {}
    v['rematch'] = {'me': bool(rm.get(color)), 'opp': bool(rm.get(opp))} if color in ('W', 'B') else {'me': False, 'opp': False}
    # 턴 제한시간(모래시계) — 솔로/봇차례엔 표시 안 함
    show_clock = (st['phase'] == 'play' and st.get('turn_deadline')
                  and not room.get('solo')
                  and not (room.get('bot') and st['turn'] == room.get('bot')))
    v['turnSecondsLeft'] = max(0, int(round(st['turn_deadline'] - now))) if show_clock else None
    v['turnSeconds'] = TURN_SECONDS
    sa = st.get('started_at')                                 # 플레이 경과 시간(초). 게임이 끝나면 멈춘 값
    if sa:
        if st['phase'] == 'over' and not st.get('ended_at'):
            st['ended_at'] = now
        v['elapsed'] = int((st.get('ended_at') or now) - sa)
    else:
        v['elapsed'] = None
    v['maxMisses'] = MAX_MISSES
    v['misses'] = dict(st.get('misses', {'W': 0, 'B': 0}))
    # 표시 이름(내/상대). 솔로는 백/흑 라벨.
    nm = room.get('names', {})
    if color in ('W', 'B'):
        v['myName'] = nm.get(color, '플레이어')
        v['oppName'] = nm.get(opp, '상대')
    else:
        v['myName'] = None; v['oppName'] = None
    # 레이팅: 게임이 끝났으면 정산(한 번만) → 내/상대 레이팅·이번 판 변동
    settle_rating(room)
    rt = room.get('ratings', {})
    if room.get('bot') and BOT_RATED:
        rt = dict(rt, **{room['bot']: BOT_RATING.get(room.get('botlevel', 'normal'), 1000)})
    v['rated'] = is_rated(room)
    v['myRating'] = rt.get(color) if color in ('W', 'B') else None
    v['oppRating'] = rt.get(opp) if color in ('W', 'B') else None
    v['ratingDelta'] = room.get('rating_result', {}).get(color) if color in ('W', 'B') else None
    return v


# ------------------------- HTTP -------------------------
STATIC_MIME = {'.svg': 'image/svg+xml', '.png': 'image/png', '.css': 'text/css'}


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _json(self, obj, code=200):
        body = json.dumps(obj).encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        self._sent = True

    def _file(self, relpath, mime):
        try:
            with open(os.path.join(HERE, relpath), 'rb') as f:
                body = f.read()
        except FileNotFoundError:
            self._json({'error': 'not found'}, 404)
            return
        self.send_response(200)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(body)))
        # 정적 파일(html/js/css) 캐시 방지 — 갱신 즉시 반영(개발 중 '옛 파일' 혼동 제거)
        self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
        self.end_headers()
        self.wfile.write(body)
        self._sent = True

    def _room(self, code):
        return ROOMS.get((code or '').strip().upper())

    def _admin(self, data=None):
        """관리자 인증: X-Admin-Key 헤더 → ?key= → 본문 key 순으로 읽어 검사. 실패면 403/429 응답을 보내고 False."""
        u = urlparse(self.path)
        key = (self.headers.get('X-Admin-Key') or parse_qs(u.query).get('key', [''])[0] or (data or {}).get('key') or '')
        ip = self.client_address[0] if self.client_address else '?'
        res = admin_gate(ip, key)
        if res == 'ok':
            return True
        if res == 'locked':
            self._json({'ok': False, 'error': 'locked', 'msg': '틀린 시도가 많아 잠시 잠겼어요. 10분 뒤 다시.'}, 429)
        else:
            self._json({'ok': False, 'error': 'forbidden'}, 403)
        return False

    def do_GET(self):
        self._safe(self._get)

    def do_POST(self):
        self._safe(self._post)

    def _safe(self, fn):
        """핸들러 예외가 '응답 없이 연결 끊김'으로 새지 않게 — 로그 남기고 JSON 500 응답."""
        try:
            fn()
        except Exception as e:
            print('[server] handler error:', repr(e))
            if not getattr(self, '_sent', False):
                try:
                    self._json({'ok': False, 'msg': '서버 오류가 났습니다. 새로고침해 보세요.'}, 500)
                except Exception:
                    pass

    def _get(self):
        u = urlparse(self.path)
        if u.path in ('/', '/index.html'):
            self._file('client.html', 'text/html; charset=utf-8')
            return
        if u.path == '/style.css':
            self._file('style.css', 'text/css; charset=utf-8')
            return
        if u.path in ('/sound.js', '/game.js', '/fx.js'):
            self._file(u.path.lstrip('/'), 'application/javascript; charset=utf-8')
            return
        if u.path.startswith('/img/'):
            name = os.path.basename(u.path)
            ext = os.path.splitext(name)[1].lower()
            self._file(os.path.join('img', name), STATIC_MIME.get(ext, 'application/octet-stream'))
            return
        if u.path == '/admin':                                 # 관리자 페이지(비밀번호는 페이지 안에서 입력)
            self._file('admin.html', 'text/html; charset=utf-8')
            return
        if u.path == '/admin/check':                           # 비밀번호 확인용
            if self._admin():
                self._json({'ok': True})
            return
        if u.path == '/admin/users':                           # 회원 목록(관리자)
            if self._admin():
                self._json({'rows': accounts.users_list()})
            return
        if u.path == '/feedback':                              # 피드백 읽기(관리자): ?all=1 이면 처리된 것도
            if not self._admin():
                return
            q0 = parse_qs(u.query)
            self._json({'rows': accounts.feedback_list(int(q0.get('limit', ['100'])[0] or 100),
                                                       include_done=q0.get('all', ['0'])[0] == '1')})
            return
        if u.path == '/version':                               # 배지용 버전(공개)
            self._json({'version': APP_VERSION})
            return
        if u.path == '/patchnotes':                            # 패치노트(공개) — 사이드바 버전을 누르면 모달로 표시
            self._json({'version': APP_VERSION, 'entries': load_patchnotes()})
            return
        if u.path == '/leaderboard':                           # 레이팅 순위(공개)
            self._json({'rows': accounts.leaderboard(), 'total': accounts.user_count(),
                        'rules': {'default': RATING_DEFAULT, 'floor': RATING_FLOOR, 'k': ELO_K, 'botRated': BOT_RATED,
                                  'botNoLoss': BOT_NO_LOSS, 'botCap': BOT_GAIN_CAP,
                                  'bot': BOT_RATING, 'tiers': [[f, t] for f, t in RATING_TIERS]}})   # 규칙 공개(클라가 그림)
            return
        q = parse_qs(u.query)
        token = q.get('token', [''])[0]
        code = q.get('room', [''])[0]
        with lock:
            gc_rooms(time.time())
            room = self._room(code)
            if not room:
                self._json({'gone': True})
                return
            use_terrain(room)
            color = effective_color(room, token)
            now = time.time()
            room['seen'][token] = now
            if room.get('bot'):
                room['seen'][BOT_TOKEN] = now   # 봇은 항상 '접속' 상태로 표시
            if u.path == '/state':
                maybe_setup_timer(room)
                maybe_start(room['state'])
                enforce_clock(room, now)            # 턴 제한시간 초과 시 자동으로 상대 턴으로
                reveal = room.get('solo') and q.get('reveal', ['0'])[0] == '1'
                self._json(state_response(room, color, now, reveal))
                return
            if u.path == '/moves':
                pid = q.get('pid', [''])[0]
                st = room['state']
                p = st['pieces'].get(pid)
                if st['phase'] != 'play' or st['turn'] != color or not p or p['o'] != color:
                    self._json({'moves': [], 'canFire': False, 'fireCells': [], 'fireRange': [],
                                'canBarrage': False, 'barrageCells': [],
                                'canScan': False, 'scanCells': []})
                    return
                self._json({
                    'moves': legal_moves(st, pid),
                    'canFire': p['t'] == 'B',
                    'fireCells': fire_cells(st, pid) if p['t'] == 'B' else [],
                    'fireRange': fire_range(st, pid) if p['t'] == 'B' else [],
                    'canBarrage': p['t'] == 'R',
                    'barrageCells': barrage_reach(st, pid) if p['t'] == 'R' else [],
                    'canScan': p['t'] == 'Q',
                    'scanCells': scan_cells(st, pid) if p['t'] == 'Q' else [],
                })
                return
        self._json({'error': 'not found'}, 404)

    def _post(self):
        u = urlparse(self.path)
        try:
            length = int(self.headers.get('Content-Length', 0) or 0)
        except ValueError:
            length = 0
        if length > MAX_BODY:                                   # 본문 상한(메모리 남용 방지)
            self._json({'ok': False, 'msg': '요청이 너무 큽니다.'}, 413)
            return
        raw = self.rfile.read(length) if length else b'{}'
        try:
            data = json.loads(raw.decode('utf-8') or '{}')
        except Exception:
            data = {}
        if not isinstance(data, dict):                          # 본문은 JSON 객체만 받는다
            data = {}
        now = time.time()

        # ── 계정(회원가입/로그인/로그아웃/내 정보) — 방 락 불필요(accounts가 자체 락) ──
        if u.path in ('/signup', '/login'):
            fn = accounts.signup if u.path == '/signup' else accounts.login
            res, err = fn(data.get('name'), data.get('pw'))
            self._json({'ok': res is not None, 'msg': err, **(res or {})})
            return
        if u.path == '/logout':
            accounts.logout(data.get('session'))
            self._json({'ok': True})
            return
        if u.path == '/account/name':                          # 닉네임 변경(로그인 회원)
            user, err = accounts.change_name(data.get('session'), data.get('name'))
            self._json({'ok': user is not None, 'msg': err, 'user': user})
            return
        if u.path == '/account/pw':                            # 비밀번호 변경(현재 비밀번호 확인 · 새 규칙 검사)
            ok, err = accounts.change_password(data.get('session'), data.get('old'), data.get('new'))
            self._json({'ok': ok, 'msg': err})
            return
        if u.path == '/me':
            user = accounts.user_by_token(data.get('session'))
            self._json({'ok': user is not None, 'user': user})
            return
        if u.path == '/me/history':                            # 내 최근 전적(최근 20판)
            user = accounts.user_by_token(data.get('session'))
            if not user:
                self._json({'ok': False, 'msg': '로그인이 필요합니다.'})
                return
            self._json({'ok': True, 'rows': accounts.game_history(user['id'], 20)})
            return
        if u.path in ('/match/join', '/match/status', '/match/cancel', '/match/accept', '/match/decline'):   # 랭크 매칭(로그인 회원 전용)
            user = accounts.user_by_token(data.get('session'))
            if not user:
                self._json({'ok': False, 'state': 'idle', 'msg': '랭크 매칭은 로그인이 필요합니다.'})
                return
            with lock:
                if u.path in ('/match/cancel', '/match/decline'):     # 거절 = 나만 대기열에서 나감(상대는 다시 대기)
                    matchmaking.cancel(data.get('session'), now)
                    self._json({'ok': True, 'state': 'idle'})
                    return
                if u.path == '/match/join':
                    matchmaking.join(data.get('session'), user, now)
                if u.path == '/match/accept':
                    matchmaking.accept(data.get('session'), now)
                res = matchmaking.status(data.get('session'), now, make_match_room)
                res['ok'] = True; res['me'] = {'name': user['name'], 'rating': user['rating']}
                self._json(res)
            return
        if u.path in ('/feedback/done', '/feedback/delete'):        # 관리자: 처리됨 표시 / 삭제
            if not self._admin(data):
                return
            try:
                fid = int(data.get('id'))
            except (TypeError, ValueError):
                self._json({'ok': False, 'msg': 'id가 필요합니다.'})
                return
            if u.path == '/feedback/done':
                ok = accounts.feedback_set_done(fid, bool(data.get('done', True)))
            else:
                ok = accounts.feedback_delete(fid)
            self._json({'ok': ok, 'msg': None if ok else '없는 항목입니다.'})
            return
        if u.path == '/feedback':                                   # 개발자 피드백 저장
            ip = self.client_address[0] if self.client_address else '?'
            if now - FB_LAST.get(ip, 0) < FB_COOLDOWN:
                self._json({'ok': False, 'msg': '잠시 후 다시 보내주세요.'})
                return
            user = accounts.user_by_token(data.get('session'))
            name = user['name'] if user else clean_name(data.get('name'), '')
            ok, err = accounts.add_feedback(data.get('category'), data.get('message'), name or None,
                                            user['id'] if user else None, data.get('room'), data.get('ua'))
            if ok:
                FB_LAST[ip] = now
            self._json({'ok': ok, 'msg': err})
            return

        if u.path == '/join':
            with lock:
                if data.get('solo'):   # 혼자 연습(핫시트) 방
                    code = gen_code()
                    room = new_room(code)
                    use_terrain(room)
                    room['solo'] = True
                    ntok = uuid.uuid4().hex
                    room['seats']['W'] = room['seats']['B'] = ntok
                    room['tokens'][ntok] = 'solo'
                    room['seen'][ntok] = now
                    st = room['state']
                    st['phase'] = 'play'
                    st['turn'] = 'W'
                    st['log'] = ['🎯 혼자 연습 - 백과 흑을 번갈아 두세요.']
                    room['names'] = {'W': clean_name(data.get('name'), '백'), 'B': '흑'}
                    ROOMS[code] = room
                    self._json({'room': code, 'token': ntok, 'color': 'solo'})
                    return
                if data.get('vs_bot'):   # 컴퓨터(봇)와 대전 — 사람=백, 봇=흑
                    code = gen_code()
                    room = new_room(code)
                    use_terrain(room)
                    room['bot'] = 'B'
                    lv = data.get('level')
                    room['botlevel'] = lv if lv in ('easy', 'normal', 'hard') else 'normal'
                    htok = uuid.uuid4().hex
                    room['seats']['W'] = htok
                    room['seats']['B'] = BOT_TOKEN
                    room['tokens'][htok] = 'W'
                    room['tokens'][BOT_TOKEN] = 'B'
                    room['seen'][htok] = now
                    room['seen'][BOT_TOKEN] = now
                    st = room['state']
                    bot.setup_and_ready(st, 'B')       # 봇은 즉시 배치+준비
                    st['deadline'] = time.time() + SETUP_SECONDS
                    st['log'] = ['🤖 컴퓨터와 대전 — 백(당신) 기물을 배치하고 [준비 완료]. 흑(컴퓨터)은 준비됨.']
                    attach_user(room, 'W', data, '플레이어')          # 회원이면 계정 닉네임·레이팅전
                    room['names']['B'] = '컴퓨터(' + room['botlevel'] + ')'
                    note = bot_rating_note(room)
                    if note:
                        st['log'].append(note)
                    ROOMS[code] = room
                    self._json({'room': code, 'token': htok, 'color': 'W'})
                    return
                code = (data.get('room') or '').strip().upper()
                token = data.get('token') or ''
                room = ROOMS.get(code) if code else None
                if room is None:
                    code = code if code else gen_code()
                    room = new_room(code)
                    ROOMS[code] = room
                elif token and token in room['tokens']:
                    room['seen'][token] = now
                    c = room['tokens'][token]
                    if c in ('W', 'B'):
                        attach_user(room, c, data, room['names'].get(c, '플레이어'))
                    self._json({'room': code, 'token': token, 'color': c})
                    return
                ntok = uuid.uuid4().hex
                color = assign_seat(room, now, ntok)
                room['tokens'][ntok] = color
                room['seen'][ntok] = now
                if color in ('W', 'B'):
                    attach_user(room, color, data, '플레이어')
                maybe_setup_timer(room)
                self._json({'room': code, 'token': ntok, 'color': color})
            return

        if u.path == '/action':
            with lock:
                room = self._room(data.get('room'))
                if not room:
                    self._json({'ok': False, 'msg': '방을 찾을 수 없습니다. 새로고침하세요.', 'gone': True})
                    return
                use_terrain(room)
                token = data.get('token')
                room['seen'][token] = now
                color = effective_color(room, token)
                st = room['state']
                act = data.get('type')
                if color not in ('W', 'B'):
                    self._json({'ok': False, 'msg': '관전자는 조작할 수 없습니다.'})
                    return
                if act not in ('rematch', 'resign'):
                    enforce_clock(room, now)        # 마감 지난 턴은 먼저 자동으로 넘김
                if act == 'rematch':                                  # 솔로·봇: 즉시 새 판 / 사람끼리: 제안 → 둘 다 누르면 새 판
                    self._json(rematch_request(room, color))
                    return
                if act == 'rematch_decline':
                    self._json(rematch_decline(room, color))
                    return
                if act == 'resign':
                    ok, msg = apply_resign(st, color)
                    self._json({'ok': ok, 'msg': msg})
                    return
                try:                                    # 필드 누락/타입 오류 → 연결 끊김 대신 JSON 오류
                    if act == 'place':
                        ok, msg = apply_place(st, color, data['pid'], data['r'], data['c'])
                    elif act == 'autoplace':
                        ok, msg = autoplace(st, color, data.get('mode', 'default'))
                    elif act == 'ready':
                        if st['phase'] == 'setup':
                            st['ready'][color] = bool(data.get('value', True))
                            maybe_start(st)
                            ok, msg = True, None
                        else:
                            ok, msg = False, '배치 단계가 아닙니다.'
                    elif st['phase'] != 'play':
                        ok, msg = False, '아직 전투 단계가 아닙니다.'
                    elif st['turn'] != color:
                        ok, msg = False, '상대 턴입니다.'
                    elif act == 'move':
                        ok, msg = apply_move(st, color, data['pid'], data['r'], data['c'])
                    elif act == 'fire':
                        ok, msg = apply_fire(st, color, data['pid'], data['r'], data['c'])
                    elif act == 'barrage':
                        ok, msg = apply_barrage(st, color, data['pid'], data['r'], data['c'])
                    elif act == 'scan':
                        ok, msg = apply_scan(st, color, data['pid'], data['r'], data['c'])
                    elif act == 'promote':
                        ok, msg = apply_promote(st, color, data.get('choice'))
                    else:
                        ok, msg = False, '알 수 없는 동작.'
                except (KeyError, TypeError, ValueError):
                    ok, msg = False, '잘못된 요청입니다.'
                fx_mine = None                                  # 내 액션의 fx(봇 응수 전 스냅샷)
                if ok and st.get('fx') and st['fx'].get('actor') == color:
                    f = st['fx']
                    fx_mine = {'seq': f['seq'], 'type': f['type'], 'cells': [[r, c] for (r, c) in f['cells']]}
                bot_moved, bot_spent, bot_lvl = False, 0.0, room.get('botlevel', 'normal')
                if ok and room.get('bot'):
                    t0 = time.time()
                    guard = 0                      # 봇 차례면 응수(교착 방지 상한)
                    while st['phase'] == 'play' and st['turn'] == room['bot'] and guard < 8:
                        bot_moved = True
                        if not bot.act(st, room['bot'], bot_lvl):
                            advance_turn(st)       # 봇이 둘 수 없으면 패스
                            break
                        guard += 1
                    bot_spent = time.time() - t0
                resp = {'ok': ok, 'msg': msg, 'fx': fx_mine}
            # ── 락 해제 후 ── 봇이 실제로 뒀으면 '최소 생각시간'까지 대기(다른 방/배치 안 막음)
            if bot_moved:
                delay = BOT_MIN_THINK.get(bot_lvl, 1.0) - bot_spent
                if delay > 0:
                    time.sleep(delay)
            self._json(resp)
            return

        self._json({'error': 'not found'}, 404)


class ThreadingServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True


def lan_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(('8.8.8.8', 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return None


def start_tunnel(port):
    """--share: cloudflared '빠른 터널'로 서버를 인터넷에 공개(무료·계정 불필요).
    cloudflared가 있으면 실행해 공개 URL을 크게 출력하고, 없으면 설치법을 안내한다.
    (원격으로 할 땐 '나도' 이 공개 주소로 접속해 로비를 만들어야 초대 링크가 그 주소가 된다.)"""
    exe = shutil.which('cloudflared')
    if not exe:
        print('-' * 54)
        print('  [원격 공유] cloudflared 가 없습니다 (무료, 계정 불필요 터널).')
        print('  설치(택1):')
        print('    - winget install --id Cloudflare.cloudflared')
        print('    - https://github.com/cloudflare/cloudflared/releases (cloudflared.exe)')
        print('  설치 후:  python server.py --share')
        print(f'  (또는 다른 터미널에서 직접:  cloudflared tunnel --url http://localhost:{port} )')
        print('-' * 54)
        return
    print('-' * 54)
    print('  [원격 공유] cloudflared 터널 여는 중... 공개 주소가 곧 아래에 뜹니다.')
    try:
        proc = subprocess.Popen(
            [exe, 'tunnel', '--url', f'http://localhost:{port}'],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    except Exception as e:
        print(f'  터널 실행 실패: {e}')
        print('-' * 54)
        return

    def relay():
        seen = False
        for line in proc.stdout:
            m = re.search(r'https://[a-z0-9-]+\.trycloudflare\.com', line)
            if m and not seen:
                seen = True
                url = m.group(0)
                print('=' * 54)
                print('  [원격 접속 주소] 인터넷 어디서나 접속 가능:')
                print(f'     {url}')
                print('  -> 나도 이 주소로 접속해 [로비 게임 만들기] 후,')
                print('     화면의 "친구 초대 링크"를 친구에게 보내면 됩니다.')
                print('  (이 서버를 끄면 주소도 사라집니다. Ctrl+C 로 종료)')
                print('=' * 54)
            elif ('ERR' in line or 'error' in line.lower()) and 'trycloudflare' not in line:
                print('  [cloudflared] ' + line.rstrip())

    threading.Thread(target=relay, daemon=True).start()


if __name__ == '__main__':
    ip = lan_ip()
    if ip:
        LAN_URL = f"http://{ip}:{PORT}/"
    accounts.init_db()                                   # 계정/레이팅 DB 준비(fogchess.db, 없으면 생성)
    srv = ThreadingServer(('0.0.0.0', PORT), Handler)
    threading.Thread(target=sweeper, daemon=True).start()   # 턴 시계·접속 끊김 기권 주기 점검
    print('=' * 54)
    print('  안개전장 체스 v4 서버 실행 중 (방/재접속/재대결)')
    print(f'  내 브라우저:  http://localhost:{PORT}')
    if ip:
        print(f'  친구 접속용:  http://{ip}:{PORT}   <- 같은 와이파이')
    print('  브라우저에서 접속하면 방이 자동 생성되고, 화면의')
    print('  "친구 초대 링크"를 복사해 친구에게 보내면 됩니다.')
    print(f'  먼 곳의 친구와(다른 와이파이):  python server.py --share')
    print('-' * 54)
    src = '펄린 노이즈 자동생성' if USE_PERLIN else '수동 MAP_ROWS'
    print(f'  지형 예시({src}, #=숲{len(FORESTS)} ~=강{len(RIVERS)} "=부쉬{len(BUSHES)}) / 실제 맵은 방마다 새로 생성(방 태그의 맵 #시드):')
    for row in terrain_to_ascii(FORESTS, RIVERS, BUSHES):
        print('    ' + row)
    if USE_PERLIN:
        print('  ↑ 모든 방을 같은 맵으로 고정하려면 config.PERLIN_SEED를 정수로(또는 MAP_ROWS + USE_PERLIN=False).')
    print('  종료: Ctrl+C')
    print('=' * 54)
    if '--share' in sys.argv:
        start_tunnel(PORT)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print('\n서버 종료.')
