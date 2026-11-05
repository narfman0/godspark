## Static tables for the strategic sim: goods, biomes, cultures, lairs, names (data/sim/*.json)
## and a compact combat profile for every SRD monster stat block. Loaded once, shared.
class_name SimData
extends RefCounted

const MONSTERS_PATH := "res://addons/srd/data/srd-5.2.1/monsters.json"
const NUMBER_WORDS := {"one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6}

static var _loaded := false
static var goods: Dictionary = {}
static var good_names: Array[String] = []
static var biomes: Dictionary = {}
static var cultures: Dictionary = {}
static var culture_ids: Array[String] = []
static var lairs: Dictionary = {}          # band -> Array of lair defs
static var names: Dictionary = {}
## slug -> {name, cr, xp, hp, ac, bonus, dmg, attacks, dmg1}
## dmg/attacks: best attack (all damage parts) times the Multiattack count.
## dmg1: first attack's first damage part only, one attack (what BattleSimulator swings).
static var monsters: Dictionary = {}

static func ensure() -> void:
	if _loaded:
		return
	_loaded = true
	goods = _load("res://data/sim/goods.json")
	for g in goods:
		good_names.append(g)
	biomes = _load("res://data/sim/biomes.json")
	cultures = _load("res://data/sim/cultures.json")
	for c in cultures:
		culture_ids.append(c)
	lairs = _load("res://data/sim/lairs.json")
	names = _load("res://data/sim/names.json")
	_load_monsters()

static func _load(path: String) -> Dictionary:
	var txt := FileAccess.get_file_as_string(path)
	var d: Variant = JSON.parse_string(txt)
	if not d is Dictionary:
		push_error("SimData: can't read %s" % path)
		return {}
	(d as Dictionary).erase("_doc")
	return d

static func _load_monsters() -> void:
	var rows: Variant = JSON.parse_string(FileAccess.get_file_as_string(MONSTERS_PATH))
	if not rows is Array:
		push_error("SimData: can't read monsters")
		return
	for r in rows:
		var d: Dictionary = r.data
		var best := 0.0
		var best_bonus := 0
		var first := -1.0
		var first_bonus := 0
		for a in d.get("actions", []):
			var atk: Variant = a.get("attack")
			if not atk is Dictionary or atk.get("damage", []).is_empty():
				continue
			var total := 0.0
			for part in atk.damage:
				total += float(part.get("avg", 0))
			if first < 0.0:
				first = float(atk.damage[0].get("avg", 0))
				first_bonus = int(atk.get("bonus", 0))
			if total > best:
				best = total
				best_bonus = int(atk.get("bonus", 0))
		var attacks := 1
		for a in d.get("actions", []):
			if str(a.get("name", "")) == "Multiattack":
				attacks = maxi(_count_attacks(str(a.get("text", ""))), 1)
		monsters[r.slug] = {
			"name": str(r.name), "cr": _cr(str(d.get("cr", "0"))), "xp": int(d.get("xp", 0)),
			"hp": maxi(int(d.get("hp", 1)), 1), "ac": int(d.get("ac", 10)),
			"bonus": best_bonus, "dmg": best, "attacks": attacks,
			"bonus1": first_bonus, "dmg1": maxf(first, 0.0),
		}

## "The owlbear makes two Rend attacks." -> 2; "one Bite attack and one Tail Stinger attack" -> 2.
static func _count_attacks(text: String) -> int:
	var sentence := text.split(".")[0].to_lower()
	var n := 0
	for w in sentence.replace(",", " ").split(" "):
		if NUMBER_WORDS.has(w):
			n += NUMBER_WORDS[w]
	return n

static func _cr(s: String) -> float:
	if "/" in s:
		var p := s.split("/")
		return float(p[0]) / float(p[1])
	return float(s)

static func has_monster(slug: String) -> bool:
	ensure()
	return monsters.has(slug)

static func monster(slug: String) -> Dictionary:
	ensure()
	return monsters.get(slug, monsters["commoner"])

static func culture(id: String) -> Dictionary:
	ensure()
	return cultures[id]

## Resource capacities for a biome, falling back to the band's default biome.
static func biome(name: String, band: String) -> Dictionary:
	ensure()
	if biomes.has(name):
		return biomes[name]
	var fb: Dictionary = biomes["_band_default"]
	return biomes[fb.get(band, "plains")]

## Band family used by lairs and route classes: surface, caves or deeps.
static func band_family(band: String) -> String:
	match band:
		"surface", "sky", "":
			return "surface"
		"caves", "underground", "cavern":
			return "caves"
	return "deeps"

## Every slug a culture or lair table names (for validation).
static func all_referenced_slugs() -> Array[String]:
	ensure()
	var out: Array[String] = []
	for cid in cultures:
		var c: Dictionary = cultures[cid]
		out.append(str(c.people))
		for role in ["guards", "escort", "raiders", "army"]:
			for e in c[role]:
				out.append(str(e[0]))
	for band in lairs:
		for l in lairs[band]:
			for m in l.members:
				out.append(str(m[0]))
			if str(l.get("grow", "")) != "":
				out.append(str(l.grow))
	return out

## XP of a {slug: count} group: a quick strength measure.
static func group_xp(members: Dictionary) -> float:
	ensure()
	var total := 0.0
	for slug in members:
		total += float(monster(slug).xp) * int(members[slug])
	return total

## Expected damage output times hit points: a Lanchester-style strength.
static func group_power(members: Dictionary) -> float:
	ensure()
	var dpr := 0.0
	var hp := 0.0
	for slug in members:
		var m := monster(slug)
		var n := int(members[slug])
		dpr += (m.dmg * m.attacks * clampf((21.0 + m.bonus - 14.0) / 20.0, 0.05, 0.95)) * n
		hp += m.hp * n
	return sqrt(maxf(dpr * hp, 0.0))

## Allocate n units over a [slug, weight] recipe by largest remainder: deterministic and
## integral. Units with weight below one share still appear once n is large enough.
static func allocate(recipe: Array, n: int) -> Dictionary:
	var out := {}
	if n <= 0:
		return out
	var wsum := 0.0
	for e in recipe:
		wsum += float(e[1])
	var rem: Array = []
	var given := 0
	for i in recipe.size():
		var share := float(recipe[i][1]) / wsum * n
		var k := int(floor(share))
		given += k
		rem.append([share - k, i])
		if k > 0:
			out[str(recipe[i][0])] = k
	rem.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	var j := 0
	while given < n:
		var slug := str(recipe[rem[j][1]][0])
		out[slug] = int(out.get(slug, 0)) + 1
		given += 1
		j = (j + 1) % rem.size()
	return out

static func count(members: Dictionary) -> int:
	var n := 0
	for k in members:
		n += int(members[k])
	return n
