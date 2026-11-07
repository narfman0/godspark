## One resumable A* search on tiles (see MonsterNav). Call step(n) until it returns true,
## then result(). Everything it reads from the world is cached for the search's lifetime, so
## a search spread over several ticks sees the tiles as they were when it read them; the
## follower and the replan timer deal with what changed since.
class_name NavSearch
extends RefCounted

const E := MonsterNav.Edge
const SOLID := MonsterNav.SOLID
const ONEWAY := MonsterNav.ONEWAY
const LADDER := MonsterNav.LADDER
const WET := MonsterNav.WET
const HAZARD := MonsterNav.HAZARD
const UNKNOWN := MonsterNav.UNKNOWN
const MARGIN := 24
## Tiles of a jump's landing box that must lie over floor (a sliver over a ledge's corner is
## not a landing a body makes reliably).
const MIN_SUPPORT := 0.5
## Rows a jump's arc must rise above its landing (a landing at the very top of the arc is
## missed by a hair's difference in take-off).
const MIN_CLEARANCE := 0.6

var world: TileWorld
var prof: NavProfile
var start: Vector2i
var goal: Vector2i
var tol := Vector2i(1, 1)
var partial := true
var max_expand := 6000
## Longest drop (rows) the search may plan, off a ledge or through a one-way floor. Life's
## people use MonsterNav.SAFE_FALL: they never plan a fall that would hurt them.
var max_drop := MonsterNav.MAX_FALL
var expanded := 0
var done := false
## Microseconds spent in step() so far.
var usec := 0

var x0 := 0
var y0 := 0
var W := 0
var H := 0
var fx0 := 0
var fy0 := 0
var FW := 0
var FH := 0
var _flags := PackedByteArray()
var _clear := PackedByteArray()      # 0 unknown, 1 clear, 2 blocked, 3 clear once dug
var _stand := PackedByteArray()      # 0 unknown, 1 yes, 2 no
var _g := PackedFloat32Array()
var _came := PackedInt32Array()
var _how := PackedInt32Array()       # edge | extra << 4
var _closed := PackedByteArray()
var _hk := PackedInt32Array()
var _hf := PackedFloat32Array()
var _found := -1
var _best := -1
var _best_h := INF
var _dig_mask := 0
var _inv_speed := 1.0

func setup(w: TileWorld, p: NavProfile, s: Vector2i, gl: Vector2i, t: Vector2i, part: bool, cap: int,
		radius := Vector2i(-1, -1)) -> void:
	world = w
	prof = p
	start = s
	goal = gl
	tol = t
	partial = part
	max_expand = cap
	var r := Vector2i(MonsterNav.WINDOW, MonsterNav.WINDOW) if radius.x < 0 else radius
	x0 = s.x - r.x
	y0 = s.y - r.y
	W = 2 * r.x + 1
	H = 2 * r.y + 1
	fx0 = x0 - MARGIN
	fy0 = y0 - MARGIN
	FW = W + 2 * MARGIN
	FH = H + 2 * MARGIN
	_flags.resize(FW * FH)
	_flags.fill(UNKNOWN)
	_clear.resize(W * H)
	_stand.resize(W * H)
	_g.resize(W * H)
	_g.fill(INF)
	_came.resize(W * H)
	_how.resize(W * H)
	_closed.resize(W * H)
	if p.dig > 0.0:
		_dig_mask = MonsterNav.SOFT if p.dig <= MonsterNav.SOFT_HARDNESS else MonsterNav.ROCK
	_inv_speed = 1.0 / maxf(p.max_speed, 0.5)
	var k := _key(s.x, s.y)
	if k < 0 or not _valid(s.x, s.y):
		# Starting inside something (dug in, pushed): try the nodes around it.
		for o: Vector2i in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1)]:
			if _valid(s.x + o.x, s.y + o.y):
				start = s + o
				k = _key(start.x, start.y)
				break
	if k < 0 or not _valid(start.x, start.y):
		done = true
		return
	_g[k] = 0.0
	_came[k] = -1
	_how[k] = -1
	_push(k, _h(start.x, start.y))

