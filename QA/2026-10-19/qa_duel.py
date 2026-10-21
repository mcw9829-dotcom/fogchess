# -*- coding: utf-8 -*-
"""
M1 QA 하네스 — A(백) vs B(흑) 자동 대국으로 서버/규칙/안개 버그 사냥.

설계(합의된 범위):
  - 접점: HTTP API만 사용(서버 계층·안개·동시성까지 검증). 전체 상태 st는 안 봄.
  - 두뇌: 서버가 준 /state 뷰 + /moves(합법수)만으로 두는 가벼운 휴리스틱(포그 준수).
  - 서버: dev_server를 인프로세스로, 임시 DB + 랜덤 포트로 격리 기동
          (운영/개발 DB·포트 불변). run_godot_smoke.py와 동일한 격리 방식.

오라클(매 턴 자동 검증):
  1) 안개 누출 : 내 뷰에서 f==1(가림)인 칸에 적 기물 p가 노출되면 위반
  2) 턴 정합   : turnCount 단조 증가, turn in {'W','B'}, yourColor 일치
  3) 기물 수   : aliveMe/aliveOpp 비음수, 증가하지 않음(캡처로 줄기만)
  4) 합법수    : 일부러 불법 수를 쏘면 서버가 ok:false로 거부
  5) 종료      : winner 설정 ⇒ phase=='over', 종료 후 action 거부
  6) 견고성    : 깨진 요청에 5xx/크래시 없이 ok:false

실행:
  python QA/2026-10-19/qa_duel.py --games 1 --max-turns 400 --seed 1
"""
import argparse
import json
import os
import random
import sys
import tempfile
import threading
import time
import uuid
from pathlib import Path
from urllib import request as urlrequest
from urllib.error import HTTPError, URLError

ROOT = Path(__file__).resolve().parents[2]      # QA/<날짜>/ → 저장소 루트
sys.path.insert(0, str(ROOT))

import dev_server                       # noqa: E402
server = dev_server.server


# ─────────────────────────── HTTP 클라이언트 ───────────────────────────
class Client:
    def __init__(self, base):
        self.base = base

    def _call(self, path, body=None, method=None, raw=False):
        """반환: (status, parsed_or_text). 네트워크 오류는 예외로 던지지 않고 (0, {...}).
        raw=True면 깨진 바디를 그대로 보내기 위한 경로."""
        url = self.base + path
        data = None
        headers = {}
        if body is not None:
            if raw:
                data = body if isinstance(body, bytes) else str(body).encode('utf-8')
            else:
                data = json.dumps(body).encode('utf-8')
            headers['Content-Type'] = 'application/json'
        req = urlrequest.Request(url, data=data, headers=headers,
                                 method=method or ('POST' if data is not None else 'GET'))
        try:
            with urlrequest.urlopen(req, timeout=15) as resp:
                text = resp.read().decode('utf-8', 'replace')
                return resp.status, _maybe_json(text)
        except HTTPError as e:
            text = e.read().decode('utf-8', 'replace')
            return e.code, _maybe_json(text)
        except URLError as e:
            return 0, {'network_error': True, 'msg': str(e)}

    def get(self, path):
        return self._call(path, method='GET')

    def post(self, path, body, raw=False):
        return self._call(path, body=body, method='POST', raw=raw)


def _maybe_json(text):
    try:
        return json.loads(text)
    except Exception:
        return {'_nonjson': True, 'text': text[:200]}


# ─────────────────────────── 이슈 수집 ───────────────────────────
class Report:
    def __init__(self):
        self.issues = []
        self.cover = {}        # 액션 종류별 누적 실행 횟수(검증 커버리지)

    def add(self, severity, category, detail, ctx=None):
        self.issues.append({'severity': severity, 'category': category,
                            'detail': detail, 'ctx': ctx or {}})
        print(f'  [!] {severity} / {category}: {detail}', flush=True)

    def coverage(self, mix):
        for k, n in (mix or {}).items():
            self.cover[k] = self.cover.get(k, 0) + n

    def summary(self):
        by_sev = {}
        for i in self.issues:
            by_sev[i['severity']] = by_sev.get(i['severity'], 0) + 1
        return by_sev


