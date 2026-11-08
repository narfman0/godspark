## The character sheet's numbers: the host's SheetSummary (RulesClient.summary: abilities,
## saves, skills, AC and its parts, attacks, features, resistances, proficiencies, speed),
## plus movement lines from the own MoveStats (the sparks' mirror, identical to the host's).
## Nothing here is worked out on the client.
class_name SheetModel
extends RefCounted

## summary: RulesClient.summary ({} until the host sends it); stats: the own MoveStats.
static func build(summary: Dictionary, stats: MoveStats) -> Dictionary:
	if summary.is_empty():
		return {}
	var out := summary.duplicate(true)
	out["move"] = move_lines(stats)
	return out

## Movement as changed by sparks, in plain numbers.
static func move_lines(s: MoveStats) -> Array:
	if s == null:
		return []
	var out: Array = ["Run %.1f tiles/s" % s.run_speed, "Jump %.1f tiles/s up" % s.jump_velocity]
	if s.air_jumps > 0:
		out.append("%d air jump%s" % [s.air_jumps, "" if s.air_jumps == 1 else "s"])
	if s.dash_speed > 0.0:
		out.append("Dash %.0f tiles/s, every %.1f s" % [s.dash_speed, s.dash_cooldown])
	if s.glide_fall > 0.0:
		out.append("Glide at %.0f tiles/s" % s.glide_fall)
	if s.climb_speed > 0.0:
		out.append("Climb walls %.1f tiles/s" % s.climb_speed)
	out.append("Swim %.1f tiles/s" % s.swim_speed)
	return out
