## Rolls ordinary gear (material, quality, affixes, sometimes a +N) and names items.
## Deterministic: everything comes from the RandomNumberGenerator passed in.
##
##   var it := ItemGen.roll(rng, "longsword", 20, "elite")   # {base, count, material, quality, affixes?, ...}
##   ItemGen.name(it)                                        # "Fine Iron Longsword of Embers"
class_name ItemGen
extends RefCounted

const RANKS := ["minion", "standard", "elite", "champion", "boss"]
## Affix count weights [0, 1, 2, 3] by rank.
const AFFIX_COUNTS := {
	"minion": [80, 20, 0, 0], "standard": [55, 35, 9, 1], "elite": [10, 50, 32, 8],
	"champion": [0, 20, 50, 30], "boss": [0, 0, 30, 70],
}
## Ranks above standard (quality upgrades, +N chance).
const RANK_STEP := {"minion": -1, "standard": 0, "elite": 1, "champion": 2, "boss": 3}
## Bases a random roll may pick from (SRD weapons and armour; firearms left out).
const NO_RANDOM := ["musket", "pistol", "lance", "blowgun", "net"]

## A random piece of ordinary gear. base "" picks an SRD weapon or armour. level_hint (1-100)
## gates materials and affix tiers; rank (ItemGen.RANKS) shifts quality, affix count and the
## chance of a +N.
static func roll(rng: RandomNumberGenerator, base: String, level_hint: int, rank := "standard") -> Dictionary:
	Items.ensure()
	if base == "" or not Items.exists(base):
		base = random_base(rng)
	var step := int(RANK_STEP.get(rank, 0))
	var item := {"base": base, "count": 1}
	var k := String(Items.row(base).get("kind", ""))
	if not k in ["weapon", "armor", "shield"]:
		return item
	if Items.takes_material(base):
		item["material"] = _pick_material(rng, level_hint)
	item["quality"] = _pick_quality(rng, step)
	var affs := _pick_affixes(rng, "weapon" if k == "weapon" else "armor", level_hint, rank)
	if not affs.is_empty():
		item["affixes"] = affs
	# A plain +N now and then, deeper and on stronger foes; kept inside the +3 budget.
	var p := clampf((level_hint - 10) / 200.0, 0.0, 0.25) + 0.04 * maxi(0, step)
	if rng.randf() < p:
		var top := 1 if level_hint < 40 else (2 if level_hint < 70 else 3)
		var n := rng.randi_range(1, top)
		var mat_bonus := int(Items.materials().get(String(item.get("material", "")), {}).get(
				"weapon" if k == "weapon" else "armor", {}).get("mods", {}).get("attack" if k == "weapon" else "ac", 0))
		n = mini(n, Items.BUDGET - mat_bonus)
		if n > 0:
			item["magic"] = "weapon-1-2-or-3" if k == "weapon" else ("shield-1-2-or-3" if k == "shield" else "armor-1-2-or-3")
			item["tier"] = n - 1
	return item

static func random_base(rng: RandomNumberGenerator) -> String:
	var pool: Array = []
	for s: String in Items.weapon_slugs + Items.armor_slugs:
		if not s in NO_RANDOM:
			pool.append(s)
	return pool[rng.randi_range(0, pool.size() - 1)]

static func _pick_material(rng: RandomNumberGenerator, level_hint: int) -> String:
	var ids: Array = []
	var w: Array = []
	var mats := Items.materials()
	for id: String in mats:
		var m: Dictionary = mats[id]
		if int(m.get("level", 1)) <= level_hint:
			ids.append(id)
			w.append(float(m.get("weight", 1)))
	return ids[_weighted(rng, w)] if not ids.is_empty() else "iron"

static func _pick_quality(rng: RandomNumberGenerator, step: int) -> String:
	var order := Items.quality_order()
	var q := Items.quality_table()
	var w: Array = []
	for id: String in order:
		w.append(float(q[id].get("chance", 1)))
	var i := _weighted(rng, w)
	for _s in absi(step):
		if rng.randf() < 0.35:
			i += signi(step)
	return order[clampi(i, 0, order.size() - 1)]

