## Cave and world reachability over several generated worlds.
##   godot --headless -s res://tools/cave_nav.gd -- [seeds=3,5,7,11,13] [pairs=24] [mode=pairs|sites|both]
##                                                   [size=dev] [back=1] [passages=0|1] [pairs_size=medium]
## pairs: the monsters track's cave nav test (tests/test_monster_nav.gd _caves: a Medium walker
##   and a Large climber, air-connected spots ~40 tiles apart in the caves band of a 1024x512
##   world, or pairs_size, a WorldGen size) per seed, and the totals.
## sites: on a `size` world, a Medium walker from the spawn settlement (the first surface
##   settlement) to every other site, on foot: one flood of the nav graph from the spawn (the
##   graph's jumps are recorded from the real controller), then the real body walks each
##   path with NavFollow and PlayerController (replanning up to 4 times), and with back=1
##   walks home again from each site it reached. passages=0 generates without the
##   "passages" stage (the before numbers).
extends SceneTree

func _initialize() -> void:
	var opts := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		opts[kv[0]] = kv[1] if kv.size() > 1 else ""
	var mode := String(opts.get("mode", "pairs"))
	var seeds := String(opts.get("seeds", "3,5,7,11,13")).split(",")
	if mode == "pairs" or mode == "both":
		_pairs(seeds, int(opts.get("pairs", 24)), WorldGen.SIZES.get(opts.get("pairs_size", ""), Vector2i(1024, 512)))
	if mode == "sites" or mode == "both":
		_sites(seeds, String(opts.get("size", "dev")), opts.get("back", "1") != "0", opts.get("passages", "1") != "0",
			opts.get("walk", "1") != "0")
	quit()

func _pairs(seeds: PackedStringArray, pairs: int, size: Vector2i) -> void:
	var test: Object = load("res://tests/test_monster_nav.gd").new()
	var tot := [[0, 0], [0, 0]]
	for s in seeds:
		var r: Array = test.call("_caves", TestLog.new(), int(s), pairs, size)
		for k in 2:
			tot[k][0] += int(r[k][0])
			tot[k][1] += int(r[k][1])
		print("seed %s: medium %d/%d, large %d/%d" % [s, r[0][0], r[0][1], r[1][0], r[1][1]])
	print("CAVENAV medium %d/%d (%.0f%%), large %d/%d (%.0f%%)" % [tot[0][0], tot[0][1], 100.0 * tot[0][0] / maxi(1, tot[0][1]),
		tot[1][0], tot[1][1], 100.0 * tot[1][0] / maxi(1, tot[1][1])])

