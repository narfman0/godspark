## Stage "passages": guarantees a world a Medium walker crosses both ways without digging,
## and that every site and both ends of every route are reachable on foot from the spawn.
## Runs last of the terrain stages (after "places" and "roads", before "dressing"), so it
## sees every cave, cavern, ramp, ruin, settlement and road as they will be.
##
## 0. Ramps (the ascent's, the portal's) are floored with treads where they cross a cave
##    (outside building lots).
## 1. Standing spots: a Medium body is a 2 x 3 box of cells; a spot (x, y) is that box with
##    its left column x and feet row y, free of solid tiles, with a solid or one-way tile
##    under one of its columns.
## 2. Two-way moves join spots (union-find): walking to the next column with a step of at
##    most one row (headroom checked); from the ends of floors, jumps up to JUMP_UP rows and
##    across gaps of up to JUMP_ACROSS columns (ACROSS_ROOM rows over the box), landing with
##    floor on the side the body comes from; a ladder or rope joins every spot whose box has
##    it in its middle column. These moves are a subset of what the monsters' nav graph
##    (jumps recorded from the real controller) can do (tools/passability_sweep.gd checks).
## 3. The spawn's component is the network. Every other component of at least MIN_SPOTS
##    spots is joined to it with the cheapest believable feature to the nearest network spot:
##    a carved passage with steps (stairs in the deeps), a walkway bridge over open air, and
##    for steep joins a shaft with a ladder (surface, deeps) or a hanging rope (caves). Joined
##    parts become network; so do the pockets a feature runs through, and the feature itself
##    (a pocket beside a shaft gets a short way into it, not a shaft of its own). A cut
##    through the floor of another way leaves a plank, so it is not cut in two.
## 4. Unsettled deep caverns get crisscrossing walkways and staircases at two heights.
## 5. A second look at the world as it now is: every site and route end is checked and
##    joined if apart (then looked at again, up to REACH_ROUNDS times), and whatever a later
##    join cut apart is joined again.
## 6. Deep routes still flagged rough are walked again, or graded (_grade), and lose the flag.
## Settlement places, roads, settled caverns, paved floors and the floor under every site are
## never cut. Deterministic (the stage RNG only picks feature variants).
extends RefCounted

const GenContext := preload("gen_context.gd")
const Barriers := preload("stage_barriers.gd")

const JUMP_UP := 4
const JUMP_ACROSS := 4
## Rows clear over the box for a running jump across a gap (the arc rises that much).
const ACROSS_ROOM := 2
const MIN_SPOTS := 4
## In the deeps and the nadir only regions this big are joined (their pockets are sparse and
## a long straight tunnel to each would not look like a cave); small pockets anywhere are
## joined only within SMALL_REACH tiles.
const BIG_SPOTS := 24
const SMALL_REACH := 48
## Search radius (tiles) for the nearest network spot, by pass.
const RADII := [24, 48, 96, 200, 400]
## Tunnel clear height (rows above the floor): a step up needs the box's 3 rows plus one
## over the column it leaves.
const TALL := 5
## Network spots kept per 16 x 16 block, and component spots sampled, when aiming a join.
const BUCKET_KEEP := 6
## Pairs a must-reach join looks through when the cheap ones all run into something built.
const MUST_TRIES := 400
const SAMPLES := 64
## A component waiting for a join near it: the blocks its box is filed under (1 << WAIT_SHIFT
## tiles), and how much past the search radius a join still wakes it.
const WAIT_SHIFT := 7
const WAIT_MARGIN := 32
## Where a site's or route end's standing node is looked for, around the node of its cell.
const NEAR := [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(1, 1),
	Vector2i(0, -1), Vector2i(-2, 0), Vector2i(2, 0)]
## Tile ids from here up are the Places track's (roads, bridges, buildings).
const PLACE_TILES := 96

static var stats := {}

static func run(c: GenContext, rng: RandomNumberGenerator) -> void:
	reach_stats = {}
	if not bool(c.opts.get("passages", true)):
		stats = {"skipped": true}
		return            # opts {"passages": false}: the world as it was before this stage (tools)
	var t0 := Time.get_ticks_usec()
	# the places stage cleared building lots (the ramps' floors in them too): ramps are
	# floored outside the lots
	var lots := _lots(c)
	var holes := _ramp_holes(c, c.ascent, lots) + _ramp_holes(c, c.portal, lots)
	var tg := targets(c)
	var tm := {}
	var tt := Time.get_ticks_usec()
	var p := Passer.new(c, rng)
	p.build_spots()
	p.protect(tg)
	p.join_moves()
	var spawn := p._spot_near(tg[0][1]) if not tg.is_empty() else -1
	p.connect_all(spawn)
	var rounds: Array = [p.connect_targets(tg)] if not tg.is_empty() else []
	tm["first"] = (Time.get_ticks_usec() - tt) / 1000
	tt = Time.get_ticks_usec()
	p.caverns()
	stats = p.stats
	stats["ramp_holes"] = holes
	# A second look at the world as it now is: a later join may have cut into an earlier one,
	# and the cavern works add ways; whatever is still apart is joined again, and every site
	# and route end is checked (and joined) again, until a look joins nothing for them.
	var p2 := Passer.new(c, rng)
	p2.build_spots()
	p2.protect(tg)
	p2.join_moves()
	if not tg.is_empty():
		rounds.append(p2.connect_targets(tg))      # checked on the world as it is, first
	p2.connect_all(p2._spot_near(tg[0][1]) if not tg.is_empty() else -1)
	stats["second"] = {"joined": p2.stats["joined"], "left": p2.stats["left"], "features": p2.stats["features"],
		"ms": int(p2.stats["spots_ms"]) + int(p2.stats["moves_ms"]) + int(p2.stats["join_ms"])}
	tm["second"] = (Time.get_ticks_usec() - tt) / 1000
	tt = Time.get_ticks_usec()
	if not tg.is_empty():
		while int(rounds[-1]["joined"]) > 0 and rounds.size() < REACH_ROUNDS + 1:
			var p3 := Passer.new(c, rng)
			p3.build_spots()
			p3.protect(tg)
			p3.join_moves()
			rounds.append(p3.connect_targets(tg))
	reach_stats["rounds"] = rounds
	reach_stats["missing"] = rounds[-1]["missing"] if not rounds.is_empty() else []
	tm["checks"] = (Time.get_ticks_usec() - tt) / 1000
	tt = Time.get_ticks_usec()
	reach_stats["clean"] = _clean_routes(c, lots)
	tm["routes"] = (Time.get_ticks_usec() - tt) / 1000
	stats["phases_ms"] = tm
	c.survey()           # joins near the surface cut into hillsides
	if p.log_joins:
		stats["log"] = p.join_log
	stats["ms"] = (Time.get_ticks_usec() - t0) / 1000

