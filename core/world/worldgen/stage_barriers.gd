## Natural barriers: mountain ranges and rivers (data/worldgen/barriers.json).
##
## The world is a side view, so a surface is one line: nothing goes around anything. A range
## is a barrier because that line is broken by cliffs no body can climb, and a pass is the
## walkable way left through them.
##
## Stage "surface" plans them, since they shape the ground:
##   plan_ranges   a crest in each mountain stretch, and a level shelf for each mouth of its
##                 under-route; towns keep off them (c.reserved).
##   plan_rivers   a channel in the wet biomes on ground held level for its banks.
##   raise         the mountain as it stands is the pass (step 1, walked without jumping):
##                 it is recorded (c.pass_y), then cliffed walls are stood on it, and the
##                 river channels are cut into the ground.
## The caves stay under rock_top, so the walls stay solid and only the pass runs through them,
## and the passages stage leaves what stands on the walls alone: the walls are not climbed.
## Stage "barriers" (after the caves) builds what crosses them:
##   the pass      paved, cut through the walls: a thin roof goes, a thick one stays, a gallery.
##   the under-route  a tunnel from a mouth on one side down under the range and up to a mouth
##                 on the other, one row per column at most, floored with treads and planks
##                 where it crosses a cave.
##   rivers        bed sealed against the caves, water laid, and the crossing: a bridge over
##                 deep water, or a ford (one tile of water). The banks slope a row a column,
##                 so nobody is stuck in a channel, and swimming is not needed.
## Roads follow crossings (stage_roads.gd), and a route's length grows by a cost for each one
## (crossings, cost), so the sim feels them. River tiles are in the range the passages stage
## never cuts.
extends RefCounted

const GenContext := preload("gen_context.gd")
const Deeps := preload("stage_deeps.gd")
const PATH := "res://data/worldgen/barriers.json"

## c.reserved: columns only barriers use (no towns, ruins, cave entrances or ramp mouths).
const RESERVED := 1
## Rows over a pass's floor that still count as the pass; a spot higher is on the range's rock.
const PASS_CLEAR := 8

static var _data := {}

static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _data

static func enabled(c: GenContext) -> bool:
	return c.w >= int(data()["min_world"]) and String(c.opts.get("only_biome", "")) == ""

## The top of the rock a cave may run under in column x: over a pass, the pass, so the peaks
## stay solid and only the pass runs through them.
static func rock_top(c: GenContext, x: int) -> int:
	return c.pass_y[x] - 1 if c.pass_y[x] >= 0 else c.ground[x]

static func _rnd(rng: RandomNumberGenerator, pair: Array) -> int:
	return rng.randi_range(int(pair[0]), int(pair[1]))

static func reserve(c: GenContext, x0: int, x1: int) -> void:
	for x in range(maxi(0, x0), mini(c.w - 1, x1) + 1):
		c.reserved[x] = RESERVED

## Is any column of x0..x1 reserved?
static func reserved_in(c: GenContext, x0: int, x1: int) -> bool:
	for x in range(maxi(0, x0), mini(c.w - 1, x1) + 1):
		if c.reserved[x] != 0:
			return true
	return false

# --- planned by stage "surface" -----------------------------------------------------------

