## Lays out settlements and turns their lots into tile writes. Pure: it plans from a site and
## produces writes; worldgen (stage_places.gd) and the host (PlaceKeeper) apply them.
##
## A place (meta.places["<site id>"], JSON-safe):
##   {site, rect: [x, y, w, h], culture, style, tier, street: [x0, x1, y], seed,
##    lots: [{tpl, kind, x, w, h, tier, state}], buildings: [...]}   (Places contract)
##   lot.tier: the lowest settlement tier the lot is built at; lot.state: empty | built | ruin
##   tier "" means a laid-out site nobody lives on yet (no buildings).
## The street is the feet row y from x0 to x1; every building stands on it with doorways
## at both ends, so the street runs through ground floors and stays walkable end to end.
##
##   var place := PlaceBuilder.plan(site, "human", seed, left_limit, right_limit)
##   var w := PlaceBuilder.lot_writes(place, i, "built")   # {cells: PackedInt32Array (x, y, fg, bg), objects: [[id, x, y, v]]}
class_name PlaceBuilder
extends RefCounted

const KEEP := -1

## Plan a place for a site: lots outward from the centre, inside [lo, hi] (inclusive
## columns). Every lot of the plan is listed; tier decides which are built.
static func plan(site: Dictionary, culture: String, world_seed: int, lo: int, hi: int) -> Dictionary:
	PlaceStyles.ensure()
	var st := PlaceStyles.style(culture)
	var pl := PlaceStyles.plan(String(st.get("plan", "town")))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, "place", int(site["id"])])
	var y := int(site["y"])
	var cx := int(site["x"])
	var gap_min := maxi(PlaceStyles.gap.x, 2 * int(st["roof"].get("overhang", 0)) + 1)
	var lots: Array = []
	# The centre lot: its template changes with the tier (square, then market).
	var centre: Dictionary = pl.get("centre", {"hamlet": "square"})
	var c_tpl := PlaceStyles.template(String(centre.get("hamlet", "square")))
	var cw := int(c_tpl["w"])
	var c_x0 := cx - cw / 2
	if c_x0 < lo or c_x0 + cw - 1 > hi:
		return {}
	lots.append(_lot(String(centre.get("hamlet", "square")), "hamlet", c_x0, centre))
	var left := c_x0           # next free column going left is left - gap - w
	var right := c_x0 + cw     # next lot starts at right + gap
	# Reserve room for the end gates.
	var gates: Array = pl.get("gates", [null, null])
	var gate_t := PlaceStyles.template("gate")
	var gw := int(gate_t["w"]) + gap_min
	var lo_in := lo + (gw if gates[0] != null else 0)
	var hi_in := hi - (gw if gates[1] != null else 0)
	var pending: Array = []     # alternatives not picked, for "other"
	var side := 1
	for entry: Array in pl.get("lots", []):
		var what := String(entry[0])
		var tier := String(entry[1])
		if what == "home?":
			what = "home"
			if rng.randf() < 0.5:
				tier = PlaceStyles.TIERS[mini(PlaceStyles.tier_index(tier) + 1, 3)]
		elif what.contains("|"):
			var alts := what.split("|")
			var k := rng.randi_range(0, alts.size() - 1)
			what = alts[k]
			for j in alts.size():
				if j != k:
					pending.append(alts[j])
		elif what == "other":
			if pending.is_empty():
				continue
			what = pending.pop_front()
		var tpl_name := _pick_template(what, tier, st, rng)
		if tpl_name == "":
			continue
		var w := int(PlaceStyles.template(tpl_name)["w"])
		var g := rng.randi_range(gap_min, maxi(gap_min, PlaceStyles.gap.y))
		for attempt in 2:
			var s := side if attempt == 0 else -side
			if s > 0 and right + g + w - 1 <= hi_in:
				lots.append(_lot(tpl_name, tier, right + g))
				right += g + w
				break
			elif s < 0 and left - g - w >= lo_in:
				lots.append(_lot(tpl_name, tier, left - g - w))
				left -= g + w
				break
		side = -side   # a lot that fits on neither side is left out; smaller ones may still fit
	if gates[0] != null and left - gap_min - int(gate_t["w"]) >= lo:
		left -= gap_min + int(gate_t["w"])
		lots.append(_lot("gate", String(gates[0]), left))
	if gates[1] != null and right + gap_min + int(gate_t["w"]) - 1 <= hi:
		lots.append(_lot("gate", String(gates[1]), right + gap_min))
		right += gap_min + int(gate_t["w"])
	var x0 := left - 2
	var x1 := right + 1
	var top := 0
	for lot: Dictionary in lots:
		top = maxi(top, int(lot["h"]) + roof_height(st, PlaceStyles.template(lot["tpl"])))
	return {"site": int(site["id"]), "rect": [x0, y, x1 - x0 + 1, top], "culture": culture,
		"style": String(st["name"]), "tier": "", "street": [x0, x1, y], "lots": lots, "buildings": []}

