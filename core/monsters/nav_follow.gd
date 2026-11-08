## Turns a NavPath into PlayerInputs, one per host tick, for the real PlayerController (the
## host runs MoveStats.step_hz() / K.TICK_HZ controller steps per tick with that input, the
## jump press only on the first). Jumps hold the recorded jump button and steer along the
## recorded arc: each tick the steering that keeps the body nearest the arc is tried on a
## copy of the body (so a take-off a little off its spot, or a wall, is corrected in the
## air). Everything else steers toward the next node's middle. Diggers dig the solid cells
## of the next node first.
## Recovery: a body standing on a node of its path a little ahead (it landed further on) or
## behind (it fell back) picks the path up from there instead of giving up; a stuck edge
## fails (the caller replans from where the body is).
##
##   follow.set_path(path)
##   var inp := follow.input(world, e.body)      # null: arrived, or failed (see failed)
class_name NavFollow
extends RefCounted

const E := MonsterNav.Edge
## Seconds without getting closer to the next node before the follower gives up.
const STUCK_S := 1.2
## Seconds a jump waits to line up on its take-off spot before it goes from where it is.
const ALIGN_S := 1.0
## How many times a path may be picked up again behind where it was before it fails.
const MAX_FALLBACKS := 6
## Tiles a climb may stop short of a ladder node's row and count as there: float noise only,
## under TileCollision.EPS (a body held EPS under the top rung beside rock cannot step off).
const LADDER_TOL := 5e-4
## Tiles a climb goes past a ladder node's row before a walk sideways off the ladder: let go
## at the row, a body at a walking pace drops into a hole between the ladder and the ledge
## before its box is over the ledge (dev seed 2's descent).
const STEP_OFF_LIFT := 0.45
## Seconds a platform drop waits before pressing down + jump again.
const DROP_RETRY_S := 0.3

var path: NavPath
var i := 1
var failed := false
var why := ""
## Ticks into the current jump (-1: not jumping yet).
var jump_t := -1
## The current jump edge has been jumped (now settling onto its node).
var jumped := false
var _best := INF
var _since := 0.0
var _dig_t := 0.0
var _dig_at := Vector2i(-99999, -99999)
var _dropped := false
var _align := 0.0
var _fallbacks := 0
var _jump_from := Vector2.ZERO
var _carrot_end := 0
## Cells dug so far (for tests and the track notes).
var dug := 0

func set_path(p: NavPath) -> void:
	path = p
	i = 1
	failed = false
	why = ""
	_fallbacks = 0
	_reset_edge()

func active() -> bool:
	return path != null and not failed and i < path.size()

func target_node() -> Vector2i:
	return path.nodes[mini(i, path.size() - 1)] if path != null and path.size() > 0 else Vector2i.ZERO

func _reset_edge() -> void:
	jump_t = -1
	jumped = false
	_best = INF
	_since = 0.0
	_dig_t = 0.0
	_dropped = false
	_align = 0.0

func _fail(reason: String) -> PlayerInput:
	failed = true
	why = reason
	return null

