"""Forward capture is one square, consistent across visibility and both sides."""
import copy
import pytest
import pieces
import bot
from test_fogchess import clean_terrain, bare, put, _set_terrain


@pytest.mark.parametrize('side,opponent,start,forward', [('W','B',6,-1),('B','W',5,1)])
@pytest.mark.parametrize('hidden', [False, True])
@pytest.mark.parametrize('moved', [False, True])
def test_forward_capture(side, opponent, start, forward, hidden, moved):
    target = (start+forward,5)
    _set_terrain(bushes={target} if hidden else set())
    st = bare(); st['turn']=side
    pawn = put(st,side+'_P1',side,'P',start,5,moved=moved)
    enemy = put(st,opponent+'_N1',opponent,'N',*target)
    assert target in pieces.legal_moves(st,pawn['id'])
    assert target in pieces.move_candidates(st,pawn['id'])
    assert bool(pieces.enemy_visible_at(st,side,*target)) != hidden
    assert pieces.apply_move(st,side,pawn['id'],*target)[0]
    assert (pawn['r'],pawn['c']) == target and not enemy['alive']
    assert st['turnCount']==1 and st['captured'][side]==['N']
    assert st['fx']['type']=='capture'


@pytest.mark.parametrize('side,opponent,start,forward', [('W','B',6,-1),('B','W',5,1)])
@pytest.mark.parametrize('distance', [1,2])
def test_hidden_enemy_does_not_leak_through_hints_or_grant_two_square_attack(side,opponent,start,forward,distance):
    target=(start+distance*forward,5)
    _set_terrain(bushes={target})
    clear=bare();clear['turn']=side
    pawn=put(clear,side+'_P1',side,'P',start,5,moved=False)
    occupied=copy.deepcopy(clear)
    enemy=put(occupied,opponent+'_N1',opponent,'N',*target)
    assert pieces.player_view(clear,side)['grid']==pieces.player_view(occupied,side)['grid']
    assert pieces.move_candidates(clear,pawn['id'])==pieces.move_candidates(occupied,pawn['id'])
    assert pieces.apply_move(occupied,side,pawn['id'],start+2*forward,5)[0]
    assert (occupied['pieces'][pawn['id']]['r'],occupied['pieces'][pawn['id']]['c'])==(start+forward,5)
    assert enemy['alive']==(distance==2)
    assert occupied['turnCount']==1


@pytest.mark.parametrize('side,opponent,start,forward', [('W','B',6,-1),('B','W',5,1)])
def test_two_square_visible_enemy_is_not_capturable(side,opponent,start,forward):
    st=bare();st['turn']=side
    pawn=put(st,side+'_P1',side,'P',start,5,moved=False)
    put(st,side+'_N1',side,'N',start+2*forward,7) # Observe the target without blocking travel.
    put(st,opponent+'_N1',opponent,'N',start+2*forward,5)
    before=copy.deepcopy(st)
    assert not pieces.apply_move(st,side,pawn['id'],start+2*forward,5)[0]
    assert st==before


@pytest.mark.parametrize('blocker', ['ally','forest','river'])
def test_forward_capture_respects_blockers(blocker):
    st=bare();put(st,'W_P1','W','P',6,5,moved=False)
    if blocker=='ally': put(st,'W_N1','W','N',5,5)
    elif blocker=='forest': _set_terrain(forests={(5,5)})
    else: _set_terrain(rivers={(5,5)})
    before=copy.deepcopy(st)
    assert (5,5) not in pieces.move_candidates(st,'W_P1')
    assert not pieces.apply_move(st,'W','W_P1',5,5)[0]
    assert not pieces.apply_move(st,'W','W_P1',4,5)[0]
    assert st==before


@pytest.mark.parametrize('target', [(5,4),(5,6),(6,4),(6,6)])
def test_existing_diagonal_and_sideways_captures_remain(target):
    st=bare();put(st,'W_P1','W','P',6,5)
    enemy=put(st,'B_N1','B','N',*target)
    assert pieces.apply_move(st,'W','W_P1',*target)[0] and not enemy['alive']


def test_forward_capture_can_promote_or_end_game():
    st=bare();put(st,'W_P1','W','P',1,5);put(st,'B_N1','B','N',0,5)
    assert pieces.apply_move(st,'W','W_P1',0,5)[0]
    assert st['promote']['pid']=='W_P1' and st['turnCount']==0
    st=bare();put(st,'W_P1','W','P',6,5);put(st,'B_K1','B','K',5,5)
    assert pieces.apply_move(st,'W','W_P1',5,5)[0]
    assert st['phase']=='over' and st['winner']=='W'


@pytest.mark.parametrize('me,forward', [('W',1),('B',-1)])
def test_bot_accounts_for_forward_pawn_threat(me,forward):
    danger=bot._threat_cells([(5,5,'P')],me)
    assert (5+forward,5) in danger
    assert (5+2*forward,5) not in danger
