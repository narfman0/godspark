## The item catalogue and the item record's rules. Pure static functions over data loaded
## once: SRD weapons and armour (from the addon's tables, by slug), every breakable tile
## (tile:<name>), data/items/base.json (materials, coin, spark), and the 258 SRD magic items
## (rarity, attunement and text from the addon; slot, mods and tiers from data/items/magic.json).
##
## Item record (a JSON-safe Dictionary; docs/tracks/items.md):
##   {base, count, material?, quality?, affixes?: [id or "id:tier"], magic?: slug, tier?: int,
##    spark?: {id, rank}, bonded?: true}
##
##   var sword := {"base": "longsword", "count": 1, "material": "iron", "affixes": ["embers"]}
##   ItemEffects.apply(c, Items.mods(sword))
##   Items.make_magic("ring-of-protection")      # {base: "ring-of-protection", magic: ..., count: 1}
class_name Items
extends RefCounted

const SRD_DIR := "res://addons/srd/data/srd-5.2.1/"
const DIR := "res://data/items/"
## Most bonus to attack rolls (weapons) or AC (armour, shields) one item gets from material,
## quality and magic together: the SRD's +3. Items.mods enforces it, trimming quality first,
## then material (magic is SRD and already within it).
const BUDGET := 3
## ItemEffects keys an affix may never carry (riders and utility only).
const FORBIDDEN_AFFIX_MODS := ["attack", "ac", "save", "spell_attack", "spell_dc", "damage", "unarmored_ac",
	"initiative", "set_ability", "ability"]
## Equipment slot kinds a row may name.
const SLOT_KINDS := ["main_hand", "off_hand", "armor", "head", "neck", "cloak", "hands", "belt", "feet", "ring"]
const SPELLCASTERS := ["bard", "cleric", "druid", "paladin", "ranger", "sorcerer", "warlock", "wizard"]

static var _loaded := false
## base -> row: {name, kind, slot, stack, value, weight, ...}
static var _rows := {}
## magic slug -> entry: magic.json's row plus name, rarity, attunement, attunement_by, consumable, text
static var _magic := {}
static var _materials := {}
static var _quality := {}
static var _quality_order: Array = []
static var _no_metal := {}
static var _affixes := {}
static var _recipes := {}
## tile id -> base of what digging it gives
static var _tile_drop := {}
## SRD weapon and armour slugs, in table order.
static var weapon_slugs: Array = []
static var armor_slugs: Array = []

static func ensure() -> void:
	if _loaded:
		return
	_loaded = true
	TileDefs.ensure()
	var base: Dictionary = _json(DIR + "base.json")
	for k: String in base["rows"]:
		_rows[k] = (base["rows"][k] as Dictionary).duplicate(true)
	var tile_stack := int(base.get("tile_stack", 999))
	for id in TileDefs.names.size():
		var n := TileDefs.names[id]
		if n == "" or id == TileDefs.AIR or TileDefs.hardness[id] < 0.0:
			continue
		_rows["tile:" + n] = {"name": n.capitalize(), "kind": "tile", "tile": id, "stack": tile_stack,
				"value": 0, "weight": 1}
	var drops: Dictionary = base.get("tile_drops", {})
	for id in TileDefs.names.size():
		var n := TileDefs.names[id]
		if _rows.has("tile:" + n):
			_tile_drop[id] = String(drops.get(n, "tile:" + n))
	for r: Dictionary in _json(SRD_DIR + "weapons.json"):
		var d: Dictionary = r["data"]
		weapon_slugs.append(r["slug"])
		var props: Array = d.get("properties", [])
		_rows[r["slug"]] = {"name": r["name"], "kind": "weapon", "slot": "main_hand", "stack": 1,
				"value": SRDItems.cost_gp(String(d.get("cost", ""))), "weight": _lb(String(d.get("weight", ""))),
				"category": d.get("category", ""), "damage_type": String(d.get("damage_type", "")).to_lower(),
				"two_handed": "two_handed" in props or "two-handed" in props, "light": "light" in props,
				"melee": String(d.get("category", "")).ends_with("melee")}
	for r: Dictionary in _json(SRD_DIR + "armor.json"):
		var d: Dictionary = r["data"]
		armor_slugs.append(r["slug"])
		var shield := String(d.get("type", "")) == "shield"
		_rows[r["slug"]] = {"name": r["name"], "kind": "shield" if shield else "armor",
				"slot": "off_hand" if shield else "armor", "stack": 1, "armor_type": d.get("type", ""),
				"value": SRDItems.cost_gp(String(d.get("cost", ""))), "weight": _lb(String(d.get("weight", "")))}
	var authored: Dictionary = _json(DIR + "magic.json")
	for r: Dictionary in _json(SRD_DIR + "magic_items.json"):
		var d: Dictionary = r["data"]
		var e: Dictionary = (authored.get(r["slug"], {"slot": "", "kind": "carried", "status": "inert"}) as Dictionary).duplicate(true)
		e["name"] = r["name"]
		e["rarity"] = String(d.get("rarity", "common"))
		e["variants"] = d.get("variants", {})
		e["attunement"] = bool(d.get("attunement", false))
		e["attunement_by"] = String(d.get("attunement_by", ""))
		e["consumable"] = bool(d.get("consumable", false)) or e.get("kind") == "consumable"
		e["text"] = String(d.get("text", ""))
		_magic[r["slug"]] = e
		var stack := 20 if e["consumable"] else 1
		_rows[r["slug"]] = {"name": r["name"], "kind": e.get("kind", "carried"), "slot": e.get("slot", ""),
				"stack": stack, "value": SRDItems.value_of(rarity_of(r["slug"], 0), e["consumable"]),
				"weight": 1, "magic": true}
	var mat: Dictionary = _json(DIR + "materials.json")
	_materials = mat["materials"]
	_quality = mat["quality"]
	_quality_order = mat["quality_order"]
	for b: String in mat.get("no_metal", []):
		_no_metal[b] = true
	_affixes = _json(DIR + "affixes.json")["affixes"]
	_recipes = _json(DIR + "recipes.json")["recipes"]

