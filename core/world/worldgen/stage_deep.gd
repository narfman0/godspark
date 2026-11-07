## The underground biomes and the ways down (M6, docs/tracks/deep.md), from
## data/worldgen/biomes.json "underground". A world narrower than min_world (or a one-biome
## scenario world) has none of this.
##
##   "regions"       plan: each band's regions, a pure function of the seed. Rows go into
##                   c.regions (meta.biomes after the surface strip: {biome, band, x0, x1, y0,
##                   y1}), the plain underdark filling the gaps.
##   "region_caves"  each region's own cave shape before the caverns and the deep road are
##                   cut: fungal domes (wide and round), crystal chambers (cellular, angular),
##                   and in the low nadir of the magma the lava tubes.
##   "lake"          the deep lake: a basin under the caverns and the road, its beaches,
##                   islands and water (c.liquid, swum), sealed in lake rock, and its crossing,
##                   a shore path that climbs from one beach into the rock over the cavern and
##                   down to the other.
##   "lava"          pools of lava in the tubes' floors: a stone bridge over each one a walker
##                   cannot jump, and the nadir floor every walker must reach.
##   "region_rock"   each region's rock, floor and wall tiles, seams interleaved; crystal ores.
##   "sinkholes"     after the sites and routes, before the towns and roads (so the sim sees the
##                   world it saw before them): one shaft per surface biome, between the first
##                   town and the last, from the ground down into the caves band, a deck over it
##                   with a rope through, ledges on the way down and a chamber at the bottom; the
##                   deck is a crossing the road over it walks.
##   "glow"          after the passages: the regions' light tiles (glow caps, crystal clusters,
##                   lumen moss) on open floors and ceilings, never on anything built.
## The lake's water and the lava are tiles the passages stage never cuts (96 and up), so its
## joins go round them, and both are walls to a walker (MonsterNav: liquid without a swim speed,
## HAZARD for lava). Their crossings, the sinkholes and the nadir floor are passages targets.
extends RefCounted

const GenContext := preload("gen_context.gd")
const StageBiomes := preload("stage_biomes.gd")
const Barriers := preload("stage_barriers.gd")
const Deeps := preload("stage_deeps.gd")

const NONE := 255
## A sinkhole: shaft width (the rope in its middle column), rows between ledges, the bell's
## widening under the deck, the chamber at the bottom.
const SINK_W := 9
const LEDGE_EVERY := 12
const BELL := 4
const CHAMBER_W := 22
const CHAMBER_H := 7

static func data() -> Dictionary:
	return StageBiomes.data().get("underground", {})

static func enabled(c: GenContext) -> bool:
	var d := data()
	return not d.is_empty() and c.w >= int(d.get("min_world", 2048)) and String(c.opts.get("only_biome", "")) == "" \
		and bool(c.opts.get("regions", true))

static func def(biome: String) -> Dictionary:
	return data().get("regions", {}).get(biome, {})

# --- "regions" -------------------------------------------------------------------------------

