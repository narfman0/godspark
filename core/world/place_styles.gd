## Settlement styles and building templates from data/places/ (styles.json, buildings.json,
## kits.json): which style a culture builds in, its palette of tiles, roof shape, skin kit and
## plan, and the parsed templates. Read-only after ensure(); see docs/tracks/places.md.
##
##   PlaceStyles.style_name("gnome")   # "halfling"
##   PlaceStyles.style("dwarf")        # {palette ids, roof, tall, kit, plan}
##   PlaceStyles.template("home")      # {name, kind, w, h, cells, roof, pieces}
class_name PlaceStyles
extends RefCounted

const DIR := "res://data/places/"
const TIERS := ["hamlet", "village", "town", "city"]

static var _loaded := false
static var _styles := {}       ## name -> style (palette resolved to ids)
static var _cultures := {}
static var _default := "human"
static var _templates := {}    ## name -> parsed template
static var _by_kind := {}      ## kind -> [template names]
static var _plans := {}
static var _kits := {}         ## kit name -> {role: dressing name, ...}
static var gap := Vector2i(3, 5)

static func ensure() -> void:
	if _loaded:
		return
	_loaded = true
	TileDefs.ensure()
	var s: Dictionary = _json("styles.json")
	_cultures = s.get("cultures", {})
	_default = String(s.get("default", "human"))
	_plans = s.get("plans", {})
	var g: Array = s.get("gap", [3, 5])
	gap = Vector2i(int(g[0]), int(g[1]))
	for n: String in s.get("styles", {}):
		var d: Dictionary = (s["styles"][n] as Dictionary).duplicate(true)
		var pal := {}
		var raw: Dictionary = d["palette"]
		for role: String in raw:
			pal[role] = TileDefs.wall_id(raw[role]) if role == "back" else TileDefs.id(raw[role])
		d["ids"] = pal
		d["name"] = n
		_styles[n] = d
	var b: Dictionary = _json("buildings.json")
	for n: String in b.get("templates", {}):
		var t := _parse(n, b["templates"][n])
		_templates[n] = t
		if not _by_kind.has(t["kind"]):
			_by_kind[t["kind"]] = []
		_by_kind[t["kind"]].append(n)
	var k: Variant = _json("kits.json")
	if k is Dictionary:
		_kits = k.get("kits", {})

static func _json(file: String) -> Variant:
	var path := DIR + file
	if not FileAccess.file_exists(path):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}

## Template: cells is a PackedByteArray of legend chars, index dx + dy * w with dy = 0 the
## feet row (bottom of the body). anchors {role: [Vector2i]}, door Vector2i (or -1, -1).
static func _parse(n: String, d: Dictionary) -> Dictionary:
	var rows: Array = d["rows"]
	var h := rows.size()
	var w := String(rows[0]).length()
	var cells := PackedByteArray()
	cells.resize(w * h)
	var anchors := {}
	var door := Vector2i(-1, -1)
	for r in h:
		var line := String(rows[r])
		assert(line.length() == w, "template %s: ragged row %d" % [n, r])
		var dy := h - 1 - r
		for dx in w:
			var ch := line.unicode_at(dx)
			cells[dx + dy * w] = ch
			var role := ROLES.get(char(ch).to_lower(), "") as String
			if role != "":
				if not anchors.has(role):
					anchors[role] = []
				anchors[role].append(Vector2i(dx, dy))
			if ch == 68:   # 'D'
				door = Vector2i(dx, dy)
	return {"name": n, "kind": String(d.get("kind", "home")), "w": w, "h": h, "cells": cells,
		"anchors": anchors, "door": door, "roof": bool(d.get("roof", true)), "pieces": d.get("pieces", [])}

const ROLES := {"s": "smith", "m": "merchant", "k": "keeper", "p": "priest", "g": "guard", "t": "townsfolk"}

static func style_name(culture: String) -> String:
	ensure()
	return String(_cultures.get(culture, _default))

static func style(culture_or_style: String) -> Dictionary:
	ensure()
	if _styles.has(culture_or_style):
		return _styles[culture_or_style]
	return _styles[style_name(culture_or_style)]

static func template(n: String) -> Dictionary:
	ensure()
	return _templates.get(n, {})

static func templates_of(kind: String) -> Array:
	ensure()
	return _by_kind.get(kind, [])

static func plan(n: String) -> Dictionary:
	ensure()
	return _plans.get(n, _plans.get("town", {}))

static func tier_index(t: String) -> int:
	return TIERS.find(t)

## The dressing name a kit uses for a role ("" when it has none).
static func kit_piece(kit: String, role: String) -> String:
	ensure()
	var k: Dictionary = _kits.get(kit, {})
	if k.has(role):
		return String(k[role])
	var base := String(k.get("_base", ""))
	return kit_piece(base, role) if base != "" and base != kit else ""

static func kit(n: String) -> Dictionary:
	ensure()
	return _kits.get(n, {})