## The input for this tick, or null when the path is done (arrived) or failed.
func input(world: TileWorld, b: Body, dt: float, dig_rate := 1.0) -> PlayerInput:
	if path == null or failed:
		return null
	var prof := path.prof
	if jump_t < 0:
		_resync(prof, b)
		if failed:
			return null
	while i < path.size():
		var tgt: Vector2i = path.nodes[i]
		var edge := path.how[i] & 15
		if jump_t < 0 and _arrived(prof, b, tgt, edge):
			i += 1
			_reset_edge()
			continue
		break
	if i >= path.size():
		return null
	var tgt: Vector2i = path.nodes[i]
	var edge := path.how[i] & 15
	var extra := path.how[i] >> 4
	var tp := MonsterNav.node_pos(prof, tgt)
	var inp := PlayerInput.new()
	# progress watchdog (a jump has its own clock)
	var d := b.pos.distance_to(tp)
	if d < _best - 0.15:
		_best = d
		_since = 0.0
	else:
		_since += dt
	if _since > STUCK_S and jump_t < 0 and _dig_t <= 0.0:
		return _fail("stuck going %s to %d,%d" % [MonsterNav.EDGE_NAMES[edge], tgt.x, tgt.y])
	# diggers clear the next node first
	if prof.dig > 0.0 and edge in [E.WALK, E.DROP]:
		var cell := _solid_cell(world, prof, tgt)
		if cell != Vector2i(-99999, -99999):
			if cell != _dig_at:
				_dig_at = cell
				_dig_t = 0.0
			_dig_t += dt
			_since = 0.0
			var hd := TileDefs.hardness[world.get_fg(cell.x, cell.y)]
			if hd < 0.0 or hd > prof.dig:
				return _fail("cannot dig %d,%d" % [cell.x, cell.y])
			if _dig_t >= hd / maxf(dig_rate, 0.05):
				world.set_fg(cell.x, cell.y, TileDefs.AIR)
				dug += 1
				_dig_t = 0.0
			inp.move_x = 0.0
			b.facing = 1 if cell.x + 0.5 >= b.pos.x else -1
			return inp
	match edge:
		E.WALK:
			var aim := _carrot(prof, b)
			inp.move_x = _approach(world, b, aim, dt)
			if b.climbing:                  # stepping off a ladder sideways, at the node's height
				inp.move_x = signf(tp.x - b.pos.x)
				inp.up = tp.y > b.pos.y + 0.002
		E.STAIRS:
			inp.move_x = _approach(world, b, _carrot(prof, b), dt)   # run up a flight, not node by node
			# W takes a staircase; once on it, it keeps climbing. Not with a ladder in the body's
			# centre column: there W takes the ladder (a flight can start beside one). The leading
			# edge reaches the tread after the centre has left the ladder.
			inp.up = not b.on_stairs and not TileCollision.ladder_at(world, b)
		E.DROP:
			inp.move_x = _aim(world, b, tp.x, dt)
			if b.climbing:                  # off a ladder or rope onto the floor beside it
				inp.move_x = _steer(tp.x - b.pos.x, 2.0)
				inp.down = true
			elif b.clinging:                  # let go of the wall
				inp.move_x = -float(b.wall_dir)
			elif b.on_floor and tgt.y < floori(b.pos.y + 0.05) and absf(tp.x - b.pos.x) < 0.6 \
					and TileCollision.on_platform_only(world, b) and not TileCollision.ladder_at(world, b, true):
				inp.down = true             # on a walkway over the stairs going on down: S
		E.PLATFORM:
			var top: Vector2i = path.nodes[i - 1]
			if b.climbing:                  # caught on a ladder dropping past it: climb on down
				inp.down = true
				inp.move_x = _steer(tp.x - b.pos.x, 2.0)   # over the node's columns, not the rock beside
				if b.on_floor and absf(b.vel.y) < 0.01 and floori(b.pos.y + 0.05) >= top.y:
					# held up by a walkway or tread on the ladder: let go (down + jump), stepping
					# off the ladder's column so it is not grabbed again, then drop through
					inp.jump_pressed = true
					inp.move_x = 1.0 if b.pos.x - floorf(b.pos.x) > 0.5 else -1.0
			elif b.on_floor and floori(b.pos.y + 0.05) < top.y and floori(b.pos.y + 0.05) > tgt.y \
					and TileCollision.on_platform_only(world, b):
				if not _dropped or _align > DROP_RETRY_S:  # on a walkway part of the way down: through it too
					inp.down = true
					inp.jump = true
					inp.jump_pressed = true
					_dropped = true
					_align = 0.0
					_since = 0.0
				_align += dt
			elif b.on_floor and floori(b.pos.y + 0.05) >= top.y:
				# still on the walkway: stand over the drop (only one-way tiles under the box),
				# then down + jump; again if it did not go through
				var off := MonsterNav.node_pos(prof, top).x - b.pos.x
				_align += dt
				if (absf(off) > 0.12 or absf(b.vel.x) > 1.5 or not TileCollision.on_platform_only(world, b)) and _align < 1.0:
					inp.move_x = _steer(off, 3.0) if absf(off) > 0.03 else 0.0
				elif not _dropped or _align > DROP_RETRY_S:
					inp.down = true
					inp.jump = true
					inp.jump_pressed = true
					_dropped = true
					_align = 0.0
					_since = 0.0
			else:
				inp.move_x = _aim(world, b, tp.x, dt)
		E.JUMP:
			var j: Dictionary = prof.jumps[extra]
			if jumped and jump_t < 0:
				inp.move_x = _aim(world, b, tp.x, dt)
				return inp
			if jump_t < 0:
				var from := MonsterNav.node_pos(prof, path.nodes[i - 1])
				var off := from.x - b.pos.x
				_align += dt
				var held := b.climbing and absf(b.pos.y - from.y) <= 0.3 and absf(off) <= 0.3 \
					and TileCollision.is_ladder(world, floori(from.x), floori(from.y + 0.5))
				if held or b.on_floor and not b.climbing and (absf(off) <= 0.15 and absf(b.vel.x) <= 1.5 or _align > ALIGN_S):
					jump_t = 0          # in place (or from the ladder it stands in), or as close as a wall lets it get
					_jump_from = from
				else:
					inp.move_x = _aim(world, b, from.x, dt) if absf(off) > 0.03 or absf(b.vel.x) > 1.0 else 0.0
					inp.up = b.on_floor and from.y > b.pos.y + 0.5    # back up the stairs it ran down
					if b.climbing:              # on a ladder at the take-off: get onto the floor
						# up to the floor's height (a ladder step overshoots it a little: not back
						# down for that), then sideways off the ladder onto the floor
						inp.up = from.y > b.pos.y + 0.002
						inp.down = b.pos.y > from.y + 0.6
						var away := from.x - (floorf(b.pos.x) + 0.5)
						inp.move_x = signf(off) if absf(off) > 0.05 else signf(away)
					return inp
			inp.jump = jump_t < int(j["hold"])
			inp.jump_pressed = jump_t == 0
			inp.move_x = _track(world, b, inp, j, dt)
			jump_t += 1
			_since = 0.0
			if jump_t > 3 and b.on_floor and b.vel.y <= 0.0 and jump_t >= int(j["hold"]):
				# down already (on the node, or short of it): settle from here
				jump_t = int(j["ticks"]) + 2
			if jump_t > int(j["ticks"]) + 1:
				# the recorded landing tick has passed: settle onto the node
				jump_t = -1
				jumped = true
				_best = INF
		E.LADDER:
			# the node's middle has the ladder in its centre column and keeps a wide box clear
			# of the rock beside a ladder in a narrow shaft. An even box's middle is the ladder
			# column's west edge, so aim a little inside it: a body a hair west of that edge (in
			# the steering's dead zone) has the column beside the ladder as its centre and never
			# takes hold (a rope in the open, a descent walk on dev seed 2).
			var lx := tp.x
			if prof.cw % 2 == 0:
				lx += minf(0.2, (prof.cw - prof.w) * 0.5 - 0.02)
			inp.move_x = _steer(lx - b.pos.x, 4.0 if not b.climbing else 2.0)
			var lift := _step_off_lift(b)
			inp.up = tgt.y > floori(b.pos.y + 0.05) or (b.climbing and tp.y + lift > b.pos.y + LADDER_TOL)
			inp.down = not inp.up and (tgt.y < floori(b.pos.y + 0.05) or tgt.y < b.pos.y - 0.2
				or (b.climbing and tp.y < b.pos.y - LADDER_TOL))
		E.CLING:
			var side := b.wall_dir if b.wall_dir != 0 else ((extra & 3) - 1 if extra != 0 else _wall_side(world, prof, tgt))
			if tgt.x != path.nodes[i - 1].x:          # over the top of the wall
				inp.move_x = signf(tp.x - b.pos.x)
				inp.up = true
			else:
				inp.move_x = float(side) if side != 0 else _steer(tp.x - b.pos.x, 3.0)
				inp.up = tgt.y > b.pos.y + 0.1
				inp.down = tgt.y < b.pos.y - 0.1
		E.FLY, E.SWIM:
			inp.move_x = _steer(tp.x - b.pos.x, 2.5)
			var dy := tp.y - b.pos.y
			inp.up = dy > 0.2
			inp.down = dy < -0.2
			if edge == E.SWIM and inp.up:
				inp.jump = true
				inp.jump_pressed = b.swimming and b.in_liquid < prof.stats.leap_below     # the leap out at the surface
	return inp

