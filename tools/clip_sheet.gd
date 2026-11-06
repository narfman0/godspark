## A contact sheet of the moves in data/looks.json "swings": a body in the game's side view at
## evenly spaced moments of each move, the frame at the contact framed in red. For choosing
## the moves' times by eye. Needs a renderer:
##   tools/soft_godot.sh -s res://tools/clip_sheet.gd -- out=sheet.png [model=knight]
##       [weapon=longsword] [moves=slash_a,slash_b] [frames=8] [size=220]
## even=1: spaced evenly over the move's whole span, ignoring the contact.
## Forge monsters' clips: forge=goblin-warrior [clips=attack_melee].
extends SceneTree

var opts := {}

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var i := a.find("=")
		opts[a.substr(0, i) if i >= 0 else a] = a.substr(i + 1) if i >= 0 else "1"
	_run.call_deferred()

func _run() -> void:
	var size := int(opts.get("size", 220))
	var n := int(opts.get("frames", 8))
	var vp := SubViewport.new()
	vp.size = Vector2i(size, size)
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.82, 0.86, 0.9)
	vp.add_child(env)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.0, 4.4)
	cam.fov = 40.0
	vp.add_child(cam)
	var turn := Node3D.new()
	turn.rotation.y = ActorBody.SIDE_YAW
	vp.add_child(turn)
	var rows: Array = []     # [label, [segments...]]
	var layer: SwingLayer
	var skel: Skeleton3D
	if opts.has("forge"):
		var m := ForgeMonster.load_monster(String(opts["forge"]))
		turn.add_child(m)
		m.scale = Vector3.ONE * minf(1.0, 1.9 / maxf(m.aabb.size.y, 0.01))
		m.set_weapon(m.wielded())
		for c: String in String(opts.get("clips", "attack_melee")).split(","):
			if m.has_clip(c):
				m.layer.add_clip(c, m.anim.get_animation(c))
				rows.append([c, 0.0, m.contact_of(c), m.anim.get_animation(c).length, c])
		layer = m.layer
		skel = m.skeleton
	else:
		var t := Looks.table()
		var cv := CharacterVisual.new()
		if not cv.setup(t["models"][String(opts.get("model", "knight"))], t.get("clips", {}), 1.8):
			printerr("no model")
			quit(1)
			return
		turn.add_child(cv)
		cv.set_weapon(String(opts.get("weapon", "longsword")))
		var moves: Dictionary = SwingPlan.conf()["moves"]
		var names: PackedStringArray = String(opts.get("moves", ",".join(PackedStringArray(moves.keys())))).split(",")
		for name in names:
			var mv: Dictionary = moves[name]
			for part: String in ["pre", "post"]:
				cv.load_swing_clip(String(mv[part][0]))
			rows.append([name, float(mv["pre"][1]), float(mv["pre"][2]), float(mv["post"][2]), String(mv["pre"][0]), String(mv["post"][0]), float(mv["post"][1])])
		layer = cv.layer
		skel = cv.skeleton
	var sheet := Image.create_empty(size * n, size * rows.size(), false, Image.FORMAT_RGB8)
	for r in rows.size():
		var row: Array = rows[r]
		for i in n:
			var f := float(i) / float(n - 1)
			# half the sheet before the contact, half after
			var pre_part := f <= 0.5
			var time: float = lerpf(row[1], row[2], f * 2.0) if pre_part else lerpf(row[2] if row.size() < 7 else row[6], row[3], (f - 0.5) * 2.0)
			var clip: String = row[4] if pre_part or row.size() < 7 else row[5]
			if opts.has("even"):
				time = lerpf(row[1], row[3], f)
				clip = row[4]
			layer.plan = [{"clip": clip, "from": time, "to": time, "start": 0.0, "dur": 10.0}]
			layer.fade_in = 0.0
			layer.fade_out = 0.0
			layer._end = 10.0
			layer.t = 1.0
			layer.lower = 1.0
			for b in skel.get_bone_count():
				skel.set_bone_pose_rotation(b, skel.get_bone_rest(b).basis.get_rotation_quaternion())
			layer.step(0.0, false)
			await process_frame
			await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			if absf(f - 0.5) < 0.5 / float(n - 1) + 1e-4 and f <= 0.5:
				img.fill_rect(Rect2i(0, 0, size, 3), Color.RED)
			sheet.blit_rect(img, Rect2i(0, 0, size, size), Vector2i(i * size, r * size))
		print("row %d %s: %.3f %.3f %.3f" % [r, row[0], row[1], row[2], row[3]])
	sheet.save_png(String(opts.get("out", "sheet.png")))
	print("saved ", opts.get("out", "sheet.png"))
	quit(0)
