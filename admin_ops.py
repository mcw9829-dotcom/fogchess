"""Server-owned moderation and operations. All durable changes share the account DB.

No admin credentials, session tokens, recovery material, or hidden live boards are
returned here. Handler authentication is mandatory before dispatch_admin().
"""
import copy
import hashlib
import json
import re
import time
import uuid
from collections import Counter, deque
import threading
import accounts

SCHEMA = '''
CREATE TABLE IF NOT EXISTS admin_sanctions(
 id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER NOT NULL, kind TEXT NOT NULL,
 created REAL NOT NULL, until_at REAL NOT NULL, reason TEXT NOT NULL, actor TEXT NOT NULL,
 revoked_at REAL, revoked_reason TEXT, revoked_actor TEXT);
CREATE INDEX IF NOT EXISTS sanctions_user ON admin_sanctions(user_id,until_at);
CREATE TABLE IF NOT EXISTS admin_audit(
 id INTEGER PRIMARY KEY AUTOINCREMENT, created REAL NOT NULL, actor TEXT NOT NULL,
 action TEXT NOT NULL, target TEXT NOT NULL, before_json TEXT NOT NULL,
 after_json TEXT NOT NULL, reason TEXT NOT NULL, request_id TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS admin_receipts(
 request_id TEXT PRIMARY KEY, fingerprint TEXT NOT NULL, response TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS admin_notices(
 id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, body TEXT NOT NULL,
 kind TEXT NOT NULL, published INTEGER NOT NULL DEFAULT 0, updated REAL NOT NULL,
 revision INTEGER NOT NULL DEFAULT 1);
CREATE TABLE IF NOT EXISTS admin_settings(key TEXT PRIMARY KEY,value TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS admin_games(
 id TEXT PRIMARY KEY, room TEXT NOT NULL, created REAL NOT NULL, ended REAL NOT NULL,
 kind TEXT NOT NULL, winner TEXT, reason TEXT, users_json TEXT NOT NULL,
 names_json TEXT NOT NULL, ratings_json TEXT NOT NULL, request_json TEXT,
 replay_id TEXT, notation_json TEXT NOT NULL, chat_json TEXT NOT NULL,
 review TEXT NOT NULL DEFAULT 'new', revision INTEGER NOT NULL DEFAULT 1);
CREATE INDEX IF NOT EXISTS admin_games_ended ON admin_games(ended);
CREATE TABLE IF NOT EXISTS admin_presence(user_id INTEGER PRIMARY KEY, seen REAL NOT NULL);
CREATE TABLE IF NOT EXISTS admin_errors(
 id INTEGER PRIMARY KEY AUTOINCREMENT, created REAL NOT NULL, route TEXT NOT NULL,
 kind TEXT NOT NULL, resolved INTEGER NOT NULL DEFAULT 0);
'''

LABELS = {'warn':'경고','chat':'채팅 제한','match':'대국 제한','account':'계정 정지'}
STATES = ('new','review','planned','waiting','done','accepted','rejected')
PRIORITIES = ('low','normal','high')
_errors = deque(maxlen=60)
_presence_clock = {}
_memory_lock = threading.Lock()


class Problem(Exception):
    def __init__(self, message, status=400):
        super().__init__(message)
        self.status = status


def migrate(c):
    c.executescript(SCHEMA)
    columns = {r[1] for r in c.execute('PRAGMA table_info(feedback)')}
    for name, ddl in [('kind',"TEXT NOT NULL DEFAULT 'feedback'"),('target_user_id','INTEGER'),
                      ('replay_id','TEXT'),('sanction_id','INTEGER'),('frame_index','INTEGER'),
                      ('state',"TEXT NOT NULL DEFAULT 'new'"),('priority',"TEXT NOT NULL DEFAULT 'normal'"),
                      ('admin_note',"TEXT NOT NULL DEFAULT ''"),('revision','INTEGER NOT NULL DEFAULT 1'),
                      ('deleted','INTEGER NOT NULL DEFAULT 0')]:
        if columns and name not in columns:
            c.execute(f'ALTER TABLE feedback ADD COLUMN {name} {ddl}')
    if columns and 'state' not in columns:
        c.execute("UPDATE feedback SET state='done' WHERE done=1")
    cols = {r[1] for r in c.execute('PRAGMA table_info(games)')}
    if cols and 'game_id' not in cols:
        c.execute('ALTER TABLE games ADD COLUMN game_id TEXT')
    if cols:c.execute('CREATE INDEX IF NOT EXISTS history_game_id ON games(game_id)')
    session_cols={r[1] for r in c.execute('PRAGMA table_info(sessions)')}
    if session_cols and 'scope' not in session_cols:
        c.execute("ALTER TABLE sessions ADD COLUMN scope TEXT NOT NULL DEFAULT 'play'")


