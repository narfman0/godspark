extends RefCounted

## The visual polish pass (docs/tracks/look-below.md, "Polish"): the maps and mesh pieces the
## shaders read. The pictures themselves are judged with tools/look_shot.gd and tools/corner_shot.gd.
func run(t: TestLog) -> void:
	_opaque(t)
	_rock(t)
	_ground_line(t)
	_light_rect(t)
	_liquid_slopes(t)

## The solid map: 255 where a tile blocks light, an outside chunk all rock.
func _opaque(t: TestLog) -> void:
	var w := TileWorld.new(64, 64)
	w.set_fg(5, 6, TileDefs.id("stone"), true)
	w.set_fg(7, 6, TileDefs.id("torch"), true)
	w.set_fg(8, 6, TileDefs.id("water"), true)
	var b := ChunkMesher.opaque_bytes(ChunkMesher.snapshot(w, 0, 0, true))
	t.eq(b.size(), K.CHUNK * K.CHUNK, "a byte a tile")
	t.eq(b[5 + 6 * K.CHUNK], 255, "stone blocks light")
	t.eq([b[7 + 6 * K.CHUNK], b[8 + 6 * K.CHUNK], b[0]], [0, 0, 0], "a torch, water and air do not")
	t.eq(b.count(255), 1, "nothing else")
	var outside := {"fgs": [1, 1, 1, 1, 1, 1, 1, 1, 1]}
	t.eq(ChunkMesher.opaque_bytes(outside).count(255), K.CHUNK * K.CHUNK, "rock where there is no chunk")
	var lit_rock := []
	for id in TileDefs.names.size():
		if TileDefs.opaque[id] != 0 and TileDefs.emit[id] > 0:
			lit_rock.append(TileDefs.names[id])
	t.eq(lit_rock, [], "no opaque tile gives light (gs_face_levels reads none inside rock)")

## The rock glow map: the deep regions' colour, nothing in the plain underdark or on the surface.
func _rock(t: TestLog) -> void:
	var meta := {"biomes": [
		{"biome": "meadow", "x0": 0, "x1": 300},
		{"biome": "fungal", "band": "deeps", "x0": 0, "x1": 99, "y0": 0, "y1": 99},
		{"biome": "underdark", "band": "deeps", "x0": 100, "x1": 199, "y0": 0, "y1": 99},
		{"biome": "magma", "band": "deeps", "x0": 200, "x1": 300, "y0": 0, "y1": 99}]}
	var rect := Rect2i(0, 0, 296, 160)
	var b := BelowLook.rock_bytes(meta, rect, 8)
	var at := func(x: int, y: int) -> Color:
		var i := (x / 8 + y / 8 * 37) * 4
		return Color(b[i] / 255.0, b[i + 1] / 255.0, b[i + 2] / 255.0, b[i + 3] / 255.0)
	var f: Color = at.call(40, 40)
	var m: Color = at.call(240, 40)
	t.check(f.a > 0.02 and f.b > f.r, "the fungal rock glows violet (%s)" % f)
	t.check(m.a > 0.02 and m.r > m.b * 2.0, "the magma's red (%s)" % m)
	t.eq((at.call(140, 40) as Color).a, 0.0, "the plain underdark has none: its dark stays black")
	t.eq((at.call(40, 140) as Color).a, 0.0, "nor the surface")
	t.eq(BelowLook.rock_bytes({"biomes": [{"biome": "meadow", "x0": 0, "x1": 9}]}, rect, 8).count(0), 37 * 20 * 4, "nor a world with no regions")
	for r: String in ["fungal", "crystal", "deep_lake", "magma"]:
		var g := float(BelowLook.row(r).get("rock_glow", 0.0))
		t.check(g > 0.0 and g <= 0.4, "%s rock glows faintly (%.2f)" % [r, g])
	t.eq(float(BelowLook.row("underdark").get("rock_glow", 0.0)), 0.0, "the underdark's rock does not")