## A crest in each inland mountain stretch, and where its under-route comes up. raw: the heights
## so far.
static func plan_ranges(c: GenContext, rng: RandomNumberGenerator, raw: PackedFloat32Array, blend: float) -> void:
	c.ranges = []
	if not enabled(c):
		return
	var d: Dictionary = data()["range"]
	var u: Dictionary = data()["under"]
	var shelf := int(u["shelf"])
	for i in c.biomes.size():
		var seg: Dictionary = c.biomes[i]
		if seg["biome"] != "mountain" or i == 0 or i == c.biomes.size() - 1:
			continue                     # a range stands between neighbours
		var sx0 := int(seg["x0"])
		var span := int(seg["x1"]) - sx0 + 1
		var n := maxi(1, span / int(d["range_every"]))
		var cw := clampi(int(c.w * float(d["crest_share"])), int(d["crest"][0]), int(d["crest"][1]))
		for k in n:
			var slack := maxi(0, span / n - cw) / 4
			var mid := sx0 + span * (2 * k + 1) / (2 * n) + rng.randi_range(-slack, slack)
			var x0 := mid - cw / 2
			var rg := {"id": c.ranges.size(), "x0": x0, "x1": x0 + cw - 1, "walls": _walls(x0, cw, rng, d)}
			rg["mouths"] = [_mouth(raw, x0 - int(d["margin"]), -1, u), _mouth(raw, int(rg["x1"]) + int(d["margin"]), 1, u)]
			c.ranges.append(rg)
			reserve(c, x0 - int(d["margin"]), int(rg["x1"]) + int(d["margin"]))
			for m: int in rg["mouths"]:
				reserve(c, m - shelf - int(blend), m + shelf + int(blend))

## raw is held level on a shelf at each mouth of an under-route: the road passes there, and a
## road cut into a ridge would leave a mouth hanging. Returns the columns to hold, [x0, x1]
## pairs. Call after the flats are placed.
static func plan_shelves(c: GenContext, raw: PackedFloat32Array, blend: float) -> Array:
	var held: Array = []
	var shelf := int(data()["under"]["shelf"]) if enabled(c) else 0
	for rg: Dictionary in c.ranges:
		for m: int in rg["mouths"]:
			var level := 0.0
			for x in range(m - shelf, m + shelf + 1):
				level += raw[x]
			_hold(raw, m - shelf, m + shelf, blend, _near_town(c, roundf(level / (2 * shelf + 1)), m - shelf, m + shelf))
			held.append([m - shelf, m + shelf])
	return held

## This level, or the nearest to it that a road from a town can reach at a walk: two held
## stretches closer than their heights differ would leave a cliff between them.
static func _near_town(c: GenContext, level: float, x0: int, x1: int) -> float:
	for f: Dictionary in c.flats:
		var gap := maxi(int(f["x0"]) - x1, x0 - int(f["x1"]))
		if gap < 240:
			level = clampf(level, float(f["y"]) - gap / 2, float(f["y"]) + gap / 2)
	return level

## Hold raw level over x0..x1 and ease it back to the ground over blend columns.
static func _hold(raw: PackedFloat32Array, x0: int, x1: int, blend: float, level: float) -> void:
	for x in range(maxi(0, x0 - int(blend)), mini(raw.size() - 1, x1 + int(blend)) + 1):
		var e := maxf(x0 - x, x - x1)
		raw[x] = level if e <= 0 else lerpf(level, raw[x], smoothstep(0.0, 1.0, e / blend))

## The mouth of an under-route, searching from start away from the crest (dir): the nearest
## column where the ground does not fall away into the way the tunnel goes.
static func _mouth(raw: PackedFloat32Array, start: int, dir: int, u: Dictionary) -> int:
	var best := start
	var best_cover := -INF
	for k in range(0, int(u["search"]), 4):
		var x := start + dir * k
		if x < 32 or x >= raw.size() - 32:
			break
		var cover := INF
		for j in range(4, 40, 4):       # rows of rock over a tunnel falling a row a column
			var q := x - dir * j
			cover = minf(cover, raw[q] - (raw[x] - j) - mini(j, 8))
		if cover >= 0.0:
			return x
		if cover > best_cover:
			best_cover = cover
			best = x
	return best

static func _walls(x0: int, cw: int, rng: RandomNumberGenerator, d: Dictionary) -> Array:
	var n := clampi(roundi(float(cw) / float(d["walls_per"])), int(d["walls"][0]), int(d["walls"][1]))
	var slot := cw / n
	var out: Array = []
	for i in n:
		var hw := int(slot * 0.5 * rng.randf_range(float(d["wall_w"][0]), float(d["wall_w"][1])))
		var room := maxi(0, slot / 2 - hw)
		var cx := x0 + slot * i + slot / 2 + rng.randi_range(-room, room)
		out.append({"x": cx, "hw": hw, "terrace": _rnd(rng, d["terrace"]),
			"h": clampi(int(hw * rng.randf_range(float(d["height"][0]), float(d["height"][1]))), int(d["wall_h"][0]), int(d["wall_h"][1]))})
	return out

