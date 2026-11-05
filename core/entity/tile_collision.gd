## Swept AABB collision of Bodies against the tile grid. No physics server, no nodes.
##
## Each move is axis-separated (x, then y). Along each axis the leading edge sweeps tile
## row by tile row (or column by column) over everything the box's other extent overlaps,
## and stops at the first blocking tile: no tunnelling at any speed, any body size.
## Resting contact is exact: a stopped edge is placed on the tile boundary, so a body
## standing on the ground has an integer `pos.y` and never sinks or jitters.
##
## What blocks:
##   - solid tiles (TileDefs.solid) block from every side; outside the world reads as bedrock
##   - one-way tiles block only a body moving down onto their top: TileDefs.platform tiles
##     and the top rung of a ladder (a ladder tile with no ladder above it). A body ignores
##     them while `climbing`, and ignores those whose top is at or above `drop_y`.
##   - ladders are otherwise not solid.
class_name TileCollision
extends RefCounted

## Contact tolerance in tiles. Positions are Vector2 (float32): at x = 8192 one ulp is
## ~0.001, so this is the floor for worlds up to 16384 wide.
const EPS := 1e-3

## Move `body` by `body.vel * dt`, stopping at blocking tiles. Zeroes the velocity
## component that hit something, then refreshes on_floor / on_wall / on_ceiling.
static func move(world: TileWorld, body: Body, dt: float) -> void:
	var hw := body.size.x * 0.5
	var x: float = body.pos.x
	var y: float = body.pos.y
	var dx: float = body.vel.x * dt
	var dy: float = body.vel.y * dt
	if dx != 0.0:
		var r := _sweep_x(world, x - hw, x + hw, y, y + body.size.y, dx)
		if r[0]:
			body.vel.x = 0.0
			# place the stopped edge exactly on the tile boundary
			x = (r[1] - hw) if dx > 0.0 else (r[1] + hw)
		else:
			x += dx
	if dy != 0.0:
		var r := _sweep_y(world, body, x - hw, x + hw, y, y + body.size.y, dy)
		if r[0]:
			body.vel.y = 0.0
			y = r[1] if dy < 0.0 else (r[1] - body.size.y)
		else:
			y += dy
	body.pos = Vector2(x, y)
	update_contacts(world, body)

## Recompute on_floor, on_ceiling, on_wall and wall_dir from the tiles touching the box
## (within EPS). on_floor needs vel.y <= 0: a body rising past a platform is not on it.
static func update_contacts(world: TileWorld, body: Body) -> void:
	var l := body.left()
	var r := body.right()
	var b: float = body.pos.y
	var t := body.top()
	body.on_floor = body.vel.y <= 0.0 and _touching_floor(world, body, l, r, b)
	body.on_ceiling = false
	var tn := roundi(t)
	if absf(t - tn) <= EPS:
		body.on_ceiling = _row_solid(world, tn, l, r)
	var left_wall := touching_wall(world, body, -1)
	var right_wall := touching_wall(world, body, 1)
	body.on_wall = left_wall or right_wall
	if left_wall and right_wall:
		body.wall_dir = body.facing
	elif left_wall:
		body.wall_dir = -1
	elif right_wall:
		body.wall_dir = 1
	else:
		body.wall_dir = 0

## True if a solid tile touches the body's side `dir` (-1 left, +1 right).
static func touching_wall(world: TileWorld, body: Body, dir: int) -> bool:
	var edge := body.right() if dir > 0 else body.left()
	var n := roundi(edge)
	if absf(edge - n) > EPS:
		return false
	var c := n if dir > 0 else n - 1
	return _col_solid(world, c, body.pos.y, body.top())

## Tile id the body stands on (the first supporting tile, centre column first), or -1 if
## it is not standing on anything. Counts one-way tiles the body is not ignoring.
static func ground_under(world: TileWorld, body: Body) -> int:
	var b: float = body.pos.y
	var n := roundi(b)
	if absf(b - n) > EPS:
		return -1
	var row := n - 1
	var cc := floori(body.pos.x)
	if _floor_blocks(world, body, cc, row):
		return world.get_fg(cc, row)
	for c in range(floori(body.left() + EPS), ceili(body.right() - EPS)):
		if _floor_blocks(world, body, c, row):
			return world.get_fg(c, row)
	return -1

