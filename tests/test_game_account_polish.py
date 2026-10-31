import copy
import gzip
import json
import time
import pytest
import accounts
import account_lifecycle
import matchmaking
import pieces
import replays
import server
from test_security import http_world
from test_fogchess import bare, put, clean_terrain, _set_terrain


@pytest.mark.parametrize('side,start,end', [('W',1,0),('B',10,11)])
def test_queen_promotion_then_scan(side,start,end):
    st=bare();st['turn']=side
    pawn=put(st,side+'_P1',side,'P',start,5,moved=True)
    assert pieces.apply_move(st,side,pawn['id'],end,5)[0]
    assert not pieces.apply_promote(st,'B' if side=='W' else 'W','Q')[0]
    assert pieces.apply_promote(st,side,'Q')[0]
    assert pawn['t']=='Q' and st['promote'] is None and st['turnCount']==1
    st['turn']=side
    assert pieces.apply_scan(st,side,pawn['id'],end,5)[0]


@pytest.mark.parametrize('side', ['W','B'])
@pytest.mark.parametrize('mode', ['friend','bot','rank'])
def test_new_game_color_and_reconnect(http_world,monkeypatch,side,mode):
    monkeypatch.setattr(server,'draw_starting_color',lambda:side)
    if mode=='rank':
        a=accounts.signup('First','FixturePass123!')[0];b=accounts.signup('Second','FixturePass123!')[0]
        entries=[dict(uid=x['user']['id'],name=x['user']['name'],rating=1000) for x in (a,b)]
        code,ta,ca,tb,cb=server.make_match_room(*entries)
        assert ca==side and cb!=ca
        seat={'room':code,'token':ta,'color':ca}
    else:
        seat=http_world('/join',{'vs_bot':mode=='bot'})[2]
        assert seat['color']==side
    room=server.ROOMS[seat['room']]
    assert room['tokens'][seat['token']]==side and room['seats'][side]==seat['token']
    assert http_world('/join',seat)[2]==seat
    if mode=='friend':
        other=http_world('/join',{'room':seat['room']})[2]
        assert other['color']!=side and other['color']!='spectator'
    if mode=='bot':
        computer='B' if side=='W' else 'W'
        assert room['bot']==computer and room['state']['ready'][computer]
        assert not room['state']['ready'][side]
        assert not server.valid_client_token(room,server.BOT_TOKEN)
        http_world('/action',dict(seat,type='ready'))
        assert room['state']['phase']=='play' and room['state']['turn']=='W'
        assert (room['state']['turn']==room['bot'])==(side=='B')
        room['state'].update(phase='over',winner=side)
        assert server.start_rematch(room)
        assert room['state']['ready'][computer] and not room['state']['ready'][side]


def test_rank_queue_order_does_not_choose_color(http_world,monkeypatch):
    monkeypatch.setattr(matchmaking,'QUEUE',{})
    a=accounts.signup('Early','FixturePass123!')[0];b=accounts.signup('Late','FixturePass123!')[0]
    for forced in ('B','W'):
        monkeypatch.setattr(server,'draw_starting_color',lambda:forced)
        matchmaking.QUEUE.clear();server.ROOMS.clear()
        matchmaking.join(a['session'],a['user'],100)
        matchmaking.join(b['session'],b['user'],101)
        matchmaking.try_match(101)
        matchmaking.accept(a['session'],102);matchmaking.accept(b['session'],102)
        first=matchmaking.status(a['session'],102,server.make_match_room)
        second=matchmaking.status(b['session'],102,server.make_match_room)
        assert first['color']==forced and second['color']!=forced
        assert server.ROOMS[first['room']]['users'][forced]==a['user']['id']


@pytest.mark.parametrize('actor,viewer', [('W','B'),('B','W')])
@pytest.mark.parametrize('origin', [(5,4),(4,5)])
def test_concealed_bush_move_has_no_enemy_effect(actor,viewer,origin):
    _set_terrain(bushes={(5,5),(4,5)})
    st=bare();st['turn']=actor
    put(st,actor+'_R1',actor,'R',*origin)
    put(st,viewer+'_N1',viewer,'N',6,6) # Lit terrain does not reveal its occupants.
    assert (5,5) in pieces.visible_cells(st,viewer)
    assert pieces.apply_move(st,actor,actor+'_R1',5,5)[0]
    hidden=pieces.player_view(st,viewer)
    assert hidden['grid'][5][5]['p'] is None and hidden['fx'] is None
    assert pieces.player_view(st,actor)['fx']['cells']==[[5,5]]
    # Real scan vision makes the same movement observable, and expiry hides it again.
    st['scans']=[{'viewer':viewer,'cells':[(5,5)],'until':st['turnCount']+1}]
    visible=pieces.player_view(st,viewer)
    assert visible['grid'][5][5]['p'] and visible['fx']['cells']==[[5,5]]
    assert visible['scanZones'][0]['remaining']==1
    assert set(visible['scanZones'][0])=={'cells','owner','remaining'}
    st['turnCount']+=1
    assert pieces.player_view(st,viewer)['fx'] is None
    assert pieces.player_view(st,viewer)['scanZones']==[]