## JSON with whole numbers as ints (mods compare and print as the data says).
static func _json(path: String) -> Variant:
	return Character._ints(JSON.parse_string(FileAccess.get_file_as_string(path)))

static func _lb(s: String) -> float:
	var m := RegEx.create_from_string("([\\d.]+)").search(s)
	return float(m.get_string(1)) if m != null else 0.0

# --- rows -------------------------------------------------------------------------------

static func row(base: String) -> Dictionary:
	ensure()
	return _rows.get(base, {})

static func exists(base: String) -> bool:
	ensure()
	return _rows.has(base)

static func all_bases() -> Array:
	ensure()
	return _rows.keys()

static func magic_entry(slug: String) -> Dictionary:
	ensure()
	return _magic.get(slug, {})

static func magic_slugs() -> Array:
	ensure()
	return _magic.keys()

static func materials() -> Dictionary:
	ensure()
	return _materials

static func quality_table() -> Dictionary:
	ensure()
	return _quality

static func quality_order() -> Array:
	ensure()
	return _quality_order

static func affixes() -> Dictionary:
	ensure()
	return _affixes

static func recipes() -> Dictionary:
	ensure()
	return _recipes

## Can this base take a metal material?
static func takes_material(base: String) -> bool:
	var k := String(row(base).get("kind", ""))
	return k in ["weapon", "armor", "shield"] and not _no_metal.has(base)

# --- records ----------------------------------------------------------------------------

static func make(base: String, count := 1) -> Dictionary:
	return {"base": base, "count": count}

## An SRD magic item. Weapons and armour need a base (the first allowed one if "" is given).
static func make_magic(slug: String, tier := 0, base := "") -> Dictionary:
	var e := magic_entry(slug)
	if e.is_empty():
		return {}
	var k := String(e.get("kind", ""))
	var b := slug
	if k in ["weapon", "armor", "shield"]:
		b = base if base != "" else _first_base(e)
	var out := {"base": b, "count": 1, "magic": slug}
	if tier > 0 or e.has("tiers"):
		out["tier"] = clampi(tier, 0, maxi(0, (e.get("tiers", []) as Array).size() - 1))
	return out

static func _first_base(e: Dictionary) -> String:
	var bases: Array = e.get("bases", ["*"])
	for b: String in bases:
		if not b.begins_with("*"):
			return b
	return "longsword" if String(e.get("kind")) == "weapon" else ("shield" if String(e.get("kind")) == "shield" else "chain-mail")

## Bases a magic weapon or armour can be made on.
static func magic_bases(slug: String) -> Array:
	var e := magic_entry(slug)
	var out := []
	for b: String in e.get("bases", ["*"]):
		match b:
			"*":
				out.append_array(weapon_slugs if e.get("kind") == "weapon" else armor_slugs.filter(func(s: String) -> bool: return s != "shield"))
			"*melee":
				out.append_array(weapon_slugs.filter(func(s: String) -> bool: return bool(_rows[s].get("melee", false))))
			"*armor":
				out.append_array(armor_slugs.filter(func(s: String) -> bool: return s != "shield"))
			_:
				out.append(b)
	return out

