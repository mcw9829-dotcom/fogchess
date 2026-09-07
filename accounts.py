# -*- coding: utf-8 -*-
"""
계정 · 레이팅 (SQLite, 표준 라이브러리만)

  회원가입/로그인/세션  : signup · login · logout · user_by_token
  레이팅(Elo) · 티어    : expected · elo_delta · tier · record_result(회원 vs 회원) · record_vs_fixed(봇 등 고정 레이팅)

보안 메모: 비밀번호는 PBKDF2-HMAC-SHA256(개인 솔트, 20만 회)로 해시만 저장하고 어디에도 평문을 남기지 않는다.
비밀번호는 숫자 4자리 PIN(닉네임=아이디)이라 연속 실패 잠금을 둔다. 세션 토큰은 secrets로 생성. 서버가 HTTP(LAN)라 전송 구간 암호화(TLS)는 없다 — 공개 배포 시 HTTPS 뒤에 둘 것.
DB 파일: fogchess.db (환경변수 FOG_DB 로 경로 변경 가능 — 배포 볼륨용).
"""
import os
import re
import time
import hmac
import hashlib
import secrets
import sqlite3
import threading
from contextlib import contextmanager

from config import RATING_DEFAULT, RATING_FLOOR, ELO_K, RATING_TIERS

DB_PATH = os.environ.get('FOG_DB', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'fogchess.db'))
NAME_RE = re.compile(r'^[A-Za-z0-9가-힣_]{2,12}$')     # 닉네임 = 로그인 아이디(2~12자)
PBKDF_ITERS = 200_000
SESSION_TTL = 30 * 24 * 3600                          # 로그인 세션 유효기간(초) - 30일
PW_MIN, PW_MAX = 8, 64                                # 비밀번호 규칙: 8~64자, 영문·숫자·특수문자 각 1개 이상, 공백 없음
LOGIN_MAX_FAILS, LOGIN_LOCK_SEC = 5, 30               # 비밀번호 무차별 대입 방지: 같은 닉네임 연속 5회 실패 -> 30초 잠금
_fails = {}                                           # name_lc -> {'n': 연속 실패 수, 'until': 잠금 해제 시각}
SCHEMA = '''
CREATE TABLE IF NOT EXISTS users(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL, name_lc TEXT NOT NULL UNIQUE,
  salt BLOB NOT NULL, pw_hash BLOB NOT NULL,
  rating INTEGER NOT NULL,
  wins INTEGER NOT NULL DEFAULT 0, losses INTEGER NOT NULL DEFAULT 0, draws INTEGER NOT NULL DEFAULT 0,
  created REAL NOT NULL);
CREATE TABLE IF NOT EXISTS sessions(
  token TEXT PRIMARY KEY, user_id INTEGER NOT NULL, created REAL NOT NULL);
CREATE TABLE IF NOT EXISTS feedback(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  created REAL NOT NULL, name TEXT, user_id INTEGER,
  category TEXT NOT NULL, message TEXT NOT NULL, room TEXT, ua TEXT);
'''
_lock = threading.Lock()
_ready = False


def _ensure():
    global _ready
    if _ready:
        return
    c = sqlite3.connect(DB_PATH)
    c.executescript(SCHEMA)
    _migrate(c)
    c.commit()
    c.close()
    _ready = True


def _migrate(c):
    """기존 DB에 없는 컬럼을 보태는 마이그레이션(멱등). v1.32: feedback.done(처리됨 표시)."""
    cols = {row[1] for row in c.execute('PRAGMA table_info(feedback)')}
    if cols and 'done' not in cols:
        c.execute('ALTER TABLE feedback ADD COLUMN done INTEGER NOT NULL DEFAULT 0')


def init_db(path=None):
    """DB 준비(멱등). path를 주면 그 파일을 쓴다(테스트용 임시 DB)."""
    global DB_PATH, _ready
    if path:
        DB_PATH = path
        _ready = False
    with _lock:
        _ensure()


@contextmanager
def _db():
    with _lock:
        _ensure()
        c = sqlite3.connect(DB_PATH, timeout=5)
        c.row_factory = sqlite3.Row
        try:
            yield c
            c.commit()
        finally:
            c.close()


def _s(x):
    return '' if x is None else str(x)


def _hash(pw, salt):
    return hashlib.pbkdf2_hmac('sha256', pw.encode('utf-8'), salt, PBKDF_ITERS)


