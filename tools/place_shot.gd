## Screenshot of a generated place, with its dressing records and a few people for scale.
## Runs under tools/soft_godot.sh (CPU Vulkan).
##   tools/soft_godot.sh -s res://tools/place_shot.gd -- out=/tmp/x.png [seed=1] [size=dev]
##     [site=N | style=human|halfling|dwarf|elf|drow|raider [tier=town]] [route=N (a bridge on it)]
##     [dx=0 dy=0 (camera offset, tiles)] [zoom=1] [sun=1 (0 = night)] [w=1280 h=720]
## Without site/style it picks the biggest surface place. Prints what it framed.
extends SceneTree

func _initialize() -> void:
	var o := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		o[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var size := Vector2i(int(o.get("w", 1280)), int(o.get("h", 720)))
	DisplayServer.window_set_size(size)
	root.size = size
	var world := WorldGen.generate_named(String(o.get("size", "dev")), int(o.get("seed", "1")))
	var focus := Vector2(world.width / 2.0, world.height / 2.0)
	var label := ""
	var people: Array = []
	if o.has("route"):
		var path := Places.route_path(world, int(o["route"]))
		var best: Vector2i = path[path.size() / 2] if not path.is_empty() else Vector2i.ZERO
		var bi := path.size() / 2
		for i in path.size():   # the first bridge cell, if any
			if world.get_fg(path[i].x, path[i].y - 1) == TileDefs.id("bridge"):
				best = path[i]
				bi = i
				break
		focus = Vector2(best) + Vector2(0, 4)
		label = "route %s at %s" % [o["route"], best]
		var pp: Vector2i = path[maxi(0, bi - 4)] if not path.is_empty() else best
		people.append(["player", Vector2(pp.x + 0.5, pp.y)])
	else:
		var pick := -1
		var biggest := -1
		for k: String in Places.all(world):
			var p: Dictionary = Places.all(world)[k]
			if o.has("site") and k != String(o["site"]):
				continue
			if o.has("style") and p["style"] != o["style"]:
				continue
			if o.has("tier") and p["tier"] != o["tier"]:
				continue
			if p["buildings"].is_empty():
				continue
			var n: int = p["buildings"].size()
			if n > biggest:
				biggest = n
				pick = int(k)
		if pick < 0:
			print("place_shot: no such place")
			quit(1)
			return
		var pl := Places.place(world, pick)
		var st: Array = pl["street"]
		focus = Vector2((int(st[0]) + int(st[1])) / 2.0, int(st[2]) + 6)
		label = "site %d %s %s (%s) street %s" % [pick, pl["culture"], pl["tier"], pl["style"], st]
		var y := int(st[2])
		people.append(["player", Vector2(focus.x - 6.5, y)])
		for role: String in ["smith", "merchant", "keeper", "priest", "guard", "townsfolk"]:
			var an := Places.anchors(world, pick, role)
			for i in mini(an.size(), 3):
				people.append([pl["culture"], Vector2(an[i].x + 0.5, an[i].y)])
	focus += Vector2(float(o.get("dx", 0)), float(o.get("dy", 0)))
	var light := LightEngine.new(world)
	light.sun = float(o.get("sun", 1.0))
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.background_color = WorldView.sky_color(light.sun)
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var view := WorldView.new()
	root.add_child(view)
	view.setup(world, light)
	var rig := CameraRig.new()
	root.add_child(rig)
	rig.zoom = float(o.get("zoom", 1.0))
	rig.target = focus
	rig.snap()
	var id := 1
	for p: Array in people:
		var look := {"player": "fighter", "name": "Ash"} if p[0] == "player" else {"people": String(p[0]), "name": String(p[0])}
		view.add_actor(id, look)
		view.move_actor(id, p[1], 1 if id % 2 == 0 else -1)
		id += 1
	var dv := DressingView.new()
	root.add_child(dv)
	var recs: Array = []
	var cx0 := maxi(0, int(focus.x - 80) >> 5)
	var cx1 := mini(world.chunks_x - 1, int(focus.x + 80) >> 5)
	var cy0 := maxi(0, int(focus.y - 50) >> 5)
	var cy1 := mini(world.chunks_y - 1, int(focus.y + 50) >> 5)
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			for r: Dictionary in Dressing.records_in(world, cx, cy):
				recs.append({"id": Dressing.name_of(r["id"]), "x": r["x"], "y": r["y"], "v": r["v"]})
	dv.set_objects(recs)
	var frames := 0
	while frames < 900:
		view.view_half = rig.visible_half_extent()
		view.set_focus(rig.pos)
		await process_frame
		frames += 1
		if frames > 5 and view.is_idle():
			break
	for i in 3:
		await RenderingServer.frame_post_draw
	var out := String(o.get("out", "/tmp/place_shot.png"))
	root.get_texture().get_image().save_png(out)
	print("place_shot: %s -> %s (%d records, %s drawn)" % [label, out, recs.size(), dv.counts])
	quit()