static func _lots(c: GenContext) -> Array:
	var lots: Array = []
	for key: String in c.places:
		var pl: Dictionary = c.places[key]
		for i in (pl.get("lots", []) as Array).size():
			lots.append(PlaceBuilder.lot_rect(pl, i))
	return lots

## A ramp (the ascent, the portal's) is paved only over rock: where it crosses a cave its
## floor is open air. Those cells get a stair tread rising the ramp's way (a landing gets a
## walkway plank): one-way, so the cave under it is not walled off. Not out in the open
## above the ground at the ramp's mouth. Returns the cells floored.
static func _ramp_holes(c: GenContext, ramp: Dictionary, avoid: Array = []) -> int:
	var path: Array = ramp.get("path", [])
	if path.size() < 2:
		return 0
	var dx := signi((path[1] as Vector2i).x - (path[0] as Vector2i).x)
	var dy := signi((path[-1] as Vector2i).y - (path[0] as Vector2i).y)
	var tread := TileDefs.id("stairs_r") if dx * dy > 0 else TileDefs.id("stairs_l")
	var plank := TileDefs.id("platform")
	var n := 0
	for k in path.size():
		var q: Vector2i = path[k]
		if q.y - 1 < 1 or q.y - 1 > c.ground[q.x]:
			continue
		var i := q.x + (q.y - 1) * c.w
		if c.fg[i] != c.AIR:
			continue
		var inside := false
		for r: Rect2i in avoid:
			if r.has_point(Vector2i(q.x, q.y - 1)):
				inside = true
				break
		if inside:
			continue
		var level := (k == 0 or (path[k - 1] as Vector2i).y == q.y) and (k + 1 >= path.size() or (path[k + 1] as Vector2i).y == q.y)
		c.fg[i] = plank if level else tread
		n += 1
	return n

## What every site and route end needs: up to this many looks after joining for them.
const REACH_ROUNDS := 3

static var reach_stats := {}

## What must be reachable: [label, feet cell] for every site and both ends of every route's
## path. The first surface settlement (the spawn) comes first.
static func targets(c: GenContext) -> Array:
	var out: Array = []
	var spawn := -1
	for s: Dictionary in c.sites:
		if s["kind"] == "settlement" and String(s["band"]) in ["surface", "sky"]:
			spawn = int(s["id"])
			out.append(["spawn %d" % spawn, Vector2i(int(s["x"]), int(s["y"]))])
			break
	for s: Dictionary in c.sites:
		if int(s["id"]) != spawn:
			out.append(["%s %d" % [s["kind"], s["id"]], Vector2i(int(s["x"]), int(s["y"]))])
	for r: Dictionary in c.routes:
		var path: Array = r.get("path", [])
		if path.size() >= 2:
			out.append(["route %d a" % r["id"], Vector2i(int(path[0][0]), int(path[0][1]))])
			out.append(["route %d b" % r["id"], Vector2i(int(path[-1][0]), int(path[-1][1]))])
	return out

## Deep routes flagged rough: walk them again one tile up or down per column; a clean walk
## replaces the path and drops the flag. Where there is none, the route is graded: the
## cheapest walk near its current path where a step that is not walkable costs the rock cut
## for the body and the treads laid under it, which are then built. Returns how many became
## clean.
static func _clean_routes(c: GenContext, avoid: Array = []) -> int:
	var Roads: Script = load("res://core/world/worldgen/stage_roads.gd")
	var n := 0
	for r: Dictionary in c.routes:
		if not r.get("rough", false):
			continue
		var path: Array = r.get("path", [])
		if path.size() < 2:
			continue
		var a := Vector2i(int(path[0][0]), int(path[0][1]))
		var b := Vector2i(int(path[-1][0]), int(path[-1][1]))
		var res: Array = Roads.call("walk", c, a, b, 1, 1)
		if res.is_empty():
			# where the jumping and falling walk steps more than a row, a short flight of
			# treads down from the higher cell makes it a walk, then try again
			var rough: Array = Roads.call("walk", c, a, b, 24, 6)
			var built := 0
			for i in range(1, rough.size()):
				var p0: Vector2i = rough[i - 1]
				var p1: Vector2i = rough[i]
				if absi(p1.y - p0.y) > 1 and absi(p1.x - p0.x) == 1:
					built += _flight(c, p0 if p0.y > p1.y else p1, p1 if p0.y > p1.y else p0)
			if built > 0:
				res = Roads.call("walk", c, a, b, 1, 1)
		if res.is_empty():
			var sa: Vector2i = Roads.call("_settle", c, a)
			var sb: Vector2i = Roads.call("_settle", c, b)
			res = _grade(c, _corridor(c, r, sa, sb) + path, sa, sb, avoid)
		if res.is_empty():
			continue
		var out: Array = []
		for q: Vector2i in res:
			out.append([q.x, q.y])
		r["path"] = out
		r.erase("rough")
		n += 1
	return n

