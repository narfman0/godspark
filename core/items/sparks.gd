## Sparks (data/sparks.json): what each does at each rank, and applying a kindled list to a
## MoveStats and to a tags Dictionary. THE RULE: a spark never touches the combatant, so it
## cannot change an attack roll, AC, save DC or damage die (tests/test_sparks.gd).
##
## Host and client run the same code on the same inputs (the base speeds and the kindled
## list the host mirrors to the owner), so the client's own movement and the host's checks
## agree: Sparks.move_stats(speeds, size, kindled).
##
##   var out := {}
##   Sparks.apply([{"id": "fleet", "rank": 1}], stats, out)    # stats.run_speed * 1.2
class_name Sparks
extends RefCounted

const PATH := "res://data/sparks.json"
const RANKS := 3

static var _data := {}

static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _data

static func ids() -> Array:
	return (data()["sparks"] as Dictionary).keys()

static func exists(id: String) -> bool:
	return (data()["sparks"] as Dictionary).has(id)

static func row(id: String) -> Dictionary:
	return data()["sparks"].get(id, {})

static func spark_name(id: String) -> String:
	return String(row(id).get("name", id.capitalize()))

static func rank_name(rank: int) -> String:
	var names: Array = data().get("rank_names", ["I", "II", "III"])
	return String(names[clampi(rank, 0, names.size() - 1)])

## The rank row {move?, tags?} of a spark (rank 0-2).
static func effect(id: String, rank: int) -> Dictionary:
	var ranks: Array = row(id).get("ranks", [])
	return ranks[clampi(rank, 0, ranks.size() - 1)] if not ranks.is_empty() else {}

## Rank weights [I, II, III] for a worldgen band name.
static func depth_weights(band: String) -> Array:
	var d: Dictionary = data().get("depth", {})
	return d.get(band, d.get("surface", [1, 0, 0]))

## Apply kindled sparks ([{id, rank}]) in order: movement ones change `stats` (additive
## abilities default off, so an empty list leaves it untouched), the rest add tags to `out`.
static func apply(kindled: Array, stats: MoveStats, out: Dictionary) -> void:
	for k: Variant in kindled:
		if not k is Dictionary:
			continue
		var eff := effect(String(k.get("id", "")), int(k.get("rank", 0)))
		var mv: Dictionary = eff.get("move", {})
		if stats != null and not mv.is_empty():
			_move(stats, mv)
		for t: String in eff.get("tags", {}):
			out[t] = float(out.get(t, 0.0)) + float(eff["tags"][t])

static func _move(s: MoveStats, mv: Dictionary) -> void:
	if mv.has("run_mult"):
		s.run_speed *= float(mv["run_mult"])
	if mv.has("jump_add"):
		# Same gravity, higher apex: v = sqrt(v0^2 + 2 g dh).
		s.jump_velocity = sqrt(s.jump_velocity * s.jump_velocity + 2.0 * s.gravity * float(mv["jump_add"]))
	if mv.has("air_jumps"):
		s.air_jumps = maxi(s.air_jumps, int(mv["air_jumps"]))
		s.air_jump_mult = float(mv.get("air_jump_mult", s.air_jump_mult))
	if mv.has("dash_speed"):
		s.dash_speed = maxf(s.dash_speed, float(mv["dash_speed"]))
		s.dash_time = float(mv.get("dash_time", s.dash_time))
		s.dash_cooldown = float(mv.get("dash_cooldown", s.dash_cooldown))
	if mv.has("glide_fall"):
		var g := float(mv["glide_fall"])
		s.glide_fall = g if s.glide_fall <= 0.0 else minf(s.glide_fall, g)
	if mv.has("climb_speed") or mv.has("climb_mult"):
		s.climb_speed = maxf(s.climb_speed, climb_of(mv))
	if mv.has("swim_mult"):
		s.swim_speed *= float(mv["swim_mult"])

## Gecko's wall-climb speed (tiles/s) from a spark's move block: climb_mult x the pace, or
## an absolute climb_speed.
static func climb_of(mv: Dictionary) -> float:
	if mv.has("climb_mult"):
		return float(mv["climb_mult"]) * MoveStats.pace()
	return float(mv.get("climb_speed", 0.0))

## The MoveStats a player moves with: MoveStats.from_srd(speeds, size) plus the kindled
## sparks. speeds: {walk, climb?, swim?, fly?} in ft (what the host mirrors).
static func move_stats(speeds: Dictionary, size_name: String, kindled: Array) -> MoveStats:
	var s := MoveStats.from_srd(speeds, size_name)
	apply(kindled, s, {})
	return s

## Tags the kindled sparks add (no movement).
static func tags(kindled: Array) -> Dictionary:
	var out := {}
	apply(kindled, null, out)
	return out