## Expand up to n nodes, or until budget_us microseconds have passed (0: no limit). True when
## finished (found, exhausted or over the expansion cap).
func step(n: int, budget_us := 0) -> bool:
	if done:
		return true
	var t0 := Time.get_ticks_usec()
	var i := 0
	while i < n and not _hk.is_empty():
		if budget_us > 0 and i > 0 and Time.get_ticks_usec() - t0 >= budget_us:
			break
		var k := _pop()
		if _closed[k] != 0:
			continue
		_closed[k] = 1
		i += 1
		expanded += 1
		var L := x0 + k % W
		var y := y0 + k / W
		var hh := _h(L, y)
		if hh < _best_h:
			_best_h = hh
			_best = k
		if absi(L - goal.x) <= tol.x and absi(y - goal.y) <= tol.y:
			_found = k
			done = true
			break
		_expand(k, L, y)
		if expanded >= max_expand:
			done = true
			break
	if _hk.is_empty():
		done = true
	usec += Time.get_ticks_usec() - t0
	return done

## The path found (or, with partial, the one to the reachable node nearest the goal); null
## when there is none.
func result() -> NavPath:
	var end := _found
	if end < 0:
		if not partial or _best < 0 or _best == _key(start.x, start.y):
			return null
		end = _best
	var nodes: Array[Vector2i] = []
	var how := PackedInt32Array()
	var k := end
	while k >= 0:
		nodes.append(Vector2i(x0 + k % W, y0 + k / W))
		how.append(_how[k])
		k = _came[k]
	nodes.reverse()
	how.reverse()
	var p := NavPath.new()
	p.prof = prof
	p.nodes = nodes
	p.how = how
	p.reached = _found >= 0
	p.goal = goal
	p.cost = _g[end]
	return p

## The path from the start to node n if the search reached it (a flood: search toward an
## unreachable goal with partial off and a large cap, then ask for any node), else null.
func path_to(n: Vector2i) -> NavPath:
	var k := _key(n.x, n.y)
	if k < 0 or _g[k] == INF:
		return null
	var nodes: Array[Vector2i] = []
	var how := PackedInt32Array()
	while k >= 0:
		nodes.append(Vector2i(x0 + k % W, y0 + k / W))
		how.append(_how[k])
		k = _came[k]
	nodes.reverse()
	how.reverse()
	var p := NavPath.new()
	p.prof = prof
	p.nodes = nodes
	p.how = how
	p.reached = true
	p.goal = n
	p.cost = _g[_key(n.x, n.y)]
	return p

## The highest node reached (for tools: where a flood up out of a pit stops).
func highest() -> Vector2i:
	var best := Vector2i(0, -(1 << 30))
	for k in _g.size():
		if _g[k] != INF and y0 + k / W > best.y:
			best = Vector2i(x0 + k % W, y0 + k / W)
	return best

## Nodes reached so far (g known), for floods.
func reached_count() -> int:
	var n := 0
	for g in _g:
		if g != INF:
			n += 1
	return n

func reached() -> bool:
	return _found >= 0

# --- the graph ----------------------------------------------------------------------------------