## True if the body stands only on one-way tiles (so down+jump can drop through).
static func on_platform_only(world: TileWorld, body: Body) -> bool:
	var b: float = body.pos.y
	var n := roundi(b)
	if absf(b - n) > EPS:
		return false
	var row := n - 1
	var any := false
	for c in range(floori(body.left() + EPS), ceili(body.right() - EPS)):
		if world.is_solid(c, row):
			return false
		if is_one_way(world, c, row):
			any = true
	return any

## True if any solid tile overlaps `rect` (tile units, y up: position is the bottom-left).
## Touching edges do not count.
static func overlaps_solid(world: TileWorld, rect: Rect2) -> bool:
	for y in range(floori(rect.position.y + EPS), ceili(rect.end.y - EPS)):
		for x in range(floori(rect.position.x + EPS), ceili(rect.end.x - EPS)):
			if world.is_solid(x, y):
				return true
	return false

## A one-way tile: a platform, or a ladder's top rung.
static func is_one_way(world: TileWorld, x: int, y: int) -> bool:
	var id := world.get_fg(x, y)
	if TileDefs.platform[id] != 0:
		return true
	return TileDefs.ladder[id] != 0 and TileDefs.ladder[world.get_fg(x, y + 1)] == 0

static func is_ladder(world: TileWorld, x: int, y: int) -> bool:
	return TileDefs.ladder[world.get_fg(x, y)] != 0

## True if a ladder tile in the body's centre column overlaps its box, or with
## `include_below`, sits directly under its feet (so down on a ladder top grabs it).
static func ladder_at(world: TileWorld, body: Body, include_below := false) -> bool:
	var c := floori(body.pos.x)
	var y0 := floori(body.pos.y + EPS)
	if include_below:
		y0 = floori(body.pos.y + EPS) - 1
	for y in range(y0, ceili(body.top() - EPS)):
		if is_ladder(world, c, y):
			return true
	return false

## 0..1: fraction of the body's height under liquid, measured in its centre column.
## A cell's liquid level L (low 4 bits, 0-15) fills the bottom L/15 of the cell.
static func liquid_fraction(world: TileWorld, body: Body) -> float:
	var c := floori(body.pos.x)
	var b: float = body.pos.y
	var t := body.top()
	var wet := 0.0
	for y in range(floori(b), ceili(t)):
		var level := world.get_liquid(c, y) & 15
		if level == 0:
			continue
		var surface := y + level / 15.0
		wet += maxf(0.0, minf(surface, t) - maxf(float(y), b))
	return clampf(wet / body.size.y, 0.0, 1.0)

## First solid tile on the segment from -> to (tile units), by grid traversal (DDA).
## Returns {hit: bool, tile: Vector2i, id: int, point: Vector2, normal: Vector2i,
## distance: float}. If `from` is inside a solid tile, that tile is the hit at distance 0.
## Only solid tiles block (platforms and ladders don't): use it for line of sight and cover.
static func raycast(world: TileWorld, from: Vector2, to: Vector2) -> Dictionary:
	var cx := floori(from.x)
	var cy := floori(from.y)
	var miss := {"hit": false, "tile": Vector2i(cx, cy), "id": TileDefs.AIR, "point": to,
			"normal": Vector2i.ZERO, "distance": from.distance_to(to)}
	if world.is_solid(cx, cy):
		return {"hit": true, "tile": Vector2i(cx, cy), "id": world.get_fg(cx, cy), "point": from,
				"normal": Vector2i.ZERO, "distance": 0.0}
	var ox: float = from.x
	var oy: float = from.y
	var ddx: float = to.x - ox
	var ddy: float = to.y - oy
	var length := sqrt(ddx * ddx + ddy * ddy)
	if length == 0.0:
		return miss
	var dirx := ddx / length
	var diry := ddy / length
	var step_x := 1 if dirx > 0.0 else -1
	var step_y := 1 if diry > 0.0 else -1
	var t_max_x := INF
	var t_max_y := INF
	var t_dx := INF
	var t_dy := INF
	if dirx != 0.0:
		t_dx = 1.0 / absf(dirx)
		t_max_x = ((cx + 1 - ox) if dirx > 0.0 else (ox - cx)) * t_dx
	if diry != 0.0:
		t_dy = 1.0 / absf(diry)
		t_max_y = ((cy + 1 - oy) if diry > 0.0 else (oy - cy)) * t_dy
	var limit := absi(floori(to.x) - cx) + absi(floori(to.y) - cy) + 2
	for i in limit:
		var t: float
		var normal: Vector2i
		if t_max_x < t_max_y:
			t = t_max_x
			cx += step_x
			t_max_x += t_dx
			normal = Vector2i(-step_x, 0)
		else:
			t = t_max_y
			cy += step_y
			t_max_y += t_dy
			normal = Vector2i(0, -step_y)
		if t > length:
			break
		if world.is_solid(cx, cy):
			return {"hit": true, "tile": Vector2i(cx, cy), "id": world.get_fg(cx, cy),
					"point": Vector2(ox + dirx * t, oy + diry * t), "normal": normal, "distance": t}
	return miss

