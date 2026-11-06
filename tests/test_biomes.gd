## The climate journey and each biome's ground: orders, widths, heights, tiles, seams.
extends RefCounted

const GenContext := preload("res://core/world/worldgen/gen_context.gd")
const StageBiomes := preload("res://core/world/worldgen/stage_biomes.gd")
const StageSurface := preload("res://core/world/worldgen/stage_surface.gd")
const StageBarriers := preload("res://core/world/worldgen/stage_barriers.gd")
const FIVE := ["desert", "forest", "meadow", "mountain", "swamp"]

func run(t: TestLog) -> void:
	_journey(t)
	_heights(t)
	_ground(t)
	_seams(t)
	_tables(t)
	_on_a_thread(t)

## The game generates behind a loading screen: on a thread the world comes out the same.
func _on_a_thread(t: TestLog) -> void:
	var here := WorldGen.generate(512, 256, 11)
	var th := Thread.new()
	th.start(func() -> TileWorld: return WorldGen.generate(512, 256, 11))
	var w: TileWorld = th.wait_to_finish()
	t.eq(w.content_hash(), here.content_hash(), "a thread makes the same world")
	t.eq(JSON.stringify(w.meta), JSON.stringify(here.meta), "and the same meta")
	t.eq(WorldGen.stage_index, WorldGen.STAGES.size(), "stage_index ends past the last stage")
	WorldGen.cancel = true
	t.eq(WorldGen.generate(512, 256, 11), null, "cancel stops a run")
	WorldGen.cancel = false

## Just the biome and surface stages of a world.
func _plan(w: int, h: int, sd: int) -> GenContext:
	var c := GenContext.new(w, h, sd, {})
	StageBiomes.run(c, WorldGen.rng_for(sd, "biomes"))
	StageSurface.run(c, WorldGen.rng_for(sd, "surface"))
	return c

func _journey(t: TestLog) -> void:
	var climate: Dictionary = StageBiomes.data()["climate"]
	var orders := {}
	for o: Dictionary in climate["orders"]:
		var names: Array = o["biomes"]
		orders[o["name"]] = names
		var sorted := names.duplicate()
		sorted.sort()
		t.eq(sorted, FIVE, "order %s names each biome once" % o["name"])
		t.check(names[0] != names[-1], "order %s: the two ends differ" % o["name"])
	t.eq(orders.size(), 2, "two orders")
	var min_share := float(climate["min_share"])
	var seen := {}
	var firsts := {}
	var thinnest := 1.0
	for size: Vector2i in [Vector2i(512, 256), Vector2i(1024, 512), Vector2i(2048, 1024), Vector2i(8192, 2560)]:
		for sd in range(1, 41):
			var c := GenContext.new(size.x, size.y, sd, {})
			StageBiomes.run(c, WorldGen.rng_for(sd, "biomes"))
			var label := "%dx%d seed %d" % [size.x, size.y, sd]
			var got: Array = c.biomes.map(func(s: Dictionary) -> String: return s["biome"])
			t.eq(got, orders[c.climate["order"]], "%s lies in its order" % label)
			seen[c.climate["order"]] = int(seen.get(c.climate["order"], 0)) + 1
			var next := 0
			var last_temp := -1.0
			for seg: Dictionary in c.biomes:
				t.eq(int(seg["x0"]), next, "%s: the strip has no gaps" % label)
				next = int(seg["x1"]) + 1
				t.check(float(seg["temp"]) > last_temp, "%s: warmer across the width" % label)
				last_temp = seg["temp"]
				var share := float(int(seg["x1"]) - int(seg["x0"]) + 1) / size.x
				thinnest = minf(thinnest, share)
				t.check(share >= min_share - 2.0 / size.x, "%s: %s is no sliver (%.3f)" % [label, seg["biome"], share])
				t.eq(c.col_biome[(int(seg["x0"]) + int(seg["x1"])) / 2], c.biome_defs.map(func(d: Dictionary) -> String:
						return d["name"]).find(seg["biome"]), "%s: columns match the strip" % label)
			t.eq(next, size.x, "%s: the strip covers the width" % label)
			firsts[str(c.biomes[0]["x1"])] = true
	t.eq(seen.size(), 2, "worlds take both orders (%s)" % seen)
	t.check(int(seen.values()[0]) >= 40 and int(seen.values()[1]) >= 40, "both orders are common (%s)" % seen)
	t.check(firsts.size() > 30, "widths vary between worlds (%d)" % firsts.size())
	print("  thinnest biome over the sweep: %.1f%%" % (thinnest * 100.0))
	# a pure function of the seed
	var a := GenContext.new(1024, 512, 77, {})
	var b := GenContext.new(1024, 512, 77, {})
	StageBiomes.run(a, WorldGen.rng_for(77, "biomes"))
	StageBiomes.run(b, WorldGen.rng_for(77, "biomes"))
	t.eq(a.biomes, b.biomes, "the same seed gives the same strip")
	t.eq(a.col_biome, b.col_biome, "the same seed gives the same columns")

