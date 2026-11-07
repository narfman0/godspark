## The sim and the spawn director read the underground regions (M6 track deep, item 4): the
## director hunts by the region under a spot, a spot in the deep lake's water takes a water pack,
## no pack stands in lava, and each region hunts unlike its band's plain underdark.
extends RefCounted

func run(t: TestLog) -> void:
	var w := WorldGen.generate_named("dev", 2)
	var host := WorldHost.new(w)
	var ms := MonstersSystem.new()
	ms.director_enabled = 0
	ms.lairs_enabled = false
	host.add_system(ms)
	var dir: SpawnDirector = ms.director
	dir.rng.seed = 7
	for r: Dictionary in BiomeIds.regions(w.meta):
		var x := (float(r["x0"]) + float(r["x1"])) * 0.5
		var y := (float(r["y0"]) + float(r["y1"])) * 0.5
		t.eq(dir.biome_at(host, x, String(r["band"]), y), r["biome"], "the director hunts the %s at (%d, %d)" % [r["biome"], int(x), int(y)])
	t.eq(dir.biome_at(host, 100.0, "deeps"), "underdark", "without a row it reads the band's biome, as before")
	# the lake: its water is a water spot
	var lk: Dictionary = w.meta["descent"]["lake"]
	var mid := Vector2((float(lk["x0"]) + float(lk["x1"])) * 0.5, float(lk["bed"]) + 1.0)
	t.check(SpawnDirector.in_water(w, mid), "the lake's bed is under water")
	t.check(not SpawnDirector.in_water(w, Vector2(float(lk["x0"]) + 3.5, float(lk["water"]) + 5.0)), "its beach is not")
	var table: Dictionary = Ecology.spawning()["bands"]["deeps"]["any"]
	var seen := {}
	for i in 200:
		for m: Dictionary in dir.build_pack(host, "deeps", "deep_lake", table, float(table["pack_cr"]), true):
			seen[m["slug"]] = true
	t.check(not seen.is_empty(), "the lake's water has packs (%s)" % [seen.keys()])
	for s: String in seen:
		t.eq(String(Ecology.row(s).get("medium", "")), "water", "%s lives in water" % s)
	# on by default since M6 integration: the lake's lair site in the deep lake's region, its water
	# near enough for a creature of the water (the aboleth) to come out in it (LairLink.water_near:
	# 60 x 30 tiles), and a way per sinkhole with its rope as its path
	lk = w.meta["descent"]["lake"]
	var lair := int(lk.get("lair", -1))
	t.check(lair >= 0, "the lake has a lair site")
	if lair >= 0:
		var site: Dictionary = (w.meta["sites"] as Array).filter(func(x: Dictionary) -> bool: return int(x["id"]) == lair)[0]
		t.eq([site["kind"], site["biome"]], ["lair", "deep_lake"], "a lair in the deep lake")
		var wet := LairLink.water_near(host, Vector2(float(site["x"]) + 0.5, float(site["y"])))
		t.check(wet != Vector2.INF, "with deep water within 60 x 30 tiles (%s)" % wet)
	# meta.ways: each sinkhole, with its rope as its path, and a link route that keeps it
	var ways: Array = w.meta.get("ways", [])
	t.eq(ways.size(), (w.meta["descent"]["sinkholes"] as Array).size(), "a way in meta.ways per sinkhole")
	for wy: Dictionary in ways:
		var path: Array = wy.get("path", [])
		t.check(path.size() > 20 and path[0] == wy["top"] and path[-1] == wy["bottom"], "%s's path runs from its top to its bottom (%d cells)" % [wy["kind"], path.size()])
	# the sim's lair there favours a lake-only row, and its creature really has water
	var abo := 0
	for sd in 8:
		var row := {"biome": "deep_lake", "band": "deeps"}
		var r := RandomNumberGenerator.new()
		r.seed = sd * 31 + 5
		if WorldSim._pick_lair(SimData.lairs["deeps"], row, r)["id"] == "aboleth":
			abo += 1
	t.check(abo >= 5, "the aboleth is the lake's usual lair (%d of 8 draws)" % abo)
	var linked := 0
	for r: Dictionary in host.sim.routes:
		if String(r.get("way", "")) == "sinkhole":
			linked += 1
			t.check((r.get("path", []) as Array).size() > 20, "the sim's link route %d keeps the sinkhole's path" % r["id"])
	t.check(linked > 0, "the sim links a sinkhole (%d)" % linked)
	w = WorldGen.generate_named("dev", 2)
	host = WorldHost.new(w)
	ms = MonstersSystem.new()
	ms.director_enabled = 0
	ms.lairs_enabled = false
	host.add_system(ms)
	dir = ms.director
	dir.rng.seed = 7
	# each region's packs are its own creatures
	for b: String in ["fungal", "crystal", "deep_lake"]:
		var own := {}
		for i in 200:
			for m: Dictionary in dir.build_pack(host, "deeps", b, table, float(table["pack_cr"])):
				own[m["slug"]] = true
		t.check(own.size() >= 2, "the %s hunts with several kinds (%s)" % [b, own.keys()])
		for s: String in own:
			var row := Ecology.row(s)
			var lead_ok := b in (row["biomes"] as Array)
			if not lead_ok:      # a leader's followers come with it
				for l: String in Ecology.habitats():
					if not l.begins_with("_") and s in (Ecology.row(l).get("leader_of", []) as Array) and b in (Ecology.row(l)["biomes"] as Array):
						lead_ok = true
			t.check(lead_ok, "%s hunts in the %s" % [s, b])
	var nadir: Dictionary = Ecology.spawning()["bands"]["nadir"]["any"]
	var fire := 0
	for i in 300:
		for m: Dictionary in dir.build_pack(host, "nadir", "magma", nadir, float(nadir["pack_cr"])):
			if String(m["slug"]) in ["fire-elemental", "salamander", "fire-giant", "magmin", "magma-mephit", "azer-sentinel", "hell-hound"]:
				fire += 1
	t.check(fire > 100, "the magma's packs are fire creatures (%d)" % fire)
	# no pack stands in lava
	var tube: Dictionary = (w.meta["descent"]["lava"] as Array)[0]
	var p: Dictionary = (tube["pools"] as Array)[0]
	var bad := 0
	for x in range(int(p["x0"]) - 2, int(p["x1"]) + 3):
		var at := dir._stand_near(host, Vector2(x + 0.5, float(p["y"]) + 1.0), "")
		if at != Vector2.INF and SpawnDirector._burns(w, floori(at.x - 1.0), floori(at.y), 2, 3):
			bad += 1
	t.eq(bad, 0, "no spawn spot stands in the lava")
