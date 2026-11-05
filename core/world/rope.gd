## Ropes: a `rope` item anchored at a cell hangs down through open cells as `rope` tiles
## (TileDefs.rope; climbable like a ladder, not solid, not opaque). A rope is a vertical run of
## rope tiles; its top cell is the anchor. Nothing but the tiles is stored, so ropes save with
## the world and reach every client as ordinary tile changes.
##
## Rules (the host applies them: WorldHost.request_place, _advance_dig, _on_tile_changed):
##   - Aim at a cell: if it is solid or one-way (rock, a walkway, a stair), the rope is tied to
##     it and the anchor is the open cell under it; otherwise the anchor is that cell.
##   - The anchor must be air and held: a solid or one-way tile above it, to its left or to its
##     right, or a background wall in the cell; and not directly under another rope.
##   - It unrolls down from the anchor through air until the next cell is not air (a floor,
##     a block, a torch) or it is LENGTH tiles long.
##   - Digging any of its cells, or placing a rope on it, reels the whole rope back: one rope item.
##   - When the anchor is no longer held (its rock dug, its walkway taken), the rope falls: the
##     whole run is removed and one rope item drops where its anchor was.
##
##   var a := Rope.anchor_cell(world, target)
##   if Rope.can_anchor(world, a.x, a.y): world.set_fg(a.x, a.y, Rope.id()); Rope.unroll(world, a)
class_name Rope
extends RefCounted

const NONE := Vector2i(-(1 << 30), -(1 << 30))

static var _id := -1

## Tiles a rope unrolls at most (data/movement.json rope.length).
static func length() -> int:
	return int((MoveStats.data().get("rope", {}) as Dictionary).get("length", 30))

static func id() -> int:
	if _id < 0:
		_id = TileDefs.id("rope")
	return _id

static func is_rope(world: TileWorld, x: int, y: int) -> bool:
	return TileDefs.rope[world.get_fg(x, y)] != 0

## Where a rope aimed at `target` would be anchored: the cell under a solid or one-way tile,
## else the target itself.
static func anchor_cell(world: TileWorld, target: Vector2i) -> Vector2i:
	var id := world.get_fg(target.x, target.y)
	if TileDefs.solid[id] != 0 or TileDefs.platform[id] != 0:
		return target + Vector2i(0, -1)
	return target

## A solid or one-way tile above, left or right of the cell, or a background wall in it.
static func held(world: TileWorld, x: int, y: int) -> bool:
	if world.get_bg(x, y) != 0:
		return true
	for d: Vector2i in [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var id := world.get_fg(x + d.x, y + d.y)
		if TileDefs.solid[id] != 0 or TileDefs.platform[id] != 0:
			return true
	return false

static func can_anchor(world: TileWorld, x: int, y: int) -> bool:
	TileDefs.ensure()
	return world.in_bounds(x, y) and world.get_fg(x, y) == TileDefs.AIR and held(world, x, y) \
		and not is_rope(world, x, y + 1)

## Lay the rope below an anchor already set: down through air, up to `n` tiles in all.
## Returns the cells set (the anchor not included).
static func unroll(world: TileWorld, anchor: Vector2i, n := -1, quiet := false) -> Array[Vector2i]:
	if n < 0:
		n = length()
	var out: Array[Vector2i] = []
	var y := anchor.y - 1
	while out.size() + 1 < n and world.in_bounds(anchor.x, y) and world.get_fg(anchor.x, y) == TileDefs.AIR:
		world.set_fg(anchor.x, y, id(), quiet)
		out.append(Vector2i(anchor.x, y))
		y -= 1
	return out

## The top (anchor) of the rope through `cell`, or NONE if it is not a rope.
static func top_of(world: TileWorld, cell: Vector2i) -> Vector2i:
	if not is_rope(world, cell.x, cell.y):
		return NONE
	var y := cell.y
	while is_rope(world, cell.x, y + 1):
		y += 1
	return Vector2i(cell.x, y)

## Every cell of the rope through `cell`, top first.
static func run_of(world: TileWorld, cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var top := top_of(world, cell)
	if top == NONE:
		return out
	var y := top.y
	while is_rope(world, cell.x, y):
		out.append(Vector2i(cell.x, y))
		y -= 1
	return out

## Remove the whole rope through `cell`. Returns its top, or NONE if there was none.
static func remove(world: TileWorld, cell: Vector2i) -> Vector2i:
	var run := run_of(world, cell)
	if run.is_empty():
		return NONE
	for c in run:
		world.set_fg(c.x, c.y, TileDefs.AIR)
	return run[0]

## Tops of ropes that a change at (x, y) may have left unheld: the rope cell under it, and
## those beside it, if each is a top and no longer held.
static func loose_after(world: TileWorld, x: int, y: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d: Vector2i in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var c := Vector2i(x + d.x, y + d.y)
		if is_rope(world, c.x, c.y) and not is_rope(world, c.x, c.y + 1) and not held(world, c.x, c.y):
			out.append(c)
	return out