def member(http,name):
    response=http('/signup',{'name':name,'pw':'FixturePass123!'})[2]
    assert response['ok'];return response


def test_delete_requires_confirmation_password_and_revokes_all_sessions(http_world):
    one=member(http_world,'DeleteMe');uid=one['user']['id']
    other=member(http_world,'KeepMe')
    second=accounts.login('DeleteMe','FixturePass123!')[0]
    assert http_world('/account/delete',{'session':'bad','confirm':'DELETE','pw':'FixturePass123!'})[0]==401
    assert not http_world('/account/delete',{'session':one['session'],'pw':'FixturePass123!'})[2]['ok']
    assert not http_world('/account/delete',{'session':one['session'],'pw':'wrong','confirm':'DELETE','userId':other['user']['id']})[2]['ok']
    assert accounts.user_by_id(uid)
    accounts.add_game(uid,'bot','win','king','Bot',None,1300,True,12,1012,'ROOM')
    accounts.add_game(other['user']['id'],'lobby','loss','king','DeleteMe',uid,1012,False,None,None,'ROOM')
    payload={'id':'keep-replay','names':{'W':'DeleteMe','B':'KeepMe'},'frames':[{'view':{'names':{'W':'DeleteMe','B':'KeepMe'}}}]}
    with replays.database() as db:
        db.execute('INSERT INTO replays VALUES(?,?,?,?)',('keep-replay',time.time()-300,json.dumps({'users':[uid,other['user']['id']],'tokens':[]}),gzip.compress(json.dumps(payload).encode())))
    result=http_world('/account/delete',{'session':one['session'],'pw':'FixturePass123!','confirm':'DELETE','userId':other['user']['id']})
    assert result[2]['ok']
    assert not accounts.user_by_id(uid) and not accounts.user_by_token(second['session'])
    assert not accounts.user_by_token(one['session']) and accounts.user_by_token(other['session'])
    assert accounts.game_history(uid)==[]
    assert accounts.game_history(other['user']['id'])[0]['opp_name']==account_lifecycle.REMOVED
    assert not accounts.login('DeleteMe','FixturePass123!')[0]
    assert not accounts.recover_with_code(one['recovery'],'NewFixture123!')[0]
    replay=replays.load('keep-replay','',other['session'],time.time())['replay']
    assert replay['names']['W']==account_lifecycle.REMOVED and replay['names']['B']=='KeepMe'


def test_delete_blocks_active_game_and_revokes_finished_room_token(http_world):
    user=member(http_world,'Playing')
    seat=http_world('/join',{'session':user['session'],'vs_bot':True})[2]
    body={'session':user['session'],'pw':'FixturePass123!','confirm':'DELETE'}
    assert http_world('/account/delete',body)[0]==409
    assert accounts.user_by_token(user['session'])
    assert http_world('/action',dict(seat,type='resign'))[2]['ok']
    assert http_world('/account/delete',body)[2]['ok']
    room=server.ROOMS[seat['room']]
    assert not server.valid_client_token(room,seat['token'])
    assert not server.rematch_request(room,seat['color'])['ok']


def test_delete_cancels_queue_and_releases_opponent(http_world,monkeypatch):
    monkeypatch.setattr(matchmaking,'QUEUE',{})
    one=member(http_world,'QueueOne');two=member(http_world,'QueueTwo')
    now=time.time()
    for user in (one,two):matchmaking.join(user['session'],user['user'],now)
    matchmaking.try_match(now)
    assert matchmaking.QUEUE[two['session']]['pending']
    assert http_world('/account/delete',{'session':one['session'],'pw':'FixturePass123!','confirm':'DELETE'})[2]['ok']
    assert one['session'] not in matchmaking.QUEUE and not matchmaking.QUEUE[two['session']]['pending']


def test_guest_signup_keeps_replay_but_does_not_import_ratings(http_world):
    guest=http_world('/join',{'vs_bot':True})[2]
    assert http_world('/action',dict(guest,type='resign'))[2]['ok']
    user=member(http_world,'NewMember')
    assert user['user']['rating']==1000 and accounts.game_history(user['user']['id'])==[]
    room=server.ROOMS[guest['room']]
    rid=room['_replay']['data']['id']
    assert replays.load(rid,guest['token'],user['session'],time.time())['ok']


def test_deletion_rolls_back_if_shared_archive_cannot_be_processed(http_world):
    user=member(http_world,'Rollback')
    with replays.database() as db:
        db.execute('INSERT INTO replays VALUES(?,?,?,?)',('broken',time.time(),json.dumps({'users':[user['user']['id']],'tokens':[]}),b'broken-gzip'))
    with pytest.raises(gzip.BadGzipFile):
        account_lifecycle.delete_account(user['session'],'FixturePass123!')
    assert accounts.user_by_token(user['session']) and accounts.user_by_id(user['user']['id'])
