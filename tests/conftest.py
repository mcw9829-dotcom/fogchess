"""Keep automatic replay persistence inside each test's temporary directory."""
import pytest


@pytest.fixture(autouse=True)
def isolated_replay_database(monkeypatch, tmp_path):
    monkeypatch.setenv('FOG_REPLAY_DB', str(tmp_path / 'replays.sqlite3'))
    monkeypatch.setenv('FOG_SECURITY_DB', str(tmp_path / 'security.sqlite3'))
    monkeypatch.delenv('FOG_TRUSTED_PROXY_CIDRS', raising=False)
    monkeypatch.delenv('FOG_TRUST_FLY_PROXY', raising=False)
