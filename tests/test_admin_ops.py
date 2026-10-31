import json, time, uuid, sqlite3
from concurrent.futures import ThreadPoolExecutor
import pytest
import accounts, admin_ops as ops, server, spectator, replays
from test_security import http_world

KEY={'X-Admin-Key':'Admin-Test-Key'}
def change(action,**kw):
    return ops.mutate(action,dict(requestId=uuid.uuid4().hex,**kw),'QA operator')

def signup(name='Alpha'):
    data,err=accounts.signup(name,'Secure-Test-492!')
    assert not err
    return data

def game(a,b,code='QA01',pending=False):
    r=server.new_room(code)
    r.update(match=True,users={'W':a['user']['id'],'B':b['user']['id']},names={'W':a['user']['name'],'B':b['user']['name']},ratings={'W':1000,'B':1000})
    r['state'].update(phase='play',turn_deadline=None)
    spectator.capture(r)
    r['state']['notation']=[{'action':'fire','actor':'W','captures':1},{'action':'scan','actor':'B','captures':0}]
    r['state'].update(phase='over',winner='W')
    if pending:
        real=accounts.settle_game
        accounts.settle_game=lambda *a: (_ for _ in ()).throw(sqlite3.OperationalError('injected'))
        try:assert not server.settle_rating(r)
        finally:accounts.settle_game=real
    else:assert server.settle_rating(r)
    spectator.capture(r)
    return r

@pytest.fixture(autouse=True)
def isolated(tmp_path,monkeypatch):
    monkeypatch.setattr(accounts,'DB_PATH',str(tmp_path/'ops.db'))
    monkeypatch.setattr(accounts,'_ready',False)
    monkeypatch.setattr(server.matchmaking,'QUEUE',{})
    accounts.init_db()

@pytest.mark.parametrize('path',['overview','users','user?id=1','tickets','games','game?id=none','replay?id=none','notices','balance','audit'])
def test_all_admin_reads_require_key(http_world,path):
    assert http_world('/admin/ops/'+path)[0]==403
    assert http_world('/admin/ops/'+path,headers=KEY)[0] in (200,404)

@pytest.mark.parametrize('action',['sanction','revoke','ticket','ticket-delete','notice','maintenance','adjust','review','retry','error'])
def test_all_admin_writes_require_key(http_world,action):
    assert http_world('/admin/ops/'+action,{'key':'Admin-Test-Key'})[0]==403
    assert http_world('/admin/ops/'+action,{},headers=KEY)[0]==400


def test_mutation_once_conflict_rollback_and_audit():
    a=signup();uid=a['user']['id']
    data={'requestId':uuid.uuid4().hex,'userId':uid,'kind':'chat','days':1,'reason':'Confirmed abuse'}
    with ThreadPoolExecutor(max_workers=5) as pool:
        results=list(pool.map(lambda _:ops.mutate('sanction',data,'QA'),range(5)))
    assert all(x==results[0] for x in results)
    assert len(ops.restrictions(uid))==len(ops.audit()['rows'])==1
    with pytest.raises(ops.Problem,match='요청 ID'):ops.mutate('sanction',dict(data,days=2),'QA')
    with pytest.raises(ops.Problem):change('sanction',userId=uid,kind='account',days=31,reason='invalid')
    assert len(ops.audit()['rows'])==1
    assert ops.block_reason(uid,'chat') and not ops.block_reason(uid,'match')
    change('revoke',id=results[0]['id'],reason='appeal accepted')
    assert not ops.block_reason(uid,'chat')
    assert len(ops.audit()['rows'])==2


def test_scoped_support_login_appeal_and_own_only(http_world):
    a,b=signup(),signup('Bravo')
    sid=change('sanction',userId=a['user']['id'],kind='account',days=1,reason='reviewed')['id']
    assert not accounts.login('Alpha','Secure-Test-492!')[0]
    status,_,support=http_world('/support/login',{'name':'Alpha','pw':'Secure-Test-492!'})
    assert status==200 and support['ok']
    token=support['session']
    assert not accounts.user_by_token(token)
    assert accounts.user_by_token(token,support=True)['id']==a['user']['id']
    assert not http_world('/join',{'session':token})[2]['ok']
    assert http_world('/support/mine',{'session':token})[2]['sanctions'][0]['id']==sid
    assert http_world('/support/submit',{'session':b['session'],'kind':'appeal','sanctionId':sid,'message':'not mine'})[0]==403
    assert http_world('/support/submit',{'session':token,'kind':'appeal','sanctionId':sid,'message':'please review'})[2]['ok']
    assert http_world('/support/submit',{'session':token,'kind':'appeal','sanctionId':sid,'message':'duplicate review'})[0]==409
    mine=http_world('/support/mine',{'session':token})[2]
    assert 'admin_note' not in json.dumps(mine) and len(mine['tickets'])==1


