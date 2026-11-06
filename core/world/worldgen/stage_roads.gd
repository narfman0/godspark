## Stage "roads": the surface roads between neighbouring settlements and the feet-cell path
## of every route (meta.routes[i].path, the Places contract).
##
## Surface roads ("road" routes, and the surface leg of the ascent route from the ramp mouth
## to its town) are graded between the street ends: the road follows the ground, closed over
## dips narrower than DIP (cave mouths, pits), never more than one tile up or down per
## column, cut where the ground is higher and filled (up to FILL_MAX deep) where it is lower;
## deeper or over a tunnel it is a bridge of walkway tiles. The road surface is the biome's
## road tile (c.col_road). A road path runs from one place's street end to the next one's.
## Deep routes (deep_road) follow the tiles: a breadth-first walk over feet cells (3 open
## rows, a floor below) with at most one tile up or down per column. When no such walk
## exists (caves still to be made passable) the route gets the path a jumper and faller
## would take, flagged "rough": true, or none.
## Signposts stand at the street ends where a road leaves and milestones along the way
## (dressing ids "signpost" and "milestone", when data/dressing.json has them).
extends RefCounted

const GenContext := preload("gen_context.gd")
const StagePlaces := preload("stage_places.gd")

const DIP := 14
const FILL_MAX := 3
const MILE := 64
const BODY_H := 3

static func run(c: GenContext, rng: RandomNumberGenerator) -> void:
	Dressing.ensure()
	var bridge := TileDefs.id("bridge")
	var graded := {}   # columns a road already runs over
	var by_id := {}
	for s: Dictionary in c.sites:
		by_id[int(s["id"])] = s
	for r: Dictionary in c.routes:
		var a: Dictionary = by_id[int(r["a"])]
		var b: Dictionary = by_id[int(r["b"])]
		var path: Array = []
		if r["kind"] == "road":
			var left := a if int(a["x"]) <= int(b["x"]) else b
			var right := b if left == a else a
			var ea := _end(c, left, 1)
			var eb := _end(c, right, -1)
			path = grade(c, ea, eb, bridge, rng)
			for p: Vector2i in path:
				graded[p.x] = true
			_signs(c, rng, path)
			if left != a:
				path.reverse()
		else:
			var surf_a := String(a["band"]) in ["surface", "sky"]
			var surf_b := String(b["band"]) in ["surface", "sky"]
			var ea := _end(c, a, signi(int(b["x"]) - int(a["x"])))
			var eb := _end(c, b, signi(int(a["x"]) - int(b["x"])))
			if (surf_a or surf_b) and not c.ascent.is_empty():
				# the ascent: grade the surface from the ramp mouth to the town's street end
				var town := a if surf_a else b
				var mouth := int(c.ascent["x1"])
				var dir := signi(int(town["x"]) - mouth)
				var te := _end(c, town, -dir)
				var px := mouth + dir * 6
				var p0 := Vector2i(px, c.surface[px] + 1)
				var crosses := false
				for x in range(mini(px, te.x), maxi(px, te.x) + 1):
					if graded.has(x):
						crosses = true   # a road already runs there: the walk follows it
						break
				if not crosses:
					var leg := grade(c, p0 if dir > 0 else te, te if dir > 0 else p0, bridge, rng)
					_signs(c, rng, leg)
				if surf_a:
					ea = te
				else:
					eb = te
			var res := walk(c, ea, eb, 1, 1)
			if res.is_empty():
				res = walk(c, ea, eb, 24, 6)
				r["rough"] = true
			if res.is_empty():
				res = walk(c, ea, eb, 0, 0, true)   # through open cells, ignoring gravity
			path = res
		var out: Array = []
		for p: Vector2i in path:
			out.append([p.x, p.y])
		r["path"] = out
	# a surface site a road was graded over (the surface ruin) stands on the new ground
	for s: Dictionary in c.sites:
		if s["kind"] != "settlement" and String(s["band"]) in ["surface", "sky"] and graded.has(int(s["x"])):
			s["y"] = c.surface[int(s["x"])] + 1

## The feet cell at a site's street end facing dir (+1 right, -1 left), or the site.
static func _end(c: GenContext, s: Dictionary, dir: int) -> Vector2i:
	var p: Dictionary = c.places.get(str(s["id"]), {})
	if p.is_empty():
		return Vector2i(int(s["x"]), int(s["y"]))
	var st: Array = p["street"]
	return Vector2i(int(st[1]) if dir > 0 else int(st[0]), int(st[2]))

