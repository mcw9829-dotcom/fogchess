"""Fairness regressions using isolated boards; no live server or user database."""
import copy
import random
import pytest
import bot
import pieces
import game_map
from test_fogchess import clean_terrain, bare, put, _set_terrain


@pytest.mark.parametrize('kind,key,start,target', [
    ('B','W_B1',(6,6),(4,4)),
    ('R','W_R1',(6,5),(4,5)),
    ('Q','W_Q1',(6,6),(4,4)),
    ('P','W_P1',(6,5),(4,5)),
])
def test_hidden_occupancy_does_not_change_candidates(kind,key,start,target):
    hidden = (5,5)
    _set_terrain(bushes={hidden})
    a = bare()
    put(a,key,'W',kind,*start,moved=False)
    b = copy.deepcopy(a)
    put(b,'B_N1','B','N',*hidden)
    assert pieces.player_view(a,'W')['grid'] == pieces.player_view(b,'W')['grid']
    assert pieces.move_candidates(a,key) == pieces.move_candidates(b,key)
    assert target in pieces.move_candidates(b,key)
    ok,_ = pieces.apply_move(b,'W',key,*target)
    assert ok and (b['pieces'][key]['r'],b['pieces'][key]['c']) == hidden
    assert not b['pieces']['B_N1']['alive'] and b['turnCount']==1
    assert b['captured']['W']==['N']


@pytest.mark.parametrize('fn', [pieces.apply_move,pieces.apply_fire,pieces.apply_barrage,pieces.apply_scan])
def test_promotion_blocks_all_other_actions(fn):
    st=bare()
    put(st,'W_P1','W','P',1,3)
    put(st,'W_K1','W','K',9,8)
    assert pieces.apply_move(st,'W','W_P1',0,3)[0]
    before=copy.deepcopy(st)
    assert not fn(st,'W','W_K1',8,8)[0]
    assert st==before


def test_promotion_timeout_resolves_once_without_extra_move():
    st=bare()
    put(st,'W_P1','W','P',1,3)
    assert pieces.apply_move(st,'W','W_P1',0,3)[0]
    assert pieces.time_out(st)
    assert st['turn']=='B' and st['turnCount']==1 and st['promote'] is None
    assert st['pieces']['W_P1']['t']=='R'
    assert not pieces.apply_promote(st,'W','N')[0]
    assert st['turnCount']==1


def test_prediction_and_search_independent_of_hidden_king(monkeypatch):
    _set_terrain(bushes={(4,4),(4,8)})
    a=bare()
    put(a,'W_K1','W','K',10,8)
    put(a,'W_B1','W','B',6,6)
    put(a,'B_K1','B','K',4,4)
    b=copy.deepcopy(a)
    b['pieces']['B_K1'].update(r=4,c=8)
    assert pieces.player_view(a,'W')['grid']==pieces.player_view(b,'W')['grid']
    assert pieces.observed_state(a,'W')['pieces']==pieces.observed_state(b,'W')['pieces']
    assert 'B_K1' not in pieces.observed_state(a,'W')['pieces']
    monkeypatch.setattr(bot,'MINIMAX_MAX_DEPTH',1)
    assert bot._best_minimax_move(a,'W',1)==bot._best_minimax_move(b,'W',1)
    for choose in (bot.choose_action_easy,bot.choose_action,bot.choose_action_hard):
        random.seed(81)
        first=choose(copy.deepcopy(a),'W',budget=.2)
        random.seed(81)
        second=choose(copy.deepcopy(b),'W',budget=.2)
        assert first==second


def test_history_does_not_disclose_opponent_move():
    st=bare()
    put(st,'W_N1','W','N',9,3)
    put(st,'B_K1','B','K',0,10)
    assert pieces.apply_move(st,'W','W_N1',7,4)[0]
    assert pieces.player_view(st,'W')['moveHistory']
    assert pieces.player_view(st,'B')['moveHistory']==[]
    assert 'notation' not in pieces.player_view(st,'B')


