import copy, json, time, os
from pathlib import Path
import pytest
import accounts, matchmaking, server, pieces, account_lifecycle, replays
from test_security import http_world
from test_fogchess import bare, put, clean_terrain, _set_terrain

OUT = None

def evidence(name, data):
    if os.environ.get('FOG_QA_EVIDENCE'):
        out = Path(os.environ['FOG_QA_EVIDENCE']); out.mkdir(parents=True, exist_ok=True)
        (out/name).write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')

@pytest.fixture(autouse=True)
def isolation(monkeypatch,tmp_path):
    monkeypatch.setenv('FOG_SECURITY_DB',str(tmp_path/'security.db'))
    monkeypatch.setenv('FOG_REPLAY_DB',str(tmp_path/'replays.db'))
    monkeypatch.setattr(matchmaking,'QUEUE',{})
    monkeypatch.setattr(server,'draw_starting_color',lambda:'W')

def member(http,name):
    value=http('/signup',{'name':name,'pw':'FixturePass123!'})[2]
    assert value['ok'];return value

@pytest.mark.parametrize('invalidate',['logout','password'])
def test_invalidated_pending_session_cannot_enter_rank(http_world,invalidate):
    a=member(http_world,'SessionA');b=member(http_world,'SessionB')
    a2=http_world('/login',{'name':'SessionA','pw':'FixturePass123!'})[2]
    assert http_world('/match/join',{'session':a['session']})[2]['state']=='waiting'
    assert http_world('/match/join',{'session':b['session']})[2]['state']=='found'
    assert http_world('/match/accept',{'session':a['session']})[2]['state']=='found'
    if invalidate=='logout':
        assert http_world('/logout',{'session':a['session']})[2]['ok']
    else:
        assert http_world('/account/pw',{'session':a2['session'],'old':'FixturePass123!','new':'SecondFixture123!'})[2]['ok']
    assert accounts.user_by_token(a['session']) is None
    result=http_world('/match/accept',{'session':b['session']})[2]
    assert result['state']=='waiting'
    assert a['session'] not in matchmaking.QUEUE
    assert not server.active_account_room(a['user']['id'])
    assert not server.ROOMS
    future=time.time()+91
    server.sweep_rooms(future)
    assert accounts.user_by_id(a['user']['id'])['rating']==1000
    assert not accounts.game_history(a['user']['id'])
    evidence(f'invalidated-{invalidate}.json', {'revoked_session_authenticated':False,
        'opponent_accept_state':result['state'],'new_rank_rooms':len(server.ROOMS),
        'rating_after_simulated_91_seconds':1000,'history_rows':0})

@pytest.mark.parametrize('mode',['solo','vs_bot'])
def test_account_delete_while_queue_practice_active_is_blocked_and_no_rating(http_world,mode):
    a=member(http_world,'WarmupOwner')
    http_world('/match/join',{'session':a['session']})
    join=http_world('/join',dict(session=a['session'],queuePractice=True,**{mode:True}))[2]
    room=server.ROOMS[join['room']]
    assert room['queue_practice']
    delete=http_world('/account/delete',{'session':a['session'],'pw':'FixturePass123!','confirm':'DELETE'})
    assert delete[0]==409 and delete[2]['activeGame']['mode']=='practice'
    assert http_world('/match/cancel',{'session':a['session']})[2]['state']=='idle'
    assert not server.is_rated(room)
    assert http_world('/practice/leave',{'session':a['session'],'room':join['room']})[2]['ok']
    assert http_world('/account/delete',{'session':a['session'],'pw':'FixturePass123!','confirm':'DELETE'})[2]['ok']

