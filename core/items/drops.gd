## Loot on the ground: a flat list of light records the items system owns (not entities).
## Each falls under gravity until it rests on something solid or a platform, merges with an
## identical stack resting next to it, and goes after DESPAWN seconds. The host steps them;
## a client steps its copies with the same step() for the picture and takes the host's word
## on landing (DROP_MOVE). Saved with the world (items system save_world).
##
##   var drops := Drops.new()
##   var d := drops.spawn(item, pos, Vector2(0, 6), tick, from_id)
##   drops.step(world, dt)      # returns ids that landed or woke this step
class_name Drops
extends RefCounted

const GRAVITY := 40.0
const TERMINAL := 20.0
const FRICTION := 8.0
## Seconds a drop stays on the ground.
const DESPAWN := 900.0
## Most drops kept; the oldest go first.
const MAX_DROPS := 1500
## Seconds before anyone may pick a drop up, and before the one who dropped it may.
const PICK_DELAY := 0.4
const OWNER_DELAY := 2.0
## Resting drops this close (tiles) merge when they stack.
const MERGE_DIST := 1.25

## A drop: id, item, pos (tile units, bottom centre), vel, rest, born (s), from (entity id or 0).
class Drop extends RefCounted:
	var id := 0
	var item := {}
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var rest := false
	var born := 0.0
	var from := 0

## id -> Drop, in spawn order.
var list := {}
var next_id := 1
## Host time (s) the list runs on.
var time := 0.0

func spawn(item: Dictionary, pos: Vector2, vel := Vector2.ZERO, from := 0) -> Drop:
	var d := Drop.new()
	d.id = next_id
	next_id += 1
	d.item = item.duplicate(true)
	d.item.erase("bonded")       # a bond does not survive leaving your hands
	d.pos = pos
	d.vel = vel
	d.born = time
	d.from = from
	list[d.id] = d
	return d

func remove(id: int) -> Drop:
	var d: Drop = list.get(id)
	list.erase(id)
	return d

func get_drop(id: int) -> Drop:
	return list.get(id)

## Ids of drops past DESPAWN, or beyond MAX_DROPS (oldest first).
func expired() -> Array:
	var out: Array = []
	for d: Drop in list.values():
		if time - d.born >= DESPAWN:
			out.append(d.id)
	var extra := list.size() - out.size() - MAX_DROPS
	if extra > 0:
		for d: Drop in list.values():
			if extra <= 0:
				break
			if not d.id in out:
				out.append(d.id)
				extra -= 1
	return out

## Step every moving drop; resting ones are checked for support (dug out from under).
## Returns {landed: [id], woke: [id]}.
func step(world: TileWorld, dt: float) -> Dictionary:
	time += dt
	var landed: Array = []
	var woke: Array = []
	for d: Drop in list.values():
		if d.rest:
			if not supported(world, d.pos):
				d.rest = false
				woke.append(d.id)
			continue
		if move(world, d, dt):
			landed.append(d.id)
	return {"landed": landed, "woke": woke}

## One step of one drop. True when it comes to rest.
static func move(world: TileWorld, d: Drop, dt: float) -> bool:
	d.vel.y = maxf(d.vel.y - GRAVITY * dt, -TERMINAL)
	d.vel.x = move_toward(d.vel.x, 0.0, FRICTION * dt)
	var nx := d.pos.x + d.vel.x * dt
	if _blocks(world, floori(nx), floori(d.pos.y + 0.25)):
		d.vel.x = 0.0
	else:
		d.pos.x = nx
	var ny := d.pos.y + d.vel.y * dt
	if d.vel.y <= 0.0:
		# Rows whose top lies between the old and the new feet, highest first.
		var c := floori(d.pos.y + 1e-4) - 1
		while float(c + 1) >= ny - 1e-4 and c >= -1:
			if _floor(world, floori(d.pos.x), c):
				d.pos.y = float(c + 1)
				d.vel = Vector2.ZERO
				d.rest = true
				return true
			c -= 1
		if ny < 0.0:
			d.pos.y = 0.0
			d.vel = Vector2.ZERO
			d.rest = true
			return true
	elif _blocks(world, floori(d.pos.x), floori(ny + 0.5)):
		d.vel.y = 0.0
		ny = d.pos.y
	d.pos.y = ny
	return false

## Is there something under a drop resting at pos?
static func supported(world: TileWorld, pos: Vector2) -> bool:
	return pos.y <= 0.0 or (absf(pos.y - roundf(pos.y)) < 1e-3 and _floor(world, floori(pos.x), roundi(pos.y) - 1))

static func _floor(world: TileWorld, x: int, y: int) -> bool:
	if not world.in_bounds(x, y):
		return y < 0
	var id := world.get_fg(x, y)
	return TileDefs.solid[id] != 0 or TileDefs.platform[id] != 0

static func _blocks(world: TileWorld, x: int, y: int) -> bool:
	return world.in_bounds(x, y) and TileDefs.solid[world.get_fg(x, y)] != 0

## Merge resting drop `id` into a resting identical stack nearby. Returns the id it merged
## into (the drop `id` is then gone), or 0.
func merge(id: int) -> int:
	var d: Drop = list.get(id)
	if d == null or not d.rest:
		return 0
	for o: Drop in list.values():
		if o.id == id or not o.rest or o.pos.distance_to(d.pos) > MERGE_DIST or not Items.same_stack(o.item, d.item):
			continue
		var mx := Items.stack_max(o.item)
		if Items.count(o.item) + Items.count(d.item) > mx:
			continue
		o.item["count"] = Items.count(o.item) + Items.count(d.item)
		o.born = maxf(o.born, d.born)
		list.erase(id)
		return o.id
	return 0

## May entity `who` pick drop d up now?
func pickable(d: Drop, who: int) -> bool:
	var age := time - d.born
	return age >= PICK_DELAY and (who != d.from or age >= OWNER_DELAY)

func to_dict() -> Dictionary:
	var out: Array = []
	for d: Drop in list.values():
		out.append([d.pos.x, d.pos.y, d.item.duplicate(true), time - d.born])
	return {"drops": out}

func load_dict(d: Variant) -> void:
	list.clear()
	if not d is Dictionary:
		return
	for e: Variant in d.get("drops", []):
		if e is Array and (e as Array).size() == 4:
			var rec := Items.clean(e[2])
			if rec.is_empty() or not Items.exists(String(rec["base"])):
				continue
			var dr := spawn(rec, Vector2(float(e[0]), float(e[1])))
			dr.born = time - float(e[3])
