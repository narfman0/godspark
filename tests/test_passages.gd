## Worldgen stage "passages": deterministic, joins the stray cave regions, builds cavern works,
## and leaves every site reachable on foot (the monsters' nav graph, whose jumps are recorded
## from the real controller) from the spawn settlement. tools/cave_nav.gd measures more.
extends RefCounted

const SP := preload("res://core/world/worldgen/stage_passages.gd")

func run(t: TestLog) -> void:
	var a := WorldGen.generate(1024, 512, 5)
	var st: Dictionary = SP.stats
	var b := WorldGen.generate(1024, 512, 5)
	t.eq(ChunkHash.of(a, _all(a)), ChunkHash.of(b, _all(b)), "the same seed makes the same world")
	t.check(int(st.get("joined", 0)) > 20 and int(st.get("left", 99)) * 10 <= int(st.get("to_join", 0)),
		"stray regions are joined (%s)" % st)
	var off := WorldGen.generate(1024, 512, 5, {"passages": false})
	t.check(ChunkHash.of(off, _all(off)) != ChunkHash.of(a, _all(a)), "passages=false leaves the world as it was")
	var feats := 0
	for y in a.height:
		for x in a.width:
			var id := a.get_fg(x, y)
			if TileDefs.rope[id] != 0 or TileDefs.stairs[id] != 0 or id == TileDefs.id("rubble"):
				feats += 1
	t.check(feats > 50, "ropes, stairs and rubble steps were laid (%d cells)" % feats)
	# every site on foot from the spawn settlement
	var prof := MonsterNav.profile(MoveStats.from_srd({"walk": 30}, "medium"))
	var spawn := Vector2.INF
	for s: Dictionary in a.meta["sites"]:
		if s["kind"] == "settlement" and s["band"] in ["surface", "sky"]:
			spawn = Vector2(float(s["x"]) + 0.5, float(s["y"]))
			break
	var f := MonsterNav.start(a, prof, spawn, Vector2(-5000, -5000), Vector2i.ZERO, false, 20000000, Vector2i(a.width, a.height))
	while not f.step(1000000):
		pass
	var missed: Array = []
	var n := 0
	for s: Dictionary in a.meta["sites"]:
		n += 1
		var g := MonsterNav.node_of(prof, Vector2(float(s["x"]) + 0.5, float(s["y"])))
		var ok := false
		for o: Vector2i in [Vector2i.ZERO, Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(1, 1)]:
			if f.path_to(g + o) != null:
				ok = true
				break
		if not ok:
			missed.append("%s %d" % [s["kind"], s["id"]])
	t.check(missed.size() * 8 <= n, "sites reachable on foot from the spawn: %d of %d (missed %s)" % [n - missed.size(), n, missed])

static func _all(w: TileWorld) -> Array:
	var out: Array = []
	for cy in w.chunks_y:
		for cx in w.chunks_x:
			out.append(Vector2i(cx, cy))
	return out
