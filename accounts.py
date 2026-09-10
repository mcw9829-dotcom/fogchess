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
import json
import time
import hmac
import hashlib
import secrets
import sqlite3
import threading
from contextlib import contextmanager

from config import RATING_DEFAULT, RATING_FLOOR, ELO_K, RATING_TIERS
import mailer

DB_PATH = os.environ.get('FOG_DB', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'fogchess.db'))
NAME_RE = re.compile(r'^[A-Za-z0-9가-힣_]{2,12}$')     # 닉네임 = 로그인 아이디(2~12자)
PBKDF_ITERS = 200_000
SESSION_TTL = 30 * 24 * 3600                          # 로그인 세션 유효기간(초) - 30일
PW_MIN, PW_MAX = 8, 64                                # 비밀번호 규칙: 8~64자, 영문·숫자·특수문자 각 1개 이상, 공백 없음
LOGIN_MAX_FAILS, LOGIN_LOCK_SEC = 5, 30               # 비밀번호 무차별 대입 방지: 같은 닉네임 연속 5회 실패 -> 30초 잠금
_fails = {}                                           # name_lc -> {'n': 연속 실패 수, 'until': 잠금 해제 시각}
# ---- 이메일 인증 · 복구 코드(v1.50) ----
EMAIL_RE = re.compile(r'^[^\s@]+@[^\s@]+\.[A-Za-z0-9-]{2,}$')
EMAIL_MAX = 120
CODE_TTL = 10 * 60                                    # 인증 코드(6자리) 유효 10분
CODE_MAX_ATTEMPTS = 5                                 # 한 코드를 5회 틀리면 무효(다시 요청)
SEND_COOLDOWN = 60                                    # 같은 주소로 재발송 간격(초)
SEND_MAX_EMAIL_HOUR = 5                               # 주소당 시간당 발송 상한
SEND_MAX_IP_HOUR = 20                                 # IP당 시간당 발송 상한
RECOV_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'   # 복구 코드 글자(헷갈리는 0/O/1/I 제외) 8자 = 40비트
RECOV_MAX_FAILS, RECOV_LOCK_SEC = 5, 600              # 복구 코드 5회 틀리면 그 IP 10분 잠금
_sends = {}                                           # 발송 기록 ('e', 주소) / ('ip', ip) -> [시각...]
SCHEMA = '''
CREATE TABLE IF NOT EXISTS users(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL, name_lc TEXT NOT NULL UNIQUE,
  salt BLOB NOT NULL, pw_hash BLOB NOT NULL,
  rating INTEGER NOT NULL,
  wins INTEGER NOT NULL DEFAULT 0, losses INTEGER NOT NULL DEFAULT 0, draws INTEGER NOT NULL DEFAULT 0,
  created REAL NOT NULL,
  email TEXT, email_lc TEXT, email_verified INTEGER NOT NULL DEFAULT 0,   -- 인증된 이메일(찾기용) — 공개 정보엔 안 나감
  recov_hash TEXT, recov_at REAL);                                        -- 복구 코드 해시(SHA-256, 코드 자체는 저장 안 함)
CREATE TABLE IF NOT EXISTS mail_codes(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  email_lc TEXT NOT NULL, purpose TEXT NOT NULL,          -- signup(가입 대기: payload에 닉네임·비밀번호 해시) / reset(비밀번호 찾기) / link(이메일 등록)
  code_hash TEXT NOT NULL, expires REAL NOT NULL, attempts INTEGER NOT NULL DEFAULT 0,
  payload TEXT, user_id INTEGER, created REAL NOT NULL, ip TEXT);
CREATE INDEX IF NOT EXISTS mail_codes_email ON mail_codes(email_lc, purpose);
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
    ucols = {row[1] for row in c.execute('PRAGMA table_info(users)')}        # v1.50: 이메일 인증·복구 코드 컬럼
    if ucols:
        for col, ddl in (('email', 'TEXT'), ('email_lc', 'TEXT'), ('email_verified', 'INTEGER NOT NULL DEFAULT 0'),
                         ('recov_hash', 'TEXT'), ('recov_at', 'REAL')):
            if col not in ucols:
                c.execute(f'ALTER TABLE users ADD COLUMN {col} {ddl}')
        c.execute('CREATE UNIQUE INDEX IF NOT EXISTS users_email ON users(email_lc) WHERE email_lc IS NOT NULL')   # 이메일 하나에 계정 하나
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
    """본인에게만 주는 정보(/me·로그인 응답): public + 이메일(가림)·인증 여부·복구 코드 보유 여부"""
    d = public(row)
    d.update({'email': mask_email(row['email']) if row['email'] else '', 'emailVerified': bool(row['email_verified']),
              'hasRecovery': bool(row['recov_hash'])})
    return d


# ------------------------- 이메일 · 인증 코드 · 복구 코드 도우미 -------------------------
def _norm_email(e):
    e = _s(e).strip()
    return e, e.lower()


def email_problem(e):
    e = _s(e).strip()
    if not e or len(e) > EMAIL_MAX or not EMAIL_RE.match(e):
        return '이메일 주소 형식을 확인해 주세요.'
    return None


def mask_email(e):
    """'moon@gmail.com' → 'mo***@gmail.com' (본인 확인용 표시)"""
    e = _s(e)
    if '@' not in e:
        return ''
    local, dom = e.split('@', 1)
    return (local[:2] if len(local) > 2 else local[:1]) + '***@' + dom


def _code_hash(email_lc, code):
    return hashlib.sha256(f'code:{email_lc}:{_s(code).strip()}'.encode('utf-8')).hexdigest()


def _send_ok(email_lc, ip, now=None):
    """발송 남용 방지: 같은 주소 60초 간격, 주소당 시간당 5회, IP당 시간당 20회 → 위반 사유 또는 None"""
    now = now or time.time()
    for key, cap in ((('e', email_lc), SEND_MAX_EMAIL_HOUR), (('ip', ip or '?'), SEND_MAX_IP_HOUR)):
        hist = [t for t in _sends.get(key, []) if now - t < 3600]
        _sends[key] = hist
        if key[0] == 'e' and hist and now - hist[-1] < SEND_COOLDOWN:
            return f'잠시 후 다시 요청해 주세요. ({int(SEND_COOLDOWN - (now - hist[-1])) + 1}초)'
        if len(hist) >= cap:
            return '인증 메일 요청이 너무 많아요. 한 시간 뒤 다시 시도해 주세요.'
    return None


def _send_mark(email_lc, ip, now=None):
    now = now or time.time()
    _sends.setdefault(('e', email_lc), []).append(now)
    _sends.setdefault(('ip', ip or '?'), []).append(now)


def _issue_code(c, email_lc, purpose, payload=None, user_id=None, ip=None):
    """새 6자리 코드 발급(같은 주소·용도의 이전 코드는 무효, 만료된 코드 청소). 해시만 저장 → 코드 평문(메일로만 나간다)"""
    now = time.time()
    c.execute('DELETE FROM mail_codes WHERE expires < ? OR (email_lc=? AND purpose=?)', (now, email_lc, purpose))
    code = f'{secrets.randbelow(10 ** 6):06d}'
    c.execute('INSERT INTO mail_codes(email_lc, purpose, code_hash, expires, payload, user_id, created, ip) VALUES(?,?,?,?,?,?,?,?)',
              (email_lc, purpose, _code_hash(email_lc, code), now + CODE_TTL,
               json.dumps(payload, ensure_ascii=False) if payload is not None else None, user_id, now, ip))
    return code


_CODE_DEAD = '틀린 횟수가 많아 이 코드는 무효가 됐어요. 코드를 다시 요청해 주세요.'


def _check_code(c, email_lc, purpose, code):
    """코드 확인 → (row, None) / (None, 오류). 맞으면 그 코드는 삭제(1회용). 틀리면 시도 수 +1(5회면 무효)."""
    row = c.execute('SELECT * FROM mail_codes WHERE email_lc=? AND purpose=? ORDER BY id DESC LIMIT 1', (email_lc, purpose)).fetchone()
    if not row or row['expires'] < time.time():
        return None, '인증 코드가 없거나 만료됐어요. 코드를 다시 요청해 주세요.'
    if row['attempts'] >= CODE_MAX_ATTEMPTS:
        return None, _CODE_DEAD
    if not hmac.compare_digest(row['code_hash'], _code_hash(email_lc, code)):
        c.execute('UPDATE mail_codes SET attempts=attempts+1 WHERE id=?', (row['id'],))
        left = CODE_MAX_ATTEMPTS - row['attempts'] - 1
        return None, (f'인증 코드가 맞지 않아요. ({left}회 남음)' if left > 0 else _CODE_DEAD)
    c.execute('DELETE FROM mail_codes WHERE id=?', (row['id'],))
    return row, None


def _mail_code(email, code, purpose):
    what = {'signup': '회원가입', 'reset': '비밀번호 찾기', 'link': '이메일 등록'}.get(purpose, '인증')
    mailer.send(email, f'[안개전장 체스] {what} 인증 코드 {code}',
                f'안개전장 체스 {what} 인증 코드입니다.\n\n    {code}\n\n{CODE_TTL // 60}분 안에 게임 화면에 입력해 주세요.\n'
                '본인이 요청한 것이 아니면 이 메일은 무시하셔도 됩니다.\n')


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
def _validate_new_account(name, pw):
    if not NAME_RE.match(name):
        return '닉네임은 2~12자(한글·영문·숫자·_)만 가능합니다.'
    return password_problem(pw)


def signup(name, pw):
    """이메일 없이 가입(메일 미설정 서버) → ({'session','user','recovery'}, None) 또는 (None, 오류). 복구 코드는 이때 한 번만 보여준다."""
    name, pw = _s(name).strip(), _s(pw)                  # 타입이 이상해도(숫자·리스트) 오류 메시지로
    err = _validate_new_account(name, pw)
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


def signup_start(name, pw, email, ip=None):
    """이메일 인증 가입 1단계: 검사 후 코드 발송 → ({'pending':True,'email':가린 주소}, None) / (None, 오류).
    계정은 아직 만들지 않는다(닉네임 선점 방지 — 코드는 10분 만료). 비밀번호는 해시로만 임시 보관(payload)."""
    name, pw = _s(name).strip(), _s(pw)
    email, email_lc = _norm_email(email)
    err = _validate_new_account(name, pw) or email_problem(email)
    if err:
        return None, err
    with _db() as c:
        if c.execute('SELECT 1 FROM users WHERE name_lc=?', (name.lower(),)).fetchone():
            return None, '이미 사용 중인 닉네임입니다.'
        if c.execute('SELECT 1 FROM users WHERE email_lc=?', (email_lc,)).fetchone():
            return None, '이미 가입에 쓰인 이메일이에요. 로그인하거나 [찾기]에서 비밀번호를 재설정하세요.'
        err = _send_ok(email_lc, ip)
        if err:
            return None, err
        salt = secrets.token_bytes(16)
        code = _issue_code(c, email_lc, 'signup', {'name': name, 'salt': salt.hex(), 'pw_hash': _hash(pw, salt).hex(), 'email': email}, ip=ip)
        _send_mark(email_lc, ip)
    _mail_code(email, code, 'signup')
    return {'pending': True, 'email': mask_email(email)}, None


def signup_resend(email, ip=None):
    """가입 인증 코드 재발송(진행 중인 가입이 있을 때) — 이전 코드는 무효."""
    email, email_lc = _norm_email(email)
    with _db() as c:
        row = c.execute('SELECT * FROM mail_codes WHERE email_lc=? AND purpose=? ORDER BY id DESC LIMIT 1', (email_lc, 'signup')).fetchone()
        if not row or not row['payload'] or row['expires'] < time.time() - 3600:
            return None, '진행 중인 가입이 없어요. 처음부터 다시 해주세요.'
        err = _send_ok(email_lc, ip)
        if err:
            return None, err
        payload = json.loads(row['payload'])
        code = _issue_code(c, email_lc, 'signup', payload, ip=ip)
        _send_mark(email_lc, ip)
    _mail_code(payload.get('email') or email, code, 'signup')
    return {'pending': True, 'email': mask_email(payload.get('email') or email)}, None


def signup_verify(email, code):
    """2단계: 코드 확인 → 계정 생성(이메일 인증됨) + 로그인 + 복구 코드 → ({'session','user','recovery'}, None)"""
    email, email_lc = _norm_email(email)
    with _db() as c:
        row, err = _check_code(c, email_lc, 'signup', code)
        if err:
            return None, err
        p = json.loads(row['payload'] or '{}')
        name = p.get('name', '')
        if not name or c.execute('SELECT 1 FROM users WHERE name_lc=?', (name.lower(),)).fetchone():
            return None, '그 사이 닉네임이 다른 사람에게 갔어요. 처음부터 다시 해주세요.'
        if c.execute('SELECT 1 FROM users WHERE email_lc=?', (email_lc,)).fetchone():
            return None, '이미 가입에 쓰인 이메일이에요.'
        recov = _new_recovery()
        c.execute('INSERT INTO users(name, name_lc, salt, pw_hash, rating, created, email, email_lc, email_verified, recov_hash, recov_at) '
                  'VALUES(?,?,?,?,?,?,?,?,1,?,?)',
                  (name, name.lower(), bytes.fromhex(p['salt']), bytes.fromhex(p['pw_hash']), RATING_DEFAULT, time.time(),
                   p.get('email') or email, email_lc, _recov_hash(_recov_norm(recov)), time.time()))
        urow = c.execute('SELECT * FROM users WHERE name_lc=?', (name.lower(),)).fetchone()
        token = _new_session(c, urow['id'])
        return {'session': token, 'user': private(urow), 'recovery': recov, 'weakPw': False}, None


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


# ------------------------- 비밀번호 찾기: 이메일 코드 / 복구 코드 -------------------------
def reset_start(email, ip=None):
    """비밀번호 찾기 1단계: 인증된 이메일이면 코드 발송. 주소 존재 여부는 응답에 드러내지 않는다(같은 문구·같은 제한)."""
    email, email_lc = _norm_email(email)
    err = email_problem(email)
    if err:
        return None, err
    with _db() as c:
        row = c.execute('SELECT * FROM users WHERE email_lc=? AND email_verified=1', (email_lc,)).fetchone()
        err = _send_ok(email_lc, ip)
        if err:
            return None, err
        _send_mark(email_lc, ip)
        code = _issue_code(c, email_lc, 'reset', user_id=row['id'], ip=ip) if row else None
    if row:
        _mail_code(row['email'], code, 'reset')
    return {'sent': True, 'email': mask_email(email)}, None


def reset_verify(email, code, new_pw):
    """2단계: 코드 + 새 비밀번호 → 비밀번호 변경 · 모든 기기 로그아웃 · 새 로그인(닉네임 안내) → ({'session','user'}, None)"""
    email, email_lc = _norm_email(email)
    err = password_problem(new_pw)
    if err:
        return None, err
    with _db() as c:
        row, err = _check_code(c, email_lc, 'reset', code)
        if err:
            return None, err
        urow = c.execute('SELECT * FROM users WHERE id=?', (row['user_id'],)).fetchone()
        if not urow:
            return None, '계정을 찾을 수 없어요.'
        salt = secrets.token_bytes(16)
        c.execute('UPDATE users SET salt=?, pw_hash=? WHERE id=?', (salt, _hash(_s(new_pw), salt), urow['id']))
        c.execute('DELETE FROM sessions WHERE user_id=?', (urow['id'],))
        token = _new_session(c, urow['id'])
        _fails.pop(urow['name'].lower(), None)
        return {'session': token, 'user': private(urow), 'weakPw': False}, None


def recover_with_code(code, new_pw, ip=None):
    """복구 코드로 비밀번호 재설정 → ({'session','user','recovery'(새 코드)}, None). 코드는 1회용: 성공하면 새로 발급.
    IP당 5회 틀리면 10분 잠금(코드는 40비트)."""
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


# ------------------------- 프로필: 이메일 등록/변경 · 복구 코드 재발급 -------------------------
def email_link_start(token, pw, email, ip=None):
    """이메일 등록/변경 1단계: 현재 비밀번호 확인 → 코드 발송 → ({'sent':True,'email':가림}, None)"""
    user = user_by_token(token)
    if not user:
        return None, '로그인이 필요합니다.'
    email, email_lc = _norm_email(email)
    err = email_problem(email)
    if err:
        return None, err
    with _db() as c:
        row = c.execute('SELECT * FROM users WHERE id=?', (user['id'],)).fetchone()
        err = _verify_pw(c, row, pw, 'pw:' + row['name'].lower())
        if err:
            return None, err
        if c.execute('SELECT id FROM users WHERE email_lc=? AND id<>?', (email_lc, row['id'])).fetchone():
            return None, '이미 다른 계정에 등록된 이메일이에요.'
        err = _send_ok(email_lc, ip)
        if err:
            return None, err
        code = _issue_code(c, email_lc, 'link', {'email': email}, user_id=row['id'], ip=ip)
        _send_mark(email_lc, ip)
    _mail_code(email, code, 'link')
    return {'sent': True, 'email': mask_email(email)}, None


def email_link_verify(token, code):
    """2단계: 코드 확인 → 이메일 저장(인증됨) → (user(private), None)"""
    user = user_by_token(token)
    if not user:
        return None, '로그인이 필요합니다.'
    with _db() as c:
        pend = c.execute("SELECT email_lc FROM mail_codes WHERE user_id=? AND purpose='link' ORDER BY id DESC LIMIT 1", (user['id'],)).fetchone()
        if not pend:
            return None, '인증 코드가 없거나 만료됐어요. 코드를 다시 요청해 주세요.'
        row, err = _check_code(c, pend['email_lc'], 'link', code)
        if err:
            return None, err
        if row['user_id'] != user['id']:
            return None, '이 코드는 다른 계정의 요청이에요.'
        if c.execute('SELECT id FROM users WHERE email_lc=? AND id<>?', (pend['email_lc'], user['id'])).fetchone():
            return None, '이미 다른 계정에 등록된 이메일이에요.'
        p = json.loads(row['payload'] or '{}')
        c.execute('UPDATE users SET email=?, email_lc=?, email_verified=1 WHERE id=?', (p.get('email') or pend['email_lc'], pend['email_lc'], user['id']))
        urow = c.execute('SELECT * FROM users WHERE id=?', (user['id'],)).fetchone()
        return private(urow), None


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
    """세션 토큰 → 회원(public). private_info=True 면 본인용(이메일 가림·인증·복구 코드 보유)까지."""
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
    """관리자용 전체 회원 목록(레이팅순) [{id, name, rating, tier, wins, losses, draws, created, email, emailVerified, hasRecovery}]"""
    with _db() as c:
        rows = c.execute('SELECT * FROM users ORDER BY rating DESC, id').fetchall()
    return [dict(public(r), created=r['created'], email=r['email'] or '', emailVerified=bool(r['email_verified']),
                 hasRecovery=bool(r['recov_hash'])) for r in rows]


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
    elif len(sys.argv) > 2 and sys.argv[1] == 'mailtest':        # mailtest 주소  → SMTP 설정 점검(동기 발송)
        c = mailer.config()
        print('smtp:', c['host'], c['port'], c['user'], '| dev' if c['dev'] else '')
        ok = mailer.send_now(c, sys.argv[2], '[안개전장 체스] 메일 설정 점검', '이 메일이 보이면 SMTP 설정이 맞습니다.\n') if mailer.smtp_ready(c) else False
        print('sent OK' if ok else 'FAILED (FOG_SMTP_HOST/USER/PASS 확인)')
    else:
        print('usage: python accounts.py feedback [limit] [all] | users | mailtest <주소>')
