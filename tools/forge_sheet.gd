## A proof sheet of creature bodies as the game builds them (ActorBody.build: the looks chain,
## the box clamp, LitMaterials, facing), one cell each: the collision box drawn as a frame, the
## ground at the feet, the slug and body kind (forge / synty / primitive) under it.
## Needs a renderer:
##   tools/soft_godot.sh -s res://tools/forge_sheet.gd -- out=sheet.png [ids=wolf,ape | pick=40]
##       [state=idle|walk|attack|hit|death] [at=0.5: how far into the clip] [light=day|torch]
##       [cols=8] [cell=160] [no_forge=1: the same slugs without their forge body]
##       [forge=1: the same slugs as if no Synty file were fetched: their forge body, to compare]
##       [weapons=1: forge bodies hold what they wield (game/view_presenter.gd does the same)]
## pick=N: N synced monsters spread over the body plans (deterministic).
extends SceneTree

var opts := {}

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var i := a.find("=")
		opts[a.substr(0, i) if i >= 0 else a] = a.substr(i + 1) if i >= 0 else "1"
	_run.call_deferred()

func _ids() -> PackedStringArray:
	if opts.has("ids"):
		return String(opts["ids"]).split(",")
	var n := int(opts.get("pick", 40))
	var by_plan := {}
	var cr := Looks.creatures()
	for slug: String in cr.keys():
		if ForgeMonster.is_synced(slug):
			var p := String(cr[slug].get("plan", "?"))
			if not by_plan.has(p):
				by_plan[p] = []
			by_plan[p].append(slug)
	var plans := by_plan.keys()
	plans.sort()
	for p: String in plans:
		by_plan[p].sort()
	var out := PackedStringArray()
	var round_i := 0
	while out.size() < n:
		var added := false
		for p: String in plans:
			var list: Array = by_plan[p]
			# spread over each plan's list instead of its first few names
			var k := (round_i * 7) % maxi(list.size(), 1)
			if round_i < list.size() and out.size() < n and not list[k] in out:
				out.append(list[k])
				added = true
		round_i += 1
		if not added and round_i > 400:
			break
	return out

