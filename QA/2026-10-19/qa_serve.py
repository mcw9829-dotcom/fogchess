# -*- coding: utf-8 -*-
"""
길 2 QA용 상주 서버 — dev_server를 고정 포트 + 임시 DB로 띄워 한 판 내내 유지한다.
(운영/개발 DB 불변. 이 프로세스가 살아있는 동안 방 상태가 메모리에 유지됨)

실행(저장소 루트에서, 백그라운드):
  python QA/2026-10-19/qa_serve.py
런타임 상태(접속 주소 qa_session.json, 임시 DB qa-llm.db)는 Git 제외 폴더 .dev-data/ 에 둔다
→ qa_cli.py가 같은 곳을 읽어 접속.
종료: 프로세스를 멈추면 됨(턴 제한 등 QA 오버라이드도 함께 사라짐).
"""
import json
import os
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]      # QA/<날짜>/ → 저장소 루트
sys.path.insert(0, str(ROOT))

# server를 먼저 직접 import → dev_server/pieces가 가리키는 객체와 동일 보장(이중 로드 방지)
import server
import pieces
import dev_server
assert dev_server.server is server, '모듈 이중 로드 감지'

DATA = ROOT / '.dev-data'
SESSION = DATA / 'qa_session.json'
QA_DB = DATA / 'qa-llm.db'
PORT = int(os.environ.get('QA_PORT', '7600'))

# ── QA 전용 런타임 오버라이드(메모리에서만 — 프로세스 종료 시 원상복구) ──
# 길 2는 Kiro가 사람처럼 '천천히' 두므로, 30초 턴 제한/3회 미행동 패배/200턴 무승부가
# QA를 방해한다. config.py 파일은 건드리지 않고, 이 프로세스의 server/pieces 전역만 덮어쓴다.
BIG_SECONDS = 10 ** 9          # 사실상 무한 턴 제한(시간패 방지)
BIG_MISSES = 10 ** 9           # 미행동 자동 패배 방지
BIG_TURN_LIMIT = 10 ** 9       # 턴 한도 무승부 방지
server.TURN_SECONDS = BIG_SECONDS
server.MAX_MISSES = BIG_MISSES
pieces.TURN_SECONDS = BIG_SECONDS       # advance_turn이 turn_deadline을 이 값으로 재설정
pieces.MAX_MISSES = BIG_MISSES
pieces.TURN_LIMIT = BIG_TURN_LIMIT
server.DISCONNECT_FORFEIT = BIG_SECONDS  # 느린 폴링에도 접속 끊김 기권 방지

# 가장 확실한 방지책: 시간패/미행동 패배 경로를 함수 단위로 완전히 무력화.
#  - server.enforce_clock: 사람 차례의 시간패 자동 넘김(폴링/스위퍼에서 호출) → no-op
#  - pieces.time_out:      미행동 누적 → MAX_MISSES회 자동 패배 판정 → no-op
# 함수 교체라 참조 경로 문제 없이 확실히 먹는다. (QA 프로세스 한정, 소스 파일 불변)
server.enforce_clock = lambda room, now: None
pieces.time_out = lambda st: False
server.time_out = pieces.time_out        # server.py가 from pieces import time_out 로 가져가므로 동기화


import uuid


class QAHandler(dev_server.DevHandler):
    """능력 검증용 fixture 방을 즉석 세팅하는 /qa-fixture POST 추가.
    run_godot_smoke.py의 FixtureHandler와 같은 방식(테스트 프로세스에만 존재)."""

    def _post(self):
        if self.path != '/qa-fixture':
            return super()._post()
        length = int(self.headers.get('Content-Length', 0) or 0)
        data = json.loads(self.rfile.read(length).decode('utf-8') or '{}')
        scenario = data.get('scenario')
        with server.lock:
            code = server.gen_code()
            room = server.new_room(code)
            # 시나리오별 지형: scan은 부쉬에 숨은 킹 확인용으로 (3,4)에 부쉬
            room['terrain'] = {'seed': 1, 'forests': set(), 'rivers': set(),
                               'bushes': {(3, 4)} if scenario == 'scan' else set(),
                               'impassable': set()}
            token = uuid.uuid4().hex
            room['solo'] = True                     # 한 토큰이 양쪽을 조작(능력 검증용)
            room['seats'] = {'W': token, 'B': token}
            room['tokens'] = {token: 'solo'}
            room['seen'] = {token: time.time()}
            st = room['state']
            st['phase'] = 'play'
            for p in st['pieces'].values():
                p['alive'] = False                  # 전부 비활성 후 시나리오 기물만 배치

            def place(pid, r, c):
                st['pieces'][pid].update(alive=True, r=r, c=c, moved=True)

            # 공통: 양 킹
            place('W_K1', 11, 11)
            place('B_K1', 3, 4)
            if scenario == 'scan':                  # 부쉬(3,4)에 숨은 흑 킹을 퀸 스캔으로 노출
                place('W_Q1', 6, 4)
            elif scenario == 'fire':                # 비숍 저격 사거리 안의 적
                place('W_B1', 4, 4)
                place('B_P1', 4, 7)                 # 같은 시야/사거리 내 표적
            elif scenario == 'barrage':             # 전차 돌파 십자선상의 적
                place('W_R1', 4, 4)
                place('B_P1', 4, 7)                 # 같은 행 → 돌파 사격선상
            elif scenario == 'promotion':           # 끝줄 직전 폰(승격)
                place('W_P1', 1, 4)
            server.ROOMS[code] = room
            self._json({'room': code, 'token': token, 'scenario': scenario})


def main():
    print('QA 오버라이드 적용:', flush=True)
    print(f"  server.time_out is pieces.time_out: {server.time_out is pieces.time_out}", flush=True)
    print(f"  enforce_clock no-op: {server.enforce_clock.__name__ == '<lambda>'}", flush=True)
    print('  sweeper 미기동(시간패/방정리 비활성) · /qa-fixture 활성', flush=True)
    server.accounts.init_db(str(QA_DB))
    httpd = server.ThreadingServer(('127.0.0.1', PORT), QAHandler)
    # sweeper 스레드는 띄우지 않는다 — 5초마다 enforce_clock/정리를 돌려 QA 중 턴을 넘기는 원인.
    SESSION.write_text(json.dumps({'base': f'http://127.0.0.1:{PORT}', 'pid': os.getpid()}),
                       encoding='utf-8')
    print(f'QA serve: http://127.0.0.1:{PORT}  (db={QA_DB.name})', flush=True)
    try:
        httpd.serve_forever()
    finally:
        httpd.server_close()


if __name__ == '__main__':
    main()
