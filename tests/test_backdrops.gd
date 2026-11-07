## The look that is not tiles: soft terrain meshes over untouched collision, the material map, and
## the backdrops. Headless, and art is optional, so this checks data and geometry.
extends RefCounted

func run(t: TestLog) -> void:
	_stairs(t)
	_built(t)
	_material(t)
	_inner_data(t)
	_backdrops(t)

## Steps one tile high, on a flat world.
func _stair_world() -> TileWorld:
	var w := TileWorld.new(128, 64)
	var dirt := TileDefs.id("dirt")
	for x in w.width:
		var top := 20 + mini(maxi(x - 42, 0), 6)
		for y in top + 1:
			w.set_fg(x, y, dirt)
	return w

func _verts_at_front(arr: Array) -> Array:
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var out: Array = []
	for p in v:
		if absf(p.z - ChunkMesher.FRONT * K.TILE_M) < 0.001:
			out.append(Vector2(p.x, p.y) / K.TILE_M)
	return out

## On a stair of single steps the outline is one slope through the middle of each tread.
func _stairs(t: TestLog) -> void:
	var w := _stair_world()
	var hard := ChunkMesher.build(w, 1, 0)
	var soft := ChunkMesher.build_arrays(ChunkMesher.snapshot(w, 1, 0, true))
	t.check(not soft.is_empty(), "a soft chunk meshes")
	var f: PackedVector2Array = soft[Mesh.ARRAY_TEX_UV2]
	var kinds := {}
	for p in f:
		kinds[int(p.y)] = true
	t.check(kinds.has(3), "natural ground is kind 3 (%s)" % [kinds.keys()])
	t.check(not kinds.has(0), "and no plain block is left in it")
	var hk: PackedVector2Array = hard[Mesh.ARRAY_TEX_UV2]
	var plain := true
	for p in hk:
		plain = plain and int(p.y) == 0
	t.check(plain, "the block mesher is unchanged without soft")
	# side faces reach z = BACK: the outline, in tiles
	var v: PackedVector3Array = soft[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = soft[Mesh.ARRAY_NORMAL]
	var sides := 0
	var on_line := 0
	for i in v.size():
		if absf(n[i].x + n[i].y * 0.0) > 0.5 and absf(n[i].z) < 0.01 and absf(n[i].x) < 0.9:
			var p := Vector2(v[i].x, v[i].y) / K.TILE_M + Vector2(K.CHUNK, 0)
			# the slope up the stair: y - x at the foot of its first step
			if absf((p.y - p.x) - (21.0 - 42.5)) < 0.01:
				on_line += 1
			sides += 1
	t.check(sides > 0, "stairs have sloped sides (%d vertices)" % sides)
	t.eq(on_line, sides, "every slope of the stair lies on one line through the treads' middles")
	# collision is the world's: nothing about soft meshing touches a tile
	t.eq(w.is_solid(43, 21), true, "the step is still solid under the cut")
	t.eq(w.is_solid(42, 21), false, "and the fillet's cell still open")

func _built(t: TestLog) -> void:
	var w := TileWorld.new(128, 128)
	w.set_fg(40, 40, TileDefs.id("wood"))
	var a := ChunkMesher.build_arrays(ChunkMesher.snapshot(w, 1, 1, true))
	var b := ChunkMesher.build(w, 1, 1)
	t.eq((a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), (b[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), "built tiles keep their corners")
	var r := TileWorld.new(128, 128)
	r.set_fg(40, 40, TileDefs.id("thatch"))
	r.set_fg(41, 40, TileDefs.id("thatch"))
	r.set_fg(41, 41, TileDefs.id("thatch"))
	var s := ChunkMesher.build_arrays(ChunkMesher.snapshot(r, 1, 1, true))
	var kinds := {}
	for p: Vector2 in s[Mesh.ARRAY_TEX_UV2]:
		kinds[int(p.y)] = true
	t.check(kinds.has(3), "a roof cuts like ground")

func _material(t: TestLog) -> void:
	var w := TileWorld.new(64, 64)
	w.set_fg(3, 2, TileDefs.id("grass"))
	w.set_fg(4, 2, TileDefs.id("wood"))
	var snap := ChunkMesher.snapshot(w, 0, 0, true)
	var m := ChunkMesher.material_bytes(snap)
	t.eq(m.size(), K.CHUNK * K.CHUNK * 4, "a texel per tile")
	var at := (3 + 2 * K.CHUNK) * 4
	t.eq(m[at + 3], 255, "ground has alpha")
	t.eq(m[at], TileDefs.colors[TileDefs.id("grass")].r8, "and its colour")
	t.eq(m[(4 + 2 * K.CHUNK) * 4 + 3], 0, "a built plank does not blend")
	t.eq(m[(5 + 2 * K.CHUNK) * 4 + 3], 0, "nor does air")

## The table names only biomes that exist, and every generated surface biome has its row.
func _inner_data(t: TestLog) -> void:
	var d := Backdrops.data()
	t.check(not d.is_empty(), "data/backdrops.json parses")
	var bs: Dictionary = d["biomes"]
	for b: String in BiomeIds.generated("surface"):
		t.check(bs.has(b), "%s has a backdrop" % b)
		for l: Dictionary in d["layers"]:
			t.check((bs[b]["layers"] as Dictionary).has(l["name"]), "%s has layer %s" % [b, l["name"]])
		for e: Array in bs[b]["props"]["list"]:
			t.check((d["models"] as Dictionary).has(e[0]), "%s prop %s is a model" % [b, e[0]])
		for e: Array in bs[b]["fore"]["list"]:
			t.check((d["models"] as Dictionary).has(e[0]), "%s foreground %s is a model" % [b, e[0]])
	t.check((d["layers"] as Array).size() >= 3, "three or more depths behind the plane")
	var last := INF
	for l: Dictionary in d["layers"]:
		t.check(float(l["depth"]) < last, "layers run back to front")
		last = float(l["depth"])

func _backdrops(t: TestLog) -> void:
	var w := TileWorld.new(2048, 256)
	var surf := []
	surf.resize(w.width)
	surf.fill(100)
	for x in range(1200, 1400):
		surf[x] = 200
	w.meta = {"surface": surf, "biomes": [{"x0": 0, "x1": 999, "biome": "forest", "temp": 0.2},
		{"x0": 1000, "x1": 2047, "biome": "desert", "temp": 0.8}]}
	var b := Backdrops.new()
	b.setup(w)
	t.eq(b.counts["ribbons"], (Backdrops.data()["layers"] as Array).size() + 1, "a ribbon per layer and one under the near row")
	t.eq(b.tint_at(100.0)["light"], _c(Backdrops.data()["biomes"]["forest"]["light"]), "a biome's light in its own ground")
	t.eq(b.tint_at(1900.0)["light"], _c(Backdrops.data()["biomes"]["desert"]["light"]), "and the next one's in its")
	var at_seam: Color = b.tint_at(999.0)["light"]
	var fa: Color = b.tint_at(100.0)["light"]
	var fb: Color = b.tint_at(1900.0)["light"]
	t.check(at_seam.b > minf(fa.b, fb.b) - 0.001 and at_seam.b < maxf(fa.b, fb.b) + 0.001 and at_seam != fa and at_seam != fb, "and the seam is between them")
	var last := fa
	var jump := 0.0
	for x in range(800, 1200, 10):
		var c: Color = b.tint_at(float(x))["light"]
		jump = maxf(jump, absf(c.r - last.r) + absf(c.b - last.b))
		last = c
	t.check(jump < 0.04, "with no jump across it (%.3f a step)" % jump)
	b.update(Vector2(500, 110))
	t.check(absf(b.anchor - 100.0) < 0.01, "a layer's anchor is the ground under the camera")
	t.eq(b.fore_fade, 1.0, "the foreground shows in the open")
	b.update(Vector2(1300, 110))
	t.check(b.anchor > 150.0, "and on the heights it is the heights (%.0f)" % b.anchor)
	b.update(Vector2(500, 60))
	t.eq(b.fore_fade, 0.0, "underground the foreground is gone")
	# the same seed gives the same near row: picks come from the seed and the spot
	var a := b._near_segment(3, 96)
	var c := b._near_segment(3, 96)
	t.eq(a.get_child_count(), c.get_child_count(), "a segment is deterministic")
	a.free()
	c.free()
	for i in 12:
		b.update(Vector2(500 + i * 40, 110))
	var segs := 0
	for k: String in b._segs:
		segs += 1
		t.check(k.begins_with("near") or k.begins_with("fore"), "only near and fore stream")
	t.check(segs < 16, "segments stay few as the camera moves (%d)" % segs)
	b.free()

static func _c(a: Array) -> Color:
	return Color(a[0], a[1], a[2])