def dump(obj):
    return json.dumps(obj,ensure_ascii=False,sort_keys=True,separators=(',',':'))


def text(value, name, maximum=500, minimum=1):
    if not isinstance(value,str) or not minimum<=len(value.strip())<=maximum:
        raise Problem(f'{name}: {minimum}~{maximum}자로 입력해 주세요.')
    return value.strip()


def integer(value, name, low=1, high=2**53-1):
    if isinstance(value,bool) or not isinstance(value,int) or not low<=value<=high:
        raise Problem(f'{name} 값이 올바르지 않습니다.')
    return value


def active_in(c, uid, now=None):
    return [dict(r) for r in c.execute('SELECT * FROM admin_sanctions WHERE user_id=? '
            "AND revoked_at IS NULL AND kind!='warn' AND until_at>? ORDER BY id DESC",
            (uid,time.time() if now is None else now))]


def restrictions(uid, now=None):
    if not uid:return []
    with accounts._db() as c:return active_in(c,uid,now)


def block_reason(uid, kind, now=None):
    for s in restrictions(uid,now):
        if s['kind']=='account' or s['kind']==kind:
            until=time.strftime('%Y-%m-%d %H:%M UTC',time.gmtime(s['until_at']))
            return f"{LABELS[s['kind']]} 중입니다. {until}까지 · {s['reason']}"
    return None


def maintenance():
    with accounts._db() as c:
        r=c.execute("SELECT value FROM admin_settings WHERE key='maintenance'").fetchone()
    return json.loads(r[0]) if r else {'paused':False,'reason':''}


def touch(uid):
    if not uid:return
    now=time.time(); key=(accounts.DB_PATH,uid)
    with _memory_lock:
        if now-_presence_clock.get(key,0)<20:return
        if len(_presence_clock)>10000:_presence_clock.clear()
        _presence_clock[key]=now
    with accounts._db() as c:
        c.execute('INSERT INTO admin_presence VALUES(?,?) ON CONFLICT(user_id) DO UPDATE SET seen=excluded.seen',(uid,now))


def record_error(route, error):
    # Record only route allowlisted characters and exception class, never bodies or exception text.
    route=re.sub(r'[^A-Za-z0-9/_-]','',str(route).split('?')[0])[:90]
    kind=type(error).__name__[:60]
    try:
        with accounts._db() as c:
            c.execute('INSERT INTO admin_errors(created,route,kind) VALUES(?,?,?)',(time.time(),route,kind))
            c.execute('DELETE FROM admin_errors WHERE id < (SELECT COALESCE(MAX(id),0)-1000 FROM admin_errors)')
    except Exception:
        with _memory_lock:_errors.append({'created':time.time(),'route':route,'kind':kind})


def archive(room):
    st=room['state']
    st.setdefault('_admin_start_ratings',dict(room.get('ratings',{})))
    if st.get('phase') in ('waiting','setup'):
        st['_admin_start_ratings']=dict(room.get('ratings',{}))
    if st.get('phase')!='over':return
    gid=st.setdefault('_settlement_id',uuid.uuid4().hex)
    replay_id=room.get('_replay',{}).get('data',{}).get('id')
    payload=(room.get('rated_done'),replay_id,st.get('_settlement_request'),st.get('end_reason'))
    signature=hashlib.sha256(dump(payload).encode()).hexdigest()
    if st.get('_admin_archive_signature')==signature:return
    req=st.get('_settlement_request')
    with accounts._db() as c:
        c.execute('''INSERT INTO admin_games(id,room,created,ended,kind,winner,reason,users_json,names_json,
                    ratings_json,request_json,replay_id,notation_json,chat_json) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                    ON CONFLICT(id) DO UPDATE SET request_json=COALESCE(excluded.request_json,request_json),
                    replay_id=COALESCE(excluded.replay_id,replay_id),reason=excluded.reason''',
                  (gid,room['code'],st.get('started_at') or room['created'],st.get('ended_at') or time.time(),
                   'solo' if room.get('solo') else 'match' if room.get('match') else 'bot' if room.get('bot') else 'lobby',
                   st.get('winner'),st.get('end_reason') or (req.get('reason','') if req else ''),dump(room.get('users',{})),
                   dump(room.get('names',{})),dump(st['_admin_start_ratings']),dump(req) if req else None,
                   replay_id,dump(st.get('notation',[])),dump([{k:v for k,v in m.items() if k!='nonce'} for m in room.get('chat',[])])))
    st['_admin_archive_signature']=signature