static func spark_item(id: String, rank: int) -> Dictionary:
	return {"base": "spark", "count": 1, "spark": {"id": id, "rank": rank}}

static func coin(n: int) -> Dictionary:
	return {"base": "coin", "count": n}

## What kind of thing it is: weapon, armor, shield, worn, focus, consumable, carried, ammo,
## tile, material, coin, spark ("" unknown).
static func kind(item: Dictionary) -> String:
	if item.has("magic") and not String(row(String(item.get("base", ""))).get("kind", "")) in ["weapon", "armor", "shield"]:
		return String(magic_entry(String(item["magic"])).get("kind", "carried"))
	return String(row(String(item.get("base", ""))).get("kind", ""))

## The Equipment slot kind it goes in (SLOT_KINDS), or "" if it is not worn.
static func slot_kind(item: Dictionary) -> String:
	if item.has("magic"):
		var e := magic_entry(String(item["magic"]))
		if not e.is_empty():
			return String(e.get("slot", ""))
	return String(row(String(item.get("base", ""))).get("slot", ""))

static func is_two_handed(item: Dictionary) -> bool:
	return bool(row(String(item.get("base", ""))).get("two_handed", false))

static func is_light(item: Dictionary) -> bool:
	return bool(row(String(item.get("base", ""))).get("light", false))

static func is_weapon(item: Dictionary) -> bool:
	return String(row(String(item.get("base", ""))).get("kind", "")) == "weapon"

static func is_shield(item: Dictionary) -> bool:
	return String(item.get("base", "")) == "shield"

static func stack_max(item: Dictionary) -> int:
	return maxi(1, int(row(String(item.get("base", ""))).get("stack", 1)))

static func count(item: Dictionary) -> int:
	return int(item.get("count", 0))