@pytest.mark.parametrize('side,other',[('W','B'),('B','W')])
@pytest.mark.parametrize('kind,origin,target',[('N',(6,4),(4,5)),('B',(6,7),(4,5)),('R',(6,5),(4,5)),('Q',(6,7),(4,5)),('P',(5,5),(4,5))])
def test_hidden_movement_has_no_public_fx_or_notation(side,other,kind,origin,target):
    if side=='B' and kind=='P':origin=(3,5)
    _set_terrain(bushes={target})
    st=bare();st['turn']=side
    pid=side+'_'+kind+'1'
    put(st,pid,side,kind,*origin)
    put(st,side+'_K1',side,'K',11,11)
    put(st,other+'_K1',other,'K',0,0)
    put(st,other+'_N1',other,'N',4,7)
    assert pieces.apply_move(st,side,pid,*target)[0]
    view=pieces.player_view(st,other)
    assert view['grid'][target[0]][target[1]]['p'] is None
    assert view['fx'] is None and not view['moveHistory'] and 'notation' not in view

def test_scan_expiration_does_not_leave_hidden_fx():
    _set_terrain(bushes={(5,5)})
    st=bare();put(st,'W_R1','W','R',5,4);put(st,'B_N1','B','N',5,7)
    st['scans']=[{'viewer':'B','cells':[(5,5)],'until':1}]
    assert pieces.apply_move(st,'W','W_R1',5,5)[0]
    view=pieces.player_view(st,'B')
    assert st['turnCount']==1 and not view['scanZones'] and view['fx'] is None

def test_deleted_renamed_user_chat_author_is_anonymized(http_world):
    a=member(http_world,'OldNick');b=member(http_world,'KeepNick')
    seat=http_world('/join',{'session':a['session']})[2]
    peer=http_world('/join',{'session':b['session'],'room':seat['room']})[2]
    assert http_world('/chat',dict(seat,text='test message',nonce='qa-message-1'))[2]['ok']
    assert http_world('/action',dict(seat,type='resign'))[2]['ok']
    assert http_world('/account/name',{'session':a['session'],'name':'NewNick'})[2]['ok']
    result=http_world('/account/delete',{'session':a['session'],'pw':'FixturePass123!','confirm':'DELETE'})[2]
    assert result['ok']
    with accounts._db() as db:
        row=db.execute('SELECT names_json,chat_json FROM admin_games LIMIT 1').fetchone()
    names=json.loads(row['names_json']);chat=json.loads(row['chat_json'])
    assert account_lifecycle.REMOVED in names.values()
    assert chat[0]['name']==account_lifecycle.REMOVED
    assert chat[0]['text']=='test message'
    assert server.ROOMS[seat['room']]['chat'][0]['name']==account_lifecycle.REMOVED
    evidence('renamed-delete-chat.json', {'names':names,'archived_chat':chat})

def test_disconnect_reason_is_explicit_in_state_history_and_replay(http_world):
    a=member(http_world,'DisconnectA');b=member(http_world,'DisconnectB')
    http_world('/match/join',{'session':a['session']})
    http_world('/match/join',{'session':b['session']})
    http_world('/match/accept',{'session':a['session']})
    matched=http_world('/match/accept',{'session':b['session']})[2]
    room=server.ROOMS[matched['room']]
    future=time.time()+91
    room['seen'][matched['token']]=future
    server.sweep_rooms(future)
    history=accounts.game_history(a['user']['id'])
    assert room['state']['phase']=='over' and any('접속 끊김' in ln for ln in room['state']['log'])
    assert history[0]['reason']=='disconnect'
    with accounts._db() as db:
        assert db.execute('SELECT reason FROM admin_games LIMIT 1').fetchone()['reason']=='disconnect'
    assert room['state']['end_reason']=='disconnect'
    view=server.state_response(room,'B',future)
    assert view['endReason']=='disconnect'
    payload=replays.admin_payload(view['replayId'])[0]
    assert payload['endReason']=='disconnect'
    frame=payload['frames'][-1]
    assert frame['view']['endReason']=='disconnect'
    assert all(p['endReason']=='disconnect' for p in frame['perspectives'].values())
    assert '접속 종료' in frame['label']
    assert frame['action']['endReason']=='disconnect'
    evidence('disconnect-reason.json', {'state':room['state']['end_reason'],
        'history':history[0]['reason'],'api':view['endReason'],'replay':payload['endReason'],
        'test_clock':'time.time() + 91 seconds; opponent remains connected'})


