## The underground regions (M6 track deep, item 1): a medium world's plan holds every
## underground biome in its band, a dev world carries them (rock, floor, light, sites, meta),
## the deep lake is a sealed body of water swum in, the lava lies in pools with bridges, and
## none of it reaches a world under min_world. docs/tracks/deep.md.
extends RefCounted

const GC := preload("res://core/world/worldgen/gen_context.gd")
const Deep := preload("res://core/world/worldgen/stage_deep.gd")
const Barriers := preload("res://tests/test_barriers.gd")

const UNDER := ["fungal", "crystal", "deep_lake", "magma"]

func run(t: TestLog) -> void:
	_tiles(t)
	_plan(t)
	var w := WorldGen.generate_named("dev", 2)
	_meta(t, w)
	_rock(t, w)
	_lake(t, w)
	_lava(t, w)
	_glow(t, w)
	_sites(t, w)
	var again := WorldGen.generate_named("dev", 2)
	t.eq(again.content_hash(), w.content_hash(), "a pure function of the seed")
	t.eq(JSON.stringify(again.meta["biomes"]), JSON.stringify(w.meta["biomes"]), "and so are its regions")
	var small := WorldGen.generate(1024, 512, 5)
	t.eq(BiomeIds.regions(small.meta).size(), 0, "a world under min_world has no underground regions")
	t.eq(small.meta["descent"]["lake"], {}, "nor a lake")

## Appended, never renumbered; lights give light.
func _tiles(t: TestLog) -> void:
	var want := {"spore_stone": 34, "mycelium": 35, "glow_cap": 36, "crystal_stone": 37, "geode_floor": 38, "crystal_cluster": 39,
		"lake_stone": 40, "shore_sand": 41, "silt": 42, "basalt": 43, "ash": 44, "obsidian": 45, "lumen_moss": 46, "lava": 120, "lava_bridge": 121}
	for n: String in want:
		t.eq(TileDefs.id(n), want[n], "%s is tile %d" % [n, want[n]])
	for n: String in ["glow_cap", "crystal_cluster", "lumen_moss", "lava"]:
		t.check(TileDefs.emit[TileDefs.id(n)] > 0 and TileDefs.solid[TileDefs.id(n)] == 0, "%s gives light and stands in an open cell" % n)
	t.check(TileDefs.burn[TileDefs.id("lava")] != 0 and TileDefs.hardness[TileDefs.id("lava")] < 0.0, "lava burns and cannot be dug")
	t.check(TileDefs.id("lava") >= 96 and TileDefs.id("lava_bridge") >= 96 and TileDefs.id("water") >= 96, "lava, its bridge and water are tiles the passages stage never cuts")
	for n: String in ["spore_wall", "crystal_wall", "lake_wall", "basalt_wall"]:
		t.check(TileDefs.wall_id(n) >= 18 and TileDefs.wall_id(n) <= 21, "%s is a wall" % n)
	for n: String in ["spore_stone", "mycelium", "crystal_stone", "geode_floor", "lake_stone", "shore_sand", "silt", "basalt", "ash", "obsidian"]:
		t.eq(Items.tile_drop(TileDefs.id(n)), "tile:rubble", "digging %s gives rubble" % n)
	for b: String in UNDER:
		t.check(Array(BiomeIds.generated("underground")).has(b), "%s is marked generated" % b)

## Medium's plan: one region at least of each, in its band, the band tiled end to end.
func _plan(t: TestLog) -> void:
	for sd: int in [1, 2, 3]:
		var c := GC.new(8192, 2560, sd, {})
		WorldGen.Biomes.run(c, WorldGen.rng_for(sd, "biomes"))
		Deep.plan(c, WorldGen.rng_for(sd, "regions"))
		var seen := {}
		for band: String in ["deeps", "nadir"]:
			var next := 0
			for r: Dictionary in c.regions:
				if r["band"] != band:
					continue
				t.eq(int(r["x0"]), next, "medium seed %d: %s's regions run on without a gap (%s at %d)" % [sd, band, r["biome"], r["x0"]])
				next = int(r["x1"]) + 1
				t.eq([int(r["y0"]), int(r["y1"])], [int(c.bands[band][0]), int(c.bands[band][1])], "medium seed %d: %s lies in its band" % [sd, r["biome"]])
				seen[r["biome"]] = band
			t.eq(next, c.w, "medium seed %d: %s's regions reach the east end" % [sd, band])
		for b: String in UNDER:
			t.check(seen.has(b), "medium seed %d has %s" % [sd, b])
		t.eq(seen.get("magma", ""), "nadir", "medium seed %d: the magma is in the nadir" % sd)
		for b: String in ["fungal", "crystal", "deep_lake"]:
			t.eq(seen.get(b, ""), "deeps", "medium seed %d: %s is in the deeps" % [sd, b])
		var again := GC.new(8192, 2560, sd, {})
		WorldGen.Biomes.run(again, WorldGen.rng_for(sd, "biomes"))
		Deep.plan(again, WorldGen.rng_for(sd, "regions"))
		t.eq(again.regions, c.regions, "medium seed %d: the plan is a pure function of the seed" % sd)