static func plan(c: GenContext, rng: RandomNumberGenerator) -> void:
	c.regions = []
	c.reg_col = {}
	if not enabled(c):
		return
	var d := data()
	for band: String in ["deeps", "nadir"]:
		var rows: Array = (d["bands"] as Dictionary).get(band, [])
		var kinds: Array = []
		for row: Dictionary in rows:
			for k in maxi(1, roundi(c.w / float(row["every"]))):
				kinds.append(row)
		for i in range(kinds.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t: Variant = kinds[i]
			kinds[i] = kinds[j]
			kinds[j] = t
		var widths: Array = []
		var total := 0
		for row: Dictionary in kinds:
			var sh: Array = row["share"]
			var ti: Array = row["tiles"]
			var wd := clampi(int(c.w * rng.randf_range(float(sh[0]), float(sh[1]))), int(ti[0]), int(ti[1]))
			widths.append(wd)
			total += wd
		var margin := int(d["margin"])
		var gap := int(d["gap"])
		var room := c.w - 2 * margin - (kinds.size() + 1) * gap
		if total > room:
			for i in widths.size():
				widths[i] = int(int(widths[i]) * float(room) / total)
			total = 0
			for v: int in widths:
				total += v
		var weights: Array = []
		var wsum := 0.0
		for i in kinds.size() + 1:
			var v := rng.randf_range(0.5, 1.5)
			weights.append(v)
			wsum += v
		var spare := room - total
		var b: Array = c.bands[band]
		var col := PackedByteArray()
		col.resize(c.w)
		col.fill(NONE)
		var x := 0
		for i in kinds.size() + 1:
			var gw := gap + int(spare * float(weights[i]) / wsum) + (margin if i == 0 else 0)
			var gx1 := x + gw - 1 if i < kinds.size() else c.w - 1
			_row(c, col, "underdark", band, x, gx1, b)
			x = gx1 + 1
			if i < kinds.size():
				_row(c, col, String(kinds[i]["biome"]), band, x, x + int(widths[i]) - 1, b)
				x += int(widths[i])
		c.reg_col[band] = col

static func _row(c: GenContext, col: PackedByteArray, biome: String, band: String, x0: int, x1: int, b: Array) -> void:
	x1 = mini(x1, c.w - 1)
	if x1 < x0:
		return
	var i := c.regions.size()
	c.regions.append({"biome": biome, "band": band, "x0": x0, "x1": x1, "y0": int(b[0]), "y1": int(b[1])})
	for x in range(x0, x1 + 1):
		col[x] = i

## Region rows of one biome.
static func of(c: GenContext, biome: String) -> Array:
	return c.regions.filter(func(r: Dictionary) -> bool: return r["biome"] == biome)

# --- "region_caves" --------------------------------------------------------------------------

static func shape(c: GenContext, rng: RandomNumberGenerator) -> void:
	for r: Dictionary in c.regions:
		var sh: Dictionary = def(String(r["biome"])).get("shape", {})
		match String(sh.get("kind", "")):
			"round":
				_domes(c, rng, r, sh)
			"angular":
				_chambers(c, rng, r, sh)
			"tube":
				_tube(c, rng, r, sh)

## Wide round caverns with level floors: half-ellipses, rx 1.5 times ry.
static func _domes(c: GenContext, rng: RandomNumberGenerator, r: Dictionary, sh: Dictionary) -> void:
	var x0 := int(r["x0"])
	var x1 := int(r["x1"])
	var y0 := int(r["y0"])
	var y1 := int(r["y1"])
	var rr: Array = sh["r"]
	var n := maxi(2, (x1 - x0 + 1) * (y1 - y0 + 1) / int(sh["per"]))
	for k in n:
		var ry := rng.randf_range(float(rr[0]), float(rr[1])) * clampf(c.sy(), 1.0, 1.6)
		var rx := ry * rng.randf_range(1.3, 1.8)
		var cx := rng.randi_range(x0 + int(rx), maxi(x0 + int(rx), x1 - int(rx)))
		var cy := rng.randi_range(y0 + int(ry) + 10, maxi(y0 + int(ry) + 10, y1 - int(ry) - 10))
		var floor_y := cy - int(ry * 0.45)
		for y in range(floor_y, cy + int(ry) + 1):
			var dy := float(y - cy) / ry
			var half := int(rx * sqrt(maxf(0.0, 1.0 - dy * dy)))
			if y >= c.h - 1 or y < 2:
				continue
			var row := y * c.w
			for x in range(maxi(1, cx - half), mini(c.w - 2, cx + half) + 1):
				if c.fg[row + x] != c.BEDROCK:
					c.fg[row + x] = c.AIR

## Angular chambers: the cells of a cellular noise, a share of them opened, a rim of rock kept
## along every cell's edge, so walls are straight and meet at angles.
static func _chambers(c: GenContext, rng: RandomNumberGenerator, r: Dictionary, sh: Dictionary) -> void:
	var x0 := int(r["x0"])
	var y0 := int(r["y0"]) + 6
	var gw := int(r["x1"]) - x0 + 1
	var gh := int(r["y1"]) - 6 - y0 + 1
	var cell := FastNoiseLite.new()
	cell.seed = rng.randi() & 0x7fffffff
	cell.noise_type = FastNoiseLite.TYPE_CELLULAR
	cell.fractal_type = FastNoiseLite.FRACTAL_NONE
	cell.frequency = float(sh["freq"]) / clampf(c.sy(), 1.0, 1.6)
	cell.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	var edge := cell.duplicate() as FastNoiseLite
	edge.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	var vals := GenContext.noise_bytes(cell, x0, y0, gw, gh)
	var rims := GenContext.noise_bytes(edge, x0, y0, gw, gh)
	var cut := int(255.0 * (1.0 - float(sh["cut"])))
	var rim := int(255.0 * float(sh["rim"]) * 0.25)
	for gy in gh:
		var row := (y0 + gy) * c.w
		for gx in gw:
			var k := gx + gy * gw
			if vals[k] > cut and rims[k] > rim and c.fg[row + x0 + gx] != c.BEDROCK:
				c.fg[row + x0 + gx] = c.AIR

## The magma's lava tube: a low winding cave along the region under the portal's chamber, its
## floor a row a column at most, swelling into chambers. Pools come later (stage "lava").
static func _tube(c: GenContext, rng: RandomNumberGenerator, r: Dictionary, sh: Dictionary) -> void:
	var nb: Array = c.bands["nadir"]
	var bed_max := 0
	for v in c.bed:
		bed_max = maxi(bed_max, v)
	var ch := clampi(int(14 * c.sy()), 9, 16)
	var portal_floor := maxi(bed_max + 3, (int(nb[0]) + int(nb[1])) / 2 - ch / 2)
	var hh: Array = sh["h"]
	var top := portal_floor - 8                  # the tube stays under the portal's chamber and ramp
	var lo := bed_max + 6
	var hmax := mini(int(hh[1]), maxi(int(hh[0]), (top - lo) / 2))
	if top - lo < int(hh[0]) + 4:
		return
	var x0 := int(r["x0"]) + 12
	var x1 := int(r["x1"]) - 12
	var wander := c.noise(rng, 1.0 / 70.0, 2)
	var swell := c.noise(rng, 1.0 / 45.0, 1)
	var roof := c.noise(rng, 1.0 / 9.0, 1)
	var base := rng.randi_range(lo + 2, maxi(lo + 2, top - hmax - 2))
	var amp := minf(14.0, (top - lo - hmax) * 0.4)
	var rock := TileDefs.id(String(def("magma")["rock"]))
	var ash := TileDefs.id(String(def("magma")["floor"]))
	var floors := PackedInt32Array()
	var f := base
	for x in range(x0, x1 + 1):
		# the floor's aim changes every 28 columns, so it runs level between its slopes (room for pools)
		var want := clampi(base + roundi(wander.get_noise_1d(x - posmod(x, 28)) * amp), lo, top - int(hh[0]))
		f += clampi(want - f, -1, 1)
		floors.append(f)
		var s := clampf((swell.get_noise_1d(x) + 0.6) / 1.6, 0.0, 1.0)
		var tall := int(hh[0]) + int(s * s * (hmax - int(hh[0]))) + roundi(roof.get_noise_1d(x) * 1.5)
		tall = clampi(tall, int(hh[0]), mini(hmax, top - f))
		var row := x
		for y in range(f - 3, f):
			if c.fg[row + y * c.w] != c.BEDROCK:
				c.fg[row + y * c.w] = ash if y == f - 1 else rock       # a sound floor
		for y in range(f, f + tall):
			if c.fg[row + y * c.w] != c.BEDROCK:
				c.fg[row + y * c.w] = c.AIR
	c.lava.append({"region": r, "x0": x0, "x1": x1, "floor": floors, "pools": [], "bridges": []})

# --- "lake" ----------------------------------------------------------------------------------

static func lake(c: GenContext, rng: RandomNumberGenerator) -> void:
	c.lake = {}
	var sh: Dictionary = def("deep_lake")["shape"]
	var planned := of(c, "deep_lake")
	for r: Dictionary in planned:
		if _lake(c, rng, r, sh, int(r["x0"]) + 16, int(r["x1"]) - 16):
			return
	if planned.is_empty():
		return
	# no room where it was planned (the portal's ramp, the caverns): the lake goes to the widest
	# stretch of the underdark that has room, and its region with it
	var gaps := c.regions.filter(func(r: Dictionary) -> bool: return r["band"] == "deeps" and r["biome"] == "underdark")
	gaps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["x1"]) - int(a["x0"]) > int(b["x1"]) - int(b["x0"]) or (int(a["x1"]) - int(a["x0"]) == int(b["x1"]) - int(b["x0"]) and int(a["x0"]) < int(b["x0"])))
	var old: Dictionary = planned[0]
	var want := int(old["x1"]) - int(old["x0"])
	for g: Dictionary in gaps:
		var gx0 := int(g["x0"]) + 24
		var gx1 := int(g["x1"]) - 24
		if gx1 - gx0 < 150:
			continue
		var span := mini(want, gx1 - gx0)
		for at: int in [(gx0 + gx1 - span) / 2, gx0, gx1 - span]:
			if _lake(c, rng, g, sh, at, at + span):
				_move_region(c, "deeps", old, int(c.lake["x0"]) - 16, int(c.lake["x1"]) + 16)
				return

