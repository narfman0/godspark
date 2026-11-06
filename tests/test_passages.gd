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
	# pockets that no feature may reach (beside a town or a road, small and far) are left
	t.check(int(st.get("joined", 0)) > 20 and int(st.get("left", 99)) * 4 <= int(st.get("to_join", 0)),
		"stray regions are joined (joined %s, left %s of %s)" % [st.get("joined"), st.get("left"), st.get("to_join")])
	var off := WorldGen.generate(1024, 512, 5, {"passages": false})
	t.check(ChunkHash.of(off, _all(off)) != ChunkHash.of(a, _all(a)), "passages=false leaves the world as it was")
	var feats := 0
	for y in a.height:
		for x in a.width:
			var id := a.get_fg(x, y)
			if TileDefs.rope[id] != 0 or TileDefs.stairs[id] != 0 or id == TileDefs.id("rubble"):
				feats += 1
	t.check(feats > 50, "ropes, stairs and rubble steps were laid (%d cells)" % feats)
	# every site and both ends of every route on foot from the spawn settlement (stage
	# "reach" guarantees it; the monsters' nav graph, jumps recorded from the real controller,
	# checks it), on this world and one more
	_every_target(t, a, "1024x512 seed 5")
	_every_target(t, WorldGen.generate(1024, 512, 2), "1024x512 seed 2")
	var dev := WorldGen.generate_named("dev", 7)
	_every_target(t, dev, "dev seed 7")
	var rough := 0
	for r: Dictionary in dev.meta["routes"]:
		if r.get("rough", false):
			rough += 1
	t.check(rough * 4 <= (dev.meta["routes"] as Array).size(), "deep routes are walks, few rough (%d of %d)" % [rough, (dev.meta["routes"] as Array).size()])

static func _every_target(t: TestLog, world: TileWorld, label: String) -> void:
	var prof := MonsterNav.profile(MoveStats.from_srd({"walk": 30}, "medium"))
	var tg: Array = load("res://tools/passability_sweep.gd")._targets(world)
	var f := MonsterNav.start(world, prof, tg[0][1], Vector2(-5000, -5000), Vector2i.ZERO, false, 40000000, Vector2i(world.width, world.height))
	while not f.step(1000000):
		pass
	var missed: Array = []
	for tt: Array in tg:
		if not load("res://tools/passability_sweep.gd")._reached(f, prof, tt[1]):
			missed.append(tt[0])
	t.check(missed.is_empty(), "%s: every site and route end on foot from the spawn (%d targets; apart: %s)" % [label, tg.size(), missed])

static func _all(w: TileWorld) -> Array:
	var out: Array = []
	for cy in w.chunks_y:
		for cx in w.chunks_x:
			out.append(Vector2i(cx, cy))
	return out