static func _lot(tpl_name: String, tier: String, x: int, by_tier := {}) -> Dictionary:
	var t := PlaceStyles.template(tpl_name)
	var lot := {"tpl": tpl_name, "kind": t["kind"], "x": x, "w": t["w"], "h": t["h"], "tier": tier, "state": "empty"}
	if not by_tier.is_empty():
		lot["by_tier"] = by_tier.duplicate()
	return lot

## A template for a kind: two-storey variants only on town and city lots, with the style's
## chance.
static func _pick_template(kind: String, tier: String, st: Dictionary, rng: RandomNumberGenerator) -> String:
	var names: Array = PlaceStyles.templates_of(kind)
	if PlaceStyles.template(kind).is_empty() and names.is_empty():
		return ""
	var plain: Array = []
	var tall: Array = []
	for n: String in names:
		if n == "square" or n == "market":
			continue
		if n.ends_with("_tall"):
			tall.append(n)
		else:
			plain.append(n)
	var roll := rng.randf()
	if PlaceStyles.tier_index(tier) >= 2 and not tall.is_empty() and roll < float(st.get("tall", 0.0)):
		return tall[0]
	return plain[0] if not plain.is_empty() else (tall[0] if not tall.is_empty() else "")

## The template a lot shows at a tier (the centre lot changes from square to market).
static func lot_template(lot: Dictionary, tier: String) -> String:
	var by: Dictionary = lot.get("by_tier", {})
	if by.is_empty():
		return String(lot["tpl"])
	var best := String(lot["tpl"])
	var ti := PlaceStyles.tier_index(tier)
	var top := -1
	for t: String in by:
		var k := PlaceStyles.tier_index(t)
		if k <= ti and k > top:
			top = k
			best = String(by[t])
	return best

static func roof_height(st: Dictionary, t: Dictionary) -> int:
	if not t.get("roof", true):
		return 0
	var r: Dictionary = st["roof"]
	match String(r.get("shape", "gable")):
		"flat":
			return 1
		_:
			var step := maxi(1, int(r.get("step", 1)))
			var span := int(t["w"]) + 2 * int(r.get("overhang", 0))
			return (span + 2 * step - 1) / (2 * step)

## The template lot i stands as (or would be built as) at the place's tier.
static func shown(place: Dictionary, i: int) -> String:
	var lot: Dictionary = place["lots"][i]
	if lot.has("shown"):
		return String(lot["shown"])
	var tier := String(place.get("tier", ""))
	return lot_template(lot, tier if tier != "" else "hamlet")

## What the lot should be at a tier: built if the tier reaches it, else empty.
static func lot_wanted(lot: Dictionary, tier: String) -> bool:
	if tier == "":
		return false
	return PlaceStyles.tier_index(String(lot["tier"])) <= PlaceStyles.tier_index(tier)

# --- writes -----------------------------------------------------------------------------

