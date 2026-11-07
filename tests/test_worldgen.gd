extends RefCounted

const W := 512
const H := 256
const SITE_KEYS := ["id", "kind", "x", "y", "biome", "band", "size"]
const ROUTE_KEYS := ["id", "a", "b", "kind", "length"]
const KINDS := ["settlement", "lair", "ruin", "portal"]
const BANDS := ["sky", "surface", "caves", "deeps", "nadir"]

func run(t: TestLog) -> void:
	var a := WorldGen.generate(W, H, 7)
	var b := WorldGen.generate(W, H, 7)
	t.eq(a.content_hash(), b.content_hash(), "same seed, same tiles")
	t.check(a.meta == b.meta, "same seed, same meta")
	var c := WorldGen.generate(W, H, 8)
	t.check(a.content_hash() != c.content_hash(), "different seeds, different tiles")
	t.check(WorldGen.rng_for(7, "caves").randi() == WorldGen.rng_for(7, "caves").randi(), "stage rng is stable")
	t.check(WorldGen.rng_for(7, "caves").randi() != WorldGen.rng_for(7, "ores").randi(), "stage rngs differ by name")
	t.check(a.chunk_at(0, 0).fg.size() == Chunk.CELLS * 2 and not a.chunk_at(0, 0).modified,
			"chunks are full size and unmodified")
	t.eq(a.get_fg(0, 0), TileDefs.id("bedrock"), "bedrock at the bottom")

	_check_world(t, a, "512x256 seed 7")
	_check_world(t, c, "512x256 seed 8")
	for s in [3, 21, 99, 12345]:
		_check_world(t, WorldGen.generate(W, H, s), "512x256 seed %d" % s)
	_check_world(t, WorldGen.generate(1024, 512, 5), "1024x512 seed 5")

