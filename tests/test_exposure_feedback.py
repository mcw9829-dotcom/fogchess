"""Own-piece detection feedback must match the opponent's actual rendered sight."""
import pytest
import pieces
import server
import spectator
from test_fogchess import bare, put, clean_terrain, _set_terrain


def exposed(st, side, reveal=False):
    return {item['pid'] for item in pieces.player_view(st, side, reveal)['exposed']}


@pytest.mark.parametrize('side,enemy', [('W', 'B'), ('B', 'W')])
@pytest.mark.parametrize('kind', list('PNBRQK'))
def test_all_types_follow_real_opponent_sight(side, enemy, kind):
    st = bare()
    pid = side+'_'+kind+'1'
    put(st, pid, side, kind, 5, 5)
    observer = put(st, enemy+'_N1', enemy, 'N', 5, 7)
    assert exposed(st, side) == {pid}
    assert pieces.player_view(st, enemy)['grid'][5][5]['p']['t'] == kind
    observer['c'] = 8
    assert exposed(st, side) == set()
    assert pieces.player_view(st, enemy)['grid'][5][5]['p'] is None
    # Debug full-board display must not fake opponent visibility.
    assert exposed(st, side, reveal=True) == set()
    observer['c'] = 7
    observer['alive'] = False
    assert exposed(st, side) == set()


def test_unseen_observer_only_discloses_own_warning():
    st = bare()
    put(st, 'W_P1', 'W', 'P', 5, 5)
    put(st, 'B_N1', 'B', 'N', 5, 7)
    view = pieces.player_view(st, 'W')
    assert view['grid'][5][7]['p'] is None
    assert view['exposed'] == [{'pid':'W_P1', 'type':'P', 'remaining':0}]


def test_forest_occlusion_hides_alert():
    st = bare()
    put(st, 'W_R1', 'W', 'R', 5, 5)
    put(st, 'B_K1', 'B', 'K', 5, 8)
    assert exposed(st, 'W') == {'W_R1'}
    _set_terrain(forests={(5, 6)})
    assert exposed(st, 'W') == set()


def test_bush_sharing_scan_and_shot_expiry():
    _set_terrain(bushes={(4, c) for c in range(4, 9)})
    st = bare()
    put(st, 'W_B1', 'W', 'B', 4, 4)
    observer = put(st, 'B_P1', 'B', 'P', 4, 3)
    assert exposed(st, 'W') == set()  # Adjacent is not enough outside the bush.
    observer['c'] = 8
    assert exposed(st, 'W') == {'W_B1'}  # Connected bush exceeds ordinary vision.
    observer.update(r=3, c=8)
    assert exposed(st, 'W') == set()
    st['scans'] = [{'viewer':'B', 'cells':[(4,4)], 'until':2}]
    assert exposed(st, 'W') == {'W_B1'}
    st['turnCount'] = 2
    assert exposed(st, 'W') == set()
    pieces.add_reveal(st, 'W_B1', 'B', 2)
    assert exposed(st, 'W') == {'W_B1'}
    st['turnCount'] = 4
    assert exposed(st, 'W') == set()
    observer.update(r=4, c=8)
    view = pieces.player_view(st, 'W')
    assert view['exposed'][0]['remaining'] == 0
    assert exposed(st, 'W') == {'W_B1'}  # Shot expires, but real sight continues.
    st['pieces']['W_B1']['alive'] = False
    assert exposed(st, 'W') == set()


def test_setup_and_spectator_have_no_private_alerts():
    st = bare()
    put(st, 'W_P1', 'W', 'P', 5, 5)
    put(st, 'B_N1', 'B', 'N', 5, 7)
    assert pieces.player_view(st, 'spectator')['exposed'] == []
    st['phase'] = 'setup'
    assert exposed(st, 'W') == set()


def test_replay_records_alert_at_each_perspective_and_ply():
    room = server.new_room('EXPOSE')
    room['terrain'] = dict(seed=0, forests=set(), rivers=set(), bushes=set(), impassable=set())
    st = room['state'] = bare()
    put(st, 'W_P1', 'W', 'P', 5, 5)
    put(st, 'B_N1', 'B', 'N', 5, 7)
    spectator.capture(room, 1000)
    assert pieces.apply_move(st, 'B', 'B_N1', 3, 8)[0]
    spectator.capture(room, 1001)
    frames = room['_replay']['data']['frames']
    assert frames[0]['perspectives']['W']['exposed'][0]['pid'] == 'W_P1'
    assert frames[1]['perspectives']['W']['exposed'] == []
    assert all(frame['view']['exposed'] == [] for frame in frames)
