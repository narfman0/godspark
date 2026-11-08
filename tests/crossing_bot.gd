## A walker from the cold end of a world to the hot end, on the surface: the real
## PlayerController on the world's own tiles, driven by the monsters' planner with no digging,
## a leg of LEG columns at a time along the line a player on foot would take (the road where
## there is one, the street through a town, the pass over a range, the crossing of a river,
## the ground elsewhere). One body from end to end, so its time is the time on screen.
## Used by tools/crossing.gd and tests/test_m5_crossing.gd.
##   var r := CrossingBot.walk(world)
##   r = {ok, why, entered: [{biome, name, x, t}], crossed: [{kind, id, name, x0, x1, t, off}],
##        seconds, ticks, digs, tiles_changed, below, trail: [{biome, x, y}], start, end,
##        reached: Array of float (seconds on screen the body first stood in each column; -1 never)}
class_name CrossingBot
extends RefCounted

## Columns a leg asks of the planner: well inside its search window (MonsterNav.WINDOW).
const LEG := 30
## A goal that cannot be planned is moved this far and tried again, up to TRIES times a side.
const NUDGE := 5
const TRIES := 8
## Ticks a leg may take, and legs that may pass with no ground gained.
const LEG_TICKS := 1500
const IDLE_LEGS := 4
## Rows off a crossing's own line a foot on the ground may be and still be on the crossing.
const ON_WAY := 3.0
## Rows under the line a foot may stand and still be on the surface: a dip the planner took.
const MAX_BELOW := 16.0
## How far from the world's edge the walk starts and ends.
const END_MARGIN := 8

## The feet row of the walker's line in each column, west to east.
static func line(world: TileWorld) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(world.width)
	for x in world.width:
		out[x] = _ground(world, x)
	for r: Dictionary in world.meta.get("routes", []):
		if String(r.get("kind", "")) == "road" and _on_top(world, int(r["a"])) and _on_top(world, int(r["b"])):
			for c: Vector2i in Places.route_path(world, int(r["id"])):
				out[c.x] = c.y
	var places := Places.all(world)
	for k: String in places:
		var st: Array = places[k].get("street", [])
		if st.size() == 3 and _on_top(world, int(k)):
			for x in range(int(st[0]), int(st[1]) + 1):
				out[x] = int(st[2])
	for span: Dictionary in spans(world):
		var cells: Dictionary = span["cells"]
		for x: int in cells:
			out[x] = cells[x]
	return out

static func _on_top(world: TileWorld, site_id: int) -> bool:
	return String(Places.site(world, site_id).get("band", "")) in ["surface", "sky"]

## The top of the column seen from the sky: what you stand on with nothing built over it. A
## ladder's head counts, so a shaft is walked past, not gone down.
static func _ground(world: TileWorld, x: int) -> int:
	var y := world.height - 1
	while y > 0:
		var g := world.get_fg(x, y)
		if TileDefs.solid[g] != 0 or TileDefs.platform[g] != 0 or TileDefs.ladder[g] != 0:
			break
		y -= 1
	return y + 1

## Every barrier's way across, west to east: {kind, id, name, x0, x1, cells: {x: feet row}}.
static func spans(world: TileWorld) -> Array:
	var out: Array = []
	var bar: Dictionary = world.meta.get("barriers", {})
	for rg: Dictionary in bar.get("ranges", []):
		out.append(_span("pass", rg, rg["pass"]["path"]))
	for rv: Dictionary in bar.get("rivers", []):
		out.append(_span(String(rv["crossing"]["kind"]), rv, rv["crossing"]["cells"]))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["x0"]) < int(b["x0"]))
	return out

static func _span(kind: String, row: Dictionary, path: Array) -> Dictionary:
	var cells := {}
	var lo := 1 << 30
	var hi := -1
	for q: Array in path:
		cells[int(q[0])] = int(q[1])
		lo = mini(lo, int(q[0]))
		hi = maxi(hi, int(q[0]))
	return {"kind": kind, "id": int(row["id"]), "name": String(row.get("name", "")), "x0": lo, "x1": hi, "cells": cells}

## Walk it. cold-end column to hot-end column, one body, every tick the real controller.
static func walk(world: TileWorld) -> Dictionary:
	var biomes: Array = BiomeIds.strip(world.meta)
	var way := line(world)
	var x0 := int(biomes[0]["x0"]) + END_MARGIN
	var x1 := int(biomes[-1]["x1"]) - END_MARGIN
	var st := NavMaps.stats("medium")
	var prof := MonsterNav.profile(st, 0.0)
	var b := st.make_body()
	b.pos = Vector2(x0 + 0.5, way[x0])
	TileCollision.depenetrate(world, b)
	TileCollision.update_contacts(world, b)
	var hash0 := world.content_hash()
	var r := {"ok": false, "why": "", "entered": [], "crossed": [], "seconds": 0.0, "ticks": 0, "digs": 0, "tiles_changed": false,
		"below": 0.0, "trail": [], "start": x0, "end": x1, "legs": 0, "reached": []}
	(r["reached"] as Array).resize(world.width)
	(r["reached"] as Array).fill(-1.0)
	var todo: Array = []
	for span: Dictionary in spans(world):
		span["off"] = 0.0
		span["t0"] = -1.0
		todo.append(span)
	var w := {"b": biomes, "seg": -1, "way": way, "todo": todo, "r": r, "st": st, "ticks": 0, "last_t": 0.0}
	var f := NavFollow.new()
	var idle := 0
	var best := b.pos.x
	while b.pos.x < x1 - 2.0:
		r["legs"] = int(r["legs"]) + 1
		var path := _plan(world, prof, b, way, mini(floori(b.pos.x) + LEG, x1))
		if path == null:
			r["why"] = "no plan from %s" % b.pos
			break
		f.set_path(path)
		var why := _leg(world, b, f, w)
		if why != "":
			r["why"] = "%s at %s" % [why, b.pos]
			break
		if b.pos.x > best + 1.0:
			best = b.pos.x
			idle = 0
		else:
			idle += 1
			if idle >= IDLE_LEGS:
				r["why"] = "no ground gained from %s" % b.pos
				break
	r["ticks"] = w["ticks"]
	r["seconds"] = float(w["ticks"]) / K.TICK_HZ
	r["digs"] = f.dug
	r["tiles_changed"] = world.content_hash() != hash0
	r["ok"] = r["why"] == ""
	return r

