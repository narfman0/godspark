## Burrowing as a way of moving (an SRD Burrow speed): a burrower digs the cells its body needs to
## stand one column further toward its goal, up or down at most a row a column, then walks into
## them. Only natural tiles give way (data/ecology/brains.json `burrow.natural`, never bedrock,
## water or anything built); the tiles are removed through the world's own tile path
## (TileWorld.set_fg: the host sends them to every client), so a tunnel is real and stays. Each
## dug tile is owed as what a player's dig of it gives (Items.tile_drop: rubble, or the ore),
## dropped in piles behind the burrower. A burrower removes at most `cap_per_min` tiles a minute
## (its row in `burrow.creatures`), so worlds don't dissolve.
##
##   var bw := Burrow.new("purple-worm", stats)
##   var inp := bw.step(host, e, goal, dt)       # null: blocked (built or unbreakable ahead)
class_name Burrow
extends RefCounted

var slug := ""
## Tiles removed in all, and in the current minute.
var dug := 0
var window_n := 0
var window_t := 0.0
## Tiles owed as drops, by item base, and how many.
var owed := {}
var owed_n := 0
## Seconds of digging done on the next cells.
var progress := 0.0
## The last step found built or unbreakable ground ahead.
var blocked := false
var cap := 120
## Hardness-seconds of digging a second.
var rate := 2.0
var pile := 8
## Waited on the cap this many times (tests, reports).
var capped := 0

static func cfg() -> Dictionary:
	return MonsterBrain.cfg().get("burrow", {})

static func row(s: String) -> Dictionary:
	return (cfg().get("creatures", {}) as Dictionary).get(s, {})

static func is_burrower(s: String) -> bool:
	return not row(s).is_empty()

## A natural tile a burrower may dig: solid, breakable, of the natural ranges.
static func natural(id: int) -> bool:
	TileDefs.ensure()
	if id <= 0 or id >= TileDefs.solid.size() or TileDefs.solid[id] == 0 or TileDefs.hardness[id] < 0.0:
		return false
	for r: Variant in cfg().get("natural", []):
		if id >= int(r[0]) and id <= int(r[1]):
			return true
	return false

func _init(s := "", stats: MoveStats = null) -> void:
	slug = s
	var r := row(s)
	cap = int(r.get("cap_per_min", cfg().get("cap_per_min", 120)))
	pile = int(cfg().get("pile", 8))
	var tps := stats.burrow_speed if stats != null else 0.0
	rate = maxf(tps * float(cfg().get("rate_per_tile_s", 1.0)) * float(r.get("rate_mult", 1.0)), float(cfg().get("min_rate", 0.5)))

## Cells (solid now) a body must clear to stand one column on toward dir and dy rows up (1) or
## down (-1): going up, the body's columns and the next one, a row higher (the next column's
## lowest cell stays, the step it climbs); level, the next column's box; going down, the next
## column's box and the row under it (it walks in, then drops once its whole width is over the
## hole).
static func next_cells(world: TileWorld, b: Body, dir: int, dy: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var w := ceili(b.size.x - 1e-3)
	var h := ceili(b.size.y - 1e-3)
	var left := floori(b.pos.x - b.size.x * 0.5 + 1e-3)
	var fy := floori(b.pos.y + 1e-3)
	var x0 := left + dir
	var xa := mini(left, x0) if dy > 0 else x0
	var xb := maxi(left + w - 1, x0 + w - 1) if dy > 0 else x0 + w - 1
	var ya := fy + dy
	var yb := fy + h - 1 + maxi(dy, 0)
	for x in range(xa, xb + 1):
		for y in range(ya, yb + 1):
			if world.is_solid(x, y):
				out.append(Vector2i(x, y))
	return out

## Cells straight above the body up to row `top` (its feet there): a shaft to come up through.
static func shaft_cells(world: TileWorld, b: Body, top: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var w := ceili(b.size.x - 1e-3)
	var h := ceili(b.size.y - 1e-3)
	var left := floori(b.pos.x - b.size.x * 0.5 + 1e-3)
	var fy := floori(b.pos.y + 1e-3)
	for x in range(left, left + w):
		for y in range(fy, top + h):
			if world.is_solid(x, y):
				out.append(Vector2i(x, y))
	return out

## Tiles it may still take this minute.
func room() -> int:
	return maxi(cap - window_n, 0)

func tick(dt: float) -> void:
	window_t += dt
	if window_t >= 60.0:
		window_t = 0.0
		window_n = 0

## One step toward goal: dig what is in the way (taking its time), else walk on. Null when the
## way ahead is not natural ground.
func step(host: WorldHost, e: HostEntity, goal: Vector2, dt: float) -> PlayerInput:
	tick(dt)
	var b := e.body
	var d := goal - b.pos
	var inp := PlayerInput.new()
	var dir := signi(int(signf(d.x))) if absf(d.x) > 0.6 else 0
	var dy := 0
	if d.y > 1.5:
		dy = 1
	elif d.y < -1.5:
		dy = -1
	if dir == 0 and dy == 0:
		progress = 0.0
		return inp
	if dir == 0:
		dir = b.facing if b.facing != 0 else 1
	var cells := next_cells(host.world, b, dir, dy)
	if cells.is_empty():
		progress = 0.0
		blocked = false
		inp.move_x = float(dir)
		if dy > 0 and b.on_floor and b.on_wall:
			inp.jump = true
			inp.jump_pressed = true
		return inp
	if not dig(host, e, cells, dt):
		return null if blocked else _wait(b, dir)
	inp.move_x = float(dir)
	return inp

func _wait(b: Body, dir: int) -> PlayerInput:
	b.facing = dir
	return PlayerInput.new()

## Dig these cells once enough time has gone into them: true when they are gone. False while it
## works (or waits on the cap); `blocked` when one of them will never give.
func dig(host: WorldHost, e: HostEntity, cells: Array[Vector2i], dt: float) -> bool:
	var need := 0.0
	for c in cells:
		var id := host.world.get_fg(c.x, c.y)
		if not natural(id):
			blocked = true
			return false
		need += TileDefs.hardness[id]
	blocked = false
	if cells.size() > room():
		capped += 1
		return false
	progress += dt * rate
	if progress < need:
		return false
	progress = 0.0
	for c in cells:
		var old := host.world.get_fg(c.x, c.y)
		host.world.set_fg(c.x, c.y, TileDefs.AIR)
		var base := Items.tile_drop(old)
		if base != "":
			owed[base] = int(owed.get(base, 0)) + 1
			owed_n += 1
	dug += cells.size()
	window_n += cells.size()
	if owed_n >= pile:
		drop(host, e)
	return true

## What it dug, dropped where it stands (behind it, as it moves on).
func drop(host: WorldHost, e: HostEntity) -> void:
	if owed.is_empty():
		return
	var items: Array = []
	for base: String in WorldSim._sorted_keys(owed):
		items.append(Items.make(base, int(owed[base])))
	owed.clear()
	owed_n = 0
	var sys := host.system(HostSystem.ITEMS)
	if sys != null and sys.has_method("drop"):
		sys.call("drop", e.body.pos + Vector2(-float(e.body.facing) * (e.body.size.x * 0.5 + 0.5), 0.5), items)
