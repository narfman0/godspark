## The goal's first clause as a tool: a bot walks from the cold end to the hot end on the surface,
## the real PlayerController on the world's tiles, taking passes, bridges and fords, never digging.
##   godot --headless -s res://tools/crossing.gd -- gen=medium seed=1 [cache=DIR]
## descent: a walker from the spawn settlement down to the nadir floor and back (DescentBot),
## printing the bands and regions entered, the ways in it used, what it crossed, digs=0, and
## the ways in from the surface each surface biome has.
##   godot --headless -s res://tools/crossing.gd -- gen=medium seed=1 descent [cache=DIR]
## Prints the biomes entered with their x, every crossing and its kind, the time on screen, and a
## last line with digs=0. A spot in the middle of each biome is printed for tools/look_shot.gd.
## cache=DIR loads the world from DIR, or generates it and saves it there.
## pace=X walks at X tiles a second per 30 ft instead of data/movement.json's pace (measuring
## only: MoveStats.pace_override); the world is the same at any pace.
## Exit code 1 if the walk was not a whole crossing.
extends SceneTree

func _initialize() -> void:
	var o := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		o[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if o.has("pace"):
		MoveStats.pace_override = float(o["pace"])
	var gen := String(o.get("gen", "medium"))
	var sd := int(o.get("seed", 1))
	var world := _world(gen, sd, String(o.get("cache", "")))
	if o.has("descent"):
		_descent(world, gen, sd)
		return
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
	_towns(world, r)
	var faults := CrossingBot.faults(world, r)
	for f: String in faults:
		print("  FAULT %s" % f)
	if r.has("below_at"):
		print("  deepest under the line at %s" % [r["below_at"]])
	var names: Array = (r["entered"] as Array).map(func(e: Dictionary) -> String: return String(e["biome"]))
	print("CROSSING pace %.1f tiles/s per 30 ft" % MoveStats.pace())
	print("CROSSING %s seed=%d biomes=%d %s crossings=%d %s time=%.0f s (%.1f min) ticks=%d legs=%d below=%.1f digs=%d tiles_changed=%s walked in %d ms" % [
		"PASS" if faults.is_empty() else "FAIL", sd, names.size(), ">".join(names), (r["crossed"] as Array).size(), kinds, r["seconds"], float(r["seconds"]) / 60.0, r["ticks"], r["legs"], r["below"],
		r["digs"], r["tiles_changed"], Time.get_ticks_msec() - t0])
	quit(0 if faults.is_empty() else 1)

## Each surface settlement's street, west to east, with the time the walker first stood in its
## middle column, and the walk between neighbours; the spawn is the first settled surface place
## (game/main.gd spawn_for), so its neighbours are the first towns a new player walks to.
func _towns(world: TileWorld, r: Dictionary) -> void:
	var reached: Array = r["reached"]
	var spawn: Vector2 = load("res://game/main.gd").spawn_for(world, Vector2.ZERO)
	var rows: Array = []
	var all := Places.all(world)
	for k: String in all:
		var p: Dictionary = all[k]
		if not p.has("street") or String(p.get("tier", "")) == "":
			continue
		var st: Array = p["street"]
		var mx := (int(st[0]) + int(st[1])) / 2
		var t := -1.0
		for x in range(mx, mini(mx + 40, reached.size())):
			if float(reached[x]) >= 0.0:
				t = float(reached[x])
				break
		rows.append({"site": k, "x": mx, "y": int(st[2]), "t": t, "tier": p["tier"],
			"spawn": spawn.x >= int(st[0]) and spawn.x <= int(st[1]) and absf(spawn.y - int(st[2])) < 4.0})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["x"]) < int(b["x"]))
	for i in rows.size():
		var row: Dictionary = rows[i]
		var gap := ""
		if i > 0 and float(row["t"]) >= 0.0 and float(rows[i - 1]["t"]) >= 0.0:
			gap = "  %5.1f s (%d tiles) from the last" % [float(row["t"]) - float(rows[i - 1]["t"]), int(row["x"]) - int(rows[i - 1]["x"])]
		print("  town %-4s %-8s x=%-5d t=%6.1f s%s%s" % [row["site"], row["tier"], row["x"], row["t"], gap, "  <- spawn" if row["spawn"] else ""])

func _descent(world: TileWorld, gen: String, sd: int) -> void:
	var t0 := Time.get_ticks_msec()
	var r := DescentBot.descent(world)
	print("DESCENT pace %.1f tiles/s per 30 ft" % MoveStats.pace())
	print("DESCENT gen=%s seed=%d %dx%d from %s to %s" % [gen, sd, world.width, world.height, r["from"], r["to"]])
	for name: String in ["down", "back"]:
		var leg: Dictionary = r.get(name, {})
		print("  %-4s %s in %.0f s on screen (%d path nodes, planned in %d ms, %d legs planned again, %d rewinds)%s" % [name, "ok" if leg.get("ok", false) else "STOPPED",
			float(leg.get("seconds", 0.0)), int(leg.get("nodes", 0)), int(leg.get("plan_ms", 0)), int(leg.get("retries", 0)), int(leg.get("rewinds", 0)),
			"" if leg.get("ok", false) else ": " + String(leg.get("why", ""))])
		print("       bands   %s" % " > ".join(leg.get("bands", [])))
		print("       regions %s" % " > ".join(leg.get("regions", [])))
		print("       ways    %s" % [leg.get("ways", [])])
		print("       on      %s (ticks), deepest row %d" % [leg.get("crossings", {}), int(leg.get("deepest", 0.0))])
	var d: Dictionary = world.meta.get("descent", {})
	for seg: Dictionary in BiomeIds.strip(world.meta):
		var kinds := {}
		for wy: Dictionary in d.get("ways", []):
			var mid := (int(wy["x0"]) + int(wy["x1"])) / 2
			if mid >= int(seg["x0"]) and mid <= int(seg["x1"]):
				kinds[wy["kind"]] = int(kinds.get(wy["kind"], 0)) + 1
		print("  ways in from the %-8s %s" % [seg["biome"], kinds])
	var all := {}
	for wy: Dictionary in d.get("ways", []):
		all[wy["kind"]] = int(all.get(wy["kind"], 0)) + 1
	var faults := DescentBot.faults(world, r)
	for f: String in faults:
		print("  FAULT %s" % f)
	print("DESCENT %s seed=%d bands=%s ways=%s kinds_in_world=%d time=%.0f s (%.1f min) digs=%d tiles_changed=%s walked in %d ms" % [
		"PASS" if faults.is_empty() else "FAIL", sd, " > ".join(r.get("down", {}).get("bands", [])), r.get("ways", {}), all.size(),
		float(r.get("seconds", 0.0)), float(r.get("seconds", 0.0)) / 60.0, r["digs"], r["tiles_changed"], Time.get_ticks_msec() - t0])
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
