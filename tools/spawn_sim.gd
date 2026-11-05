## What the spawn director makes around a player standing or walking in each depth band.
##   godot --headless -s res://tools/spawn_sim.gd -- [seed=4] [size=1024x512] [minutes=3]
##       [walk=1] [bands=surface,caves,deeps,nadir] [night=0|1] [perf=1]
## Prints per band: packs (creatures and ranks), pack sizes, rank mix, CR alive over time, and
## host tick cost (avg / p99) with the monsters it made (perf=1 also nav numbers).
extends SceneTree

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var seed_value := int(args.get("seed", 4))
	var size := String(args.get("size", "1024x512")).split("x")
	var minutes := float(args.get("minutes", 3))
	var walk := String(args.get("walk", "1")) != "0"
	var bands := String(args.get("bands", "surface,caves,deeps,nadir")).split(",")
	var world := WorldGen.generate(int(size[0]), int(size[1]), seed_value)
	for band in bands:
		var nights: Array = [true]
		if args.has("night"):
			nights = [String(args["night"]) == "1"]
		elif band in ["surface", "sky"]:
			nights = [false, true]
		for night: bool in nights:
			_run(WorldGen.generate(int(size[0]), int(size[1]), seed_value), band, night, minutes, walk)
	quit()

func _run(world: TileWorld, band: String, night: bool, minutes: float, walk: bool) -> void:
	var host := WorldHost.new(world)
	Dice.rng = host.rng
	if night:
		host.clock.ticks += 14 * WorldClock.TICKS_PER_HOUR      # 22:00
	host.add_system(CombatSystem.new())
	var ms := MonstersSystem.new()
	host.add_system(ms)
	ms.director_enabled = 1
	ms.lairs_enabled = false
	ms.director.keep_log = true
	var start := _spot(world, band)
	var p := host.add_player("walker", 2, {"class": "fighter"})
	p.body.pos = start
	p.combatant.stats.max_hp = 99999
	p.combatant.stats.current_hp = 99999
	var ticks := int(minutes * 60.0 * K.TICK_HZ)
	var usec := PackedInt32Array()
	var cr_samples: Array = []
	var dir := 1.0
	for i in ticks:
		if walk and i % 15 == 0:
			# walk along the band: step a tile, turn at the ends
			var nx := p.body.pos.x + dir * 2.0
			if nx < 100 or nx > world.width - 100:
				dir = -dir
			var q := ms.director._stand_near(host, Vector2(nx, p.body.pos.y + 2.0), "")
			if q != Vector2.INF and absf(q.y - p.body.pos.y) < 6.0:
				p.body.pos = q
			else:
				dir = -dir
		var t0 := Time.get_ticks_usec()
		host.tick()
		usec.append(Time.get_ticks_usec() - t0)
		if i % (K.TICK_HZ * 15) == 0:
			var c: Dictionary = ms.director.group_cost([p])
			cr_samples.append("%.1f/%d" % [c["cost"], c["n"]])
	var ranks := {}
	var sizes: Array = []
	var kinds := {}
	for l: Dictionary in ms.director.log:
		sizes.append((l["pack"] as PackedStringArray).size())
		for s: String in l["pack"]:
			var rk := s.get_slice("(", 1).trim_suffix(")")
			ranks[rk] = int(ranks.get(rk, 0)) + 1
			var k := s.get_slice("(", 0)
			kinds[k] = int(kinds.get(k, 0)) + 1
	var sorted := usec.duplicate()
	sorted.sort()
	var avg := 0.0
	for u in usec:
		avg += u
	avg /= maxf(usec.size(), 1)
	print("\n== %s %s, %.0f min %s, from %s ==" % [band, "night" if night else "day", minutes, "walking" if walk else "standing", start])
	print("packs %d, creatures %d, despawned %d, raiders %d; pack sizes %s" % [ms.director.stats["packs"], ms.director.stats["spawned"],
		ms.director.stats["despawned"], ms.director.stats["raiders"], sizes])
	print("ranks %s" % ranks)
	print("kinds %s" % kinds)
	print("CR alive / count every 15 s: %s" % " ".join(cr_samples))
	print("first packs:")
	for l: Dictionary in ms.director.log.slice(0, 8):
		print("  t=%5.1f %s at %s: %s" % [l["t"], l["band"], l["at"], ", ".join(l["pack"])])
	print("host tick: avg %.0f us, p99 %d us, max %d us; alive now %d; plans %d (%.2f ms each), plan fails %d" % [avg,
		sorted[int(sorted.size() * 0.99)], sorted[sorted.size() - 1], ms.alive_count(), ms.stats["plans"],
		ms.stats["plan_usec"] / 1000.0 / maxf(ms.stats["plans"], 1), ms.stats["plan_fail"]])

static func _spot(w: TileWorld, band: String) -> Vector2:
	var r := RandomNumberGenerator.new()
	r.seed = 99
	if band == "surface" or band == "sky":
		var x := w.width / 3
		return Vector2(x + 0.5, int(w.meta["surface"][x]) + 1)
	var rg: Array = w.meta["bands"][band]
	for k in 20000:
		var x := r.randi_range(100, w.width - 100)
		var y := r.randi_range(int(rg[0]) + 4, int(rg[1]) - 4)
		if not w.is_solid(x, y) and not w.is_solid(x + 1, y) and not w.is_solid(x, y + 1) and not w.is_solid(x, y + 2) \
				and not w.is_solid(x + 1, y + 2) and w.is_solid(x, y - 1):
			return Vector2(x + 1.0, y)
	return Vector2(w.width / 2.0, int(rg[0]) + 10)
