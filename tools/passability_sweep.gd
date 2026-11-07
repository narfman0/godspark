## Passability over many generated worlds: generation time, the joins the passages stage
## built (by kind), what the final "reach" stage found apart and joined, and the check that
## matters: a flood of the monsters' nav graph (Medium walker, jumps recorded from the real
## controller) from the spawn settlement to every site and both ends of every route.
##   godot --headless -s res://tools/passability_sweep.gd -- [seeds=3,5,7] [size=dev] [flood=1]
##                                                            [passages=0|1] [cross=1]
## Prints one line per world and a PASSWEEP total. flood=0 skips the nav check (timings only).
## cross=1: the real controller walks every pass, under-route and river crossing both ways.
extends SceneTree

const SP := preload("res://core/world/worldgen/stage_passages.gd")

func _initialize() -> void:
	var opts := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() > 1 else ""
	var seeds := String(opts.get("seeds", "3,5,7")).split(",")
	var size := String(opts.get("size", "dev"))
	var flood: bool = opts.get("flood", "1") != "0"
	var gopts := {"passages": String(opts.get("passages", "1")) != "0"}
	var prof := MonsterNav.profile(MoveStats.from_srd({"walk": 30}, "medium"))
	var tot_ok := 0
	var tot_n := 0
	var worlds_ok := 0
	var gen_ms := 0
	var pass_ms := 0
	var reach_ms := 0
	var kinds_all := {}
	var rough := 0
	var routes := 0
	var cross_bad := 0
	for s in seeds:
		var world := WorldGen.generate_named(size, int(s), gopts)
		var tm: Dictionary = WorldGen.last_timings
		gen_ms += int(tm["total"])
		pass_ms += int(tm.get("passages", 0))
		reach_ms += int(tm.get("reach", 0))
		var st: Dictionary = SP.stats
		var kinds := {}
		for src: Dictionary in [st.get("features", {}), st.get("second", {}).get("features", {})]:
			for k: String in src:
				kinds[k] = int(kinds.get(k, 0)) + int(src[k])
		var rs: Dictionary = SP.reach_stats
		for rd: Dictionary in rs.get("rounds", []):
			for k: String in rd.get("kinds", {}):
				kinds["reach " + k] = int(kinds.get("reach " + k, 0)) + int(rd["kinds"][k])
		for k: String in kinds:
			kinds_all[k] = int(kinds_all.get(k, 0)) + int(kinds[k])
		for r: Dictionary in world.meta["routes"]:
			routes += 1
			if r.get("rough", false):
				rough += 1
		print("  hash ", world.content_hash(), " stages ms: ", tm)
		print("  phases ms: ", st.get("phases_ms", {}), " first ", st.get("prof_us", {}), " spots ", st.get("spots_ms"), " moves ", st.get("moves_ms"), " join ", st.get("join_ms"), " comps ", st.get("components"), " to_join ", st.get("to_join"), " joined ", st.get("joined"), " left ", st.get("left"), " second ", st.get("second", {}).get("ms"))
		var line := "seed %s %s: gen %d ms (passages %d, reach %d); joins %s; reach %s" % [s, size, tm["total"],
			tm.get("passages", 0), tm.get("reach", 0), kinds, _brief(rs)]
		if not flood:
			print(line)
			continue
		var tg := _targets(world)
		var spawn: Vector2 = tg[0][1]
		var f := MonsterNav.start(world, prof, spawn, Vector2(-5000, -5000), Vector2i.ZERO, false, 40000000,
			Vector2i(world.width, world.height))
		while not f.step(1000000):
			pass
		var miss: Array = []
		for t: Array in tg:
			if not _reached(f, prof, t[1]):
				miss.append("%s at %s" % [t[0], t[1]])
		tot_ok += tg.size() - miss.size()
		tot_n += tg.size()
		if miss.is_empty():
			worlds_ok += 1
		print(line, "; on foot %d/%d" % [tg.size() - miss.size(), tg.size()])
		if not rs.get("missing", []).is_empty():
			print("    passages left apart: ", rs["missing"])
		for m: String in miss:
			print("    apart: ", m)
		if opts.has("cross"):
			var bad: Array = load("res://tests/test_barriers.gd").check_world(world)
			print("    crossings: %s" % ("all walked both ways" if bad.is_empty() else str(bad)))
			cross_bad += bad.size()
	var n := seeds.size()
	print("PASSWEEP %s x%d: targets on foot %d/%d, every target in %d of %d worlds; rough routes %d/%d; gen %.0f ms avg (passages %.0f, reach %.0f); joins per world %s" % [
		size, n, tot_ok, tot_n, worlds_ok, n if flood else 0, rough, routes, float(gen_ms) / n, float(pass_ms) / n,
		float(reach_ms) / n, _per(kinds_all, n)])
	if opts.has("cross"):
		print("PASSWEEP crossings wrong: %d" % cross_bad)
	quit()