def archive_safe(room):
    try:archive(room)
    except Exception as exc:record_error('/archive',exc)


def _audit(c,actor,action,target,before,after,reason,rid):
    c.execute('INSERT INTO admin_audit(created,actor,action,target,before_json,after_json,reason,request_id) VALUES(?,?,?,?,?,?,?,?)',
              (time.time(),actor,action,str(target),dump(before),dump(after),reason,rid))


def _mutate(action,data,actor,fn):
    rid=text(data.get('requestId'),'요청 ID',80)
    if not re.fullmatch(r'[A-Za-z0-9_-]{16,80}',rid):raise Problem('요청 ID 형식이 올바르지 않습니다.')
    fingerprint=hashlib.sha256(dump([action,data]).encode()).hexdigest()
    with accounts._db() as c:
        c.execute('BEGIN IMMEDIATE')
        old=c.execute('SELECT * FROM admin_receipts WHERE request_id=?',(rid,)).fetchone()
        if old:
            if old['fingerprint']!=fingerprint:raise Problem('이미 사용한 요청 ID입니다.',409)
            return json.loads(old['response'])
        result=fn(c,rid)
        c.execute('INSERT INTO admin_receipts VALUES(?,?,?)',(rid,fingerprint,dump(result)))
        return result


def _revision(row,data):
    if not row:raise Problem('항목을 찾을 수 없습니다.',404)
    if integer(data.get('revision'),'수정 버전')!=row['revision']:
        raise Problem('다른 작업으로 변경되었습니다. 새로고침 후 확인해 주세요.',409)


def _sanction(c,d,actor,rid):
    uid=integer(d.get('userId'),'회원 ID');kind=d.get('kind')
    if not isinstance(kind,str) or kind not in LABELS:raise Problem('조치 종류를 확인해 주세요.')
    if not c.execute('SELECT 1 FROM users WHERE id=?',(uid,)).fetchone():raise Problem('없는 회원입니다.',404)
    days=0 if kind=='warn' else integer(d.get('days'),'기간',1,30)
    reason=text(d.get('reason'),'조치 사유')
    before=active_in(c,uid);now=time.time()
    if kind!='warn':
        c.execute('UPDATE admin_sanctions SET revoked_at=?,revoked_reason=?,revoked_actor=? '
                  'WHERE user_id=? AND kind=? AND revoked_at IS NULL AND until_at>?',
                  (now,'새 조치로 대체: '+reason,actor,uid,kind,now))
    sid=c.execute('INSERT INTO admin_sanctions(user_id,kind,created,until_at,reason,actor) VALUES(?,?,?,?,?,?)',
                  (uid,kind,now,now+days*86400,reason,actor)).lastrowid
    _audit(c,actor,'sanction',uid,before,{'id':sid,'kind':kind,'days':days},reason,rid)
    return {'ok':True,'id':sid}


def _revoke(c,d,actor,rid):
    sid=integer(d.get('id'),'제재 ID');reason=text(d.get('reason'),'해제 사유')
    s=c.execute('SELECT * FROM admin_sanctions WHERE id=?',(sid,)).fetchone()
    if not s:raise Problem('없는 제재입니다.',404)
    if s['revoked_at'] is not None or s['until_at']<=time.time() or s['kind']=='warn':raise Problem('이미 해제되었거나 만료된 제재입니다.',409)
    c.execute('UPDATE admin_sanctions SET revoked_at=?,revoked_reason=?,revoked_actor=? WHERE id=?',(time.time(),reason,actor,sid))
    _audit(c,actor,'revoke',s['user_id'],dict(s),{'revoked':True},reason,rid)
    return {'ok':True}


def _ticket(c,d,actor,rid):
    fid=integer(d.get('id'),'제보 ID');row=c.execute('SELECT * FROM feedback WHERE id=? AND deleted=0',(fid,)).fetchone()
    _revision(row,d)
    state=d.get('state');priority=d.get('priority');category=d.get('category')
    allowed=('new','review','waiting','accepted','rejected') if row['kind']=='appeal' else ('new','review','planned','waiting','done')
    if state not in allowed or priority not in PRIORITIES:raise Problem('처리 상태와 우선순위를 확인해 주세요.')
    cats=('bug','balance','idea','other') if row['kind']=='feedback' else ('conduct','chat','rules','cheat','other') if row['kind']=='report' else ('appeal',)
    if category not in cats:raise Problem('분류를 확인해 주세요.')
    note=text(d.get('note',''),'검토 메모',1000,1 if state in ('done','accepted','rejected') else 0)
    done=state in ('done','accepted','rejected')
    c.execute('UPDATE feedback SET state=?,priority=?,category=?,admin_note=?,done=?,revision=revision+1 WHERE id=?',
              (state,priority,category,note,int(done),fid))
    before={k:row[k] for k in ('state','priority','category','admin_note')}
    _audit(c,actor,'ticket',fid,before,{'state':state,'priority':priority,'category':category,'note':note},note or '검토 단계 변경',rid)
    return {'ok':True}


