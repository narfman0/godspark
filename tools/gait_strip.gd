## Do the feet stay planted at the pace? Bodies as the game builds them (ActorBody.build), moving
## across a fixed camera at the speeds the game moves them (data/movement.json pace): one row per
## body and speed, frames left to right every dt seconds, a ruler on the ground every 0.25 m.
## A planted foot stands on the same ruler mark from frame to frame; a sliding one creeps.
## Also measured, without a picture: slide = how fast (m/s) the lowest foot moves over the
## ground while it is the lowest (0 when planted; the body's own speed when the legs stand still).
##   tools/soft_godot.sh -s res://tools/gait_strip.gd -- out=strip.png [ids=goblin-warrior,wolf]
##       [player=fighter] [moves=wander,chase] [frames=8] [dt=0.0667] [cell=200] [pace=X]
##   onion=1: instead of a strip, each body and move is one 640x220 cell holding all its frames
##       laid over each other (the darkest of each pixel: every pose stays solid; a planted foot
##       is one foot, a sliding one a streak along the ruler), two moves to a row
##   godot --headless -s res://tools/gait_strip.gd -- measure=1 [ids=...] [moves=...]  (numbers only)
##       [inplace=1: also the clip's own ground speed, from the same clip held still]
## Moves: wander (0.4 of the run, MonsterBrain), calm (0.45, Life's people), chase / run (1.0),
## sprint (2.0: a Dash spark, or a fast creature). sweep=1 forces the playback from 0.5 to 4.0
## and prints where the foot on the ground stands still (the clip's real ground speed).
extends SceneTree

const MOVES := {"wander": 0.4, "calm": 0.45, "chase": 1.0, "run": 1.0, "sprint": 2.0}
var opts := {}

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var i := a.find("=")
		opts[a.substr(0, i) if i >= 0 else a] = a.substr(i + 1) if i >= 0 else "1"
	if opts.has("pace"):
		MoveStats.pace_override = float(opts["pace"])
	_run.call_deferred()

func _rows() -> Array:
	var out := []
	var moves := String(opts.get("moves", "wander,chase")).split(",")
	var srd := SRDContent.new()
	for slug in String(opts.get("ids", "goblin-warrior,wolf,ogre")).split(",", false):
		var row: Dictionary = srd.pack.get_row("monster", slug)
		var d: Dictionary = row.get("data", {})
		var st := MoveStats.from_srd(WorldHost.monster_speeds(d), WorldHost.monster_size(d))
		for m in moves:
			out.append({"look": {"slug": slug}, "label": slug, "move": m, "v": st.run_speed * float(MOVES.get(m, 1.0))})
	if opts.has("player"):
		var st := MoveStats.player()
		for m in moves:
			out.append({"look": {"player": String(opts["player"])}, "label": "player " + String(opts["player"]), "move": m,
				"v": st.run_speed * float(MOVES.get(m, 1.0))})
	return out

