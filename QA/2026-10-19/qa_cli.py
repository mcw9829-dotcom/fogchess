# -*- coding: utf-8 -*-
"""
길 2 QA CLI — Kiro(사람 역할 LLM)가 A(백)/B(흑)를 번갈아 두며 QA하는 조작 도구.
qa_serve.py가 띄운 상주 서버에 HTTP로 붙는다. 포그 준수: 각 좌석은 자기 뷰만 본다.

명령(저장소 루트에서, qa_serve.py 실행 중일 때):
  python QA/2026-10-19/qa_cli.py new                 새 방 생성 + 양쪽 배치/ready → play
  python QA/2026-10-19/qa_cli.py fixture <시나리오>   능력 검증용 방(scan|fire|barrage|promotion)
  python QA/2026-10-19/qa_cli.py view W              백 시점 보드/합법수/오라클 출력
  python QA/2026-10-19/qa_cli.py view B              흑 시점
  python QA/2026-10-19/qa_cli.py moves W W_P1        특정 기물의 합법수/능력 상세
  python QA/2026-10-19/qa_cli.py act W move W_P1 9 2 수 두기 (move|fire|barrage|scan|promote)
      - move/fire/barrage/scan: act <seat> <type> <pid> <r> <c>
      - promote:               act <seat> promote <pid> <choice: R|N|B>
  python QA/2026-10-19/qa_cli.py raw W '{"type":...}' 임의 JSON 액션(적대적 프로브용)

상태는 .dev-data/qa_session.json (서버 주소) + .dev-data/qa_room.json (방/토큰)에 저장(Git 제외).
"""
import json
import sys
from pathlib import Path
from urllib import request as urlrequest
from urllib.error import HTTPError, URLError

DATA = Path(__file__).resolve().parents[2] / '.dev-data'   # 런타임 상태는 Git 제외 폴더에
DATA.mkdir(exist_ok=True)
SESSION = DATA / 'qa_session.json'
ROOMF = DATA / 'qa_room.json'

GLYPH_TERR = {0: '.', 1: '#', 2: '~', 3: '%'}   # 0 평지 1 숲 2 강 3 부쉬


def base():
    s = json.loads(SESSION.read_text(encoding='utf-8'))
    return s['base']


def call(path, body=None, raw_body=None):
    url = base() + path
    data = None
    headers = {}
    if raw_body is not None:
        data = raw_body.encode('utf-8'); headers['Content-Type'] = 'application/json'
    elif body is not None:
        data = json.dumps(body).encode('utf-8'); headers['Content-Type'] = 'application/json'
    req = urlrequest.Request(url, data=data, headers=headers,
                             method='POST' if data is not None else 'GET')
    try:
        with urlrequest.urlopen(req, timeout=15) as r:
            txt = r.read().decode('utf-8', 'replace')
            return r.status, _json(txt)
    except HTTPError as e:
        return e.code, _json(e.read().decode('utf-8', 'replace'))
    except URLError as e:
        return 0, {'network_error': True, 'msg': str(e)}


def _json(txt):
    try:
        return json.loads(txt)
    except Exception:
        return {'_nonjson': True, 'text': txt[:300]}


def load_room():
    return json.loads(ROOMF.read_text(encoding='utf-8'))


# ─────────────── 명령: new ───────────────
def cmd_new():
    s, ra = call('/join', {'name': 'QA_A'})
    room, tok_a, col_a = ra['room'], ra['token'], ra['color']
    s, rb = call('/join', {'room': room, 'name': 'QA_B'})
    tok_b, col_b = rb['token'], rb['color']
    seats = {col_a: tok_a, col_b: tok_b}
    if set(seats) != {'W', 'B'}:
        print('좌석 배정 실패:', seats); return
    for col, tok in seats.items():
        call('/action', {'room': room, 'token': tok, 'type': 'autoplace', 'mode': 'default'})
    for col, tok in seats.items():
        call('/action', {'room': room, 'token': tok, 'type': 'ready', 'value': True})
    ROOMF.write_text(json.dumps({'room': room, 'seats': seats}), encoding='utf-8')
    s, v = call(f'/state?room={room}&token={tok_a}')
    print(f"방 {room} 생성. phase={v.get('phase')} turn={v.get('turn')}")
    render(v, 'W')


# ─────────────── 보드 렌더 + 오라클 ───────────────
def render(v, seat):
    grid = v.get('grid') or []
    opp = 'B' if seat == 'W' else 'W'
    print(f"--- {seat} 시점 | phase={v.get('phase')} turn={v.get('turn')} "
          f"turnCount={v.get('turnCount')} winner={v.get('winner')} "
          f"aliveMe={v.get('aliveMe')} aliveOpp={v.get('aliveOpp')} ---")
    print('   ' + ' '.join(f'{c:2d}' for c in range(len(grid))))
    for r, row in enumerate(grid):
        cells = []
        for c, cell in enumerate(row):
            p = cell.get('p')
            if cell.get('f') == 1:
                ch = ' ?'                    # 안개(가림)
            elif p:
                t = p.get('t', '?')
                ch = (' ' + t) if p.get('o') == seat else (' ' + t.lower())
            else:
                ch = ' ' + GLYPH_TERR.get(cell.get('t', 0), '.')
            cells.append(ch)
        print(f'{r:2d} ' + ' '.join(cells))
    st = v.get('scanTiles') or []
    if st:
        print('scanTiles(감시중):', st)
    # 오라클
    issues = oracle(v, seat)
    if issues:
        for it in issues:
            print('  [!] ', it)
    else:
        print('  (오라클 통과)')