func _expand(k: int, L: int, y: int) -> void:
	var g0 := _g[k]
	var st := _stand_at(L, y)
	var wet := prof.walker and _wet(L, y)
	if prof.fly or wet:
		var mode := E.FLY if prof.fly else E.SWIM
		var unit := 1.0 / maxf(prof.stats.fly_speed if prof.fly else prof.swim_speed, 0.5)
		for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
				Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
			var nl := L + o.x
			var ny := y + o.y
			if _clear_at(nl, ny) != 1:
				continue
			if o.x != 0 and o.y != 0 and (_clear_at(L + o.x, y) != 1 or _clear_at(L, y + o.y) != 1):
				continue
			if mode == E.SWIM and not (_wet(nl, ny) or _stand_at(nl, ny) or (o.y > 0 and prof.fly)):
				continue
			_relax(k, nl, ny, g0 + unit * (1.4142 if o.x != 0 and o.y != 0 else 1.0), mode, 0)
	if not prof.walker:
		return
	var ld := _ladder(L, y)
	var side := _cling(L, y) if prof.climb else 0
	if st or ld or wet:
		for dir: int in [1, -1]:
			_ground(k, g0, L, y, dir, st)
	if st:
		_platform_drop(k, g0, L, y)
		_stairs_up(k, g0, L, y)
		if _jump_worthy(L, y):
			_jumps(k, g0, L, y)
	# ladders: in the box's centre column, or the top rung under the feet
	var cc := floori(L + prof.cw * 0.5)
	var lu := 1.0 / maxf(prof.stats.ladder_speed, 0.5)
	if ld:
		if _ladder(L, y + 1) or (_clear_at(L, y + 1) == 1 and _stand_at(L, y + 1)):
			_relax(k, L, y + 1, g0 + lu, E.LADDER, 0)
	# down: not through a walkway or tread in the centre column (it holds a climber up)
	var under := _cf(cc, y - 1)
	if (ld or (st and under & LADDER)) and not (under & ONEWAY and not (under & LADDER)):
		if _ladder(L, y - 1):
			_relax(k, L, y - 1, g0 + lu, E.LADDER, 0)
		elif ld and _stand_at(L, y - 1):
			_relax(k, L, y - 1, g0 + lu, E.LADDER, 0)
	# walls (climbers)
	if prof.climb and (side != 0 or st):
		var cu := 1.0 / maxf(prof.stats.climb_speed, 0.5)
		for dy: int in [1, -1]:
			var ny := y + dy
			if side == 0:
				break           # up or down a wall needs a wall beside the box
			if _clear_at(L, ny) == 1 and (_cling(L, ny) != 0 or _stand_at(L, ny)):
				_relax(k, L, ny, g0 + cu, E.CLING, 0)
		if side != 0:
			for up in range(0, 3):
				var nl := L + side
				if _clear_at(nl, y + up) == 1 and _stand_at(nl, y + up) and _clear_at(L, y + up) == 1:
					_relax(k, nl, y + up, g0 + cu * (up + 1), E.CLING, (side + 1) | (up << 2))
					break
			if not st:
				_fall(k, g0, L, y, L)

func _ground(k: int, g0: float, L: int, y: int, dir: int, st: bool) -> void:
	var nl := L + dir
	var unit := 1.0 / prof.run
	var c := _clear_at(nl, y)
	if c != 2 and _stand_at(nl, y):
		if st and _treads_only(L, y):
			# on a staircase the controller keeps to the treads: a tread at the feet's row in
			# the column the leading edge enters lifts it (the STAIRS edge), one a row down
			# brings it down; it does not walk on level there
			var lead := _lead(nl, dir)
			if _cf(lead, y) & MonsterNav.STAIR:
				return
			if (_cf(lead, y - 2) & MonsterNav.STAIR) and not (_cf(lead, y - 1) & SOLID):
				if _clear_at(nl, y - 1) == 1 and _stand_at(nl, y - 1):
					_relax(k, nl, y - 1, g0 + unit, E.WALK, 0)
				return
		_relax(k, nl, y, g0 + unit + _dig_cost(nl, y, c), E.WALK, 0)
		return
	if c == 2 or c == 3:
		if not st:
			return
		for up in range(1, prof.step + 1):
			var a := _clear_at(L, y + up)
			var b := _clear_at(nl, y + up)
			if a != 2 and b != 2 and _stand_at(nl, y + up):
				_relax(k, nl, y + up, g0 + unit * 1.5 + _dig_cost(L, y + up, a) + _dig_cost(nl, y + up, b), E.WALK, 0)
				return
		return
	if st:
		_fall(k, g0, L, y, nl)

## Walk off (or let go) at column nl and fall to the first floor or water below.
func _fall(k: int, g0: float, L: int, y: int, nl: int) -> void:
	for d in range(1, max_drop + 1):
		var c := _clear_at(nl, y - d)
		if c != 1:
			return
		if _stand_at(nl, y - d) or _wet(nl, y - d):
			var t := sqrt(2.0 * d / maxf(prof.stats.gravity * prof.stats.fall_gravity_mult, 1.0)) + 1.0 / prof.run
			if d > MonsterNav.SAFE_FALL:
				t += (d - MonsterNav.SAFE_FALL) * 0.35
			_relax(k, nl, y - d, g0 + t, E.DROP, 0)
			return

func _platform_drop(k: int, g0: float, L: int, y: int) -> void:
	var any := false
	for c in range(L, L + prof.cw):
		var f := _cf(c, y - 1)
		if f & SOLID:
			return
		if f & ONEWAY:
			any = true
	if not any:
		return
	for d in range(1, max_drop + 1):
		if _clear_at(L, y - d) != 1:
			return
		# the controller ignores one-way tops only down to the row it dropped through: the
		# first floor below (one row down too) holds it
		if _stand_at(L, y - d):
			_relax(k, L, y - d, g0 + 0.15 + sqrt(2.0 * d / maxf(prof.stats.gravity, 1.0)), E.PLATFORM, 0)
			return