func _run() -> void:
	var rows := _rows()
	var frames := int(opts.get("frames", 8))
	var dt := float(opts.get("dt", 1.0 / 15.0))
	var cell := int(opts.get("cell", 200))
	var picture := not opts.has("measure")
	var onion := opts.has("onion")
	var cw := 640 if onion else cell
	var ch := 220 if onion else cell
	var per_row := 2 if onion else 1
	var sheet := Image.create_empty(cw * (per_row if onion else frames), ch * ceili(float(rows.size()) / per_row), false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.1, 0.1, 0.1))
	var mat := StandardMaterial3D.new()
	for ri in rows.size():
		var r: Dictionary = rows[ri]
		var vp := SubViewport.new()
		vp.size = Vector2i(cw, ch)
		vp.own_world_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		var a := ActorBody.build(r["look"], mat)
		a.set_process(false)
		vp.add_child(a)
		var v: float = r["v"]
		var mps := v * K.TILE_M
		a.vel = Vector2(v, 0.0)
		a.facing = 1
		a.set_state("run")
		# warm up the cycle, then measure the slide over 2 s of 60 Hz steps
		_advance(a, v, 0.5, 1.0 / 60.0)
		var slide := _slide(a, v, 2.0)
		var clip := _clip(a)
		var ground := ""
		if opts.has("inplace"):
			# the same clip at the same playback with the body held still: its ground speed
			var g := _slide_still(a, v)
			ground = "  clip ground speed %.2f m/s at x1" % g if g != INF else ""
		print("%-26s %-6s %5.2f m/s  %-6s clip %-5s x%.2f  foot on the ground moves %s%s" % [r["label"], r["move"], mps, a.kind, clip[0], clip[1],
			"%+.2f m/s (%.0f%% of the body's speed)" % [slide, 100.0 * absf(slide) / maxf(mps, 0.01)] if slide != INF else "(no feet found)", ground])
		if opts.has("sweep"):
			var line := "    sweep:"
			var best := INF
			var best_pb := 0.0
			for k in 15:
				force_pb = 0.5 + 0.25 * k
				var sl := _slide(a, v, 1.5)
				line += " x%.2f %+.2f" % [force_pb, sl]
				if sl != INF and absf(sl) < best:
					best = absf(sl)
					best_pb = force_pb
			force_pb = 0.0
			print(line)
			print("    planted near x%.2f: the clip carries %.2f m/s at x1 (slide there %.2f m/s)" % [best_pb, mps / best_pb, best])
		if not picture:
			vp.queue_free()
			continue
		_scene(vp, a)
		var box := Vector2(a.size.x, a.size.y) * K.TILE_M
		var travel := mps * dt * (frames - 1)
		var span := maxf(box.y * 1.5, box.x * 1.6 + travel) + 0.4
		if onion:
			span = maxf(box.y * 1.25, (box.x + travel) * float(ch) / cw * 1.15) + 0.3
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = span
		var x0 := a.position.x
		cam.position = Vector3(x0 + travel * 0.5, span * 0.42, 6.0)
		cam.near = 0.05
		cam.far = 50.0
		vp.add_child(cam)
		_ruler(vp, x0 - span * 4.0, x0 + span * 4.0)
		var lab := Label.new()
		lab.text = "%s %s %.1f m/s %s x%.1f slide %.2f" % [r["label"], r["move"], mps, clip[0], clip[1], slide]
		lab.add_theme_font_size_override("font_size", 13 if onion else maxi(9, cell / 18))
		lab.add_theme_color_override("font_color", Color.WHITE)
		lab.add_theme_color_override("font_outline_color", Color.BLACK)
		lab.add_theme_constant_override("outline_size", 3)
		lab.position = Vector2(3, 3)
		var acc := PackedByteArray()
		if onion:
			lab.add_theme_color_override("font_color", Color(0.05, 0.05, 0.1))
			lab.add_theme_constant_override("outline_size", 0)
			vp.add_child(lab)
		for f in frames:
			if f == 0 and not onion:
				vp.add_child(lab)
			elif f == 1 and not onion:
				lab.visible = false
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			if onion:
				var px := img.get_data()
				if acc.is_empty():
					acc = px
				else:
					for k in px.size():
						acc[k] = mini(acc[k], px[k])
			else:
				sheet.blit_rect(img, Rect2i(0, 0, cell, cell), Vector2i(f * cell, ri * cell))
			_advance(a, v, dt, 1.0 / 60.0)
		if onion:
			var comp := Image.create_from_data(cw, ch, false, Image.FORMAT_RGB8, acc)
			sheet.blit_rect(comp, Rect2i(0, 0, cw, ch), Vector2i((ri % per_row) * cw, (ri / per_row) * ch))
		vp.queue_free()
	if picture:
		var out := String(opts.get("out", "gait_strip.png"))
		sheet.save_png(out)
		print("saved %s (%dx%d)" % [out, sheet.get_width(), sheet.get_height()])
	quit(0)

## Moves the body v tiles/s for t seconds in steps of h, its clip running as ActorBody runs it.
func _advance(a: ActorBody, v: float, t: float, h: float) -> void:
	var n := maxi(1, roundi(t / h))
	for i in n:
		if not held:
			a.position.x += v * K.TILE_M * h
		a.set_state("run")
		if force_pb > 0.0 and _anim(a) != null:
			_anim(a).speed_scale = force_pb
		a.call("_process", h)

## [clip, playback] the body plays now.
func _clip(a: ActorBody) -> Array:
	var ap := _anim(a)
	if ap == null:
		return ["-", 0.0]
	return [String(ap.current_animation), ap.speed_scale]

## The body's AnimationPlayer and Skeleton3D (forge, CharacterVisual, or a Synty creature model).
func _anim(a: ActorBody) -> AnimationPlayer:
	if a.visual == null:
		return null
	if a.kind == "forge":
		return (a.visual as ForgeMonster).anim
	if a.visual is CharacterVisual:
		return (a.visual as CharacterVisual).anim
	var found := a.visual.find_children("*", "AnimationPlayer", true, false)
	return found[0] as AnimationPlayer if not found.is_empty() else null