def legacy_feedback(fid,done,delete,actor):
    # Preserve old clients while ensuring every privileged change is audited atomically.
    with accounts._db() as c:
        c.execute('BEGIN IMMEDIATE')
        r=c.execute('SELECT id,done,deleted FROM feedback WHERE id=? AND deleted=0',(fid,)).fetchone()
        if not r:return False
        if delete:c.execute('UPDATE feedback SET deleted=1,revision=revision+1 WHERE id=?',(fid,))
        else:c.execute('UPDATE feedback SET done=?,state=?,revision=revision+1 WHERE id=?',(int(done),'done' if done else 'new',fid))
        _audit(c,actor,'ticket-delete' if delete else 'ticket',fid,dict(r),{'deleted':bool(delete),'done':bool(done)},'기존 관리자 도구의 삭제 요청' if delete else '기존 관리자 도구의 처리 상태 변경',uuid.uuid4().hex)
        return True


def _delete_ticket(c,d,actor,rid):
    fid=integer(d.get('id'),'제보 ID');r=c.execute('SELECT * FROM feedback WHERE id=? AND deleted=0',(fid,)).fetchone();_revision(r,d)
    reason=text(d.get('reason'),'삭제 사유')
    c.execute('UPDATE feedback SET deleted=1,revision=revision+1 WHERE id=?',(fid,))
    _audit(c,actor,'ticket-delete',fid,{'state':r['state']},{'deleted':True},reason,rid)
    return {'ok':True}


def _notice(c,d,actor,rid):
    title=text(d.get('title'),'공지 제목',60);body=text(d.get('body'),'공지 내용',2000)
    kind=d.get('kind');published=d.get('published')
    if kind not in ('update','maintenance','operations') or not isinstance(published,bool):raise Problem('공지 분류와 게시 상태를 확인해 주세요.')
    reason=text(d.get('reason'),'변경 사유');nid=d.get('id')
    before={}
    if nid is not None:
        integer(nid,'공지 ID');row=c.execute('SELECT * FROM admin_notices WHERE id=?',(nid,)).fetchone();_revision(row,d);before=dict(row)
        c.execute('UPDATE admin_notices SET title=?,body=?,kind=?,published=?,updated=?,revision=revision+1 WHERE id=?',(title,body,kind,int(published),time.time(),nid))
    else:
        nid=c.execute('INSERT INTO admin_notices(title,body,kind,published,updated) VALUES(?,?,?,?,?)',(title,body,kind,int(published),time.time())).lastrowid
    _audit(c,actor,'notice',nid,before,{'title':title,'body':body,'kind':kind,'published':published},reason,rid)
    return {'ok':True,'id':nid}


def _maintenance(c,d,actor,rid):
    paused=d.get('paused');reason=text(d.get('reason'),'운영 사유')
    if not isinstance(paused,bool):raise Problem('중지 여부를 확인해 주세요.')
    row=c.execute("SELECT value FROM admin_settings WHERE key='maintenance'").fetchone()
    before=json.loads(row[0]) if row else {'paused':False,'reason':''}
    if before['paused']!=d.get('expectedPaused'):raise Problem('다른 작업으로 상태가 바뀌었습니다. 새로고침하세요.',409)
    after={'paused':paused,'reason':reason,'updated':time.time()}
    c.execute("INSERT INTO admin_settings VALUES('maintenance',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",(dump(after),))
    _audit(c,actor,'maintenance','service',before,after,reason,rid)
    return {'ok':True}