## Channels in the wet biomes, wherever the flats leave room. raw (the heights so far) is held
## level over each river's banks. Returns the columns to hold, [x0, x1] pairs. Call after the
## flats are placed.
static func plan_rivers(c: GenContext, rng: RandomNumberGenerator, raw: PackedFloat32Array, blend: float) -> Array:
	c.rivers = []
	var held: Array = []
	if not enabled(c):
		return held
	var d: Dictionary = data()["river"]
	var wet: Array = []
	for seg: Dictionary in c.biomes:
		if (d["biomes"] as Dictionary).has(seg["biome"]):
			wet.append({"seg": seg, "n": 0})
	for _i in maxi(1, roundi(float(c.w) / float(d["count"]))):
		wet.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:    # the emptiest stretch next
			var sa := float(int(a["seg"]["x1"]) - int(a["seg"]["x0"])) / (int(a["n"]) + 1)
			var sb := float(int(b["seg"]["x1"]) - int(b["seg"]["x0"])) / (int(b["n"]) + 1)
			return sa > sb or (sa == sb and int(a["seg"]["x0"]) < int(b["seg"]["x0"])))
		for row: Dictionary in wet:
			if _lay_river(c, rng, raw, blend, row["seg"], held):
				row["n"] = int(row["n"]) + 1
				break
	c.rivers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["x0"]) < int(b["x0"]))
	for i in c.rivers.size():
		c.rivers[i]["id"] = i
	return held

## One river in this stretch of a wet biome, if the flats leave room for it.
static func _lay_river(c: GenContext, rng: RandomNumberGenerator, raw: PackedFloat32Array, blend: float, seg: Dictionary, held: Array) -> bool:
	var d: Dictionary = data()["river"]
	var margin := int(d["banks"])
	var ford := rng.randf() < float(d["biomes"][seg["biome"]]["ford_p"])
	var width := _rnd(rng, d["ford_width"] if ford else d["width"])
	var lo := maxi(int(seg["x0"]) + int(blend), int(d["edge"]))
	var hi := mini(int(seg["x1"]) - int(blend), c.w - int(d["edge"])) - width
	if hi <= lo:
		return false
	for _try in 60:
		var x0 := rng.randi_range(lo, hi)
		var x1 := x0 + width - 1
		if _flat_near(c, x0, x1, int(d["flat_gap"])) or reserved_in(c, x0 - margin - int(blend), x1 + margin + int(blend)):
			continue
		var level := 0.0
		for x in range(x0 - margin, x1 + margin + 1):
			level += raw[x]
		level = _near_town(c, roundf(level / (x1 - x0 + 1 + 2 * margin)), x0 - margin, x1 + margin)
		_hold(raw, x0 - margin, x1 + margin, blend, level)
		var rv := {"id": 0, "x0": x0, "x1": x1, "biome": seg["biome"], "kind": "ford" if ford else "bridge"}
		if ford:
			rv["drop"] = _rnd(rng, d["ford_drop"])
			rv["wet"] = 1                            # one tile of water: walked through
		else:
			rv["wet"] = _rnd(rng, d["deep"])
			rv["drop"] = rv["wet"] + _rnd(rng, d["drop"])
		c.rivers.append(rv)
		held.append([x0 - margin, x1 + margin])
		reserve(c, x0 - margin - int(d["flat_gap"]) / 2, x1 + margin + int(d["flat_gap"]) / 2)
		return true
	return false