## The line a deep route should follow, as feet cells [[x, y]]: from end a along the deep
## road to the ramp it takes (the ascent's or the portal's), up or down the ramp, and on to
## end b; straight lines between the pieces.
static func _corridor(c: GenContext, r: Dictionary, a: Vector2i, b: Vector2i) -> Array:
	var by_id := {}
	for s: Dictionary in c.sites:
		by_id[int(s["id"])] = s
	var sa: Dictionary = by_id.get(int(r["a"]), {})
	var sb: Dictionary = by_id.get(int(r["b"]), {})
	var ramp: Array = []
	if String(sa.get("kind", "")) == "portal" or String(sb.get("kind", "")) == "portal":
		ramp = c.portal.get("path", [])
	elif String(sa.get("band", "")) in ["surface", "sky"] or String(sb.get("band", "")) in ["surface", "sky"]:
		ramp = c.ascent.get("path", [])
	var pts: Array = [a]
	if not ramp.is_empty():
		var r0: Vector2i = ramp[0]
		var r1: Vector2i = ramp[-1]
		var fwd := absi(r0.x - a.x) + absi(r0.y - a.y) <= absi(r1.x - a.x) + absi(r1.y - a.y)
		var start: Vector2i = r0 if fwd else r1
		# along the deep road to the ramp's start, where the road runs
		var step := signi(start.x - a.x)
		var x := a.x
		while step != 0 and x != start.x:
			x += step
			if c.road_x0 >= 0 and x >= c.road_x0 and x <= c.road_x1 and absi(c.road_floor[x - c.road_x0] - a.y) < 40:
				pts.append(Vector2i(x, c.road_floor[x - c.road_x0]))
		var seq: Array = ramp if fwd else ramp.duplicate()
		if not fwd:
			seq.reverse()
		pts.append_array(seq)
	pts.append(b)
	var out: Array = []
	for i in pts.size():
		var p: Vector2i = pts[i]
		if i > 0:
			var q: Vector2i = pts[i - 1]
			var n := maxi(absi(p.x - q.x), absi(p.y - q.y))
			for k in range(1, n):
				out.append([q.x + (p.x - q.x) * k / n, q.y + (p.y - q.y) * k / n])
		out.append([p.x, p.y])
	return out

const GRADE_R := 5          # corridor half-width around a route's line
const GRADE_CUT := 3        # cost of a rock cell cut for the body
const GRADE_TREAD := 2      # cost of a tread or plank laid over air

## The cheapest one-row-per-column walk from a to b (feet cells) within GRADE_R of `near`
## (the route's old path, [[x, y]]), built: rock in the body's way is cut and air under the
## feet floored (a tread where it rises, a plank where level). Never through bedrock, paved
## floors, the Places track's tiles or the rects in `avoid`. [] when there is none.
static func _grade(c: GenContext, near: Array, a: Vector2i, b: Vector2i, avoid: Array) -> Array:
	if a.x < 0 or b.x < 0 or near.is_empty():
		return []
	var lo := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
	var hi := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
	for q: Array in near:
		lo = Vector2i(mini(lo.x, int(q[0])), mini(lo.y, int(q[1])))
		hi = Vector2i(maxi(hi.x, int(q[0])), maxi(hi.y, int(q[1])))
	lo -= Vector2i(GRADE_R, GRADE_R)
	hi += Vector2i(GRADE_R, GRADE_R)
	lo = Vector2i(maxi(lo.x, 1), maxi(lo.y, 2))
	hi = Vector2i(mini(hi.x, c.w - 2), mini(hi.y, c.h - 6))
	var bw := hi.x - lo.x + 1
	var bh := hi.y - lo.y + 1
	var mask := PackedByteArray()
	mask.resize(bw * bh)
	# the corridor: cells within GRADE_R of the old path
	for q: Array in near:
		var qx := int(q[0]) - lo.x
		var qy := int(q[1]) - lo.y
		for dy in range(-GRADE_R, GRADE_R + 1):
			var yy := qy + dy
			if yy < 0 or yy >= bh:
				continue
			var row := yy * bw
			for xx in range(maxi(0, qx - GRADE_R), mini(bw - 1, qx + GRADE_R) + 1):
				mask[xx + row] = 1
	# inside a building lot the walk may pass (the street runs through) but builds nothing
	for r: Rect2i in avoid:
		for yy in range(maxi(r.position.y, lo.y), mini(r.end.y, hi.y + 1)):
			for xx in range(maxi(r.position.x, lo.x), mini(r.end.x, hi.x + 1)):
				var mi := (xx - lo.x) + (yy - lo.y) * bw
				if mask[mi] != 0:
					mask[mi] = 2
	for p: Vector2i in [a, b]:
		mask[(p.x - lo.x) + (p.y - lo.y) * bw] = 1
	var cost := PackedInt32Array()
	cost.resize(bw * bh)
	cost.fill(1 << 30)
	var prev := PackedInt32Array()
	prev.resize(bw * bh)
	prev.fill(-1)
	var si := (a.x - lo.x) + (a.y - lo.y) * bw
	var gi := (b.x - lo.x) + (b.y - lo.y) * bw
	cost[si] = 0
	var hk := PackedInt32Array([si])
	var hf := PackedInt32Array([0])
	while not hk.is_empty():
		var k := hk[0]
		var f := hf[0]
		_hpop(hk, hf)
		if f > cost[k]:
			continue
		if k == gi:
			break
		var px := lo.x + k % bw
		var py := lo.y + k / bw
		for dx: int in [-1, 1]:
			for dy: int in [-1, 0, 1]:
				var nx := px + dx
				var ny := py + dy
				if nx < lo.x or nx > hi.x or ny < lo.y or ny > hi.y:
					continue
				var nk := (nx - lo.x) + (ny - lo.y) * bw
				if mask[nk] == 0:
					continue
				var step := _grade_cost(c, px, py, nx, ny)
				if step < 0 or (step > 0 and mask[nk] == 2):
					continue
				var nc := cost[k] + 1 + step
				if nc < cost[nk]:
					cost[nk] = nc
					prev[nk] = k
					_hpush(hk, hf, nk, nc)
	if gi != si and prev[gi] < 0:
		var near_b := a
		var bd := 1 << 30
		for k2 in cost.size():
			if cost[k2] < (1 << 30):
				var q := Vector2i(lo.x + k2 % bw, lo.y + k2 / bw)
				var d := absi(q.x - b.x) + absi(q.y - b.y)
				if d < bd:
					bd = d
					near_b = q
		reach_stats["grade_fail"] = reach_stats.get("grade_fail", []) + [[a, b, near_b]]
		return []
	var cells: Array = []
	var k := gi
	while k >= 0:
		cells.append(Vector2i(lo.x + k % bw, lo.y + k / bw))
		k = prev[k]
	cells.reverse()
	# build it
	var tr := TileDefs.id("stairs_r")
	var tl := TileDefs.id("stairs_l")
	var plank := TileDefs.id("platform")
	for i in cells.size():
		var q: Vector2i = cells[i]
		var top := q.y + 3
		if i + 1 < cells.size() and (cells[i + 1] as Vector2i).y > q.y:
			top = q.y + 4                  # a step up needs a row over the column it leaves
		for yy in range(q.y, top):
			if c.solid[c.fg[q.x + yy * c.w]] != 0:
				c.fg[q.x + yy * c.w] = c.AIR
		var fi := q.x + (q.y - 1) * c.w
		if c.fg[fi] == c.AIR:
			var rise := 0
			if i > 0:
				rise = signi(q.y - (cells[i - 1] as Vector2i).y) * signi(q.x - (cells[i - 1] as Vector2i).x)
			if rise == 0 and i + 1 < cells.size():
				rise = signi((cells[i + 1] as Vector2i).y - q.y) * signi((cells[i + 1] as Vector2i).x - q.x)
			c.fg[fi] = plank if rise == 0 else (tr if rise > 0 else tl)
	return cells

