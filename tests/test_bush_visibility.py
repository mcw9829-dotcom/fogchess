"""Connected-bush visibility through real moves, without live rooms or databases."""
import pytest
import pieces
from test_fogchess import clean_terrain, bare, put, _set_terrain

@pytest.mark.parametrize('side,enemy', [('W','B'),('B','W')])
def test_enter_leave_connected_bush(side,enemy):
    _set_terrain(bushes={(4,c) for c in range(4,9)} | {(3,9)})
    st=bare()
    st['turn']=side
    put(st,side+'_K1',side,'K',11,11)
    put(st,enemy+'_K1',enemy,'K',0,0)
    put(st,side+'_N1',side,'N',6,3)
    put(st,enemy+'_P1',enemy,'P',4,8)
    put(st,enemy+'_P2',enemy,'P',3,9)
    assert pieces.player_view(st,side)['grid'][4][8]['p'] is None
    assert pieces.apply_move(st,side,side+'_N1',4,4)[0]
    view=pieces.player_view(st,side)
    assert view['grid'][4][8]['p']['o']==enemy
    assert view['grid'][3][9]['p'] is None # Diagonal-only bush is a separate cluster.
    assert pieces.player_view(st,enemy)['grid'][4][4]['p']['o']==side
    assert pieces.apply_move(st,enemy,enemy+'_K1',0,1)[0]
    assert pieces.apply_move(st,side,side+'_N1',6,3)[0]
    assert pieces.player_view(st,side)['grid'][4][8]['p'] is None
    put(st,side+'_P1',side,'P',4,5)
    assert pieces.player_view(st,side)['grid'][4][8]['p']['o']==enemy
    st['pieces'][side+'_P1']['alive']=False
    assert pieces.player_view(st,side)['grid'][4][8]['p'] is None