def password_problem(pw):
    """새 비밀번호 규칙 위반 사유(없으면 None): 8~64자, 영문(문자)·숫자·특수문자 각 1개 이상, 공백 없음.
    클라이언트 game.js pwProblem 과 같은 규칙."""
    pw = _s(pw)
    if not (PW_MIN <= len(pw) <= PW_MAX):
        return f'비밀번호는 {PW_MIN}~{PW_MAX}자입니다.'
    if any(ch.isspace() for ch in pw):
        return '비밀번호에 공백은 쓸 수 없습니다.'
    if not any(ch.isalpha() for ch in pw):
        return '비밀번호에 영문(문자)을 넣어주세요.'
    if not any(ch.isdigit() for ch in pw):
        return '비밀번호에 숫자를 넣어주세요.'
    if not any(not ch.isalnum() for ch in pw):
        return '비밀번호에 특수문자(!@#$ 등)를 넣어주세요.'
    return None


def password_weak(pw):
    """옛 규칙(숫자 4자리 등)으로 만든 비밀번호인가 → 로그인은 허용하되 변경을 안내한다."""
    return password_problem(pw) is not None


# ------------------------- 티어 · Elo -------------------------
def tier(rating):
    """레이팅 → 티어 기물 문자(P/N/R/B/Q/K). config.RATING_TIERS(이상 기준)."""
    for floor, t in RATING_TIERS:
        if rating >= floor:
            return t
    return RATING_TIERS[-1][1]


def expected(ra, rb):
    """a가 b를 이길 기대승률(0~1). 점수차 400 = 10배 차이."""
    return 1.0 / (1.0 + 10 ** ((rb - ra) / 400.0))


def elo_delta(ra, rb, score_a, k=ELO_K):
    """a의 변동치. 변동 = K × (결과 − 기대승률) → 약자가 이기면 많이 얻고 강자가 이기면 조금 얻는다."""
    return int(round(k * (score_a - expected(ra, rb))))


def public(row):
    return {'id': row['id'], 'name': row['name'], 'rating': row['rating'], 'tier': tier(row['rating']),
            'wins': row['wins'], 'losses': row['losses'], 'draws': row['draws']}


# ------------------------- 계정 -------------------------
def signup(name, pw):
    """→ ({'session', 'user'}, None) 또는 (None, 오류메시지)"""
    name, pw = _s(name).strip(), _s(pw)                  # 타입이 이상해도(숫자·리스트) 오류 메시지로
    if not NAME_RE.match(name):
        return None, '닉네임은 2~12자(한글·영문·숫자·_)만 가능합니다.'
    err = password_problem(pw)
    if err:
        return None, err
    salt = secrets.token_bytes(16)
    with _db() as c:
        if c.execute('SELECT 1 FROM users WHERE name_lc=?', (name.lower(),)).fetchone():
            return None, '이미 사용 중인 닉네임입니다.'
        c.execute('INSERT INTO users(name, name_lc, salt, pw_hash, rating, created) VALUES(?,?,?,?,?,?)',
                  (name, name.lower(), salt, _hash(pw, salt), RATING_DEFAULT, time.time()))
    return login(name, pw)


def login(name, pw):
    name, pw = _s(name).strip(), _s(pw)
    key = name.lower()
    with _db() as c:
        f = _fails.get(key)
        if f and f['until'] > time.time():                       # 잠금 중(연속 실패)
            return None, f"실패가 많아 잠시 잠겼습니다. {int(f['until'] - time.time()) + 1}초 후 다시 시도하세요."
        row = c.execute('SELECT * FROM users WHERE name_lc=?', (key,)).fetchone()
        if not row or not hmac.compare_digest(_hash(pw or '', row['salt']), row['pw_hash']):
            f = _fails.setdefault(key, {'n': 0, 'until': 0})
            f['n'] += 1
            if f['n'] >= LOGIN_MAX_FAILS:                        # 연속 5회 실패 -> 30초 잠금
                f['n'] = 0
                f['until'] = time.time() + LOGIN_LOCK_SEC
            return None, '닉네임 또는 비밀번호가 맞지 않습니다.'
        _fails.pop(key, None)                                    # 성공 -> 실패 카운트 초기화
        c.execute('DELETE FROM sessions WHERE created < ?', (time.time() - SESSION_TTL,))   # 만료 세션 정리
        token = secrets.token_urlsafe(24)
        c.execute('INSERT INTO sessions(token, user_id, created) VALUES(?,?,?)', (token, row['id'], time.time()))
        return {'session': token, 'user': public(row), 'weakPw': password_weak(pw)}, None   # weakPw: 옛 규칙 비밀번호 → 변경 안내