static func _pick_affixes(rng: RandomNumberGenerator, on: String, level_hint: int, rank: String) -> Array:
	var counts: Array = AFFIX_COUNTS.get(rank, AFFIX_COUNTS["standard"])
	var n := _weighted(rng, counts)
	var tier := 1 if level_hint < 30 else (2 if level_hint < 65 else 3)
	var ids: Array = []
	var w: Array = []
	var all := Items.affixes()
	for id: String in all:
		var a: Dictionary = all[id]
		if String(a.get("on", "any")) in ["any", on]:
			ids.append(id)
			w.append(float(a.get("weight", 10)))
	var out: Array = []
	var prefixes := 0
	while out.size() < n and not ids.is_empty():
		var i := _weighted(rng, w)
		var id: String = ids[i]
		ids.remove_at(i)
		w.remove_at(i)
		if String(all[id].get("kind", "")) == "prefix":
			if prefixes >= 1:
				continue
			prefixes += 1
		out.append(id if tier == 1 else "%s:%d" % [id, tier])
	return out

## Index into `weights` (floats or ints), chosen in proportion.
static func _weighted(rng: RandomNumberGenerator, weights: Array) -> int:
	var total := 0.0
	for x: Variant in weights:
		total += float(x)
	if total <= 0.0:
		return 0
	var r := rng.randf() * total
	for i in weights.size():
		r -= float(weights[i])
		if r < 0.0:
			return i
	return weights.size() - 1

## Public alias of the weighted pick for other item code (Loot).
static func weighted(rng: RandomNumberGenerator, weights: Array) -> int:
	return _weighted(rng, weights)

## Display name. Ordinary gear: [Quality] [Prefix] [Material] Base [of Suffix] [+N]; SRD
## magic items by their SRD name (with the base and variant where it varies); sparks
## "Spark of Fleet II"; tiles and materials by their row name; stacks are not counted here.
static func name(item: Dictionary) -> String:
	Items.ensure()
	var base := String(item.get("base", ""))
	var r := Items.row(base)
	if item.has("spark"):
		var sp: Dictionary = item["spark"]
		return "Spark of %s %s" % [Sparks.spark_name(String(sp.get("id", ""))), Sparks.rank_name(int(sp.get("rank", 0)))]
	var k := String(r.get("kind", ""))
	var magic := String(item.get("magic", ""))
	var is_plus := magic.ends_with("-1-2-or-3")
	if magic != "" and not is_plus:
		var e := Items.magic_entry(magic)
		var n := String(e.get("name", magic))
		var tiers: Array = e.get("tiers", [])
		var tn := String(tiers[clampi(int(item.get("tier", 0)), 0, tiers.size() - 1)].get("name", "")) if not tiers.is_empty() else ""
		if magic == "potions-of-healing":
			n = "Potion of " + tn
		elif magic == "belt-of-giant-strength":
			n = "Belt of %s Giant Strength" % tn
		elif magic == "potion-of-giant-strength":
			n = "Potion of %s Giant Strength" % tn
		elif tn != "":
			n += " (%s)" % tn
		if k in ["weapon", "armor", "shield"] and Items.magic_bases(magic).size() > 1:
			n += " (%s)" % String(r.get("name", base))
		return n
	var parts := PackedStringArray()
	var q := String(Items.quality_table().get(String(item.get("quality", "")), {}).get("name", ""))
	if q != "":
		parts.append(q)
	var suffix := ""
	for a: Variant in item.get("affixes", []):
		var af: Dictionary = Items.affixes().get(String(a).split(":")[0], {})
		if String(af.get("kind", "")) == "prefix" and parts.size() < 3:
			parts.append(String(af.get("name", "")))
		elif suffix == "" and String(af.get("kind", "")) == "suffix":
			suffix = String(af.get("name", ""))
	if item.has("material"):
		parts.append(String(Items.materials().get(String(item["material"]), {}).get("name", "")))
	var bn := String(r.get("name", base))
	if is_plus and base == magic:
		bn = bn.replace(", +1, +2, or +3", "")
	parts.append(bn)
	var out := " ".join(parts)
	if suffix != "":
		out += " " + suffix
	if is_plus:
		out += " +%d" % (int(item.get("tier", 0)) + 1)
	return out