## Free distance the body could move straight down, up to `max_dist` (>= 0), honouring
## one-way tiles. Used for step-down snapping and by AI to probe ledges.
static func free_below(world: TileWorld, body: Body, max_dist: float) -> float:
	var hw := body.size.x * 0.5
	var r := _sweep_y(world, body, body.pos.x - hw, body.pos.x + hw, body.pos.y, body.top(), -max_dist)
	return (body.pos.y - r[1]) if r[0] else max_dist

# --- internals ---------------------------------------------------------------------

## Sweep the box [l, r] x [b, t] by dx. Returns [blocked, edge]: edge is the tile boundary
## the leading edge stops on when blocked.
static func _sweep_x(world: TileWorld, l: float, r: float, b: float, t: float, dx: float) -> Array:
	if dx > 0.0:
		var c := ceili(r - EPS)
		var target := r + dx
		while c < target:
			if _col_solid(world, c, b, t):
				return [true, float(c)]
			c += 1
	else:
		var c := floori(l + EPS) - 1
		var target := l + dx
		while c + 1 > target:
			if _col_solid(world, c, b, t):
				return [true, float(c + 1)]
			c -= 1
	return [false, 0.0]

static func _sweep_y(world: TileWorld, body: Body, l: float, r: float, b: float, t: float, dy: float) -> Array:
	if dy < 0.0:
		var row := floori(b + EPS) - 1
		var target := b + dy
		while row + 1 > target:
			for c in range(floori(l + EPS), ceili(r - EPS)):
				if _floor_blocks(world, body, c, row):
					return [true, float(row + 1)]
			row -= 1
	else:
		var row := ceili(t - EPS)
		var target := t + dy
		while row < target:
			if _row_solid(world, row, l, r):
				return [true, float(row)]
			row += 1
	return [false, 0.0]

static func _col_solid(world: TileWorld, c: int, b: float, t: float) -> bool:
	for y in range(floori(b + EPS), ceili(t - EPS)):
		if world.is_solid(c, y):
			return true
	return false

static func _row_solid(world: TileWorld, row: int, l: float, r: float) -> bool:
	for c in range(floori(l + EPS), ceili(r - EPS)):
		if world.is_solid(c, row):
			return true
	return false

## Does tile (c, row) hold up a body coming down onto it from above?
static func _floor_blocks(world: TileWorld, body: Body, c: int, row: int) -> bool:
	var id := world.get_fg(c, row)
	if TileDefs.solid[id] != 0:
		return true
	if body == null or body.climbing or row + 1 >= body.drop_y:
		return false
	return is_one_way(world, c, row)

static func _touching_floor(world: TileWorld, body: Body, l: float, r: float, b: float) -> bool:
	var n := roundi(b)
	if absf(b - n) > EPS:
		return false
	for c in range(floori(l + EPS), ceili(r - EPS)):
		if _floor_blocks(world, body, c, n - 1):
			return true
	return false
