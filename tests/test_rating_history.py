"""Last-ten result chart data; isolated DB, no production accounts."""
import accounts
import pytest


@pytest.fixture
def db(tmp_path, monkeypatch):
    monkeypatch.setattr(accounts, 'DB_PATH', str(tmp_path / 'ratings.db'))
    monkeypatch.setattr(accounts, '_ready', False)
    accounts.init_db()
    with accounts._db() as c:
        for uid in (1, 2):
            c.execute("INSERT INTO users(id,name,name_lc,salt,pw_hash,rating,created) VALUES(?,?,?,X'00',X'00',1000,0)", (uid, str(uid), str(uid)))


def add(uid=1, rated=True, delta=16, after=1016, room='test'):
    accounts.add_game(uid, 'match' if rated else 'lobby', 'win', 'king', 'opponent', None, 1000, rated, delta, after, room)


def test_empty_and_single_zero_delta(db):
    assert accounts.rating_history(1) == []
    add(delta=0, after=1000)
    rows = accounts.rating_history(1)
    assert len(rows) == 1 and rows[0]['delta'] == 0 and rows[0]['rating_after'] == 1000


def test_ten_rated_games_even_after_many_unrated_games(db):
    for i in range(12): add(room=str(i), after=1000+i)
    for _ in range(25): add(rated=False, delta=None, after=None)
    rows = accounts.rating_history(1)
    assert [r['room'] for r in rows] == [str(i) for i in range(11, 1, -1)]
    assert len(accounts.game_history(1)) == 20  # Existing profile contract stays intact.


def test_owner_scope_and_unsettled_rows(db):
    add(uid=1, room='mine')
    add(uid=2, room='private-other')
    add(uid=1, after=None, delta=None, room='no-rating')
    assert [r['room'] for r in accounts.rating_history(1)] == ['mine']
    assert [r['room'] for r in accounts.rating_history(2)] == ['private-other']
