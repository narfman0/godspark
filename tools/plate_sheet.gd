## A proof sheet of every hit point plate form (view/fx/nameplates.gd) as Nameplates draws it,
## with what Nameplates.show_rule decides for each case written under it. Needs a renderer:
##   tools/soft_godot.sh -s res://tools/plate_sheet.gd -- out=plates.png [bg=shot.png] [scale=1.5]
extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var o := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		o[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var size := Vector2i(1280, 560)
	DisplayServer.window_set_size(size)
	root.size = size
	var bg := ColorRect.new()
	bg.color = Color(0.36, 0.52, 0.42)
	bg.size = Vector2(size)
	root.add_child(bg)
	if o.has("bg"):
		var img := Image.load_from_file(String(o["bg"]))
		if img != null:
			var tr := TextureRect.new()
			tr.texture = ImageTexture.create_from_image(img)
			tr.size = Vector2(size)
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tr.modulate = Color(1, 1, 1, 0.6)
			root.add_child(tr)
	var np := Nameplates.new()
	root.add_child(np)
	var sc := float(o.get("scale", 1.5))
	var H := Nameplates.HOLD_S
	var F := Nameplates.FADE_S
	# [label, hp, max, since, hovered, player, downed, rank, affixes, name]
	var cases := [
		["goblin, hit 1 s ago", 5, 12, 1.0, false, false, false, "", [], "Goblin Warrior"],
		["goblin, %.1f s: fading" % (H + F * 0.5), 5, 12, H + F * 0.5, false, false, false, "", [], "Goblin Warrior"],
		["goblin, hurt, 20 s ago", 5, 12, 20.0, false, false, false, "", [], "Goblin Warrior"],
		["goblin, full, fighting", 12, 12, INF, false, false, false, "", [], "Goblin Warrior"],
		["goblin, full, hovered", 12, 12, INF, true, false, false, "", [], "Goblin Warrior"],
		["minion, hit", 2, 7, 0.5, false, false, false, "minion", [], "Goblin Minion"],
		["elite, hit", 30, 52, 0.5, false, false, false, "elite", ["Shielded"], "Hobgoblin Captain"],
		["champion, hit", 20, 65, 0.5, false, false, false, "champion", ["Frenzied", "Gilded"], "Ogre"],
		["boss, hit", 90, 120, 0.5, false, false, false, "boss", [], "Troll"],
		["boss, full, hovered", 120, 120, INF, true, false, false, "boss", [], "Troll"],
		["player, hit", 31, 51, 0.5, false, true, false, "", [], "Wren"],
		["player, down", 0, 51, 30.0, false, true, true, "", [], "Wren"],
	]
	var cols := 4
	var cw := size.x / cols
	for i in cases.size():
		var c: Array = cases[i]
		var rule := Nameplates.show_rule(c[1], c[2], c[3], c[4], c[5], c[6], String(c[7]) in ["boss", "champion", "elite"])
		var at := Vector2(cw * (i % cols) + cw * 0.5, 130.0 + 170.0 * (i / cols))
		var lab := Label.new()
		lab.text = "%s\n%s" % [c[0], "nothing" if float(rule["alpha"]) <= 0.0 else "alpha %.2f%s%s" % [rule["alpha"], ", bar" if rule["bar"] else "", ", name" if rule["name"] else ""]]
		lab.position = at + Vector2(-cw * 0.5 + 8, 12)
		lab.size = Vector2(cw - 16, 40)
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.add_theme_color_override("font_color", Color.WHITE)
		lab.add_theme_color_override("font_outline_color", Color.BLACK)
		lab.add_theme_constant_override("outline_size", 4)
		root.add_child(lab)
		var head := ColorRect.new()     # where the creature's head is
		head.color = Color(0, 0, 0, 0.5)
		head.position = at + Vector2(-14, 0)
		head.size = Vector2(28, 8)
		root.add_child(head)
		if float(rule["alpha"]) <= 0.0:
			continue
		var plate := np.plates[i]
		var affs: Array = c[8]
		var compact := not bool(rule["name"])
		var d := {"id": i, "name": c[9], "hp": c[1], "max": c[2], "rank": c[7], "affixes": affs, "player": c[5],
			"downed": c[6], "named": rule["name"], "has_bar": rule["bar"], "bar": compact}
		np._data[i] = d
		plate.scale = Vector2(sc, sc)
		plate.position = Vector2(at.x - Nameplates.W * 0.5 * sc, at.y - Nameplates.H * sc)
		plate.modulate.a = float(rule["alpha"])
		plate.visible = true
		plate.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var out := String(o.get("out", "user://plates.png"))
	root.get_texture().get_image().save_png(out)
	print("PLATES wrote ", out)
	quit()