def _adjust(c,d,actor,rid):
    gid=text(d.get('id'),'대국 ID',80);g=c.execute('SELECT * FROM admin_games WHERE id=?',(gid,)).fetchone();_revision(g,d)
    receipt=c.execute('SELECT result FROM game_settlements WHERE game_id=?',(gid,)).fetchone()
    if not receipt:raise Problem('정산이 완료된 대국만 정정할 수 있습니다.',409)
    result=json.loads(receipt['result']);users=json.loads(g['users_json']);deltas=d.get('deltas')
    if not result or not isinstance(deltas,dict) or set(deltas)!=set(result):raise Problem('정산 대상과 값을 확인해 주세요.')
    reason=text(d.get('reason'),'정정 사유');before=copy.deepcopy(result);new=copy.deepcopy(result)
    for side,value in result.items():
        delta=integer(deltas[side],'정정 증감',-1000,1000);uid=users[side]
        current=c.execute('SELECT rating FROM users WHERE id=?',(uid,)).fetchone()
        if not current:raise Problem('정산 회원을 찾을 수 없습니다.',404)
        difference=delta-value['delta'];rating=current['rating']+difference
        if rating<accounts.RATING_FLOOR:raise Problem('레이팅 하한 아래로 정정할 수 없습니다.')
        history=c.execute('SELECT * FROM games WHERE game_id=? AND user_id=?',(gid,uid)).fetchone()
        if not history:raise Problem('연결된 정산 기록이 없습니다. 이전 전적은 읽기만 지원합니다.',409)
        # A historical correction shifts that point and every later point, preserving graph continuity.
        low=c.execute('SELECT MIN(rating_after) FROM games WHERE user_id=? AND id>=? AND rated=1',(uid,history['id'])).fetchone()[0]
        if low is not None and low+difference<accounts.RATING_FLOOR:raise Problem('이후 전적에 레이팅 하한 위반이 생겨 정정할 수 없습니다.')
        c.execute('UPDATE users SET rating=? WHERE id=?',(rating,uid))
        c.execute('UPDATE games SET delta=? WHERE id=?',(delta,history['id']))
        c.execute('UPDATE games SET rating_after=rating_after+? WHERE user_id=? AND id>=? AND rated=1',(difference,uid,history['id']))
        # Later receipts must agree with the shifted timeline, including a subsequent correction.
        later=c.execute('SELECT game_id FROM games WHERE user_id=? AND id>? AND rated=1 AND game_id IS NOT NULL',(uid,history['id'])).fetchall()
        for entry in later:
            linked=c.execute('SELECT users_json FROM admin_games WHERE id=?',(entry['game_id'],)).fetchone()
            receipt_later=c.execute('SELECT result FROM game_settlements WHERE game_id=?',(entry['game_id'],)).fetchone()
            if linked and receipt_later:
                users_later=json.loads(linked[0]);values=json.loads(receipt_later[0])
                for side_later,uid_later in users_later.items():
                    if uid_later==uid and side_later in values:values[side_later]['rating']+=difference
                c.execute('UPDATE game_settlements SET result=? WHERE game_id=?',(dump(values),entry['game_id']))
                c.execute('UPDATE admin_games SET revision=revision+1 WHERE id=?',(entry['game_id'],))
        new[side]={'delta':delta,'rating':value['rating']+difference}
    if new==before:raise Problem('변경할 정산 값이 없습니다.')
    c.execute('UPDATE game_settlements SET result=? WHERE game_id=?',(dump(new),gid))
    c.execute("UPDATE admin_games SET revision=revision+1,review='corrected' WHERE id=?",(gid,))
    _audit(c,actor,'adjust',gid,before,new,reason,rid)
    return {'ok':True,'result':new}


def _review(c,d,actor,rid):
    gid=text(d.get('id'),'대국 ID',80);g=c.execute('SELECT * FROM admin_games WHERE id=?',(gid,)).fetchone();_revision(g,d)
    reason=text(d.get('reason'),'검토 사유')
    if g['request_json'] and not c.execute('SELECT 1 FROM game_settlements WHERE game_id=?',(gid,)).fetchone():raise Problem('정산 대기 항목은 먼저 정산을 완료해 주세요.',409)
    c.execute("UPDATE admin_games SET review='clear',revision=revision+1 WHERE id=?",(gid,))
    _audit(c,actor,'review',gid,{'review':g['review']},{'review':'clear'},reason,rid)
    return {'ok':True}


def _retry(c,d,actor,rid):
    gid=text(d.get('id'),'대국 ID',80);g=c.execute('SELECT * FROM admin_games WHERE id=?',(gid,)).fetchone();_revision(g,d)
    if not g['request_json']:raise Problem('재처리할 정산 요청이 없습니다.')
    if c.execute('SELECT 1 FROM game_settlements WHERE game_id=?',(gid,)).fetchone():raise Problem('이미 정산된 대국입니다.',409)
    result=accounts._settle_in(c,gid,json.loads(g['request_json']))
    reason=text(d.get('reason'),'재시도 사유')
    c.execute("UPDATE admin_games SET revision=revision+1,review='clear' WHERE id=?",(gid,))
    _audit(c,actor,'retry',gid,{'pending':True},result,reason,rid)
    return {'ok':True,'result':result}