def test_reports_link_only_owned_ended_replay(http_world):
    a,b,c=signup(),signup('Bravo'),signup('Charlie')
    r=game(a,b);rid=r['_replay']['data']['id']
    ctx=http_world('/support/context',{'session':a['session'],'replayId':rid})[2]
    assert ctx['ok'] and ctx['targets']==[{'id':b['user']['id'],'name':'Bravo'}]
    payload={'kind':'report','replayId':rid,'frame':1,'targetUserId':b['user']['id'],'category':'cheat','message':'review the position'}
    assert http_world('/support/submit',dict(payload,session=c['session']))[0]==403
    assert http_world('/support/submit',dict(payload,session=a['session'],frame=999))[0]==400
    result=http_world('/support/submit',dict(payload,session=a['session']))[2]
    assert result['ok']
    ticket=ops.tickets()['rows'][0]
    change('ticket',id=ticket['id'],revision=ticket['revision'],state='done',category='cheat',priority='high',note='Evidence reviewed')
    with pytest.raises(ops.Problem):change('ticket',id=ticket['id'],revision=ticket['revision'],state='review',category='cheat',priority='high',note='stale')
    assert ops.tickets()['rows'][0]['state']=='done'
    assert 'Evidence reviewed' not in json.dumps(ops.support_mine(a['user']))


def test_archived_pending_survives_restart_and_retry_is_once():
    a,b=signup(),signup('Bravo');r=game(a,b,pending=True);gid=r['state']['_settlement_id']
    accounts.init_db(accounts.DB_PATH)
    assert ops.game_detail(gid)['game']['pending']
    result=change('retry',id=gid,revision=1,reason='storage restored')
    assert result['ok'] and not ops.game_detail(gid)['game']['pending']
    with pytest.raises(ops.Problem):change('retry',id=gid,revision=2,reason='repeat')
    with accounts._db() as db:assert db.execute('SELECT count(*) FROM games').fetchone()[0]==2
    assert accounts.user_by_id(a['user']['id'])['wins']==1


def test_historical_correction_shifts_history_receipts_and_preserves_wins():
    a,b=signup(),signup('Bravo');r1=game(a,b);r2=game(a,b,'QA02')
    g1=r1['state']['_settlement_id'];g2=r2['state']['_settlement_id']
    before=ops.game_detail(g2)['game'];old=ops.game_detail(g1)['game']['result']
    deltas={side:value['delta']+(4 if side=='W' else -4) for side,value in old.items()}
    change('adjust',id=g1,revision=1,deltas=deltas,reason='verified correction')
    after=ops.game_detail(g2)['game']
    assert after['result']['W']['rating']==before['result']['W']['rating']+4
    assert after['revision']>before['revision']
    uid=a['user']['id']
    assert accounts.user_by_id(uid)['wins']==2
    with accounts._db() as db:
        last=db.execute('SELECT rating_after FROM games WHERE user_id=? ORDER BY id DESC',(uid,)).fetchone()[0]
    assert last==accounts.user_by_id(uid)['rating']==after['result']['W']['rating']
    with pytest.raises(ops.Problem):change('adjust',id=g2,revision=after['revision'],deltas={'W':-1000,'B':1000},reason='invalid floor')
    assert accounts.user_by_id(uid)['rating']==last


def test_public_notices_versions_and_real_stats(http_world):
    n=change('notice',title='Scheduled maintenance',body='New matches pause only',kind='maintenance',published=False,reason='prepare')
    assert http_world('/announcements')[2]['rows']==[]
    change('notice',id=n['id'],revision=1,title='Scheduled maintenance',body='New matches pause only',kind='maintenance',published=True,reason='publish')
    assert len(http_world('/announcements')[2]['rows'])==1
    with pytest.raises(ops.Problem):change('notice',id=n['id'],revision=1,title='stale',body='stale body',kind='update',published=True,reason='stale')
    assert ops.balance()['games']==0
    game(signup(),signup('Bravo'))
    stats=ops.balance()
    assert stats['games']==1 and stats['outcomes']=={'W':1}
    assert stats['uses']=={'fire':1,'scan':1} and stats['captureUses']['fire']==1


def test_maintenance_new_games_blocked_current_reconnect_preserved(http_world):
    a=signup()
    first=http_world('/join',{'session':a['session']})[2]
    assert first.get('room')
    change('maintenance',paused=True,expectedPaused=False,reason='service update')
    assert not http_world('/join',{'session':a['session'],'vs_bot':True})[2]['ok']
    assert not http_world('/join',{'name':'Guest'})[2]['ok']
    assert http_world('/join',{'session':a['session'],'room':first['room'],'token':first['token']})[2].get('room')==first['room']
    # A seat token cannot turn a new solo/bot game into a reconnect.
    assert not http_world('/join',{'room':first['room'],'token':first['token'],'solo':True})[2]['ok']
    assert http_world('/state?room='+first['room']+'&token='+first['token'])[2].get('phase')
    change('maintenance',paused=False,expectedPaused=True,reason='completed')
    assert http_world('/join',{'name':'Guest'})[2].get('room')


