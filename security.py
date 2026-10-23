"""Persistent request budgets. No passwords, tokens, or raw IPs are stored."""
from contextlib import contextmanager
import hashlib
import ipaddress
import math
import os
from pathlib import Path
import sqlite3
import time

import accounts
from functools import lru_cache

MAX_BUCKETS = 20_000


@lru_cache(maxsize=1)
def fly_gateway():
    """The per-Machine IPv4 gateway used by Fly Proxy, not the whole private range."""
    try:
        for line in Path('/proc/net/route').read_text().splitlines()[1:]:
            fields = line.split()
            if fields[1] == '00000000' and int(fields[3], 16) & 2:
                return str(ipaddress.IPv4Address(bytes.fromhex(fields[2])[::-1]))
    except (OSError, ValueError, IndexError):
        pass
    return None


def client_ip(peer, headers):
    """Trust Fly-Client-IP only at explicitly configured proxy socket peers.

    Production binds IPv4 behind Fly Proxy. X-Forwarded-For is never used.
    Local/LAN servers default to the socket address, regardless of headers.
    """
    try:
        address = ipaddress.ip_address(peer)
        trusted = any(address in ipaddress.ip_network(net.strip())
                      for net in os.environ.get('FOG_TRUSTED_PROXY_CIDRS', '').split(',') if net.strip())
        if os.environ.get('FOG_TRUST_FLY_PROXY') == '1' and os.environ.get('FLY_APP_NAME'):
            trusted = trusted or str(address) == fly_gateway()
        forwarded = headers.get_all('Fly-Client-IP') if hasattr(headers, 'get_all') else [headers.get('Fly-Client-IP')]
        if trusted and len(forwarded or []) == 1 and forwarded[0]:
            return str(ipaddress.ip_address(forwarded[0].strip()))
        return str(address)
    except ValueError:
        return peer


@contextmanager
def database(now):
    path = Path(os.environ.get('FOG_SECURITY_DB', str(Path(accounts.DB_PATH).with_name('security.sqlite3'))))
    path.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(path, timeout=3)
    try:
        with db:
            db.execute('CREATE TABLE IF NOT EXISTS budgets (scope TEXT, subject TEXT, n INTEGER, expires REAL, PRIMARY KEY(scope, subject))')
            db.execute('CREATE INDEX IF NOT EXISTS budgets_expiry ON budgets(expires)')
            db.execute('BEGIN IMMEDIATE')
            db.execute('DELETE FROM budgets WHERE expires <= ?', (now,))
            yield db
    finally:
        db.close()


def digest(value):
    return hashlib.sha256(str(value).encode('utf-8')).hexdigest()


def consume(rules, now=None):
    """Atomically consume (scope, subject, count, seconds) budgets; return retry seconds."""
    now = time.time() if now is None else now
    pending = []
    retry = 0
    with database(now) as db:
        for scope, subject, limit, seconds in rules:
            subject = digest(subject)
            row = db.execute('SELECT n, expires FROM budgets WHERE scope=? AND subject=?', (scope, subject)).fetchone()
            count, expires = row if row else (0, now + seconds)
            if count >= limit:
                retry = max(retry, math.ceil(expires - now))
            pending.append((scope, subject, count + 1, expires, row is None))
        if retry:
            return max(1, retry)
        new_count = sum(item[4] for item in pending)
        if new_count and db.execute('SELECT count(*) FROM budgets').fetchone()[0] + new_count > MAX_BUCKETS:
            return 60
        db.executemany('INSERT OR REPLACE INTO budgets VALUES (?,?,?,?)', [item[:4] for item in pending])
    return 0


def admin_attempt(subject, valid, limit, seconds, now=None):
    now = time.time() if now is None else now
    subject = digest(subject)
    with database(now) as db:
        row = db.execute("SELECT n, expires FROM budgets WHERE scope='admin-fail' AND subject=?", (subject,)).fetchone()
        if row and row[0] >= limit:
            return 'locked'
        if valid:
            db.execute("DELETE FROM budgets WHERE scope='admin-fail' AND subject=?", (subject,))
            return 'ok'
        if not row and db.execute('SELECT count(*) FROM budgets').fetchone()[0] >= MAX_BUCKETS:
            return 'locked'
        count, expires = row if row else (0, now + seconds)
        db.execute("INSERT OR REPLACE INTO budgets VALUES ('admin-fail',?,?,?)", (subject, count + 1, expires))
    return 'forbidden'


def request_rules(path, data, ip):
    if path == '/login':
        name = str(data.get('name') or '').strip().lower()
        return [('login-ip', ip, 60, 300), ('login-name', name, 12, 300)]
    if path == '/signup':
        return [('signup-ip', ip, 10, 3600)]
    if path == '/recover/code':
        return [('recover-ip', ip, 5, 600)]
    if path in ('/account/pw', '/account/recovery'):
        return [('account-ip', ip, 20, 300), ('account-session', str(data.get('session') or ''), 10, 300)]
    if path in ('/join', '/watch/join'):
        return [('join-ip', ip, 30, 60), ('join-hour', ip, 200, 3600)]
    if path == '/match/join':
        return [('match-ip', ip, 60, 60)]
    if path == '/feedback':
        return [('feedback-ip', ip, 6, 60)]
    return []
