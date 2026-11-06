## The hit-stop: how long a contact holds the attacker's and the victim's swing clocks, on the
## attacker's client only. View time: nothing here reaches the client's body, the input or the
## host, so no simulation tick moves (tests/test_swings.gd keeps that true).
class_name HitStop
extends RefCounted

## Seconds for this event on this client: 0 unless the own player landed it.
static func seconds(kind: int, src: int, my_id: int) -> float:
	if src == 0 or src != my_id:
		return 0.0
	var f := CombatTempo.section("feel")
	match kind:
		CombatCodec.Ev.HIT:
			return float(f.get("hit_stop_s", 0.06))
		CombatCodec.Ev.CRIT:
			return float(f.get("crit_stop_s", 0.1))
	return 0.0
