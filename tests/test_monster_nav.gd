## Monster navigation: paths on hand-built maps walked by real bodies through the real
## PlayerController (stairs, gaps, a pit, platforms, a ladder, a low tunnel by size, walls for
## climbers, open space for fliers, water for swimmers, digging), the search window and
## budget, and determinism.
extends RefCounted

func run(t: TestLog) -> void:
	_jumps_recorded(t)
	_stairs(t)
	_stair_tiles(t)
	_gap(t)
	_pit(t)
	_platforms(t)
	_platform_drop(t)
	_ladder(t)
	_tunnel(t)
	_climber(t)
	_flier(t)
	_swimmer(t)
	_digger(t)
	_drop(t)
	_window_and_partial(t)
	_caves(t)

static func _ok(t: TestLog, name: String, r: Dictionary, want_edges := []) -> void:
	t.check(r["planned"], "%s: a path is found" % name)
	if not r["planned"]:
		return
	var p: NavPath = r["path"]
	for e: int in want_edges:
		t.check(p.counts().has(e), "%s: the path uses edge %d (%s)" % [name, e, p.describe()])
	t.check(r["reached"], "%s: the real body gets there (ended at %s after %d ticks; %s; path %s)" % [name, r["pos"], r["ticks"], r["why"], p.describe()])

func _jumps_recorded(t: TestLog) -> void:
	var prof := MonsterNav.profile(NavMaps.stats("medium"))
	t.check(prof.jumps.size() > 20, "medium walker has recorded jumps (%d)" % prof.jumps.size())
	var up := 0
	var far := 0
	for j: Dictionary in prof.jumps:
		up = maxi(up, int(j["dy"]))
		far = maxi(far, absi(int(j["dl"])))
	# the controller's measured peak is 6.47 tiles: feet clear 6 rows
	t.check(up == 6, "highest recorded landing is 6 rows up (got %d)" % up)
	t.check(far >= 7, "a running jump crosses at least 7 columns (got %d)" % far)
	var slow := MonsterNav.profile(NavMaps.stats("medium", {"walk": 20}))
	var far2 := 0
	for j: Dictionary in slow.jumps:
		far2 = maxi(far2, absi(int(j["dl"])))
	t.check(far2 < far, "a slower walker jumps shorter (%d < %d)" % [far2, far])

## Stair tiles (one-way treads): up and down a staircase to a walkway, and S onto stairs from
## a walkway boxed in so the drop is the only way down.
static func _stair_world() -> TileWorld:
	var w := TileWorld.new(96, 96, 7)
	var stone := TileDefs.id("stone")
	for x in 96:
		for y in 8:
			w.set_fg(x, y, stone, true)
	for y in range(8, 60):
		w.set_fg(0, y, stone, true)
		w.set_fg(95, y, stone, true)
	for i in 12:
		w.set_fg(20 + i, 8 + i, TileDefs.id("stairs_r"), true)
	for x in range(32, 46):
		w.set_fg(x, 19, TileDefs.id("platform"), true)
	return w

func _stair_tiles(t: TestLog) -> void:
	var med := NavMaps.stats("medium")
	var w := _stair_world()
	var up := {"world": w, "start": Vector2(10.5, 8), "goal": Vector2(41.5, 20)}
	_ok(t, "a medium walker takes a staircase up to a walkway", NavMaps.run(up, med), [MonsterNav.Edge.STAIRS])
	var down := {"world": w, "start": Vector2(41.5, 20), "goal": Vector2(10.5, 8)}
	_ok(t, "and comes back down it", NavMaps.run(down, med))
	var small := NavMaps.stats("small")
	_ok(t, "a small walker takes it too", NavMaps.run(up, small), [MonsterNav.Edge.STAIRS])
	# a walkway over the lower stairs, walled in: S (a platform drop) is the only way down
	var b := TileWorld.new(96, 96, 7)
	var stone := TileDefs.id("stone")
	for x in 96:
		for y in 8:
			b.set_fg(x, y, stone, true)
	for i in 6:
		b.set_fg(20 + i, 8 + i, TileDefs.id("stairs_r"), true)
	for x in range(22, 28):
		b.set_fg(x, 14, TileDefs.id("platform"), true)
	for y in range(14, 40):
		b.set_fg(21, y, stone, true)
		b.set_fg(28, y, stone, true)
	var box := {"world": b, "start": Vector2(25.0, 15), "goal": Vector2(10.5, 8)}
	_ok(t, "from a boxed-in walkway it drops onto the stairs below and walks down", NavMaps.run(box, med), [MonsterNav.Edge.PLATFORM])

