## The Monsters track's data: data/ecology/habitats.json (where each SRD monster lives and how
## it behaves), spawning.json (director, ranks), affixes.json. Read-only after loading.
class_name Ecology
extends RefCounted

const HABITATS := "res://data/ecology/habitats.json"
const SPAWNING := "res://data/ecology/spawning.json"
const AFFIXES := "res://data/ecology/affixes.json"

static var _hab := {}
static var _spawn := {}
static var _affix := {}
static var _cr := {}

static func habitats() -> Dictionary:
	if _hab.is_empty():
		_hab = JSON.parse_string(FileAccess.get_file_as_string(HABITATS))
	return _hab

static func spawning() -> Dictionary:
	if _spawn.is_empty():
		_spawn = JSON.parse_string(FileAccess.get_file_as_string(SPAWNING))
	return _spawn

static func affixes() -> Dictionary:
	if _affix.is_empty():
		_affix = JSON.parse_string(FileAccess.get_file_as_string(AFFIXES))
	return _affix

## The row for a slug ({} if none).
static func row(slug: String) -> Dictionary:
	var r: Variant = habitats().get(slug)
	return r if r is Dictionary else {}

static func rank_def(rank: String) -> Dictionary:
	return spawning()["ranks"].get(rank, spawning()["ranks"]["standard"])

## SRD challenge rating as a float ("1/4" -> 0.25).
static func cr_of(srd: SRDContent, slug: String) -> float:
	if _cr.has(slug):
		return _cr[slug]
	var c := str(srd.pack.get_row("monster", slug).get("data", {}).get("cr", "0"))
	var v := 0.0
	if "/" in c:
		var p := c.split("/")
		v = float(p[0]) / float(p[1])
	else:
		v = float(c)
	_cr[slug] = v
	return v

## CR as budget weight: CR 0 creatures still cost something.
static func cost(cr: float) -> float:
	return maxf(cr, 0.125)

## Maximum hit points from the stat block's hit dice ("20d10+40" -> 240), or 0.
static func max_hp(srd: SRDContent, slug: String) -> int:
	var expr := str(srd.pack.get_row("monster", slug).get("data", {}).get("hp_dice", ""))
	var re := RegEx.create_from_string("^\\s*(\\d+)d(\\d+)\\s*(?:([+-])\\s*(\\d+))?")
	var m := re.search(expr)
	if m == null:
		return 0
	var n := int(m.get_string(1)) * int(m.get_string(2))
	if m.get_string(3) != "":
		n += int(m.get_string(4)) * (-1 if m.get_string(3) == "-" else 1)
	return n

## Candidates for a place and time: [{slug, row, cr}] with spawn "wild", band and biome
## matching, time allowed, CR within [lo, hi]; water creatures only if `water`.
static func roster(srd: SRDContent, band: String, biome: String, night: bool, lo: float, hi: float,
		water := false) -> Array:
	var out: Array = []
	var biomes: Array = spawning()["biome_fallback"].get(biome, [biome])
	if not biome in biomes:
		biomes = biomes + [biome]
	for slug: String in habitats():
		if slug.begins_with("_"):
			continue
		var r: Dictionary = habitats()[slug]
		if r.get("spawn", "wild") != "wild" or float(r.get("w", 1.0)) <= 0.0:
			continue
		if not band in r.get("bands", []):
			continue
		var ok := false
		for b: String in r.get("biomes", []):
			if b in biomes:
				ok = true
				break
		if not ok:
			continue
		var tm := String(r.get("time", "any"))
		if (tm == "day" and night) or (tm == "night" and not night and band in ["surface", "sky"]):
			continue
		if (String(r.get("medium", "")) == "water") != water:
			continue
		var cr := cr_of(srd, slug)
		if cr < lo - 1e-6 or cr > hi + 1e-6:
			continue
		out.append({"slug": slug, "row": r, "cr": cr})
	return out