## The region `row` (a deep lake planned where it did not fit) becomes underdark, and a region of
## its biome takes columns x0..x1 out of the underdark instead; neighbours of one biome merge.
static func _move_region(c: GenContext, band: String, row: Dictionary, x0: int, x1: int) -> void:
	var biome := String(row["biome"])
	row["biome"] = "underdark"
	var b: Array = c.bands[band]
	var cut: Array = []
	for r: Dictionary in c.regions:
		if r["band"] != band:
			continue
		if int(r["x1"]) < x0 or int(r["x0"]) > x1:
			cut.append(r.duplicate())
			continue
		if int(r["x0"]) < x0:
			cut.append({"biome": r["biome"], "x0": int(r["x0"]), "x1": x0 - 1})
		if int(r["x1"]) > x1:
			cut.append({"biome": r["biome"], "x0": x1 + 1, "x1": int(r["x1"])})
	cut.append({"biome": biome, "x0": x0, "x1": x1})
	cut.sort_custom(func(a: Dictionary, z: Dictionary) -> bool: return int(a["x0"]) < int(z["x0"]))
	var merged: Array = []
	for r: Dictionary in cut:
		if not merged.is_empty() and merged[-1]["biome"] == r["biome"]:
			merged[-1]["x1"] = r["x1"]
		else:
			merged.append({"biome": r["biome"], "x0": int(r["x0"]), "x1": int(r["x1"])})
	var keep := c.regions.filter(func(r: Dictionary) -> bool: return r["band"] != band)
	var rows: Array = []
	for r: Dictionary in merged:
		rows.append({"biome": r["biome"], "band": band, "x0": r["x0"], "x1": r["x1"], "y0": int(b[0]), "y1": int(b[1])})
	# bands in their order (deeps first), as plan laid them
	c.regions = rows + keep if band == "deeps" else keep + rows
	for bd: String in c.reg_col:
		var col: PackedByteArray = c.reg_col[bd]
		col.fill(NONE)
		for i in c.regions.size():
			var r: Dictionary = c.regions[i]
			if r["band"] == bd:
				for x in range(int(r["x0"]), int(r["x1"]) + 1):
					col[x] = i
		c.reg_col[bd] = col
	for r: Dictionary in c.regions:
		if r["biome"] == biome and r["band"] == band and int(r["x0"]) == x0:
			c.lake["region"] = r

## Rows a lake at columns x0..x1 must stay under: the caverns, the deep road and both ramps.
static func _ceiling_limit(c: GenContext, x0: int, x1: int) -> int:
	var top := c.h
	for cav: Dictionary in c.caverns:
		var reach := int(int(cav["rx"]) * 1.5) + 4
		if int(cav["x"]) + reach >= x0 and int(cav["x"]) - reach <= x1:
			top = mini(top, int(cav["floor"]) - 4)
	if c.road_x0 >= 0:
		for x in range(maxi(x0, c.road_x0), mini(x1, c.road_x1) + 1):
			top = mini(top, c.road_floor[x - c.road_x0] - 2)
	for ramp: Dictionary in [c.ascent, c.portal]:
		for p: Vector2i in ramp.get("path", []):
			if p.x >= x0 and p.x <= x1:
				top = mini(top, p.y - 2)
	return top