static func _brief(rs: Dictionary) -> String:
	var parts := PackedStringArray()
	for rd: Dictionary in rs.get("rounds", []):
		parts.append("%d apart, %d joined, %s ms" % [rd["apart"], rd["joined"], rd.get("ms", "-")])
	return "[%s] clean %s, %s ms" % [", ".join(parts), rs.get("clean", "-"), rs.get("ms", "-")]

static func _per(d: Dictionary, n: int) -> Dictionary:
	var out := {}
	for k: String in d:
		out[k] = snappedf(float(d[k]) / n, 0.1)
	return out

## [label, feet position] for every site and both ends of every route; the spawn first.
static func _targets(world: TileWorld) -> Array:
	var out: Array = []
	var spawn := -1
	for s: Dictionary in world.meta["sites"]:
		if s["kind"] == "settlement" and s["band"] in ["surface", "sky"]:
			spawn = int(s["id"])
			out.append(["spawn %d" % spawn, Vector2(float(s["x"]) + 0.5, float(s["y"]))])
			break
	for s: Dictionary in world.meta["sites"]:
		if int(s["id"]) != spawn:
			out.append(["%s %d (%s)" % [s["kind"], s["id"], s["band"]], Vector2(float(s["x"]) + 0.5, float(s["y"]))])
	for r: Dictionary in world.meta["routes"]:
		var path: Array = r.get("path", [])
		if path.size() >= 2:
			out.append(["route %d a" % r["id"], Vector2(float(path[0][0]) + 0.5, float(path[0][1]))])
			out.append(["route %d b" % r["id"], Vector2(float(path[-1][0]) + 0.5, float(path[-1][1]))])
	var bar: Dictionary = world.meta.get("barriers", {})
	for rg: Dictionary in bar.get("ranges", []):
		for way: String in ["pass", "under"]:
			var path: Array = rg[way]["path"]
			out.append(["%s %d west" % [way, rg["id"]], Vector2(float(path[0][0]) + 0.5, float(path[0][1]))])
			out.append(["%s %d east" % [way, rg["id"]], Vector2(float(path[-1][0]) + 0.5, float(path[-1][1]))])
	for rv: Dictionary in bar.get("rivers", []):
		var cells: Array = rv["crossing"]["cells"]
		out.append(["river %d west" % rv["id"], Vector2(float(cells[0][0]) + 0.5, float(cells[0][1]))])
		out.append(["river %d east" % rv["id"], Vector2(float(cells[-1][0]) + 0.5, float(cells[-1][1]))])
	# the underground (M6): the lake's shore path, the lava bridges, the sinkholes, the nadir floor
	var d: Dictionary = world.meta.get("descent", {})
	var at := func(q: Array) -> Vector2: return Vector2(float(q[0]) + 0.5, float(q[1]))
	var lc: Array = d.get("lake", {}).get("crossing", {}).get("cells", [])
	if lc.size() >= 2:
		out.append(["lake west", at.call(lc[0])])
		out.append(["lake east", at.call(lc[-1])])
	for t: Dictionary in d.get("lava", []):
		for b: Dictionary in t["bridges"]:
			out.append(["lava bridge %d west" % b["x0"], at.call(b["cells"][0])])
			out.append(["lava bridge %d east" % b["x0"], at.call(b["cells"][-1])])
	for i in (d.get("sinkholes", []) as Array).size():
		var sk: Dictionary = d["sinkholes"][i]
		out.append(["sinkhole %d top" % i, at.call([int(sk["rope"]) - 1, int(sk["top"])])])
		out.append(["sinkhole %d bottom" % i, at.call([int(sk["rope"]) - 1, int(sk["bottom"])])])
	if (d.get("nadir", []) as Array).size() == 2:
		out.append(["nadir floor", at.call(d["nadir"])])
	return out

static func _reached(f: NavSearch, prof: NavProfile, p: Vector2) -> bool:
	var g := MonsterNav.node_of(prof, p)
	for o: Vector2i in SP.NEAR:
		var k := f._key(g.x + o.x, g.y + o.y)
		if k >= 0 and f._g[k] != INF:
			return true
	return false