# ─────────────────────────── 오라클 ───────────────────────────
def oracle_check_view(view, seat, report, seed, turn_no, last_count):
    """한 좌석의 /state 뷰에 대한 불변식 검사. 반환: 현재 aliveOpp(기물수 추적용)."""
    ctx = {'seed': seed, 'turn_no': turn_no, 'seat': seat}

    # (2) 턴 정합
    if view.get('yourColor') != seat:
        report.add('HIGH', 'turn', f"yourColor={view.get('yourColor')} != seat {seat}", ctx)
    if view.get('turn') not in ('W', 'B'):
        report.add('HIGH', 'turn', f"turn 값 비정상: {view.get('turn')}", ctx)

    # (1) 안개 누출 — f==1(가림)인데 '적' 기물이 노출되면 위반
    grid = view.get('grid') or []
    opp = 'B' if seat == 'W' else 'W'
    leaked = []
    for r, row in enumerate(grid):
        for c, cell in enumerate(row):
            p = cell.get('p')
            if p and p.get('o') == opp and cell.get('f') == 1:
                leaked.append((r, c, p.get('t')))
    if leaked:
        report.add('CRITICAL', 'fog_leak',
                   f"가려진 칸에 적 기물 노출 {leaked[:5]}", ctx)

    # (3) 기물 수 — 비음수
    am, ao = view.get('aliveMe'), view.get('aliveOpp')
    if isinstance(am, int) and am < 0:
        report.add('HIGH', 'count', f"aliveMe 음수: {am}", ctx)
    if isinstance(ao, int) and ao < 0:
        report.add('HIGH', 'count', f"aliveOpp 음수: {ao}", ctx)

    # (5) 종료 정합
    if view.get('winner') and view.get('phase') != 'over':
        report.add('HIGH', 'end', f"winner={view['winner']} 인데 phase={view.get('phase')}", ctx)

    return ao


# ─────────────────────────── 두뇌(뷰 기반 휴리스틱) ───────────────────────────
def _tuple_set(cells):
    """[[r,c],...] → {(r,c),...}. 방어적으로 2원소만."""
    out = set()
    for m in cells or []:
        if isinstance(m, (list, tuple)) and len(m) >= 2:
            out.add((m[0], m[1]))
    return out


def pick_move(cli, room, token, view, seat):
    """내 기물 중 합법수/능력이 있는 것을 찾아 수를 고른다.
    우선순위: 능력으로 보이는 적 타격 > 보이는 적 잡는 이동 > 스캔(가끔) > 일반 이동 > 승격 유도.
    반환: action dict 또는 None(둘 수 없음). (포그 준수: 서버 뷰/합법수만 사용)"""
    grid = view.get('grid') or []
    opp = 'B' if seat == 'W' else 'W'
    my_pieces = []
    visible_enemies = set()
    for r, row in enumerate(grid):
        for c, cell in enumerate(row):
            p = cell.get('p')
            if not p:
                continue
            if p.get('o') == seat and p.get('id'):
                my_pieces.append((r, c, p))
            elif p.get('o') == opp:
                visible_enemies.add((r, c))

    random.shuffle(my_pieces)
    N = len(grid)
    promote_row = 0 if seat == 'W' else (N - 1)   # 폰이 도달하면 승격되는 끝줄

    move_fallback = None       # 합법 이동이 있는 첫 기물(일반 전진용)
    scan_candidate = None      # 스캔 가능한 퀸(안개 탐색용)
    barrage_candidate = None   # 돌파 가능한 전차(안개 너머 정찰 사격용)
    promote_push = None        # 승격 줄로 전진 가능한 폰

    for (r, c, p) in my_pieces:
        st, mv = cli.get(f"/moves?room={room}&token={token}&pid={p['id']}")
        if st != 200 or not isinstance(mv, dict):
            continue
        moves = mv.get('moves') or []

        # 1) 능력으로 보이는 적 타격 — 비숍 저격 / 전차 돌파(타깃 칸에 적이 보이면)
        if mv.get('canFire'):
            for (tr, tc) in _tuple_set(mv.get('fireCells')):
                if (tr, tc) in visible_enemies:
                    return {'type': 'fire', 'pid': p['id'], 'r': tr, 'c': tc}
        if mv.get('canBarrage'):
            for (tr, tc) in _tuple_set(mv.get('barrageCells')):
                if (tr, tc) in visible_enemies:
                    return {'type': 'barrage', 'pid': p['id'], 'r': tr, 'c': tc}

        # 2) 보이는 적을 잡는 이동
        for m in moves:
            if (m[0], m[1]) in visible_enemies:
                return {'type': 'move', 'pid': p['id'], 'r': m[0], 'c': m[1]}

        # 3) 스캔 후보 기억(퀸) — 보이는 적이 없을 때 안개 탐색
        if mv.get('canScan') and scan_candidate is None:
            sc = _tuple_set(mv.get('scanCells'))
            if sc:
                tr, tc = random.choice(sorted(sc))
                scan_candidate = {'type': 'scan', 'pid': p['id'], 'r': tr, 'c': tc}

        # 3b) 돌파 후보 기억(전차) — 보이는 적이 없어도 가끔 안개 너머 정찰 사격
        if mv.get('canBarrage') and barrage_candidate is None:
            bc = _tuple_set(mv.get('barrageCells'))
            if bc:
                tr, tc = random.choice(sorted(bc))
                barrage_candidate = {'type': 'barrage', 'pid': p['id'], 'r': tr, 'c': tc}

        # 4) 승격 유도(폰) — 끝줄로 가는 이동이 있으면 기억
        if p.get('t') == 'P' and promote_push is None:
            toward = [m for m in moves if m[0] == promote_row]
            if toward:
                m = toward[0]
                promote_push = {'type': 'move', 'pid': p['id'], 'r': m[0], 'c': m[1]}

        # 5) 일반 이동 폴백 기억
        if moves and move_fallback is None:
            m = random.choice(moves)
            move_fallback = {'type': 'move', 'pid': p['id'], 'r': m[0], 'c': m[1]}

    # 보이는 적이 없을 때: 승격 유도 > 가끔 스캔/돌파(정찰) > 일반 이동
    if promote_push is not None:
        return promote_push
    if scan_candidate is not None and random.random() < 0.25:
        return scan_candidate
    if barrage_candidate is not None and random.random() < 0.25:
        return barrage_candidate
    return move_fallback


