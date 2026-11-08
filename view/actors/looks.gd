## Creature look -> body plan, from data/looks.json (the one looks table) and
## data/looks_creatures.json (size, type, body plan of every SRD monster slug).
## Pure: it only decides; ActorBody builds. The order, first that is available wins:
##
##   1. a row (slug, people or player key; keys drop their last ":" part until one matches),
##      naming a Synty model whose files are there                         body = "synty"
##   2. monster-forge: look.slug is synced in assets/monsters/<slug>       body = "forge"
##   3. by_type for the slug's creature type, a Synty model                body = "synty"
##   4. a tinted primitive with a nameplate                                body = "primitive"
##
## Keep Synty as much as possible; the forge only replaces the others (the user's ruling,
## 2026-11-08, docs/plan.md "Decisions"). So a slug with its OWN Synty row keeps it, and the
## forge body stands for it only when the Synty files are missing. The forge body comes first
## (2 before 1) for a slug with no row of its own (one that would reach by_type, by_size or a
## primitive) and for the few in looks.json forge.forge_first, stand-ins that are plainly wrong
## (the goat lying on its side, a brown polar bear: reason given per slug).
## A player look, or a people look of a humanoid (a forge.person_types type), never takes a
## forge body (a giant spider in a drow escort carries a people key and still gets its spider).
## A slug in data/forge_quarantine.json, or a look with no_forge = true (ActorBody, after a
## forge body failed to load), skips the forge link.
##
## look keys (all optional): slug ("goblin-warrior"), people ("human:guard" or
## "people:human:guard"), player ("fighter" or "player:fighter"), key (any row key), name,
## size (Vector2 tiles: the collision box), size_name ("medium"), type ("beast"), color,
## tint, scale, height_m, nameplate. The original {kind, size, color} form is a primitive.
## Rows may set size_name too (people:goblin is small), used when the look has no slug.
##
##   var plan := Looks.resolve({"people": "elf:drow:raider"})
##   plan.body, plan.model_def, plan.size, plan.height_m, plan.tint, plan.color, plan.name
##
## has_file decides what exists (tests pass a fake); by default FileAccess.
class_name Looks
extends RefCounted

const FILE := "res://data/looks.json"
const CREATURES := "res://data/looks_creatures.json"
const QUARANTINE := "res://data/forge_quarantine.json"
const SIZES := ["tiny", "small", "medium", "large", "huge", "gargantuan"]

static var _table := {}
static var _creatures := {}
static var _quarantine := {}
static var _quarantine_read := false

static func table() -> Dictionary:
	if _table.is_empty():
		var t = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		_table = t if t is Dictionary else {"looks": {}, "models": {}, "clips": {}}
		var ref: String = _table.get("clips", {}).get("ref", "")
		if ref != "":
			AnimRetarget.ref_character = ref
	return _table

static func creatures() -> Dictionary:
	if _creatures.is_empty():
		var c = JSON.parse_string(FileAccess.get_file_as_string(CREATURES))
		_creatures = c.get("creatures", {}) if c is Dictionary else {}
	return _creatures

## slug -> reason: forge monsters known bad today (data/forge_quarantine.json).
static func quarantine() -> Dictionary:
	if not _quarantine_read:
		_quarantine_read = true
		var q = JSON.parse_string(FileAccess.get_file_as_string(QUARANTINE)) if FileAccess.file_exists(QUARANTINE) else null
		_quarantine = q.get("monsters", {}) if q is Dictionary and q.get("monsters", {}) is Dictionary else {}
	return _quarantine

## Whether a forge body may stand for this look at all (synced or not), and whether Synty
## comes first for it. Pure on the table: [forge_allowed, synty_first].
static func forge_rule(look: Dictionary, slug: String, ctype: String) -> Array:
	var f: Dictionary = table().get("forge", {})
	var person: bool = ctype in f.get("person_types", [])
	if slug == "" or look.has("player") or (look.has("people") and person) or bool(look.get("no_forge", false)):
		return [false, false]
	if quarantine().has(slug) or not creatures().has(slug):
		return [false, false]
	var own_row: bool = table().get("looks", {}).has(slug)
	return [true, own_row and not f.get("forge_first", {}).has(slug)]