func _skel(a: ActorBody) -> Skeleton3D:
	if a.visual == null:
		return null
	if a.kind == "forge":
		return (a.visual as ForgeMonster).skeleton
	if a.visual is CharacterVisual and (a.visual as CharacterVisual).skeleton != null:
		return (a.visual as CharacterVisual).skeleton
	var found := a.visual.find_children("*", "Skeleton3D", true, false)
	return found[0] as Skeleton3D if not found.is_empty() else null

## The feet bones of the body: forge feet from clips.json, Synty bones named like feet.
func _feet(a: ActorBody) -> Array:
	var sk := _skel(a)
	var names: Array = []
	if sk == null:
		return []
	if a.kind == "forge":
		names = (a.visual as ForgeMonster).clip_meta.get("clips", {}).get("walk", {}).get("feet", [])
	else:
		for b in sk.get_bone_count():
			var n := sk.get_bone_name(b).to_lower()
			if (n.contains("foot") or n.contains("ankle")) and not n.contains("ik") and not n.contains("toe"):
				names.append(sk.get_bone_name(b))
	var out := []
	for n: Variant in names:
		var b := sk.find_bone(String(n))
		if b >= 0:
			out.append([sk, b])
	return out

## Median speed (m/s) along x of a foot on the ground over t seconds: the lowest foot, counted
## only while it is within 2% of the body's height of the lowest any foot gets (a run's flight
## phase has no foot down). Signed: + forward. A planted foot reads 0; legs standing still read
## the body's speed; with the body held still it is minus the clip's ground speed x playback.
func _slide(a: ActorBody, v: float, t: float) -> float:
	var feet := _feet(a)
	if feet.is_empty():
		return INF
	var h := 1.0 / 60.0
	var tol := 0.02 * a.size.y * K.TILE_M
	var samples: Array = []      # [foot, x, y] per step
	var ymin := INF
	for i in roundi(t / h):
		_advance(a, v, h, h)
		var low := -1
		var low_y := INF
		var low_x := 0.0
		for k in feet.size():
			var sk: Skeleton3D = feet[k][0]
			var p := sk.global_transform * sk.get_bone_global_pose(int(feet[k][1])).origin
			if p.y < low_y:
				low_y = p.y
				low = k
				low_x = p.x
		samples.append([low, low_x, low_y])
		ymin = minf(ymin, low_y)
	var speeds := PackedFloat32Array()
	for i in range(1, samples.size()):
		var s0: Array = samples[i - 1]
		var s1: Array = samples[i]
		if s0[0] == s1[0] and float(s0[2]) <= ymin + tol and float(s1[2]) <= ymin + tol:
			speeds.append((float(s1[1]) - float(s0[1])) / h)
	if speeds.is_empty():
		return INF
	speeds.sort()
	return speeds[speeds.size() / 2]

## The clip the body plays at speed v, held still: minus the planted foot's speed, per 1x.
func _slide_still(a: ActorBody, v: float) -> float:
	var pb := float(_clip(a)[1])
	var keep := a.position.x
	var feet := _feet(a)
	if feet.is_empty() or pb <= 0.0:
		return INF
	# _advance moves the body; move it back each step by the same amount
	var saved := a.vel
	var s := _slide_held(a, v)
	a.position.x = keep
	a.vel = saved
	return -s / pb if s != INF else INF

func _slide_held(a: ActorBody, v: float) -> float:
	held = true
	var r := _slide(a, v, 2.0)
	held = false
	return r

var held := false
## sweep=1: the playback forced over a range, to find where the foot on the ground stands still.
var force_pb := 0.0

func _scene(vp: SubViewport, a: ActorBody) -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.72, 0.82)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.58, 0.62)
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(30), 0)
	sun.light_energy = 1.1
	vp.add_child(sun)

## Ground with a mark every 0.25 m (every metre taller).
func _ruler(vp: SubViewport, x0: float, x1: float) -> void:
	var ground := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(x1 - x0, 0.04, 2.0)
	ground.mesh = gm
	ground.position = Vector3((x0 + x1) * 0.5, -0.02, -0.5)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.35, 0.3, 0.25)
	ground.material_override = gmat
	vp.add_child(ground)
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(1, 1, 0.3)
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var x := snappedf(x0, 0.25)
	while x < x1:
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var big := is_equal_approx(fposmod(x, 1.0), 0.0)
		bm.size = Vector3(0.015, 0.12 if big else 0.05, 0.02)
		m.mesh = bm
		m.position = Vector3(x, -0.04, 1.0)
		m.material_override = tmat
		vp.add_child(m)
		x += 0.25