static func _flat_near(c: GenContext, x0: int, x1: int, gap: int) -> bool:
	for f: Dictionary in c.flats:
		if x1 + gap >= int(f["x0"]) and x0 - gap <= int(f["x1"]):
			return true
	return false

## The ground is final but for these: record each pass, stand the walls on it, cut the rivers.
static func raise(c: GenContext, rng: RandomNumberGenerator) -> void:
	var jag := c.noise(rng, 1.0 / 16.0, 2)
	for rg: Dictionary in c.ranges:
		var x0 := int(rg["x0"])
		var x1 := int(rg["x1"])
		var path: Array = []
		var top := Vector2i(x0, -1)
		for x in range(x0, x1 + 1):
			var p := Vector2i(x, c.ground[x] + 1)
			c.pass_y[x] = p.y
			path.append(p)
			if p.y > top.y:
				top = p
		rg["pass"] = {"path": path, "top": top}
		var lift := PackedInt32Array()
		lift.resize(x1 - x0 + 1)
		for wall: Dictionary in rg["walls"]:
			var hw := int(wall["hw"])
			var step := int(wall["terrace"])
			for x in range(maxi(x0, int(wall["x"]) - hw), mini(x1, int(wall["x"]) + hw) + 1):
				var u := 1.0 - absf(float(x - int(wall["x"]))) / hw
				var v := float(wall["h"]) * pow(u, 0.6) + jag.get_noise_1d(x) * step * 0.45
				lift[x - x0] = maxi(lift[x - x0], int(maxf(v, 0.0) / step) * step)  # ledges and cliffs
		var peak := -1
		for x in range(x0, x1 + 1):
			c.ground[x] = mini(c.ground[x] + lift[x - x0], c.h - 24)
			peak = maxi(peak, c.ground[x])
		rg["peak"] = peak
	for rv: Dictionary in c.rivers:
		var x0 := int(rv["x0"])
		var x1 := int(rv["x1"])
		var bank := c.ground[x0 - 1]
		rv["bank"] = bank
		rv["bed"] = bank - int(rv["drop"])
		rv["water"] = int(rv["bed"]) + int(rv["wet"])     # the top row of water
		for x in range(x0, x1 + 1):                       # banks slope a row a column
			c.ground[x] = bank - mini(mini(x - x0 + 1, x1 - x + 1), int(rv["drop"]))

# --- stage "barriers" -----------------------------------------------------------------------

static func run(c: GenContext, rng: RandomNumberGenerator) -> void:
	var wander := c.noise(rng, 1.0 / 90.0, 2)
	for rg: Dictionary in c.ranges:
		_pass(c, rg)
		_under(c, rg, wander)
	for rv: Dictionary in c.rivers:
		_river(c, rv)

## Pave the pass and open it through the walls.
static func _pass(c: GenContext, rg: Dictionary) -> void:
	var d: Dictionary = data()["range"]
	var tall := int(d["pass_h"])
	var torch := TileDefs.id("torch")
	var lit := 0
	var galleries := 0
	var inside := false
	for p: Vector2i in rg["pass"]["path"]:
		var top := p.y + tall - 1
		c.carve_rect(p.x, p.y, p.x, top)
		var cover := c.ground[p.x] - top
		if cover > 0 and cover <= int(d["open_cut"]):
			c.carve_rect(p.x, top + 1, p.x, c.ground[p.x])
			for y in range(p.y, c.ground[p.x] + 1):
				c.bg[p.x + y * c.w] = 0
			cover = 0
		c.fg[p.x + (p.y - 1) * c.w] = c.col_road[p.x]
		if cover > 0:
			if not inside:
				galleries += 1
				lit = 0
			lit += 1
			if lit % int(d["torch_every"]) == 1:       # one just inside each mouth, too
				c.fg[p.x + (p.y + 3) * c.w] = torch
		inside = cover > 0
	rg["pass"]["galleries"] = galleries

