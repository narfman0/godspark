## Render the view demo and save a PNG. Runs under tools/soft_godot.sh (CPU Vulkan).
##   tools/soft_godot.sh -s res://tools/shot.gd -- out=/tmp/x.png [x=.. y=.. zoom=.. sun=..]
##     [w=1280 h=720] [still] [gen=seed] [dig=1: dig a shaft into the cave first]
## Prints chunk build and light timings from the run.
extends SceneTree

func _initialize() -> void:
	var opts := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var out: String = opts.get("out", "/tmp/godspark_shot.png")
	var size := Vector2i(int(opts.get("w", 1280)), int(opts.get("h", 720)))
	DisplayServer.window_set_size(size)
	root.size = size
	opts["still"] = "1"
	var demo: Node3D = load("res://view/demo.tscn").instantiate()
	demo.opts = opts
	root.add_child(demo)
	await process_frame
	if opts.has("dig"):
		var w: TileWorld = demo.world
		var mid := w.width / 2
		var g := w.height / 2
		for y in range(g - 9, g):
			w.set_fg(mid - 6, y, TileDefs.AIR)
	var frames := 0
	while frames < 600:
		await process_frame
		frames += 1
		if frames > 3 and demo.view.is_idle():
			break
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out)
	var st: Dictionary = demo.view.stats
	print("shot: %s %dx%d after %d frames, %d chunks" % [out, img.get_width(), img.get_height(), frames, demo.view.chunk_count()])
	for k: String in st:
		var a: PackedInt32Array = st[k]
		if a.is_empty():
			continue
		var s := 0
		var mx := 0
		for v in a:
			s += v
			mx = maxi(mx, v)
		print("  %-8s n=%d avg=%.2f ms max=%.2f ms" % [k, a.size(), s / 1000.0 / a.size(), mx / 1000.0])
	quit()