func _meta(t: TestLog, w: TileWorld) -> void:
	var regs := BiomeIds.regions(w.meta)
	t.eq(BiomeIds.strip(w.meta).size() + regs.size(), (w.meta["biomes"] as Array).size(), "meta.biomes is the surface strip and the underground regions")
	t.eq(BiomeIds.strip(w.meta).size(), 5, "the strip is the five surface biomes")
	var kinds := {}
	for r: Dictionary in regs:
		for k: String in ["band", "x0", "x1", "y0", "y1", "biome", "name"]:
			t.check(r.has(k), "region row has %s" % k)
		t.check(BiomeIds.has(r["biome"]), "%s is canonical" % r["biome"])
		t.check(String(r.get("name", "")).begins_with("the "), "%s is named (%s)" % [r["biome"], r.get("name", "")])
		kinds[r["biome"]] = true
	for b: String in UNDER:
		t.check(kinds.has(b), "dev seed 2 has %s" % b)
	var mid: Dictionary = regs[regs.size() / 2]
	var at := BiomeIds.region_at(w.meta, (float(mid["x0"]) + float(mid["x1"])) * 0.5, (float(mid["y0"]) + float(mid["y1"])) * 0.5)
	t.eq(at, mid, "region_at finds the row at a cell")
	t.eq(BiomeIds.region_at(w.meta, 100.0, float(w.meta["bands"]["surface"][0]) + 5.0), {}, "and none on the surface")

## A region's rock is its own, and its open floors wear its floor tile.
func _rock(t: TestLog, w: TileWorld) -> void:
	var g := WorldGen.grids(w)
	var fg: PackedByteArray = g[0]
	for r: Dictionary in BiomeIds.regions(w.meta):
		if r["biome"] == "underdark":
			continue
		var d := Deep.def(String(r["biome"]))
		var own := TileDefs.id(String(d["rock"]))
		var flo := TileDefs.id(String(d["floor"]))
		var slate := TileDefs.id("slate")
		var n_own := 0
		var n_slate := 0
		var n_floor := 0
		var seam := 40
		for y in range(int(r["y0"]) + 4, int(r["y1"]) - 4, 3):
			for x in range(int(r["x0"]) + seam, int(r["x1"]) - seam, 3):
				var id := fg[x + y * w.width]
				if id == own:
					n_own += 1
				elif id == slate:
					n_slate += 1
				elif id == flo:
					n_floor += 1
		t.check(n_own > n_slate * 10, "%s at %d: its own rock (%d), not slate (%d)" % [r["biome"], r["x0"], n_own, n_slate])
		t.check(n_floor > 0, "%s at %d: floors of %s (%d)" % [r["biome"], r["x0"], d["floor"], n_floor])

## The lake: water swum (liquid) and sealed, beaches at both ends, a shore path walked both ways.
func _lake(t: TestLog, w: TileWorld) -> void:
	var lk: Dictionary = w.meta["descent"]["lake"]
	t.check(not lk.is_empty(), "dev seed 2 has a deep lake")
	if lk.is_empty():
		return
	var water := TileDefs.id("water")
	var cells := 0
	var leaks := 0
	var dry := 0
	for x in range(int(lk["x0"]), int(lk["x1"]) + 1):
		for y in range(int(lk["bed"]), int(lk["water"]) + 1):
			if w.get_fg(x, y) != water:
				continue
			cells += 1
			if w.get_liquid(x, y) & 15 != 15:
				dry += 1
			for o: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1)]:
				var n := w.get_fg(x + o.x, y + o.y)
				if n != water and not w.is_solid(x + o.x, y + o.y):
					leaks += 1
	t.check(cells > 200, "the lake holds water (%d cells)" % cells)
	t.eq(dry, 0, "every water cell holds liquid, so a body swims it")
	t.eq(leaks, 0, "the water is sealed: rock or water beside and under every cell")
	t.check(int(lk["water"]) - int(lk["bed"]) >= 8, "deep enough to swim (%d rows)" % (int(lk["water"]) - int(lk["bed"])))
	for x: int in [int(lk["x0"]) + 2, int(lk["x1"]) - 2]:
		t.check(w.is_solid(x, int(lk["water"]) + 4) and not w.is_solid(x, int(lk["water"]) + 5), "a beach above the water at %d" % x)
	t.eq(BiomeIds.region_at(w.meta, float(lk["x0"] + lk["x1"]) * 0.5, float(lk["water"])).get("biome", ""), "deep_lake", "the lake lies in the deep lake's region")
	var path: Array = []
	for q: Array in lk["crossing"]["cells"]:
		path.append(Vector2i(int(q[0]), int(q[1])))
	var bad: Array = []
	Barriers._way(w, NavMaps.stats("medium"), path, "the shore path", bad)
	t.eq(bad, [], "the shore path round the lake is walked both ways by the real controller")
	t.eq((lk.get("well", []) as Array).size(), 3, "a well climbs from the shore path to the deep road over it")