## True if a and b are the same thing (everything but count equal), so they stack.
static func same_stack(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty() or a.size() != b.size():
		return false
	for k: String in a:
		if k == "count":
			continue
		if not b.has(k) or not _deep_eq(a[k], b[k]):
			return false
	return true

static func _deep_eq(x: Variant, y: Variant) -> bool:
	if (x is int or x is float) and (y is int or y is float):
		return float(x) == float(y)
	if x is Dictionary and y is Dictionary:
		if (x as Dictionary).size() != (y as Dictionary).size():
			return false
		for k: Variant in x:
			if not (y as Dictionary).has(k) or not _deep_eq(x[k], y[k]):
				return false
		return true
	if x is Array and y is Array:
		if (x as Array).size() != (y as Array).size():
			return false
		for i in (x as Array).size():
			if not _deep_eq(x[i], y[i]):
				return false
		return true
	return x == y

## The record with its numbers made ints again after JSON (counts, tier, spark rank).
static func clean(item: Variant) -> Dictionary:
	if not item is Dictionary or (item as Dictionary).is_empty():
		return {}
	var d: Dictionary = item
	var out := {"base": String(d.get("base", "")), "count": int(d.get("count", 1))}
	for k: String in ["material", "quality", "magic"]:
		if d.has(k):
			out[k] = String(d[k])
	if d.has("tier"):
		out["tier"] = int(d["tier"])
	if d.has("affixes"):
		var a: Array = []
		for x: Variant in d["affixes"]:
			a.append(String(x))
		out["affixes"] = a
	if d.has("spark") and d["spark"] is Dictionary:
		out["spark"] = {"id": String(d["spark"].get("id", "")), "rank": int(d["spark"].get("rank", 0))}
	if bool(d.get("bonded", false)):
		out["bonded"] = true
	return out

## A copy with another count.
static func with_count(item: Dictionary, n: int) -> Dictionary:
	var out := item.duplicate(true)
	out["count"] = n
	return out

# --- tiles ------------------------------------------------------------------------------

## The base digging tile `tile_id` gives ("" for none: air, bedrock).
static func tile_drop(tile_id: int) -> String:
	ensure()
	return String(_tile_drop.get(tile_id, ""))

## The tile a record places (0: not placeable).
static func tile_of(item: Dictionary) -> int:
	return int(row(String(item.get("base", ""))).get("tile", 0))

static func tile_base(tile_id: int) -> String:
	ensure()
	return "tile:" + TileDefs.names[tile_id] if tile_id > 0 and tile_id < TileDefs.names.size() else ""

# --- rules ------------------------------------------------------------------------------

## The SRD rarity of a magic item at a tier ("varies" items use their variants table).
static func rarity_of(slug: String, tier: int) -> String:
	var e: Dictionary = _magic.get(slug, {})
	var v: Dictionary = e.get("variants", {})
	if v.has(str(tier + 1)):
		return String(v[str(tier + 1)])
	var r := String(e.get("rarity", "common"))
	if r == "varies":
		return ["common", "uncommon", "rare", "very rare", "legendary", "legendary"][clampi(tier, 0, 5)]
	return r

## True if its magic needs a bond (the SRD's attunement) before it works.
static func needs_bond(item: Dictionary) -> bool:
	return item.has("magic") and bool(magic_entry(String(item["magic"])).get("attunement", false))

## Who may bond it ("" anyone): the SRD's "Requires Attunement by ..." text.
static func bond_by(item: Dictionary) -> String:
	return String(magic_entry(String(item.get("magic", ""))).get("attunement_by", ""))

## May a character of this class bond it (SRDItems.can_attune)?
static func can_bond(item: Dictionary, class_slug: String) -> bool:
	return needs_bond(item) and SRDItems.can_attune(bond_by(item), class_slug, class_slug in SPELLCASTERS)

## Is its magic working now (no bond needed, or bonded)?
static func magic_active(item: Dictionary) -> bool:
	return item.has("magic") and (not needs_bond(item) or bool(item.get("bonded", false)))

static func _part(item: Dictionary) -> String:
	var k := String(row(String(item.get("base", ""))).get("kind", ""))
	return "weapon" if k == "weapon" else ("armor" if k == "armor" or k == "shield" else "")

static func _affix_id(a: String) -> String:
	return a.split(":")[0]

static func _affix_tier(a: String) -> int:
	var p := a.split(":")
	return clampi(int(p[1]) - 1, 0, 2) if p.size() > 1 else 0

## An affix's tier row ({mods?, tags?}); {} if unknown.
static func affix_row(a: String) -> Dictionary:
	ensure()
	var af: Dictionary = _affixes.get(_affix_id(a), {})
	var tiers: Array = af.get("tiers", [])
	return tiers[mini(_affix_tier(a), tiers.size() - 1)] if not tiers.is_empty() else {}

## The magic part's {mods, tags, use} at the item's tier ({} without magic).
static func magic_part(item: Dictionary) -> Dictionary:
	if not item.has("magic"):
		return {}
	var e := magic_entry(String(item["magic"]))
	var out := {"mods": (e.get("mods", {}) as Dictionary).duplicate(true), "tags": (e.get("tags", {}) as Dictionary).duplicate(true)}
	var tiers: Array = e.get("tiers", [])
	if not tiers.is_empty():
		var t: Dictionary = tiers[clampi(int(item.get("tier", 0)), 0, tiers.size() - 1)]
		out["mods"].merge(t.get("mods", {}), true)
		if t.has("use"):
			out["use"] = t["use"]
	if e.has("use"):
		out["use"] = e["use"]
	return out

## ItemEffects mods of the whole item (base, material, quality, affixes, magic), the +3 budget
## applied. With active_only, an unbonded item's magic is left out.
static func mods(item: Dictionary, active_only := false) -> Array:
	ensure()
	var out: Array = []
	var part := _part(item)
	var base_mods: Dictionary = row(String(item.get("base", ""))).get("mods", {})
	var mat: Dictionary = {}
	var qual: Dictionary = {}
	if part != "":
		mat = (_materials.get(String(item.get("material", "")), {}).get(part, {}).get("mods", {}) as Dictionary).duplicate(true)
		qual = (_quality.get(String(item.get("quality", "")), {}).get(part, {}).get("mods", {}) as Dictionary).duplicate(true)
	var magic: Dictionary = {}
	if item.has("magic") and (not active_only or magic_active(item)):
		magic = magic_part(item)["mods"]
	# The budget: attack (weapons) and ac (everything) from material + quality + magic <= BUDGET.
	for key: String in ["attack", "ac"]:
		var room := maxi(0, BUDGET - int(magic.get(key, 0)))
		var q := int(qual.get(key, 0))
		var m := int(mat.get(key, 0))
		if q + m > room:
			q = clampi(room - m, mini(q, 0), q)
			if q + m > room:
				m = room - q
			_set_or_erase(qual, key, q)
			_set_or_erase(mat, key, m)
		if int(magic.get(key, 0)) > BUDGET:
			magic[key] = BUDGET
	for m: Dictionary in [base_mods, mat, qual]:
		if not m.is_empty():
			out.append(m)
	for a: Variant in item.get("affixes", []):
		var am: Dictionary = affix_row(String(a)).get("mods", {})
		if not am.is_empty():
			out.append(_resolve_same(am.duplicate(true), item))
	if not magic.is_empty():
		out.append(_resolve_same(magic, item))
	return out

static func _set_or_erase(d: Dictionary, k: String, v: int) -> void:
	if v == 0:
		d.erase(k)
	else:
		d[k] = v

## extra_damage of type "same" (Vicious Weapon) takes the base weapon's damage type.
static func _resolve_same(m: Dictionary, item: Dictionary) -> Dictionary:
	if m.has("extra_damage") and String(m["extra_damage"].get("type", "")) == "same":
		m["extra_damage"]["type"] = String(row(String(item.get("base", ""))).get("damage_type", "bludgeoning"))
	return m

## Bonus to attack rolls (x) and AC (y) the item's mods add up to: the +3 budget's measure.
static func budget_of(item: Dictionary) -> Vector2i:
	var v := Vector2i.ZERO
	for m: Dictionary in mods(item):
		v.x += int(m.get("attack", 0))
		v.y += int(m.get("ac", 0))
	return v

## Game effects of the item for other systems (summed): material, quality, affixes, and the
## magic's when active.
static func tags(item: Dictionary) -> Dictionary:
	ensure()
	var out := {}
	var part := _part(item)
	if part != "":
		_add_tags(out, _materials.get(String(item.get("material", "")), {}).get(part, {}).get("tags", {}))
		_add_tags(out, _quality.get(String(item.get("quality", "")), {}).get(part, {}).get("tags", {}))
	for a: Variant in item.get("affixes", []):
		_add_tags(out, affix_row(String(a)).get("tags", {}))
	if magic_active(item):
		_add_tags(out, magic_part(item)["tags"])
	return out

static func _add_tags(out: Dictionary, t: Dictionary) -> void:
	for k: String in t:
		out[k] = float(out.get(k, 0.0)) + float(t[k])

## Sum several tag dictionaries.
static func merge_tags(dicts: Array) -> Dictionary:
	var out := {}
	for t: Dictionary in dicts:
		_add_tags(out, t)
	return out

## What using it does: {heal: "2d4+2"} for potions; {} if it cannot be used.
static func use_of(item: Dictionary) -> Dictionary:
	if item.has("magic"):
		return magic_part(item).get("use", {})
	return row(String(item.get("base", ""))).get("use", {})

## Value in coin (GP) of one of it.
static func value(item: Dictionary) -> int:
	var r := row(String(item.get("base", "")))
	var v := float(r.get("value", 0))
	var mat: Dictionary = _materials.get(String(item.get("material", "")), {})
	var q: Dictionary = _quality.get(String(item.get("quality", "")), {})
	v *= float(mat.get("value", 1.0)) * float(q.get("value", 1.0))
	v *= 1.0 + 0.5 * (item.get("affixes", []) as Array).size()
	if item.has("magic") and String(r.get("kind", "")) in ["weapon", "armor", "shield"]:
		var e := magic_entry(String(item["magic"]))
		v += SRDItems.value_of(rarity_of(String(item["magic"]), int(item.get("tier", 0))), bool(e.get("consumable", false)))
	elif item.has("magic"):
		var e2 := magic_entry(String(item["magic"]))
		v = SRDItems.value_of(rarity_of(String(item["magic"]), int(item.get("tier", 0))), bool(e2.get("consumable", false)))
	return roundi(v)

## Weight (lb) of one of it.
static func weight(item: Dictionary) -> float:
	var w := float(row(String(item.get("base", ""))).get("weight", 0))
	w *= float(_materials.get(String(item.get("material", "")), {}).get("weight_mult", 1.0))
	w *= float(_quality.get(String(item.get("quality", "")), {}).get("weight_mult", 1.0))
	w *= maxf(0.1, 1.0 + float(tags(item).get("weight_mult", 0.0)))
	return w

## The record's display name ("Fine Iron Longsword of Embers"): ItemGen.name.
static func display_name(item: Dictionary) -> String:
	return ItemGen.name(item)