## Up a staircase: a tread at the feet's row in the next node's columns lifts the body one
## row (PlayerController._stairs), if both columns have the headroom.
func _stairs_up(k: int, g0: float, L: int, y: int) -> void:
	for dir: int in [1, -1]:
		var nl := L + dir
		# the controller lifts only for a tread in the column its leading edge enters
		var any := (_cf(_lead(nl, dir), y) & MonsterNav.STAIR) != 0
		if any and _clear_at(nl, y + 1) == 1 and _clear_at(L, y + 1) == 1 and _stand_at(nl, y + 1):
			_relax(k, nl, y + 1, g0 + 1.2 / prof.run, E.STAIRS, 0)

## The column a body's leading edge is in at node nl, moving in dir (the column the
## controller's stairs rule looks at).
func _lead(nl: int, dir: int) -> int:
	if dir > 0:
		return floori(nl + prof.cw * 0.5 + prof.w * 0.5 - 0.01)
	return floori(nl + prof.cw * 0.5 - prof.w * 0.5 + 0.01)

## Standing on stair treads and nothing else (so on a staircase).
func _treads_only(L: int, y: int) -> bool:
	var any := false
	for c in range(L, L + prof.cw):
		var f := _cf(c, y - 1)
		if f & SOLID or (f & ONEWAY and not (f & MonsterNav.STAIR)):
			return false
		if f & MonsterNav.STAIR:
			any = true
	return any

func _tread_under(L: int, y: int) -> bool:
	for c in range(L, L + prof.cw):
		if _cf(c, y - 1) & MonsterNav.STAIR:
			return true
	return false

## Jumps are tried where walking does not simply continue (a ledge, a wall, a gap) or where
## something to stand on hangs within jumping height.
func _jump_worthy(L: int, y: int) -> bool:
	for dir: int in [1, -1]:
		var nl := L + dir
		if _clear_at(nl, y) != 1 or not _stand_at(nl, y):
			return true
	for c in range(L - 3, L + prof.cw + 3):
		for r in range(y + prof.ch, y + 7):
			var f := _cf(c, r)
			if f & (SOLID | ONEWAY) and not (_cf(c, r + 1) & SOLID):
				return true
	return false

func _jumps(k: int, g0: float, L: int, y: int) -> void:
	var js: Array = prof.jumps
	var jdl := prof.jdl
	var jdy := prof.jdy
	for i in jdl.size():
		var tl := L + jdl[i]
		var ty := y + jdy[i]
		var tk := _key(tl, ty)
		if tk < 0 or _closed[tk] != 0:
			continue
		if _stand[tk] == 2 or _clear[tk] == 2 or _clear_at(tl, ty) != 1 or not _stand_at(tl, ty):
			continue
		var j: Dictionary = js[i]
		if float(j["peak"]) - jdy[i] < MIN_CLEARANCE:
			continue
		var ov: PackedFloat32Array = j["ov"]
		var held := 0.0
		for c in prof.cw:
			if _cf(tl + c, ty - 1) & (SOLID | ONEWAY):
				held += ov[c]
		if held < MIN_SUPPORT:
			continue
		var ok := true
		for o: int in j["asc"]:
			if _cf(L + (o & 1023) - 512, y + ((o >> 10) & 1023) - 512) & (SOLID | HAZARD):
				ok = false
				break
		if not ok:
			continue
		for o: int in j["desc"]:
			if _cf(L + (o & 1023) - 512, y + ((o >> 10) & 1023) - 512) & (SOLID | ONEWAY | HAZARD):
				ok = false
				break
		if ok:
			_relax(k, tl, ty, g0 + float(j["t"]) + 0.1, E.JUMP, i)

# --- node tests ---------------------------------------------------------------------------------

func _valid(L: int, y: int) -> bool:
	if _clear_at(L, y) != 1:
		return false
	if prof.fly or _stand_at(L, y) or _ladder(L, y) or _wet(L, y):
		return true
	return prof.climb and _cling(L, y) != 0

