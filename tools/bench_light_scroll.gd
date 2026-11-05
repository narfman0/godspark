## Main-thread light cost per frame while a client walks across a generated world: chunks
## arrive as the interest area moves (radius 2, as the host streams them), the view keeps
## its light rectangle (160x112 tiles) lit. Prints the worst and mean frame cost.
##   godot --headless -s res://tools/bench_light_scroll.gd -- [seed=3] [deferred=1] [seconds=8]
extends SceneTree

func _initialize() -> void:
	var opts := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		opts[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var deferred := String(opts.get("deferred", "1")) != "0"
	var budget := int(opts.get("budget", 3000))
	var host := WorldGen.generate_named("dev", int(opts.get("seed", 3)))
	var site: Dictionary = {}
	for s: Dictionary in host.meta["sites"]:
		if s["kind"] == "settlement" and s["band"] == "surface":
			site = s
			break
	var cw := ClientWorld.new()
	var pos := Vector2(float(site["x"]), float(site["y"]))
	cw.setup(host.width, host.height, host.world_seed, 1, "bench", pos, 0, 2)
	cw.apply_meta(host.meta)
	var light := LightEngine.new(cw.world)
	light.deferred = deferred
	var frames := PackedInt32Array()
	var dt := 1.0 / 60.0
	var seconds := float(opts.get("seconds", 8.0))
	var held := {}
	var arrive_worst := 0
	var light_worst := 0
	for f in roundi(seconds / dt):
		var t0 := Time.get_ticks_usec()
		pos.x += 13.0 * dt
		pos.y = float(host.meta["surface"][int(pos.x)] + 1)
		cw.body.pos = pos
		var center := Interest.chunk_of(cw.body.center())
		var n := 0
		for c in Interest.around(cw.world, center, 2):
			if not held.has(c) and n < 16:
				cw.apply_chunk(c.x, c.y, host.chunk_at(c.x, c.y).to_bytes())
				held[c] = true
				n += 1
		for c: Vector2i in held.keys():
			if Interest.dist(c, center) > 3:
				cw.drop_chunk(c.x, c.y)
				held.erase(c)
		var t1 := Time.get_ticks_usec()
		arrive_worst = maxi(arrive_worst, t1 - t0)
		var rect := Rect2i(Vector2i(pos) - Vector2i(80, 56), Vector2i(160, 112))
		if deferred:
			light.process(budget, rect)
		else:
			light.ensure_region(rect)
		light_worst = maxi(light_worst, Time.get_ticks_usec() - t1)
		if Time.get_ticks_usec() - t1 > 20000:
			print("  frame %d: light %.1f ms" % [f, (Time.get_ticks_usec() - t1) / 1000.0])
		frames.append(Time.get_ticks_usec() - t0)
	var worst := 0
	var sum := 0
	var sorted := frames.duplicate()
	sorted.sort()
	for u in frames:
		worst = maxi(worst, u)
		sum += u
	print("  worst arrivals part %.1f ms, worst light part %.1f ms" % [arrive_worst / 1000.0, light_worst / 1000.0])
	print("LIGHTBENCH deferred=%s budget=%d frames=%d worst=%.1f ms p99=%.1f ms mean=%.2f ms pages=%d backlog=%d" % [
			deferred, budget, frames.size(), worst / 1000.0, sorted[int(sorted.size() * 0.99)] / 1000.0,
			float(sum) / frames.size() / 1000.0, light.page_count(), light.backlog()])
	quit()