## Tile writes and dressing for lot i of a place in a state ("built" or "ruin"), using the
## place's style. cells: flat (x, y, fg, bg) with KEEP (-1) for a layer left alone.
static func lot_writes(place: Dictionary, i: int, state: String, world_seed := 0) -> Dictionary:
	var lot: Dictionary = place["lots"][i]
	var st := PlaceStyles.style(String(place["style"]))
	var tpl_name := shown(place, i)
	var t := PlaceStyles.template(tpl_name)
	var pal: Dictionary = st["ids"]
	var x0 := int(lot["x"])
	var y0 := int(place["street"][2])
	var w := int(t["w"])
	var h := int(t["h"])
	var cells := PackedInt32Array()
	var objects: Array = []
	var back := int(pal["back"])
	var cs: PackedByteArray = t["cells"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, "ruin", int(place["site"]), i])
	var ruin := state == "ruin"
	var building: bool = bool(t.get("roof", true)) or tpl_name == "gate"
	# Foundation (or street) under the lot.
	for dx in w:
		_put(cells, x0 + dx, y0 - 1, pal["base"] if building else pal["street"], KEEP)
	var keep_bg := PackedInt32Array()   # ruin: back wall kept up to this row per column
	if ruin:
		keep_bg.resize(w)
		for dx in w:
			keep_bg[dx] = rng.randi_range(1, maxi(1, mini(h - 2, 5)))
	for dy in h:
		for dx in w:
			var ch := char(cs[dx + dy * w])
			var fb := _legend(ch, pal, back)
			var fg: int = fb[0]
			var bg: int = fb[1]
			if ruin:
				fg = TileDefs.AIR
				if bg != KEEP:
					bg = back if dy < keep_bg[dx] else 0
			_put(cells, x0 + dx, y0 + dy, fg, bg)
	if ruin and building:
		# The skin: a broken wall at the back and a rubble heap; rubble tiles between them,
		# one tile high, so a walker steps over them (the street stays open).
		var kit := String(st.get("kit", ""))
		var rw := Dressing.id(PlaceStyles.kit_piece(kit, "ruin_wall"))
		var rr := Dressing.id(PlaceStyles.kit_piece(kit, "ruin_rubble"))
		if rw >= 0 and w >= 6:
			objects.append([rw, x0 + 1, y0, rng.randi() & 0xff])
		if rr >= 0 and w >= 9:
			objects.append([rr, x0 + w - 4, y0, rng.randi() & 0xff])
		for k in rng.randi_range(1, 2):
			if w >= 11:
				_put(cells, x0 + rng.randi_range(5, w - 5), y0, pal["masonry"], KEEP)
	# Roof.
	if t.get("roof", true):
		var r: Dictionary = st["roof"]
		var shape := String(r.get("shape", "gable"))
		var ytop := y0 + h
		var rid: int = TileDefs.AIR if ruin else int(pal["roof"])
		if shape == "flat":
			for dx in range(0, w, 2):
				_put(cells, x0 + dx, ytop, rid, KEEP)
			_put(cells, x0 + w - 1, ytop, rid, KEEP)
		else:
			var step := maxi(1, int(r.get("step", 1)))
			var ov := int(r.get("overhang", 0))
			var a := x0 - ov
			var b := x0 + w - 1 + ov
			var k := 0
			while a <= b:
				for x in range(a, b + 1):
					_put(cells, x, ytop + k, rid, KEEP)
				a += step
				b -= step
				k += 1
	# Furniture and signs (the kit maps roles to dressing ids; missing ones are skipped).
	if not ruin:
		for p: Array in t.get("pieces", []):
			var dn := PlaceStyles.kit_piece(String(st.get("kit", "")), String(p[0]))
			var id := Dressing.id(dn) if dn != "" else -1
			if id >= 0 and not _fits(t, id, int(p[1]), int(p[2])):
				id = -1   # the piece does not fit in this template
			if id >= 0:
				objects.append([id, x0 + int(p[1]), y0 + int(p[2]), rng.randi() & 0xff])
	return {"cells": cells, "objects": objects}

## A ground piece fits where its footprint cells are open in the template and the row
## under it is solid (a floor, the foundation, or the ground under an open lot).
static func _fits(t: Dictionary, id: int, dx: int, dy: int) -> bool:
	var fp := Dressing.footprint(id)
	var w := int(t["w"])
	var h := int(t["h"])
	var cs: PackedByteArray = t["cells"]
	for i in fp.x:
		var x := dx + i
		if x < 0 or x >= w:
			return false
		if dy > 0 and not char(cs[x + (dy - 1) * w]) in ["=", "+", "#"]:
			return false
		for j in fp.y:
			var y := dy + j
			if y >= h:
				return false
			if char(cs[x + y * w]) in ["=", "+", "#", "-", "^"]:
				return false
	return true