def change_name(token, new_name):
    """닉네임 변경 → (user, None) 또는 (None, 오류). 다른 회원과 대소문자 무시 중복 불가. 세션·레이팅은 그대로."""
    user = user_by_token(token)
    if not user:
        return None, '로그인이 필요합니다.'
    new_name = _s(new_name).strip()
    if not NAME_RE.match(new_name):
        return None, '닉네임은 2~12자(한글·영문·숫자·_)만 가능합니다.'
    with _db() as c:
        if c.execute('SELECT id FROM users WHERE name_lc=? AND id<>?', (new_name.lower(), user['id'])).fetchone():
            return None, '이미 사용 중인 닉네임입니다.'
        c.execute('UPDATE users SET name=?, name_lc=? WHERE id=?', (new_name, new_name.lower(), user['id']))
    return user_by_id(user['id']), None


def change_password(token, old, new):
    """비밀번호 변경 → (ok, 오류). 현재 비밀번호 확인 + 새 비밀번호 규칙. 성공하면 다른 기기의 세션은 모두 로그아웃.
    현재 비밀번호를 연속 5회 틀리면 30초 잠금(로그인과 같은 규칙)."""
    user = user_by_token(token)
    if not user:
        return False, '로그인이 필요합니다.'
    err = password_problem(new)
    if err:
        return False, err
    key = 'pw:' + user['name'].lower()
    f = _fails.get(key)
    if f and f['until'] > time.time():
        return False, f"실패가 많아 잠시 잠겼습니다. {int(f['until'] - time.time()) + 1}초 후 다시 시도하세요."
    with _db() as c:
        row = c.execute('SELECT * FROM users WHERE id=?', (user['id'],)).fetchone()
        if not hmac.compare_digest(_hash(_s(old), row['salt']), row['pw_hash']):
            f = _fails.setdefault(key, {'n': 0, 'until': 0})
            f['n'] += 1
            if f['n'] >= LOGIN_MAX_FAILS:
                f['n'] = 0
                f['until'] = time.time() + LOGIN_LOCK_SEC
            return False, '현재 비밀번호가 맞지 않습니다.'
        _fails.pop(key, None)
        salt = secrets.token_bytes(16)
        c.execute('UPDATE users SET salt=?, pw_hash=? WHERE id=?', (salt, _hash(_s(new), salt), row['id']))
        c.execute('DELETE FROM sessions WHERE user_id=? AND token<>?', (row['id'], token))   # 다른 기기 로그아웃
    return True, None


def logout(token):
    with _db() as c:
        c.execute('DELETE FROM sessions WHERE token=?', (token or '',))


def user_by_token(token):
    if not token:
        return None
    with _db() as c:
        row = c.execute('SELECT u.* FROM sessions s JOIN users u ON u.id = s.user_id '
                        'WHERE s.token=? AND s.created > ?', (token, time.time() - SESSION_TTL)).fetchone()
        return public(row) if row else None


def user_by_id(uid):
    with _db() as c:
        row = c.execute('SELECT * FROM users WHERE id=?', (uid,)).fetchone()
        return public(row) if row else None


# ------------------------- 결과 반영 -------------------------
def _apply(c, uid, delta, score):
    row = c.execute('SELECT rating FROM users WHERE id=?', (uid,)).fetchone()
    new = max(RATING_FLOOR, row['rating'] + delta)
    col = 'wins' if score == 1 else ('losses' if score == 0 else 'draws')
    c.execute(f'UPDATE users SET rating=?, {col}={col}+1 WHERE id=?', (new, uid))
    return new


def fixed_delta(ra, opp_rating, score, no_loss=False, cap=None):
    """고정 레이팅 상대(컴퓨터)와의 변동치. no_loss=True면 음수는 0(져도 안 떨어짐),
    cap이 있으면 그 이상으로는 오르지 않음(cap 도달 시 상승 0, 넘치는 만큼은 잘라냄)."""
    d = elo_delta(ra, opp_rating, score)
    if no_loss and d < 0:
        d = 0
    if cap is not None and d > 0:
        d = max(0, min(d, cap - ra))
    return d


def record_vs_fixed(uid, opp_rating, score, no_loss=False, cap=None):
    """고정 레이팅 상대(컴퓨터)와의 결과(score=1 승 / 0 패 / 0.5 무) → {'delta', 'rating'}. 전적(승/패/무)은 항상 기록."""
    with _db() as c:
        ra = c.execute('SELECT rating FROM users WHERE id=?', (uid,)).fetchone()['rating']
        new = _apply(c, uid, fixed_delta(ra, opp_rating, score, no_loss, cap), score)
        return {'delta': new - ra, 'rating': new}


def record_result(uid_a, uid_b, score_a):
    """회원 a vs 회원 b 결과(a 기준 1/0/0.5). 변동은 대국 전 레이팅으로 계산 → {'a': {...}, 'b': {...}}"""
    with _db() as c:
        ra = c.execute('SELECT rating FROM users WHERE id=?', (uid_a,)).fetchone()['rating']
        rb = c.execute('SELECT rating FROM users WHERE id=?', (uid_b,)).fetchone()['rating']
        na = _apply(c, uid_a, elo_delta(ra, rb, score_a), score_a)
        nb = _apply(c, uid_b, elo_delta(rb, ra, 1 - score_a), 1 - score_a)
        return {'a': {'delta': na - ra, 'rating': na}, 'b': {'delta': nb - rb, 'rating': nb}}


