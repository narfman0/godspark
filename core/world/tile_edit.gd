## Rules for digging and placing tiles. These only decide; applying an edit is
## `world.set_fg(x, y, id)` by whoever owns the world (the host).
##
##   if TileEdit.can_dig(world, body, x, y): progress.update(Vector2i(x, y), world.get_fg(x, y), dt)
class_name TileEdit
extends RefCounted

## How far a body can dig or build: the gap between its box and the tile's cell, in tiles.
## 4 tiles = 10 ft beyond the edge of the body, so a Medium body (1.5 x 2.5) reaches tiles
## centred about 5 tiles from its middle: two rows under its feet and above its head, and a
## ledge two body-widths away. That is Terraria's feel (about 5 tiles from the player)
## rather than SRD melee reach (5 ft = 2 tiles), which would make building fiddly. Measured
## from the box, so larger creatures reach further.
const REACH := 4.0

## True if the tile is within reach of the body.
static func in_reach(body: Body, x: int, y: int) -> bool:
	var r := body.rect()
	var gx := maxf(0.0, maxf(r.position.x - (x + 1), x - r.end.x))
	var gy := maxf(0.0, maxf(r.position.y - (y + 1), y - r.end.y))
	return gx * gx + gy * gy <= REACH * REACH + 1e-6

## In reach, inside the world, not air, and breakable (hardness >= 0).
static func can_dig(world: TileWorld, body: Body, x: int, y: int) -> bool:
	if not world.in_bounds(x, y) or not in_reach(body, x, y):
		return false
	var id := world.get_fg(x, y)
	return id != TileDefs.AIR and TileDefs.hardness[id] >= 0.0

## Seconds to dig a tile with a tool of `tool_power` (1 = bare hands; 2 digs twice as fast).
## INF for unbreakable tiles and air.
static func dig_time(tile_id: int, tool_power := 1.0) -> float:
	TileDefs.ensure()
	if tile_id == TileDefs.AIR or tile_id < 0 or tile_id >= TileDefs.hardness.size():
		return INF
	var h := TileDefs.hardness[tile_id]
	if h < 0.0 or tool_power <= 0.0:
		return INF
	return h / tool_power

## In reach, inside the world, the cell's foreground is air, it touches something to build
## on (a non-air foreground tile in one of the 4 neighbours, or a background wall in the
## cell), and, if the new tile is solid, no body in `bodies` (Array of Body) overlaps the
## cell. Non-solid tiles (platforms, ladders, torches) may go where bodies stand.
static func can_place(world: TileWorld, body: Body, x: int, y: int, tile_id: int, bodies: Array) -> bool:
	TileDefs.ensure()
	if tile_id <= TileDefs.AIR or tile_id >= TileDefs.solid.size():
		return false
	if not world.in_bounds(x, y) or not in_reach(body, x, y):
		return false
	if world.get_fg(x, y) != TileDefs.AIR:
		return false
	var anchored := world.get_bg(x, y) != 0
	if not anchored:
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if world.get_fg(x + d.x, y + d.y) != TileDefs.AIR:
				anchored = true
				break
	if not anchored:
		return false
	if TileDefs.solid[tile_id] != 0:
		var cell := Rect2(x, y, 1, 1)
		for other: Body in bodies:
			var r := other.rect().grow(-TileCollision.EPS)
			if r.intersects(cell):
				return false
	return true

## A held dig: accumulates time on one tile, starts over when the target or its tile changes.
##   var dig := TileEdit.DigProgress.new()
##   if dig.update(target, world.get_fg(target.x, target.y), dt): world.set_fg(target.x, target.y, 0)
class DigProgress extends RefCounted:
	var target := Vector2i(-1 << 30, -1 << 30)
	var tile_id := -1
	var elapsed := 0.0
	var needed := INF

	## Add dt of digging at `at` (whose current tile is `id`). True on the step it completes;
	## the progress then resets so the next update starts a fresh dig.
	func update(at: Vector2i, id: int, dt: float, tool_power := 1.0) -> bool:
		if at != target or id != tile_id:
			target = at
			tile_id = id
			elapsed = 0.0
			needed = TileEdit.dig_time(id, tool_power)
		elapsed += dt
		if elapsed + 1e-9 >= needed:
			reset()
			return true
		return false

	## 0..1 for a crack overlay.
	func fraction() -> float:
		if needed == INF or needed <= 0.0:
			return 0.0
		return clampf(elapsed / needed, 0.0, 1.0)

	func reset() -> void:
		target = Vector2i(-1 << 30, -1 << 30)
		tile_id = -1
		elapsed = 0.0
		needed = INF
