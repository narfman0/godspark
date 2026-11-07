## Timings for the view track, headless:
##   godot --headless -s res://tools/bench_view.gd
## Chunk mesh build per 32x32 chunk (single thread), light for one chunk region, and the
## incremental light updates that play does every frame.
extends SceneTree

func _initialize() -> void:
	var world := TileWorld.make_test(512, 256)
	# Rough up the test world so chunks are not all flat: random caves and holes.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 220:
		var cx := rng.randi_range(0, world.width - 1)
		var cy := rng.randi_range(0, world.height / 2 - 2)
		var r := rng.randi_range(1, 5)
		for y in range(cy - r, cy + r + 1):
			for x in range(cx - r * 2, cx + r * 2 + 1):
				if Vector2(x - cx, (y - cy) * 2).length() <= r * 2 and rng.randf() < 0.9:
					world.set_fg(x, y, TileDefs.AIR, true)
	var by_kind := {"buried": [], "surface": [], "caves": [], "air": []}
	var verts := 0
	var n := 0
	var all: Array[float] = []
	var snap_us := 0
	for cy in world.chunks_y:
		for cx in world.chunks_x:
			var t0 := Time.get_ticks_usec()
			var snap := ChunkMesher.snapshot(world, cx, cy)
			var t1 := Time.get_ticks_usec()
			var arr := ChunkMesher.build_arrays(snap)
			var ms := (Time.get_ticks_usec() - t1) / 1000.0
			snap_us += t1 - t0
			var v := 0 if arr.is_empty() else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			verts += v
			n += 1
			all.append(ms)
			var kind := "air" if v == 0 else ("buried" if v <= 8 else ("surface" if cy == (world.height / 2 - 1) / K.CHUNK else "caves"))
			by_kind[kind].append(ms)
	all.sort()
	var soft_us := 0
	var soft_verts := 0
	for cy in world.chunks_y:
		for cx in world.chunks_x:
			var snap := ChunkMesher.snapshot(world, cx, cy, true)
			var t0 := Time.get_ticks_usec()
			var arr := ChunkMesher.build_arrays(snap)
			ChunkMesher.material_bytes(snap)
			soft_us += Time.get_ticks_usec() - t0
			soft_verts += 0 if arr.is_empty() else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	print("soft: avg %.2f ms a chunk with its material map, avg verts %d" % [soft_us / 1000.0 / n, soft_verts / n])
	print("chunk mesh build, %d chunks of %dx%d, single thread:" % [n, K.CHUNK, K.CHUNK])
	print("  avg %.2f ms  median %.2f  p95 %.2f  max %.2f   avg verts %d   snapshot avg %.3f ms" %
		[_avg(all), all[n / 2], all[int(n * 0.95)], all[n - 1], verts / n, snap_us / 1000.0 / n])
	for k: String in by_kind:
		var a: Array = by_kind[k]
		if not a.is_empty():
			print("  %-8s n=%3d avg %.2f ms" % [k, a.size(), _avg(a)])
	# Where the time goes in one busy chunk.
	var busy := ChunkMesher.snapshot(world, 4, 3)
	var t := Time.get_ticks_usec()
	for i in 20:
		ChunkMesher.build_arrays(busy)
	print("  busy chunk (4,3): %.2f ms" % ((Time.get_ticks_usec() - t) / 20000.0))
	t = Time.get_ticks_usec()
	for i in 20:
		ChunkMesher.emitters(busy)
	print("  its light-giving tiles for the lamps (ChunkMesher.emitters): %.2f ms" % ((Time.get_ticks_usec() - t) / 20000.0))

	# Light: one chunk region from cold (includes its padding), a full world, edits, movers.
	var light := LightEngine.new(world)
	t = Time.get_ticks_usec()
	light.ensure_region(Rect2i(4 * K.CHUNK, 3 * K.CHUNK, K.CHUNK, K.CHUNK))
	print("light: one chunk from cold %.1f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
	t = Time.get_ticks_usec()
	light.ensure_region(Rect2i(0, 0, 160, 112))
	print("light: 160x112 tiles (the view's texture) from cold %.1f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
	t = Time.get_ticks_usec()
	light.ensure_region(Rect2i(0, 0, world.width, world.height))
	print("light: rest of the %dx%d world %.1f ms" % [world.width, world.height, (Time.get_ticks_usec() - t) / 1000.0])
	var g := world.height / 2
	t = Time.get_ticks_usec()
	for i in 20:
		world.set_fg(100 + i * 3, g - 6, TileDefs.AIR)
	print("light: dig one buried tile %.2f ms" % ((Time.get_ticks_usec() - t) / 20000.0))
	t = Time.get_ticks_usec()
	for i in 20:
		world.set_fg(200 + i * 3, g - 1, TileDefs.AIR)
	print("light: dig one surface tile (sun column changes) %.2f ms" % ((Time.get_ticks_usec() - t) / 20000.0))
	light.add_light(1, 50.0, g + 2.0, LightEngine.TORCH)
	t = Time.get_ticks_usec()
	for i in 40:
		light.move_light(1, 50.0 + i, g + 2.0)
	print("light: carried torch moves one tile %.2f ms" % ((Time.get_ticks_usec() - t) / 40000.0))
	t = Time.get_ticks_usec()
	for i in 20:
		light.region_bytes(Rect2i(0, 0, 160, 112), true)
		light.region_bytes(Rect2i(0, 0, 160, 112), false)
	print("light: texture bytes for 160x112, both fields %.2f ms" % ((Time.get_ticks_usec() - t) / 20000.0))
	quit()

func _avg(a: Array) -> float:
	var s := 0.0
	for v: float in a:
		s += v
	return s / maxf(a.size(), 1)