## A plan to the line at column gx, or near it: a goal can sit under a stair or in a doorway.
static func _plan(world: TileWorld, prof: NavProfile, b: Body, way: PackedInt32Array, gx: int) -> NavPath:
	for k in TRIES * 2 + 1:
		var dx: int = -((k + 1) / 2) * NUDGE if k % 2 == 1 else (k / 2) * NUDGE
		var x := clampi(gx + dx, floori(b.pos.x) + 1, world.width - 1)
		var s := MonsterNav.start(world, prof, b.pos, Vector2(x + 0.5, way[x]), Vector2i(1, 1), false)
		while not s.step(100000):
			pass
		var path := s.result()
		if path != null:
			return path
	return null

## One planned leg, tick by tick. "" when it ended with the body on the ground.
static func _leg(world: TileWorld, b: Body, f: NavFollow, w: Dictionary) -> String:
	var dt := 1.0 / K.TICK_HZ
	var steps := maxi(1, MoveStats.step_hz() / K.TICK_HZ)
	var sdt := 1.0 / MoveStats.step_hz()
	var st: MoveStats = w["st"]
	for k in LEG_TICKS:
		var inp := f.input(world, b, dt, 2.0)
		if inp == null:
			if f.failed:
				return f.why
			inp = PlayerInput.new()       # the path is walked: come to rest on something
			if b.on_floor or b.on_stairs:
				return ""
		for i in steps:
			PlayerController.step(world, b, inp, st, sdt)
			inp.jump_pressed = false
		w["ticks"] = int(w["ticks"]) + 1
		_note(b, w)
	return "out of ticks on a leg"

## What the body has reached at the end of this tick.
static func _note(b: Body, w: Dictionary) -> void:
	var r: Dictionary = w["r"]
	var x := floori(b.pos.x)
	var t := float(w["ticks"]) / K.TICK_HZ
	var reached: Array = r["reached"]
	if x >= 0 and x < reached.size() and float(reached[x]) < 0.0:
		reached[x] = t
	var biomes: Array = w["b"]
	var seg := int(w["seg"])
	if seg + 1 < biomes.size() and x >= int(biomes[seg + 1]["x0"]):
		seg += 1
		w["seg"] = seg
		var row: Dictionary = biomes[seg]
		(r["entered"] as Array).append({"biome": row["biome"], "name": String(row.get("name", "")), "x": x, "t": t})
	if seg >= 0 and (r["trail"] as Array).size() == seg and x >= (int(biomes[seg]["x0"]) + int(biomes[seg]["x1"])) / 2 and b.on_floor:
		(r["trail"] as Array).append({"biome": biomes[seg]["biome"], "x": x, "y": floori(b.pos.y)})
	var way: PackedInt32Array = w["way"]
	var grounded := b.on_floor or b.on_stairs
	if grounded:
		var under := way[clampi(x, 0, way.size() - 1)] - b.pos.y
		if under > float(r["below"]):
			r["below"] = under
			r["below_at"] = [x, floori(b.pos.y)]
	var todo: Array = w["todo"]
	if todo.is_empty():
		return
	var span: Dictionary = todo[0]
	if x < int(span["x0"]):
		return
	if float(span["t0"]) < 0.0:
		span["t0"] = t
	var cells: Dictionary = span["cells"]
	if grounded and cells.has(x):
		span["off"] = maxf(float(span["off"]), absf(b.pos.y - int(cells[x])))
	if x > int(span["x1"]):
		(r["crossed"] as Array).append({"kind": span["kind"], "id": span["id"], "name": span["name"], "x0": span["x0"], "x1": span["x1"],
			"t": t, "took": t - float(span["t0"]), "off": span["off"]})
		todo.pop_front()

## What is wrong with a finished walk over this world, as a list. Empty is a real crossing.
static func faults(world: TileWorld, r: Dictionary) -> Array:
	var out: Array = []
	if not r["ok"]:
		out.append("stopped: %s" % r["why"])
	var want: Array = []
	for s: Dictionary in BiomeIds.strip(world.meta):
		want.append(String(s["biome"]))
	var got: Array = (r["entered"] as Array).map(func(e: Dictionary) -> String: return String(e["biome"]))
	if got != want:
		out.append("biomes entered %s, the strip is %s" % [got, want])
	var ways := spans(world)
	if (r["crossed"] as Array).size() != ways.size():
		out.append("crossed %d of %d barriers" % [(r["crossed"] as Array).size(), ways.size()])
	for c: Dictionary in r["crossed"]:
		if float(c["off"]) > ON_WAY:
			out.append("%s %s: %.1f rows off its way" % [c["kind"], c["name"], c["off"]])
	if float(r["below"]) > MAX_BELOW:
		out.append("went %.0f rows under the surface" % r["below"])
	if int(r["digs"]) != 0:
		out.append("%d digs" % r["digs"])
	if r["tiles_changed"]:
		out.append("the world's tiles changed")
	return out