def paired(http):
    a=member(http,'QueuedA'); b=member(http,'QueuedB')
    http('/match/join',{'session':a['session']})
    http('/match/join',{'session':b['session']})
    return a,b


@pytest.mark.parametrize('invalidate',['expired','deleted','wrong_owner'])
def test_commit_boundary_revalidates_both_accounts(http_world,invalidate):
    a,b=paired(http_world)
    now=time.time()
    matchmaking.accept(a['session'],now); matchmaking.accept(b['session'],now)
    if invalidate=='wrong_owner':
        matchmaking.QUEUE[a['session']]['uid']=b['user']['id']+100
    else:
        with accounts._db() as db:
            if invalidate=='expired':
                db.execute('UPDATE sessions SET created=? WHERE token=?',(now-accounts.SESSION_TTL-10,a['session']))
            else:
                db.execute('DELETE FROM users WHERE id=?',(a['user']['id'],))
    with server.lock:
        result=matchmaking.status(b['session'],now,server.commit_match_room)
    assert result['state']=='waiting' and not server.ROOMS
    assert a['session'] not in matchmaking.QUEUE


def test_recovery_revokes_accepted_queue_but_keeps_practice(http_world):
    a=member(http_world,'RecoverA'); b=member(http_world,'RecoverB')
    code=http_world('/account/recovery',{'session':a['session'],'pw':'FixturePass123!'})[2]['recovery']
    http_world('/match/join',{'session':a['session']})
    practice=http_world('/join',{'session':a['session'],'solo':True,'queuePractice':True})[2]
    http_world('/match/join',{'session':b['session']})
    http_world('/match/accept',{'session':a['session']})
    recovered=http_world('/recover/code',{'code':code,'new':'RecoveredPass123!'})[2]
    assert recovered['ok'] and accounts.user_by_token(a['session']) is None
    assert a['session'] not in matchmaking.QUEUE
    assert http_world('/match/accept',{'session':b['session']})[2]['state']=='waiting'
    assert list(server.ROOMS)==[practice['room']]
    assert server.ROOMS[practice['room']]['queue_practice']
    assert http_world('/match/status',{'session':recovered['session']})[2]['state']=='idle'
    assert not accounts.game_history(a['user']['id'])


@pytest.mark.parametrize('operation',['logout','password','recover'])
def test_revoking_auth_keeps_existing_rank_seat_reconnectable(http_world,operation):
    a,b=paired(http_world)
    code=http_world('/account/recovery',{'session':a['session'],'pw':'FixturePass123!'})[2]['recovery']
    a2=http_world('/login',{'name':'QueuedA','pw':'FixturePass123!'})[2]
    http_world('/match/accept',{'session':a['session']})
    matched=http_world('/match/accept',{'session':b['session']})[2]
    room=server.ROOMS[matched['room']]
    seat=room['seats']['W']
    if operation=='logout':
        assert http_world('/logout',{'session':a['session']})[2]['ok']
        session=a2['session']
    elif operation=='password':
        assert http_world('/account/pw',{'session':a2['session'],'old':'FixturePass123!','new':'ChangedPass123!'})[2]['ok']
        session=a2['session']
    else:
        result=http_world('/recover/code',{'code':code,'new':'RecoveredPass123!'})[2]
        assert result['ok'];session=result['session']
    assert accounts.user_by_token(a['session']) is None
    result=http_world('/match/status',{'session':session})[2]
    assert result['state']=='matched' and result['token']==seat
    assert result['room']==room['code'] and len(server.ROOMS)==1
    assert room['state']['phase']=='setup'


