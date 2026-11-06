## Tile navigation for host-simulated bodies on a diggable platformer world.
##
## A node is a body standing (or hanging, flying, swimming) with its box's left column L and
## its feet on row y: it covers columns L..L+cw-1 and rows y..y+ch-1, cw x ch being its box
## rounded up to whole tiles (Medium 1.5 x 2.5 -> 2 x 3: it fits a 2-wide, 3-high gap, a
## Large 3 x 4 does not). Edges are what the real PlayerController can do with that body's
## MoveStats:
##   WALK      to the next column, with step-up (stats.step_tiles) and step-down snaps
##   DROP      walk off a ledge and fall (cost grows past the fall-damage height)
##   JUMP      an arc recorded by running PlayerController itself on an empty world with
##             scripted inputs (hold time, when to steer), for this exact MoveStats; valid
##             where every cell its box swept is free and the landing node stands
##   PLATFORM  down + jump through one-way tiles (onto stairs: one tile is enough)
##   STAIRS    up a staircase: to the next column one row up where a tread sits at the
##             feet's row (the follower holds W, as a player must to take stairs); down a
##             staircase is a one-row DROP the controller steps
##   LADDER    up / down a ladder in the box's centre column (anyone)
##   CLING     up / down a wall and over its top (bodies with a climb speed)
##   FLY       any of the 8 neighbours through open space (bodies with a fly speed)
##   SWIM      any of the 8 neighbours through liquid (everyone; half speed without a swim speed)
## Diggers (a burrow speed, or the Tunnelling affix) may also walk through solid tiles up to
## a hardness; the follower digs them (NavFollow).
##
## Searches are A* inside a window (WINDOW tiles each way from the start), bounded in
## expansions, resumable (NavSearch.step) so a scheduler can spread them over ticks.
##
##   var prof := MonsterNav.profile(stats)
##   var s := MonsterNav.start(world, prof, from_pos, to_pos)
##   while not s.step(500): pass
##   var path: NavPath = s.result()      # null if nothing reachable
class_name MonsterNav
extends RefCounted

enum Edge { WALK, DROP, JUMP, PLATFORM, LADDER, CLING, FLY, SWIM, STAIRS }
const EDGE_NAMES := ["walk", "drop", "jump", "platform", "ladder", "cling", "fly", "swim", "stairs"]

const WINDOW := 64
## Cell flags.
const SOLID := 1
const ONEWAY := 2       # platform or ladder top: blocks only from above
const LADDER := 4
const WET := 8          # liquid at least half full
const SOFT := 16        # diggable by the Tunnelling affix (hardness <= SOFT_HARDNESS)
const ROCK := 32        # diggable by a burrower (hardness <= ROCK_HARDNESS)
const STAIR := 64       # a stair tread (also ONEWAY)
const KNOWN := 128
const SOFT_HARDNESS := 0.6
const ROCK_HARDNESS := 2.0
## Falls longer than this (tiles) cost extra (fall damage starts past 10 ft = 4 tiles).
const SAFE_FALL := 4
const MAX_FALL := 24
## Hold times (ticks) and steering delays (ticks) of the recorded jumps.
const JUMP_HOLDS := [2, 4, 7, 12]
const JUMP_DELAYS := [0, 3, 6, 9]
const JUMP_MAX_TICKS := 45

static var _profiles := {}

## What a body of these MoveStats can do, with its recorded jumps. Cached per movement key.
static func profile(stats: MoveStats, dig_hardness := 0.0) -> NavProfile:
	var key := "%s|%.2f|%.2f|%.2f|%.2f|%.2f|%d|%.2f" % [stats.size_name, stats.run_speed, stats.jump_velocity,
		stats.gravity, stats.climb_speed, stats.fly_speed, stats.step_tiles, dig_hardness]
	var p: NavProfile = _profiles.get(key)
	if p != null:
		return p
	p = NavProfile.new()
	p.key = key
	p.stats = stats
	p.w = stats.size.x
	p.h = stats.size.y
	p.cw = ceili(stats.size.x - 1e-3)
	p.ch = ceili(stats.size.y - 1e-3)
	p.step = stats.step_tiles
	p.climb = stats.climb_speed > 0.0
	p.fly = stats.fly_speed > 0.0
	p.walker = stats.run_speed > 0.5
	p.swim_speed = stats.swim_speed
	p.dig = dig_hardness
	p.run = maxf(stats.run_speed, 0.5)
	p.max_speed = maxf(maxf(p.run, stats.fly_speed), maxf(stats.swim_speed, stats.ladder_speed))
	if p.walker:
		_record_jumps(p)
	_profiles[key] = p
	return p

