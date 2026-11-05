## Memory a client's world costs: a ClientWorld of a named size with its interest area
## (5x5 chunks) arrived, plus a LightEngine over it with that area lit.
##   godot --headless -s res://tools/mem_client.gd -- size=dev|small|medium|large
extends SceneTree

func _initialize() -> void:
	var opts := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		opts[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var size: Vector2i = WorldGen.SIZES[String(opts.get("size", "dev"))]
	TileDefs.ensure()
	# One chunk's blob stands in for the host's (contents do not matter for memory).
	var src := TileWorld.make_test(64, 64)
	var blob := src.chunk_at(0, 0).to_bytes()
	var m0 := OS.get_static_memory_usage()
	var t0 := Time.get_ticks_msec()
	var cw := ClientWorld.new()
	cw.setup(size.x, size.y, 1, 1, "mem", Vector2(size.x / 2, size.y / 2), 0, Interest.DEFAULT_RADIUS)
	var m1 := OS.get_static_memory_usage()
	for c in Interest.around(cw.world, Interest.chunk_of(cw.body.center()), cw.radius):
		cw.apply_chunk(c.x, c.y, blob)
	var light := LightEngine.new(cw.world)
	var r := Rect2i(Vector2i(cw.body.pos) - Vector2i(80, 56), Vector2i(160, 112))
	light.ensure_region(r)
	var m2 := OS.get_static_memory_usage()
	print("MEM size=%dx%d world=%.1f MB world+area+light=%.1f MB setup_ms=%d" % [size.x, size.y,
			(m1 - m0) / 1048576.0, (m2 - m0) / 1048576.0, Time.get_ticks_msec() - t0])
	light = null
	cw = null
	quit()
