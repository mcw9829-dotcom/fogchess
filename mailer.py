# -*- coding: utf-8 -*-
"""
메일 발송(표준 라이브러리 smtplib) — 회원가입 이메일 인증 · 비밀번호 찾기 · 이메일 등록 코드.

설정은 환경변수(배포는 `fly secrets set ...`):
  FOG_SMTP_HOST   예) smtp.gmail.com · smtp-relay.brevo.com · smtp.naver.com
  FOG_SMTP_PORT   587(STARTTLS, 기본) 또는 465(SSL)
  FOG_SMTP_USER   SMTP 로그인 계정(보통 보내는 주소)
  FOG_SMTP_PASS   SMTP 비밀번호(Gmail은 2단계 인증 뒤 만드는 '앱 비밀번호' 16자리)
  FOG_MAIL_FROM   보내는 주소(생략하면 USER)
  FOG_MAIL_DEV=1  실제로 보내지 않고 서버 로그에 내용을 찍는다(로컬 개발·테스트·E2E)
HOST·USER·PASS 가 없고 DEV 도 아니면 enabled() 는 False → 서버는 이메일 인증 없이 옛 방식(닉네임+비밀번호)으로 가입을 받는다(막히지 않게).
발송은 백그라운드 스레드에서(SMTP 왕복 1~3초가 요청 응답을 막지 않게). 실패는 로그와 SENT 기록에만 남긴다.
"""
import os
import smtplib
import ssl
import threading
import time
from email.message import EmailMessage
from email.utils import formataddr

APP_NAME = '안개전장 체스'
SENT = []            # 최근 발송 기록(관리자 진단·테스트용, 최대 30건) [{to, subject, body, at, mode, error?}]
_SENT_MAX = 30


def config():
    user = os.environ.get('FOG_SMTP_USER', '').strip()
    try:
        port = int(os.environ.get('FOG_SMTP_PORT', '587') or 587)
    except ValueError:
        port = 587
    return {'host': os.environ.get('FOG_SMTP_HOST', '').strip(), 'port': port, 'user': user,
            'pw': os.environ.get('FOG_SMTP_PASS', ''), 'sender': os.environ.get('FOG_MAIL_FROM', '').strip() or user,
            'dev': os.environ.get('FOG_MAIL_DEV', '').strip() == '1'}


def smtp_ready(c=None):
    c = c or config()
    return bool(c['host'] and c['user'] and c['pw'])


def enabled():
    """이메일 인증을 켤 수 있나(실제 SMTP 설정 또는 개발 모드)."""
    c = config()
    return c['dev'] or smtp_ready(c)


def status():
    """관리자 페이지용 상태(비밀번호 제외). 발송 기록의 본문은 개발 모드(로그 발송)일 때만 포함."""
    c = config()
    sent = [dict((k, v) for k, v in r.items() if k != 'body' or r.get('mode') == 'dev') for r in SENT]
    return {'enabled': enabled(), 'dev': c['dev'], 'smtp': smtp_ready(c), 'host': c['host'], 'port': c['port'],
            'sender': c['sender'], 'sent': sent}


def send(to, subject, body):
    """즉시 반환(백그라운드 발송). 개발 모드/미설정이면 로그에만 찍는다. → True(접수) / False(설정 없음)"""
    c = config()
    mode = 'dev' if c['dev'] or not smtp_ready(c) else 'smtp'
    SENT.append({'to': to, 'subject': subject, 'body': body, 'at': time.time(), 'mode': mode})
    del SENT[:-_SENT_MAX]
    if mode == 'dev':
        print(f'[mail:dev] to={to} | {subject}\n{body}', flush=True)
        return c['dev']
    threading.Thread(target=send_now, args=(c, to, subject, body), daemon=True).start()
    return True


def send_now(c, to, subject, body):
    """동기 SMTP 발송(스레드 안에서, 또는 CLI 점검용). 실패하면 예외 대신 False + 로그."""
    msg = EmailMessage()
    msg['Subject'] = subject
    msg['From'] = formataddr((APP_NAME, c['sender']))
    msg['To'] = to
    msg.set_content(body)
    try:
        ctx = ssl.create_default_context()
        if c['port'] == 465:
            with smtplib.SMTP_SSL(c['host'], c['port'], timeout=20, context=ctx) as s:
                s.login(c['user'], c['pw'])
                s.send_message(msg)
        else:
            with smtplib.SMTP(c['host'], c['port'], timeout=20) as s:
                s.ehlo()
                s.starttls(context=ctx)
                s.ehlo()
                s.login(c['user'], c['pw'])
                s.send_message(msg)
        print(f'[mail] sent to {to}: {subject}', flush=True)
        return True
    except Exception as e:
        print(f'[mail] send FAILED to {to}: {e!r}', flush=True)
        for r in reversed(SENT):                       # 관리자 페이지 발송 기록에 오류 표시
            if r['to'] == to and r.get('mode') == 'smtp' and 'error' not in r:
                r['error'] = repr(e)
                break
        return False
