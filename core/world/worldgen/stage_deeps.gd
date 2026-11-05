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

static func caverns(c: GenContext, rng: RandomNumberGenerator) -> void:
	var db: Array = c.bands["deeps"]
	var bh := c.band_h("deeps")
	var n := maxi(2, int(5 * c.sx()))
	var slot := c.w / n
	var shape := c.noise(rng, 1.0 / 28.0, 2)
	var lobes := c.noise(rng, 1.0 / 85.0, 1)
	c.caverns = []
	for i in n:
		var ry := int(bh * rng.randf_range(0.17, 0.27))
		var rx := int(minf(ry * rng.randf_range(2.0, 3.4), slot * 0.42))
		var cx := slot * i + slot / 2 + rng.randi_range(-slot / 8, slot / 8)
		cx = clampi(cx, rx + 8, c.w - rx - 9)
		var cy: int = db[0] + int(bh * rng.randf_range(0.38, 0.62))
		var floor_y: int = cy - int(ry * 0.55)
		_carve_cavern(c, shape, lobes, cx, cy, rx, ry, floor_y)
		c.caverns.append({"x": cx, "cy": cy, "rx": rx, "ry": ry, "floor": floor_y, "settled": false})
	# Settle the biggest one or two.
	var order: Array = range(n)
	order.sort_custom(func(a: int, b: int) -> bool:
		var ca: Dictionary = c.caverns[a]
		var cb: Dictionary = c.caverns[b]
		return ca["rx"] * ca["ry"] > cb["rx"] * cb["ry"] or (ca["rx"] * ca["ry"] == cb["rx"] * cb["ry"] and a < b))
	var settle := 2 if n >= 3 else 1
	if n == 2:
		settle = 2  # small worlds: two deep sites so a deep road links sites
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
			if y >= fy and d < 1.0:
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
	var pts: Array = []
	for cav: Dictionary in c.caverns:
		pts.append(Vector2i(cav["x"], cav["floor"]))
	pts.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)
	var wiggle := c.noise(rng, 1.0 / 160.0, 2)
	var amp := bh * 0.12
	c.road_x0 = pts[0].x
	c.road_x1 = pts[-1].x
	c.road_floor = PackedInt32Array()
	c.road_floor.resize(c.road_x1 - c.road_x0 + 1)
	var lo: int = db[0] + 4
	var hi: int = db[1] - GenContext.ROAD_H - 4
	var f: int = pts[0].y
	var seg := 0
	for x in range(c.road_x0, c.road_x1 + 1):
		while seg < pts.size() - 2 and x > pts[seg + 1].x:
			seg += 1
		var a: Vector2i = pts[seg]
		var b: Vector2i = pts[seg + 1]
		var t := float(x - a.x) / maxf(1.0, float(b.x - a.x))
		var target := lerpf(a.y, b.y, smoothstep(0.0, 1.0, t)) + wiggle.get_noise_1d(x) * amp * sin(PI * t)
		var ti := clampi(roundi(target), lo, hi)
		f += clampi(ti - f, -1, 1)  # never steeper than one tile per column
		c.road_floor[x - c.road_x0] = f
		c.carve_road_column(x, f, GenContext.ROAD_H)

## Walks a 45-degree ramp from (x, y) in direction dir, rising (up = 1) or falling
## (up = -1), with short flat landings; returns the cells of its floor (first open row).
## stop(x, y) decides when it has arrived.
static func _ramp_path(c: GenContext, rng: RandomNumberGenerator, x: int, y: int, dir: int, up: int,
		stop: Callable, max_steps: int) -> Array:
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
			if rng.randf() < 0.04:
				flat_left = rng.randi_range(3, 7)
		path.append(Vector2i(x, y))
	return []

static func _carve_path(c: GenContext, path: Array, tall: int) -> void:
	for p: Vector2i in path:
		if p.y - 1 > c.ground[p.x]:
			c.carve_rect(p.x, p.y, p.x, p.y + tall - 1)  # out in the open: no paving in the air
		else:
			c.carve_road_column(p.x, p.y, tall)

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
		for dir: int in [1, -1]:
			var sx: int = cav["x"] + dir * int(cav["rx"] * 0.6)
			var sub := RandomNumberGenerator.new()
			sub.seed = rng.seed + ci * 2 + (1 if dir > 0 else 0)
			var path := _ramp_path(c, sub, sx, int(cav["floor"]), dir, 1, stop, c.h * 3)
			if path.is_empty():
				continue
			var end: Vector2i = path[-1]
			var gap := _flat_gap(c, end.x)
			if gap < 24:
				continue
			var score: float = float(gap) + path.size() * 0.05
			if score < best_score:
				best_score = score
				best = path
				best_meta = {"cavern": ci, "x0": sx, "y0": int(cav["floor"]), "x1": end.x, "y1": end.y,
					"steps": path.size()}
	if best.is_empty():
		c.ascent = {}
		return
	_carve_path(c, best, GenContext.RAMP_H)
	c.ascent = best_meta

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
	var sx: int = cav["x"] + dir * int(cav["rx"] * 0.6)
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
		"x0": sx}

static func ascent_uses(c: GenContext, ci: int) -> bool:
	return not c.ascent.is_empty() and int(c.ascent["cavern"]) == ci
