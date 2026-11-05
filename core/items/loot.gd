## Loot tables (data/loot/loot.json): what a kill drops, by creature type, CR band and rank,
## with spark ranks by depth band. Deterministic given the RandomNumberGenerator.
##
##   var info := Loot.victim_info("goblin-warrior", "elite", "caves")
##   var items := Loot.roll(rng, info)        # [item records]; coin as {base: "coin", count}
class_name Loot
extends RefCounted

const PATH := "res://data/loot/loot.json"
const GenCtx := preload("res://core/world/worldgen/gen_context.gd")
## Potions loot draws from (SRD magic slug and tier), by band index.
const POTION_TIERS := [0, 0, 1, 2, 3]

static var _data := {}
## rarity -> [[slug, weight]] of SRD magic items (no artifacts, no +N or potion families)
static var _by_rarity := {}

static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _data

## What the loot roll needs about a victim: {type, cr, rank, band, drop_find, coin_find}.
## slug: an SRD monster slug ("" for none); band: a worldgen band name (sky, surface, caves,
## deeps, nadir).
static func victim_info(slug: String, rank := "standard", band := "surface", srd: SRDContent = null) -> Dictionary:
	var type := "default"
	var cr := 0.0
	if slug != "":
		var s := srd if srd != null else WorldHost.shared_srd()
		var r: Dictionary = s.pack.get_row("monster", slug)
		if not r.is_empty():
			type = String(r["data"].get("type", "default")).split(" ")[0].to_lower()
			cr = s.monster_cr(slug)
	return {"type": type, "cr": cr, "rank": rank, "band": band, "drop_find": 0.0, "coin_find": 0.0}

static func band_of(cr: float) -> int:
	var bands: Array = data()["bands"]
	for i in bands.size():
		if cr <= float(bands[i]["max_cr"]):
			return i
	return bands.size() - 1

## Worldgen depth band at row y of a world `height` rows tall (gen_context.gd BAND_CUTS).
static func depth_band(y: float, height: int) -> String:
	var f := y / maxf(1.0, float(height))
	var out := "nadir"
	for cut: Array in GenCtx.BAND_CUTS:
		if f >= float(cut[1]):
			out = String(cut[0])
	return out

## Roll a kill's loot: [item records]. info as victim_info.
static func roll(rng: RandomNumberGenerator, info: Dictionary) -> Array:
	var d := data()
	var bi := band_of(float(info.get("cr", 0.0)))
	var band: Dictionary = d["bands"][bi]
	var types: Dictionary = d["types"]
	var t: Dictionary = types.get(String(info.get("type", "default")), types["default"])
	var rank := String(info.get("rank", "standard"))
	var rk: Dictionary = d["ranks"].get(rank, d["ranks"]["standard"])
	var out: Array = []
	# coin
	if rng.randf() < float(t.get("coin", 0.0)) and float(rk.get("coin", 1.0)) > 0.0:
		var n := roundi(roll_dice(rng, String(band["coin"])) * float(rk.get("coin", 1.0)) * (1.0 + float(info.get("coin_find", 0.0))))
		if n > 0:
			out.append(Items.coin(n))
	# drops
	var rolls := float(rk.get("rolls", 1.0))
	var n_rolls := floori(rolls) + (1 if rng.randf() < rolls - floorf(rolls) else 0)
	var chance := float(band["drop"]) * (1.0 + float(info.get("drop_find", 0.0)))
	for i in n_rolls:
		if rng.randf() < chance:
			var it := _drop(rng, t, bi, band, rank)
			if not it.is_empty():
				out.append(it)
	# sparks and guarantees
	if rng.randf() < float(rk.get("spark", 0.0)):
		out.append(random_spark(rng, String(info.get("band", "surface"))))
	match String(rk.get("guarantee", "")):
		"spark_or_item":
			if rng.randf() < 0.5:
				out.append(random_spark(rng, String(info.get("band", "surface"))))
			else:
				out.append(_gear_or_magic(rng, bi, band, rank))
		"spark_and_magic":
			out.append(random_spark(rng, String(info.get("band", "surface"))))
			out.append(random_magic(rng, band))
	return out

