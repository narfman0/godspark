## Knacks and deeds (docs/m2.md, "The level track"). A Knack is a small permanent perk picked
## from three offers at every KNACK level: an SRD skill or tool proficiency, a language, or a
## Bond with a people or a kind of beast. Offers are weighted by the deeds of the band just
## played (the growth of the Character's deed counters since the last offer) and seeded, so
## the same character, level and deeds always get the same three. Data: data/rules/knacks.json.
##
##   var ids := Knacks.offer(ch, delta, seed_value, owned_skills)    # up to three knack ids
##   Knacks.def("skill-athletics")    # {id, kind, key, name, text, deeds}
##
## Deed counters (Character.deeds, ints; "a:b" counters also add to the aggregate "a"):
##   dig, dig:<tile name>        tiles dug          place, place:<tile name>   tiles placed
##   run, climb, fall, swim      tiles moved that way
##   underground, underground:<band>   seconds below the surface (band: caves, deeps, nadir...)
##   sleep                       nights slept       rest                       short rests taken
##   kill, kill:<creature type>  kills you got XP for; beast:<kind> for beasts in beast_kinds
##   revive, downed              allies revived; times you went down
##   trade, trade:<culture>      fed later (trades with a people, by data/sim/cultures.json key)
##   craft, craft:<what>         fed later (items crafted)
##   kindle                      fed later (sparks kindled)
## Pure data and static functions; deterministic (its own seeded RNG, never Dice).
class_name Knacks
extends RefCounted

const PATH := "res://data/rules/knacks.json"
## Offers per KNACK level.
const OFFER := 3
enum Kind { SKILL, TOOL, LANGUAGE, BOND }
const KIND_NAMES := ["skill", "tool", "language", "bond"]

static var _data := {}
static var _by_id := {}
static var _beast_of := {}

static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if not d is Dictionary:
			push_error("knacks: cannot read %s" % PATH)
			return {}
		var by_id := {}
		for k: Dictionary in d.get("knacks", []):
			by_id[String(k["id"])] = k
		var beast := {}
		var kinds: Dictionary = d.get("beast_kinds", {})
		for kind: String in kinds:
			for slug: String in kinds[kind].get("slugs", []):
				beast[slug] = kind
		_by_id = by_id
		_beast_of = beast
		_data = d
	return _data

## Every knack row, in file order.
static func all() -> Array:
	return data().get("knacks", [])

## One knack row ({} if unknown).
static func def(id: String) -> Dictionary:
	data()
	return _by_id.get(id, {})

static func exists(id: String) -> bool:
	return not def(id).is_empty()

## "skill" | "tool" | "language" | "bond" ("" if unknown).
static func kind_of(id: String) -> String:
	return String(def(id).get("kind", ""))

## The beast kind of an SRD monster slug ("" if none): the key after "beast:" in a Bond.
static func beast_kind(slug: String) -> String:
	data()
	return String(_beast_of.get(slug, ""))

## Add n to a deed counter and, for "a:b", to the aggregate "a" too.
static func add_deed(deeds: Dictionary, counter: String, n: int) -> void:
	if n == 0 or counter == "":
		return
	deeds[counter] = int(deeds.get(counter, 0)) + n
	var i := counter.find(":")
	if i > 0:
		var agg := counter.substr(0, i)
		deeds[agg] = int(deeds.get(agg, 0)) + n

## How much each counter grew from `mark` to `now`.
static func delta(now: Dictionary, mark: Dictionary) -> Dictionary:
	var out := {}
	for k: String in now:
		var d := int(now[k]) - int(mark.get(k, 0))
		if d > 0:
			out[k] = d
	return out

## Offer weight of one knack for a band's deed growth.
static func weight(k: Dictionary, band_deeds: Dictionary) -> float:
	var d := data()
	var units: Dictionary = d.get("units", {})
	var cap := float(d.get("cap", 4.0))
	var w := float(d.get("base", 1.0))
	var deeds: Dictionary = k.get("deeds", {})
	for counter: String in deeds:
		var got := float(band_deeds.get(counter, 0))
		if got <= 0.0:
			continue
		var prefix := counter.split(":")[0]
		var unit := maxf(1.0, float(units.get(prefix, 10)))
		w += float(deeds[counter]) * minf(cap, got / unit)
	return w

## Up to `n` knack ids for a character: never one it holds, never a skill it is already
## proficient in (`owned_skills`), weighted by `band_deeds`, sampled without replacement with
## an RNG seeded by `seed_value`.
static func offer(held: Array, band_deeds: Dictionary, seed_value: int, owned_skills: Array = [], n := OFFER) -> Array:
	var pool := []
	var weights := []
	for k: Dictionary in all():
		var id := String(k["id"])
		if id in held:
			continue
		if k.get("kind") == "skill" and String(k.get("key")) in owned_skills:
			continue
		pool.append(id)
		weights.append(weight(k, band_deeds))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out := []
	while out.size() < n and not pool.is_empty():
		var total := 0.0
		for w: float in weights:
			total += w
		var r := rng.randf() * total
		var pick := pool.size() - 1
		for i in pool.size():
			r -= float(weights[i])
			if r < 0.0:
				pick = i
				break
		out.append(pool[pick])
		pool.remove_at(pick)
		weights.remove_at(pick)
	return out

## The seed for an offer: stable for a character's name, level and world.
static func offer_seed(char_name: String, level: int, world_seed: int) -> int:
	return hash("knack:%s:%d:%d" % [char_name, level, world_seed])