def _resolve_error(c,d,actor,rid):
    eid=integer(d.get('id'),'오류 ID');reason=text(d.get('reason'),'확인 내용')
    row=c.execute('SELECT * FROM admin_errors WHERE id=?',(eid,)).fetchone()
    if not row:raise Problem('없는 기록입니다.',404)
    if row['resolved']:raise Problem('이미 확인된 오류입니다.',409)
    c.execute('UPDATE admin_errors SET resolved=1 WHERE id=?',(eid,))
    _audit(c,actor,'error',eid,{'resolved':False},{'resolved':True},reason,rid)
    return {'ok':True}


MUTATIONS={'sanction':_sanction,'revoke':_revoke,'ticket':_ticket,'ticket-delete':_delete_ticket,
           'notice':_notice,'maintenance':_maintenance,'adjust':_adjust,'review':_review,
           'retry':_retry,'error':_resolve_error}


def mutate(action,data,actor):
    fn=MUTATIONS.get(action)
    if not fn:raise Problem('없는 관리 작업입니다.',404)
    return _mutate(action,data,actor,lambda c,rid:fn(c,data,actor,rid))


def actor(session):
    u=accounts.user_by_token(session)
    return f"{u['name']} (#{u['id']}, 관리자 키 인증)" if u else '관리자 (공용 키 인증)'


def list_users(query='',offset=0):
    with accounts._db() as c:
        pattern='%'+query.replace('\\','\\\\').replace('%','\\%').replace('_','\\_')+'%'
        params=(pattern,str(query))
        clause="name LIKE ? ESCAPE '\\' OR CAST(id AS TEXT)=?"
        total=c.execute(f'SELECT COUNT(*) FROM users WHERE {clause}',params).fetchone()[0]
        rows=c.execute(f'SELECT * FROM users WHERE {clause} ORDER BY id DESC LIMIT 100 OFFSET ?',(*params,offset)).fetchall()
        values=[]
        for r in rows:
            p=c.execute('SELECT seen FROM admin_presence WHERE user_id=?',(r['id'],)).fetchone()
            values.append(dict(accounts.public(r),created=r['created'],lastSeen=p[0] if p else None,
                               restrictions=active_in(c,r['id']),hasRecovery=bool(r['recov_hash'])))
        return {'ok':True,'rows':values,'total':total,'offset':offset}


def user_detail(uid):
    with accounts._db() as c:
        r=c.execute('SELECT * FROM users WHERE id=?',(uid,)).fetchone()
        if not r:raise Problem('없는 회원입니다.',404)
        sanctions=[dict(s) for s in c.execute('SELECT * FROM admin_sanctions WHERE user_id=? ORDER BY id DESC LIMIT 100',(uid,))]
        games=[dict(g) for g in c.execute('SELECT id,created,kind,result,reason,opp_name,rated,delta,rating_after,room,game_id FROM games WHERE user_id=? ORDER BY id DESC LIMIT 20',(uid,))]
        return {'ok':True,'user':dict(accounts.public(r),created=r['created']), 'sanctions':sanctions,'history':games}


def tickets(query='',kind='',offset=0):
    with accounts._db() as c:
        clauses=['f.deleted=0'];args=[]
        if kind in ('feedback','report','appeal'):clauses.append('f.kind=?');args.append(kind)
        if query:
            clauses.append('(instr(lower(f.message),lower(?))>0 OR instr(lower(COALESCE(f.name,\'\')),lower(?))>0 OR CAST(f.id AS TEXT)=?)');args.extend([query,query,query])
        where=' AND '.join(clauses)
        total=c.execute('SELECT COUNT(*) FROM feedback f WHERE '+where,args).fetchone()[0]
        rows=c.execute('SELECT f.*,u.name target_name FROM feedback f LEFT JOIN users u ON u.id=f.target_user_id WHERE '+where+' ORDER BY f.done,f.id DESC LIMIT 100 OFFSET ?',(*args,offset)).fetchall()
    return {'ok':True,'rows':[dict(r) for r in rows],'total':total,'offset':offset}


def game_rows(offset=0):
    with accounts._db() as c:
        rows=c.execute('SELECT g.*,s.result FROM admin_games g LEFT JOIN game_settlements s ON s.game_id=g.id ORDER BY g.ended DESC LIMIT 50 OFFSET ?',(offset,)).fetchall()
        total=c.execute('SELECT COUNT(*) FROM admin_games').fetchone()[0]
    out=[]
    for row in rows:
        d=dict(row)
        for k in ('users','names','ratings'):d[k]=json.loads(d.pop(k+'_json'))
        d['result']=json.loads(d['result']) if d['result'] else {}
        d['pending']=bool(d['request_json'] and not d['result'] and json.loads(d['request_json']).get('rated'))
        # Unrated settlements legitimately have an empty receipt.
        if d['request_json']:
            with accounts._db() as c:d['pending']=not bool(c.execute('SELECT 1 FROM game_settlements WHERE game_id=?',(d['id'],)).fetchone())
        for k in ('request_json','notation_json','chat_json'):d.pop(k,None)
        out.append(d)
    return {'ok':True,'rows':out,'total':total,'offset':offset}


