import pieces
from test_fogchess import clean_terrain, bare, put


def board():
    st=bare()
    put(st,'W_K1','W','K',11,11)
    put(st,'B_K1','B','K',0,0)
    return st


def test_knight_capture_and_private_history():
    st=board(); put(st,'W_N1','W','N',6,6);put(st,'B_P1','B','P',4,7)
    assert pieces.apply_move(st,'W','W_N1',4,7)[0]
    assert st['move_history']['W']==['1. Nxh5']
    assert st['notation'][-1]['from']==[6,6]
    assert st['notation'][-1]['compact']=='Nxh5'
    assert pieces.player_view(st,'B')['moveHistory']==[]


def test_pawn_and_scan_notation():
    st=board();put(st,'W_P1','W','P',6,5)
    assert pieces.apply_move(st,'W','W_P1',5,5)[0]
    assert st['move_history']['W']==['1. f6']
    st=board();put(st,'W_Q1','W','Q',6,4)
    assert pieces.apply_scan(st,'W','W_Q1',3,4)[0]
    assert st['move_history']['W']==['1. Q?e4']


def test_pawn_capture_origin_file_and_promotion():
    st=board();put(st,'W_P1','W','P',2,5);put(st,'B_P1','B','P',1,6)
    assert pieces.apply_move(st,'W','W_P1',1,6)[0]
    assert st['move_history']['W']==['1. fxg2']
    st=board();put(st,'W_P1','W','P',1,5)
    assert pieces.apply_move(st,'W','W_P1',0,5)[0]
    assert pieces.apply_promote(st,'W','R')[0]
    assert st['notation'][-1]['compact']=='f1=R'