## A lake within columns rx0..rx1 of region r, or false where there is no room for one.
static func _lake(c: GenContext, rng: RandomNumberGenerator, r: Dictionary, sh: Dictionary, rx0: int, rx1: int) -> bool:
	# keep off the portal's ramp and chamber, and from under a town's cavern (the passages stage
	# never joins through one): the lake takes the widest stretch left
	var blocked: Array = []
	if not c.portal.is_empty():
		var px0 := int(c.portal["x"]) - int(c.portal["w"])
		var px1 := int(c.portal["x"]) + int(c.portal["w"])
		for p: Vector2i in c.portal.get("path", []):
			px0 = mini(px0, p.x)
			px1 = maxi(px1, p.x)
		blocked.append([px0 - 24, px1 + 24])
	for cav: Dictionary in c.caverns:
		if cav["settled"]:
			var rx := int(cav["rx"])
			blocked.append([int(cav["x"]) - rx * 3 / 4 - 24, int(cav["x"]) + rx * 3 / 4 + 24])
	var free: Array = [[rx0, rx1]]
	for bl: Array in blocked:
		var next: Array = []
		for f: Array in free:
			if int(bl[1]) < int(f[0]) or int(bl[0]) > int(f[1]):
				next.append(f)
				continue
			if int(bl[0]) - 1 >= int(f[0]):
				next.append([int(f[0]), int(bl[0]) - 1])
			if int(bl[1]) + 1 <= int(f[1]):
				next.append([int(bl[1]) + 1, int(f[1])])
		free = next
	if free.is_empty():
		return false
	free.sort_custom(func(a: Array, b: Array) -> bool: return int(a[1]) - int(a[0]) > int(b[1]) - int(b[0]))
	rx0 = int(free[0][0])
	rx1 = int(free[0][1])
	if rx1 - rx0 < 120:
		return false
	var lw := int((rx1 - rx0) * rng.randf_range(0.75, 0.92))
	var lx0 := rx0 + rng.randi_range(0, (rx1 - rx0) - lw)
	var lx1 := lx0 + lw
	var db: Array = c.bands["deeps"]
	var bottom := maxi(int(db[0]) - c.band_h("nadir") / 4, 24)
	var top := _ceiling_limit(c, lx0 - 12, lx1 + 12) - 8
	var dd: Array = sh["depth"]
	var aa: Array = sh["air"]
	var depth := rng.randi_range(int(dd[0]), int(dd[1]))
	var air := rng.randi_range(int(aa[0]), int(aa[1]))
	# shell 3, water, beach 4 over it, air, rock 2 and a gallery 6 over the cavern
	var need := func(dp: int, ar: int) -> int: return 3 + dp + 4 + ar + 3 + GenContext.RAMP_H + 2
	while need.call(depth, air) > top - bottom and (depth > 8 or air > 12):
		depth = maxi(8, depth - 1)
		air = maxi(12, air - 1)
	if need.call(depth, air) > top - bottom:
		return false
	var water := bottom + 3 + depth + rng.randi_range(0, (top - bottom) - need.call(depth, air))
	var bb: Array = sh["beach"]
	var beach := rng.randi_range(int(bb[0]), int(bb[1]))
	var wall := TileDefs.wall_id(String(def("deep_lake")["wall"]))
	var stone := TileDefs.id(String(def("deep_lake")["rock"]))
	var sand := TileDefs.id(String(def("deep_lake")["floor"]))
	var silt := TileDefs.id(String(sh["bed"]))
	var wet := TileDefs.id("water")
	var wob := c.noise(rng, 1.0 / 23.0, 2)
	var dome := c.noise(rng, 1.0 / 40.0, 2)
	# islands: small, so the passages stage leaves them to swimmers
	var islands: Array = []
	var open0 := lx0 + beach + depth + 10
	var open1 := lx1 - beach - depth - 10
	var iw: Array = sh["island_w"]
	var n_isl := clampi((open1 - open0) / int(sh["islands_per"]), 0, 3)
	for k in n_isl:
		var span := float(open1 - open0) / n_isl
		var wd := rng.randi_range(int(iw[0]), int(iw[1]))
		var cx := open0 + int(span * (k + 0.5)) + rng.randi_range(-int(span / 5), int(span / 5))
		islands.append({"x": cx, "w": wd, "top": water + rng.randi_range(2, 3)})
	var beds := PackedInt32Array()
	var ceils := PackedInt32Array()
	var ceil_max := 0
	for x in range(lx0, lx1 + 1):
		var e := mini(x - lx0, lx1 - x)
		var b: int
		if e < beach:
			b = water + 4
		else:
			b = maxi(water - depth + roundi(wob.get_noise_1d(x) * 2.0), water + 4 - (e - beach))
		for isl: Dictionary in islands:
			var off := absi(x - int(isl["x"])) - int(isl["w"]) / 2
			b = maxi(b, int(isl["top"]) - maxi(0, off))
		var ce := maxi(b + 7, water + 5 + int(minf(e * 0.6, air)) + roundi(dome.get_noise_1d(x) * 3.0))
		beds.append(b)
		ceils.append(ce)
		ceil_max = maxi(ceil_max, ce)
	var gallery := ceil_max + 3
	if gallery + GenContext.RAMP_H + 1 > top + 8:
		return false
	for k in beds.size():
		var x := lx0 + k
		var b := beds[k]
		for y in range(b - 3, ceils[k] + 1):
			var i := x + y * c.w
			if c.fg[i] == c.BEDROCK:
				continue
			c.bg[i] = wall
			if y < b:
				c.fg[i] = stone
			elif y == b:
				c.fg[i] = silt if b <= water else sand
			elif y <= water:
				c.fg[i] = wet
				c.set_liquid(i, 15)
			else:
				c.fg[i] = c.AIR
	# the beach ends: rock beside the basin as deep as the water goes
	for side: int in [-1, 1]:
		var ex := lx0 if side < 0 else lx1
		for k in range(1, 4):
			var x := ex + side * k
			for y in range(water - depth - 3, water + 5):
				var i := x + y * c.w
				if c.fg[i] != c.BEDROCK and not c.solid[c.fg[i]]:
					c.fg[i] = stone
				c.bg[i] = wall
	# the shore path: from the west beach up into the rock over the cavern, along, and down
	var yw := beds[2] + 1
	var ye := beds[beds.size() - 3] + 1
	var xw := lx0 + 2
	var xe := lx1 - 2
	var path: Array = []
	for x in range(xw, xe + 1):
		path.append(Vector2i(x, mini(gallery, mini(yw + (x - xw), ye + (xe - x)))))
	Deeps._carve_path(c, path, GenContext.RAMP_H)
	Barriers._floor(c, path)
	var well := _well(c, path, gallery)
	c.lake = {"region": r, "well": well, "x0": lx0, "x1": lx1, "water": water, "bed": water - depth, "ceil": ceil_max,
		"beach": beach, "islands": islands, "crossing": {"kind": "shore_path", "cells": path}}
	return true

## The deep road over a lake's shore path is the way the rest of the underground reaches it: a
## shaft from the middle of the path's level run up to the road, a ladder in it whose head is in the
## road's floor (a body walks over a ladder head) and a plank beside it. The passages stage never
## breaks a paved floor, so it would not make this join itself. [x, from row, to row], or [].
static func _well(c: GenContext, path: Array, level: int) -> Array:
	if c.road_x0 < 0:
		return []
	var run: Array = path.filter(func(p: Vector2i) -> bool: return p.y == level)
	run.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return absi(a.x - (path[0] as Vector2i).x - path.size() / 2) < absi(b.x - (path[0] as Vector2i).x - path.size() / 2))
	var ladder := TileDefs.id("ladder")
	var plank := TileDefs.id("platform")
	for p: Vector2i in run:
		var xs := p.x
		if xs < c.road_x0 or xs + 1 > c.road_x1:
			continue
		var f := mini(c.road_floor[xs - c.road_x0], c.road_floor[xs + 1 - c.road_x0])
		if c.road_floor[xs - c.road_x0] != c.road_floor[xs + 1 - c.road_x0] or f - 1 <= level + GenContext.RAMP_H:
			continue
		if _built_in(c, xs - 1, level + GenContext.RAMP_H, xs + 2, f - 2):
			continue
		for y in range(level + GenContext.RAMP_H, f - 1):
			for x: int in [xs, xs + 1]:
				if c.fg[x + y * c.w] != c.BEDROCK:
					c.fg[x + y * c.w] = c.AIR
				c.bg[x + y * c.w] = c.W_COBBLE
		for y in range(level, f):
			c.fg[xs + 1 + y * c.w] = ladder
		c.fg[xs + (f - 1) * c.w] = plank
		return [xs, level, f]
	return []

# --- "lava" ----------------------------------------------------------------------------------