# ------------------------- 리더보드 -------------------------
def leaderboard(limit=50):
    """레이팅 순 상위 목록 [{rank, name, rating, tier, wins, losses, draws}] (id는 내보내지 않음)"""
    with _db() as c:
        rows = c.execute('SELECT * FROM users ORDER BY rating DESC, wins DESC, created ASC LIMIT ?',
                         (int(limit),)).fetchall()
    out = []
    for i, r in enumerate(rows, 1):
        d = public(r); d.pop('id', None); d['rank'] = i
        out.append(d)
    return out


# ------------------------- 개발자 피드백 -------------------------
FEEDBACK_CATS = ('bug', 'balance', 'idea', 'other')
FEEDBACK_MAX = 1000


def add_feedback(category, message, name=None, user_id=None, room=None, ua=None):
    """피드백 저장 → (ok, 오류메시지). 분류는 FEEDBACK_CATS, 내용은 3~1000자."""
    category = _s(category).strip().lower()
    message = _s(message).strip()
    if category not in FEEDBACK_CATS:
        return False, '분류를 골라주세요.'
    if len(message) < 3:
        return False, '내용을 조금 더 적어주세요(3자 이상).'
    if len(message) > FEEDBACK_MAX:
        return False, f'내용은 {FEEDBACK_MAX}자까지입니다.'
    with _db() as c:
        c.execute('INSERT INTO feedback(created, name, user_id, category, message, room, ua) VALUES(?,?,?,?,?,?,?)',
                  (time.time(), (_s(name).strip()[:16] or None), user_id, category, message,
                   (_s(room).strip()[:8] or None), (_s(ua).strip()[:200] or None)))
    return True, None


def feedback_list(limit=100, include_done=False):
    """피드백 목록(최신순) [{id, created, name, category, message, room, ua, done}]. 기본은 미처리만."""
    with _db() as c:
        rows = c.execute('SELECT id, created, name, user_id, category, message, room, ua, done FROM feedback '
                         + ('' if include_done else 'WHERE done=0 ') + 'ORDER BY id DESC LIMIT ?', (int(limit),)).fetchall()
    return [dict(r) for r in rows]


def feedback_set_done(fid, done=True):
    """처리됨 표시/해제 → 있었으면 True"""
    with _db() as c:
        return c.execute('UPDATE feedback SET done=? WHERE id=?', (1 if done else 0, int(fid))).rowcount == 1


def feedback_delete(fid):
    """피드백 삭제 → 있었으면 True"""
    with _db() as c:
        return c.execute('DELETE FROM feedback WHERE id=?', (int(fid),)).rowcount == 1


def user_count():
    with _db() as c:
        return c.execute('SELECT COUNT(*) FROM users').fetchone()[0]


def users_list():
    """관리자용 전체 회원 목록(레이팅순) [{id, name, rating, tier, wins, losses, draws, created}]"""
    with _db() as c:
        rows = c.execute('SELECT id, name, rating, wins, losses, draws, created FROM users ORDER BY rating DESC, id').fetchall()
    return [dict(public(r), created=r['created']) for r in rows]


if __name__ == '__main__':                         # python accounts.py feedback  → 최근 피드백 출력(서버에서 fly ssh로도)
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == 'feedback':          # feedback [limit] [all]  (기본: 미처리만)
        args = sys.argv[2:]
        nums = [a for a in args if a.isdigit()]
        rows = feedback_list(int(nums[0]) if nums else 50, include_done='all' in args)
        print(f'feedback: {len(rows)} ({"all" if "all" in args else "open"}, newest first)')
        for r in rows:
            when = time.strftime('%Y-%m-%d %H:%M', time.localtime(r['created']))
            flag = '[done] ' if r.get('done') else ''
            print(f"#{r['id']} {flag}[{when}] [{r['category']}] {r['name'] or '(guest)'} room={r['room'] or '-'}\n   {r['message']}")
    elif len(sys.argv) > 1 and sys.argv[1] == 'users':
        rows = users_list()
        print(f'users: {len(rows)} (by rating)')
        for r in rows:
            when = time.strftime('%Y-%m-%d', time.localtime(r['created']))
            print(f"  {r['name']:<16} {r['rating']:>5} {r['tier']}  {r['wins']}승 {r['losses']}패 {r['draws']}무  가입 {when}")
    else:
        print('usage: python accounts.py feedback [limit] [all] | users')