# ─────────────────────────── 적대적 프로브(오라클 4·6) ───────────────────────────
def adversarial_probes(cli, room, token, report, seed, turn_no):
    """불법/깨진 요청을 쏴서 서버가 안전하게 거부하는지 확인."""
    ctx = {'seed': seed, 'turn_no': turn_no}

    # (4) 불법 수: 존재하지 않는 pid로 이동
    stt, res = cli.post('/action', {'room': room, 'token': token,
                                    'type': 'move', 'pid': 'NOPE', 'r': 0, 'c': 0})
    if isinstance(res, dict) and res.get('ok') is True:
        report.add('HIGH', 'rule', "없는 pid 이동이 수락됨(ok:true)", ctx)

    # (6) 견고성: 깨진 JSON 바디
    stt, res = cli.post('/action', b'{bad json', raw=True)
    if stt >= 500:
        report.add('HIGH', 'robust', f"깨진 JSON에 5xx 응답: {stt}", ctx)

    # (6) 견고성: 필드 타입 오류
    stt, res = cli.post('/action', {'room': room, 'token': token,
                                    'type': 'move', 'pid': 123, 'r': 'x', 'c': None})
    if stt >= 500:
        report.add('HIGH', 'robust', f"타입 오류에 5xx 응답: {stt}", ctx)