def test_friendly_fire_is_not_an_enemy_trophy():
    st=bare()
    put(st,'W_R1','W','R',6,6)
    put(st,'W_P1','W','P',6,7)
    put(st,'B_N1','B','N',6,8)
    assert pieces.apply_barrage(st,'W','W_R1',6,9)[0]
    assert pieces.player_view(st,'W')['captured']==['N']
    assert len(st['feed'])==2


def test_rotational_rank_terrain():
    for seed in range(50):
        for extra in ('bush','river','both'):
            terrain=game_map.generate_terrain(seed,extra=extra,symmetry='rotational')
            for key in ('forests','rivers','bushes','impassable'):
                assert terrain[key]=={(11-r,11-c) for r,c in terrain[key]}
            assert not terrain['bushes'] & terrain['impassable']


def test_random_setup_avoids_rivers():
    _set_terrain(rivers={(9,3),(10,4),(11,5)})
    for _ in range(10):
        st=pieces.new_game()
        assert pieces.autoplace(st,'W','random')[0]
        assert all((p['r'],p['c']) not in pieces.IMPASSABLE
                   for p in st['pieces'].values() if p['o']=='W')


def test_http_candidates_and_promotion_guard(monkeypatch):
    import server
    import json
    import threading
    from urllib.request import urlopen, Request
    # No account calls, persistent DB or live QA room touched.
    monkeypatch.setattr(server,'ROOMS',{})
    room=server.new_room('QAISOLATED')
    room['terrain']={'seed':0,'forests':set(),'rivers':set(),'bushes':{(5,5)},'impassable':set()}
    room['seats']={'W':'white','B':'black'}
    room['tokens']={'white':'W','black':'B'}
    st=bare()
    put(st,'W_B1','W','B',6,6)
    put(st,'W_K1','W','K',10,8)
    put(st,'B_N1','B','N',5,5)
    put(st,'B_K1','B','K',0,9)
    room['state']=st
    server.ROOMS['QAISOLATED']=room
    handler=server.Handler
    httpd=server.ThreadingServer(('127.0.0.1',0),handler)
    thread=threading.Thread(target=httpd.serve_forever,daemon=True)
    thread.start()
    base=f'http://127.0.0.1:{httpd.server_port}'
    def request(path,body=None):
        data=None if body is None else json.dumps(body).encode()
        with urlopen(Request(base+path,data=data,headers={'Content-Type':'application/json'})) as response:
            return json.load(response)
    try:
        response=request('/moves?room=QAISOLATED&token=white&pid=W_B1')
        assert [4,4] in response['moves']
        response=request('/action',{'room':'QAISOLATED','token':'white','type':'move','pid':'W_B1','r':4,'c':4})
        assert response['ok'] and response['fx']['cells']==[[5,5]]
        st['turn']='W'
        st['promote']={'pid':'W_P1','color':'W'}
        put(st,'W_P1','W','P',0,3)
        result=request('/action',{'room':'QAISOLATED','token':'white','type':'move','pid':'W_K1','r':9,'c':8})
        assert not result['ok']
        assert request('/moves?room=QAISOLATED&token=white&pid=W_B1')['moves']==[]
        assert request('/action',{'room':'QAISOLATED','token':'white','type':'promote','choice':'N'})['ok']
    finally:
        httpd.shutdown()
        httpd.server_close()
        thread.join(timeout=2)


def test_rank_room_and_rematch_are_symmetric(monkeypatch):
    import server
    monkeypatch.setattr(server,'ROOMS',{})
    monkeypatch.setattr(server,'NEW_MAP_ON_REMATCH',True)
    code,*_=server.make_match_room({'uid':1,'rating':1000,'name':'A'},
                                  {'uid':2,'rating':1000,'name':'B'})
    room=server.ROOMS[code]
    for _ in range(3):
        for key in ('forests','bushes','rivers'):
            cells=room['terrain'][key]
            assert cells=={(11-r,11-c) for r,c in cells}
        server.start_rematch(room)
