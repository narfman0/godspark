## Mountain ranges and rivers (stage_barriers.gd): every range has a pass and an under-route,
## every river a walkable crossing, the real controller walks them both ways, roads run on
## them, and a route over a barrier costs more than a flat one.
extends RefCounted

const Barriers := preload("res://core/world/worldgen/stage_barriers.gd")
const SP := preload("res://core/world/worldgen/stage_passages.gd")
const TestRoads := preload("test_roads.gd")
const SEEDS := [1, 2, 3, 4]

func run(t: TestLog) -> void:
	for sd: int in SEEDS:
		var world := WorldGen.generate_named("dev", sd)
		var label := "dev seed %d" % sd
		var bar: Dictionary = world.meta["barriers"]
		t.check((bar["ranges"] as Array).size() >= 1, "%s has a range" % label)
		t.check((bar["rivers"] as Array).size() >= 1, "%s has a river" % label)
		for fail: String in check_world(world):
			t.check(false, "%s: %s" % [label, fail])
		_roads(t, world, label)
		_cost(t, world, label)
		t.check(true, "%s checked" % label)
	var a := WorldGen.generate_named("dev", 5)
	var b := WorldGen.generate_named("dev", 5)
	t.eq(a.content_hash(), b.content_hash(), "barriers are a pure function of the seed")
	t.eq(JSON.stringify(a.meta["barriers"]), JSON.stringify(b.meta["barriers"]), "and so is meta.barriers")
	var off := WorldGen.generate(1024, 512, 5)
	t.eq((off.meta["barriers"]["ranges"] as Array).size() + (off.meta["barriers"]["rivers"] as Array).size(), 0, "a world under min_world has neither")
	var only := WorldGen.generate_named("dev", 2, {"only_biome": "meadow"})
	t.eq((only.meta["barriers"]["rivers"] as Array).size(), 0, "nor has a one-biome scenario world")
	_river_is_built(t)

## Everything a world's barriers must be, as a list of what is wrong (tools/passability_sweep.gd
## runs it on bigger worlds).
static func check_world(world: TileWorld) -> Array:
	var out: Array = []
	var bar: Dictionary = world.meta["barriers"]
	var st := NavMaps.stats("medium")
	for rg: Dictionary in bar["ranges"]:
		var name := "range %d" % rg["id"]
		var way: Array = _cells(rg["pass"]["path"])
		_way(world, st, way, "%s pass" % name, out)
		var under: Array = _cells(rg["under"]["path"])
		_way(world, st, under, "%s under-route" % name, out)
		if under.is_empty() or under[0].x >= int(rg["x0"]) or under[-1].x <= int(rg["x1"]):
			out.append("%s: the under-route does not run from one side to the other" % name)
			continue
		var low := 1 << 30
		for x in range(int(rg["x0"]), int(rg["x1"]) + 1):
			low = mini(low, way[x - int(rg["x0"])].y)
		for p: Vector2i in under:
			if p.x >= int(rg["x0"]) and p.x <= int(rg["x1"]) and p.y >= low - 4:
				out.append("%s: the under-route comes up to the pass at %s" % [name, p])
				break
		# a walker cannot just go over: somewhere a wall stands up out of its reach
		var surf: Array = world.meta["surface"]
		var cliff := 0
		for x in range(int(rg["x0"]) + 1, int(rg["x1"]) + 1):
			cliff = maxi(cliff, absi(int(surf[x]) - int(surf[x - 1])))
		if cliff < 8:
			out.append("%s: no cliff (highest step %d)" % [name, cliff])
		if int(rg["peak"]) <= int(rg["pass"]["top"][1]):
			out.append("%s: the walls stand no higher than the pass" % name)
	var water := TileDefs.id("water")
	for rv: Dictionary in bar["rivers"]:
		var name := "river %d (%s)" % [rv["id"], rv["kind"]]
		_way(world, st, _cells(rv["crossing"]["cells"]), name, out)
		var deepest := 0
		for x in range(int(rv["x0"]), int(rv["x1"]) + 1):
			var n := 0
			for y in range(int(rv["bed"]), int(rv["bank"]) + 1):
				if world.get_fg(x, y) == water:
					n += 1
			deepest = maxi(deepest, n)
		if deepest < 1:
			out.append("%s has no water" % name)
		if rv["kind"] == "ford" and deepest > 1:
			out.append("%s: %d rows deep, a ford is one" % [name, deepest])
		if rv["kind"] == "bridge":
			var deck := TileDefs.id("bridge")
			for x in range(int(rv["x0"]) + 1, int(rv["x1"])):
				var g := world.get_fg(x, int(rv["bank"]))
				if g != deck and not TileDefs.solid[g]:
					out.append("%s: a gap in the deck at %d" % [name, x])
					break
	return out

