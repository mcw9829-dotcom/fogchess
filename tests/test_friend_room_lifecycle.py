"""Friend entry/cancellation contracts over real HTTP and isolated accounts."""
import copy
import pytest
import accounts
import server
from test_security import http_world


def member(http, name):
    result = http('/signup', {'name': name, 'pw': 'FixturePass123!'})[2]
    assert result['ok']
    return result


@pytest.mark.parametrize('code', ['ZZZZ', ' zzzz ', 'EXPIRED'])
def test_missing_friend_code_never_creates_room(http_world, code):
    owner = member(http_world, 'Owner')
    result = http_world('/join', {'room': code, 'session': owner['session']})[2]
    assert result.get('ok') is False
    assert '방 코드' in result['msg']
    assert not server.ROOMS
    assert server.active_account_room(owner['user']['id']) is None


@pytest.mark.parametrize('color', ['W', 'B'])
@pytest.mark.parametrize('registered', [False, True])
def test_cancel_empty_friend_room_releases_owner_without_result(http_world, monkeypatch, color, registered):
    monkeypatch.setattr(server, 'draw_starting_color', lambda: color)
    owner = member(http_world, 'Owner') if registered else None
    auth = {'session': owner['session']} if owner else {'name': 'Guest'}
    first = http_world('/join', auth)[2]
    assert first['color'] == color
    result = http_world('/room/cancel', {'room': first['room'], 'token': first['token']})[2]
    assert result['ok']
    assert first['room'] not in server.ROOMS
    if owner:
        assert server.active_account_room(owner['user']['id']) is None
        assert accounts.game_history(owner['user']['id']) == []
        current = accounts.user_by_token(owner['session'])
        assert (current['rating'], current['wins'], current['losses']) == (1000, 0, 0)
    # A repeated cancellation is harmless, but old invitations cannot recreate it.
    assert http_world('/room/cancel', {'room': first['room'], 'token': first['token']})[2]['ok']
    assert http_world('/join', {'room': first['room'], 'token': first['token']})[2]['ok'] is False
    host = http_world('/join', {'name': 'Friend'})[2]
    joined = http_world('/join', dict(auth, room=host['room']))[2]
    assert joined['room'] == host['room'] and joined['color'] != host['color']
    reconnect = http_world('/join', dict(auth, room=host['room'], token=joined['token']))[2]
    assert reconnect['token'] == joined['token']


def test_cancel_releases_owner_for_rank_queue(http_world):
    owner = member(http_world, 'Owner')
    seat = http_world('/join', {'session': owner['session']})[2]
    assert http_world('/room/cancel', {'room': seat['room'], 'token': seat['token']})[2]['ok']
    queued = http_world('/match/join', {'session': owner['session']})[2]
    assert queued.get('ok') is not False and queued.get('state') == 'waiting'
    http_world('/match/cancel', {'session': owner['session']})


@pytest.mark.parametrize('token', ['', 'forged', server.BOT_TOKEN])
def test_cancel_rejects_non_owner_credentials(http_world, token):
    seat = http_world('/join', {})[2]
    before = copy.deepcopy(server.ROOMS[seat['room']])
    assert http_world('/room/cancel', {'room': seat['room'], 'token': token})[0] == 403
    assert server.ROOMS[seat['room']] == before


def test_spectator_cannot_cancel_host_room(http_world):
    host = http_world('/join', {})[2]
    watch = http_world('/watch/join', {'room': host['room']})[2]
    assert http_world('/room/cancel', {'room': host['room'], 'token': watch['token']})[0] == 403
    assert host['room'] in server.ROOMS


@pytest.mark.parametrize('mode', ['joined', 'play', 'over', 'match', 'bot', 'solo', 'queue_practice'])
def test_cancel_cannot_erase_committed_or_non_friend_room(http_world, mode):
    host = http_world('/join', {})[2]
    room = server.ROOMS[host['room']]
    if mode == 'joined':
        http_world('/join', {'room': host['room']})
    elif mode in ('play', 'over'):
        room['state']['phase'] = mode
    else:
        room[mode] = 'B' if mode == 'bot' else True
    before = copy.deepcopy(room)
    response = http_world('/room/cancel', {'room': host['room'], 'token': host['token']})
    assert response[0] == 409 and response[2]['ok'] is False
    assert server.ROOMS[host['room']] == before
    # In particular, a peer arriving after the leave dialog opened keeps both seats.
    if mode == 'joined':
        assert server.both_joined(room)
        assert http_world('/join', {'room': host['room'], 'token': host['token']})[2]['token'] == host['token']