## The steering for this tick of a jump: of a few choices (the recorded one first), the one
## that leaves a copy of the body nearest the recorded arc after this tick.
func _track(world: TileWorld, b: Body, inp: PlayerInput, j: Dictionary, dt: float) -> float:
	var rec := float(j["dir"]) if jump_t >= int(j["delay"]) else 0.0
	var tx: PackedFloat32Array = j.get("tx", PackedFloat32Array())
	if tx.is_empty():
		return rec
	var want := _jump_from.x + tx[mini(jump_t, tx.size() - 1)]
	var st: MoveStats = path.prof.stats
	var steps := maxi(1, roundi(dt * MoveStats.step_hz()))
	var sdt := 1.0 / MoveStats.step_hz()
	var best := rec
	var best_err := INF
	for mx: float in [rec, 0.0, 1.0, -1.0, 0.5, -0.5]:
		var c := b.duplicate_body()
		var ci := PlayerInput.new()
		ci.jump = inp.jump
		ci.jump_pressed = inp.jump_pressed
		ci.move_x = mx
		for k in steps:
			PlayerController.step(world, c, ci, st, sdt)
			ci.jump_pressed = false
		var err := absf(c.pos.x - want) + (0.0 if mx == rec else 0.03)
		if err < best_err - 1e-4:
			best_err = err
			best = mx
	return best

