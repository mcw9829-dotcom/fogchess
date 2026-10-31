"""Forest coverage must be symmetric and identical for UI targets and actions."""
import copy
import pytest
import game_map
import pieces
from test_fogchess import bare,put,clean_terrain,_set_terrain


@pytest.mark.parametrize('origin,target,forest', [
    ((5,5),(3,4),(4,4)), # Previous rounding skipped one side of a half-cell crossing.
    ((5,5),(4,3),(4,4)),
    ((5,5),(4,4),(5,4)), # Adjacent diagonal cannot look through a forest corner.
    ((5,5),(3,3),(4,5)),
    ((5,5),(5,7),(5,6)),
])
def test_forest_crossed_or_touched_by_ray_blocks_both_directions(origin,target,forest):
    _set_terrain(forests={forest})
    assert not game_map.los_clear(*origin,*target)
    assert not game_map.los_clear(*target,*origin)
    st=bare();put(st,'W_K1','W','K',*origin);put(st,'B_R1','B','R',*target)
    assert target not in pieces.visible_cells(st,'W')
    assert pieces.player_view(st,'W')['grid'][target[0]][target[1]]['p'] is None
    assert not pieces.enemy_visible_at(st,'W',*target)


def test_forest_endpoint_is_visible_but_not_cells_beyond():
    _set_terrain(forests={(5,6)})
    assert game_map.los_clear(5,5,5,6)
    assert not game_map.los_clear(5,5,5,7)
    assert game_map.los_clear(5,5,3,5)


def test_visibility_is_reciprocal_for_all_slopes():
    _set_terrain(forests={(3,3),(3,4),(5,7),(7,4)})
    for r in range(12):
        for c in range(12):
            assert game_map.los_clear(5,5,r,c)==game_map.los_clear(r,c,5,5)


def test_shared_vision_does_not_allow_bishop_to_shoot_through_forest():
    _set_terrain(forests={(5,6)})
    st=bare();put(st,'W_B1','W','B',5,5);put(st,'W_N1','W','N',4,8);put(st,'B_R1','B','R',5,8)
    assert pieces.enemy_visible_at(st,'W',5,8) # Legitimate allied scout vision remains.
    assert (5,8) not in pieces.fire_cells(st,'W_B1')
    before=copy.deepcopy(st)
    assert not pieces.apply_fire(st,'W','W_B1',5,8)[0]
    assert st==before
    _set_terrain()
    assert (5,8) in pieces.fire_cells(st,'W_B1')
    assert pieces.apply_fire(st,'W','W_B1',5,8)[0]


def test_bishop_alone_cannot_see_two_rows_away_without_reveal():
    # Relative spacing visible in the report: bishop left, enemy rook two rows above.
    _set_terrain(forests={(6,0),(6,1),(8,3),(9,3)})
    st=bare();put(st,'W_B1','W','B',8,1);put(st,'B_R1','B','R',6,2)
    assert pieces.player_view(st,'W')['grid'][6][2]['p'] is None
    assert (6,2) not in pieces.fire_cells(st,'W_B1')
    # Existing muzzle-flash rule is explicit, temporary visibility, not natural vision.
    pieces.add_reveal(st,'B_R1','W',1)
    assert pieces.player_view(st,'W')['grid'][6][2]['p']
    st['turnCount']+=1
    assert pieces.player_view(st,'W')['grid'][6][2]['p'] is None
