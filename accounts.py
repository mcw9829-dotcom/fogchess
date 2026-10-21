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
import json
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
# ---- 복구 코드(v1.50~): 비밀번호를 잊었을 때 계정을 되찾는 1회용 열쇠. 가입 때 한 번 보여주고 해시(SHA-256)만 저장 ----
RECOV_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'   # 헷갈리는 0/O/1/I 제외 · 8자 = 40비트
RECOV_MAX_FAILS, RECOV_LOCK_SEC = 5, 600              # 복구 코드 5회 틀리면 그 IP 10분 잠금
SCHEMA = '''
CREATE TABLE IF NOT EXISTS users(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL, name_lc TEXT NOT NULL UNIQUE,
  salt BLOB NOT NULL, pw_hash BLOB NOT NULL,
  rating INTEGER NOT NULL,
  wins INTEGER NOT NULL DEFAULT 0, losses INTEGER NOT NULL DEFAULT 0, draws INTEGER NOT NULL DEFAULT 0,
  created REAL NOT NULL,
  recov_hash TEXT, recov_at REAL);                    -- 복구 코드 해시(코드 자체는 저장 안 함)
CREATE TABLE IF NOT EXISTS sessions(
  token TEXT PRIMARY KEY, user_id INTEGER NOT NULL, created REAL NOT NULL);
CREATE TABLE IF NOT EXISTS feedback(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  created REAL NOT NULL, name TEXT, user_id INTEGER,
  category TEXT NOT NULL, message TEXT NOT NULL, room TEXT, ua TEXT);
CREATE TABLE IF NOT EXISTS games(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  created REAL NOT NULL, user_id INTEGER NOT NULL,
  kind TEXT NOT NULL, result TEXT NOT NULL, reason TEXT,
  opp_name TEXT, opp_user_id INTEGER, opp_rating INTEGER,
  rated INTEGER NOT NULL DEFAULT 0, delta INTEGER, rating_after INTEGER, room TEXT);
CREATE INDEX IF NOT EXISTS games_user ON games(user_id, id);
CREATE TABLE IF NOT EXISTS game_settlements(
 game_id TEXT PRIMARY KEY, result TEXT NOT NULL, created REAL NOT NULL);
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
    ucols = {row[1] for row in c.execute('PRAGMA table_info(users)')}        # v1.50: 복구 코드 컬럼
    if ucols:
        for col, ddl in (('recov_hash', 'TEXT'), ('recov_at', 'REAL')):
            if col not in ucols:
                c.execute(f'ALTER TABLE users ADD COLUMN {col} {ddl}')
        c.execute('CREATE INDEX IF NOT EXISTS users_recov ON users(recov_hash)')


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


def private(row):
    """본인에게만 주는 정보(/me·로그인 응답): public + 복구 코드 보유 여부"""
    d = public(row)
    d['hasRecovery'] = bool(row['recov_hash'])
    return d


# ------------------------- 세션 · 복구 코드 · 비밀번호 확인 도우미 -------------------------
def _new_session(c, uid):
    c.execute('DELETE FROM sessions WHERE created < ?', (time.time() - SESSION_TTL,))   # 만료 세션 정리
    token = secrets.token_urlsafe(24)
    c.execute('INSERT INTO sessions(token, user_id, created) VALUES(?,?,?)', (token, uid, time.time()))
    return token


def _new_recovery():
    s = ''.join(secrets.choice(RECOV_ALPHABET) for _ in range(8))
    return f'FOG-{s[:4]}-{s[4:]}'


def _recov_norm(code):
    """입력 정리: 대문자화, 구분자·공백 제거, 'FOG' 접두 제거 → 8자 비밀 부분"""
    s = re.sub(r'[^A-Z0-9]', '', _s(code).upper())
    return s[3:] if s.startswith('FOG') else s


def _recov_hash(secret):
    return hashlib.sha256(('recov:' + secret).encode('utf-8')).hexdigest()


def _verify_pw(c, row, pw, key):
    """현재 비밀번호 확인(연속 5회 실패 → 30초 잠금, 로그인과 같은 규칙) → 오류 또는 None"""
    f = _fails.get(key)
    if f and f['until'] > time.time():
        return f"실패가 많아 잠시 잠겼습니다. {int(f['until'] - time.time()) + 1}초 후 다시 시도하세요."
    if not hmac.compare_digest(_hash(_s(pw), row['salt']), row['pw_hash']):
        f = _fails.setdefault(key, {'n': 0, 'until': 0})
        f['n'] += 1
        if f['n'] >= LOGIN_MAX_FAILS:
            f['n'] = 0
            f['until'] = time.time() + LOGIN_LOCK_SEC
        return '현재 비밀번호가 맞지 않습니다.'
    _fails.pop(key, None)
    return None


# ------------------------- 계정 -------------------------
def signup(name, pw):
    """→ ({'session','user','recovery'}, None) 또는 (None, 오류메시지). 복구 코드(recovery)는 이때 한 번만 보여준다."""
    name, pw = _s(name).strip(), _s(pw)                  # 타입이 이상해도(숫자·리스트) 오류 메시지로
    if not NAME_RE.match(name):
        return None, '닉네임은 2~12자(한글·영문·숫자·_)만 가능합니다.'
    err = password_problem(pw)
    if err:
        return None, err
    salt, recov = secrets.token_bytes(16), _new_recovery()
    with _db() as c:
        if c.execute('SELECT 1 FROM users WHERE name_lc=?', (name.lower(),)).fetchone():
            return None, '이미 사용 중인 닉네임입니다.'
        c.execute('INSERT INTO users(name, name_lc, salt, pw_hash, rating, created, recov_hash, recov_at) VALUES(?,?,?,?,?,?,?,?)',
                  (name, name.lower(), salt, _hash(pw, salt), RATING_DEFAULT, time.time(), _recov_hash(_recov_norm(recov)), time.time()))
    res, err = login(name, pw)
    if res:
        res['recovery'] = recov
    return res, err


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
        token = _new_session(c, row['id'])
        return {'session': token, 'user': private(row), 'weakPw': password_weak(pw)}, None   # weakPw: 옛 규칙 비밀번호 → 변경 안내


def recover_with_code(code, new_pw, ip=None):
    """복구 코드로 비밀번호 재설정 → ({'session','user','recovery'(새 코드)}, None). 코드는 1회용: 성공하면 새로 발급.
    모든 기기 로그아웃 뒤 새 세션. IP당 5회 틀리면 10분 잠금(코드는 40비트)."""
    key = 'recov:' + (ip or '?')
    f = _fails.get(key)
    if f and f['until'] > time.time():
        return None, f"틀린 시도가 많아 잠시 잠겼어요. {int(f['until'] - time.time()) + 1}초 후 다시."
    err = password_problem(new_pw)
    if err:
        return None, err
    secret = _recov_norm(code)
    with _db() as c:
        row = c.execute('SELECT * FROM users WHERE recov_hash=?', (_recov_hash(secret),)).fetchone() if len(secret) == 8 else None
        if not row:
            f = _fails.setdefault(key, {'n': 0, 'until': 0})
            f['n'] += 1
            if f['n'] >= RECOV_MAX_FAILS:
                f['n'] = 0
                f['until'] = time.time() + RECOV_LOCK_SEC
            return None, '복구 코드가 맞지 않아요. FOG-XXXX-XXXX 형식을 확인해 주세요.'
        _fails.pop(key, None)
        salt, recov = secrets.token_bytes(16), _new_recovery()
        c.execute('UPDATE users SET salt=?, pw_hash=?, recov_hash=?, recov_at=? WHERE id=?',
                  (salt, _hash(_s(new_pw), salt), _recov_hash(_recov_norm(recov)), time.time(), row['id']))
        c.execute('DELETE FROM sessions WHERE user_id=?', (row['id'],))
        token = _new_session(c, row['id'])
        _fails.pop(row['name'].lower(), None)
        urow = c.execute('SELECT * FROM users WHERE id=?', (row['id'],)).fetchone()
        return {'session': token, 'user': private(urow), 'recovery': recov, 'weakPw': False}, None


def recovery_reissue(token, pw):
    """복구 코드 (재)발급: 현재 비밀번호 확인. 이전 코드는 무효 → (새 코드, None)"""
    user = user_by_token(token)
    if not user:
        return None, '로그인이 필요합니다.'
    with _db() as c:
        row = c.execute('SELECT * FROM users WHERE id=?', (user['id'],)).fetchone()
        err = _verify_pw(c, row, pw, 'pw:' + row['name'].lower())
        if err:
            return None, err
        recov = _new_recovery()
        c.execute('UPDATE users SET recov_hash=?, recov_at=? WHERE id=?', (_recov_hash(_recov_norm(recov)), time.time(), row['id']))
    return recov, None


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
    with _db() as c:
        row = c.execute('SELECT * FROM users WHERE id=?', (user['id'],)).fetchone()
        err = _verify_pw(c, row, old, 'pw:' + user['name'].lower())
        if err:
            return False, err
        salt = secrets.token_bytes(16)
        c.execute('UPDATE users SET salt=?, pw_hash=? WHERE id=?', (salt, _hash(_s(new), salt), row['id']))
        c.execute('DELETE FROM sessions WHERE user_id=? AND token<>?', (row['id'], token))   # 다른 기기 로그아웃
    return True, None


def logout(token):
    with _db() as c:
        c.execute('DELETE FROM sessions WHERE token=?', (token or '',))


def user_by_token(token, private_info=False):
    """세션 토큰 → 회원(public). private_info=True 면 본인용(복구 코드 보유 여부)까지."""
    if not token:
        return None
    with _db() as c:
        row = c.execute('SELECT u.* FROM sessions s JOIN users u ON u.id = s.user_id '
                        'WHERE s.token=? AND s.created > ?', (token, time.time() - SESSION_TTL)).fetchone()
        return (private(row) if private_info else public(row)) if row else None


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


def settle_game(game_id, request):
    """Commit ratings, both history rows, and the idempotency receipt atomically."""
    with _db() as c:
        c.execute('BEGIN IMMEDIATE')
        existing = c.execute('SELECT result FROM game_settlements WHERE game_id=?', (game_id,)).fetchone()
        if existing:
            return json.loads(existing['result'])
        users, result = request['users'], {}
        before = {side: c.execute('SELECT rating FROM users WHERE id=?', (uid,)).fetchone()['rating']
                  for side, uid in users.items()}
        if request['rated']:
            for side, uid in users.items():
                score = request['scores'][side]
                opp = 'B' if side == 'W' else 'W'
                if request['bot']:
                    delta = fixed_delta(before[side], request['bot_rating'], score,
                                        request['no_loss'], request['cap'])
                else:
                    delta = elo_delta(before[side], before[opp], score)
                rating = _apply(c, uid, delta, score)
                result[side] = {'delta': rating-before[side], 'rating': rating}
        for side, uid in users.items():
            opp = 'B' if side == 'W' else 'W'
            rr = result.get(side)
            score = request['scores'][side]
            c.execute('INSERT INTO games(created,user_id,kind,result,reason,opp_name,opp_user_id,opp_rating,rated,delta,rating_after,room) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',
                      (request['created'], uid, request['kind'], 'draw' if score == .5 else ('win' if score == 1 else 'loss'),
                       request['reason'], request['names'].get(opp, '상대'), users.get(opp),
                       request['bot_rating'] if request['bot'] else before.get(opp, request['ratings'].get(opp)),
                       int(bool(rr)), rr['delta'] if rr else None, rr['rating'] if rr else None, request['room']))
        c.execute('INSERT INTO game_settlements VALUES(?,?,?)', (game_id, json.dumps(result), time.time()))
        return result


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


# ------------------------- 전적(게임 기록) -------------------------
def add_game(user_id, kind, result, reason, opp_name, opp_user_id, opp_rating, rated, delta, rating_after, room):
    """게임 한 판의 결과를 회원 기준으로 한 줄 저장. kind: match/bot/lobby · result: win/loss/draw ·
    reason: king/resign/disconnect/timeout/draw · rated면 delta·rating_after."""
    with _db() as c:
        c.execute('INSERT INTO games(created, user_id, kind, result, reason, opp_name, opp_user_id, opp_rating, rated, delta, rating_after, room) '
                  'VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',
                  (time.time(), int(user_id), kind, result, reason, opp_name, opp_user_id, opp_rating,
                   1 if rated else 0, delta, rating_after, room))


def game_history(user_id, limit=20):
    """최근 전적(최신순) [{id, created, kind, result, reason, opp_name, opp_rating, rated, delta, rating_after, room}]"""
    with _db() as c:
        rows = c.execute('SELECT id, created, kind, result, reason, opp_name, opp_user_id, opp_rating, rated, delta, rating_after, room '
                         'FROM games WHERE user_id=? ORDER BY id DESC LIMIT ?', (int(user_id), int(limit))).fetchall()
    return [dict(r) for r in rows]


def user_count():
    with _db() as c:
        return c.execute('SELECT COUNT(*) FROM users').fetchone()[0]


def users_list():
    """관리자용 전체 회원 목록(레이팅순) [{id, name, rating, tier, wins, losses, draws, created, hasRecovery}]"""
    with _db() as c:
        rows = c.execute('SELECT * FROM users ORDER BY rating DESC, id').fetchall()
    return [dict(public(r), created=r['created'], hasRecovery=bool(r['recov_hash'])) for r in rows]


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