static func lava(c: GenContext, rng: RandomNumberGenerator) -> void:
	c.nadir_floor = Vector2i(-1, -1)
	if c.lava.is_empty():
		return
	var sh: Dictionary = def("magma")["shape"]
	var lava_t := TileDefs.id("lava")
	var deck := TileDefs.id("lava_bridge")
	var rim := TileDefs.id(String(sh["rim"]))
	var pw: Array = sh["pool"]
	var ev: Array = sh["every"]
	var over := int(sh["bridge_over"])
	var deep := int(sh["deep"])
	for t: Dictionary in c.lava:
		var floors: PackedInt32Array = t["floor"]
		var x0 := int(t["x0"])
		var k := rng.randi_range(int(ev[0]), int(ev[1]))
		while k < floors.size() - 24:
			var wd := rng.randi_range(int(pw[0]), int(pw[1]))
			var f := floors[k]
			var ok := k + wd + 3 < floors.size()
			if ok:
				for j in range(k - 3, k + wd + 3):
					if floors[j] != f or not _open_over(c, x0 + j, f, 4):
						ok = false
						break
			if ok:
				var bridged := wd >= over
				var dp := deep if bridged else 2
				for j in range(k - 1, k + wd + 1):
					var x := x0 + j
					for y in range(f - dp - 1, f):
						var i := x + y * c.w
						if c.fg[i] == c.BEDROCK:
							continue
						var inside := j >= k and j < k + wd and y >= f - dp
						c.fg[i] = lava_t if inside else rim
					if bridged and j >= k and j < k + wd:
						c.fg[x + (f - 1) * c.w] = deck
				(t["pools"] as Array).append({"x0": x0 + k, "x1": x0 + k + wd - 1, "y": f, "bridge": bridged})
				if bridged:
					var cells: Array = []
					for j in range(k - 2, k + wd + 2):
						cells.append(Vector2i(x0 + j, f))
					(t["bridges"] as Array).append({"x0": x0 + k, "x1": x0 + k + wd - 1, "y": f, "cells": cells})
				k += wd
			k += rng.randi_range(int(ev[0]), int(ev[1]))
	# the nadir floor: the middle of the first tube, off any pool
	var t0: Dictionary = c.lava[0]
	var floors: PackedInt32Array = t0["floor"]
	var mid := floors.size() / 2
	for d in floors.size() / 2:
		for k: int in [mid + d, mid - d]:
			if k < 3 or k >= floors.size() - 3:
				continue
			var x := int(t0["x0"]) + k
			var f := floors[k]
			if _open_over(c, x, f, 4) and _open_over(c, x + 1, f, 4) and c.solid[c.fg[x + (f - 1) * c.w]] and c.solid[c.fg[x + 1 + (f - 1) * c.w]] \
					and c.fg[x + (f - 1) * c.w] != lava_t and not _near_pool(t0, x, 4):
				c.nadir_floor = Vector2i(x, f)
				return

static func _near_pool(t: Dictionary, x: int, m: int) -> bool:
	for p: Dictionary in t["pools"]:
		if x >= int(p["x0"]) - m and x <= int(p["x1"]) + m:
			return true
	return false

## Rows y..y+n-1 of column x are open air (no ladder, nothing built).
static func _open_over(c: GenContext, x: int, y: int, n: int) -> bool:
	for k in n:
		if c.fg[x + (y + k) * c.w] != c.AIR:
			return false
	return true

# --- "region_rock" ---------------------------------------------------------------------------

## Each region's rock (in place of slate and stone), floor (the top of that rock under open air)
## and wall; across a border the two rocks interleave in fingers seam columns wide. Then the
## crystal's extra ore.
static func rock(c: GenContext, rng: RandomNumberGenerator) -> void:
	if c.regions.is_empty():
		return
	var d := data()
	var seam := int(d["seam"])
	var nf := c.noise(rng, 1.0 / 16.0, 2)
	var defs: Array = []
	for r: Dictionary in c.regions:
		var rd := def(String(r["biome"]))
		defs.append(PackedInt32Array([TileDefs.id(String(rd["rock"])), TileDefs.id(String(rd["floor"])), TileDefs.wall_id(String(rd["wall"]))]))
	var slate := c.SLATE
	var stone := c.STONE
	var w_slate := c.W_SLATE
	var w_stone := c.W_STONE
	var air := c.AIR
	var w := c.w
	var fg := c.fg
	var bg := c.bg
	for band: String in ["deeps", "nadir"]:
		var col: PackedByteArray = c.reg_col.get(band, PackedByteArray())
		if col.is_empty():
			continue
		var b: Array = c.bands[band]
		var y0 := int(b[0])
		var top := int(b[1])
		var y1 := top if band == "nadir" else top + 12     # up to the slate line's wander
		var fingers := GenContext.noise_bytes(nf, 0, y0, w, y1 - y0 + 1)
		# only the columns a region other than the underdark reaches (seam included): the
		# underdark's rock is the slate already there
		var spans: Array = []
		for r: Dictionary in c.regions:
			if r["band"] == band and r["biome"] != "underdark":
				spans.append([maxi(0, int(r["x0"]) - seam), mini(w - 1, int(r["x1"]) + seam)])
		for sp: Array in spans:
			for y in range(y0, y1 + 1):
				var row := y * w
				var frow := (y - y0) * w
				var above := y > top
				for x in range(int(sp[0]), int(sp[1]) + 1):
					var i := row + x
					var t := fg[i]
					var wl := bg[i]
					var rock_here := t == slate or (t == stone and not above)
					if not rock_here and wl != w_slate and wl != w_stone:
						continue
					var ri := col[clampi(x + (int(fingers[frow + x]) - 128) * seam / 110, 0, w - 1)]
					if ri == NONE:
						continue
					var dd: PackedInt32Array = defs[ri]
					if rock_here:
						fg[i] = dd[1] if fg[i + w] == air else dd[0]
					if wl == w_slate or wl == w_stone:
						bg[i] = dd[2]
	_crystal_ores(c, rng)