## 1 clear, 2 blocked, 3 clear once its solid cells are dug.
func _clear_at(L: int, y: int) -> int:
	var k := _key(L, y)
	if k >= 0 and _clear[k] != 0:
		return _clear[k]
	var v := 1
	for r in range(y, y + prof.ch):
		for c in range(L, L + prof.cw):
			var f := _cf(c, r)
			if f & HAZARD:
				v = 2
				break
			if f & SOLID:
				if _dig_mask != 0 and f & _dig_mask:
					v = 3
				else:
					v = 2
					break
		if v == 2:
			break
	if v != 2 and not prof.swimmer and not prof.fly and _wet(L, y):
		v = 2           # no swim speed: deep water is a wall
	if k >= 0:
		_clear[k] = v
	return v

func _stand_at(L: int, y: int) -> bool:
	var k := _key(L, y)
	if k >= 0 and _stand[k] != 0:
		return _stand[k] == 1
	var v := false
	if _clear_at(L, y) != 2:
		for c in range(L, L + prof.cw):
			if _cf(c, y - 1) & (SOLID | ONEWAY):
				v = true
				break
	if k >= 0:
		_stand[k] = 1 if v else 2
	return v

func _ladder(L: int, y: int) -> bool:
	if _clear_at(L, y) != 1:
		return false
	var cc := floori(L + prof.cw * 0.5)
	for r in range(y, y + prof.ch):
		if _cf(cc, r) & LADDER:
			return true
	return false

func _wet(L: int, y: int) -> bool:
	var cc := floori(L + prof.cw * 0.5)
	for r in range(y, y + maxi(1, (prof.ch + 1) / 2)):
		if not (_cf(cc, r) & WET):
			return false
	return true

## -1 / +1: a wall touches that side of the box; 0 none.
func _cling(L: int, y: int) -> int:
	for r in range(y, y + prof.ch):
		if _cf(L - 1, r) & SOLID:
			return -1
		if _cf(L + prof.cw, r) & SOLID:
			return 1
	return 0

func _dig_cost(L: int, y: int, c: int) -> float:
	if c != 3:
		return 0.0
	var n := 0
	for r in range(y, y + prof.ch):
		for cx in range(L, L + prof.cw):
			if _cf(cx, r) & SOLID:
				n += 1
	return n * 0.6

func _cf(x: int, y: int) -> int:
	var lx := x - fx0
	var ly := y - fy0
	if lx < 0 or ly < 0 or lx >= FW or ly >= FH:
		return MonsterNav.cell_flags(world, x, y)
	var i := lx + ly * FW
	var v := _flags[i]
	if v == UNKNOWN:
		v = MonsterNav.cell_flags(world, x, y)
		_flags[i] = v
	return v

func _key(L: int, y: int) -> int:
	var lx := L - x0
	var ly := y - y0
	if lx < 0 or ly < 0 or lx >= W or ly >= H:
		return -1
	return lx + ly * W

func _h(L: int, y: int) -> float:
	var dx := float(L - goal.x)
	var dy := float(y - goal.y)
	return sqrt(dx * dx + dy * dy) * _inv_speed

func _relax(from: int, L: int, y: int, g: float, edge: int, extra: int) -> void:
	var k := _key(L, y)
	if k < 0 or _closed[k] != 0 or g >= _g[k]:
		return
	_g[k] = g
	_came[k] = from
	_how[k] = edge | (extra << 4)
	_push(k, g + _h(L, y))

# --- binary heap ---------------------------------------------------------------------------------

func _push(k: int, f: float) -> void:
	_hk.append(k)
	_hf.append(f)
	var i := _hk.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if _hf[p] <= f:
			break
		_hk[i] = _hk[p]
		_hf[i] = _hf[p]
		i = p
	_hk[i] = k
	_hf[i] = f

func _pop() -> int:
	var top := _hk[0]
	var n := _hk.size() - 1
	var lk := _hk[n]
	var lf := _hf[n]
	_hk.resize(n)
	_hf.resize(n)
	if n == 0:
		return top
	var i := 0
	while true:
		var c := 2 * i + 1
		if c >= n:
			break
		if c + 1 < n and _hf[c + 1] < _hf[c]:
			c += 1
		if _hf[c] >= lf:
			break
		_hk[i] = _hk[c]
		_hf[i] = _hf[c]
		i = c
	_hk[i] = lk
	_hf[i] = lf
	return top
