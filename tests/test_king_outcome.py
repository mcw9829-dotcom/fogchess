"""Friendly fire preserves victim-based game outcome; isolated boards only."""
import pytest
import pieces
from test_fogchess import bare, put, _set_terrain, clean_terrain

@pytest.mark.parametrize("actor", ["W", "B"])
@pytest.mark.parametrize("friendly", [True, False])
def test_barrage_king_owner_loses(actor, friendly):
    _set_terrain()
    other = "B" if actor == "W" else "W"
    victim = actor if friendly else other
    survivor = other if friendly else actor
    state = bare()
    state["turn"] = actor
    put(state, actor+"_R1", actor, "R", 6, 6)
    put(state, victim+"_K1", victim, "K", 6, 7)
    put(state, survivor+"_K1", survivor, "K", 0, 0)
    assert pieces.apply_barrage(state, actor, actor+"_R1", 6, 9)[0]
    assert state["phase"] == "over" and state["winner"] == survivor
    assert state["turn_deadline"] is None
    assert state["pieces"][survivor+"_K1"]["alive"]
    assert not state["pieces"][victim+"_K1"]["alive"]

@pytest.mark.parametrize("first", ["W", "B"])
def test_barrage_stops_at_first_king(first):
    _set_terrain()
    second = "B" if first == "W" else "W"
    state = bare()
    put(state, "W_R1", "W", "R", 6, 6)
    put(state, first+"_K1", first, "K", 6, 7)
    put(state, second+"_K1", second, "K", 6, 8)
    assert pieces.apply_barrage(state, "W", "W_R1", 6, 9)[0]
    assert state["winner"] == second
    assert state["pieces"][second+"_K1"]["alive"]
