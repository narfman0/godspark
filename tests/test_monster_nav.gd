## Monster navigation: paths on hand-built maps walked by real bodies through the real
## PlayerController (stairs, gaps, a pit, platforms, a ladder, a low tunnel by size, walls for
## climbers, open space for fliers, water for swimmers, digging), the search window and
## budget, and determinism.
extends RefCounted

func run(t: TestLog) -> void:
	_jumps_recorded(t)
	_stairs(t)
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
