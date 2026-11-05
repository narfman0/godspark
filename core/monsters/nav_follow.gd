## Turns a NavPath into PlayerInputs, one per host tick, for the real PlayerController (the
## host runs MoveStats.step_hz() / K.TICK_HZ controller steps per tick with that input, the
## jump press only on the first). Jumps replay the recorded inputs exactly; everything else
## steers toward the next node's middle. Diggers dig the solid cells of the next node first.
##
##   follow.set_path(path)
##   var inp := follow.input(world, e.body)      # null: arrived, or failed (see failed)
class_name NavFollow
extends RefCounted

const E := MonsterNav.Edge
## Seconds without getting closer to the next node before the follower gives up.
const STUCK_S := 1.2

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
## Cells dug so far (for tests and the track notes).
var dug := 0

func set_path(p: NavPath) -> void:
	path = p
	i = 1
	failed = false
	why = ""
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

func _fail(reason: String) -> PlayerInput:
	failed = true
	why = reason
	return null

## The input for this tick, or null when the path is done (arrived) or failed.
func input(world: TileWorld, b: Body, dt: float, dig_rate := 1.0) -> PlayerInput:
	if path == null or failed:
		return null
	var prof := path.prof
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
		return _fail("stuck going %s to %d,%d" % [["walk", "drop", "jump", "platform", "ladder", "cling", "fly", "swim"][edge], tgt.x, tgt.y])
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
			inp.move_x = _steer(aim - b.pos.x, 2.5)
			if b.climbing:                  # stepping off a ladder sideways
				inp.move_x = signf(tp.x - b.pos.x)
		E.DROP:
			inp.move_x = _steer(tp.x - b.pos.x, 3.0 if b.on_floor else 4.0)
			if b.clinging:                  # let go of the wall
				inp.move_x = -float(b.wall_dir)
		E.PLATFORM:
			if b.climbing:                  # caught on a ladder dropping past it: climb on down
				inp.down = true
			elif b.on_floor and not _dropped:
				inp.down = true
				inp.jump = true
				inp.jump_pressed = true
				_dropped = true
			else:
				inp.move_x = _steer(tp.x - b.pos.x, 3.0)
		E.JUMP:
			var j: Dictionary = prof.jumps[extra]
			if jumped and jump_t < 0:
				inp.move_x = _steer(tp.x - b.pos.x, 3.0)
				return inp
			if jump_t < 0:
				var from := MonsterNav.node_pos(prof, path.nodes[i - 1])
				var off := from.x - b.pos.x
				if b.on_floor and absf(off) <= 0.2 and absf(b.vel.x) <= 2.0:
					jump_t = 0
				else:
					inp.move_x = _steer(off, 3.0) if absf(off) > 0.05 else 0.0
					return inp
			inp.jump = jump_t < int(j["hold"])
			inp.jump_pressed = jump_t == 0
			inp.move_x = float(j["dir"]) if jump_t >= int(j["delay"]) else 0.0
			jump_t += 1
			_since = 0.0
			if jump_t > int(j["ticks"]) + 1:
				# the recorded landing tick has passed: settle onto the node
				jump_t = -1
				jumped = true
				_best = INF
				inp.move_x = _steer(tp.x - b.pos.x, 3.0)
		E.LADDER:
			var cc := floori(tgt.x + prof.cw * 0.5)
			if not b.climbing:
				inp.move_x = _steer(cc + 0.5 - b.pos.x, 4.0)
			inp.up = tgt.y > floori(b.pos.y + 0.05)
			inp.down = tgt.y < floori(b.pos.y + 0.05) or (not inp.up and tgt.y < b.pos.y - 0.2)
		E.CLING:
			var side := b.wall_dir if b.wall_dir != 0 else ((extra & 3) - 1 if extra != 0 else 0)
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
	return inp

## Where a run of walks in one direction ends (at most 4 ahead): no slowing at every node.
func _carrot(prof: NavProfile, b: Body) -> float:
	var tgt: Vector2i = path.nodes[i]
	var dir := signi(tgt.x - path.nodes[i - 1].x)
	var k := i
	while k + 1 < path.size() and k < i + 4:
		var e := path.how[k + 1] & 15
		var n: Vector2i = path.nodes[k + 1]
		if e != E.WALK or signi(n.x - path.nodes[k].x) != dir:
			break
		k += 1
	return MonsterNav.node_pos(prof, path.nodes[k]).x

func _arrived(prof: NavProfile, b: Body, tgt: Vector2i, edge: int) -> bool:
	var tp := MonsterNav.node_pos(prof, tgt)
	var dx := absf(b.pos.x - tp.x)
	var dy := absf(b.pos.y - tp.y)
	match edge:
		E.FLY, E.SWIM:
			return dx <= 0.45 and dy <= 0.45
		E.LADDER:
			# past the node's row in the direction of travel (a body half in a floor row cannot leave sideways)
			var up := i > 0 and tgt.y > path.nodes[i - 1].y
			var past := b.pos.y >= tp.y - 0.02 if up else b.pos.y <= tp.y + 0.02
			return past and dy <= 0.6 and (b.climbing or b.on_floor) and dx <= 0.75
		E.CLING:
			return dy <= 0.35 and dx <= 0.6 and (b.clinging or b.on_floor)
		E.WALK:
			# keep running: arrived once its box is in the node's columns, on the node's row
			return MonsterNav.node_of(prof, b.pos) == tgt and (b.on_floor or b.climbing or b.swimming) \
				or (dx <= 0.3 and dy <= 0.3)
	return (b.on_floor or b.swimming or b.climbing) and dx <= 0.65 and dy <= 0.3

static func _steer(d: float, gain: float) -> float:
	if absf(d) < 0.04:
		return 0.0
	return clampf(d * gain, -1.0, 1.0)

static func _solid_cell(world: TileWorld, prof: NavProfile, n: Vector2i) -> Vector2i:
	for r in range(n.y, n.y + prof.ch):
		for c in range(n.x, n.x + prof.cw):
			if world.is_solid(c, r):
				return Vector2i(c, r)
	return Vector2i(-99999, -99999)