func _check_world(t: TestLog, world: TileWorld, label: String) -> void:
	var m := world.meta
	for key in ["surface", "biomes", "bands", "sites", "routes"]:
		t.check(m.has(key), "%s: meta has %s" % [label, key])
	t.check(JSON.parse_string(JSON.stringify(m)) != null, "%s: meta survives JSON" % label)

	# surface: highest solid tile per column
	var surf: Array = m["surface"]
	t.eq(surf.size(), world.width, "%s: one surface entry per column" % label)
	var bad := 0
	for x in world.width:
		var s: int = surf[x]
		if not world.is_solid(x, s):
			bad += 1
			continue
		for y in range(s + 1, world.height):
			if world.is_solid(x, y):
				bad += 1
				break
	t.eq(bad, 0, "%s: surface[x] is the highest solid tile" % label)

	# biome strip covers the width, in order, no gaps
	var strip: Array = BiomeIds.strip(m)
	var next := 0
	for seg: Dictionary in strip:
		t.check(int(seg["x0"]) == next and int(seg["x1"]) >= int(seg["x0"]) and seg["biome"] is String,
				"%s: biome segment %s continues the strip" % [label, seg])
		next = int(seg["x1"]) + 1
	t.eq(next, world.width, "%s: biome strip covers the width" % label)

	# bands are contiguous and cover the height
	var bands: Dictionary = m["bands"]
	t.eq(bands.keys(), BANDS, "%s: band names" % label)
	var rows := 0
	for name: String in bands:
		var r: Array = bands[name]
		rows += int(r[1]) - int(r[0]) + 1
	t.check(int(bands["nadir"][0]) == 0 and int(bands["sky"][1]) == world.height - 1 and rows == world.height,
			"%s: bands cover the height" % label)

	# sites
	var sites := {}
	var counts := {}
	for s: Dictionary in m["sites"]:
		t.check(s.keys() == SITE_KEYS, "%s: site keys %s" % [label, s.keys()])
		t.check(s["kind"] in KINDS and s["band"] in BANDS, "%s: site kind and band valid: %s" % [label, s])
		t.check(not sites.has(s["id"]), "%s: site ids unique" % label)
		sites[s["id"]] = s
		var key: String = s["kind"] + ("" if s["kind"] != "settlement" else ("_surface" if s["band"] == "surface" else "_deep"))
		counts[key] = counts.get(key, 0) + 1
		var x: int = s["x"]
		var y: int = s["y"]
		t.check(world.is_solid(x, y - 1) and not world.is_solid(x, y) and not world.is_solid(x, y + 1),
				"%s: site %d stands on ground with room" % [label, s["id"]])
		if s["kind"] == "settlement":
			var clear := true
			var floor_ok := 0
			var half: int = 8
			for dx in range(-half, half + 1):
				for dy in 6:
					if world.is_solid(x + dx, y + dy):
						clear = false
				if world.is_solid(x + dx, y - 1):
					floor_ok += 1
			t.check(clear, "%s: settlement %d has 6 tiles of headroom across 17 columns" % [label, s["id"]])
			t.eq(floor_ok, 2 * half + 1, "%s: settlement %d floor is solid across 17 columns" % [label, s["id"]])
	t.check(counts.get("settlement_surface", 0) >= 2, "%s: at least two surface settlements (%s)" % [label, counts])
	t.check(counts.get("settlement_deep", 0) >= 1, "%s: a deep settlement (%s)" % [label, counts])
	t.eq(counts.get("portal", 0), 1, "%s: one portal" % label)
	t.check(counts.get("lair", 0) >= 1 and counts.get("ruin", 0) >= 1, "%s: lairs and ruins (%s)" % [label, counts])

	# routes
	var kinds := {}
	var deep_to_surface: Array = []
	var deep_to_deep: Array = []
	for r: Dictionary in m["routes"]:
		t.check(r.keys().slice(0, ROUTE_KEYS.size()) == ROUTE_KEYS and r.has("path"), "%s: route keys %s" % [label, r.keys()])
		t.check(sites.has(r["a"]) and sites.has(r["b"]) and r["a"] != r["b"], "%s: route %d endpoints exist" % [label, r["id"]])
		t.check(r["kind"] in ["road", "deep_road"] and int(r["length"]) > 0, "%s: route %d kind and length" % [label, r["id"]])
		kinds[r["kind"]] = true
		if not (sites.has(r["a"]) and sites.has(r["b"])):
			continue
		var da := _deep(sites[r["a"]])
		var db := _deep(sites[r["b"]])
		if da != db:
			deep_to_surface.append(r)
		elif da and db:
			deep_to_deep.append(r)
	t.check(kinds.has("road") and kinds.has("deep_road"), "%s: roads and deep roads exist" % label)
	t.check(not deep_to_surface.is_empty(), "%s: a route links the deep to the surface" % label)
	t.check(not deep_to_deep.is_empty(), "%s: a deep road links two deep sites" % label)

	# deep roads are physically walkable by something 4 tiles tall
	for r: Dictionary in deep_to_deep + deep_to_surface:
		var sa: Dictionary = sites[r["a"]]
		var sb: Dictionary = sites[r["b"]]
		t.check(_reachable(world, Vector2i(sa["x"], sa["y"]), Vector2i(sb["x"], sb["y"]), 4),
				"%s: route %d (%s %d -> %d) is open 4 tiles high end to end" % [label, r["id"], r["kind"], r["a"], r["b"]])

func _deep(s: Dictionary) -> bool:
	return s["band"] == "deeps" or s["band"] == "nadir"

## Flood fill over cells whose column of `tall` tiles is open; true if b is reached from a.
func _reachable(world: TileWorld, a: Vector2i, b: Vector2i, tall: int) -> bool:
	var w := world.width
	var h := world.height
	var open := PackedByteArray()
	open.resize(w * h)
	for x in w:
		var run := 0
		for y in range(h - 1, -1, -1):  # top down: run = open cells from y upward
			run = 0 if world.is_solid(x, y) else run + 1
			open[x + y * w] = 1 if run >= tall else 0
	var seen := PackedByteArray()
	seen.resize(w * h)
	var queue := PackedInt32Array([a.x + a.y * w])
	if open[queue[0]] == 0:
		return false
	seen[queue[0]] = 1
	var head := 0
	var goal := b.x + b.y * w
	while head < queue.size():
		var i := queue[head]
		head += 1
		if i == goal:
			return true
		var x := i % w
		for j: int in [i - 1 if x > 0 else -1, i + 1 if x < w - 1 else -1, i - w, i + w]:
			if j >= 0 and j < w * h and seen[j] == 0 and open[j] == 1:
				seen[j] = 1
				queue.append(j)
	return false
