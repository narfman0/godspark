## The first deep band, the start of the Underdark:
##   "caverns"   a few very large caverns with flat floors spread across the deeps band;
##               the biggest one or two are marked settled (deep settlements go there).
##   "deep_road" a long, gently sloped paved tunnel (ROAD_H clear) linking the caverns
##               left to right through their floors.
##   "ascent"    a 45-degree paved ramp from a settled cavern up to the surface, coming out
##               beside a settlement flat, so raiders below can reach the roads above.
##   "portal"    a chamber in the nadir band under one cavern, reached by a ramp down.
extends RefCounted

const GenContext := preload("gen_context.gd")
const Barriers := preload("stage_barriers.gd")

static func caverns(c: GenContext, rng: RandomNumberGenerator) -> void:
	var db: Array = c.bands["deeps"]
	var bh := c.band_h("deeps")
	var n := maxi(2, int(5 * c.sx()))
	var slot := c.w / n
	var shape := c.noise(rng, 1.0 / 28.0, 2)
	var lobes := c.noise(rng, 1.0 / 85.0, 1)
	c.caverns = []
	var prev_floor := -1
	for i in n:
		# Sizes in tiles, not band fractions, so big worlds get more caverns, not taller ones.
		var ry := int(minf(bh * rng.randf_range(0.17, 0.27), rng.randf_range(48.0, 75.0)))
		var rx := int(minf(ry * rng.randf_range(2.0, 3.4), slot * 0.42))
		var cx := slot * i + slot / 2 + rng.randi_range(-slot / 8, slot / 8)
		cx = clampi(cx, rx + 8, c.w - rx - 9)
		var cy: int = db[0] + int(bh * rng.randf_range(0.3, 0.7))
		cy = clampi(cy, db[0] + int(bh * 0.25), db[1] - ry - 8)
		var floor_y: int = cy - int(ry * 0.55)
		if prev_floor >= 0:
			# keep the floor within reach of the deep road (at most 1 tile up per 3 across)
			var reach := maxi(4, (slot - 2 * rx) / 3)
			floor_y = clampi(floor_y, prev_floor - reach, prev_floor + reach)
		floor_y = clampi(floor_y, db[0] + 8, db[1] - int(ry * 1.45) - 8)
		cy = floor_y + int(ry * 0.55)
		prev_floor = floor_y
		_carve_cavern(c, shape, lobes, cx, cy, rx, ry, floor_y)
		c.caverns.append({"x": cx, "cy": cy, "rx": rx, "ry": ry, "floor": floor_y, "settled": false})
	# Settle the biggest one or two.
	var order: Array = range(n)
	order.sort_custom(func(a: int, b: int) -> bool:
		var ca: Dictionary = c.caverns[a]
		var cb: Dictionary = c.caverns[b]
		return ca["rx"] * ca["ry"] > cb["rx"] * cb["ry"] or (ca["rx"] * ca["ry"] == cb["rx"] * cb["ry"] and a < b))
	# Two deep settlements (so a deep road links sites), more in big worlds.
	var settle := maxi(2, n / 4)
	for k in settle:
		c.caverns[order[k]]["settled"] = true

static func _carve_cavern(c: GenContext, shape: FastNoiseLite, lobes: FastNoiseLite, cx: int, cy: int, rx: int, ry: int, floor_y: int) -> void:
	var x0 := cx - int(rx * 1.5) - 2
	var y0 := floor_y - 3
	var gw := 2 * (cx - x0) + 1
	var gh := cy + int(ry * 1.5) + 2 - y0
	var nb := GenContext.noise_bytes(shape, x0, y0, gw, gh)
	var nl := GenContext.noise_bytes(lobes, x0, y0, gw, gh)
	for gy in gh:
		var y := y0 + gy
		var dy := float(y - cy) / ry
		for gx in gw:
			var x := x0 + gx
			if x < 0 or x >= c.w:
				continue
			var dx := float(x - cx) / rx
			var wob := (nb[gx + gy * gw] - 128) / 128.0
			var lobe := (nl[gx + gy * gw] - 128) / 128.0
			var d := dx * dx + dy * dy + wob * 0.35 + lobe * 0.9
			var i := x + y * c.w
			# flat floor in the middle, curving up toward the walls
			var fy := floor_y + int(maxf(0.0, absf(dx) - 0.6) * ry * 1.2)
			# the middle of the floor is always open and level: settlements and the road go there
			var plateau := absf(dx) < 0.55 and y >= floor_y and y <= floor_y + maxi(8, int(ry * 0.6))
			if plateau or (y >= fy and d < 1.0):
				if c.fg[i] != c.BEDROCK:
					c.fg[i] = c.AIR
			elif y < floor_y and y >= floor_y - 3 and absf(dx) < 0.75:
				c.fg[i] = c.SLATE  # a sound floor, even over older caves
	# A few stalagmite pillars, away from the middle where people settle.
	var seed_x := absi(cx * 7919 + cy * 104729)
	for k in 2:
		var px := cx + (1 if k == 0 else -1) * int(rx * (0.55 + float((seed_x >> (k * 3)) % 20) / 100.0))
		var top := cy + int(ry * 0.4)
		for y in range(floor_y, top):
			var half := 2 + int(4.0 * (1.0 - float(y - floor_y) / maxf(1.0, float(top - floor_y))))
			if y > top - 3 and (seed_x >> k) % 2 == 0:
				break  # some pillars don't reach the roof
			for x in range(px - half, px + half + 1):
				c.set_tile(x, y, c.SLATE)