func _stairs(t: TestLog) -> void:
	var m := NavMaps.build([
		"..........................#####G",
		"......................#####.....",
		"..................#####.........",
		"..............#####.............",
		"...........####.................",
		"........####....................",
		"S.....###.......................",
		"####.###........................",
		"################################"])
	_ok(t, "stairs (medium)", NavMaps.run(m, NavMaps.stats("medium")), [MonsterNav.Edge.WALK])
	var m2 := NavMaps.build([
		"....................G",
		"................#####",
		".................####",
		"............####.####",
		"............#########",
		"S.......#############",
		"#####...#############",
		"#####################"])
	_ok(t, "two-high steps need jumps", NavMaps.run(m2, NavMaps.stats("medium")), [MonsterNav.Edge.JUMP])

func _gap(t: TestLog) -> void:
	var m := NavMaps.build([
		"S.................G..",
		"#########.....#######",
		"#########.....#######",
		"#########.....#######",
		"#########.....#######",
		"#########.....#######",
		"#########.....#######",
		"#########.....#######",
		"#########.....#######",
		"#####################"])
	var r := NavMaps.run(m, NavMaps.stats("medium"))
	_ok(t, "gap of 5", r, [MonsterNav.Edge.JUMP])

func _pit(t: TestLog) -> void:
	var m := NavMaps.build([
		"..............G....",
		"########....#######",
		"########....#######",
		"########....#######",
		"########....#######",
		"########.S..#######",
		"###################"])
	_ok(t, "out of a 5-deep pit", NavMaps.run(m, NavMaps.stats("medium")), [MonsterNav.Edge.JUMP])
	var deep := NavMaps.build([
		"..............G....",
		"########....#######",
		"########....#######",
		"########....#######",
		"########....#######",
		"########....#######",
		"########....#######",
		"########....#######",
		"########.S..#######",
		"###################"])
	var r := NavMaps.run(deep, NavMaps.stats("medium"))
	t.check(not r["planned"], "an 8-deep pit is out of a walker's jump (no path)")
	var spider := NavMaps.run(deep, NavMaps.stats("medium", {"walk": 30, "climb": 30}))
	_ok(t, "a climber walks out of the 8-deep pit", spider, [MonsterNav.Edge.CLING])

func _platforms(t: TestLog) -> void:
	var m := NavMaps.build([
		"...............G..",
		"............######",
		"..................",
		"..................",
		"........====......",
		"..................",
		"..................",
		"...====...........",
		"..................",
		"..................",
		"S.................",
		"##################"])
	_ok(t, "up one-way platforms", NavMaps.run(m, NavMaps.stats("medium")), [MonsterNav.Edge.JUMP])

func _platform_drop(t: TestLog) -> void:
	var m := NavMaps.build([
		"..S.......",
		"#=====####",
		"..........",
		"..........",
		"..........",
		"......G...",
		"##########"])
	_ok(t, "down through a platform", NavMaps.run(m, NavMaps.stats("medium")), [MonsterNav.Edge.PLATFORM])

func _ladder(t: TestLog) -> void:
	var m := NavMaps.build([
		".....HH.G....",
		"#####HH######",
		"....#HH#.....",
		"....#HH#.....",
		"....#HH#.....",
		"....#HH#.....",
		"....#HH#.....",
		"....#HH#.....",
		"....#HH#.....",
		"....#HH#.....",
		"....#HH#.....",
		".....HH......",
		".....HH......",
		"..S..HH......",
		"#############"])
	_ok(t, "up a ladder shaft", NavMaps.run(m, NavMaps.stats("medium")), [MonsterNav.Edge.LADDER])

func _tunnel(t: TestLog) -> void:
	var m := NavMaps.build([
		"#########################",
		"#########################",
		"#########################",
		".........................",
		".........................",
		"S......................G.",
		"#########################"])
	_ok(t, "medium through a 3-high tunnel", NavMaps.run(m, NavMaps.stats("medium")))
	var big := NavMaps.run(m, NavMaps.stats("large"))
	t.check(not big["planned"], "large does not fit a 3-high tunnel")
	var wide := NavMaps.build([
		"#########################",
		".........................",
		".........................",
		".........................",
		"S......................G.",
		"#########################"])
	_ok(t, "large through a 4-high tunnel", NavMaps.run(wide, NavMaps.stats("large")))

func _climber(t: TestLog) -> void:
	var m := NavMaps.build([
		"..........G...",
		"......########",
		"......########",
		"......########",
		"......########",
		"......########",
		"......########",
		"......########",
		"......########",
		"......########",
		"......########",
		"..S...########",
		"##############"])
	var spider := NavMaps.stats("large", {"walk": 30, "climb": 30})
	_ok(t, "a giant spider walks up a 11-high wall", NavMaps.run(m, spider), [MonsterNav.Edge.CLING])
	t.check(not NavMaps.run(m, NavMaps.stats("large"))["planned"], "a plain large walker cannot")