def test_password_failure_and_current_session_do_not_cancel_valid_pair(http_world):
    a,b=paired(http_world)
    http_world('/match/accept',{'session':a['session']})
    assert not http_world('/account/pw',{'session':a['session'],'old':'wrong','new':'ChangedPass123!'})[2]['ok']
    assert matchmaking.QUEUE[a['session']]['pending']['accepted']
    assert http_world('/account/pw',{'session':a['session'],'old':'FixturePass123!','new':'ChangedPass123!'})[2]['ok']
    assert matchmaking.QUEUE[a['session']]['pending']['accepted']
    assert http_world('/match/accept',{'session':b['session']})[2]['state']=='matched'


@pytest.mark.parametrize('phase',['waiting','pending'])
def test_logout_cleans_only_its_queue_and_does_not_transfer_stale_accept(http_world,phase):
    a=member(http_world,'LogoutA');b=member(http_world,'LogoutB')
    a2=http_world('/login',{'name':'LogoutA','pw':'FixturePass123!'})[2]
    http_world('/match/join',{'session':a['session']})
    if phase=='pending':
        http_world('/match/join',{'session':b['session']})
        http_world('/match/accept',{'session':a['session']})
    assert http_world('/logout',{'session':a['session']})[2]['ok']
    assert a['session'] not in matchmaking.QUEUE
    assert http_world('/match/status',{'session':a2['session']})[2]['state']=='idle'
    if phase=='pending':
        assert http_world('/match/status',{'session':b['session']})[2]['state']=='waiting'


@pytest.mark.parametrize('cause',['resign','disconnect','timeout','draw','king'])
def test_all_end_reasons_are_structural_and_reset_for_new_game(cause):
    st=bare()
    if cause in ('resign','disconnect'):
        assert pieces.apply_resign(st,'W',cause)[0]
    elif cause=='timeout':
        st['misses']['W']=pieces.MAX_MISSES-1
        assert pieces.time_out(st)
    elif cause=='draw':
        st['turnCount']=pieces.TURN_LIMIT-1
        pieces.advance_turn(st)
    else:
        target=put(st,'B_K1','B','K',0,0)
        pieces.kill(st,target,'W','R','melee')
    assert st['phase']=='over' and st['end_reason']==cause
    st['log']=['arbitrary later presentation message']
    assert server.game_reason(st)==cause
    assert pieces.player_view(st,'W')['endReason']==cause
    assert pieces.new_game()['end_reason'] is None


def test_anonymization_uses_author_side_not_old_name_and_preserves_body():
    data={'names':{'W':'OldNick','B':'NewNick'},'chat':[
        {'id':1,'side':'W','name':'OldNick','text':'OldNick and NewNick remain in the message'},
        {'id':2,'side':'B','name':'NewNick','text':'I saw OldNick'}]}
    result=account_lifecycle.anonymize(data,'NewNick',['W'])
    assert result['names']=={'W':account_lifecycle.REMOVED,'B':'NewNick'}
    assert result['chat'][0]['name']==account_lifecycle.REMOVED
    assert result['chat'][1]['name']=='NewNick'
    assert [m['text'] for m in result['chat']]==[m['text'] for m in data['chat']]
    assert data['chat'][0]['name']=='OldNick'


def test_unrated_solo_archive_and_replay_keep_manual_resign_reason(http_world):
    seat=http_world('/join',{'solo':True})[2]
    result=http_world('/action',dict(seat,type='resign'))[2]
    assert result['ok']
    room=server.ROOMS[seat['room']]
    assert room['state']['end_reason']=='resign'
    with accounts._db() as db:
        assert db.execute('SELECT reason FROM admin_games LIMIT 1').fetchone()['reason']=='resign'
    payload=replays.admin_payload(room['_replay']['data']['id'])[0]
    assert payload['endReason']=='resign'
    assert payload['frames'][-1]['action']['compact']=='resign'