static func deep_road(c: GenContext, rng: RandomNumberGenerator) -> void:
	var db: Array = c.bands["deeps"]
	var bh := c.band_h("deeps")
	# Level plateaus [x0, x1, floor] through each cavern, left to right.
	var flats: Array = []
	for cav: Dictionary in c.caverns:
		var p := int(int(cav["rx"]) * 0.45)
		flats.append([int(cav["x"]) - p, int(cav["x"]) + p, int(cav["floor"])])
	flats.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var wiggle := c.noise(rng, 1.0 / 160.0, 2)
	var amp := bh * 0.12
	c.road_x0 = flats[0][0]
	c.road_x1 = flats[-1][1]
	c.road_floor = PackedInt32Array()
	c.road_floor.resize(c.road_x1 - c.road_x0 + 1)
	var lo: int = db[0] + 4
	var hi: int = db[1] - GenContext.ROAD_H - 4
	var f: int = flats[0][2]
	var seg := 0
	for x in range(c.road_x0, c.road_x1 + 1):
		while seg < flats.size() - 1 and x > flats[seg][1] and x >= flats[seg + 1][0]:
			seg += 1
		var target: float
		var a: Array = flats[seg]
		if x <= a[1] or seg == flats.size() - 1:
			target = a[2]
		else:
			var b: Array = flats[seg + 1]
			var t := float(x - a[1]) / maxf(1.0, float(b[0] - a[1]))
			target = lerpf(a[2], b[2], smoothstep(0.0, 1.0, t)) + wiggle.get_noise_1d(x) * amp * sin(PI * t)
		var ti := clampi(roundi(target), lo, hi)
		f += clampi(ti - f, -1, 1)  # never steeper than one tile per column
		c.road_floor[x - c.road_x0] = f
		c.carve_road_column(x, f, GenContext.ROAD_H)

## Walks a 45-degree ramp from (x, y) in direction dir, rising (up = 1) or falling
## (up = -1), with short flat landings; returns the cells of its floor (first open row).
## stop(x, y) decides when it has arrived.
static func _ramp_path(c: GenContext, rng: RandomNumberGenerator, x: int, y: int, dir: int, up: int,
		stop: Callable, max_steps: int, landing_p := 0.04) -> Array:
	var path: Array = []
	var flat_left := 0
	for i in max_steps:
		if stop.call(x, y):
			return path
		x += dir
		if x < 2 or x > c.w - 3:
			return []
		if flat_left > 0:
			flat_left -= 1
		else:
			y += up
			if rng.randf() < landing_p:
				flat_left = rng.randi_range(3, 7)
		path.append(Vector2i(x, y))
	return []

static func _carve_path(c: GenContext, path: Array, tall: int) -> void:
	for p: Vector2i in path:
		if p.y - 1 > c.ground[p.x]:
			c.carve_rect(p.x, p.y, p.x, p.y + tall - 1)  # out in the open: no paving in the air
		else:
			c.carve_road_column(p.x, p.y, tall, false)