## Extra cost of stepping from feet cell (px, py) to (nx, ny) one column over: 0 when it is a
## walk already, the cuts and floor it needs otherwise, -1 when it would touch something built.
static func _grade_cost(c: GenContext, px: int, py: int, nx: int, ny: int) -> int:
	var extra := 0
	var w := c.w
	for yy in range(ny, ny + 3):
		var e := _cut_cost(c, nx + yy * w)
		if e < 0:
			return -1
		extra += e
	if ny > py:
		var e := _cut_cost(c, px + (py + 3) * w)
		if e < 0:
			return -1
		extra += e
	var under := c.fg[nx + (ny - 1) * w]
	if c.solid[under] == 0 and TileDefs.platform[under] == 0 and TileDefs.ladder[under] == 0:
		if under != c.AIR:
			return -1
		extra += GRADE_TREAD
	return extra

static func _cut_cost(c: GenContext, i: int) -> int:
	var id := c.fg[i]
	if id >= PLACE_TILES:
		return -1
	if c.solid[id] == 0:
		return 0
	if id == c.BEDROCK or (id == c.COBBLE and c.solid[c.fg[i + c.w]] == 0):
		return -1                          # bedrock, or a paved floor
	return GRADE_CUT

static func _hpush(hk: PackedInt32Array, hf: PackedInt32Array, k: int, f: int) -> void:
	hk.append(k)
	hf.append(f)
	var i := hk.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if hf[p] <= f:
			break
		hk[i] = hk[p]
		hf[i] = hf[p]
		i = p
	hk[i] = k
	hf[i] = f

static func _hpop(hk: PackedInt32Array, hf: PackedInt32Array) -> void:
	var n := hk.size() - 1
	var lk := hk[n]
	var lf := hf[n]
	hk.resize(n)
	hf.resize(n)
	if n == 0:
		return
	var i := 0
	while true:
		var ch := 2 * i + 1
		if ch >= n:
			break
		if ch + 1 < n and hf[ch + 1] < hf[ch]:
			ch += 1
		if hf[ch] >= lf:
			break
		hk[i] = hk[ch]
		hf[i] = hf[ch]
		i = ch
	hk[i] = lk
	hf[i] = lf

