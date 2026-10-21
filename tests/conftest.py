"""Keep automatic replay persistence inside each test's temporary directory."""
import pytest


@pytest.fixture(autouse=True)
def isolated_replay_database(monkeypatch, tmp_path):
    monkeypatch.setenv('FOG_REPLAY_DB', str(tmp_path / 'replays.sqlite3'))
