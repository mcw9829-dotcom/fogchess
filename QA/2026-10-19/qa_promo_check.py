# -*- coding: utf-8 -*-
"""승격 경계 케이스 점검(현재 qa_room.json의 fixture 방 대상). 일회성 QA 스크립트."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import qa_cli as q

rm = q.load_room()
room, tok = rm['room'], rm['seats']['W']


def state():
    _, v = q.call(f'/state?room={room}&token={tok}')
    return v


def piece_at(v, r, c):
    return (v.get('grid') or [[]])[r][c].get('p')


v = state()
print('[1] promote 필드:', v.get('promote'), '| turn', v.get('turn'), '| tc', v.get('turnCount'))
print('    (0,4) 기물:', piece_at(v, 0, 4))

s, res = q.call('/action', {'room': room, 'token': tok, 'type': 'promote', 'choice': 'Q'})
print('[2] Q 승격 시도:', s, res)

s, res = q.call('/action', {'room': room, 'token': tok, 'type': 'move', 'pid': 'W_K1', 'r': 10, 'c': 11})
print('[3] 승격 대기 중 킹 이동 시도:', s, res)
v = state()
print('    킹 위치 (11,11):', piece_at(v, 11, 11), '| (10,11):', piece_at(v, 10, 11))

s, res = q.call('/action', {'room': room, 'token': tok, 'type': 'promote', 'choice': 'N'})
print('[4] N 승격:', s, res)
v = state()
print('    (0,4) 기물:', piece_at(v, 0, 4), '| promote', v.get('promote'),
      '| turn', v.get('turn'), '| tc', v.get('turnCount'))

s, res = q.call('/action', {'room': room, 'token': tok, 'type': 'promote', 'choice': 'R'})
print('[5] 승격 완료 후 재승격 시도:', s, res)
