## Names for the land: each stretch of a biome, each range, each river (data/setting/names.json).
## A pure function of the seed. Stage "names" writes them into the strip and the barriers, so they
## reach meta.biomes[i].name and meta.barriers.{ranges,rivers}[i].name.
class_name RegionNames
extends RefCounted

const FILE := "res://data/setting/names.json"

static var _data := {}

static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		_data = d if d is Dictionary else {}
	return _data

## Stage "names". Runs after everything: its RNG key is its own, so no other stage changes.
static func run(c: RefCounted, rng: RandomNumberGenerator) -> void:
	var taken := {}
	for s: Dictionary in c.biomes:
		s["name"] = region(String(s["biome"]), rng, taken)
	for r: Dictionary in c.ranges:
		r["name"] = range_name(rng, taken)
	for r: Dictionary in c.rivers:
		r["name"] = river(rng, taken)

static func _pick(list: Array, rng: RandomNumberGenerator) -> String:
	return String(list[rng.randi_range(0, list.size() - 1)])

static func _pair(t: Dictionary, rng: RandomNumberGenerator, taken: Dictionary) -> String:
	for attempt in 40:
		var n := "the %s %s" % [_pick(t["adj"], rng), _pick(t["noun"], rng)]
		if not taken.has(n):
			taken[n] = true
			return n
	return "the %s %s %d" % [_pick(t["adj"], rng), _pick(t["noun"], rng), taken.size()]

static func region(biome: String, rng: RandomNumberGenerator, taken: Dictionary) -> String:
	var r: Dictionary = data().get("region", {})
	return _pair(r.get(biome, r["meadow"]), rng, taken)

static func range_name(rng: RandomNumberGenerator, taken: Dictionary) -> String:
	return _pair(data()["range"], rng, taken)

static func river(rng: RandomNumberGenerator, taken: Dictionary) -> String:
	var t: Dictionary = data()["river"]
	for attempt in 40:
		var n := "the River %s%s" % [_pick(t["stem"], rng), _pick(t["end"], rng)]
		if not taken.has(n):
			taken[n] = true
			return n
	return "the River %s %d" % [_pick(t["stem"], rng), taken.size()]