## Steering toward x (a drop's landing, a jump's node): of a few choices, the one whose copy
## of the body, after this tick and a few more coasting with no input, ends nearest x. So a
## fall does not overshoot a narrow ledge, and a run off a ledge brakes in time.
func _aim(world: TileWorld, b: Body, x: float, dt: float) -> float:
	var d := x - b.pos.x
	if b.on_floor and absf(d) > 2.5:
		return signf(d)
	var st: MoveStats = path.prof.stats
	var steps := maxi(1, roundi(dt * MoveStats.step_hz()))
	var sdt := 1.0 / MoveStats.step_hz()
	var best := 0.0
	var best_err := INF
	var ci := PlayerInput.new()
	for mx: float in [signf(d), 0.0, 0.5 * signf(d), -signf(d)]:
		var c := b.duplicate_body()
		ci.move_x = mx
		for k in steps * 4:
			if k == steps:
				ci.move_x = 0.0
			PlayerController.step(world, c, ci, st, sdt)
		var err := absf(c.pos.x - x)
		if err < best_err - 1e-3:
			best_err = err
			best = mx
	return best

## Pick the path up where the body stands: a node a little ahead (it got further than the
## edge it was on) or behind (it fell back down): then on from there. Too many falls back
## and the path fails.
func _resync(prof: NavProfile, b: Body) -> void:
	if i >= path.size() or not b.on_floor or b.climbing or absf(b.vel.y) > 0.01:
		return
	var bn := MonsterNav.node_of(prof, b.pos)
	for j in range(i, mini(path.size(), i + 8)):
		if path.nodes[j] == bn:
			if j > i:
				i = j
				_reset_edge()
			return
	# a node ahead a column or a row off (a landing that slid on, stairs that took it a row
	# down): from there on
	if jumped or _since > 0.4:
		for j in range(i, mini(path.size(), i + 8)):
			var o: Vector2i = path.nodes[j] - bn
			if absi(o.x) <= 1 and absi(o.y) <= 1:
				i = j + 1
				_reset_edge()
				return
	if path.nodes[i - 1] == bn:
		if jumped:              # the jump came back down where it started: again
			_fallbacks += 1
			if _fallbacks > MAX_FALLBACKS:
				_fail("jump failed again and again to %d,%d" % [path.nodes[i].x, path.nodes[i].y])
				return
			_reset_edge()
		return
	for j in range(i - 2, maxi(0, i - 16) - 1, -1):
		if path.nodes[j] == bn:
			_fallbacks += 1
			if _fallbacks > MAX_FALLBACKS:
				_fail("fell back too often going %s to %d,%d" % [MonsterNav.EDGE_NAMES[path.how[i] & 15], path.nodes[i].x, path.nodes[i].y])
				return
			i = j + 1
			_reset_edge()
			return

