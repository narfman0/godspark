## Roads and route paths (stage "roads"): every surface road is graded (no step over one
## tile per column), runs from one place's street end to the next, and a Medium walker (the
## real controller) walks it both ways. Deep routes have a path; a path with a bigger step
## is flagged rough.
extends RefCounted

const PlaceGen := preload("test_place_gen.gd")

func run(t: TestLog) -> void:
	var world := WorldGen.generate_named("dev", 3)
	var took := int(WorldGen.last_timings.get("roads", 999))
	if took >= 400:           # other processes run beside this one (tools/test.sh): a second sample
		WorldGen.generate_named("dev", 3)
		took = mini(took, int(WorldGen.last_timings.get("roads", 999)))
	t.check(took < 400, "the roads stage takes %d ms" % took)
	var st := NavMaps.stats("medium")
	var roads := 0
	for r: Dictionary in world.meta["routes"]:
		var path := Places.route_path(world, int(r["id"]))
		t.check(path.size() >= 2, "route %d has a path" % r["id"])
		var steep := 0
		for i in range(1, path.size()):
			if absi(path[i].y - path[i - 1].y) > 1:
				steep += 1
		if r["kind"] != "road":
			t.check(steep == 0 or r.get("rough", false), "deep route %d: a step over one tile only on a rough path" % r["id"])
			continue
		roads += 1
		t.check(not r.get("rough", false), "road %d is not rough" % r["id"])
		t.eq(steep, 0, "road %d: no step over one tile" % r["id"])
		var cols_ok := true
		var feet_ok := true
		for i in path.size():
			var p: Vector2i = path[i]
			if i > 0 and absi(p.x - path[i - 1].x) != 1:
				cols_ok = false
			if world.is_solid(p.x, p.y) or world.is_solid(p.x, p.y + 1) or world.is_solid(p.x, p.y + 2) or world.is_solid(p.x, p.y + 3):
				feet_ok = false
			var u := world.get_fg(p.x, p.y - 1)
			# a ladder's head holds a body as a walkway does (a sinkhole's rope comes up through its deck)
			var head := TileDefs.ladder[u] != 0 and TileDefs.ladder[world.get_fg(p.x, p.y)] == 0
			if not world.is_solid(p.x, p.y - 1) and TileDefs.platform[u] == 0 and not head:
				feet_ok = false
		t.check(cols_ok, "road %d: one column per step" % r["id"])
		t.check(feet_ok, "road %d: every cell has a floor and 4 clear rows (a wagon fits)" % r["id"])
		var pa := Places.place(world, int(r["a"]))
		var pb := Places.place(world, int(r["b"]))
		t.check(_is_end(pa, path[0]) and _is_end(pb, path[-1]), "road %d: from a street end to a street end" % r["id"])
		t.check(_follow(world, st, path), "road %d: a Medium walker walks it from a to b" % r["id"])
		var back := path.duplicate()
		back.reverse()
		t.check(_follow(world, st, back), "road %d: and from b to a" % r["id"])
	t.check(roads >= 3, "the surface settlements are joined by roads (%d)" % roads)
	var bridged := false
	for x in world.width:
		for y in range(world.height / 2, world.height):
			if world.get_fg(x, y) == TileDefs.id("bridge"):
				bridged = true
				break
		if bridged:
			break
	t.check(bridged, "some road crosses a gap on a bridge")

static func _is_end(p: Dictionary, c: Vector2i) -> bool:
	if p.is_empty():
		return true
	var s: Array = p["street"]
	return c.y == int(s[2]) and (c.x == int(s[0]) or c.x == int(s[1]))

## Walk the path with the real controller, a leg every LEG cells.
static func _follow(world: TileWorld, st: MoveStats, path: Array) -> bool:
	var pos := Vector2(path[0].x + 0.5, path[0].y)
	var i := 0
	while i < path.size() - 1:
		i = mini(i + 30, path.size() - 1)
		var goal := Vector2(path[i].x + 0.5, path[i].y)
		var r := NavMaps.run({"world": world, "start": pos, "goal": goal}, st, 900)
		if not r["reached"]:
			print("    leg to %s failed at %s: %s" % [goal, r["pos"], r["why"]])
			return false
		pos = r["pos"]
	return true
