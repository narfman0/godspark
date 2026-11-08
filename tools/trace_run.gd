## Text-mode movement trace: runs a scripted input through PlayerController on a test
## world and prints an ASCII picture of the body's path, so jump arcs can be eyeballed
## without a renderer.
##   godot --headless -s res://tools/trace_run.gd -- scenario=runjump
## pace=X runs at X tiles a second per 30 ft instead of data/movement.json's pace.
## Scenarios: jump, tap, runjump, pit, platforms, stairs, ladder, swim, spider, sdrop (S
## drops through walkways), ladderwalk (down a ladder onto a walkway, then S), stairsup
## (W at a staircase's foot, up through a crossing walkway, back down), stairpass (along a
## walkway across a staircase, then S onto it and down); with sparks
## (data/sparks.json): airjump (Skyhook III), dash (Dash II, a double tap), glide
## (Featherfall III off a ledge).
## hash=1 prints only a SHA-256 of every step's body state (to prove a change left a
## scenario bit-identical).
## Legend: # solid  = platform  / \\ stairs  H ladder  ~ water  o feet each 3rd step  S start  E end
extends SceneTree

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if args.has("pace"):
		MoveStats.pace_override = float(args["pace"])      # pace=X: measure at another pace
	var scenario: String = args.get("scenario", "runjump")
	var world := TileWorld.make_test()
	var ground := world.height / 2
	var mid := world.width / 2
	var stats := MoveStats.player()
	var body := stats.make_body()
	var script: Callable
	var start := Vector2(mid - 40.5, ground)
	match scenario:
		"jump":
			script = func(i: int, p: PlayerInput) -> void:
				p.jump = i >= 5 and i < 60
				p.jump_pressed = i == 5
		"tap":
			script = func(i: int, p: PlayerInput) -> void:
				p.jump = i == 5
				p.jump_pressed = i == 5
		"runjump":
			script = func(i: int, p: PlayerInput) -> void:
				p.move_x = 1.0 if i < 90 else 0.0
				p.jump = i >= 20 and i < 70
				p.jump_pressed = i == 20
		"pit":
			start = Vector2(mid + 2.5, ground)
			script = func(i: int, p: PlayerInput) -> void:
				p.move_x = 1.0 if i < 80 else 0.0
				p.jump = i >= 34 and i < 80
				p.jump_pressed = i == 34
		"platforms":
			start = Vector2(mid - 2.5, ground)
			script = func(i: int, p: PlayerInput) -> void:
				p.move_x = -0.6 if i < 160 else 0.0
				p.jump = (i % 40) < 30
				p.jump_pressed = (i % 40) == 0
		"stairs":
			for k in 4:
				for x in range(mid - 30 + k * 3, mid - 10):
					world.set_fg(x, ground + k, TileDefs.id("dirt"), true)
			start = Vector2(mid - 40.5, ground)
			script = func(i: int, p: PlayerInput) -> void:
				p.move_x = 1.0 if i < 120 else 0.0
		"ladder":
			for y in range(ground, ground + 8):
				world.set_fg(mid - 30, y, TileDefs.id("ladder"), true)
			for x in range(mid - 29, mid - 22):
				world.set_fg(x, ground + 7, TileDefs.id("stone"), true)
			start = Vector2(mid - 34.5, ground)
			script = func(i: int, p: PlayerInput) -> void:
				p.move_x = 1.0 if i < 22 else (1.0 if i > 110 else 0.0)
				p.up = i >= 22 and i < 110
		"sdrop":
			# Walk along a walkway, brush S (4 steps: nothing), then hold S: drop to the
			# walkway below (S held through the landing: stays), press again: to the ground.
			for x in range(mid - 44, mid - 20):
				world.set_fg(x, ground + 12, TileDefs.id("platform"), true)
			for x in range(mid - 40, mid - 26):
				world.set_fg(x, ground + 6, TileDefs.id("platform"), true)
			start = Vector2(mid - 42.5, ground + 13)
			script = func(i: int, p: PlayerInput) -> void:
				p.move_x = 0.5 if i < 40 else 0.0
				p.down = (i >= 15 and i < 19) or (i >= 50 and i < 120) or (i >= 140 and i < 200)
		"ladderwalk":
			# Climb down a ladder that ends on a walkway with S held: it stops there; walk
			# off it, then a fresh S drops to the ground.
			for x in range(mid - 36, mid - 24):
				world.set_fg(x, ground + 6, TileDefs.id("platform"), true)
			for y in range(ground + 7, ground + 16):
				world.set_fg(mid - 30, y, TileDefs.id("ladder"), true)
			start = Vector2(mid - 29.5, ground + 16)
			script = func(i: int, p: PlayerInput) -> void:
				p.down = i < 100 or (i >= 160)
				p.move_x = 1.0 if i >= 110 and i < 140 else 0.0
		"stairsup", "stairpass":
			# A staircase rising right from the ground to a walkway, crossed half way up by a
			# lower walkway (the tread wins the crossing cell).
			for x in range(mid - 46, mid - 30):
				world.set_fg(x, ground + 8, TileDefs.id("platform"), true)
			for x in range(mid - 66, mid - 40):
				world.set_fg(x, ground + 4, TileDefs.id("platform"), true)
			for i in 9:
				world.set_fg(mid - 55 + i, ground + i, TileDefs.id("stairs_r"), true)
			if scenario == "stairsup":
				# W at the foot only; it climbs to the top, turns and runs back down to the ground.
				start = Vector2(mid - 60.5, ground)
				script = func(i: int, p: PlayerInput) -> void:
					p.move_x = 1.0 if i < 75 else (-1.0 if i >= 95 and i < 200 else 0.0)
					p.up = i >= 20 and i < 30
			else:
				# Along the lower walkway past the staircase (no W: stays on it), back, then S
				# (standing) drops onto the stairs below and it runs down them.
				start = Vector2(mid - 64.5, ground + 5)
				script = func(i: int, p: PlayerInput) -> void:
					p.move_x = 1.0 if i < 70 else (-1.0 if i >= 80 and i < 106 else 0.0)
					p.down = i >= 120 and i < 140
					if i >= 160:
						p.move_x = -1.0
		"swim":
			for x in range(mid + 10, mid + 16):
				for y in range(ground - 5, ground):
					world.set_liquid(x, y, 15, true)
			start = Vector2(mid + 4.5, ground)
			script = func(i: int, p: PlayerInput) -> void:
				p.move_x = 1.0 if i < 60 else 0.0
				p.jump = i > 100 and i < 150
				p.jump_pressed = i == 101 or i == 150
				if i >= 150:
					p.move_x = 1.0
		"spider":
			stats = MoveStats.from_srd({"walk": 30, "climb": 30}, "large")
			body = stats.make_body()
			for x in range(mid - 30, mid - 26):
				for y in range(ground, ground + 8):
					world.set_fg(x, y, TileDefs.id("stone"), true)
			start = Vector2(mid - 40.5, ground)
			script = func(i: int, p: PlayerInput) -> void:
				p.move_x = 1.0
		"airjump":
			stats = Sparks.move_stats({"walk": 30}, "medium", [{"id": "skyhook", "rank": 2}])
			script = func(i: int, p: PlayerInput) -> void:
				p.move_x = 1.0 if i < 100 else 0.0
				p.jump = (i >= 5 and i < 40) or (i >= 30 and i < 55) or (i >= 55 and i < 80)
				p.jump_pressed = i == 5 or i == 30 or i == 55
		"dash":
			stats = Sparks.move_stats({"walk": 30}, "medium", [{"id": "dash", "rank": 1}])
			script = func(i: int, p: PlayerInput) -> void:
				p.move_x = 1.0 if (i < 3 or (i >= 8 and i < 60)) else 0.0
		"glide":
			stats = Sparks.move_stats({"walk": 30}, "medium", [{"id": "featherfall", "rank": 2}])
			for x in range(mid - 44, mid - 36):
				for y in range(ground, ground + 12):
					world.set_fg(x, y, TileDefs.id("stone"), true)
			start = Vector2(mid - 37.5, ground + 12)
			script = func(i: int, p: PlayerInput) -> void:
				p.move_x = 1.0 if i < 30 else 0.0
				p.jump = i >= 10
				p.jump_pressed = i == 10
		_:
			print("unknown scenario ", scenario)
			quit(1)
			return
	body.pos = start
	var dt := 1.0 / MoveStats.step_hz()
	var path: Array[Vector2] = [body.pos]
	var peak := body.pos.y
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for i in 240:
		var p := PlayerInput.new()
		script.call(i, p)
		PlayerController.step(world, body, p, stats, dt)
		path.append(body.pos)
		peak = maxf(peak, body.pos.y)
		ctx.update(var_to_bytes([body.pos, body.vel, body.on_floor, body.on_wall, body.on_ceiling,
				body.climbing, body.swimming, body.clinging, body.flying, body.jumping, body.drop_y,
				body.coyote, body.jump_buffer, body.stepped, body.facing]))
	var digest := ctx.finish().hex_encode()
	if args.has("hash"):
		print("HASH %s %s" % [scenario, digest])
		quit(0)
		return
	_draw(world, path)
	print("scenario %s: start %s end %s, peak feet %.2f (%.2f above start), run speed %.2f t/s" % [
			scenario, start, body.pos, peak, peak - start.y, stats.run_speed])
	quit(0)