static func _put(cells: PackedInt32Array, x: int, y: int, fg: int, bg: int) -> void:
	cells.append_array(PackedInt32Array([x, y, fg, bg]))

## [fg, bg] for a legend char.
static func _legend(ch: String, pal: Dictionary, back: int) -> Array:
	match ch:
		"#": return [pal["wall"], back]
		"=": return [pal["floor"], back]
		"+": return [pal["masonry"], back]
		"-": return [pal["walk"], back]
		"H": return [TileDefs.id("ladder"), back]
		"*": return [pal["lamp"], back]
		"!": return [pal["lamp"], KEEP]
		"^": return [pal["awning"], KEEP]
		",", "S", "M", "K", "P", "G", "T": return [TileDefs.AIR, KEEP]
		_: return [TileDefs.AIR, back]      # . d D and lowercase anchors

## The Places-contract record of a lot as it stands: {kind, rect, door, anchors}.
static func building_record(place: Dictionary, i: int) -> Dictionary:
	var lot: Dictionary = place["lots"][i]
	var st := PlaceStyles.style(String(place["style"]))
	var t := PlaceStyles.template(shown(place, i))
	var x0 := int(lot["x"])
	var y0 := int(place["street"][2])
	var rec := {"kind": t["kind"], "rect": [x0, y0, int(t["w"]), int(t["h"]) + roof_height(st, t)],
		"door": [x0 + t["door"].x, y0 + t["door"].y] if t["door"].x >= 0 else [x0, y0], "anchors": {}, "lot": i}
	if lot["state"] == "ruin":
		rec["kind"] = "ruin"
		rec["was"] = t["kind"]
		return rec
	var an := {}
	for role: String in t["anchors"]:
		an[role] = []
		for c: Vector2i in t["anchors"][role]:
			an[role].append([x0 + c.x, y0 + c.y])
	if t["kind"] == "home":   # townsfolk also stand at home doors
		if not an.has("townsfolk"):
			an["townsfolk"] = []
		an["townsfolk"].append(rec["door"].duplicate())
	rec["anchors"] = an
	return rec

## Rebuild place.buildings from its lots (built and ruined lots), centre first.
static func refresh_buildings(place: Dictionary) -> void:
	var out: Array = []
	for i in (place["lots"] as Array).size():
		if place["lots"][i]["state"] != "empty":
			out.append(building_record(place, i))
	place["buildings"] = out

## The lots whose state should change to match a tier ("" = abandoned, ruins stay ruins):
## [[lot index, new state]].
static func changes_for(place: Dictionary, tier: String) -> Array:
	var out: Array = []
	for i in (place["lots"] as Array).size():
		var lot: Dictionary = place["lots"][i]
		var want := lot_wanted(lot, tier)
		var s := String(lot["state"])
		if want and (s != "built" or (lot.has("by_tier") and lot_template(lot, tier) != String(lot.get("shown", "")))):
			out.append([i, "built"])
		elif not want and s == "built":
			out.append([i, "ruin"])
	return out

## Set lot i to a state ("built" at the place's tier, or "ruin") and return its writes.
static func set_lot(place: Dictionary, i: int, state: String, world_seed := 0) -> Dictionary:
	var lot: Dictionary = place["lots"][i]
	if state == "built":
		var tier := String(place.get("tier", ""))
		lot["shown"] = lot_template(lot, tier if tier != "" else "hamlet")
	var wr := lot_writes(place, i, state, world_seed)
	lot["state"] = state
	return wr

## Every cell lot i can touch (foundation, body, roof with its overhang), as a Rect2i.
static func lot_rect(place: Dictionary, i: int) -> Rect2i:
	var lot: Dictionary = place["lots"][i]
	var st := PlaceStyles.style(String(place["style"]))
	var t := PlaceStyles.template(shown(place, i))
	var ov := int(st["roof"].get("overhang", 0)) if t.get("roof", true) else 0
	var y0 := int(place["street"][2])
	return Rect2i(int(lot["x"]) - ov, y0 - 1, int(t["w"]) + 2 * ov, int(t["h"]) + roof_height(st, t) + 1)