## Treads stepping down one row per column from feet cell hi toward the next column's lower
## feet cell lo, through open air (rock in the way of the body is cut, never anything
## built or a place's tiles), until they meet the floor. Returns the treads laid.
static func _flight(c: GenContext, hi: Vector2i, lo: Vector2i) -> int:
	var dir := signi(lo.x - hi.x)
	var tread := TileDefs.id("stairs_l") if dir > 0 else TileDefs.id("stairs_r")   # rising back toward hi
	var n := 0
	for k in range(1, hi.y - lo.y):
		var x := hi.x + k * dir
		var fy := hi.y - k - 1             # the floor under feet row hi.y - k
		if x < 1 or x >= c.w - 1 or fy < 1:
			break
		var i := x + fy * c.w
		if c.solid[c.fg[i]] != 0 or TileDefs.platform[c.fg[i]] != 0:
			break                          # the ground (or a floor) is here: the walk steps onto it
		for yy in range(fy + 1, fy + 4):
			var j := x + yy * c.w
			if c.solid[c.fg[j]] != 0:
				if c.fg[j] == c.BEDROCK or c.fg[j] == c.COBBLE or c.fg[j] >= PLACE_TILES:
					return n
				c.fg[j] = c.AIR
		if c.fg[i] == c.AIR:
			c.fg[i] = tread
			n += 1
	return n

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
	var waiting := {}                    # WAIT_CELL block key -> PackedInt32Array of pending components
	var wait_box := {}                   # pending component -> PackedInt32Array [lo x, lo y, hi x, hi y]
	var touched: Array = []              # Rect2i cells the feature being built touched
	var aims: Array = []                 # Vector2i places on it later joins may aim at
	var log_edges := false
	var edge_log := PackedInt32Array()
	var join_log: Array = []
	var jump_up := JUMP_UP
	var jump_across := JUMP_ACROSS                # Rect2i areas never carved or built in
	## Places and roads exist (the stage runs after them): their tiles are never cut.
	var final := true

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
		for key: String in c.places:
			var pl: Dictionary = c.places[key]
			var st: Array = pl.get("street", [])
			if st.size() >= 3:       # the place: its street and the buildings over it
				no_go.append(Rect2i(int(st[0]) - 3, int(st[2]) - 3, int(st[1]) - int(st[0]) + 7, 30))

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

	## A spot needs three open rows in two columns over a floor, so only rows just above a floor
	## are tried. The grid is turned on its side (each column contiguous, rows ascending) with
	## everything open made 0, and native searches jump over the rock between open runs: this
	## runs once per look, and walking 18 million cells of a medium world took a look 1.7 s.
	func build_spots() -> void:
		var t0 := Time.get_ticks_usec()
		var fg := c.fg
		var solid := c.solid
		sid.resize(w * h)
		sid.fill(-1)
		keep.resize(w * h)
		var tall := top + 4
		var img := Image.create_from_data(w, h, false, Image.FORMAT_R8, fg).get_region(Rect2i(0, 0, w, tall))
		img.rotate_90(COUNTERCLOCKWISE)      # (x, y) goes to y + (w - 1 - x) * tall
		var col := img.get_data()
		var cand: Array = []                 # per column: rows that stand on something
		cand.resize(w)
		var mark := PackedInt32Array()       # the same for walkways and ladders: cell in col
		for id in solid.size():
			if solid[id] != 0 or id == c.AIR:
				continue
			var i := col.find(id)
			while i >= 0:
				col[i] = 0
				if oneway[id] != 0 or climb[id] != 0:
					mark.append(i)
				i = col.find(id, i + 1)
		mark.sort()
		var im := mark.size() - 1            # high offsets are low columns: walked from the end
		for x in w:
			var mine := PackedInt32Array()
			var base := (w - 1 - x) * tall
			var end := base + tall
			while im >= 0 and mark[im] >= base:
				mine.append(mark[im] - base + 1)
				im -= 1
			var marks := mine.size()
			var i := col.find(0, base)
			while i >= 0 and i < end:
				mine.append(i - base)        # the first open row over rock
				i += 1
				while i + 64 <= end and col.slice(i, i + 64).count(0) == 64:
					i += 64
				while i < end and col[i] == 0:
					i += 1
				i = col.find(0, i)
			if marks > 0:
				mine.sort()
			cand[x] = mine
		for x in w - 1:
			var ca: PackedInt32Array = cand[x]
			var cb: PackedInt32Array = cand[x + 1]
			var na := ca.size()
			var nb := cb.size()
			var ia := 0
			var ib := 0
			var oa := (w - 1 - x) * tall
			var ob := oa - tall
			var last := -1
			while ia < na or ib < nb:
				var y: int
				if ib >= nb or (ia < na and ca[ia] <= cb[ib]):
					y = ca[ia]
					ia += 1
				else:
					y = cb[ib]
					ib += 1
				if y == last or y < 1 or y >= top:
					continue
				last = y
				if col[oa + y] != 0 or col[oa + y + 1] != 0 or col[oa + y + 2] != 0 \
						or col[ob + y] != 0 or col[ob + y + 1] != 0 or col[ob + y + 2] != 0:
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

	## Join two spots by a move (kind: 1 walk, 2 jump up, 3 jump across, 4 ladder or rope);
	## with log_edges the move is kept (tools compare them with the nav graph).
	func _link(a: int, b: int, kind: int) -> void:
		if log_edges:
			edge_log.append_array(PackedInt32Array([a, b, kind]))
		union(a, b)

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
		var lifted := log_edges
		for s in spx.size():
			var x := spx[s]
			var y := spy[s]
			var i := x + y * w
			var walk_r := false
			var walk_l := sid[i - 1] >= 0 or (sid[i - 1 + w] >= 0 and open(x + 1, y + 3) and _lifts(x, y, -1)) \
				or (sid[i - 1 - w] >= 0 and open(x - 1, y + 2) and open(x, y + 2) and _lifts(x - 1, y - 1, 1))
			var t := sid[i + 1]
			if t >= 0:
				if lifted:
					_link(s, t, 1)
				else:
					union(s, t)
				walk_r = true
			t = sid[i + 1 + w]
			if t >= 0 and open(x, y + 3) and _lifts(x, y, 1):
				_link(s, t, 1)
				walk_r = true
			t = sid[i + 1 - w]
			if t >= 0 and open(x + 2, y + 2) and open(x + 1, y + 2) and _lifts(x + 1, y - 1, -1):
				_link(s, t, 1)
				walk_r = true
			if walk_r and walk_l:
				continue
			edges += 1
			# the end of a floor: jumps up (and so falls back down) and across gaps
			# (rows open straight over the box first: a jump higher than that cannot rise)
			var rise := 0
			while rise < jump_up + 1 and open(x, y + 3 + rise) and open(x + 1, y + 3 + rise):
				rise += 1
			for dy in range(2, mini(jump_up, rise - 1) + 1):
				for dx in range(-3, 4):
					t = spot(x + dx, y + dy)
					if t >= 0 and (dx == 0 or _footing(t, dx)) and _clear_up(x, y, dx, dy):
						_link(s, t, 2)
			# across: the columns between must be open; a blocked column ends the farther jumps
			for dir: int in [1, -1]:
				for dy in range(-1, 2):
					var yb := maxi(y, y + dy)
					if not _col_open(x, yb) or not _col_open(x + 1, yb):
						continue
					for dx in range(1, jump_across + 2):
						if not _col_open(x + 1 + dx if dir > 0 else x - dx, yb):
							break
						if dx >= 2:
							t = spot(x + dx * dir, y + dy)
							if t >= 0 and _footing(t, dx * dir) and _footing(s, -dx * dir):
								_link(s, t, 3)       # a link is two-way: footing at both ends
		# ladders and ropes: every spot along a climbable run (the climbable cells are found
		# with a native search, not a walk over every cell)
		var fg := c.fg
		var cells := PackedInt32Array()
		for id in climb.size():
			if climb[id] == 0:
				continue
			var i := fg.find(id)
			while i >= 0:
				cells.append(i)
				i = fg.find(id, i + 1)
		cells.sort()
		var done := {}
		for i0: int in cells:
			if done.has(i0):
				continue
			var x := i0 % w
			var y := i0 / w
			if y < 1 or y >= top or climb[fg[x + (y - 1) * w]] != 0:
				continue                   # not the bottom of a run (its bottom starts it)
			var y1 := y
			while y1 < top and climb[fg[x + y1 * w]] != 0:
				done[x + y1 * w] = true
				y1 += 1
			var first := -1
			for yy in range(y, y1 + 1):
				var k := spot(x - 1, yy)       # the box whose middle column holds the ladder
				if k >= 0:
					if first < 0:
						first = k
					else:
						_link(first, k, 4)
		stats["floor_ends"] = edges
		stats["moves_ms"] = (Time.get_ticks_usec() - t0) / 1000

	## Does a body walking from the spot at (x, y) in direction dir (+1, -1) rise a row? Only
	## for something solid in its way at the feet's row, or a stair tread in the column its
	## leading edge enters. A walkway or a ladder top one row up is one-way: the body walks in
	## under it and is not lifted, so that step goes down only, and a link would join two
	## ways nobody can walk both ways (a ruin on medium seed 2 hung off one such step).
	func _lifts(x: int, y: int, dir: int) -> bool:
		var nl := x + dir
		if c.solid[c.fg[nl + y * w]] != 0 or c.solid[c.fg[nl + 1 + y * w]] != 0:
			return true
		return TileDefs.stairs[c.fg[(nl + 1 if dir > 0 else nl) + y * w]] != 0

	## A landing a jump makes reliably, coming from direction dir: floor under the column on
	## the side it comes from (a body landing on a corner whose floor is on the far side slides
	## off it; the monsters' planner asks for half a tile of the landing box over floor).
	func _footing(t: int, dir: int) -> bool:
		var i := spx[t] + (spy[t] - 1) * w + (0 if dir > 0 else 1)
		return c.solid[c.fg[i]] != 0 or oneway[c.fg[i]] != 0

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

	## The rows a running jump across sweeps (the box and ACROSS_ROOM over it) open in column xx.
	func _col_open(xx: int, yb: int) -> bool:
		if xx < 0 or xx >= w or yb < 0 or yb + 3 + ACROSS_ROOM > h:
			return false
		var fg := c.fg
		var solid := c.solid
		for yy in range(yb, yb + 3 + ACROSS_ROOM):
			if solid[fg[xx + yy * w]] != 0:
				return false
		return true

	## A running jump across: the box at the higher of the two rows, plus a row of headroom,
	## open over every column between.
	func _clear_across(x: int, y: int, dx: int, dy: int) -> bool:
		var yb := maxi(y, y + dy)
		var x0 := mini(x, x + dx)
		var x1 := maxi(x, x + dx) + 1
		for xx in range(x0, x1 + 1):
			for yy in range(yb, yb + 3 + ACROSS_ROOM):
				if not open(xx, yy):
					return false
		return true

	# --- 3. join the components ----------------------------------------------------------------

	func connect_all(spawn := -1) -> void:
		var t0 := Time.get_ticks_usec()
		var members := {}
		for s in spx.size():
			var r := find(s)
			if not members.has(r):
				members[r] = []
			(members[r] as Array).append(s)
		stats["components"] = members.size()
		# the network: the spawn's component (given, else the one under the first settlement
		# flat), else the biggest
		var root := find(spawn) if spawn >= 0 else -1
		if root < 0 and not c.flats.is_empty():
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
			if _on_a_peak(int(m[0])):
				continue               # a range's walls stay unclimbed: the pass is the way
			if m.size() >= MIN_SPOTS and (m.size() >= BIG_SPOTS or c.band_at(spy[int(m[0])]) in ["caves", "surface", "sky"]):
				todo.append(r)
		todo.sort()
		stats["to_join"] = todo.size()
		_add_net(members[root])
		var joined := 0
		var absorbed := 0
		var kinds := {}
		var prof := {}
		var tried := {}
		var woken := {}
		waiting.clear()
		wait_box.clear()
		for radius: int in RADII:
			var progress := true
			while progress and not todo.is_empty():
				progress = false
				var left: Array = []
				for r: int in todo:
					if net[int((members[r] as Array)[0])] != 0:
						continue           # joined on the way by an earlier feature
					if radius > SMALL_REACH and (members[r] as Array).size() < BIG_SPOTS:
						left.append(r)     # a small pocket far from everything stays a pocket
						continue
					var tp := Time.get_ticks_usec()
					var skip: bool = tried.get(r, -1) == radius and not woken.has(r)
					prof["near_scan"] = int(prof.get("near_scan", 0)) + Time.get_ticks_usec() - tp
					if skip:
						left.append(r)     # tried at this reach, and nothing was joined near it since
						continue
					tp = Time.get_ticks_usec()
					var best := _nearest(members[r], radius)
					prof["nearest"] = int(prof.get("nearest", 0)) + Time.get_ticks_usec() - tp
					prof["nearest_n"] = int(prof.get("nearest_n", 0)) + 1
					if best.is_empty():
						tried[r] = radius
						woken.erase(r)
						_wait(r, members[r])
						left.append(r)
						continue
					tp = Time.get_ticks_usec()
					var kind := _join(best[0], best[1])
					prof["join"] = int(prof.get("join", 0)) + Time.get_ticks_usec() - tp
					var sz := (members[r] as Array).size()
					var hb := "<8" if sz < 8 else ("<16" if sz < 16 else ("<32" if sz < 32 else ("<64" if sz < 64 else "64+")))
					var hist: Dictionary = stats.get("sizes", {})
					hist[hb] = int(hist.get(hb, 0)) + 1
					stats["sizes"] = hist
					var ex: Dictionary = stats.get("examples", {})
					var at := [spx[best[0]], spy[best[0]], spx[best[1]], spy[best[1]]]
					if not ex.has(kind) or (kind == "ladder" and spy[best[1]] > c.ground[spx[best[1]]] - 30):
						ex[kind] = at          # one of each (a ladder: the one nearest the surface)
					stats["examples"] = ex
					if log_joins:
						join_log.append([Vector2i(spx[best[0]], spy[best[0]]), Vector2i(spx[best[1]], spy[best[1]]), kind])
					kinds[kind] = int(kinds.get(kind, 0)) + 1
					joined += 1
					_wake(Vector2i(spx[best[1]], spy[best[1]]), radius, tried, woken)
					_wake(Vector2i(spx[best[0]], spy[best[0]]), radius, tried, woken)
					tp = Time.get_ticks_usec()
					_add_net(members[r])
					absorbed += _absorb(members)
					prof["absorb"] = int(prof.get("absorb", 0)) + Time.get_ticks_usec() - tp
					progress = true
				todo = left
				prof["passes"] = int(prof.get("passes", 0)) + 1
		stats["prof_us"] = prof
		stats["absorbed"] = absorbed
		stats["joined"] = joined
		stats["left"] = todo.size()
		stats["features"] = kinds
		stats["join_ms"] = (Time.get_ticks_usec() - t0) / 1000

	## Stage "reach": join every target's component to the spawn's (targets[0]). Returns
	## {targets, apart (before joining), joined, missing: [labels still apart or with no spot]}.
	func connect_targets(tg: Array) -> Dictionary:
		var t0 := Time.get_ticks_usec()
		var tspot: Array = []
		var missing: Array = []
		for t: Array in tg:
			var k := _spot_near(t[1])
			tspot.append(k)
			if k < 0:
				missing.append("%s: no standing room at %s" % [t[0], t[1]])
		var out := {"targets": tg.size(), "apart": 0, "joined": 0, "missing": missing, "kinds": {}}
		if tspot.is_empty() or int(tspot[0]) < 0:
			out["missing"].append("no spawn spot")
			return out
		var root := find(int(tspot[0]))
		var want := {}
		for k: int in tspot:
			if k >= 0 and find(k) != root and net[k] == 0:
				want[find(k)] = true
		out["apart"] = want.size()
		if want.is_empty():
			out["ms"] = (Time.get_ticks_usec() - t0) / 1000
			return out
		var members := {}
		for s in spx.size():
			var r := find(s)
			if r == root or want.has(r):
				if not members.has(r):
					members[r] = []
				(members[r] as Array).append(s)
		_add_net(members[root])
		var todo: Array = want.keys()
		todo.sort()
		var kinds := {}
		for radius: int in RADII + [maxi(w, h)]:
			var progress := true
			while progress and not todo.is_empty():
				progress = false
				var left: Array = []
				for r: int in todo:
					if net[int((members[r] as Array)[0])] != 0:
						continue
					var best := _nearest(members[r], radius, true)
					if best.is_empty():
						left.append(r)
						continue
					var kind := _join(best[0], best[1])
					kinds[kind] = int(kinds.get(kind, 0)) + 1
					out["joined"] = int(out["joined"]) + 1
					_add_net(members[r])
					_absorb(members)
					progress = true
				todo = left
		out["kinds"] = kinds
		for i in tg.size():
			var k: int = tspot[i]
			if k >= 0 and net[k] == 0 and find(k) != root:
				missing.append("%s at %s" % [tg[i][0], tg[i][1]])
		out["ms"] = (Time.get_ticks_usec() - t0) / 1000
		return out

	## The floor under every site and route end is never cut by a join.
	func protect(tg: Array) -> void:
		for t: Array in tg:
			var q: Vector2i = t[1]
			for dx in range(-3, 4):
				var x: int = q.x + dx
				if x >= 0 and x < w and q.y >= 1 and q.y < h:
					keep[x + (q.y - 1) * w] = 1

	## The spot of a body standing at feet cell q (a box whose left column is q.x, give or
	## take: the same nodes the monsters' planner and the tools try), or -1.
	func _spot_near(q: Vector2i) -> int:
		for o: Vector2i in NEAR:
			var k := spot(q.x + o.x, q.y + o.y)
			if k >= 0:
				return k
		return -1

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
	## must: a site's or route end's component: if every cheap pair runs into something built,
	## look through the dearer ones too (only then: it scans the whole network).
	func _nearest(m: Array, radius: int, must := false) -> Array:
		var best_cost := INF
		var cands: Array = []
		var stride := maxi(1, m.size() / (SAMPLES if radius < 200 else 8))     # far searches: fewer samples
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
			# rings of blocks outward; a ring d blocks away is at least (d - 1) * 16 tiles away on
			# one axis, so once the best is cheaper than that nothing farther can beat it
			for d in rb + 1:
				if best_cost <= 0.6 * 16.0 * (d - 1):
					break
				for gy in range(by - d, by + d + 1):
					var edge := absi(gy - by) == d
					var gx := bx - d
					while gx <= bx + d:
						var key := gx | (gy << 16)
						var gx0 := gx
						gx = gx + 1 if edge else (gx + 2 * d if d > 0 else gx + 1)
						if gx0 < 0 or gy < 0 or not buckets.has(key):
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
		if not must:
			return []
		var all_pairs := _dear_pairs(blocks, radius)
		for k in mini(all_pairs.size(), MUST_TRIES):
			var cd: Array = all_pairs[k]
			var pa := Vector2i(spx[cd[1]], spy[cd[1]])
			var pb := Vector2i(spx[cd[2]], spy[cd[2]])
			if not _forbidden(pa.x, pa.y, pb.x, pb.y) and not _hits_built(pa, pb):
				return [cd[1], cd[2]]
		return []

	## The MUST_TRIES cheapest pairs of the sampled component spots with network spots within
	## radius, cheapest first. Looks only at the blocks in reach, and cuts the list down as it
	## goes: a search at the world's width would otherwise sort millions of pairs.
	func _dear_pairs(blocks: Dictionary, radius: int) -> Array:
		var pairs: Array = []
		var cut := INF
		var rb := (radius >> 4) + 1
		var whole := (2 * rb + 1) * (2 * rb + 1) * blocks.size() >= buckets.size()
		for bkey: int in blocks:
			var a: int = blocks[bkey]
			var ax := spx[a]
			var ay := spy[a]
			var keys: Array = buckets.keys() if whole else _keys_near(ax >> 4, ay >> 4, rb)
			for key: int in keys:
				for b: int in buckets[key]:
					var dx := absi(spx[b] - ax)
					var dy := absi(spy[b] - ay)
					var cost := dx + 0.6 * dy
					if dx <= radius and dy <= radius and cost < cut:
						pairs.append([cost, a, b])
				if pairs.size() >= 4 * MUST_TRIES:
					pairs.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
					pairs.resize(MUST_TRIES)
					cut = pairs[-1][0]
		pairs.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
		return pairs

	func _keys_near(bx: int, by: int, rb: int) -> Array:
		var out: Array = []
		for gy in range(maxi(0, by - rb), by + rb + 1):
			for gx in range(maxi(0, bx - rb), bx + rb + 1):
				var key := gx | (gy << 16)
				if buckets.has(key):
					out.append(key)
		return out

	## Is this spot over a pass, on the rock of the range?
	func _on_a_peak(s: int) -> bool:
		var py := c.pass_y[spx[s]]
		return py >= 0 and spy[s] > py + Barriers.PASS_CLEAR

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
		if id == c.BEDROCK or (keep[i] != 0 and c.solid[id] != 0):
			return true      # bedrock, a solid floor a join stands on, the floor under a site
		if final and id >= PLACE_TILES:
			return true      # a road, a bridge, a building: never cut
		if id != c.COBBLE or c.solid[c.fg[i + w]] != 0:
			return false
		for r: Rect2i in ruins:
			if r.has_point(Vector2i(x, y)):
				return false     # a buried ruin's walls and floor may be broken into
		return true

	## A component that found nothing at this reach waits for something to be joined near it.
	## Its box (a sample of its spots) is filed under every WAIT_CELL block the box covers, so a
	## join looks only at the components around it. Rescanning every join for every waiting
	## component took 54 of 56 s on a medium world (tracks/barriers.md).
	func _wait(r: int, m: Array) -> void:
		if wait_box.has(r):
			return
		var lx := 1 << 30
		var ly := 1 << 30
		var hx := -(1 << 30)
		var hy := -(1 << 30)
		var stride := maxi(1, m.size() / 16)
		for k in range(0, m.size(), stride):
			var s := int(m[k])
			lx = mini(lx, spx[s])
			ly = mini(ly, spy[s])
			hx = maxi(hx, spx[s])
			hy = maxi(hy, spy[s])
		wait_box[r] = PackedInt32Array([lx, ly, hx, hy])
		for by in range(ly >> WAIT_SHIFT, (hy >> WAIT_SHIFT) + 1):
			for bx in range(lx >> WAIT_SHIFT, (hx >> WAIT_SHIFT) + 1):
				var key := bx | (by << 16)
				if not waiting.has(key):
					waiting[key] = PackedInt32Array()
				var cell: PackedInt32Array = waiting[key]
				cell.append(r)
				waiting[key] = cell

	## Something was joined at q: every component waiting at this radius within reach of it
	## (its box grown by radius + WAIT_MARGIN) tries again.
	func _wake(q: Vector2i, radius: int, tried: Dictionary, woken: Dictionary) -> void:
		var reach := radius + WAIT_MARGIN
		for by in range((q.y - reach) >> WAIT_SHIFT, ((q.y + reach) >> WAIT_SHIFT) + 1):
			if by < 0:
				continue
			for bx in range((q.x - reach) >> WAIT_SHIFT, ((q.x + reach) >> WAIT_SHIFT) + 1):
				var key := bx | (by << 16)
				if bx < 0 or not waiting.has(key):
					continue
				var cell: PackedInt32Array = waiting[key]
				for r: int in cell:
					if tried.get(r, -1) != radius or woken.has(r):
						continue
					var b: PackedInt32Array = wait_box[r]
					if q.x >= b[0] - reach and q.x < b[2] + reach and q.y >= b[1] - reach and q.y < b[3] + reach:
						woken[r] = true

	## Components a feature just built runs through (spots in the cells it touched) are
	## joined by it as well: marked network. Then the feature's own ways (a shaft, a passage)
	## become places later joins may aim at, so a pocket beside a shaft gets a short way into
	## it, not a shaft of its own. Returns the components joined so.
	func _absorb(members: Dictionary) -> int:
		var n := 0
		for rc: Rect2i in touched:
			for yy in range(maxi(1, rc.position.y), mini(h - 1, rc.end.y)):
				for xx in range(maxi(0, rc.position.x), mini(w - 1, rc.end.x)):
					var k := sid[xx + yy * w]
					if k < 0 or k >= net.size() or net[k] != 0:
						continue
					var r := find(k)
					if members.has(r):
						_add_net(members[r])
						n += 1
		for v: Vector2i in aims:
			_virtual(v.x, v.y)
		touched.clear()
		aims.clear()
		return n

	## A standing place on a feature just built (a rung of a shaft, a step of a passage): a
	## network spot for joins to aim at; not a real spot (nothing else sees it).
	func _virtual(x: int, y: int) -> void:
		var k := spx.size()
		spx.append(x)
		spy.append(y)
		parent.append(k)
		net.append(1)
		var key := (x >> 4) | ((y >> 4) << 16)
		if not buckets.has(key):
			buckets[key] = PackedInt32Array()
		var bk: PackedInt32Array = buckets[key]
		if bk.size() < BUCKET_KEEP + 2:
			bk.append(k)
			buckets[key] = bk

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
		# the floor of a way the cut runs through (rock with a body's room over it) stays a
		# floor: a walkway plank, so the way it crosses is not cut in two
		if y + 3 < h and spot(x, y + 1) >= 0 or spot(x - 1, y + 1) >= 0:
			c.fg[x + y * w] = platform
		else:
			c.fg[x + y * w] = c.AIR

	## One column of a carved way: TALL rows open over a floor at floor_y - 1. Rock is cut;
	## open air is crossed by a walkway plank (a bridge), or on the rising part by a stair
	## tread (one-way: it walls nothing off); in the deeps (built) a rising rock floor gets a
	## stair tread too. True if it bridged air.
	func _column(x: int, floor_y: int, rising: bool, built: bool, dir: int) -> bool:
		touched.append(Rect2i(x - 1, floor_y - 1, 3, 4))
		if x % 4 == 0:
			aims.append(Vector2i(x, floor_y))
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
		touched.append(Rect2i(xs - 2, y0 - 1, 6, y1 - y0 + 3))
		for yy in range(y0 + 3, y1, 4):
			aims.append(Vector2i(xs, yy))
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
		# a plank left where the shaft crossed a floor would hold a climber up in its column
		for yy in range(y1, y1 + TALL):
			if lx >= 1 and lx < w - 1 and yy < h - 1 and c.fg[lx + yy * w] == platform:
				c.fg[lx + yy * w] = c.AIR
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
			if not stats.has("cavern_at"):
				stats["cavern_at"] = [cx, fl, y1, y2]
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
