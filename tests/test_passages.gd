## Worldgen stage "passages": deterministic, joins the stray cave regions, builds cavern works,
## and leaves every site reachable on foot (the monsters' nav graph, whose jumps are recorded
## from the real controller) from the spawn settlement. tools/cave_nav.gd measures more.
extends RefCounted

const SP := preload("res://core/world/worldgen/stage_passages.gd")
const GC := preload("res://core/world/worldgen/gen_context.gd")

func run(t: TestLog) -> void:
	_steps(t)
	_spots(t)
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

## A body rises a row walking only for something solid in its way or a stair tread: a walkway
## one row up lets it walk in underneath, so Passer must not call that a step both ways. It
## hid a 7000-spot island of medium seed 2 from the joins. (The ground and the walkway may
## still be joined by a jump: a body jumps up through a walkway and drops back through it.)
func _steps(t: TestLog) -> void:
	for spec: Array in [
			["stone", [[20, 10], [21, 10], [22, 10], [23, 10], [24, 10]], true, "a solid ledge a row up is a step"],
			["platform", [[20, 10], [21, 10], [22, 10], [23, 10], [24, 10]], false, "a walkway a row up is not"],
			["stairs_r", [[20, 10], [21, 11], [22, 12]], true, "a stair tread lifts the body"]]:
		var c := GC.new(64, 32, 1, {})
		for y in 10:
			for x in 64:
				c.fg[x + y * 64] = c.STONE
		for x in 64:
			c.ground[x] = 9
		for q: Array in spec[1]:
			c.fg[int(q[0]) + int(q[1]) * 64] = TileDefs.id(spec[0])
		var p := SP.Passer.new(c, RandomNumberGenerator.new())
		p.log_edges = true
		p.build_spots()
		p.join_moves()
		var stepped := false
		for i in range(0, p.edge_log.size(), 3):
			var a := p.edge_log[i]
			var b := p.edge_log[i + 1]
			if p.edge_log[i + 2] == 1 and p.spy[a] != p.spy[b]:
				stepped = true
		t.eq(stepped, spec[2], spec[3])

## build_spots searches natively past the rock: it must find what a walk over every cell finds.
func _spots(t: TestLog) -> void:
	var w := WorldGen.generate(512, 256, 3)
	var c := GC.new(w.width, w.height, 3, {})
	var g := WorldGen.grids(w)
	c.fg = g[0]
	for x in c.w:
		c.ground[x] = c.h - 48
	var p := SP.Passer.new(c, RandomNumberGenerator.new())
	p.build_spots()
	var bad := 0
	var n := 0
	for y in range(1, p.top):
		for x in c.w - 1:
			var open := true
			for dy in 3:
				if c.is_solid(x, y + dy) or c.is_solid(x + 1, y + dy):
					open = false
			var a := c.fg[x + (y - 1) * c.w]
			var b := c.fg[x + 1 + (y - 1) * c.w]
			var floored := c.solid[a] != 0 or c.solid[b] != 0 or p.oneway[a] != 0 or p.oneway[b] != 0 \
				or (p.climb[a] != 0 and p.climb[c.fg[x + y * c.w]] == 0) or (p.climb[b] != 0 and p.climb[c.fg[x + 1 + y * c.w]] == 0)
			var want := open and floored
			if want:
				n += 1
			if want != (p.spot(x, y) >= 0):
				bad += 1
	t.eq(bad, 0, "build_spots finds the %d spots of a walk over every cell" % n)
	t.eq(p.spx.size(), n, "and no others")

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