def game_detail(gid):
    with accounts._db() as c:
        row=c.execute('SELECT * FROM admin_games WHERE id=?',(gid,)).fetchone()
        if not row:raise Problem('없는 대국입니다.',404)
        receipt=c.execute('SELECT result FROM game_settlements WHERE game_id=?',(gid,)).fetchone()
        history=[dict(r) for r in c.execute('SELECT user_id,delta,rating_after FROM games WHERE game_id=?',(gid,))]
    g=dict(row)
    for k in ('users','names','ratings','notation','chat'):g[k]=json.loads(g.pop(k+'_json'))
    request=json.loads(g.pop('request_json')) if row['request_json'] else None
    g['pending']=bool(request and not receipt);g['result']=json.loads(receipt[0]) if receipt else {}
    g['history']=history
    return {'ok':True,'game':g}


def notices(public=False):
    with accounts._db() as c:
        rows=c.execute('SELECT * FROM admin_notices '+('WHERE published=1 ' if public else '')+'ORDER BY updated DESC LIMIT 30').fetchall()
    return {'ok':True,'rows':[dict(r) for r in rows]}


def audit(offset=0):
    with accounts._db() as c:
        rows=c.execute('SELECT * FROM admin_audit ORDER BY id DESC LIMIT 100 OFFSET ?',(offset,)).fetchall()
        total=c.execute('SELECT COUNT(*) FROM admin_audit').fetchone()[0]
    out=[]
    for r in rows:
        d=dict(r);d['before']=json.loads(d.pop('before_json'));d['after']=json.loads(d.pop('after_json'));d.pop('request_id');out.append(d)
    return {'ok':True,'rows':out,'total':total,'offset':offset}


def overview(rooms,queue):
    now=time.time()
    with accounts._db() as c:
        online=[dict(r) for r in c.execute('SELECT p.user_id,u.name,u.rating,p.seen FROM admin_presence p JOIN users u ON u.id=p.user_id WHERE p.seen>? ORDER BY p.seen DESC LIMIT 200',(now-90,))]
        errors=[dict(r) for r in c.execute('SELECT * FROM admin_errors ORDER BY id DESC LIMIT 50')]
        counts={'users':c.execute('SELECT COUNT(*) FROM users').fetchone()[0],
                'tickets':c.execute('SELECT COUNT(*) FROM feedback WHERE deleted=0 AND done=0').fetchone()[0],
                'sanctions':c.execute("SELECT COUNT(DISTINCT user_id) FROM admin_sanctions WHERE revoked_at IS NULL AND kind!='warn' AND until_at>?",(now,)).fetchone()[0],
                'pending':c.execute('SELECT COUNT(*) FROM admin_games g WHERE request_json IS NOT NULL AND NOT EXISTS(SELECT 1 FROM game_settlements s WHERE s.game_id=g.id)').fetchone()[0]}
    running=[{'room':r['code'],'phase':r['state']['phase'],'names':dict(r['names']),'turn':r['state'].get('turnCount',0)}
             for r in rooms.values() if r['state']['phase'] in ('setup','play')]
    waiting=[{'user_id':e['uid'],'name':e['name'],'rating':e['rating'],'waited':max(0,int(now-e['since'])),'accepting':bool(e.get('pending'))}
             for e in queue.values() if not e.get('matched') and now-e['seen']<=15]
    return {'ok':True,'counts':counts,'online':online,'running':running,'queue':waiting,'errors':errors,
            'maintenance':maintenance(),'updated':now,'presenceWindow':90,'backupStatus':None}


def balance(kind='match',band='all',days=7):
    if kind not in ('match','bot','lobby'):raise Problem('대국 종류를 확인해 주세요.')
    if band not in ('all','1000','1400','1800'):raise Problem('레이팅 구간을 확인해 주세요.')
    days=max(1,min(90,int(days)));cut=time.time()-days*86400
    with accounts._db() as c:
        rows=c.execute('SELECT winner,ratings_json,notation_json FROM admin_games WHERE kind=? AND ended>?',(kind,cut)).fetchall()
        first=c.execute('SELECT MIN(ended) FROM admin_games').fetchone()[0]
    outcomes=Counter();uses=Counter();captures=Counter();measured=Counter()
    for r in rows:
        ratings=[int(v) for v in json.loads(r['ratings_json']).values() if isinstance(v,(int,float))]
        if band!='all':
            if not ratings:continue
            mean=sum(ratings)/len(ratings);lo=int(band);hi={'1000':1400,'1400':1800,'1800':999999}[band]
            if not lo<=mean<hi:continue
        outcomes[r['winner']]+=1
        for a in json.loads(r['notation_json']):
            if a.get('action') not in ('fire','barrage','scan'):continue
            uses[a['action']]+=1
            if a.get('captures') is not None:
                measured[a['action']]+=1;captures[a['action']]+=int(a['captures']>0)
    return {'ok':True,'kind':kind,'band':band,'days':days,'since':first,'games':sum(outcomes.values()),
            'outcomes':dict(outcomes),'uses':dict(uses),'captureUses':dict(captures),'measuredUses':dict(measured)}