## Lava: pools in the tube's floor, sealed, a bridge over every one a walker cannot jump.
func _lava(t: TestLog, w: TileWorld) -> void:
	var lv: Array = w.meta["descent"]["lava"]
	t.check(not lv.is_empty(), "dev seed 2 has a lava tube")
	var lava := TileDefs.id("lava")
	var deck := TileDefs.id("lava_bridge")
	var pools := 0
	for tube: Dictionary in lv:
		for p: Dictionary in tube["pools"]:
			pools += 1
			var cells := 0
			var open := 0
			for x in range(int(p["x0"]), int(p["x1"]) + 1):
				for y in range(int(p["y"]) - 4, int(p["y"])):
					if w.get_fg(x, y) == lava:
						cells += 1
						if not w.is_solid(x, y - 1) and w.get_fg(x, y - 1) != lava:
							open += 1
				if bool(p["bridge"]):
					t.eq(w.get_fg(x, int(p["y"]) - 1), deck, "a deck over the pool at %d" % x)
			t.check(cells > 0, "the pool at %d holds lava" % p["x0"])
			t.eq(open, 0, "nothing under the pool at %d but rock" % p["x0"])
			t.check(bool(p["bridge"]) or int(p["x1"]) - int(p["x0"]) + 1 <= 3, "a pool wider than a jump has a bridge (%d)" % p["x0"])
			for x: int in [int(p["x0"]) - 1, int(p["x1"]) + 1]:
				t.check(w.is_solid(x, int(p["y"]) - 1), "the floor goes on beside the pool at %d" % x)
		for b: Dictionary in tube["bridges"]:
			var path: Array = []
			for q: Array in b["cells"]:
				path.append(Vector2i(int(q[0]), int(q[1])))
			var bad: Array = []
			Barriers._way(w, NavMaps.stats("medium"), path, "the bridge at %d" % b["x0"], bad)
			t.eq(bad, [], "the lava bridge at %d is walked both ways" % b["x0"])
		t.eq(BiomeIds.region_at(w.meta, float(tube["x0"] + tube["x1"]) * 0.5, 30.0).get("biome", ""), "magma", "the tube lies in the magma")
	t.check(pools > 0, "and pools in it (%d)" % pools)
	var nf: Array = w.meta["descent"]["nadir"]
	t.eq(nf.size(), 2, "the nadir floor is recorded")
	if nf.size() == 2:
		t.eq(w.meta["bands"].keys().filter(func(k: String) -> bool: return int(nf[1]) >= int(w.meta["bands"][k][0]) and int(nf[1]) <= int(w.meta["bands"][k][1])), ["nadir"], "and it is in the nadir")
		t.check(w.is_solid(int(nf[0]), int(nf[1]) - 1) and not w.is_solid(int(nf[0]), int(nf[1])), "a body stands there")

## Each region's own light, on open cells in the region.
func _glow(t: TestLog, w: TileWorld) -> void:
	var g := WorldGen.grids(w)
	var fg: PackedByteArray = g[0]
	var counts := {}
	for r: Dictionary in BiomeIds.regions(w.meta):
		var gd: Dictionary = Deep.def(String(r["biome"])).get("glow", {})
		if gd.is_empty():
			continue
		var id := TileDefs.id(String(gd["tile"]))
		var n := 0
		for y in range(int(r["y0"]), int(r["y1"]) + 1):
			var row := y * w.width
			for x in range(int(r["x0"]), int(r["x1"]) + 1):
				if fg[row + x] == id:
					n += 1
		counts[r["biome"]] = int(counts.get(r["biome"], 0)) + n
	for b: String in ["fungal", "crystal", "deep_lake"]:
		t.check(int(counts.get(b, 0)) >= 10, "%s has its lights (%d)" % [b, counts.get(b, 0)])

## A deep site takes the region under it.
func _sites(t: TestLog, w: TileWorld) -> void:
	var sim := WorldSim.from_meta(w.meta, 2)
	for s: Dictionary in w.meta["sites"]:
		if not String(s["band"]) in ["deeps", "nadir"]:
			continue
		var r := BiomeIds.region_at(w.meta, float(s["x"]), float(s["y"]))
		t.eq(s["biome"], r.get("biome", "underdark"), "site %d (%s) has the region under it" % [s["id"], s["kind"]])
		t.eq(sim.site_by_id[int(s["id"])].biome, s["biome"], "and the sim's site %d agrees" % s["id"])