func _flier(t: TestLog) -> void:
	var m := NavMaps.build([
		"#############.......",
		"#...........#...G...",
		"#..######...#.......",
		"#..#....#...#.......",
		"#..#....#...######..",
		"#S.#....#...........",
		"####################"])
	var bat := NavMaps.stats("large", {"walk": 10, "fly": 60})
	_ok(t, "a giant bat flies through a winding cave", NavMaps.run(m, bat), [MonsterNav.Edge.FLY])

func _swimmer(t: TestLog) -> void:
	var m := NavMaps.build([
		"......................",
		"S.....................",
		"####~~~~~~~~~~~~######",
		"####~~~~~~~~~~~~######",
		"####~~~~~~~~~~~~######",
		"####~~~~~~~~~~~~######",
		"####~~~~~~~~~~~~######",
		"####~~~~~~~~~~~~######",
		"######~~~~~~~~~~######",
		"######~~~~G~~~~~######",
		"######################"])
	var shark := NavMaps.stats("medium", {"walk": 5, "swim": 40})
	_ok(t, "a swimmer dives to the bottom of a pool", NavMaps.run(m, shark))

func _digger(t: TestLog) -> void:
	var m := NavMaps.build([
		"####################",
		"....dddddddddddd....",
		"....dddddddddddd....",
		"S...dddddddddddd..G.",
		"####################"])
	var plain := NavMaps.run(m, NavMaps.stats("medium"))
	t.check(not plain["planned"], "a plain walker cannot pass solid dirt")
	var worm := NavMaps.stats("medium", {"walk": 30, "burrow": 30})
	var r := NavMaps.run(m, worm, 2400, MonsterNav.SOFT_HARDNESS)
	_ok(t, "a tunneller digs through 12 columns of dirt", r)
	t.check(int(r["dug"]) >= 24, "it dug real tiles (%d)" % int(r["dug"]))
	var w: TileWorld = m["world"]
	t.check(not w.is_solid(NavMaps.OX + 10, NavMaps.OY + 1), "the tunnel is in the world")

func _drop(t: TestLog) -> void:
	var m := NavMaps.build([
		"#####...",
		"........",
		"........",
		"S.......",
		"####....",
		"####....",
		"####....",
		"####....",
		"####....",
		"####..G.",
		"########"])
	_ok(t, "drop off a 6-high ledge", NavMaps.run(m, NavMaps.stats("medium")), [MonsterNav.Edge.DROP])

func _window_and_partial(t: TestLog) -> void:
	var world := TileWorld.new(256, 64, 3)
	var stone := TileDefs.id("stone")
	for x in 256:
		for y in 10:
			world.set_fg(x, y, stone, true)
	var prof := MonsterNav.profile(NavMaps.stats("medium"))
	var s := MonsterNav.start(world, prof, Vector2(20.5, 10), Vector2(200.5, 10))
	while not s.step(500):
		pass
	var p := s.result()
	t.check(p != null and not p.reached, "a goal outside the window gives a partial path")
	if p != null:
		t.check(p.end_node().x - 20 >= MonsterNav.WINDOW - 2, "the partial path heads to the window's edge (%d)" % p.end_node().x)
	var a := MonsterNav.start(world, prof, Vector2(20.5, 10), Vector2(60.5, 10))
	var steps := 0
	while not a.step(10):
		steps += 1
	t.check(steps >= 3, "a search is resumable in small slices (%d)" % steps)
	var b := MonsterNav.start(world, prof, Vector2(20.5, 10), Vector2(60.5, 10))
	while not b.step(100000):
		pass
	t.eq(a.result().describe(), b.result().describe(), "sliced and whole searches find the same path")