static func _crystal_ores(c: GenContext, rng: RandomNumberGenerator) -> void:
	var od: Dictionary = def("crystal").get("ores", {})
	if od.is_empty():
		return
	var rockt := TileDefs.id(String(def("crystal")["rock"]))
	var ores: Array = (od["tiles"] as Array).map(func(n: String) -> int: return TileDefs.id(n))
	for r: Dictionary in of(c, "crystal"):
		var area := (int(r["x1"]) - int(r["x0"]) + 1) * (int(r["y1"]) - int(r["y0"]) + 1)
		var veins := int(area / 10000.0 * 1.6 * float(od["times"]))
		for v in veins:
			var id: int = ores[rng.randi_range(0, ores.size() - 1)]
			var x := rng.randi_range(int(r["x0"]), int(r["x1"]))
			var y := rng.randi_range(int(r["y0"]), int(r["y1"]))
			for k in rng.randi_range(6, 16):
				for o: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1)]:
					var px := x + o.x
					var py := y + o.y
					if px >= 0 and px < c.w and py >= 1 and py < c.h and c.fg[px + py * c.w] == rockt:
						c.fg[px + py * c.w] = id
				match rng.randi_range(0, 3):
					0: x += 1
					1: x -= 1
					2: y += 1
					_: y -= 1

# --- "sinkholes" -----------------------------------------------------------------------------

## One per surface biome, after the sites and routes and before the towns and roads: a stretch
## of ground away from the planned towns, rivers, ranges, cave mouths and the ascent, over rock with
## nothing built in it. Its deck is a crossing (Barriers.crossings), so a road over it grades up to
## the deck and walks it as it is, like a ford.
static func sinkholes(c: GenContext, rng: RandomNumberGenerator) -> void:
	c.sinkholes = []
	if not enabled(c) or not bool(c.opts.get("sinkholes", true)):
		return
	var cb: Array = c.bands["caves"]
	var avoid: Array = []         # [x0, x1] spans
	for f: Dictionary in c.flats:
		avoid.append([int(f["x0"]) - 40, int(f["x1"]) + 40])
	for rv: Dictionary in c.rivers:
		avoid.append([int(rv["x0"]) - 40, int(rv["x1"]) + 40])
	for e: Vector2i in c.entrances:
		avoid.append([e.x - 30, e.x + 30])
	if not c.ascent.is_empty():
		avoid.append([int(c.ascent["x1"]) - 40, int(c.ascent["x1"]) + 40])
	for s: Dictionary in c.sites:
		if String(s["band"]) in ["surface", "sky"]:
			avoid.append([int(s["x"]) - 30, int(s["x"]) + 30])
	var lo_d := int(c.h * 0.05)
	var hi_d := int(c.h * 0.08)
	# only between the first town and the last, where a road will run over the deck: the bare
	# ground at the world's ends stays as it is (the passages stage reaches the caves from there)
	var lo := c.w
	var hi := 0
	for f: Dictionary in c.flats:
		lo = mini(lo, int(f["x1"]))
		hi = maxi(hi, int(f["x0"]))
	for seg: Dictionary in c.biomes:
		var sx0 := maxi(int(seg["x0"]) + 24, lo + 40)
		var sx1 := mini(int(seg["x1"]) - 24, hi - 40) - SINK_W
		var cands: Array = []
		var x := sx0
		while x <= sx1:
			if _sink_fits(c, x, avoid) >= 0:
				cands.append(x)
				x += 6
			else:
				x += 1
		if cands.is_empty():
			continue
		# from the middle of the biome outward, the first that has room below
		var mid := (sx0 + sx1) / 2
		cands.sort_custom(func(p: int, q: int) -> bool: return absi(p - mid) < absi(q - mid))
		for sx: int in cands.slice(0, 40):
			var top := _sink_fits(c, sx, [])
			var depth := rng.randi_range(lo_d, hi_d)
			var bottom := maxi(top - depth, int(cb[0]) + 12)
			if top - bottom < 30 or _built_in(c, sx - CHAMBER_W / 2, bottom - 4, sx + SINK_W + CHAMBER_W / 2, top - 2) \
					or _site_in(c, sx - CHAMBER_W / 2 - 8, bottom - 8, sx + SINK_W + CHAMBER_W / 2 + 8, top - 2):
				continue
			_dig_sinkhole(c, rng, sx, top, bottom, String(seg["biome"]))
			avoid.append([sx - 60, sx + 60])
			break

## The feet row over column x's ground (c.surface), or -1 where something stands on it.
static func _top(c: GenContext, x: int) -> int:
	var y := c.surface[x]
	for k in range(1, 4):
		if y + k < c.h and c.fg[x + (y + k) * c.w] != c.AIR:
			return -1
	return y + 1

## The span a sinkhole levels: its deck and two columns of ground either side, the crossing's cells.
const SPAN := 2

## Can a sinkhole's deck lie at columns x..x+SINK_W-1? Its feet row, or -1: the ground over the
## span (deck and SPAN columns either side) stands within 4 rows, and is levelled to the middle
## of that (cut above, filled below), with rock under its ends.
static func _sink_fits(c: GenContext, x: int, avoid: Array) -> int:
	for a: Array in avoid:
		if x + SINK_W + 8 >= int(a[0]) and x - 8 <= int(a[1]):
			return -1
	if Barriers.reserved_in(c, x - 12, x + SINK_W + 12):
		return -1
	var lo := 1 << 30
	var hi := -1
	for k in range(-SPAN, SINK_W + SPAN):
		var tk := _top(c, x + k)
		if tk < 0:
			return -1
		lo = mini(lo, tk)
		hi = maxi(hi, tk)
	if hi - lo > 4:
		return -1
	var t := (lo + hi + 1) / 2
	# the road from the towns either side must grade to the deck at a row a column, with room
	# to spare for their streets reaching past their flats
	for f: Dictionary in c.flats:
		var gap := maxi(int(f["x0"]) - (x + SINK_W + SPAN), (x - SPAN) - int(f["x1"])) - 48
		if gap < 0 or absi(int(f["y"]) + 1 - t) * 5 > gap * 4:
			if gap < 0 or _between(c, f, x):
				return -1
	for xx: int in [x - SPAN - 1, x + SINK_W + SPAN]:
		if absi(_top(c, xx) - t) > 1:
			return -1                    # the ground on either side meets the levelled span at a step
	for xx: int in [x - SPAN, x + SINK_W + SPAN - 1]:
		for dy in range(3, 7):
			if c.solid[c.fg[xx + (t - dy) * c.w]] == 0:
				return -1                # ends on ground with rock under it, not a crust over a cave
	return t