func _heights(t: TestLog) -> void:
	var tall := 0
	var low := 0
	var n := 0
	for size: Vector2i in [Vector2i(2048, 1024), Vector2i(8192, 2560)]:
		for sd in [1, 2, 3, 4, 5, 6]:
			var c := _plan(size.x, size.y, sd)
			var mean := {}
			var peak := {}
			for seg: Dictionary in c.biomes:
				var tot := 0
				var top := 0
				for x in range(int(seg["x0"]), int(seg["x1"]) + 1):
					tot += c.ground[x]
					top = maxi(top, c.ground[x])
				mean[seg["biome"]] = float(tot) / (int(seg["x1"]) - int(seg["x0"]) + 1)
				peak[seg["biome"]] = top
			n += 1
			var names: Array = mean.keys()
			names.sort_custom(func(p: String, q: String) -> bool: return mean[p] > mean[q])
			if names[0] == "mountain" and peak["mountain"] >= peak.values().max():
				tall += 1
			if names[-1] == "swamp":
				low += 1
			# walkable: the step limit holds everywhere, and on the mountain it is what a body can
			# climb. A range's walls are cliffs on purpose: there the pass under them is measured.
			var worst := 0
			for x in range(1, c.w):
				var step := int(c.biome_defs[c.col_biome[x]]["height"]["step"])
				var d := absi(StageBarriers.rock_top(c, x) - StageBarriers.rock_top(c, x - 1))
				worst = maxi(worst, d - step)
			t.check(worst <= 1, "%dx%d seed %d: neighbouring columns keep to the step (over by %d)" % [size.x, size.y, sd, worst])
			var band: Array = c.bands["surface"]
			var flat_tops := 0
			for x in c.w:
				if StageBarriers.rock_top(c, x) >= int(band[1]) - 4:
					flat_tops += 1
			t.check(flat_tops < c.w / 50, "%dx%d seed %d: heights are not cut flat at the band top (%d)" % [size.x, size.y, sd, flat_tops])
	t.check(tall >= n - 1, "the mountain stands highest (%d/%d)" % [tall, n])
	t.check(low >= n - 1, "the swamp lies lowest (%d/%d)" % [low, n])

## A generated world's ground before towns and roads: each biome's own tiles.
func _ground(t: TestLog) -> void:
	var w := WorldGen.generate(1024, 512, 5, {"stop_after": "finish"})
	var top_ok := 0
	var tops := 0
	var surf: Array = w.meta["surface"]
	var defs := StageBiomes.load_defs()
	var by_name := {}
	for d: Dictionary in defs:
		by_name[d["name"]] = d
	var seam := 24
	for seg: Dictionary in w.meta["biomes"]:
		var d: Dictionary = by_name[seg["biome"]]
		var seen_top := {}
		var soil := 0
		var rock := 0
		for x in range(int(seg["x0"]) + seam, int(seg["x1"]) - seam):
			var s := int(surf[x])
			var name := TileDefs.names[w.get_fg(x, s)]
			seen_top[name] = int(seen_top.get(name, 0)) + 1
			tops += 1
			if name == d["top"] or name == d.get("snow", {}).get("tile", ""):
				top_ok += 1
			if w.get_fg(x, s - 1) == TileDefs.id(d["soil"]):
				soil += 1
			for y in range(s - 1, int(w.meta["bands"]["surface"][0]), -4):
				if w.get_fg(x, y) == TileDefs.id(d["stone"]):
					rock += 1
		t.check(seen_top.has(d["top"]), "%s shows its top tile (%s)" % [seg["biome"], seen_top])
		t.check(soil > 0, "%s has its soil" % seg["biome"])
		t.check(rock > 0, "%s has its stone" % seg["biome"])
	t.check(top_ok * 10 >= tops * 5, "most open ground wears its biome's top (%d/%d)" % [top_ok, tops])

## Seams: no border is a vertical line, in the skin or the rock.
func _seams(t: TestLog) -> void:
	var w := WorldGen.generate(1024, 512, 5, {"stop_after": "finish"})
	var defs := StageBiomes.load_defs()
	var by_name := {}
	for d: Dictionary in defs:
		by_name[d["name"]] = d
	var strip: Array = w.meta["biomes"]
	var surf: Array = w.meta["surface"]
	for i in range(1, strip.size()):
		var sx := int(strip[i]["x0"])
		var b: Dictionary = by_name[strip[i]["biome"]]
		var a: Dictionary = by_name[strip[i - 1]["biome"]]
		# the stone: the first column of b's rock wanders from row to row
		var edges := {}
		var band: Array = w.meta["bands"]["surface"]
		for y in range(int(band[0]) - 20, int(surf[sx]) - 18):
			for x in range(sx - 48, sx + 48):
				if w.get_fg(x, y) == TileDefs.id(b["stone"]):
					edges[x] = true
					break
		t.check(edges.size() >= 4, "%s-%s: the rock's edge wanders (%d columns)" % [a["name"], b["name"], edges.size()])
		# each top tile crosses the border
		var left := 0
		var right := 0
		for x in range(sx - 40, sx + 40):
			var name := TileDefs.names[w.get_fg(x, int(surf[x]))]
			if x >= sx and name == a["top"]:
				right += 1
			if x < sx and name == b["top"]:
				left += 1
		t.check(left + right > 0, "%s-%s: the skins interleave (%d, %d)" % [a["name"], b["name"], left, right])

func _tables(t: TestLog) -> void:
	Items.ensure()
	var ores: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/worldgen/ores.json"))
	for d: Dictionary in StageBiomes.load_defs():
		for k: String in ["top", "road", "soil", "stone"]:
			t.check(TileDefs.id(d[k]) > 0, "%s %s is a tile" % [d["name"], k])
			if k == "road":
				t.check(TileDefs.id(d[k]) >= 96, "%s is a Places tile, so the passages stage never cuts a road" % d[k])
			t.eq(Items.tile_drop(TileDefs.id(d[k])), "tile:rubble", "digging %s gives rubble" % d[k])
		for k: String in ["soil_wall", "stone_wall"]:
			t.check(TileDefs.wall_id(d[k]) > 0, "%s %s is a wall" % [d["name"], k])
		t.check(String(d["stone"]) in ores["ores"][0]["replace"], "ore can form in %s" % d["stone"])
