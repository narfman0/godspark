## Sparse TileWorld (a client's mirror): unloaded cells, light over a partial world, pages,
## hashes, mesher snapshot, and the META message that carries the surface line.
extends RefCounted

func run(t: TestLog) -> void:
	_tiles(t)
	_light(t)
	_meta(t)

func _copy(src: TileWorld, dst: TileWorld, cx: int, cy: int) -> void:
	var c := dst.ensure_chunk(cx, cy)
	var s := src.chunk_at(cx, cy)
	c.fg = s.fg.duplicate()
	c.bg = s.bg.duplicate()
	c.liquid = s.liquid.duplicate()
	dst.chunk_changed.emit(cx, cy)

func _tiles(t: TestLog) -> void:
	var host := TileWorld.make_test(256, 256)
	var w := TileWorld.new(256, 256, 1, true)
	var bedrock := TileDefs.id("bedrock")
	t.eq(w.loaded_count(), 0, "a sparse world starts with no chunks")
	t.eq(w.get_fg(10, 10), bedrock, "unloaded reads as bedrock")
	t.check(w.is_solid(10, 200), "and is solid, even in the sky")
	t.check(not w.set_fg(10, 10, 0), "writes to unloaded cells are ignored")
	t.eq(w.light_fg(10, 200), bedrock, "with no sky line, light sees unloaded as rock")
	w.sky_line = host.scan_surface()
	t.eq(w.sky_line[10], 127, "scan_surface: the test world's ground top")
	t.eq(w.light_fg(10, 200), TileDefs.AIR, "unloaded above the sky line is air to light")
	t.eq(w.light_fg(10, 100), bedrock, "and rock below it")
	t.check(w.unloaded_is_sky(2, 7) and not w.unloaded_is_sky(2, 3), "unloaded_is_sky")
	for cy in range(3, 6):
		for cx in range(3, 6):
			_copy(host, w, cx, cy)
	t.eq(w.loaded_count(), 9, "nine chunks after nine arrive")
	t.eq(w.get_fg(100, 127), host.get_fg(100, 127), "a loaded cell reads the host's tile")
	var dense := TileWorld.new(256, 256, 1)
	for cy in range(3, 6):
		for cx in range(3, 6):
			_copy(host, dense, cx, cy)
	t.eq(w.content_hash(), dense.content_hash(), "content_hash: unloaded chunks hash as empty ones")
	t.eq(ChunkHash.of(w, [Vector2i(4, 4)]), ChunkHash.of(host, [Vector2i(4, 4)]), "ChunkHash over held chunks matches the host")
	t.check(ChunkHash.of(w, [Vector2i(0, 0)]) != ChunkHash.of(host, [Vector2i(0, 0)]), "and differs over an unloaded one")
	var snap := ChunkMesher.snapshot(w, 4, 5)
	t.eq(snap["fgs"][7], 0, "mesher: an unloaded chunk above the surface is open sky")
	var low := ChunkMesher.snapshot(w, 4, 3)
	t.eq(low["fgs"][1], 1, "mesher: an unloaded chunk below it is rock")
	t.check(w.unload_chunk(4, 4) and not w.has_chunk(4, 4), "unload_chunk frees a chunk")
	t.check(not w.unload_chunk(4, 4), "twice is a no-op")
	t.check(not dense.unload_chunk(4, 4), "dense worlds never unload")

func _light(t: TestLog) -> void:
	var host := TileWorld.make_test(256, 256)
	var w := TileWorld.new(256, 256, 1, true)
	w.sky_line = host.scan_surface()
	var light := LightEngine.new(w)
	for cy in range(3, 6):
		for cx in range(3, 6):
			_copy(host, w, cx, cy)
	var area := Rect2i(96, 96, 96, 96)
	light.ensure_region(area)
	t.eq(light.sky_at(170, 130), LightEngine.SUN, "the surface is sunlit though the sky above is not loaded")
	t.check(light.sky_at(140, 100) < LightEngine.SUN, "underground is not direct sun")
	# More arrivals, a drop, and edits; then compare with a fresh engine.
	for cx in range(3, 6):
		_copy(host, w, cx, 2)
	w.unload_chunk(3, 5)
	w.unload_chunk(3, 4)
	for y in range(118, 128):
		w.set_fg(150, y, TileDefs.AIR)          # a shaft from the surface
	w.set_fg(140, 140, TileDefs.id("stone"))
	w.set_fg(120, 90, TileDefs.id("torch"))
	var loaded := Rect2i(96, 64, 96, 128)
	light.ensure_region(loaded)
	var fresh := LightEngine.new(w)
	fresh.ensure_region(loaded)
	var bad := 0
	for y in range(loaded.position.y, loaded.end.y):
		for x in range(loaded.position.x, loaded.end.x):
			if not w.is_loaded(x, y):
				continue
			if light.block_at(x, y) != fresh.block_at(x, y) or light.sky_at(x, y) != fresh.sky_at(x, y):
				if bad < 4:
					print("    differs at %d,%d: %d/%d vs %d/%d" % [x, y, light.block_at(x, y), light.sky_at(x, y), fresh.block_at(x, y), fresh.sky_at(x, y)])
				bad += 1
	t.eq(bad, 0, "sparse light after arrivals, drops and edits equals a fresh recompute")
	t.check(light.page_count() <= 25, "light pages stay near the loaded chunks (%d)" % light.page_count())
	for c: Vector2i in [Vector2i(4, 5), Vector2i(5, 5), Vector2i(4, 4), Vector2i(5, 4), Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3), Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2)]:
		w.unload_chunk(c.x, c.y)
	t.eq(w.loaded_count(), 0, "everything dropped")
	t.eq(light.page_count(), 0, "and every light page freed")

func _meta(t: TestLog) -> void:
	var m := {"surface": [500, 501, 499, 480, 900], "biomes": [{"x0": 0, "x1": 4, "biome": "meadow"}],
		"bands": {"sky": [0, 10]}, "sites": [{"id": 0, "kind": "settlement", "x": 2, "y": 501}],
		"routes": [{"id": 0}]}
	var b := Protocol.meta(m)
	var d := Protocol.decode(b)
	t.eq(d.get("type"), Protocol.T.META, "META decodes")
	var got: Dictionary = d.get("meta", {})
	t.eq(got.get("surface"), m["surface"], "surface survives the delta coding")
	t.eq(got.get("sites"), m["sites"], "sites survive")
	t.eq(got.get("biomes"), m["biomes"], "biomes survive")
	t.eq(got.get("bands"), m["bands"], "bands survive")
	t.check(not got.has("routes"), "routes are not sent")
	t.eq(Protocol.decode(b.slice(0, 7)), {}, "a truncated META is refused")
	var bad := b.duplicate()
	bad.encode_u32(1, 999999999)
	t.eq(Protocol.decode(bad), {}, "a META claiming a huge size is refused")
	var junk := PackedByteArray([Protocol.T.META, 16, 0, 0, 0, 1, 2, 3, 4])
	t.eq(Protocol.decode(junk), {}, "a META that does not decompress is refused")
	var big := []
	for i in 16384:
		big.append(1000 + (i % 7) - 3 + i / 50)
	t.check(Protocol.meta({"surface": big}).size() < 8000, "a large world's surface compresses (%d bytes)" % Protocol.meta({"surface": big}).size())