## Start a search from a body position (feet) to a goal position (feet). tol: how close (in
## tiles, x and y) the end node must be to the goal node; partial: settle for the reachable
## node nearest the goal when the goal cannot be reached.
static func start(world: TileWorld, prof: NavProfile, from: Vector2, to: Vector2, tol := Vector2i(1, 1),
		partial := true, max_expand := 6000, radius := Vector2i(-1, -1)) -> NavSearch:
	var s := NavSearch.new()
	s.setup(world, prof, node_of(prof, from), node_of(prof, to), tol, partial, max_expand, radius)
	return s

## The node a body at `pos` (feet) occupies: left column of its box, feet row.
static func node_of(prof: NavProfile, pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x - prof.cw * 0.5 + 0.5), floori(pos.y + 0.05))

## Feet position at a node's middle.
static func node_pos(prof: NavProfile, n: Vector2i) -> Vector2:
	return Vector2(n.x + prof.cw * 0.5, n.y)

static func cell_flags(world: TileWorld, x: int, y: int) -> int:
	var id := world.get_fg(x, y)
	var f := 0
	if TileDefs.solid[id] != 0:
		f |= SOLID
		var hd := TileDefs.hardness[id]
		if hd > 0.0 and hd <= SOFT_HARDNESS:
			f |= SOFT | ROCK
		elif hd > 0.0 and hd <= ROCK_HARDNESS:
			f |= ROCK
	elif TileDefs.platform[id] != 0:
		f |= ONEWAY
		if TileDefs.stairs[id] != 0:
			f |= STAIR
	elif TileDefs.ladder[id] != 0:
		f |= LADDER
		if TileDefs.ladder[world.get_fg(x, y + 1)] == 0:
			f |= ONEWAY
	if (world.get_liquid(x, y) & 15) >= 8:
		f |= WET
	return f

# --- jumps: recorded from the real controller -------------------------------------------------

## Fly a body through scripted jumps on an empty world and keep every landing it could make:
## the cells its box swept (relative to the start node) and the inputs that made it.
static func _record_jumps(p: NavProfile) -> void:
	var world := TileWorld.new(96, 96)
	var sx := 40
	var sy := 40
	var stone := TileDefs.id("stone")
	for c in range(sx, sx + p.cw):
		world.set_fg(c, sy - 1, stone, true)
	var best := {}
	var dt := 1.0 / MoveStats.step_hz()
	var steps := maxi(1, MoveStats.step_hz() / K.TICK_HZ)
	for hold: int in JUMP_HOLDS:
		for delay: int in JUMP_DELAYS:
			var b := p.stats.make_body()
			b.pos = Vector2(sx + p.cw * 0.5, sy)
			TileCollision.update_contacts(world, b)
			var cells := {}         # packed offset -> 1 ascending, 2 descending
			var left := false
			var done := false
			var inp := PlayerInput.new()
			for tick in JUMP_MAX_TICKS:
				inp.jump = tick < hold
				inp.jump_pressed = tick == 0
				inp.move_x = 1.0 if tick >= delay else 0.0
				for s in steps:
					var prev := b.pos
					PlayerController.step(world, b, inp, p.stats, dt)
					inp.jump_pressed = false
					if not b.on_floor:
						left = true
					elif left:
						done = true       # came back down on the start floor
						break
					# landings: every whole row crossed on the way down
					if b.vel.y < 0.0 and floorf(prev.y) > b.pos.y and prev.y - b.pos.y > 0.0:
						var yb := floorf(prev.y)
						while yb > b.pos.y and yb >= sy - MAX_FALL:
							var f := (prev.y - yb) / (prev.y - b.pos.y)
							var xc := lerpf(prev.x, b.pos.x, f)
							_landing(p, best, cells, xc, int(yb), sx, sy, hold, delay, tick + 1)
							yb -= 1.0
					_sweep_cells(p, cells, b, sx, sy)
					if b.pos.y < sy - MAX_FALL:
						done = true
						break
				if done:
					break
	var out: Array = []
	for k in best:
		for j: Dictionary in best[k]:
			out.append(j)
			out.append(_mirror(p, j))
	# shortest first, so a search meets cheap arcs first
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["t"] < b["t"])
	p.jumps = out
	for j: Dictionary in out:
		p.jdl.append(int(j["dl"]))
		p.jdy.append(int(j["dy"]))