# ─────────────────────────── 한 판 ───────────────────────────
def play_one(cli, report, seed, max_turns, do_probes):
    random.seed(seed)

    # A(백) 방 생성 → B(흑) 참가
    stt, ra = cli.post('/join', {'name': 'QA_A'})
    if not (isinstance(ra, dict) and ra.get('token')):
        report.add('CRITICAL', 'setup', f"/join(A) 실패: {ra}", {'seed': seed})
        return 'error'
    room, tok_a, col_a = ra['room'], ra['token'], ra.get('color')

    stt, rb = cli.post('/join', {'room': room, 'name': 'QA_B'})
    if not (isinstance(rb, dict) and rb.get('token')):
        report.add('CRITICAL', 'setup', f"/join(B) 실패: {rb}", {'seed': seed})
        return 'error'
    tok_b, col_b = rb['token'], rb.get('color')

    seats = {col_a: tok_a, col_b: tok_b}
    if set(seats) != {'W', 'B'}:
        report.add('CRITICAL', 'setup', f"좌석 배정 비정상: A={col_a} B={col_b}", {'seed': seed})
        return 'error'

    # 배치 + 준비
    for col, tok in seats.items():
        cli.post('/action', {'room': room, 'token': tok, 'type': 'autoplace', 'mode': 'default'})
    for col, tok in seats.items():
        cli.post('/action', {'room': room, 'token': tok, 'type': 'ready', 'value': True})

    # play 진입 확인
    stt, v = cli.get(f"/state?room={room}&token={tok_a}")
    if v.get('phase') != 'play':
        report.add('HIGH', 'setup', f"ready 후 phase != play: {v.get('phase')}", {'seed': seed})
        return 'error'

    last_count = {'W': None, 'B': None}
    last_turncount = -1
    probed = False
    action_mix = {}        # 실행된 액션 종류 집계(검증 커버리지 확인용)

    for turn_no in range(max_turns):
        if turn_no % 10 == 0:
            print(f'    ... turn {turn_no}', flush=True)
        stt, v = cli.get(f"/state?room={room}&token={tok_a}")  # A 시점
        if not isinstance(v, dict) or v.get('_nonjson'):
            report.add('CRITICAL', 'robust', f"/state 비정상 응답: {v}", {'seed': seed})
            return 'error'
        if v.get('phase') == 'over':
            report.coverage(action_mix)
            return v.get('winner') or 'draw'

        side = v.get('turn')
        tok = seats.get(side)
        if tok is None:
            report.add('HIGH', 'turn', f"turn={side} 좌석 없음", {'seed': seed})
            return 'error'

        # 두는 쪽 시점 뷰로 오라클 + 수 선택
        stt, sv = cli.get(f"/state?room={room}&token={tok}")
        oracle_check_view(sv, side, report, seed, turn_no, last_count)

        # turnCount 단조성
        tc = sv.get('turnCount', 0)
        if tc < last_turncount:
            report.add('HIGH', 'turn', f"turnCount 역행: {last_turncount} -> {tc}",
                       {'seed': seed, 'turn_no': turn_no})
        last_turncount = tc

        # 기물 수 증가 감시
        ao = sv.get('aliveMe')
        if last_count[side] is not None and isinstance(ao, int) and ao > last_count[side]:
            report.add('HIGH', 'count', f"{side} 기물 증가 {last_count[side]} -> {ao}(승격 외 불가)",
                       {'seed': seed, 'turn_no': turn_no})
        if isinstance(ao, int):
            last_count[side] = ao

        # 적대적 프로브는 한 판에 한 번만(중반)
        if do_probes and not probed and turn_no == min(5, max_turns - 1):
            adversarial_probes(cli, room, tok, report, seed, turn_no)
            probed = True

        # 승격 대기면 전차로
        if sv.get('promote'):
            cli.post('/action', {'room': room, 'token': tok, 'type': 'promote', 'choice': 'R'})
            continue

        action = pick_move(cli, room, tok, sv, side)
        if action is None:
            # 둘 수 없음 — 서버가 처리(패스/시간)하도록 잠깐 둠. 교착 방지로 중단.
            report.add('LOW', 'stuck', f"{side} 둘 수 있는 수 없음(turn {turn_no})",
                       {'seed': seed})
            report.coverage(action_mix)
            return 'draw'
        atype = action.get('type')
        action.update({'room': room, 'token': tok})
        stt, res = cli.post('/action', action)
        if stt >= 500:
            report.add('CRITICAL', 'robust', f"정상 수에 5xx: {stt} {res}",
                       {'seed': seed, 'turn_no': turn_no, 'action': action})
            return 'error'
        # 서버가 수락한 액션만 커버리지로 집계
        if isinstance(res, dict) and res.get('ok'):
            action_mix[atype] = action_mix.get(atype, 0) + 1

    report.coverage(action_mix)
    return 'maxturns'


# ─────────────────────────── 서버 기동 + 메인 ───────────────────────────
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--games', type=int, default=1)
    ap.add_argument('--max-turns', type=int, default=400)
    ap.add_argument('--seed', type=int, default=1)
    ap.add_argument('--no-probes', action='store_true', help='적대적 프로브 끄기')
    args = ap.parse_args()

    report = Report()
    results = {}

    with tempfile.TemporaryDirectory(prefix='fogchess-qa-') as directory:
        server.accounts.init_db(str(Path(directory) / 'qa.db'))
        httpd = server.ThreadingServer(('127.0.0.1', 0), dev_server.DevHandler)
        threading.Thread(target=httpd.serve_forever, daemon=True).start()
        port = httpd.server_port
        cli = Client(f'http://127.0.0.1:{port}')
        print(f'QA 서버: http://127.0.0.1:{port} (임시 DB)', flush=True)

        t0 = time.time()
        try:
            for g in range(args.games):
                seed = args.seed + g
                print(f'[판 {g+1}/{args.games}] seed={seed}', flush=True)
                res = play_one(cli, report, seed, args.max_turns, not args.no_probes)
                results[res] = results.get(res, 0) + 1
        finally:
            httpd.shutdown()
            httpd.server_close()

    print('\n===== QA 결과 =====', flush=True)
    print(f'판 결과: {results}  ({time.time()-t0:.1f}s)')
    print(f'액션 커버리지(수락된 수): {report.cover}')
    for need in ('fire', 'barrage', 'scan'):
        if report.cover.get(need, 0) == 0:
            print(f"  (주의) 능력 '{need}' 경로를 한 번도 밟지 않음 — 커버리지 부족")
    print(f'이슈 {len(report.issues)}건  심각도별: {report.summary()}')
    for i in report.issues:
        print(f"  - {i['severity']}/{i['category']}: {i['detail']}  ctx={i['ctx']}")
    # 파이썬 파서용 요약 라인
    print(f"QA_ISSUES={len(report.issues)}")
    return 1 if any(i['severity'] in ('CRITICAL', 'HIGH') for i in report.issues) else 0


if __name__ == '__main__':
    raise SystemExit(main())
