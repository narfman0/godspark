## Stage "passages": guarantees a world a Medium walker crosses both ways without digging.
## Runs after "ruins" (the last carving stage) and before "ores", so it sees every cave,
## cavern, the deep road, the ascent, the portal ramp and the buried ruins, and nothing it
## does depends on sites, places or routes (those come later).
##
## 1. Standing spots: a Medium body is a 2 x 3 box of cells; a spot (x, y) is that box with
##    its left column x and feet row y, free of solid tiles, with a solid or one-way tile
##    under one of its columns.
## 2. Two-way moves join spots (union-find): walking to the next column with a step of at
##    most one row (headroom checked); from the ends of floors, jumps up to JUMP_UP rows and
##    across gaps of up to JUMP_ACROSS columns through open air (falls back down the same way
##    are free, so each is two-way); a ladder or rope joins every spot along it.
## 3. The component with the first surface settlement flat (where players spawn) is the
##    network. Every other component of at least MIN_SPOTS spots (every cave region and
##    cavern, buried ruins, lairs-to-be) is joined to it with the cheapest believable feature
##    to the nearest network spot: a carved passage with steps (stairs in the deeps), a
##    walkway bridge over open air, and for steep joins a shaft with a ladder (surface band:
##    roots) or a hanging rope (caves) or a ladder beside built stairs (deeps). Joined parts
##    become network, so later ones may join to them.
## 4. Unsettled deep caverns get crisscrossing walkways and staircases at two heights.
## Settlement flats and settled caverns are off-limits to carving and building.
## Deterministic (the stage RNG only picks feature variants).
extends RefCounted

const GenContext := preload("gen_context.gd")

const JUMP_UP := 4
const JUMP_ACROSS := 4
const MIN_SPOTS := 4
## Search radius (tiles) for the nearest network spot, by pass.
const RADII := [24, 48, 96, 200, 400]
## Tunnel clear height (rows above the floor): a step up needs the box's 3 rows plus one
## over the column it leaves.
const TALL := 5
## Network spots kept per 16 x 16 block, and component spots sampled, when aiming a join.
const BUCKET_KEEP := 6
const SAMPLES := 64

static var stats := {}

static func run(c: GenContext, rng: RandomNumberGenerator) -> void:
	if not bool(c.opts.get("passages", true)):
		stats = {"skipped": true}
		return            # opts {"passages": false}: the world as it was before this stage (tools)
	var p := Passer.new(c, rng)
	p.build_spots()
	p.join_moves()
	p.connect_all()
	p.caverns()
	stats = p.stats
	# A second look at the world as it now is: a later join may have cut into an earlier one,
	# and the cavern works add ways; whatever is still apart is joined again.
	var p2 := Passer.new(c, rng)
	p2.build_spots()
	p2.join_moves()
	p2.connect_all()
	stats["second"] = {"joined": p2.stats["joined"], "left": p2.stats["left"], "features": p2.stats["features"],
		"ms": int(p2.stats["spots_ms"]) + int(p2.stats["moves_ms"]) + int(p2.stats["join_ms"])}
	if p.log_joins:
		stats["log"] = p.join_log

## Spots that `x, y` area may belong to: for tools and tests.
static func spot_ok(c: GenContext, x: int, y: int) -> bool:
	return Passer.spot_at(c, x, y)