## Generated cave terrain: a Medium walker and a Large climber try to reach spots ~40 tiles
## away in the caves band. Pairs are random standing spots (not known to be connected).
func _caves(t: TestLog, world_seed := 13, pairs := 24) -> Array:
	var world := WorldGen.generate(1024, 512, world_seed)
	var out := []
	var band: Array = world.meta.get("bands", {}).get("caves", [100, 200])
	var r := RandomNumberGenerator.new()
	r.seed = 5
	for spec: Array in [["medium", {"walk": 30}], ["large", {"walk": 30, "climb": 30}]]:
		var st := NavMaps.stats(spec[0], spec[1])
		var ok := 0
		var planned := 0
		var n := 0
		var usec := 0
		var tries := 0
		while n < pairs and tries < 5000:
			tries += 1
			var a := _spot(world, st, r, int(band[0]), int(band[1]))
			if a == Vector2.INF:
				continue
			# a spot 35-45 tiles away in the same open cave (air-connected cells)
			var b := Vector2.INF
			var cands := _connected_spots(world, st, a)
			if not cands.is_empty():
				b = cands[r.randi_range(0, cands.size() - 1)]
			if b == Vector2.INF:
				continue
			n += 1
			var res := NavMaps.run({"world": world, "start": a, "goal": b}, st, 900)
			if OS.has_environment("NAVDBG") and not res["planned"]:
				print("   %s miss %s -> %s expanded %d" % [spec[0], a, b, res["expanded"]])
			elif OS.has_environment("NAVDBG") and not res["reached"]:
				print("   %s stuck %s -> %s at %s: %s" % [spec[0], a, b, res["pos"], res["why"]])
			usec += int(res["usec"])
			if res["planned"]:
				planned += 1
			if res["reached"]:
				ok += 1
		print("  cave nav %s: %d/%d reached (%d planned), %.1f ms per plan" % [spec[0], ok, n, planned, usec / 1000.0 / maxf(n, 1)])
		out.append([ok, n])
		t.check(n >= 20, "enough cave pairs for %s (%d)" % [spec[0], n])
		# Noise caves are often cramped shafts a 2x3 or 3x4 body cannot climb without digging;
		# when the search finds a way, the real body must take it. The passability pass
		# (docs/tracks/passability.md) made NavFollow steer jumps along their recorded arcs,
		# brake for drops and take-offs, leave ladders cleanly and pick a path up again where
		# the body stands, and made the planner match the controller (landings with real
		# footing, stairs, platform drops): over 10 seeds a Medium walker follows 98% of its
		# planned cave paths and a Large climber 85% (few Large paths per world, 8 or 9 here, so
		# one miss moves it 11 points). The bar is 9 in 10 for Medium (it was 8 in 10 before the
		# passages stage, then 7 and 6 while the follower failed jumps) and 3 in 4 for Large.
		var ok_bar := ok * 10 >= planned * 9 if spec[0] == "medium" else ok * 4 >= planned * 3
		t.check(planned > 0 and ok_bar, "%s: the real body follows found cave paths (%d of %d)" % [spec[0], ok, planned])
		# The passages stage joins cave regions through two-wide shafts and Medium-sized ways,
		# so many more pairs count as air-connected that a Large body cannot use: its share
		# fell (docs/tracks/traversal.md); a Medium one rose.
		var share := 4 if spec[0] == "medium" else 6
		t.check(ok * share >= n, "%s reaches at least 1/%d of air-connected cave spots 40 tiles away (%d/%d)" % [spec[0], share, ok, n])
		if spec[0] == "medium":
			t.check(ok * 2 >= n, "medium reaches at least half of them (%d/%d)" % [ok, n])
	return out

static func _connected_spots(world: TileWorld, st: MoveStats, a: Vector2) -> Array:
	var seen := {}
	var q: Array[Vector2i] = [Vector2i(floori(a.x), int(a.y))]
	seen[q[0]] = true
	var out := []
	var head := 0
	while head < q.size() and q.size() < 20000:
		var c: Vector2i = q[head]
		head += 1
		var d := Vector2(c).distance_to(a)
		if d >= 35.0 and d <= 45.0 and _stands(world, st, Vector2(c.x + 0.5, c.y)):
			out.append(Vector2(c.x + 0.5, c.y))
		for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := c + o
			if seen.has(n) or world.is_solid(n.x, n.y) or Vector2(n).distance_to(a) > 46.0:
				continue
			seen[n] = true
			q.append(n)
	return out

static func _spot(world: TileWorld, st: MoveStats, r: RandomNumberGenerator, y0: int, y1: int) -> Vector2:
	for k in 400:
		var p := Vector2(r.randi_range(40, world.width - 40) + 0.5, r.randi_range(y0, y1))
		if _stands(world, st, p):
			return p
	return Vector2.INF

static func _stands(world: TileWorld, st: MoveStats, p: Vector2) -> bool:
	var cw := ceili(st.size.x - 1e-3)
	var ch := ceili(st.size.y - 1e-3)
	var L := floori(p.x - cw * 0.5 + 0.5)
	var y := int(p.y)
	var floor_ok := false
	for c in range(L, L + cw):
		for rr in range(y, y + ch):
			if world.is_solid(c, rr):
				return false
		if world.is_solid(c, y - 1):
			floor_ok = true
	return floor_ok