## Running toward x: full speed while far, then braking in time (simulated, _aim) when the
## run ends there at an edge that wants the body still (a jump, a drop, a ladder).
func _approach(world: TileWorld, b: Body, x: float, dt: float) -> float:
	var d := x - b.pos.x
	if absf(d) > 3.0 or not b.on_floor:
		return _steer(d, 2.5)
	if _carrot_end + 1 < path.size() and (path.how[_carrot_end + 1] & 15) in [E.WALK, E.STAIRS]:
		return _steer(d, 2.5)
	return _aim(world, b, x, dt) if absf(d) > 0.03 or absf(b.vel.x) > 1.0 else 0.0

## Where a run of walks in one direction ends (at most 4 ahead): no slowing at every node.
func _carrot(prof: NavProfile, b: Body) -> float:
	var tgt: Vector2i = path.nodes[i]
	var dir := signi(tgt.x - path.nodes[i - 1].x)
	var k := i
	while k + 1 < path.size() and k < i + 4:
		var e := path.how[k + 1] & 15
		var n: Vector2i = path.nodes[k + 1]
		if (e != E.WALK and e != E.STAIRS) or signi(n.x - path.nodes[k].x) != dir:
			break
		k += 1
	_carrot_end = k
	return MonsterNav.node_pos(prof, path.nodes[k]).x

func _arrived(prof: NavProfile, b: Body, tgt: Vector2i, edge: int) -> bool:
	var tp := MonsterNav.node_pos(prof, tgt)
	var dx := absf(b.pos.x - tp.x)
	var dy := absf(b.pos.y - tp.y)
	match edge:
		E.FLY, E.SWIM:
			return dx <= 0.45 and dy <= 0.45
		E.LADDER:
			# past the node's row in the direction of travel (a body half in a floor row cannot leave
			# sideways; at 3 tiles/s a climb that stopped 0.001 short of the top rung was held by
			# the rock beside it, so only float noise is forgiven: LADDER_TOL)
			var up := i > 0 and tgt.y > path.nodes[i - 1].y
			var past := b.pos.y >= tp.y + _step_off_lift(b) - LADDER_TOL if up else b.pos.y <= tp.y + LADDER_TOL
			return past and dy <= 0.6 and (b.climbing or b.on_floor or b.clinging) and dx <= 0.75
		E.CLING:
			return dy <= 0.35 and dx <= 0.6 and (b.clinging or b.on_floor or b.climbing)
		E.WALK, E.STAIRS:
			# keep running: arrived once its box is in the node's columns, on the node's row
			return MonsterNav.node_of(prof, b.pos) == tgt and (b.on_floor or b.climbing or b.swimming) \
				or (dx <= 0.3 and dy <= 0.3)
	return (b.on_floor or b.swimming or b.climbing) and dx <= 0.65 and dy <= 0.3

## STEP_OFF_LIFT while climbing up to node i when the path walks sideways off it next, else 0.
func _step_off_lift(b: Body) -> float:
	if not b.climbing or i < 1 or i + 1 >= path.size():
		return 0.0
	var tgt: Vector2i = path.nodes[i]
	var nxt: Vector2i = path.nodes[i + 1]
	if tgt.y <= path.nodes[i - 1].y or nxt.y != tgt.y or (path.how[i + 1] & 15) != E.WALK:
		return 0.0
	return STEP_OFF_LIFT

static func _steer(d: float, gain: float) -> float:
	if absf(d) < 0.04:
		return 0.0
	return clampf(d * gain, -1.0, 1.0)

## The side (-1, +1) of node n's box with a wall beside it (the one a climber holds), 0 none.
static func _wall_side(world: TileWorld, prof: NavProfile, n: Vector2i) -> int:
	for r in range(n.y, n.y + prof.ch):
		if world.is_solid(n.x - 1, r):
			return -1
		if world.is_solid(n.x + prof.cw, r):
			return 1
	return 0

static func _solid_cell(world: TileWorld, prof: NavProfile, n: Vector2i) -> Vector2i:
	for r in range(n.y, n.y + prof.ch):
		for c in range(n.x, n.x + prof.cw):
			if world.is_solid(c, r):
				return Vector2i(c, r)
	return Vector2i(-99999, -99999)