def support_submit(user,data):
    if not user:raise Problem('로그인이 필요합니다.',401)
    kind=data.get('kind');message=text(data.get('message'),'제보 내용',1000,3)
    category=data.get('category');rid=data.get('replayId');target=data.get('targetUserId');sid=data.get('sanctionId');frame=data.get('frame')
    if kind not in ('report','appeal'):raise Problem('제보 종류를 확인해 주세요.')
    if kind=='report':
        if category not in ('conduct','chat','rules','cheat','other'):raise Problem('신고 분류를 확인해 주세요.')
        rid=text(rid,'기보 ID',64)
        import replays
        metadata=replays.admin_payload(rid)
        if not metadata:raise Problem('종료된 기보를 찾을 수 없습니다.',404)
        payload,access=metadata
        if user['id'] not in access.get('users',[]):raise Problem('본인이 참여한 종료 대국만 신고할 수 있습니다.',403)
        if target is not None:
            integer(target,'대상 회원')
            if target==user['id'] or target not in access.get('users',[]):raise Problem('이 대국의 상대 회원을 선택해 주세요.')
        if frame is not None:integer(frame,'수순',0,max(0,len(payload['frames'])-1))
    else:
        sid=integer(sid,'제재 ID');category='appeal';rid=None;target=user['id'];frame=None
    with accounts._db() as c:
        c.execute('BEGIN IMMEDIATE')
        if kind=='appeal':
            s=c.execute('SELECT 1 FROM admin_sanctions WHERE id=? AND user_id=?',(sid,user['id'])).fetchone()
            if not s:raise Problem('본인의 제재만 이의제기할 수 있습니다.',403)
            if c.execute("SELECT 1 FROM feedback WHERE kind='appeal' AND sanction_id=? AND done=0 AND deleted=0",(sid,)).fetchone():raise Problem('이미 검토 중인 이의제기가 있습니다.',409)
        if c.execute('SELECT COUNT(*) FROM feedback WHERE user_id=? AND created>? AND kind IN (\'report\',\'appeal\')',(user['id'],time.time()-3600)).fetchone()[0]>=5:raise Problem('한 시간에 5건까지 접수할 수 있습니다.',429)
        fid=c.execute('INSERT INTO feedback(created,name,user_id,category,message,kind,target_user_id,replay_id,sanction_id,frame_index) VALUES(?,?,?,?,?,?,?,?,?,?)',
                      (time.time(),user['name'],user['id'],category,message,kind,target,rid,sid,frame)).lastrowid
    return {'ok':True,'id':fid}


def support_mine(user):
    if not user:raise Problem('로그인이 필요합니다.',401)
    with accounts._db() as c:
        sanctions=[dict(r) for r in c.execute('SELECT id,kind,created,until_at,reason,revoked_at,revoked_reason FROM admin_sanctions WHERE user_id=? ORDER BY id DESC LIMIT 50',(user['id'],))]
        tickets=[dict(r) for r in c.execute("SELECT id,kind,created,message,state,category,sanction_id FROM feedback WHERE user_id=? AND deleted=0 AND kind IN ('report','appeal') ORDER BY id DESC LIMIT 50",(user['id'],))]
    return {'ok':True,'sanctions':sanctions,'tickets':tickets}


def support_context(user,data):
    if not user:raise Problem('로그인이 필요합니다.',401)
    import replays
    replay_id=text(data.get('replayId'),'기보 ID',64)
    record=replays.admin_payload(replay_id)
    if not record:raise Problem('종료된 기보를 찾을 수 없습니다.',404)
    payload,access=record
    if user['id'] not in access.get('users',[]):raise Problem('본인이 참여한 종료 대국만 신고할 수 있습니다.',403)
    targets=[]
    for uid in access.get('users',[]):
        u=accounts.user_by_id(uid)
        if u and uid!=user['id']:targets.append({'id':uid,'name':u['name']})
    return {'ok':True,'targets':targets,'frames':len(payload['frames'])}
