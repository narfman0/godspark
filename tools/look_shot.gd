## Pictures and frame times of a generated world, as a player's view draws it: terrain, dressing,
## backdrops, an idle hero on the ground. Runs under tools/soft_godot.sh (CPU Vulkan).
##   tools/soft_godot.sh -s res://tools/look_shot.gd -- out=/tmp/x.png gen=medium seed=1
##     [biome=forest | x=1234] [at=0.5: how far along the biome strip] [y=2100] [sun=1.0 | hour=22]
##     [dy=4: the camera over the feet] [shadows=off|low|high] [zoom=1] [nohero]
##     [cache=DIR: load the world from DIR, or generate and save it there]
##     [spawn=1: the spawn town] [open=1: walk east to where no place is in view] [hard=1: the old block look]
##     [nodress=1: none of the world's dressing, to weigh it]
##     [cave=1: stand in the nearest cave at least 20 rows under the ground] [torches=3: torch tiles
##     on the floor around the hero] [torch=0: the hero carries no light] [monster=goblin-warrior: a
##     creature four tiles right of the hero, facing it] [shaft=3: a hole that wide dug from the
##     cave's ceiling up to the sky, six tiles right of the hero]
##     [bench=300: pan for that many frames first and print the frame times] [seam=1: x at a seam]
extends SceneTree