## Mouth to mouth under the crest: down a row a column, along, and up again.
static func _under(c: GenContext, rg: Dictionary, wander: FastNoiseLite) -> void:
	var d: Dictionary = data()["under"]
	var west := int(rg["mouths"][0])
	var east := int(rg["mouths"][1])
	var low := 1 << 30
	for x in range(west, east + 1):
		low = mini(low, rock_top(c, x))
	var level := low - int(d["cover"])
	var yw := c.ground[west] + 1
	var ye := c.ground[east] + 1
	var path: Array = []
	var prev := yw
	for x in range(west, east + 1):
		var t := level + roundi(wander.get_noise_1d(x) * float(d["wander"]))
		var y := maxi(t, maxi(yw - (x - west), ye - (east - x)))
		y = clampi(y, prev - 1, prev + 1)
		prev = y
		path.append(Vector2i(x, y))
	Deeps._carve_path(c, path, GenContext.RAMP_H)
	_floor(c, path)
	rg["under"] = {"path": path}
	var shelf := int(d["shelf"])
	rg["shelves"] = [_shelf(c, west - shelf, west), _shelf(c, east, east + shelf)]

## A shelf's outer half, paved: a road comes in on it, so it arrives at the mouth's own height.
static func _shelf(c: GenContext, x0: int, x1: int) -> Array:
	var cells: Array = []
	for x in range(x0, x1 + 1):
		c.fg[x + c.ground[x] * c.w] = c.col_road[x]
		cells.append(Vector2i(x, c.ground[x] + 1))
	return cells

## Where a tunnel crosses a cave its floor is open air: a tread where it climbs (one-way, so
## the cave under it is not walled off), a plank where it is level.
static func _floor(c: GenContext, path: Array) -> void:
	var tr := TileDefs.id("stairs_r")
	var tl := TileDefs.id("stairs_l")
	var plank := TileDefs.id("platform")
	for k in path.size():
		var q: Vector2i = path[k]
		var i := q.x + (q.y - 1) * c.w
		if q.y - 1 > c.ground[q.x] or c.fg[i] != c.AIR:
			continue
		var back: int = q.y - (path[k - 1] as Vector2i).y if k > 0 else 0
		var on: int = (path[k + 1] as Vector2i).y - q.y if k + 1 < path.size() else 0
		c.fg[i] = plank if back == 0 and on == 0 else (tr if back > 0 or on > 0 else tl)

## Seal the channel against the caves, lay the water and the crossing.
static func _river(c: GenContext, rv: Dictionary) -> void:
	var d: Dictionary = data()["river"]
	var bed_tile := TileDefs.id("river_bed")
	var ford_tile := TileDefs.id("ford_stones")
	var water := TileDefs.id("water")
	var x0 := int(rv["x0"])
	var x1 := int(rv["x1"])
	var bank := int(rv["bank"])
	var bed := int(rv["bed"])
	var top := int(rv["water"])
	var ford: bool = rv["kind"] == "ford"
	for x in range(x0, x1 + 1):
		var g := c.ground[x]
		for y in range(g - int(d["seal"]), g):
			if c.fg[x + y * c.w] != c.BEDROCK:
				c.fg[x + y * c.w] = bed_tile
		c.fg[x + g * c.w] = ford_tile if ford and g == bed else bed_tile
		for y in range(g + 1, bank + 6):
			c.fg[x + y * c.w] = water if y <= top else c.AIR
	for x: int in [x0 - 2, x0 - 1, x1 + 1, x1 + 2]:
		c.fg[x + c.ground[x] * c.w] = c.col_road[x]       # the road's stretch of bank
	var cells: Array = []
	if ford:
		for x in range(x0 - 2, x1 + 3):
			cells.append(Vector2i(x, c.ground[x] + 1))
	else:
		var deck := TileDefs.id("bridge")
		for x in range(x0, x1 + 1):
			if c.ground[x] < bank:
				c.fg[x + bank * c.w] = deck
		for x in range(x0 - 2, x1 + 3):
			cells.append(Vector2i(x, bank + 1))
	rv["crossing"] = {"kind": rv["kind"], "cells": cells}