static func ascent(c: GenContext, rng: RandomNumberGenerator) -> void:
	# Try each settled cavern and both directions; keep the ramp that surfaces closest to a
	# settlement flat without coming up inside one. Paths are simulated before carving.
	var best: Array = []
	var best_score := INF
	var best_meta := {}
	var stop := func(px: int, py: int) -> bool: return py > c.ground[px] + 1
	for ci in c.caverns.size():
		var cav: Dictionary = c.caverns[ci]
		if not cav["settled"]:
			continue
		for k in 24:
			var dir := 1 if k % 2 == 0 else -1
			var sx: int = cav["x"] + dir * int(cav["rx"] * [0.4, 0.3, 0.15, 0.0][(k / 2) % 4])
			var landing_p: float = [0.04, 0.15, 0.3][k / 8]  # more landings: the mouth lands farther out
			var sub := RandomNumberGenerator.new()
			sub.seed = rng.seed + ci * 64 + k
			var path := _ramp_path(c, sub, sx, int(cav["floor"]), dir, 1, stop, c.h * 4, landing_p)
			if path.is_empty():
				continue
			var end: Vector2i = path[-1]
			var gap := _flat_gap(c, end.x)
			if gap < 6 or _tail_under_flat(c, path, 16) or Barriers.reserved_in(c, end.x - 16, end.x + 16):
				continue
			var score: float = float(gap) + path.size() * 0.05 + k / 8 * 40.0
			if score < best_score:
				best_score = score
				best = path
				best_meta = {"cavern": ci, "x0": sx, "y0": int(cav["floor"]), "x1": end.x, "y1": end.y,
					"steps": path.size()}
	if best.is_empty():
		c.ascent = {}
		return
	_carve_path(c, best, GenContext.RAMP_H)
	best_meta["path"] = best      # feet cells, for the passages stage (holes where it crosses a cave)
	c.ascent = best_meta

## True if any of the last n path columns lies under (or within 3 of) a settlement flat:
## a ramp that close to the surface would break the settlement's ground.
static func _tail_under_flat(c: GenContext, path: Array, n: int) -> bool:
	for i in range(maxi(0, path.size() - n), path.size()):
		if _flat_gap(c, path[i].x) < 3:
			return true
	return false

## Horizontal distance from x to the nearest flat (0 when inside one).
static func _flat_gap(c: GenContext, x: int) -> int:
	var gap := 1 << 30
	for f: Dictionary in c.flats:
		var d := maxi(int(f["x0"]) - x, x - int(f["x1"]))
		gap = mini(gap, maxi(0, d))
	return gap

static func portal(c: GenContext, rng: RandomNumberGenerator) -> void:
	var nb: Array = c.bands["nadir"]
	# Prefer an unsettled cavern; the middle-most one otherwise.
	var ci := -1
	var best := INF
	for i in c.caverns.size():
		var cav: Dictionary = c.caverns[i]
		var score: float = absf(int(cav["x"]) - c.w * 0.5) + (0.0 if not cav["settled"] else c.w)
		if ascent_uses(c, i):
			score += c.w * 2
		if score < best:
			best = score
			ci = i
	var cav: Dictionary = c.caverns[ci]
	var dir := 1 if int(cav["x"]) < c.w / 2 else -1
	var cw := clampi(int(36 * c.sx()), 24, 48)
	var ch := clampi(int(14 * c.sy()), 9, 16)
	var bed_max := 0
	for b in c.bed:
		bed_max = maxi(bed_max, b)
	var floor_y := maxi(bed_max + 3, (nb[0] + nb[1]) / 2 - ch / 2)
	var sx: int = cav["x"] + dir * int(cav["rx"] * 0.4)  # inside the open plateau
	var stop := func(_px: int, py: int) -> bool: return py <= floor_y
	var path := _ramp_path(c, rng, sx, int(cav["floor"]), dir, -1, stop, c.h * 3)
	if path.is_empty():
		c.portal = {}
		return
	_carve_path(c, path, GenContext.RAMP_H)
	var end: Vector2i = path[-1]
	var x0 := end.x if dir > 0 else end.x - cw + 1
	c.carve_rect(x0, floor_y, x0 + cw - 1, floor_y + ch - 1)
	c.wall_rect(x0, floor_y, x0 + cw - 1, floor_y + ch - 1, c.W_COBBLE)
	c.fill_rect(x0, floor_y - 1, x0 + cw - 1, floor_y - 1, c.COBBLE)
	c.portal = {"cavern": ci, "x": x0 + cw / 2, "y": floor_y, "w": cw, "steps": path.size(),
		"x0": sx, "path": path}

static func ascent_uses(c: GenContext, ci: int) -> bool:
	return not c.ascent.is_empty() and int(c.ascent["cavern"]) == ci