func _initialize() -> void:
	var o := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		o[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var size := Vector2i(int(o.get("w", 1280)), int(o.get("h", 720)))
	DisplayServer.window_set_size(size)
	root.size = size
	var world := _world(o) if not o.has("sheet") else _sheet_world()
	if o.has("list"):
		for s: Dictionary in world.meta.get("biomes", []):
			print("BIOME %s %d-%d temp %.2f" % [s["biome"], s["x0"], s["x1"], s.get("temp", 0.0)])
		quit()
		return
	var x := _x(world, o)
	while o.has("open") and x < world.width - 70 and not _open(world, x):
		x += 16
	var y := float(o.get("y", _ground(world, x)))
	if o.has("cave"):
		var c := _cave(world, x, int(y))
		x = c.x
		y = c.y
	if o.has("shaft"):
		_shaft(world, Vector2i(x + 6, int(y)), int(o["shaft"]))
	if o.has("torches"):
		_torches(world, Vector2i(x, int(y)), int(o["torches"]))
	var sun := float(o.get("sun", 1.0)) if not o.has("hour") else WorldClock.sun_at(float(o["hour"]))
	var light := LightEngine.new(world)
	light.sun = sun
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var view := WorldView.new()
	root.add_child(view)
	var t0 := Time.get_ticks_usec()
	view.setup(world, light)
	view.hour = float(o.get("hour", 13.0 if sun > 0.5 else 22.0))
	if o.has("shadows"):
		view.lights.set_quality(String(o["shadows"]))
	print("BENCH setup %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	view.soft = not o.has("hard")
	var dressing := DressingView.new()
	view.add_child(dressing)
	var rig := CameraRig.new()
	root.add_child(rig)
	rig.zoom = float(o.get("zoom", 1.0))
	var focus := Vector2(x + 0.5, y + float(o.get("dy", 6.0)))
	rig.target = focus
	rig.snap()
	await process_frame
	view.view_half = rig.visible_half_extent()
	view.set_focus(focus)
	env.background_color = WorldView.sky_color(sun)
	var recs := _records(world, focus) if not o.has("sheet") else _sheet(int(o["sheet"]), Vector2i(x, int(y)))
	dressing.set_objects(recs if not o.has("nodress") else [])
	if not o.has("nohero"):
		view.add_actor(1, {"player": "fighter", "name": "Ash", "kind": "hero", "color": Color(0.85, 0.3, 0.25)})
		view.move_actor(1, Vector2(x + 0.5, y), 1, "idle")
		if String(o.get("torch", "1")) != "0":
			var r := LightSources.row("tile:torch")
			light.add_light(1, x + 0.5, y + 1.8, int(r["level"]))
			view.carry(1, Vector2(x + 1.1, y + 1.8), r)
		view.keep_clear(0, Vector2(x + 0.5, y + 1.2))
	if o.has("monster"):
		var mx := x + 4
		var my := int(y) + 2
		while my > 0 and not world.is_solid(mx, my - 1):
			my -= 1
		view.add_actor(2, {"slug": String(o["monster"])})
		view.move_actor(2, Vector2(mx + 0.5, my), -1, "idle")
	var frames := 0
	while frames < 900:
		await process_frame
		frames += 1
		view.view_half = rig.visible_half_extent()
		view.set_focus(focus)
		if frames > 3 and view.is_idle():
			break
	for i in 3:
		await RenderingServer.frame_post_draw
	if o.has("bench"):
		await _bench(o, view, rig, focus)
	var out := String(o.get("out", ""))
	if out != "":
		var img := root.get_texture().get_image()
		img.save_png(out)
		print("look_shot: %s x=%d y=%d biome=%s objects=%d %s" % [out, x, int(y), _biome(world, x), recs.size(), dressing.counts])
	quit()

## Pan a screen and back; frame times exclude the first frames of each new chunk only as much as
## play does, so spikes show. Renderer is whatever ran it: compare like with like.
func _bench(o: Dictionary, view: WorldView, rig: CameraRig, focus: Vector2) -> void:
	var n := int(o["bench"])
	var times := PackedFloat32Array()
	var last := Time.get_ticks_usec()
	for i in n:
		var p := focus + Vector2(sin(float(i) / float(n) * TAU) * 50.0, 0.0)
		rig.target = p
		rig.snap()
		view.set_focus(p)
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
	var sorted := Array(times)
	sorted.sort()
	var s := 0.0
	for t: float in times:
		s += t
	print("BENCH frames=%d avg=%.2f ms p50=%.2f p95=%.2f max=%.2f chunks=%d draws=%d prims=%d" % [n, s / n, sorted[n / 2], sorted[n * 95 / 100], sorted[n - 1],
		view.chunk_count(), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	rig.target = focus
	rig.snap()
	view.set_focus(focus)
	for i in 30:
		await process_frame

static func _sheet_world() -> TileWorld:
	return TileWorld.make_test(512, 128)

## One each of the scattered objects, a page at a time, on flat ground around at.
static func _sheet(page: int, at: Vector2i) -> Array:
	var names: Array = []
	for n: String in DressingView.defs():
		var w: Dictionary = DressingView.defs()[n].get("where", {})
		if String(w.get("band", "surface")) == "surface":
			names.append(n)
	var out: Array = []
	var x := at.x - 58
	for i in range((page - 1) * 12, mini(page * 12, names.size())):
		out.append({"id": names[i], "x": x, "y": at.y})
		print("SHEET %s at %d" % [names[i], x])
		x += 10
	return out

static func _world(o: Dictionary) -> TileWorld:
	var cache := String(o.get("cache", ""))
	if cache != "" and FileAccess.file_exists(cache.path_join("meta.bin")) or (cache != "" and DirAccess.dir_exists_absolute(cache) and not DirAccess.get_files_at(cache).is_empty()):
		var back := WorldSave.load(cache)
		if back != null:
			return back
	var t0 := Time.get_ticks_msec()
	var w := WorldGen.generate_named(String(o.get("gen", "dev")), int(o.get("seed", 1)))
	print("generated in %d ms" % (Time.get_ticks_msec() - t0))
	if cache != "":
		DirAccess.make_dir_recursive_absolute(cache)
		WorldSave.save(w, cache)
	return w

static func _x(world: TileWorld, o: Dictionary) -> int:
	if o.has("x"):
		return int(o["x"])
	if o.has("spawn"):
		return floori((load("res://game/main.gd").spawn_for(world, Vector2.ZERO) as Vector2).x)
	if o.has("seam"):
		var b: Array = world.meta.get("biomes", [])
		return int(b[int(o["seam"])]["x0"])
	var want := String(o.get("biome", ""))
	for s: Dictionary in world.meta.get("biomes", []):
		if String(s["biome"]) == want:
			return int(lerpf(float(s["x0"]), float(s["x1"]), float(o.get("at", 0.5))))
	return world.width / 2

## No place within a screen of x, and no road's bridge or wall right there.
static func _open(world: TileWorld, x: int) -> bool:
	for dx in range(-60, 61, 6):
		if Places.street_at(world, x + dx).x >= 0:
			return false
	return true

static func _biome(world: TileWorld, x: int) -> String:
	for s: Dictionary in world.meta.get("biomes", []):
		if x >= int(s["x0"]) and x <= int(s["x1"]):
			return String(s["biome"])
	return "?"

## A standing spot in a cave: air with ground under it, two clear rows over it, at least 20 rows
## under the surface, nearest x first.
static func _cave(world: TileWorld, x: int, surface: int) -> Vector2i:
	for d in range(0, 200):
		for cx: int in [x + d, x - d]:
			for cy in range(surface - 20, maxi(surface - 140, 2), -1):
				if not world.is_solid(cx, cy) and world.is_solid(cx, cy - 1) \
						and not world.is_solid(cx, cy + 1) and not world.is_solid(cx, cy + 2) \
						and world.get_liquid(cx, cy) == 0:
					return Vector2i(cx, cy)
	return Vector2i(x, surface)

## A hole w wide from the ceiling over at up through the ground to open air.
static func _shaft(world: TileWorld, at: Vector2i, w: int) -> void:
	for x in range(at.x, at.x + w):
		var top := _ground(world, x)
		for y in range(at.y, top + 1):
			if world.get_fg(x, y) != TileDefs.AIR:
				world.set_fg(x, y, TileDefs.AIR, true)
	print("TORCH shaft at %d, %d wide, %d rows" % [at.x, w, _ground(world, at.x) - at.y])

## n torch tiles on the floor around at, spread left and right: each the nearest free floor cell
## to its mark, at least 5 tiles from the others.
static func _torches(world: TileWorld, at: Vector2i, n: int) -> void:
	var offs := [-10, 9, 18, -19, 27]
	var torch := TileDefs.id("torch")
	var put: Array[Vector2i] = [at]
	for i in mini(n, offs.size()):
		var best := Vector2i(-1, -1)
		var best_d := 1e9
		for ty in range(at.y - 10, at.y + 11):
			for tx in range(at.x + int(offs[i]) - 8, at.x + int(offs[i]) + 9):
				if world.get_fg(tx, ty) != TileDefs.AIR or not world.is_solid(tx, ty - 1) or world.is_solid(tx, ty + 1):
					continue
				var far := true
				for q: Vector2i in put:
					far = far and q.distance_to(Vector2i(tx, ty)) >= 5.0
				var d := Vector2(tx - at.x - int(offs[i]), (ty - at.y) * 1.5).length()
				if far and d < best_d:
					best_d = d
					best = Vector2i(tx, ty)
		if best.x >= 0:
			world.set_fg(best.x, best.y, torch, true)
			put.append(best)
			print("TORCH at %d,%d" % [best.x, best.y])

static func _ground(world: TileWorld, x: int) -> int:
	var y := world.height - 1
	while y > 0 and not world.is_solid(x, y):
		y -= 1
	return y + 1

## Every record in the chunks a client holds around the focus.
static func _records(world: TileWorld, focus: Vector2) -> Array:
	var out: Array = []
	var ccx := int(focus.x) >> 5
	var ccy := int(focus.y) >> 5
	for cy in range(maxi(ccy - 3, 0), mini(ccy + 4, world.chunks_y)):
		for cx in range(maxi(ccx - 5, 0), mini(ccx + 6, world.chunks_x)):
			for r: Dictionary in Dressing.records_in(world, cx, cy):
				out.append({"id": Dressing.name_of(r["id"]), "x": r["x"], "y": r["y"]})
	return out
