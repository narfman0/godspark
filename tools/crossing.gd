## The goal's first clause as a tool: a bot walks from the cold end to the hot end on the surface,
## the real PlayerController on the world's tiles, taking passes, bridges and fords, never digging.
##   godot --headless -s res://tools/crossing.gd -- gen=medium seed=1 [cache=DIR]
## Prints the biomes entered with their x, every crossing and its kind, the time on screen, and a
## last line with digs=0. A spot in the middle of each biome is printed for tools/look_shot.gd.
## cache=DIR loads the world from DIR, or generates it and saves it there.
## Exit code 1 if the walk was not a whole crossing.
extends SceneTree

func _initialize() -> void:
	var o := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		o[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var gen := String(o.get("gen", "medium"))
	var sd := int(o.get("seed", 1))
	var world := _world(gen, sd, String(o.get("cache", "")))
	var climate: Dictionary = world.meta.get("climate", {})
	var t0 := Time.get_ticks_msec()
	var r := CrossingBot.walk(world)
	print("CROSSING gen=%s seed=%d %dx%d order=%s walk x=%d..%d" % [gen, sd, world.width, world.height, climate.get("order", "?"), r["start"], r["end"]])
	for e: Dictionary in r["entered"]:
		print("  enter %-8s x=%-5d t=%6.1f s  %s" % [e["biome"], e["x"], e["t"], e["name"]])
	for c: Dictionary in r["crossed"]:
		print("  cross %-6s x=%d..%d t=%6.1f s took %5.1f s, %.1f rows off its way  %s" % [c["kind"], c["x0"], c["x1"], c["t"], c["took"], c["off"], c["name"]])
	for s: Dictionary in r["trail"]:
		print("  shot biome=%s x=%d y=%d" % [s["biome"], s["x"], s["y"]])
	var kinds := {}
	for c: Dictionary in r["crossed"]:
		kinds[c["kind"]] = int(kinds.get(c["kind"], 0)) + 1
	var faults := CrossingBot.faults(world, r)
	for f: String in faults:
		print("  FAULT %s" % f)
	var names: Array = (r["entered"] as Array).map(func(e: Dictionary) -> String: return String(e["biome"]))
	print("CROSSING %s seed=%d biomes=%d %s crossings=%d %s time=%.0f s (%.1f min) ticks=%d legs=%d below=%.1f digs=%d tiles_changed=%s walked in %d ms" % [
		"PASS" if faults.is_empty() else "FAIL", sd, names.size(), ">".join(names), (r["crossed"] as Array).size(), kinds, r["seconds"], float(r["seconds"]) / 60.0, r["ticks"], r["legs"], r["below"],
		r["digs"], r["tiles_changed"], Time.get_ticks_msec() - t0])
	quit(0 if faults.is_empty() else 1)

static func _world(gen: String, sd: int, cache: String) -> TileWorld:
	if cache != "" and DirAccess.dir_exists_absolute(cache) and not DirAccess.get_files_at(cache).is_empty():
		var back := WorldSave.load(cache)
		if back != null:
			return back
	var w := WorldGen.generate_named(gen, sd)
	if cache != "":
		DirAccess.make_dir_recursive_absolute(cache)
		WorldSave.save(w, cache)
	return w
