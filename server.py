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
import time
import random
import threading
from urllib.parse import urlparse, parse_qs

from config import (PORT, CODE_ALPHABET, SEAT_TIMEOUT, SETUP_SECONDS, USE_PERLIN, ROOM_TTL,
                    TURN_SECONDS, MAX_MISSES, BOT_MIN_THINK)
from game_map import FORESTS, RIVERS, BUSHES, terrain_to_ascii
from pieces import (new_game, legal_moves, fire_cells, fire_range, barrage_reach,
                    apply_move, apply_fire, apply_barrage, apply_place, autoplace,
                    player_view, advance_turn, apply_promote, apply_resign,
                    scan_cells, apply_scan, time_out)
import bot

BOT_TOKEN = '__bot__'   # 컴퓨터(봇) 좌석 토큰

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
            'solo': False,                      # 혼자 테스트(핫시트) 방인가
            'created': time.time()}


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


def state_response(room, color, now, reveal=False):
    """pieces.player_view + 방/네트워크 필드."""
    st = room['state']
    v = player_view(st, color, reveal)
    v['solo'] = room.get('solo', False)
    v['room'] = room['code']
    v['shareBase'] = LAN_URL
    v['bothJoined'] = both_joined(room)
    opp = 'B' if color == 'W' else 'W'
    opp_tok = room['seats'].get(opp) if color in ('W', 'B') else None
    v['oppConnected'] = bool(opp_tok) and (now - room['seen'].get(opp_tok, 0) < 5)
    # 턴 제한시간(모래시계) — 솔로/봇차례엔 표시 안 함
    show_clock = (st['phase'] == 'play' and st.get('turn_deadline')
                  and not room.get('solo')
                  and not (room.get('bot') and st['turn'] == room.get('bot')))
    v['turnSecondsLeft'] = max(0, int(round(st['turn_deadline'] - now))) if show_clock else None
    v['turnSeconds'] = TURN_SECONDS
    v['maxMisses'] = MAX_MISSES
    v['misses'] = dict(st.get('misses', {'W': 0, 'B': 0}))
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
        self.end_headers()
        self.wfile.write(body)

    def _room(self, code):
        return ROOMS.get((code or '').strip().upper())

    def do_GET(self):
        u = urlparse(self.path)
        if u.path in ('/', '/index.html'):
            self._file('client.html', 'text/html; charset=utf-8')
            return
        if u.path == '/style.css':
            self._file('style.css', 'text/css; charset=utf-8')
            return
        if u.path in ('/sound.js', '/game.js'):
            self._file(u.path.lstrip('/'), 'application/javascript; charset=utf-8')
            return
        if u.path.startswith('/img/'):
            name = os.path.basename(u.path)
            ext = os.path.splitext(name)[1].lower()
            self._file(os.path.join('img', name), STATIC_MIME.get(ext, 'application/octet-stream'))
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

    def do_POST(self):
        u = urlparse(self.path)
        length = int(self.headers.get('Content-Length', 0))
        raw = self.rfile.read(length) if length else b'{}'
        try:
            data = json.loads(raw.decode('utf-8') or '{}')
        except Exception:
            data = {}
        now = time.time()

        if u.path == '/join':
            with lock:
                if data.get('solo'):   # 혼자 테스트(핫시트) 방
                    code = gen_code()
                    room = new_room(code)
                    room['solo'] = True
                    ntok = uuid.uuid4().hex
                    room['seats']['W'] = room['seats']['B'] = ntok
                    room['tokens'][ntok] = 'solo'
                    room['seen'][ntok] = now
                    st = room['state']
                    st['phase'] = 'play'
                    st['turn'] = 'W'
                    st['log'] = ['🧪 혼자 테스트 모드 — 양쪽을 번갈아 조작하세요.']
                    ROOMS[code] = room
                    self._json({'room': code, 'token': ntok, 'color': 'solo'})
                    return
                if data.get('vs_bot'):   # 컴퓨터(봇)와 대전 — 사람=백, 봇=흑
                    code = gen_code()
                    room = new_room(code)
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
                    self._json({'room': code, 'token': token, 'color': room['tokens'][token]})
                    return
                ntok = uuid.uuid4().hex
                color = assign_seat(room, now, ntok)
                room['tokens'][ntok] = color
                room['seen'][ntok] = now
                maybe_setup_timer(room)
                self._json({'room': code, 'token': ntok, 'color': color})
            return

        if u.path == '/action':
            with lock:
                room = self._room(data.get('room'))
                if not room:
                    self._json({'ok': False, 'msg': '방을 찾을 수 없습니다. 새로고침하세요.', 'gone': True})
                    return
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
                if act == 'rematch':
                    room['state'] = new_game()
                    if room.get('solo'):
                        room['state']['phase'] = 'play'
                        room['state']['turn'] = 'W'
                        room['state']['log'] = ['🧪 혼자 테스트 — 재시작.']
                    elif room.get('bot'):
                        bot.setup_and_ready(room['state'], 'B')
                        room['state']['deadline'] = time.time() + SETUP_SECONDS
                        room['state']['log'] = ['🤖 컴퓨터와 대전 — 재대결! 백 배치 후 [준비 완료].']
                    else:
                        maybe_setup_timer(room)
                    self._json({'ok': True})
                    return
                if act == 'resign':
                    ok, msg = apply_resign(st, color)
                    self._json({'ok': ok, 'msg': msg})
                    return
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
                resp = {'ok': ok, 'msg': msg}
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
    srv = ThreadingServer(('0.0.0.0', PORT), Handler)
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
    print(f'  지형({src}, #=숲{len(FORESTS)} ~=강{len(RIVERS)} "=부쉬{len(BUSHES)}):')
    for row in terrain_to_ascii(FORESTS, RIVERS, BUSHES):
        print('    ' + row)
    if USE_PERLIN:
        print('  ↑ 마음에 들면 이 그림을 config.py의 MAP_ROWS에 붙여넣고 USE_PERLIN=False 하면 고정.')
    print('  종료: Ctrl+C')
    print('=' * 54)
    if '--share' in sys.argv:
        start_tunnel(PORT)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print('\n서버 종료.')