class Passer extends RefCounted:
	var c: GenContext
	var rng: RandomNumberGenerator
	var w := 0
	var h := 0
	var top := 0
	var oneway := PackedByteArray()      # by tile id: platform, stairs (a ladder's top rung also holds)
	var climb := PackedByteArray()       # by tile id: ladder or rope
	var sid := PackedInt32Array()        # cell -> spot id, -1 none
	var spx := PackedInt32Array()
	var spy := PackedInt32Array()
	var parent := PackedInt32Array()
	var net := PackedByteArray()         # spot id -> 1 when part of the network
	var buckets := {}                    # (bx, by) key -> PackedInt32Array of network spot ids
	var stats := {}
	var ladder := 0
	var rope := 0
	var platform := 0
	var stairs_r := 0
	var stairs_l := 0
	var rubble := 0
	var no_go: Array = []
	var ruins: Array = []                # Rect2i around each buried ruin room
	var keep := PackedByteArray()        # floors joins laid or stand on: never cut later
	var log_joins := false
	var join_log: Array = []
	var jump_up := JUMP_UP
	var jump_across := JUMP_ACROSS                # Rect2i areas never carved or built in

	func _init(ctx: GenContext, r: RandomNumberGenerator) -> void:
		c = ctx
		rng = r
		w = c.w
		h = c.h
		jump_up = int(c.opts.get("jump_up", JUMP_UP))
		log_joins = bool(c.opts.get("log_joins", false))
		jump_across = int(c.opts.get("jump_across", JUMP_ACROSS))
		ladder = TileDefs.id("ladder")
		rope = TileDefs.id("rope")
		platform = TileDefs.id("platform")
		stairs_r = TileDefs.id("stairs_r")
		stairs_l = TileDefs.id("stairs_l")
		rubble = TileDefs.id("rubble")
		var n := TileDefs.solid.size()
		oneway.resize(n)
		climb.resize(n)
		for i in n:
			oneway[i] = 1 if TileDefs.platform[i] != 0 else 0
			climb[i] = 1 if TileDefs.ladder[i] != 0 else 0
		for x in w:
			top = maxi(top, c.ground[x] + 40)
		top = mini(top, h - 4)
		for f: Dictionary in c.flats:
			no_go.append(Rect2i(int(f["x0"]) - 4, int(f["y"]) - 24, int(f["x1"]) - int(f["x0"]) + 9, 64))
		for room: Dictionary in c.buried_rooms:
			var rw := int(room["w"])
			ruins.append(Rect2i(int(room["x"]) - rw / 2 - 2, int(room["y"]) - 2, rw + 4, 14))
		for cav: Dictionary in c.caverns:
			if cav["settled"]:
				var rx := int(cav["rx"])
				no_go.append(Rect2i(int(cav["x"]) - rx * 3 / 4, int(cav["floor"]) - 2, rx * 3 / 2, int(cav["ry"])))

	static func spot_at(ctx: GenContext, x: int, y: int) -> bool:
		if x < 0 or x + 1 >= ctx.w or y < 1 or y + 2 >= ctx.h:
			return false
		for dy in 3:
			if ctx.is_solid(x, y + dy) or ctx.is_solid(x + 1, y + dy):
				return false
		var a := ctx.fg[x + (y - 1) * ctx.w]
		var b := ctx.fg[x + 1 + (y - 1) * ctx.w]
		return ctx.solid[a] != 0 or ctx.solid[b] != 0 or TileDefs.platform[a] != 0 or TileDefs.platform[b] != 0 \
			or TileDefs.ladder[a] != 0 or TileDefs.ladder[b] != 0

	# --- 1. spots ----------------------------------------------------------------------------

	func build_spots() -> void:
		var t0 := Time.get_ticks_usec()
		var fg := c.fg
		var solid := c.solid
		sid.resize(w * h)
		sid.fill(-1)
		keep.resize(w * h)
		# open run above each cell, capped at 3, column by column (two columns at a time)
		var up_a := PackedByteArray()
		var up_b := PackedByteArray()
		up_a.resize(top + 4)
		up_b.resize(top + 4)
		_col_up(0, up_b)
		for x in w - 1:
			var tmp := up_a
			up_a = up_b
			up_b = tmp
			_col_up(x + 1, up_b)
			for y in range(1, top):
				if up_a[y] < 3 or up_b[y] < 3:
					continue
				var a := fg[x + (y - 1) * w]
				var b := fg[x + 1 + (y - 1) * w]
				if solid[a] != 0 or solid[b] != 0 or oneway[a] != 0 or oneway[b] != 0 \
						or (climb[a] != 0 and climb[fg[x + y * w]] == 0) or (climb[b] != 0 and climb[fg[x + 1 + y * w]] == 0):
					sid[x + y * w] = spx.size()
					spx.append(x)
					spy.append(y)
		parent.resize(spx.size())
		for i in parent.size():
			parent[i] = i
		net.resize(spx.size())
		stats["spots"] = spx.size()
		stats["spots_ms"] = (Time.get_ticks_usec() - t0) / 1000

	func _col_up(x: int, out: PackedByteArray) -> void:
		var fg := c.fg
		var solid := c.solid
		var run := 0
		for y in range(top + 3, -1, -1):
			if solid[fg[x + y * w]] != 0:
				run = 0
			elif run < 3:
				run += 1
			out[y] = run

	# --- 2. two-way moves ----------------------------------------------------------------------

	func find(i: int) -> int:
		var r := i
		while parent[r] != r:
			r = parent[r]
		while parent[i] != r:
			var nx := parent[i]
			parent[i] = r
			i = nx
		return r

	func union(a: int, b: int) -> void:
		var ra := find(a)
		var rb := find(b)
		if ra != rb:
			if ra < rb:
				parent[rb] = ra
			else:
				parent[ra] = rb

	func open(x: int, y: int) -> bool:
		return x >= 0 and y >= 0 and x < w and y < h and c.solid[c.fg[x + y * w]] == 0

	func spot(x: int, y: int) -> int:
		if x < 0 or y < 0 or x >= w or y >= h:
			return -1
		return sid[x + y * w]

	func join_moves() -> void:
		var t0 := Time.get_ticks_usec()
		var edges := 0
		for s in spx.size():
			var x := spx[s]
			var y := spy[s]
			var walk_r := false
			var walk_l := spot(x - 1, y) >= 0 or (spot(x - 1, y + 1) >= 0 and open(x + 1, y + 3)) \
				or (spot(x - 1, y - 1) >= 0 and open(x - 1, y + 2) and open(x, y + 2))
			var t := spot(x + 1, y)
			if t >= 0:
				union(s, t)
				walk_r = true
			t = spot(x + 1, y + 1)
			if t >= 0 and open(x, y + 3):
				union(s, t)
				walk_r = true
			t = spot(x + 1, y - 1)
			if t >= 0 and open(x + 2, y + 2) and open(x + 1, y + 2):
				union(s, t)
				walk_r = true
			if walk_r and walk_l:
				continue
			edges += 1
			# the end of a floor: jumps up (and so falls back down) and across gaps
			for dy in range(2, jump_up + 1):
				for dx in range(-3, 4):
					t = spot(x + dx, y + dy)
					if t >= 0 and _clear_up(x, y, dx, dy):
						union(s, t)
			for dx in range(2, jump_across + 2):
				for dy in range(-1, 2):
					for dir: int in [1, -1]:
						t = spot(x + dx * dir, y + dy)
						if t >= 0 and _clear_across(x, y, dx * dir, dy):
							union(s, t)
		# ladders and ropes: every spot along a climbable run
		var fg := c.fg
		for x in w:
			var y := 1
			while y < top:
				if climb[fg[x + y * w]] == 0:
					y += 1
					continue
				var y1 := y
				while y1 < top and climb[fg[x + y1 * w]] != 0:
					y1 += 1
				var first := -1
				for yy in range(y, y1 + 1):
					for xx: int in [x - 1, x]:
						var k := spot(xx, yy)
						if k >= 0:
							if first < 0:
								first = k
							else:
								union(first, k)
				y = y1
		stats["floor_ends"] = edges
		stats["moves_ms"] = (Time.get_ticks_usec() - t0) / 1000

	## Rise straight up from (x, y) by dy, then across by dx at the top, with a row to spare
	## over the box (the real arc rises past the landing).
	func _clear_up(x: int, y: int, dx: int, dy: int) -> bool:
		for yy in range(y + 3, y + dy + 4):
			if not open(x, yy) or not open(x + 1, yy):
				return false
		var x0 := mini(x, x + dx)
		var x1 := maxi(x, x + dx) + 1
		for xx in range(x0, x1 + 1):
			for yy in range(y + dy, y + dy + 4):
				if not open(xx, yy):
					return false
		return true

	## A running jump across: the box at the higher of the two rows, plus a row of headroom,
	## open over every column between.
	func _clear_across(x: int, y: int, dx: int, dy: int) -> bool:
		var yb := maxi(y, y + dy)
		var x0 := mini(x, x + dx)
		var x1 := maxi(x, x + dx) + 1
		for xx in range(x0, x1 + 1):
			for yy in range(yb, yb + 4):
				if not open(xx, yy):
					return false
		return true

	# --- 3. join the components ----------------------------------------------------------------

	func connect_all() -> void:
		var t0 := Time.get_ticks_usec()
		var members := {}
		for s in spx.size():
			var r := find(s)
			if not members.has(r):
				members[r] = []
			(members[r] as Array).append(s)
		stats["components"] = members.size()
		# the network: the component under the first settlement flat (the spawn), else the biggest
		var root := -1
		if not c.flats.is_empty():
			var f: Dictionary = c.flats[0]
			var fx := (int(f["x0"]) + int(f["x1"])) / 2
			for dy in range(-3, 40):
				var k := spot(fx, int(f["y"]) + dy)
				if k >= 0:
					root = find(k)
					break
		if root < 0:
			var best := 0
			for r: int in members:
				if (members[r] as Array).size() > best:
					best = (members[r] as Array).size()
					root = r
		var todo: Array = []
		for r: int in members:
			if r == root:
				continue
			var m: Array = members[r]
			if m.size() >= MIN_SPOTS:
				todo.append(r)
		todo.sort()
		stats["to_join"] = todo.size()
		_add_net(members[root])
		var joined := 0
		var kinds := {}
		for radius: int in RADII:
			var progress := true
			while progress and not todo.is_empty():
				progress = false
				var left: Array = []
				for r: int in todo:
					if net[int((members[r] as Array)[0])] != 0:
						continue           # joined on the way by an earlier feature
					var best := _nearest(members[r], radius)
					if best.is_empty():
						left.append(r)
						continue
					var kind := _join(best[0], best[1])
					if log_joins:
						join_log.append([Vector2i(spx[best[0]], spy[best[0]]), Vector2i(spx[best[1]], spy[best[1]]), kind])
					kinds[kind] = int(kinds.get(kind, 0)) + 1
					joined += 1
					_add_net(members[r])
					progress = true
				todo = left
		stats["joined"] = joined
		stats["left"] = todo.size()
		stats["features"] = kinds
		stats["join_ms"] = (Time.get_ticks_usec() - t0) / 1000

	func _add_net(m: Array) -> void:
		for s: int in m:
			net[s] = 1
			var key := (spx[s] >> 4) | ((spy[s] >> 4) << 16)
			if not buckets.has(key):
				buckets[key] = PackedInt32Array()
			var bk: PackedInt32Array = buckets[key]
			if bk.size() < BUCKET_KEEP:      # a few spots per 16 x 16 block is enough to aim at
				bk.append(s)
				buckets[key] = bk

	## [component spot, network spot] at the least join cost within radius, or [].
	func _nearest(m: Array, radius: int) -> Array:
		var best := []
		var best_cost := INF
		var cands: Array = []
		var stride := maxi(1, m.size() / SAMPLES)
		var rb := (radius >> 4) + 1
		# the component's own blocks, sampled, then the network's blocks within reach of any
		var blocks := {}
		for i in range(0, m.size(), stride):
			var si: int = m[i]
			blocks[(spx[si] >> 4) | ((spy[si] >> 4) << 16)] = si
		for bkey: int in blocks:
			var a: int = blocks[bkey]
			var ax := spx[a]
			var ay := spy[a]
			var bx := ax >> 4
			var by := ay >> 4
			for gy in range(by - rb, by + rb + 1):
				for gx in range(bx - rb, bx + rb + 1):
					var key := gx | (gy << 16)
					if gx < 0 or gy < 0 or not buckets.has(key):
						continue
					for b: int in buckets[key]:
						var dx := absi(spx[b] - ax)
						var dy := absi(spy[b] - ay)
						if dx > radius or dy > radius:
							continue
						var cost := dx + 0.6 * dy
						if cost < best_cost and not _forbidden(ax, ay, spx[b], spy[b]):
							best_cost = cost
							cands.append([cost, a, b])
		# cheapest first; the first whose cells touch nothing built
		cands.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
		for k in mini(cands.size(), 12 if radius < 400 else 64):
			var cd: Array = cands[k]
			if not _hits_built(Vector2i(spx[cd[1]], spy[cd[1]]), Vector2i(spx[cd[2]], spy[cd[2]])):
				return [cd[1], cd[2]]
		return best

	func _forbidden(ax: int, ay: int, bx: int, by: int) -> bool:
		var r := Rect2i(mini(ax, bx) - 2, mini(ay, by) - 2, absi(ax - bx) + 5, absi(ay - by) + TALL + 5)
		for z: Rect2i in no_go:
			if z.intersects(r):
				return true
		return false

	## Would the join between these spots (the cells _join would cut or floor) touch something
	## built (paving, a built wall behind: roads, ramps, ruins) or bedrock? Then another pair is
	## tried: a join never breaks a built way.
	func _hits_built(a: Vector2i, b: Vector2i) -> bool:
		var lo := a if a.y <= b.y else b
		var hi := b if a.y <= b.y else a
		var dx := hi.x - lo.x
		var dy := hi.y - lo.y
		if dy > absi(dx) + 2:
			for yy in range(lo.y, hi.y + TALL):
				if _built(lo.x, yy) or _built(lo.x + 1, yy):
					return true
			return _built_run(lo.x, hi.x, hi.y, hi.y)
		return _built_run(lo.x, hi.x, lo.y, hi.y)

	## Columns lo_x..hi_x (and one past) of a way rising one row per column from y0 to y1.
	func _built_run(x0: int, x1: int, y0: int, y1: int) -> bool:
		var dir := 1 if x1 >= x0 else -1
		for k in range(absi(x1 - x0) + 2):
			var xx := x0 + k * dir
			var f := mini(y0 + k, y1) if y1 >= y0 else y0
			for yy in range(f, f + TALL):
				if _built(xx, yy):
					return true
		return false

	## Bedrock, or a paved floor (cobble with open space over it: the deep road, the ramps,
	## a ruin's floor). Ruin walls and pillars may be cut.
	func _built(x: int, y: int) -> bool:
		if x < 0 or y < 0 or x + 1 >= w or y + 1 >= h:
			return true
		var i := x + y * w
		var id := c.fg[i]
		if id == c.BEDROCK:
			return true
		if id != c.COBBLE or c.solid[c.fg[i + w]] != 0:
			return false
		for r: Rect2i in ruins:
			if r.has_point(Vector2i(x, y)):
				return false     # a buried ruin's walls and floor may be broken into
		return true

	## Build the feature joining spot a (a stray component) to spot b (the network).
	func _join(a: int, b: int) -> String:
		var ax := spx[a]
		var ay := spy[a]
		var bx := spx[b]
		var by := spy[b]
		var lo := Vector2i(ax, ay) if ay <= by else Vector2i(bx, by)
		var hi := Vector2i(bx, by) if ay <= by else Vector2i(ax, ay)
		var dx := hi.x - lo.x
		var dy := hi.y - lo.y
		var band := c.band_at(hi.y)
		if dy > absi(dx) + 2:
			# steep: a shaft up from the lower spot, then along at the top
			var xs := lo.x
			var tool := ladder if band == "surface" or band == "sky" or band == "deeps" or band == "nadir" else rope
			_shaft(xs, lo.y, hi.y, tool)
			_level(xs, hi.x, hi.y)
			return "ladder" if tool == ladder else "rope"
		# a slope of one row per column for dy columns, then level
		var dir := 1 if dx >= 0 else -1
		var built := band == "deeps" or band == "nadir"
		var bridged := false
		var n := absi(dx)
		for k in range(n + 2):
			var xx := lo.x + k * dir
			if xx < 1 or xx >= w - 1:
				break
			var floor_y := mini(lo.y + k, hi.y) if k > 0 else lo.y
			if k > n:
				floor_y = hi.y
			var rising := k > 0 and lo.y + k <= hi.y
			bridged = _column(xx, floor_y, rising, built, dir) or bridged
		if dy == 0:
			return "bridge" if bridged else "passage"
		return ("stairs" if built else "steps") + (" + bridge" if bridged else "")

	## Cut rock at (x, y), unless it is bedrock or a paved floor (_built): a join never cuts
	## the floor out of a built way.
	func _cut(x: int, y: int) -> void:
		if c.solid[c.fg[x + y * w]] == 0 or _built(x, y) or keep[x + y * w] != 0:
			return
		c.fg[x + y * w] = c.AIR

	## One column of a carved way: TALL rows open over a floor at floor_y - 1. Rock is cut;
	## open air is crossed by a walkway plank (a bridge), or on the rising part by a stair
	## tread (one-way: it walls nothing off); in the deeps (built) a rising rock floor gets a
	## stair tread too. True if it bridged air.
	func _column(x: int, floor_y: int, rising: bool, built: bool, dir: int) -> bool:
		for yy in range(floor_y, floor_y + TALL):
			if yy > 0 and yy < h - 1:
				_cut(x, yy)
		var fy := floor_y - 1
		if fy < 1:
			return false
		var i := x + fy * w
		keep[i] = 1          # a later join must not cut this floor away
		var air := c.fg[i] == c.AIR
		if rising and built and not air and c.fg[i] != c.BEDROCK and c.fg[i] != c.COBBLE:
			c.fg[i] = stairs_r if dir > 0 else stairs_l     # a built flight over rock (deeps)
			return false
		if rising and air:
			# a flight of stairs over open air: one-way, so it walls nothing off below it
			c.fg[i] = stairs_r if dir > 0 else stairs_l
			return true
		if air:
			c.fg[i] = platform
			return true
		return false

	## A level way at floor row y from x0 to x1 (inclusive).
	func _level(x0: int, x1: int, y: int) -> void:
		var dir := 1 if x1 >= x0 else -1
		for k in range(absi(x1 - x0) + 2):
			var xx := x0 + k * dir
			if xx >= 1 and xx < w - 1:
				_column(xx, y, false, false, dir)

	## A shaft two columns wide (xs, xs + 1) from floor row y0 up to floor row y1, with a ladder
	## or rope in column xs + 1: its top rung is the upper floor; xs gets a plank there.
	func _shaft(xs: int, y0: int, y1: int, tool: int) -> void:
		for yy in range(y0, y1 + TALL):
			for xx: int in [xs, xs + 1]:
				if xx >= 1 and xx < w - 1 and yy > 0 and yy < h - 1:
					_cut(xx, yy)
		# the climb goes in the right-hand column: a body standing in the shaft (its node's left
		# column is xs) has its middle there, where ladders are grabbed
		var lx := xs + 1
		if y0 >= 1:
			keep[xs + (y0 - 1) * w] = 1
			keep[lx + (y0 - 1) * w] = 1
		for yy in range(y0, y1):
			if lx >= 1 and lx < w - 1 and climb[c.fg[lx + yy * w]] == 0:
				c.fg[lx + yy * w] = tool
		if xs >= 1 and c.fg[xs + (y1 - 1) * w] == c.AIR:
			c.fg[xs + (y1 - 1) * w] = platform
		# Where the ground of a hillside meets the shaft's open side (it cut into a slope near
		# the surface), a landing plank over the free column: nobody walking by falls in, and
		# a climber passes it (it is not in the climber's middle column).
		if xs >= 1 and lx + 1 < w:
			for r in range(maxi(y0, c.ground[xs] - 16), y1 - 1):
				var left := c.solid[c.fg[xs - 1 + r * w]] != 0 and c.solid[c.fg[xs - 1 + (r + 1) * w]] == 0
				var right := c.solid[c.fg[lx + 1 + r * w]] != 0 and c.solid[c.fg[lx + 1 + (r + 1) * w]] == 0
				if (left or right) and c.fg[xs + r * w] == c.AIR:
					c.fg[xs + r * w] = platform

	# --- 4. caverns ------------------------------------------------------------------------------

	## Unsettled deep caverns: a walkway a third of the way up and another two thirds up, a
	## staircase from the floor to the first, one crossing it from the first to the second,
	## and a rope down from the second's far end.
	func caverns() -> void:
		var built := 0
		for room: Dictionary in c.buried_rooms:
			var rw := int(room["w"])
			ruins.append(Rect2i(int(room["x"]) - rw / 2 - 2, int(room["y"]) - 2, rw + 4, 14))
		for cav: Dictionary in c.caverns:
			if cav["settled"]:
				continue
			var cx := int(cav["x"])
			var fl := int(cav["floor"])
			var ry := int(cav["ry"])
			var rx := int(cav["rx"])
			var y1 := fl + maxi(8, ry / 3)
			var y2 := fl + maxi(16, ry * 2 / 3)
			var side := 1 if rng.randf() < 0.5 else -1
			# first staircase: from the floor up to walkway 1, starting left of centre
			var sx := cx - side * (y1 - fl) - side * rx / 6
			var x_top := _stair_run(sx, c.drop_to_floor(sx, fl + ry / 3, 80), y1, side)
			if x_top == -99999:
				continue
			var a0 := x_top + side
			var a1 := a0 + side * maxi(12, rx / 2)
			_walkway(a0, a1, y1)
			# second staircase rises back across the first walkway to walkway 2
			var bx := a1 - side * 2
			var x2 := _stair_run(bx, y1 + 1, y2, -side)
			if x2 != -99999:
				var b0 := x2 - side
				var b1 := b0 - side * maxi(10, rx / 3)
				_walkway(b0, b1, y2)
				_hang(b1 - side, y2 - 1)
			built += 1
		stats["cavern_works"] = built

	## Treads from row y_start (standing on the floor or a walkway there) up to row
	## y_end - 1 (level with a walkway whose feet row is y_end), rising in direction dir, only
	## through open air. Returns the last tread column (-99999 if it ran into rock).
	func _stair_run(x: int, y_start: int, y_end: int, dir: int) -> int:
		if y_start < 2:
			return -99999
		var tile := stairs_r if dir > 0 else stairs_l
		var last := -99999
		var y := y_start
		var xx := x
		while y < y_end:
			if xx < 2 or xx >= w - 2:
				break
			var i := xx + y * w
			if c.fg[i] != c.AIR:
				if c.solid[c.fg[i]] != 0:
					break
			else:
				c.fg[i] = tile
			last = xx
			xx += dir
			y += 1
		return last if y >= y_end else -99999

	## Planks along row y - 1 between x0 and x1 through open air (stops at rock).
	func _walkway(x0: int, x1: int, y: int) -> void:
		var dir := 1 if x1 >= x0 else -1
		for k in range(absi(x1 - x0) + 1):
			var xx := x0 + k * dir
			if xx < 2 or xx >= w - 2:
				return
			var i := xx + (y - 1) * w
			if c.fg[i] == c.AIR:
				c.fg[i] = platform
			elif c.solid[c.fg[i]] != 0:
				return

	## An old rope hanging from under a walkway end down to the floor.
	func _hang(x: int, y: int) -> void:
		if x < 2 or x >= w - 2 or y < 2:
			return
		var yy := y - 1
		while yy > 1 and c.fg[x + yy * w] == c.AIR:
			c.fg[x + yy * w] = rope
			yy -= 1