func _draw(world: TileWorld, path: Array[Vector2]) -> void:
	var x0 := 1 << 30
	var x1 := -(1 << 30)
	var y0 := 1 << 30
	var y1 := -(1 << 30)
	for p in path:
		x0 = mini(x0, floori(p.x))
		x1 = maxi(x1, floori(p.x))
		y0 = mini(y0, floori(p.y))
		y1 = maxi(y1, floori(p.y))
	x0 -= 6
	x1 += 6
	y0 -= 3
	y1 += 5
	var marks := {}
	for i in path.size():
		var c := Vector2i(floori(path[i].x), floori(path[i].y))
		if i % 3 == 0:
			marks[c] = "o"
	marks[Vector2i(floori(path[0].x), floori(path[0].y))] = "S"
	marks[Vector2i(floori(path[-1].x), floori(path[-1].y))] = "E"
	for y in range(y1, y0 - 1, -1):
		var line := "%4d " % y
		for x in range(x0, x1 + 1):
			var c := Vector2i(x, y)
			if marks.has(c):
				line += marks[c]
				continue
			var id := world.get_fg(x, y)
			if TileDefs.solid[id]:
				line += "#"
			elif TileDefs.stairs[id] == 1:
				line += "/"
			elif TileDefs.stairs[id] == 2:
				line += "\\"
			elif TileDefs.platform[id]:
				line += "="
			elif TileDefs.ladder[id]:
				line += "H"
			elif world.get_liquid(x, y) & 15:
				line += "~"
			else:
				line += "."
		print(line)
	print("     x %d..%d" % [x0, x1])