static func _sweep_cells(p: NavProfile, cells: Dictionary, b: Body, sx: int, sy: int) -> void:
	var g := 0.05
	var x0 := floori(b.left() - g)
	var x1 := ceili(b.right() + g) - 1
	var y0 := floori(b.pos.y + 0.01)
	var y1 := ceili(b.top() + g) - 1
	var mark := 2 if b.vel.y < 0.0 else 1
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			var k := _pack(cx - sx, cy - sy)
			cells[k] = maxi(int(cells.get(k, 0)), mark)

static func _landing(p: NavProfile, best: Dictionary, cells: Dictionary, xc: float, yb: int, sx: int, sy: int,
		hold: int, delay: int, ticks: int) -> void:
	var lx := floori(xc - p.cw * 0.5 + 0.5)
	var dl := lx - sx
	var dy := yb - sy
	if dl == 0 and dy <= 0:
		return            # straight down or back where it started: walking covers it
	if dy < 0 and absi(dl) <= 1:
		return            # a drop does this
	if dy < -8:
		return            # long jumps down: drops and shorter hops do it more simply
	var foot := cells.duplicate()
	# the box at the landing spot itself
	for cy in range(yb, yb + p.ch):
		for cx in range(floori(xc - p.w * 0.5 - 0.05), ceili(xc + p.w * 0.5 + 0.05)):
			var k := _pack(cx - sx, cy - sy)
			foot[k] = maxi(int(foot.get(k, 0)), 2)
	var asc := PackedInt32Array()
	var desc := PackedInt32Array()
	for k: int in foot:
		if int(foot[k]) == 2:
			desc.append(k)
		else:
			asc.append(k)
	var j := {"dl": dl, "dy": dy, "hold": hold, "delay": delay, "dir": 1, "ticks": ticks,
		"t": ticks / float(K.TICK_HZ), "asc": asc, "desc": desc, "xc": xc - sx}
	var key := _pack(dl, dy)
	var list: Array = best.get(key, [])
	# keep the quickest, plus the one that steers latest (it clears ledges under the jumper)
	if list.is_empty():
		list = [j]
	elif ticks < int(list[0]["ticks"]) or (ticks == int(list[0]["ticks"]) and asc.size() + desc.size() < (list[0]["asc"] as PackedInt32Array).size() + (list[0]["desc"] as PackedInt32Array).size()):
		list[0] = j
	elif list.size() < 2 and delay > int(list[0]["delay"]):
		list.append(j)
	elif list.size() == 2 and delay > int(list[1]["delay"]):
		list[1] = j
	best[key] = list

## The same jump to the left: offsets mirrored around the start node's middle.
static func _mirror(p: NavProfile, j: Dictionary) -> Dictionary:
	var m := j.duplicate()
	m["dir"] = -1
	var xc := float(p.cw) - float(j["xc"])      # around sx + cw/2
	m["xc"] = xc
	m["dl"] = floori(xc - p.cw * 0.5 + 0.5)
	for f: String in ["asc", "desc"]:
		var src: PackedInt32Array = j[f]
		var dst := PackedInt32Array()
		dst.resize(src.size())
		for i in src.size():
			var o := _unpack(src[i])
			dst[i] = _pack(p.cw - 1 - o.x, o.y)
		m[f] = dst
	return m

static func _pack(dx: int, dy: int) -> int:
	return (dx + 512) | ((dy + 512) << 10)

static func _unpack(k: int) -> Vector2i:
	return Vector2i((k & 1023) - 512, ((k >> 10) & 1023) - 512)