## Grade a road from feet cell a to feet cell b (a.x < b.x); returns the feet cells.
static func grade(c: GenContext, a: Vector2i, b: Vector2i, bridge: int, _rng: RandomNumberGenerator) -> Array:
	var xa := a.x + 1
	var xb := b.x - 1
	var la := a.y - 1
	var lb := b.y - 1
	var out: Array = [a]
	var stairs_r := TileDefs.id("stairs_r")
	var stairs_l := TileDefs.id("stairs_l")
	if xb < xa:
		out.append(b)
		return out
	# close narrow dips: the ground under a span shorter than DIP is the lower of its rims
	var n := xb - xa + 1
	var h := PackedInt32Array()
	h.resize(n)
	for i in n:
		h[i] = c.surface[xa + i]
	# a morphological closing (max filter, then min filter, radius DIP / 2) fills dips
	# narrower than DIP without lifting the road beside them
	var k := DIP / 2
	var d := PackedInt32Array()
	d.resize(n)
	for i in n:
		var m := -1000000
		for j in range(i - k, i + k + 1):
			m = maxi(m, h[j] if j >= 0 and j < n else (la if j < 0 else lb))
		d[i] = m
	var t := PackedInt32Array()
	t.resize(n)
	for i in n:
		var m := 1000000
		for j in range(maxi(0, i - k), mini(n - 1, i + k) + 1):
			m = mini(m, d[j])
		t[i] = maxi(h[i], m)
	var prev := la
	for i in n:
		var x := xa + i
		var lo := maxi(la - (i + 1), lb - (n - i))
		var hi := mini(la + (i + 1), lb + (n - i))
		var r := clampi(clampi(t[i], lo, hi), prev - 1, prev + 1)
		var prev0 := prev
		prev = r
		var nat := h[i]
		if r < nat:
			for yy in range(r + 1, nat + 1):
				c.fg[x + yy * c.w] = c.AIR
				c.bg[x + yy * c.w] = 0
			c.fg[x + r * c.w] = c.col_road[x]
			c.surface[x] = r
		elif r > nat:
			var tunnel := false
			for yy in range(nat + 1, r + 1):
				if c.bg[x + yy * c.w] == c.W_COBBLE:
					tunnel = true
			if r - nat <= FILL_MAX and not tunnel:
				for yy in range(nat, r):      # from the old top: it is buried now
					c.fg[x + yy * c.w] = c.col_soil[x]
				c.fg[x + r * c.w] = c.col_road[x]
				c.surface[x] = r
			elif r != prev0:
				# a sloping span over air is a flight of stairs (one-way like the bridge, and
				# walkable up: a walkway cannot be stepped up onto)
				c.fg[x + r * c.w] = stairs_r if r > prev0 else stairs_l
			else:
				c.fg[x + r * c.w] = bridge
		else:
			c.fg[x + r * c.w] = c.col_road[x]
		for yy in range(r + 1, mini(c.h - 1, r + 1 + BODY_H + 1)):
			if c.solid[c.fg[x + yy * c.w]] != 0:
				c.fg[x + yy * c.w] = c.AIR
		out.append(Vector2i(x, r + 1))
	out.append(b)
	return out

## Signposts at both ends of a graded road, milestones along it.
static func _signs(c: GenContext, rng: RandomNumberGenerator, path: Array) -> void:
	var sign := Dressing.id("signpost")
	var mile := Dressing.id("milestone")
	if path.size() < 8:
		return
	if sign >= 0:
		for p: Vector2i in [path[2], path[path.size() - 3]]:
			_dress(c, rng, sign, p)
	if mile >= 0:
		var k := MILE
		while k < path.size() - MILE / 2:
			_dress(c, rng, mile, path[k])
			k += MILE

static func _dress(c: GenContext, rng: RandomNumberGenerator, id: int, p: Vector2i) -> void:
	if c.solid[c.fg[p.x + (p.y - 1) * c.w]] == 0:
		return   # on a bridge
	c.objects.append_array(PackedInt32Array([id, p.x, p.y, rng.randi() & 0xff]))