## Keys to try for a look, most specific first.
static func keys_for(look: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if look.has("key"):
		_chain(String(look["key"]), out)
	if look.has("slug"):
		out.append(String(look["slug"]))
	if look.has("people"):
		var p := String(look["people"])
		_chain(p if p.begins_with("people:") else "people:" + p, out)
	if look.has("player"):
		var c := String(look["player"])
		_chain(c if c.begins_with("player") else "player:" + c, out)
	return out

static func _chain(key: String, out: PackedStringArray) -> void:
	var parts := key.split(":")
	for n in range(parts.size(), 0, -1):
		var k := ":".join(parts.slice(0, n))
		if k == "people":
			continue
		if not k in out:
			out.append(k)

static func _default_has(path: String) -> bool:
	return FileAccess.file_exists(path)

static func resolve(look: Dictionary, has_file: Callable = Callable()) -> Dictionary:
	if not has_file.is_valid():
		has_file = _default_has
	var t := table()
	var rows: Dictionary = t.get("looks", {})
	var slug := String(look.get("slug", ""))
	var meta: Dictionary = creatures().get(slug, {}) if slug != "" else {}
	var plan := {"body": "primitive", "slug": slug, "key": "", "model": "", "model_def": {},
		"forge_dir": "", "nameplate": false}
	# The row
	var row := {}
	for k in keys_for(look):
		if rows.has(k):
			row = rows[k]
			plan["key"] = k
			break
	# Size and type
	var size_name := String(look.get("size_name", meta.get("size", row.get("size_name", "medium"))))
	if not size_name in SIZES:
		size_name = "medium"
	var by_size: Dictionary = t.get("by_size", {}).get(size_name, {})
	var size: Vector2 = look.get("size", Vector2.ZERO)
	if size == Vector2.ZERO:
		var s: Array = by_size.get("size", [1.5, 2.5])
		size = Vector2(s[0], s[1])
	plan["size"] = size
	plan["size_name"] = size_name
	var ctype := String(look.get("type", meta.get("type", "")))
	plan["type"] = ctype
	plan["plan"] = String(meta.get("plan", ""))
	var type_row: Dictionary = t.get("by_type", {}).get(ctype, {})
	var dflt: Dictionary = t.get("default", {})
	# Name: explicit, the SRD name, the row key's last part, or the old "kind"
	var nm := String(look.get("name", meta.get("name", "")))
	if nm == "" and plan["key"] != "":
		nm = String(plan["key"]).get_slice(":", String(plan["key"]).get_slice_count(":") - 1).capitalize()
	if nm == "":
		nm = String(look.get("kind", ""))
	plan["name"] = nm
	var tint := _color(look.get("tint", row.get("tint", null)), Color.WHITE)
	plan["tint"] = tint
	plan["scale"] = float(look.get("scale", 1.0)) * float(row.get("scale", 1.0))
	# monster-forge: before Synty for a slug with no row of its own (or forge_first), after it otherwise
	var rule := forge_rule(look, slug, ctype)
	var forge: bool = rule[0] and has_file.call("res://assets/monsters/%s/monster.json" % slug)
	if forge and not rule[1]:
		return _forge_plan(plan, look, slug)
	# Synty model from the row, else from the creature type
	var model_key := String(row.get("model", ""))
	var from_type := false
	if model_key == "" and row.is_empty():
		model_key = String(type_row.get("model", ""))
		from_type = model_key != ""
		if from_type and not look.has("tint") and type_row.has("tint"):
			tint = _color(type_row["tint"], Color.WHITE)
			plan["tint"] = tint
	var def: Dictionary = t.get("models", {}).get(model_key, {})
	# Primitive colour: explicit, the row's, the type's, the default; a row tint shades it.
	var col := _color(look.get("color", row.get("color", type_row.get("color", dflt.get("color", "#a0a0a0")))), Color(0.63, 0.63, 0.63))
	if row.has("tint") and not look.has("color"):
		col *= tint
	plan["color"] = col
	if not def.is_empty() and _model_available(def, t, has_file):
		plan["body"] = "synty"
		plan["model"] = model_key
		plan["model_def"] = def
		var h := float(look.get("height_m", row.get("height_m", def.get("height_m", by_size.get("height_m", 1.8)))))
		plan["height_m"] = h * float(plan["scale"])
		plan["nameplate"] = bool(look.get("nameplate", row.get("nameplate", from_type or type_row.get("nameplate", false))))
		return plan
	if forge:
		return _forge_plan(plan, look, slug)
	# primitive
	plan["height_m"] = size.y * K.TILE_M
	plan["nameplate"] = bool(look.get("nameplate", nm != ""))
	return plan

static func _forge_plan(plan: Dictionary, look: Dictionary, slug: String) -> Dictionary:
	plan["body"] = "forge"
	plan["forge_dir"] = "res://assets/monsters/" + slug
	plan["nameplate"] = bool(look.get("nameplate", false))
	plan["height_m"] = 0.0
	plan["color"] = _color(look.get("color", null), Color.WHITE)
	# A row's tint and scale dress its Synty stand-in; the forge body is the creature itself.
	plan["tint"] = _color(look.get("tint", null), Color.WHITE)
	plan["scale"] = float(look.get("scale", 1.0))
	plan["model"] = ""
	plan["model_def"] = {}
	return plan

## A model counts as available when its file is there and, for humanoids, the reference
## character and the idle clip of its set are too (else it would stand in a T-pose).
static func _model_available(def: Dictionary, t: Dictionary, has_file: Callable) -> bool:
	if not has_file.call(String(def.get("path", ""))):
		return false
	var rig_set := String(def.get("set", ""))
	if rig_set == "":
		return true
	var clips: Dictionary = t.get("clips", {})
	return has_file.call(String(clips.get("ref", ""))) and has_file.call(String(clips.get(rig_set, {}).get("idle", "")))

## The row of an SRD weapon (slug, or a shown name: "War Pick"), {} when it has none.
static func weapon(what: String) -> Dictionary:
	return table().get("weapons", {}).get("rows", {}).get(what.strip_edges().to_lower().replace(" ", "-"), {})

static func _color(v: Variant, fallback: Color) -> Color:
	if v is Color:
		return v
	if v is String and String(v) != "":
		return Color.from_string(v, fallback)
	return fallback

## Every res:// asset path the table names (models and clips), for tests and tools.
static func all_paths() -> PackedStringArray:
	var out := PackedStringArray()
	var t := table()
	for m: Dictionary in t.get("models", {}).values():
		out.append(String(m.get("path", "")))
	var clips: Dictionary = t.get("clips", {})
	for k: String in clips:
		if clips[k] is String:
			out.append(clips[k])
		elif clips[k] is Dictionary:
			for p in (clips[k] as Dictionary).values():
				out.append(String(p))
	for p: Variant in t.get("swings", {}).get("clips", {}).values():
		out.append(String(p))
	for r: Dictionary in t.get("weapons", {}).get("rows", {}).values():
		out.append(String(r.get("path", "")))
	return out