def test_moderation_enforced_on_existing_chat_and_actions(http_world):
    a=signup();uid=a['user']['id']
    first=http_world('/join',{'session':a['session']})[2]
    second=http_world('/join',{'room':first['room'],'name':'Bravo'})[2]
    common={'room':first['room'],'token':first['token']}
    sid=change('sanction',userId=uid,kind='chat',days=1,reason='abusive chat')['id']
    assert not http_world('/chat',dict(common,text='blocked',nonce='a'))[2]['ok']
    change('revoke',id=sid,reason='reviewed')
    assert http_world('/chat',dict(common,text='allowed',nonce='b'))[2]['ok']
    change('sanction',userId=uid,kind='account',days=1,reason='abuse')
    assert not http_world('/action',dict(common,type='ready'))[2]['ok']
    assert http_world('/state?room='+first['room']+'&token='+first['token'])[0]==403


def test_admin_payload_never_exposes_credentials_or_live_positions(http_world):
    a=signup();r=server.new_room('LIVE');r['users']={'W':a['user']['id']};r['names']={'W':'Alpha'}
    server.ROOMS['LIVE']=r;spectator.capture(r)
    for endpoint in ['users','user?id='+str(a['user']['id']),'overview','tickets','audit']:
        status,_,data=http_world('/admin/ops/'+endpoint,headers=KEY)
        assert status==200
        text=json.dumps(data)
        for forbidden in ['pw_hash','recov_hash','"salt"','"session"','"tokens"','"pieces"']: assert forbidden not in text
    assert http_world('/admin/ops/replay?id='+r['_replay']['data']['id'],headers=KEY)[0]==404

def test_failed_audit_rolls_back_change_and_receipt():
    uid=signup()['user']['id']
    with accounts._db() as db:db.execute("CREATE TRIGGER fail_audit BEFORE INSERT ON admin_audit BEGIN SELECT RAISE(ABORT,'injected'); END")
    with pytest.raises(sqlite3.IntegrityError):change('sanction',userId=uid,kind='chat',days=1,reason='should rollback')
    with accounts._db() as db:
        assert db.execute('SELECT count(*) FROM admin_sanctions').fetchone()[0]==0
        assert db.execute('SELECT count(*) FROM admin_receipts').fetchone()[0]==0


def test_expired_restriction_and_supersession():
    uid=signup()['user']['id']
    first=change('sanction',userId=uid,kind='match',days=1,reason='first')['id']
    second=change('sanction',userId=uid,kind='match',days=2,reason='extended')['id']
    assert len(ops.restrictions(uid))==1 and ops.restrictions(uid)[0]['id']==second
    history=ops.user_detail(uid)['sanctions']
    assert next(s for s in history if s['id']==first)['revoked_at']
    assert not ops.block_reason(uid,'match',time.time()+3*86400)


def test_queue_is_cancelled_and_cannot_match_after_sanction(http_world):
    a,b=signup(),signup('Bravo')
    assert http_world('/match/join',{'session':a['session']})[2]['ok']
    payload=dict(requestId=uuid.uuid4().hex,userId=a['user']['id'],kind='match',days=1,reason='verified restriction')
    assert http_world('/admin/ops/sanction',payload,KEY)[2]['ok']
    assert a['session'] not in server.matchmaking.QUEUE
    assert not http_world('/match/join',{'session':a['session']})[2]['ok']
    assert http_world('/match/join',{'session':b['session']})[2]['state']!='matched'
    assert not server.ROOMS


def test_maintenance_blocks_rematch_but_resignation_allowed(http_world):
    a=signup()
    joined=http_world('/join',{'session':a['session'],'vs_bot':True,'level':'easy'})[2]
    common={'room':joined['room'],'token':joined['token']}
    change('maintenance',paused=True,expectedPaused=False,reason='updating')
    assert http_world('/action',dict(common,type='resign'))[2]['ok']
    assert not http_world('/action',dict(common,type='rematch'))[2]['ok']


def test_stale_hidden_ticket_not_deleted_and_legacy_audited():
    fid=accounts.add_feedback('bug','feedback','Tester',None,None,'test')
    row=ops.tickets()['rows'][0]
    assert ops.legacy_feedback(row['id'],True,False,'legacy operator')
    with pytest.raises(ops.Problem):change('ticket-delete',id=row['id'],revision=row['revision'],reason='stale')
    assert ops.legacy_feedback(row['id'],True,True,'legacy operator')
    assert ops.tickets()['rows']==[] and len(ops.audit()['rows'])==2
    with accounts._db() as db:assert db.execute('SELECT deleted FROM feedback WHERE id=?',(row['id'],)).fetchone()[0]==1