func _sites(seeds: PackedStringArray, size: String, back: bool, passages: bool, walk := true) -> void:
	var st := NavMaps.stats("medium")
	var prof := MonsterNav.profile(st)
	var all_ok := 0
	var all_n := 0
	var worlds_ok := 0
	var gen_ms := 0
	for s in seeds:
		var t0 := Time.get_ticks_msec()
		var gopts := {"passages": passages}
		for k: String in ["jump_up", "jump_across"]:
			if OS.get_cmdline_user_args().has("%s=%s" % [k, _arg(k)]):
				gopts[k] = int(_arg(k))
		var world := WorldGen.generate_named(size, int(s), gopts)
		print("  passages: ", load("res://core/world/worldgen/stage_passages.gd").get("stats"))
		gen_ms += Time.get_ticks_msec() - t0
		var sites: Array = world.meta.get("sites", [])
		var spawn := Vector2.INF
		var spawn_id := -1
		for site: Dictionary in sites:
			if site["kind"] == "settlement" and site["band"] in ["surface", "sky"]:
				spawn = Vector2(float(site["x"]) + 0.5, float(site["y"]))
				spawn_id = int(site["id"])
				break
		if spawn == Vector2.INF:
			print("seed %s: no surface settlement" % s)
			continue
		var t1 := Time.get_ticks_msec()
		var radius := Vector2i(world.width, world.height)
		var flood := MonsterNav.start(world, prof, spawn, Vector2(-5000, -5000), Vector2i.ZERO, false, 20000000, radius)
		while not flood.step(1000000):
			pass
		var flood_ms := Time.get_ticks_msec() - t1
		var n := 0
		var graph := 0
		var walked := 0
		var home := 0
		var misses: Array = []
		for site: Dictionary in sites:
			if int(site["id"]) == spawn_id:
				continue
			n += 1
			var goal := Vector2(float(site["x"]) + 0.5, float(site["y"]))
			var path := _path_near(flood, prof, goal)
			if path == null:
				misses.append("%s %d at %d,%d (%s): no graph path" % [site["kind"], site["id"], site["x"], site["y"], site["band"]])
				continue
			graph += 1
			if not walk:
				continue
			var r := _walk(world, st, prof, path, spawn, goal)
			if not bool(r["reached"]):
				misses.append("%s %d at %d,%d (%s): walk stopped at %s (%s)" % [site["kind"], site["id"], site["x"], site["y"], site["band"], r["pos"], r["why"]])
				continue
			walked += 1
			if back:
				var rb := _walk(world, st, prof, null, goal, spawn)
				if bool(rb["reached"]):
					home += 1
				else:
					var hint := ""
					if String(rb["why"]) == "no path":
						var fb := MonsterNav.start(world, prof, goal, Vector2(-5000, -5000), Vector2i.ZERO, false, 20000000, radius)
						while not fb.step(1000000):
							pass
						hint = "; from the site it reaches %d nodes, highest %s" % [fb.reached_count(), fb.call("highest")]
					misses.append("%s %d: the way home stopped at %s (%s%s)" % [site["kind"], site["id"], rb["pos"], rb["why"], hint])
		var ok := graph if not walk else (walked if not back else home)
		all_ok += ok
		all_n += n
		if ok == n:
			worlds_ok += 1
		print("seed %s (%s): sites %d, graph %d, walked there %d, and home %s; flood %d nodes in %d ms" % [s, size, n, graph,
			walked, str(home) if back else "-", flood.reached_count(), flood_ms])
		for m: String in misses:
			print("    miss: ", m)
	print("SITENAV %s: %d/%d site trips on foot (%.0f%%), every site in %d of %d worlds; gen %.0f ms avg" % [size, all_ok, all_n,
		100.0 * all_ok / maxi(1, all_n), worlds_ok, seeds.size(), float(gen_ms) / maxi(1, seeds.size())])

static func _arg(k: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(k + "="):
			return a.substr(k.length() + 1)
	return ""

static func _path_near(flood: NavSearch, prof: NavProfile, goal: Vector2) -> NavPath:
	var g := MonsterNav.node_of(prof, goal)
	for o: Vector2i in [Vector2i.ZERO, Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(1, 1),
			Vector2i(0, -1), Vector2i(-2, 0), Vector2i(2, 0)]:
		var p := flood.path_to(g + o)
		if p != null:
			return p
	return null

## Walk a real Medium body from `from` to `to` along `path` (planned with a world-sized window
## when null), replanning up to 4 times when the follower gives up.
static func _walk(world: TileWorld, st: MoveStats, prof: NavProfile, path: NavPath, from: Vector2, to: Vector2) -> Dictionary:
	var b := st.make_body()
	b.pos = from
	TileCollision.update_contacts(world, b)
	var radius := Vector2i(world.width, world.height)
	if path == null:
		path = _plan(world, prof, b.pos, to, radius)
		if path == null:
			return {"reached": false, "pos": b.pos, "why": "no path"}
	var f := NavFollow.new()
	f.set_path(path)
	var dt := 1.0 / K.TICK_HZ
	var steps := maxi(1, MoveStats.step_hz() / K.TICK_HZ)
	var sdt := 1.0 / MoveStats.step_hz()
	var replans := 0
	var why := ""
	for t in path.size() * 40 + 3000:
		var inp := f.input(world, b, dt)
		if inp == null:
			if f.failed and replans < 4:
				replans += 1
				var p2 := _plan(world, prof, b.pos, to, radius)
				if p2 != null:
					f.set_path(p2)
					continue
			why = f.why
			break
		for i in steps:
			PlayerController.step(world, b, inp, st, sdt)
			inp.jump_pressed = false
	var reached := absf(b.pos.x - to.x) <= 2.5 and absf(b.pos.y - to.y) <= 2.0
	return {"reached": reached, "pos": b.pos, "why": why}

static func _plan(world: TileWorld, prof: NavProfile, from: Vector2, to: Vector2, radius: Vector2i) -> NavPath:
	var s := MonsterNav.start(world, prof, from, to, Vector2i(1, 1), false, 4000000, radius)
	while not s.step(1000000):
		pass
	return s.result()
