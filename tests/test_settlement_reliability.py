"""Settlement failures use a temporary database and never a running server."""
import sqlite3
import pytest
import accounts
import server

@pytest.fixture
def room(tmp_path, monkeypatch):
    monkeypatch.setattr(accounts, 'DB_PATH', str(tmp_path / 'accounts.db'))
    monkeypatch.setattr(accounts, '_ready', False)
    accounts.init_db()
    with accounts._db() as c:
        for uid in (1, 2):
            c.execute("INSERT INTO users(id,name,name_lc,salt,pw_hash,rating,created) VALUES(?,?,?,X'00',X'00',1000,0)", (uid, str(uid), str(uid)))
    r = server.new_room('QA00')
    r.update(match=True, users={'W':1,'B':2}, names={'W':'one','B':'two'}, ratings={'W':1000,'B':1000})
    r['state'].update(phase='over', winner='W')
    return r

def counts():
    with accounts._db() as c:
        return ([tuple(x) for x in c.execute('SELECT rating,wins,losses FROM users ORDER BY id')],
                c.execute('SELECT count(*) FROM games').fetchone()[0],
                c.execute('SELECT count(*) FROM game_settlements').fetchone()[0])

def test_history_failure_rolls_back_both_ratings_then_retries(room):
    with accounts._db() as c:
        c.execute("CREATE TRIGGER fail_history BEFORE INSERT ON games WHEN NEW.user_id=2 BEGIN SELECT RAISE(ABORT, 'injected'); END")
    assert not server.settle_rating(room)
    assert not room['rated_done']
    assert counts() == ([(1000,0,0),(1000,0,0)],0,0)
    with accounts._db() as c: c.execute('DROP TRIGGER fail_history')
    assert server.settle_rating(room)
    assert counts() == ([(1016,1,0),(984,0,1)],2,1)

def test_commit_ack_loss_is_idempotent(room, monkeypatch):
    real = accounts.settle_game
    def lost_ack(*args):
        real(*args)
        raise OSError('ack lost after commit')
    monkeypatch.setattr(accounts,'settle_game',lost_ack)
    assert not server.settle_rating(room)
    monkeypatch.setattr(accounts,'settle_game',real)
    assert server.settle_rating(room)
    assert counts() == ([(1016,1,0),(984,0,1)],2,1)
    # A reconstructed memory flag must still receive the persisted receipt.
    room['rated_done']=False
    assert server.settle_rating(room)
    assert counts()[1:] == (2,1)

def test_failed_settlement_blocks_rematch_and_survives_cleanup(room, monkeypatch):
    def fail(*args): raise sqlite3.OperationalError('database locked')
    monkeypatch.setattr(accounts,'settle_game',fail)
    state=room['state']
    assert server.start_rematch(room) is False
    assert room['state'] is state
    monkeypatch.setattr(server,'ROOMS',{'QA00':room})
    monkeypatch.setattr(server,'_last_gc',0,raising=False)
    room['created']=0
    server.gc_rooms(100000)
    assert server.ROOMS['QA00'] is room

def test_nonrated_history_and_additive_schema(room):
    room['match']=False
    assert server.settle_rating(room)
    assert counts() == ([(1000,0,0),(1000,0,0)],2,1)
    accounts.init_db(accounts.DB_PATH)
    assert counts() == ([(1000,0,0),(1000,0,0)],2,1)

def test_bot_settlement_and_sweeper_retry(room, monkeypatch):
    room.update(bot='B',users={'W':1},botlevel='easy',match=False)
    monkeypatch.setattr(server,'ROOMS',{'QA00':room})
    server._sweep_rooms(100000)
    assert room['rated_done']
    assert counts()[1:] == (1,1)
    assert counts()[0][0][1] == 1

def test_rematch_has_new_receipt_and_same_game_retry_does_not_count_twice(room, monkeypatch):
    monkeypatch.setattr(server.spectator, 'capture', lambda room: None)
    assert server.settle_rating(room)
    first = room['state']['_settlement_id']
    assert server.start_rematch(room)
    room['state'].update(phase='over', winner='B')
    assert server.settle_rating(room)
    assert room['state']['_settlement_id'] != first
    assert counts()[1:] == (4,2)

def test_existing_users_and_history_survive_additive_upgrade(room):
    with accounts._db() as c:
        c.execute("INSERT INTO games(created,user_id,kind,result,room) VALUES(0,1,'lobby','win','OLD')")
        c.execute('DROP TABLE game_settlements')
    accounts.init_db(accounts.DB_PATH)
    assert counts() == ([(1000,0,0),(1000,0,0)],1,0)
    assert server.settle_rating(room)
    assert counts()[1:] == (3,1)

def test_participant_view_pending_until_database_recovers(room, monkeypatch):
    monkeypatch.setattr(server.spectator, 'capture', lambda room, *args: None)
    real = accounts.settle_game
    def fail(*args): raise sqlite3.OperationalError('database locked')
    monkeypatch.setattr(accounts, 'settle_game', fail)
    assert server.state_response(room, 'W', 100)['settlementPending'] is True
    assert server.state_response(room, 'B', 100)['settlementPending'] is True
    monkeypatch.setattr(accounts, 'settle_game', real)
    assert server.state_response(room, 'W', 101)['settlementPending'] is False
    assert server.state_response(room, 'B', 101)['settlementPending'] is False
    assert counts()[1:] == (2,1)
