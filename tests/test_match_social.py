import copy
import json
import threading
import time
from urllib.request import Request, urlopen
import pytest
import server
import match_social as social

@pytest.fixture
def room(monkeypatch, tmp_path):
    monkeypatch.setattr(server, 'ROOMS', {})
    monkeypatch.setattr(server.accounts, 'DB_PATH', str(tmp_path / 'accounts.db'))
    server.accounts.init_db()
    r = server.new_room('SOCIAL')
    r.update(match=True, tokens={'white': 'W', 'black': 'B', 'watch': 'spectator'},
             seats={'W': 'white', 'B': 'black'}, names={'W': 'White', 'B': 'Black'},
             seen=dict.fromkeys(('white','black','watch'),time.time()))
    server.ROOMS['SOCIAL'] = r
    server.use_terrain(r)
    return r

def finish(room, winner):
    room['state'].update(phase='over', winner=winner)
    return social.series(room)

def again(room):
    assert server.rematch_request(room,'W') == {'ok': True, 'pending': True}
    assert server.rematch_request(room,'B') == {'ok': True}
    assert room['state']['phase'] == 'setup'

def test_two_wins_blocks_both_players_and_counts_once(room):
    assert finish(room,'W')['wins'] == {'W':1,'B':0}
    for _ in range(3):
        assert server.state_response(room,'W',time.time())['series']['me'] == 1
    again(room)
    assert finish(room,'W')['complete']
    old = room['state']
    for side in ('W','B'): assert not server.rematch_request(room,side)['ok']
    assert room['state'] is old

def test_one_each_then_final_and_draws_do_not_limit_rounds(room):
    finish(room,'W'); again(room)
    finish(room,'B'); again(room)
    assert social.series_view(room,'B')['final']
    for _ in range(4):
        assert not finish(room,'draw')['complete']
        again(room)
    value = finish(room,'B')
    assert value['games'] == 7 and value['draws'] == 4
    assert value['winner'] == 'B' and value['wins'] == {'W':1,'B':2}
    assert not server.rematch_request(room,'B')['ok']

def test_decline_and_active_game_do_not_start_or_score(room):
    assert not server.rematch_request(room,'W')['ok']
    finish(room,'W')
    server.rematch_request(room,'W')
    server.rematch_decline(room,'B')
    assert room['rematch'] == {} and room['state']['phase'] == 'over'
    assert social.series(room)['games'] == 1

def test_friend_bot_solo_not_limited(room):
    room['match'] = False
    for _ in range(3):
        assert finish(room,'W') is None
        again(room)
    for mode in ('solo','bot'):
        room['match'] = True; room[mode] = True
        assert social.series(room) is None
        room.pop(mode)

def test_chat_auth_length_rate_limit_dedup_and_no_game_change(room):
    before = copy.deepcopy(room['state'])
    for token in ('watch','unknown'):
        assert not social.send_chat(room,token,'hi','1',0)['ok']
    for text in ('', ' '*20, 'x'*201, 42, '\u202e'):
        assert not social.send_chat(room,'white',text,'1',0)['ok']
    assert social.send_chat(room,'white','[b]안녕[/b] <script>','1',0)['ok']
    assert social.send_chat(room,'white','[b]안녕[/b] <script>','1',0.1)['ok']
    assert not social.send_chat(room,'white','flood','2',0.1)['ok']
    assert social.send_chat(room,'black','안녕하세요','1',0.1)['ok']
    assert len(room['chat']) == 2 and room['state'] == before
    assert 'nonce' not in social.chat_view(room)[0]
    room['solo']=True
    assert not social.send_chat(room,'white','solo','2',2)['ok']

def test_chat_bounded_room_isolation_and_survives_rematch(room):
    for i in range(100):
        assert social.send_chat(room,'white',str(i),str(i),i*2)['ok']
    assert len(social.chat_view(room)) == social.CHAT_LIMIT
    other = server.new_room('OTHER')
    assert social.chat_view(other) == []
    finish(room,'W'); again(room)
    assert len(social.chat_view(room)) == 80

def test_http_chat_both_sides_spectator_privacy_and_series_gate(room):
    httpd=server.ThreadingServer(('127.0.0.1',0),server.Handler)
    thread=threading.Thread(target=httpd.serve_forever,daemon=True); thread.start()
    def req(path,body=None):
        with urlopen(Request(f'http://127.0.0.1:{httpd.server_port}'+path,
            data=json.dumps(body).encode() if body is not None else None,
            headers={'Content-Type':'application/json'})) as response: return json.load(response)
    try:
        for token in ('watch','unknown',None,[]):
            assert not req('/chat',dict(room='SOCIAL',token=token,text='hello',nonce='n'))['ok']
        assert req('/chat',dict(room='SOCIAL',token='white',text='hello',nonce='n'))['ok']
        assert req('/state?room=SOCIAL&token=black')['chat'][0]['text']=='hello'
        assert req('/state?room=SOCIAL&token=white')['chat'][0]['side']=='W'
        assert 'chat' not in req('/state?room=SOCIAL&token=watch')
        finish(room,'W'); again(room); finish(room,'W')
        assert not req('/action',dict(room='SOCIAL',token='black',type='rematch'))['ok']
    finally:
        httpd.shutdown(); httpd.server_close(); thread.join(2)
