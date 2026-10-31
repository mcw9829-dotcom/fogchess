"""Queen scan candidates and authoritative actions must use the same circular radius."""
import copy
import pytest
import pieces
from config import SCAN_RANGE, N

def position(origin):
    state = pieces.new_game()
    for piece in state['pieces'].values():
        piece['alive'] = False
    state['phase'] = 'play'
    state['turn'] = 'W'
    state['pieces']['W_Q1'].update(alive=True, r=origin[0], c=origin[1])
    return state

@pytest.mark.parametrize('origin', [(0, 0), (5, 5), (11, 11)])
def test_candidates_and_actions_match_circle_at_every_board_cell(origin):
    original = position(origin)
    candidates = set(map(tuple, pieces.scan_cells(original, 'W_Q1')))
    expected = {(r, c) for r in range(N) for c in range(N)
                if (r-origin[0])**2 + (c-origin[1])**2 <= SCAN_RANGE**2}
    assert candidates == expected
    for r in range(N):
        for c in range(N):
            state = copy.deepcopy(original)
            ok, _ = pieces.apply_scan(state, 'W', 'W_Q1', r, c)
            assert ok == ((r, c) in expected), (origin, r, c)
            if ok:
                assert set(map(tuple, state['scans'][-1]['cells'])) == {
                    (ar, ac) for ar in (r, r+1) for ac in (c, c+1) if ar < N and ac < N}
                assert state['turnCount'] == original['turnCount'] + 1
            else:
                assert state == original, 'Invalid scan must not consume a turn or change fog'

def test_new_diagonal_and_radius_boundary():
    candidates = set(map(tuple, pieces.scan_cells(position((1, 1)), 'W_Q1')))
    assert (5, 5) in candidates   # sqrt(4²+4²) < 6; previously excluded by Manhattan distance.
    assert (7, 1) in candidates   # Exact axial radius.
    assert (7, 2) not in candidates
    assert (6, 5) not in candidates