# --- what a road crosses --------------------------------------------------------------------

## What a walk between columns xa < xb crosses, west to east: {kind, id, x0, x1, cells} (feet
## cells one column apart, walked instead of graded). kind: pass, bridge, ford, or shelf, the
## level ground at an under-route's mouth, which only holds the road to its height.
static func crossings(c: GenContext, xa: int, xb: int) -> Array:
	var out: Array = []
	for rg: Dictionary in c.ranges:
		if xa < int(rg["x0"]) and xb > int(rg["x1"]):
			out.append({"kind": "pass", "id": rg["id"], "x0": rg["x0"], "x1": rg["x1"], "cells": rg["pass"]["path"]})
		for cells: Array in rg["shelves"]:
			if xa < (cells[0] as Vector2i).x and xb > (cells[-1] as Vector2i).x:
				out.append({"kind": "shelf", "id": rg["id"], "x0": (cells[0] as Vector2i).x, "x1": (cells[-1] as Vector2i).x, "cells": cells})
	for rv: Dictionary in c.rivers:
		if xa < int(rv["x0"]) - 2 and xb > int(rv["x1"]) + 2:
			out.append({"kind": rv["kind"], "id": rv["id"], "x0": rv["x0"], "x1": rv["x1"], "cells": rv["crossing"]["cells"]})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["x0"]) < int(b["x0"]))
	return out

## What a route over these crossings adds to its length.
static func cost(c: GenContext, cross: Array) -> int:
	var d: Dictionary = data()["cost"]
	var n := 0.0
	for x: Dictionary in cross:
		n += float(d.get(x["kind"], 0.0))
	return roundi(n * c.w)

## The height a road meets the ground at in column x: the pass where there is one.
static func way_y(c: GenContext, x: int) -> int:
	return c.pass_y[x] - 1 if c.pass_y[x] >= 0 else c.surface[x]

## [label, feet cell] of both ends of every crossing: the passages stage joins them, and tools
## check them, like sites.
static func ends(c: GenContext) -> Array:
	var out: Array = []
	for rg: Dictionary in c.ranges:
		var path: Array = rg["pass"]["path"]
		var under: Array = rg["under"]["path"]
		out.append(["pass %d west" % rg["id"], path[0]])
		out.append(["pass %d east" % rg["id"], path[-1]])
		out.append(["under %d west" % rg["id"], under[0]])
		out.append(["under %d east" % rg["id"], under[-1]])
	for rv: Dictionary in c.rivers:
		var cells: Array = rv["crossing"]["cells"]
		out.append(["river %d west" % rv["id"], cells[0]])
		out.append(["river %d east" % rv["id"], cells[-1]])
	return out

# --- meta -----------------------------------------------------------------------------------

static func _cells(path: Array) -> Array:
	var out: Array = []
	for p: Vector2i in path:
		out.append([p.x, p.y])
	return out

## world.meta.barriers: plain arrays, for maps, tests and later tracks.
static func meta(c: GenContext) -> Dictionary:
	var ranges: Array = []
	for rg: Dictionary in c.ranges:
		var top: Vector2i = rg["pass"]["top"]
		ranges.append({"id": rg["id"], "x0": rg["x0"], "x1": rg["x1"], "peak": rg["peak"],
			"walls": (rg["walls"] as Array).duplicate(true),
			"pass": {"path": _cells(rg["pass"]["path"]), "top": [top.x, top.y], "galleries": rg["pass"].get("galleries", 0)},
			"under": {"path": _cells(rg.get("under", {}).get("path", []))}})
	var rivers: Array = []
	for rv: Dictionary in c.rivers:
		var row: Dictionary = rv.duplicate()
		row["crossing"] = {"kind": rv["kind"], "cells": _cells(rv.get("crossing", {}).get("cells", []))}
		rivers.append(row)
	return {"ranges": ranges, "rivers": rivers}