static func _drop(rng: RandomNumberGenerator, t: Dictionary, bi: int, band: Dictionary, rank: String) -> Dictionary:
	var cats := ["gear", "material", "potion", "magic"]
	var w: Array = []
	for c: String in cats:
		w.append(float(t.get(c, 0)))
	match cats[ItemGen.weighted(rng, w)]:
		"gear":
			return ItemGen.roll(rng, "", int(band["level"]), rank)
		"material":
			var mats: Array = t.get("materials", ["bone"])
			var base := String(mats[rng.randi_range(0, mats.size() - 1)])
			return Items.make(base, rng.randi_range(1, 3))
		"potion":
			return Items.make_magic("potions-of-healing", POTION_TIERS[clampi(bi, 0, POTION_TIERS.size() - 1)])
		"magic":
			return random_magic(rng, band)
	return {}

static func _gear_or_magic(rng: RandomNumberGenerator, bi: int, band: Dictionary, rank: String) -> Dictionary:
	if rng.randf() < 0.7:
		return ItemGen.roll(rng, "", int(band["level"]), rank)
	return random_magic(rng, band)

## A spark of any kind, its rank by depth band.
static func random_spark(rng: RandomNumberGenerator, band: String) -> Dictionary:
	var ids := Sparks.ids()
	ids.sort()
	var id: String = ids[rng.randi_range(0, ids.size() - 1)]
	return Items.spark_item(id, ItemGen.weighted(rng, Sparks.depth_weights(band)))

## An SRD magic item at the band's rarity weights; working ones weigh more.
static func random_magic(rng: RandomNumberGenerator, band: Dictionary) -> Dictionary:
	_index()
	var rar: Dictionary = band.get("magic", {"common": 1})
	var keys: Array = rar.keys()
	var w: Array = []
	for k: String in keys:
		w.append(float(rar[k]) if _by_rarity.has(k) else 0.0)
	var rarity: String = keys[ItemGen.weighted(rng, w)]
	var pool: Array = _by_rarity.get(rarity, [])
	if pool.is_empty():
		return Items.make_magic("potions-of-healing", 0)
	var pw: Array = []
	for p: Array in pool:
		pw.append(p[2])
	var pick: Array = pool[ItemGen.weighted(rng, pw)]
	var slug: String = pick[0]
	var tier: int = pick[1]
	var e := Items.magic_entry(slug)
	var base := ""
	if String(e.get("kind", "")) in ["weapon", "armor", "shield"]:
		var bases := Items.magic_bases(slug).filter(func(b: String) -> bool: return not b in ItemGen.NO_RANDOM)
		base = bases[rng.randi_range(0, bases.size() - 1)] if not bases.is_empty() else ""
	return Items.make_magic(slug, tier, base)

## Build rarity -> [[slug, tier, weight]] once. Each tier of a "varies" item is its own entry.
static func _index() -> void:
	if not _by_rarity.is_empty():
		return
	var working := float(data().get("magic_working", 4))
	var slugs := Items.magic_slugs()
	slugs.sort()
	for slug: String in slugs:
		var e := Items.magic_entry(slug)
		if String(e.get("rarity", "")) == "artifact":
			continue
		var tiers: Array = e.get("tiers", [])
		var n := maxi(1, tiers.size())
		for tier in n:
			var r := Items.rarity_of(slug, tier)
			var wt := (working if String(e.get("status", "inert")) != "inert" else 1.0) / n
			if not _by_rarity.has(r):
				_by_rarity[r] = []
			_by_rarity[r].append([slug, tier, wt])

## Roll "2d6+3" style dice (no rng: 0).
static func roll_dice(rng: RandomNumberGenerator, expr: String) -> int:
	var m := RegEx.create_from_string("^(\\d+)d(\\d+)([+-]\\d+)?$").search(expr.strip_edges())
	if m == null:
		return int(expr) if expr.is_valid_int() else 0
	var n := int(m.get_string(1))
	var sides := int(m.get_string(2))
	var total := int(m.get_string(3)) if m.get_string(3) != "" else 0
	for i in n:
		total += rng.randi_range(1, sides)
	return total