def oracle(v, seat):
    out = []
    opp = 'B' if seat == 'W' else 'W'
    if v.get('yourColor') != seat:
        out.append(f"yourColor={v.get('yourColor')} != {seat}")
    if v.get('turn') not in ('W', 'B'):
        out.append(f"turn 비정상: {v.get('turn')}")
    for r, row in enumerate(v.get('grid') or []):
        for c, cell in enumerate(row):
            p = cell.get('p')
            if p and p.get('o') == opp and cell.get('f') == 1:
                out.append(f"안개 누출: ({r},{c}) 적 {p.get('t')} 가려진 칸에 노출")
    if isinstance(v.get('aliveMe'), int) and v['aliveMe'] < 0:
        out.append('aliveMe 음수')
    if v.get('winner') and v.get('phase') != 'over':
        out.append(f"winner={v['winner']} 인데 phase={v.get('phase')}")
    return out


# ─────────────── 명령: view / moves / act / raw ───────────────
def cmd_view(seat):
    rm = load_room()
    tok = rm['seats'][seat]
    s, v = call(f"/state?room={rm['room']}&token={tok}")
    render(v, seat)
    # 두는 쪽이면 내 기물별 합법수 요약
    if v.get('turn') == seat and v.get('phase') == 'play':
        print('내 기물 합법수 요약:')
        for r, row in enumerate(v.get('grid') or []):
            for c, cell in enumerate(row):
                p = cell.get('p')
                if p and p.get('o') == seat and p.get('id'):
                    s2, mv = call(f"/moves?room={rm['room']}&token={tok}&pid={p['id']}")
                    caps = []
                    if mv.get('moves'): caps.append(f"move×{len(mv['moves'])}")
                    if mv.get('canFire') and mv.get('fireCells'): caps.append('fire')
                    if mv.get('canBarrage') and mv.get('barrageCells'): caps.append('barrage')
                    if mv.get('canScan') and mv.get('scanCells'): caps.append('scan')
                    if caps:
                        print(f"  {p['id']}@({r},{c}) {p['t']}: {', '.join(caps)}")


def cmd_moves(seat, pid):
    rm = load_room()
    tok = rm['seats'][seat]
    s, mv = call(f"/moves?room={rm['room']}&token={tok}&pid={pid}")
    print(json.dumps(mv, ensure_ascii=False, indent=1))


def cmd_act(seat, argv):
    rm = load_room()
    tok = rm['seats'][seat]
    atype = argv[0]
    body = {'room': rm['room'], 'token': tok, 'type': atype}
    if atype == 'promote':
        body['pid'] = argv[1]; body['choice'] = argv[2]
    else:
        body['pid'] = argv[1]; body['r'] = int(argv[2]); body['c'] = int(argv[3])
    s, res = call('/action', body)
    print(f"act {seat} {atype} -> status={s} {res}")
    s, v = call(f"/state?room={rm['room']}&token={tok}")
    render(v, seat)


def cmd_raw(seat, raw_json):
    rm = load_room()
    tok = rm['seats'][seat]
    try:
        obj = json.loads(raw_json)
        obj.setdefault('room', rm['room']); obj.setdefault('token', tok)
        s, res = call('/action', raw_body=json.dumps(obj))
    except Exception:
        s, res = call('/action', raw_body=raw_json)   # 깨진 JSON 그대로(견고성 테스트)
    print(f"raw {seat} -> status={s} {res}")


def cmd_fixture(scenario):
    """능력 검증용 fixture 방 생성(solo: 한 토큰이 양쪽 조작)."""
    s, r = call('/qa-fixture', {'scenario': scenario})
    if not (isinstance(r, dict) and r.get('token')):
        print('fixture 실패:', r); return
    room, tok = r['room'], r['token']
    ROOMF.write_text(json.dumps({'room': room, 'seats': {'W': tok, 'B': tok}}), encoding='utf-8')
    print(f"fixture '{scenario}' 방 {room} 생성 (solo 토큰)")
    s, v = call(f'/state?room={room}&token={tok}')
    render(v, 'W')


def main():
    a = sys.argv[1:]
    if not a:
        print(__doc__); return
    cmd = a[0]
    if cmd == 'new':
        cmd_new()
    elif cmd == 'fixture':
        cmd_fixture(a[1])
    elif cmd == 'view':
        cmd_view(a[1])
    elif cmd == 'moves':
        cmd_moves(a[1], a[2])
    elif cmd == 'act':
        cmd_act(a[1], a[2:])
    elif cmd == 'raw':
        cmd_raw(a[1], a[2])
    else:
        print('알 수 없는 명령:', cmd); print(__doc__)


if __name__ == '__main__':
    main()