static func feet_ok(c: GenContext, x: int, y: int) -> bool:
	if x < 0 or x >= c.w or y < 1 or y + BODY_H >= c.h:
		return false
	for k in BODY_H:
		if c.solid[c.fg[x + (y + k) * c.w]] != 0:
			return false
	var under := c.fg[x + (y - 1) * c.w]
	return c.solid[under] != 0 or TileDefs.platform[under] != 0 or TileDefs.ladder[under] != 0

## Breadth-first walk over feet cells from a to b, each step one column with at most `up`
## tiles up and `down` tiles down (both ways walkable when both are 1). [] when none.
## fly: ignore floors (any cell with BODY_H open rows; 4-neighbour steps), the last resort.
static func walk(c: GenContext, a: Vector2i, b: Vector2i, down: int, up: int, fly := false) -> Array:
	var sa := _settle(c, a)
	var sb := _settle(c, b)
	if sa.x < 0 or sb.x < 0:
		return []
	var x0 := maxi(0, mini(sa.x, sb.x) - 400)
	var x1 := mini(c.w - 1, maxi(sa.x, sb.x) + 400)
	var y0 := maxi(1, mini(sa.y, sb.y) - 120)
	var y1 := mini(c.h - BODY_H - 1, maxi(sa.y, sb.y) + 120)
	var bw := x1 - x0 + 1
	var bh := y1 - y0 + 1
	var prev := PackedInt32Array()
	prev.resize(bw * bh)
	prev.fill(-2)
	var q := PackedInt32Array()
	var si := (sa.x - x0) + (sa.y - y0) * bw
	var gi := (sb.x - x0) + (sb.y - y0) * bw
	prev[si] = -1
	q.append(si)
	var head := 0
	var solid := c.solid
	var fg := c.fg
	var plat := TileDefs.platform
	var lad := TileDefs.ladder
	var w := c.w
	var found := false
	while head < q.size():
		var pi := q[head]
		head += 1
		if pi == gi:
			found = true
			break
		var px := x0 + pi % bw
		var py := y0 + pi / bw
		if fly:
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx := px + d.x
				var ny := py + d.y
				if nx < x0 or nx > x1 or ny < y0 or ny > y1:
					continue
				var ni := (nx - x0) + (ny - y0) * bw
				if prev[ni] != -2:
					continue
				var open := true
				for k in BODY_H:
					if solid[fg[nx + (ny + k) * w]] != 0:
						open = false
						break
				if open:
					prev[ni] = pi
					q.append(ni)
			continue
		for dx in [-1, 1]:
			var nx: int = px + dx
			if nx < x0 or nx > x1:
				continue
			# how far up from here there is headroom
			var room := 0
			while room < up and solid[fg[px + (py + BODY_H + room) * w]] == 0:
				room += 1
			for dy in range(-down, room + 1):
				var ny := py + dy
				if ny < y0 or ny > y1:
					continue
				var ni := (nx - x0) + (ny - y0) * bw
				if prev[ni] != -2:
					continue
				var ok := true
				for k in BODY_H:
					if solid[fg[nx + (ny + k) * w]] != 0:
						ok = false
						break
				if not ok:
					continue
				var under := fg[nx + (ny - 1) * w]
				if solid[under] == 0 and plat[under] == 0 and lad[under] == 0:
					continue
				prev[ni] = pi
				q.append(ni)
	if not found:
		return []
	var out: Array = []
	var k := gi
	while k != -1:
		out.append(Vector2i(x0 + k % bw, y0 + k / bw))
		k = prev[k]
	out.reverse()
	return out

static func _open(c: GenContext, x: int, y: int) -> bool:
	if x < 0 or x >= c.w or y < 1 or y + BODY_H >= c.h:
		return false
	for k in BODY_H:
		if c.solid[c.fg[x + (y + k) * c.w]] != 0:
			return false
	return true

static func _clear_above(c: GenContext, x: int, y: int, dy: int) -> bool:
	for k in range(BODY_H, BODY_H + dy):
		if c.solid[c.fg[x + (y + k) * c.w]] != 0:
			return false
	return true

## The feet cell at or just below p (p itself if it is one), or (-1, -1).
static func _settle(c: GenContext, p: Vector2i) -> Vector2i:
	for dy in range(0, -6, -1):
		if feet_ok(c, p.x, p.y + dy):
			return Vector2i(p.x, p.y + dy)
	for dy in range(1, 4):
		if feet_ok(c, p.x, p.y + dy):
			return Vector2i(p.x, p.y + dy)
	return Vector2i(-1, -1)