## A site (a lair, a buried ruin) in the box: the sinkhole is dug after the sites are.
static func _site_in(c: GenContext, x0: int, y0: int, x1: int, y1: int) -> bool:
	for s: Dictionary in c.sites:
		if int(s["x"]) >= x0 and int(s["x"]) <= x1 and int(s["y"]) >= y0 and int(s["y"]) <= y1:
			return true
	return false

## Is flat f the nearest one on its side of column x (the town a road from x goes to)?
static func _between(c: GenContext, f: Dictionary, x: int) -> bool:
	var left := int(f["x1"]) < x
	for g: Dictionary in c.flats:
		if g == f:
			continue
		if left and int(g["x1"]) < x and int(g["x1"]) > int(f["x1"]):
			return false
		if not left and int(g["x0"]) > x and int(g["x0"]) < int(f["x0"]):
			return false
	return true

## Something built in the box: a paved floor, a built wall, a places tile, a ladder or stairs.
static func _built_in(c: GenContext, x0: int, y0: int, x1: int, y1: int) -> bool:
	for y in range(maxi(1, y0), mini(c.h - 1, y1) + 1):
		var row := y * c.w
		for x in range(maxi(0, x0), mini(c.w - 1, x1) + 1):
			var g := c.fg[row + x]
			if g >= 96 or g == c.COBBLE or c.bg[row + x] == c.W_COBBLE or c.bg[row + x] >= 40 \
					or TileDefs.platform[g] != 0:
				return true
	return false

static func _dig_sinkhole(c: GenContext, rng: RandomNumberGenerator, sx: int, top: int, bottom: int, biome: String) -> void:
	var rope := TileDefs.id("rope")
	var boards := TileDefs.id("planks")      # a solid deck (a body steps up onto it), never cut
	var plank := TileDefs.id("platform")     # either side of the rope: a climber's box passes it
	var rc := sx + SINK_W / 2
	var rows := top - 1 - bottom
	# level the span: the ground's top row at top - 1 (its own top tile, soil under a fill)
	var cells: Array = []
	for x in range(sx - SPAN, sx + SINK_W + SPAN):
		var g := c.surface[x]
		for y in range(top, g + 1):
			c.fg[x + y * c.w] = c.AIR
		for y in range(g + 1, top - 1):
			c.fg[x + y * c.w] = c.col_soil[x]
		c.fg[x + (top - 1) * c.w] = c.col_top[x]
		c.surface[x] = top - 1
		cells.append(Vector2i(x, top))
	for x in range(maxi(0, sx - SPAN - 24), mini(c.w, sx + SINK_W + SPAN + 24)):
		c.reserved[x] = 2       # no town's street, ruin or pool on it: a road has room to grade to the deck
	# the bell under the deck, then the shaft, then the chamber
	for y in range(bottom, top - 1):
		var down := top - 2 - y
		var widen := 0
		if down >= 2 and down < 2 + BELL * 3:
			widen = mini(BELL, mini(down - 1, (2 + BELL * 3 - down) / 2))
		for x in range(sx - widen, sx + SINK_W + widen):
			if c.fg[x + y * c.w] != c.BEDROCK and (x >= sx and x < sx + SINK_W or y < c.surface[x] - 2):
				c.fg[x + y * c.w] = c.AIR        # the bell keeps two rows of ground over it
	var cx0 := sx + SINK_W / 2 - CHAMBER_W / 2
	c.carve_rect(cx0, bottom, cx0 + CHAMBER_W - 1, bottom + CHAMBER_H - 1)
	for x in range(cx0 - 1, cx0 + CHAMBER_W + 1):
		for y in range(bottom - 3, bottom):
			if c.fg[x + y * c.w] == c.AIR:
				c.fg[x + y * c.w] = c.STONE
	# ledges on the rope's west, one column clear of it; knobs on the east
	var y := top - 2 - BELL * 3 - LEDGE_EVERY
	var ledge_tile := c.fg[(sx - 1) + y * c.w] if y > 0 and c.solid[c.fg[(sx - 1) + y * c.w]] else c.STONE
	var k := 0
	while y > bottom + CHAMBER_H + 4:
		if k % 2 == 0:
			for x in range(sx, sx + SINK_W / 2 - 1):
				c.fg[x + y * c.w] = ledge_tile
		else:
			c.fg[(sx + SINK_W - 1) + y * c.w] = ledge_tile
		y -= LEDGE_EVERY + rng.randi_range(-2, 2)
		k += 1
	for yy in range(bottom, top):
		c.fg[rc + yy * c.w] = rope
	for x in range(sx, sx + SINK_W):
		if x != rc:
			c.fg[x + (top - 1) * c.w] = boards if absi(x - rc) > 1 else plank
	c.sinkholes.append({"x0": sx, "x1": sx + SINK_W - 1, "rope": rc, "top": top, "bottom": bottom, "biome": biome,
		"rows": rows, "chamber": [cx0, cx0 + CHAMBER_W - 1], "cells": cells})

# --- "glow" ----------------------------------------------------------------------------------

## The regions' lights: on open floors of the region's rock (and from ceilings where it hangs),
## a tile a cell, `every` columns apart on average. Never on or under anything built, in a town's
## cavern, or in the way of a ladder.
static func glow(c: GenContext, rng: RandomNumberGenerator) -> void:
	if c.regions.is_empty():
		return
	var keep_out: Array = []
	for cav: Dictionary in c.caverns:
		if cav["settled"]:
			var rx := int(cav["rx"])
			keep_out.append(Rect2i(int(cav["x"]) - rx * 3 / 2, int(cav["floor"]) - 4, rx * 3, int(cav["ry"]) * 2))
	for r: Dictionary in c.regions:
		var gd: Dictionary = def(String(r["biome"])).get("glow", {})
		if gd.is_empty():
			continue
		var tile := TileDefs.id(String(gd["tile"]))
		var rd := def(String(r["biome"]))
		var hosts := PackedByteArray()
		hosts.resize(256)
		hosts[TileDefs.id(String(rd["rock"]))] = 1
		hosts[TileDefs.id(String(rd["floor"]))] = 1
		if r["biome"] == "deep_lake":
			hosts[TileDefs.id(String(rd["shape"]["bed"]))] = 1
		var every := int(gd["every"])
		var hang := bool(gd.get("hang", false))
		for x in range(int(r["x0"]), int(r["x1"]) + 1):
			if rng.randi_range(0, every - 1) != 0:
				continue
			var placed := 0
			for y in range(maxi(2, int(r["y0"])), mini(c.h - 3, int(r["y1"]))):
				var i := x + y * c.w
				if c.fg[i] != c.AIR or c.bg[i] == c.W_COBBLE or c.bg[i] >= 40:
					continue
				var floor_ok := hosts[c.fg[i - c.w]] != 0 and c.fg[i + c.w] == c.AIR
				var roof_ok := hang and hosts[c.fg[i + c.w]] != 0 and c.fg[i - c.w] == c.AIR
				if not floor_ok and not roof_ok:
					continue
				if rng.randf() > 0.35 or _kept(keep_out, x, y):
					continue
				c.fg[i] = tile
				placed += 1
				if placed >= 6:
					break

