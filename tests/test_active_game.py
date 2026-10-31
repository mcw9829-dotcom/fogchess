"""Authenticated active-game discovery and safe resumption over real HTTP."""
import json
import pytest
import accounts
import server
from test_security import http_world


def member(http, name):
    result=http('/signup',{'name':name,'pw':'FixturePass123!'})[2]
    assert result['ok']
    return result['session']


@pytest.mark.parametrize('mode', ['bot','friend','rank'])
def test_owned_active_game_can_resume_without_local_seat_token(http_world, mode):
    session=member(http_world,'Owner')
    other=member(http_world,'Other')
    body={'session':session}
    if mode=='bot': body['vs_bot']=True
    seat=http_world('/join',body)[2]
    room=server.ROOMS[seat['room']]
    if mode=='rank': room['match']=True
    seen_before=dict(room['seen'])
    metadata=http_world('/me/active-game',{'session':session})[2]
    assert metadata['ok'] and metadata['activeGame']['room']==seat['room']
    assert metadata['activeGame']['mode']==mode
    assert 'token' not in json.dumps(metadata) and 'grid' not in json.dumps(metadata)
    assert room['seen']==seen_before # Discovery must not keep disconnected players alive.
    assert http_world('/me',{'session':session})[2]['activeGame']==metadata['activeGame']
    assert http_world('/me/active-game',{'session':other})[2]['activeGame'] is None
    # Forging a room code cannot resume another account's seat or create a new room.
    assert http_world('/join',{'session':other,'room':seat['room'],'resume':True})[0]==410
    resumed=http_world('/join',{'session':session,'room':seat['room'],'resume':True})[2]
    assert resumed['token']==seat['token'] and resumed['color']==seat['color']
    assert len(server.ROOMS)==1
    room['state'].update(phase='over',winner='draw')
    assert http_world('/me/active-game',{'session':session})[2]['activeGame'] is None
    assert http_world('/join',{'session':session,'room':seat['room'],'resume':True})[0]==410
    del server.ROOMS[seat['room']]
    assert http_world('/join',{'session':session,'room':seat['room'],'resume':True})[0]==410
    assert not server.ROOMS


def test_blocked_new_game_includes_owned_resume_metadata(http_world):
    session=member(http_world,'Owner')
    seat=http_world('/join',{'session':session,'vs_bot':True})[2]
    for path,body in [('/match/join',{}),('/join',{'vs_bot':True}),('/join',{'solo':True})]:
        result=http_world(path,dict(body,session=session))[2]
        assert not result['ok'] and result['activeGame']['room']==seat['room']
        assert 'token' not in json.dumps(result)
    assert len(server.ROOMS)==1


def test_resume_requires_real_authenticated_account(http_world):
    for session in ['', 'invalid']:
        assert http_world('/me/active-game',{'session':session})[0]==401
        assert http_world('/join',{'session':session,'room':'FAKE12','resume':True})[0]==410
    assert not server.ROOMS