## A way: a cell a column, a row at most between neighbours, room for a body, and the real
## controller walks it both ways.
static func _way(world: TileWorld, st: MoveStats, path: Array, name: String, out: Array) -> void:
	if path.size() < 2:
		out.append("%s: no path" % name)
		return
	for i in range(1, path.size()):
		if absi(path[i].x - path[i - 1].x) != 1 or absi(path[i].y - path[i - 1].y) > 1:
			out.append("%s: a step from %s to %s" % [name, path[i - 1], path[i]])
			return
	for p: Vector2i in path:
		for k in 3:
			if world.is_solid(p.x, p.y + k):
				out.append("%s: rock in the way at %s" % [name, p])
				return
	if not TestRoads._follow(world, st, path):
		out.append("%s: a walker does not get from %s to %s" % [name, path[0], path[-1]])
	var back := path.duplicate()
	back.reverse()
	if not TestRoads._follow(world, st, back):
		out.append("%s: a walker does not get back from %s to %s" % [name, path[-1], path[0]])

static func _cells(path: Array) -> Array:
	var out: Array = []
	for q: Array in path:
		out.append(Vector2i(int(q[0]), int(q[1])))
	return out

## Roads between towns on opposite sides of a barrier run on its crossing.
func _roads(t: TestLog, world: TileWorld, label: String) -> void:
	var bar: Dictionary = world.meta["barriers"]
	var over := 0
	for r: Dictionary in world.meta["routes"]:
		if r["kind"] != "road":
			continue
		var cells := {}
		for p: Vector2i in Places.route_path(world, int(r["id"])):
			cells[p] = true
		var keys: Array = cells.keys()
		if keys.is_empty():
			continue
		var lo: int = keys[0].x
		var hi: int = keys[0].x
		for p: Vector2i in keys:
			lo = mini(lo, p.x)
			hi = maxi(hi, p.x)
		for rg: Dictionary in bar["ranges"]:
			if lo < int(rg["x0"]) and hi > int(rg["x1"]):
				over += 1
				t.check(_on(cells, rg["pass"]["path"]), "%s: road %d takes the pass" % [label, r["id"]])
		for rv: Dictionary in bar["rivers"]:
			if lo < int(rv["x0"]) and hi > int(rv["x1"]):
				over += 1
				t.check(_on(cells, rv["crossing"]["cells"]), "%s: road %d takes the %s" % [label, r["id"], rv["kind"]])
	t.check(over >= 1, "%s: some road crosses a barrier (%d)" % [label, over])

static func _on(cells: Dictionary, path: Array) -> bool:
	for q: Array in path:
		if not cells.has(Vector2i(int(q[0]), int(q[1]))):
			return false
	return true

## Per column, a road over a barrier is longer than one with nothing in its way, in the
## route's length and in the sim's hours.
func _cost(t: TestLog, world: TileWorld, label: String) -> void:
	var sim := WorldSim.from_meta(world.meta, world.world_seed)
	var by_id := {}
	for s: Dictionary in world.meta["sites"]:
		by_id[int(s["id"])] = s
	var bar: Dictionary = world.meta["barriers"]
	var rows: Array = []
	for r: Dictionary in world.meta["routes"]:
		if r["kind"] != "road":
			continue
		var xa := mini(int(by_id[int(r["a"])]["x"]), int(by_id[int(r["b"])]["x"]))
		var xb := maxi(int(by_id[int(r["a"])]["x"]), int(by_id[int(r["b"])]["x"]))
		var crossed := 0
		for rg: Dictionary in bar["ranges"]:
			if xa < int(rg["x0"]) and xb > int(rg["x1"]):
				crossed += 1
		rows.append({"crossed": crossed, "per": float(r["length"]) / (xb - xa), "hours": float(sim.route_travel_h[int(r["id"])]) / (xb - xa)})
	var flat := INF
	var flat_h := INF
	var over := 0.0
	var over_h := 0.0
	for row: Dictionary in rows:
		if row["crossed"] > 0:
			over = maxf(over, row["per"])
			over_h = maxf(over_h, row["hours"])
		else:
			flat = minf(flat, row["per"])
			flat_h = minf(flat_h, row["hours"])
	t.check(over > 0.0 and over > flat, "%s: a road over a range is longer per column (%.2f, flat %.2f)" % [label, over, flat])
	t.check(over_h > flat_h, "%s: and takes longer in the sim (%.3f h a column, flat %.3f)" % [label, over_h, flat_h])

## The passages stage treats a river as something built: it never cuts the bed or the water.
func _river_is_built(t: TestLog) -> void:
	var world := WorldGen.generate_named("dev", 1)
	var rv: Dictionary = world.meta["barriers"]["rivers"][0]
	var mid := (int(rv["x0"]) + int(rv["x1"])) / 2
	var bed: int = world.get_fg(mid, int(rv["bed"]))
	t.check(bed >= SP.PLACE_TILES, "the bed is in the tiles passages never cuts (%d)" % bed)
	t.check(TileDefs.id("water") >= SP.PLACE_TILES, "and so is the water")
	t.check(TileDefs.solid[TileDefs.id("river_bed")] != 0 and TileDefs.solid[TileDefs.id("water")] == 0, "a bed is solid and water is not")