static func _kept(rects: Array, x: int, y: int) -> bool:
	for rc: Rect2i in rects:
		if rc.has_point(Vector2i(x, y)):
			return true
	return false

# --- passages targets and meta ---------------------------------------------------------------

## [label, feet cell] the passages stage joins like sites: both ends of the lake's shore path and
## of every lava bridge, the top and bottom of every sinkhole, and the nadir floor.
static func targets(c: GenContext) -> Array:
	var out: Array = []
	var cells: Array = c.lake.get("crossing", {}).get("cells", [])
	if cells.size() >= 2:
		out.append(["lake west", cells[0]])
		out.append(["lake east", cells[-1]])
	for t: Dictionary in c.lava:
		for b: Dictionary in t["bridges"]:
			var bc: Array = b["cells"]
			out.append(["lava bridge %d west" % b["x0"], bc[0]])
			out.append(["lava bridge %d east" % b["x0"], bc[-1]])
	for i in c.sinkholes.size():
		var s: Dictionary = c.sinkholes[i]
		out.append(["sinkhole %d top" % i, Vector2i(int(s["rope"]) - 1, int(s["top"]))])
		out.append(["sinkhole %d bottom" % i, Vector2i(int(s["rope"]) - 1, int(s["bottom"]))])
	if c.nadir_floor.x >= 0:
		out.append(["nadir floor", c.nadir_floor])
	return out

## meta.ways (the sim's ways between the surface and the deeps besides the ascent, WorldSim._add_ways):
## each sinkhole, {kind, top: [x, y], bottom: [x, y], path: [[x, y]]}, the path the feet cells down its
## rope from the deck to the chamber floor. Written only with opts {"ways": true} until M6's
## integration: a link route per sinkhole moves the sim on every world (docs/tracks/deep.md).
static func ways(c: GenContext) -> Array:
	var out: Array = []
	for s: Dictionary in c.sinkholes:
		var x := int(s["rope"]) - 1
		var path: Array = []
		for y in range(int(s["top"]), int(s["bottom"]) - 1, -1):
			path.append([x, y])
		out.append({"kind": "sinkhole", "top": [x, int(s["top"])], "bottom": [x, int(s["bottom"])], "path": path})
	return out

static func _cells(path: Array) -> Array:
	var out: Array = []
	for p: Vector2i in path:
		out.append([p.x, p.y])
	return out

## world.meta.descent: the lake, the lava, the sinkholes, the ways in from the surface and the nadir
## floor, as plain arrays.
##   {lake: {x0, x1, water, bed, ceil, beach, islands, region (its row in meta.biomes), well,
##          crossing: {kind, cells}},
##    lava: [{x0, x1, region, pools: [{x0, x1, y, bridge}], bridges: [{x0, x1, y, cells}]}],
##    sinkholes: [{x0, x1, rope, top, bottom, biome, rows, chamber}], entrances: [[x, y]],
##    nadir: [x, y] (or []), ways: [{kind, x0, x1, y0, y1}]}
## ways: where a walker goes in from the surface, boxes under the ground at each: cave_mouth,
## sinkhole, under (a range's under-route), ramp (the ascent). A body in one has gone in there.
static func meta(c: GenContext) -> Dictionary:
	var lk := {}
	if not c.lake.is_empty():
		lk = c.lake.duplicate(true)
		lk["region"] = c.biomes.size() + c.regions.find(c.lake["region"])     # its row in meta.biomes
		lk["crossing"] = {"kind": "shore_path", "cells": _cells(c.lake["crossing"]["cells"])}
	var lv: Array = []
	for t: Dictionary in c.lava:
		var bridges: Array = []
		for b: Dictionary in t["bridges"]:
			bridges.append({"x0": b["x0"], "x1": b["x1"], "y": b["y"], "cells": _cells(b["cells"])})
		lv.append({"x0": t["x0"], "x1": t["x1"], "region": c.biomes.size() + c.regions.find(t["region"]), "pools": (t["pools"] as Array).duplicate(true), "bridges": bridges})
	var ents: Array = []
	var ways: Array = []
	for e: Vector2i in c.entrances:
		ents.append([e.x, e.y])
		ways.append({"kind": "cave_mouth", "x0": e.x - 10, "x1": e.x + 10, "y0": e.y - 40, "y1": e.y - 4})
	for s: Dictionary in c.sinkholes:
		ways.append({"kind": "sinkhole", "x0": int(s["x0"]) - 4, "x1": int(s["x1"]) + 4, "y0": int(s["bottom"]), "y1": int(s["top"]) - 4})
	for rg: Dictionary in c.ranges:
		var up: Array = rg.get("under", {}).get("path", [])
		for end: int in [0, up.size() - 1]:
			if up.is_empty():
				break
			var p: Vector2i = up[end]
			ways.append({"kind": "under", "x0": p.x - 30, "x1": p.x + 30, "y0": p.y - 40, "y1": p.y - 4})
	if not c.ascent.is_empty():
		var ax := int(c.ascent["x1"])
		var ay := int(c.ascent["y1"])
		ways.append({"kind": "ramp", "x0": ax - 30, "x1": ax + 30, "y0": ay - 30, "y1": ay - 4})
	var sinks: Array = []
	for s: Dictionary in c.sinkholes:
		var row := s.duplicate(true)
		row["cells"] = _cells(s["cells"])
		sinks.append(row)
	return {"lake": lk, "lava": lv, "sinkholes": sinks, "entrances": ents,
		"nadir": [c.nadir_floor.x, c.nadir_floor.y] if c.nadir_floor.x >= 0 else [], "ways": ways}