## The ground line the sun share reads: past built tiles and air down to natural ground.
func _ground_line(t: TestLog) -> void:
	var w := TileWorld.new(64, 64)
	var stone := TileDefs.id("stone")
	for x in 64:
		for y in 21:
			w.set_fg(x, y, stone, true)
	for y in range(21, 27):
		w.set_fg(5, y, TileDefs.id("planks"), true)
	w.set_fg(5, 27, TileDefs.id("thatch"), true)
	t.eq(WorldView.ground_under(w, 5, 27), 21, "under a house: the ground, not its roof")
	t.eq(WorldView.ground_under(w, 9, 20), 21, "open ground: the row over its top tile")
	t.eq(WorldView.ground_under(w, 9, 30), 21, "a line drawn over the ground steps down to it")
	var deep := TileWorld.new(64, 128)
	t.eq(WorldView.ground_under(deep, 3, 100), 100, "no ground within reach: the line as given")

## The light rectangle's origin lines up with 16 tiles, so its mip levels match the solid map's.
func _light_rect(t: TestLog) -> void:
	var world := TileWorld.make_test()
	var view := WorldView.new()
	view.setup(world, LightEngine.new(world))
	var bad := []
	for p: Vector2 in [Vector2(128, 64), Vector2(133.7, 71.2), Vector2(200.5, 90.0)]:
		view.view_half = Vector2(20, 12)
		view.set_focus(p)
		var r: Rect2i = view._light_rect
		if r.position.x % 16 != 0 or r.position.y % 16 != 0 or r.size.x % 32 != 0 or r.size.y % 32 != 0:
			bad.append(r)
		var need := Rect2i(Vector2i((p - view.view_half).floor()) - Vector2i(4, 4), Vector2i((view.view_half * 2).ceil()) + Vector2i(8, 8))
		if not r.encloses(need):
			bad.append(["short", r, need])
	t.eq(bad, [], "the light rectangle is on a 16-tile grid and covers the view")
	view.free()

## A slope of single steps down into water is a slope: the inner corners in the water get their
## fillets, the cut corners beside it are filled with the water's sheet.
func _liquid_slopes(t: TestLog) -> void:
	var counts := {}
	for fill: String in ["air", "water", "lava"]:
		var w := TileWorld.new(64, 64)
		var id := TileDefs.id(fill) if fill != "air" else TileDefs.AIR
		for x in 32:
			var top := maxi(20 - x, 8)
			for y in 32:
				if y <= top:
					w.set_fg(x, y, TileDefs.id("stone"), true)
				elif y <= 20:
					w.set_fg(x, y, id, true)
		counts[fill] = _kinds(ChunkMesher.build_arrays(ChunkMesher.snapshot(w, 0, 0, true)))
	var air: Dictionary = counts["air"]
	var water: Dictionary = counts["water"]
	var lava: Dictionary = counts["lava"]
	t.eq(water.get(3, 0), air.get(3, 0), "the ground's slope is the same under water as in air (fillets)")
	t.eq(lava.get(3, 0), air.get(3, 0), "and beside lava")
	t.check(int(water.get(-5, 0)) == 12 * 2, "the cut corners beside the water hold its sheet (%s)" % water)
	t.check(int(lava.get(-1, 0)) == 12 * 2, "and the lava's (%s)" % lava)
	t.eq(air.get(-5, 0), 0, "(none in air)")

## Vertices by kind; a liquid wedge's two vertices off the grid (half a tile in) counted under -kind.
static func _kinds(a: Array) -> Dictionary:
	var out := {}
	if a.is_empty():
		return out
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var f: PackedVector2Array = a[Mesh.ARRAY_TEX_UV2]
	for i in v.size():
		var k := roundi(f[i].y)
		out[k] = int(out.get(k, 0)) + 1
		var p := v[i] / K.TILE_M
		if k in [1, 5] and is_equal_approx(p.z, -0.3) and (is_equal_approx(fposmod(p.x, 1.0), 0.5) or is_equal_approx(fposmod(p.y, 1.0), 0.5)):
			out[-k] = int(out.get(-k, 0)) + 1
	return out