func _run() -> void:
	var ids := _ids()
	var cell := int(opts.get("cell", 160))
	var cols := int(opts.get("cols", 8))
	var rows := ceili(float(ids.size()) / cols)
	var sheet := Image.create_empty(cell * cols, cell * rows, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.1, 0.1, 0.1))
	var state := String(opts.get("state", "idle"))
	var at := float(opts.get("at", 0.5))
	var torch := String(opts.get("light", "day")) == "torch"
	var mat := StandardMaterial3D.new()      # (the game's placeholder shader is WorldView's)
	var counts := {}
	for i in ids.size():
		var slug := ids[i]
		var vp := SubViewport.new()
		vp.size = Vector2i(cell, cell)
		vp.own_world_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color(0.05, 0.05, 0.07) if torch else Color(0.62, 0.72, 0.82)
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color(0.08, 0.08, 0.1) if torch else Color(0.55, 0.58, 0.62)
		env.environment.ambient_light_energy = 1.0
		vp.add_child(env)
		var look := {"slug": slug}
		if opts.has("no_forge"):
			look["no_forge"] = true
		var t0 := Time.get_ticks_usec()
		var a := ActorBody.build(look, mat, (func(p: String) -> bool: return not p.begins_with("res://assets/meshes/") and FileAccess.file_exists(p)) if opts.has("forge") else Callable())
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		a.set_process(false)
		vp.add_child(a)
		counts[a.kind] = counts.get(a.kind, 0) + 1
		var box := Vector2(a.size.x, a.size.y) * K.TILE_M
		if torch:
			var l := OmniLight3D.new()
			l.position = Vector3(box.x * 0.9, box.y * 0.8, 1.2)
			l.omni_range = maxf(box.y, box.x) * 2.5 + 3.0
			l.light_color = Color(1.0, 0.7, 0.4)
			l.light_energy = 2.0
			vp.add_child(l)
		else:
			var sun := DirectionalLight3D.new()
			sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(30), 0)
			sun.light_energy = 1.1
			vp.add_child(sun)
		# ground and the collision box frame
		var ground := MeshInstance3D.new()
		var gm := BoxMesh.new()
		gm.size = Vector3(box.x * 6.0 + 4.0, 0.04, 2.0)
		ground.mesh = gm
		ground.position = Vector3(0, -0.02, -0.5)
		var gmat := StandardMaterial3D.new()
		gmat.albedo_color = Color(0.35, 0.3, 0.25)
		ground.material_override = gmat
		vp.add_child(ground)
		var fmat := StandardMaterial3D.new()
		fmat.albedo_color = Color(1, 1, 0.2)
		fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		for e in [[Vector3(0, box.y, 0), Vector3(box.x, 0.02, 0.02)], [Vector3(-box.x * 0.5, box.y * 0.5, 0), Vector3(0.02, box.y, 0.02)],
				[Vector3(box.x * 0.5, box.y * 0.5, 0), Vector3(0.02, box.y, 0.02)]]:
			var m := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = e[1]
			m.mesh = bm
			m.position = e[0] + Vector3(0, 0, -2.5)
			m.material_override = fmat
			vp.add_child(m)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		var vis := GltfCache.visible_aabb(a)
		var span := maxf(maxf(box.y, box.x * 2.2), maxf(vis.size.y, vis.size.x)) * 1.25 + 0.2
		cam.size = span
		cam.position = Vector3(0, span * 0.42, 6.0)
		cam.near = 0.05
		cam.far = 50.0
		vp.add_child(cam)
		var lab := Label.new()
		lab.text = "%s\n%s %.0fms" % [slug, a.kind, ms]
		lab.add_theme_font_size_override("font_size", maxi(9, cell / 16))
		lab.add_theme_color_override("font_color", Color.WHITE)
		lab.add_theme_color_override("font_outline_color", Color.BLACK)
		lab.add_theme_constant_override("outline_size", 3)
		lab.position = Vector2(3, cell - cell / 6)
		vp.add_child(lab)
		if opts.has("weapons") and a.kind == "forge":
			a.set_weapon((a.visual as ForgeMonster).wielded())
		_pose(a, state, at)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(img, Rect2i(0, 0, cell, cell), Vector2i((i % cols) * cell, (i / cols) * cell))
		var extra := ""
		if a.kind == "forge":
			var fm := a.visual as ForgeMonster
			extra = "scale %.2f h %.2f m ground %.2f m/s clips %s" % [fm.scale.x, vis.size.y, fm.ground_speed() * fm.scale.x, ",".join(fm.clips())]
		print("%-28s %-9s %6.0f ms box %.2fx%.2f m  %s" % [slug, a.kind, ms, box.x, box.y, extra])
		vp.queue_free()
	var out := String(opts.get("out", "forge_sheet.png"))
	sheet.save_png(out)
	print("bodies %s; saved %s" % [counts, out])
	quit(0)

## Puts the body in a state, `at` (0..1) through its clip.
func _pose(a: ActorBody, state: String, at: float) -> void:
	match a.kind:
		"forge":
			var m := a.visual as ForgeMonster
			var c := state
			match state:
				"walk": c = m.move_clip()
				"attack": c = "attack_melee" if m.has_clip("attack_melee") else m.move_clip()
			if not m.has_clip(c):
				c = "idle"
			m.anim.play(c)
			m.anim.seek(m.anim.get_animation(c).length * at, true)
		"synty":
			a.vel = Vector2(2.0, 0.0) if state == "walk" else Vector2.ZERO
			a.set_state("run" if state == "walk" else state)
			if a.visual.has_method("step"):
				a.visual.call("step", 0.4, state == "walk")
