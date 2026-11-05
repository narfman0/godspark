extends RefCounted

const DT := 1.0 / 60.0
const Col := preload("res://tests/test_collision.gd")

func run(t: TestLog) -> void:
	_run_speed(t)
	_jump(t)
	_ledge(t)
	_coyote(t)
	_buffer(t)
	_step_up(t)
	_platforms(t)
	_ladder(t)
	_swim(t)
	_climb_and_fly(t)
	_determinism(t)
	_input_bytes(t)

static func inp(move_x := 0.0, jump := false, jump_pressed := false, up := false, down := false) -> PlayerInput:
	var p := PlayerInput.new()
	p.move_x = move_x
	p.jump = jump
	p.jump_pressed = jump_pressed
	p.up = up
	p.down = down
	return p

## Step `n` times with input from script.call(i) -> PlayerInput; returns the feet positions
## after each step.
static func sim(world: TileWorld, body: Body, stats: MoveStats, n: int, script: Callable) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in n:
		PlayerController.step(world, body, script.call(i), stats, DT)
		out.append(body.pos)
	return out

static func peak(path: Array[Vector2]) -> float:
	var m := -INF
	for p in path:
		m = maxf(m, p.y)
	return m

func _run_speed(t: TestLog) -> void:
	var world := Col.flat(256)
	var stats := MoveStats.player()
	var body := stats.make_body()
	body.pos = Vector2(10.5, 8)
	var path := sim(world, body, stats, 60, func(_i): return inp(1.0))
	t.eq(body.vel.x, 13.0, "walk 30 runs at 13 tiles/s")
	var steps_to_top := 0
	for i in path.size() - 1:
		if path[i + 1].x - path[i].x >= 13.0 * DT - 1e-4:
			steps_to_top = i + 1
			break
	t.check(steps_to_top > 0 and steps_to_top <= 9, "reaches top speed within 0.15 s (step %d)" % steps_to_top)
	sim(world, body, stats, 20, func(_i): return inp())
	t.eq(body.vel.x, 0.0, "friction stops it within 20 steps")
	var fast := MoveStats.from_srd({"walk": 40})
	t.check(absf(fast.run_speed - 13.0 * 40.0 / 30.0) < 1e-6, "walk 40 is proportionally faster (%.2f)" % fast.run_speed)
	t.eq(body.facing, 1, "facing follows the last move")

func _jump(t: TestLog) -> void:
	var world := Col.flat(256)
	var stats := MoveStats.player()
	var body := stats.make_body()
	body.pos = Vector2(10.5, 8)
	var full := peak(sim(world, body, stats, 90, func(i): return inp(0, true, i == 0))) - 8.0
	t.check(full >= 6.2 and full <= 6.8, "a held jump rises 6.2-6.8 tiles (%.2f)" % full)
	t.eq(body.pos, Vector2(10.5, 8), "and lands back where it started")
	var tap := peak(sim(world, body, stats, 90, func(i): return inp(0, i == 0, i == 0))) - 8.0
	t.check(tap < full * 0.4, "a tapped jump is under 40%% of a full one (%.2f)" % tap)
	t.check(tap > 1.0, "a tapped jump still clears a tile (%.2f)" % tap)
	var mid := peak(sim(world, body, stats, 90, func(i): return inp(0, i < 8, i == 0))) - 8.0
	t.check(mid > tap and mid < full, "releasing after 8 steps gives an in-between height (%.2f)" % mid)

	# running jump distance on flat ground: from takeoff to touchdown
	body.pos = Vector2(10.5, 8)
	var path := sim(world, body, stats, 150, func(i): return inp(1.0, i >= 40, i == 40))
	var takeoff := path[39].x
	var land := -1.0
	for i in range(41, path.size()):
		if path[i].y == 8.0:
			land = path[i].x
			break
	var dist := land - takeoff
	t.check(dist >= 8.0 and dist <= 12.0, "a full running jump carries 8-12 tiles (%.2f)" % dist)

func _ledge(t: TestLog) -> void:
	var world := Col.flat(64)
	Col.fill(world, 0, 8, 20, 14, TileDefs.id("stone"))   # a 6-tile high ledge ending at x = 20
	var stats := MoveStats.player()
	var body := stats.make_body()
	body.pos = Vector2(15.5, 14)
	sim(world, body, stats, 40, func(_i): return inp(1.0))
	sim(world, body, stats, 60, func(_i): return inp())
	t.eq(body.pos.y, 8.0, "walking off a ledge lands on the ground below")
	t.check(body.on_floor and body.pos.x > 20.75, "on the floor past the ledge (x %.2f)" % body.pos.x)

## Steps until the body first leaves the floor walking right off the ledge.
static func _leave_step(world: TileWorld, stats: MoveStats) -> int:
	var body := stats.make_body()
	body.pos = Vector2(15.5, 14)
	for i in 100:
		PlayerController.step(world, body, inp(1.0), stats, DT)
		if not body.on_floor:
			return i
	return -1

func _coyote(t: TestLog) -> void:
	var world := Col.flat(64)
	Col.fill(world, 0, 8, 20, 14, TileDefs.id("stone"))
	var stats := MoveStats.player()
	var leave := _leave_step(world, stats)
	t.check(leave > 0, "found the step the body leaves the ledge (%d)" % leave)
	var results := {}
	for late in [1, 3, 5, 6, 9]:
		var body := stats.make_body()
		body.pos = Vector2(15.5, 14)
		var path := sim(world, body, stats, leave + late + 3, func(i): return inp(1.0, i >= leave + late, i == leave + late))
		results[late] = peak(path.slice(leave + late)) > 14.0
	t.check(results[1] and results[3] and results[5], "a jump 1-5 steps after leaving the ledge still fires (coyote)")
	t.check(not results[6] and not results[9], "a jump 6+ steps after leaving does not")

func _buffer(t: TestLog) -> void:
	var world := Col.flat(64)
	var stats := MoveStats.player()
	var body := stats.make_body()
	body.pos = Vector2(10.5, 20)
	var path := sim(world, body, stats, 120, func(_i): return inp())
	var land := -1
	for i in path.size():
		if path[i].y == 8.0:
			land = i
			break
	t.check(land > 0, "found the landing step (%d)" % land)
	var fired := {}
	for early in [1, 4, 6, 7, 12]:
		var b := stats.make_body()
		b.pos = Vector2(10.5, 20)
		var press: int = land - early
		var p := sim(world, b, stats, land + 6, func(i): return inp(0, i >= press, i == press))
		fired[early] = p[land + 5].y > 8.5
	t.check(fired[1] and fired[4] and fired[6], "a jump pressed up to 6 steps (0.1 s) before landing fires on landing (buffer)")
	t.check(not fired[7] and not fired[12], "pressed 7+ steps early it is dropped")

func _step_up(t: TestLog) -> void:
	var stats := MoveStats.player()
	var one := Col.flat(64)
	Col.fill(one, 30, 8, 64, 9, TileDefs.id("stone"))
	var body := stats.make_body()
	body.pos = Vector2(20.5, 8)
	var path := sim(one, body, stats, 90, func(_i): return inp(1.0))
	t.check(body.pos.x > 35.0 and body.pos.y == 9.0, "steps up a 1-tile ledge while running (%s)" % body.pos)
	var dips := 0
	for i in range(1, path.size()):
		if path[i].y < path[i - 1].y:
			dips += 1
	t.eq(dips, 0, "the step-up never dips or bounces")

	var two := Col.flat(64)
	Col.fill(two, 30, 8, 64, 10, TileDefs.id("stone"))
	body = stats.make_body()
	body.pos = Vector2(20.5, 8)
	sim(two, body, stats, 90, func(_i): return inp(1.0))
	t.eq(body.pos, Vector2(29.25, 8), "does not step up a 2-tile ledge")

	var low := Col.flat(64)
	Col.fill(low, 30, 8, 64, 9, TileDefs.id("stone"))
	Col.fill(low, 20, 11, 64, 12, TileDefs.id("stone"))   # ceiling 3 tiles above the floor
	body = stats.make_body()
	body.pos = Vector2(22.5, 8)
	sim(low, body, stats, 90, func(_i): return inp(1.0))
	t.eq(body.pos, Vector2(29.25, 8), "does not step up into a ceiling")

	var down := Col.flat(64)
	Col.fill(down, 0, 8, 30, 9, TileDefs.id("stone"))
	body = stats.make_body()
	body.pos = Vector2(20.5, 9)
	path = sim(down, body, stats, 60, func(_i): return inp(1.0))
	var airborne := 0
	for i in path.size():
		if path[i].y != 9.0 and path[i].y != 8.0:
			airborne += 1
	t.check(body.pos.y == 8.0 and airborne == 0, "walks down a 1-tile step without a fall (in air %d steps)" % airborne)

func _platforms(t: TestLog) -> void:
	var world := Col.flat(64)
	Col.fill(world, 20, 12, 30, 13, TileDefs.id("platform"))   # top at y = 13
	var stats := MoveStats.player()
	var body := stats.make_body()
	body.pos = Vector2(25, 8)
	sim(world, body, stats, 90, func(i): return inp(0, true, i == 0))
	t.eq(body.pos.y, 13.0, "jumps up through a platform from below and lands on it")
	sim(world, body, stats, 120, func(_i): return inp())
	t.eq(body.pos.y, 13.0, "rests on the platform")
	sim(world, body, stats, 5, func(_i): return inp(0, false, false, false, true))
	t.eq(body.pos.y, 13.0, "a brush of down (5 steps) does not drop through")
	sim(world, body, stats, 10, func(_i): return inp())
	sim(world, body, stats, 60, func(i): return inp(0, i == 0, i == 0, false, true))
	t.eq(body.pos.y, 8.0, "down + jump drops through to the ground")
	t.eq(body.drop_y, Body.NO_DROP, "drop state clears on landing")

	body.pos = Vector2(25, 20)
	sim(world, body, stats, 90, func(_i): return inp())
	t.eq(body.pos.y, 13.0, "falling from above lands on the platform")

	var mixed := Col.flat(64)
	Col.fill(mixed, 20, 12, 25, 13, TileDefs.id("platform"))
	Col.fill(mixed, 25, 12, 30, 13, TileDefs.id("stone"))
	body.pos = Vector2(25, 13)
	sim(mixed, body, stats, 30, func(i): return inp(0, i == 0, i == 0, false, true))
	t.check(body.pos.y >= 13.0, "down + jump half on stone jumps instead of dropping")
	_s_drop(t)

## S alone drops through a walkway once held drop_hold (0.1 s = 6 steps) from a press made
## standing; never off a ladder or after a landing with S still held; never off solid ground.
func _s_drop(t: TestLog) -> void:
	var stats := MoveStats.player()
	var world := Col.flat(64)
	Col.fill(world, 20, 12, 30, 13, TileDefs.id("platform"))   # top at y = 13
	Col.fill(world, 20, 20, 30, 21, TileDefs.id("platform"))   # a second walkway, top at 21
	var body := stats.make_body()
	body.pos = Vector2(25, 13)
	TileCollision.update_contacts(world, body)
	var path := sim(world, body, stats, 6, func(_i): return inp(0, false, false, false, true))
	t.check(path[4].y == 13.0 and path[5].y < 13.0, "S held 6 steps (0.1 s) drops through the walkway (%.3f, %.3f)" % [path[4].y, path[5].y])
	sim(world, body, stats, 60, func(_i): return inp(0, false, false, false, true))
	t.eq(body.pos.y, 8.0, "and falls to the ground with no jump")
	t.eq(body.drop_y, Body.NO_DROP, "drop state clears on landing")
	sim(world, body, stats, 30, func(_i): return inp(0, false, false, false, true))
	t.eq(body.pos.y, 8.0, "S on solid ground does nothing")
	# walking along a walkway brushing S
	body = stats.make_body()
	body.pos = Vector2(21, 13)
	TileCollision.update_contacts(world, body)
	sim(world, body, stats, 30, func(i): return inp(0.5, false, false, false, i >= 10 and i < 14))
	t.eq(body.pos.y, 13.0, "walking along a walkway brushing S (4 steps) stays on it")
	# landing on a walkway with S held: no drop until S is let go and pressed again
	body = stats.make_body()
	body.pos = Vector2(25, 26)
	sim(world, body, stats, 60, func(_i): return inp(0, false, false, false, true))
	t.eq(body.pos.y, 21.0, "landing on a walkway with S held does not drop through")
	sim(world, body, stats, 1, func(_i): return inp())
	sim(world, body, stats, 40, func(_i): return inp(0, false, false, false, true))
	t.eq(body.pos.y, 13.0, "pressed again: drops to the walkway below, and stops there")
	# a ladder that ends on a walkway: climbing down with S held lands on it and stays
	var lw := Col.flat(64)
	Col.fill(lw, 20, 12, 30, 13, TileDefs.id("platform"))
	Col.fill(lw, 25, 13, 26, 22, TileDefs.id("ladder"))         # rungs 13..21, on the walkway
	body = stats.make_body()
	body.pos = Vector2(25.5, 22)
	TileCollision.update_contacts(lw, body)
	sim(lw, body, stats, 120, func(_i): return inp(0, false, false, false, true))
	t.check(body.pos.y == 13.0 and body.on_floor, "climbing down a ladder onto a walkway with S held stops on the walkway (%.2f)" % body.pos.y)
	sim(lw, body, stats, 30, func(_i): return inp(1.0))
	t.check(body.pos.y == 13.0 and not body.climbing, "and walks off the ladder along it")
	sim(lw, body, stats, 1, func(_i): return inp())
	sim(lw, body, stats, 60, func(_i): return inp(0, false, false, false, true))
	t.eq(body.pos.y, 8.0, "a fresh S then drops through")
	# down + jump still drops at once
	body = stats.make_body()
	body.pos = Vector2(22, 13)
	TileCollision.update_contacts(lw, body)
	path = sim(lw, body, stats, 2, func(i): return inp(0, i == 0, i == 0, false, true))
	t.check(path[0].y < 13.0, "down + jump still drops on the first step")
	# half on stone: S does not drop
	var mixed := Col.flat(64)
	Col.fill(mixed, 20, 12, 25, 13, TileDefs.id("platform"))
	Col.fill(mixed, 25, 12, 30, 13, TileDefs.id("stone"))
	body = stats.make_body()
	body.pos = Vector2(25, 13)
	TileCollision.update_contacts(mixed, body)
	sim(mixed, body, stats, 30, func(_i): return inp(0, false, false, false, true))
	t.eq(body.pos.y, 13.0, "S half on stone does not drop")
	# a host-simulated (monster) body follows the same rule
	var ms := MoveStats.from_srd({"walk": 30}, "small")
	body = ms.make_body()
	body.pos = Vector2(25, 13)
	TileCollision.update_contacts(world, body)
	sim(world, body, ms, 60, func(_i): return inp(0, false, false, false, true))
	t.eq(body.pos.y, 8.0, "a Small body S-drops the same way")

func _ladder(t: TestLog) -> void:
	var world := Col.flat(64)
	Col.fill(world, 40, 8, 41, 18, TileDefs.id("ladder"))   # rungs y 8..17, top at 18
	var stats := MoveStats.player()
	var body := stats.make_body()
	body.pos = Vector2(40.5, 8)
	var path := sim(world, body, stats, 120, func(_i): return inp(0, false, false, true))
	t.eq(body.pos.y, 18.0, "climbs a ladder and stands on its top")
	t.check(not body.climbing and body.on_floor, "off the ladder, on its top rung")
	var rate := (path[30].y - path[20].y) / (10 * DT)
	t.check(absf(rate - stats.ladder_speed) < 1e-3, "climbs at ladder speed (%.2f t/s)" % rate)
	sim(world, body, stats, 120, func(_i): return inp())
	t.eq(body.pos.y, 18.0, "rests on the ladder top")
	sim(world, body, stats, 120, func(_i): return inp(0, false, false, false, true))
	t.eq(body.pos.y, 8.0, "down on the top climbs back down to the ground")
	sim(world, body, stats, 30, func(_i): return inp(0, false, false, true))
	var before := body.pos.y
	t.check(body.climbing and before > 9.0, "grabbed again with up")
	sim(world, body, stats, 3, func(i): return inp(1.0, true, i == 0))
	t.check(not body.climbing and body.vel.y > 0.0 and body.pos.y > before, "jump lets go of the ladder with a jump")
	body.pos = Vector2(40.5, 14)
	body.vel = Vector2.ZERO
	body.climbing = true
	sim(world, body, stats, 60, func(_i): return inp())
	t.eq(body.pos.y, 14.0, "holding a ladder with no input hangs in place")

func _swim(t: TestLog) -> void:
	var world := Col.flat(64)
	for x in range(20, 40):
		for y in range(8, 18):
			world.set_liquid(x, y, 15, true)
	var stats := MoveStats.player()
	var body := stats.make_body()
	body.pos = Vector2(25, 13)
	var path := sim(world, body, stats, 30, func(_i): return inp())
	t.check(body.swimming and body.in_liquid == 1.0, "fully submerged and swimming")
	var sink := (path[29].y - path[19].y) / (10 * DT)
	t.check(sink < 0.0 and sink > -stats.max_sink - 1e-3, "sinks slowly (%.2f t/s)" % sink)
	var y0 := body.pos.y
	sim(world, body, stats, 30, func(_i): return inp(0, true))
	t.check(body.pos.y > y0 + 1.0, "holding jump swims up")
	body.pos = Vector2(25, 10)
	body.vel = Vector2.ZERO
	sim(world, body, stats, 60, func(_i): return inp(1.0))
	t.check(absf(body.vel.x - stats.swim_speed) < 1e-3, "swims at half walk speed without a swim speed (%.2f)" % body.vel.x)
	body.pos = Vector2(30, 16)
	body.vel = Vector2(0, -stats.terminal_fall)
	sim(world, body, stats, 12, func(_i): return inp())
	t.check(body.vel.y >= -stats.swim_speed - 1e-3, "a dive into water brakes to swim speed within 0.2 s (%.2f)" % body.vel.y)
	t.check(absf(MoveStats.from_srd({"walk": 10, "swim": 40}).swim_speed - 40.0 / 30.0 * 10.0) < 1e-6, "a swim speed sets the swim rate")
	# reach the surface holding jump, then leap out onto the bank
	var bank := Col.flat(64)
	Col.fill(bank, 0, 8, 20, 18, TileDefs.id("stone"))
	for x in range(20, 40):
		for y in range(8, 17):
			bank.set_liquid(x, y, 15, true)
	body = stats.make_body()
	body.pos = Vector2(22, 9)
	sim(bank, body, stats, 300, func(i): return inp(-1.0 if i >= 60 and i < 200 else 0.0, i < 200, i < 200 and i % 30 == 0))
	t.check(body.pos.y == 18.0 and body.pos.x < 20.0, "swims up and leaps out onto a bank 1 tile above the water (%s)" % body.pos)

func _climb_and_fly(t: TestLog) -> void:
	var world := Col.flat(64)
	Col.fill(world, 30, 8, 34, 16, TileDefs.id("stone"))   # 8-high block
	var spider := MoveStats.from_srd({"walk": 30, "climb": 30}, "large")
	var body := spider.make_body()
	body.pos = Vector2(20, 8)
	sim(world, body, spider, 180, func(_i): return inp(1.0))
	t.check(body.pos.y == 16.0 or body.pos.x > 34.0, "a climber walks up an 8-high wall and over (%s)" % body.pos)
	var stats := MoveStats.player()
	body = stats.make_body()
	body.pos = Vector2(20, 8)
	sim(world, body, stats, 180, func(_i): return inp(1.0))
	t.eq(body.pos, Vector2(29.25, 8), "a walker without a climb speed cannot")

	var bird := MoveStats.from_srd({"walk": 10, "fly": 60}, "small")
	body = bird.make_body()
	body.pos = Vector2(10.5, 8)
	sim(world, body, bird, 30, func(_i): return inp(0, false, false, true))
	var y0 := body.pos.y
	t.check(body.flying and y0 > 12.0, "a flyer takes off with up (y %.2f)" % y0)
	sim(world, body, bird, 60, func(_i): return inp())
	t.check(body.vel == Vector2.ZERO and body.pos.y > y0, "and hovers with no input")
	sim(world, body, bird, 120, func(_i): return inp(0, false, false, false, true))
	t.check(body.pos.y == 8.0 and not body.flying, "and lands with down")

func _determinism(t: TestLog) -> void:
	var runs: Array = []
	for r in 2:
		var world := TileWorld.make_test()
		var stats := MoveStats.player()
		var body := stats.make_body()
		body.pos = Vector2(world.width / 2 - 20.5, world.height / 2)
		var rng := RandomNumberGenerator.new()
		rng.seed = 1234
		var held := false
		var trace := PackedVector2Array()
		for i in 900:
			var p := PlayerInput.new()
			p.move_x = rng.randf_range(-1, 1) if rng.randf() < 0.9 else 0.0
			var press := rng.randf() < 0.05
			held = press or (held and rng.randf() < 0.9)
			p.jump = held
			p.jump_pressed = press
			p.down = rng.randf() < 0.05
			PlayerController.step(world, body, p, stats, DT)
			trace.append(body.pos)
			trace.append(body.vel)
		runs.append(trace)
	t.check(runs[0] == runs[1], "the same inputs give bit-identical positions and velocities over 900 steps")

func _input_bytes(t: TestLog) -> void:
	var cases: Array[PlayerInput] = []
	cases.append(inp())
	cases.append(inp(0.37, true, true, false, true))
	cases.append(inp(-1.0, false, false, true))
	var d := inp(1.0)
	d.dig = true
	d.target = Vector2i(-3, 4095)
	cases.append(d)
	var pl := inp(-0.5)
	pl.place = true
	pl.use = true
	pl.target = Vector2i(16383, -1)
	pl.place_tile = TileDefs.id("ladder")
	cases.append(pl)
	var ok := true
	for c in cases:
		var back := PlayerInput.from_bytes(c.to_bytes())
		if not c.equals(back) or back.to_bytes() != c.to_bytes():
			ok = false
	t.check(ok, "PlayerInput survives to_bytes/from_bytes")
	t.eq(cases[0].to_bytes().size(), 2, "a move-only input is 2 bytes")
	t.eq(cases[3].to_bytes().size(), 6, "with a dig target 6 bytes")
	t.eq(cases[4].to_bytes().size(), 8, "with a place tile 8 bytes")
	t.check(PlayerInput.from_bytes(PackedByteArray([16, 0])) == null, "truncated bytes give null")
	var q := PlayerInput.new()
	q.move_x = 0.37
	t.eq(q.move_x, roundf(0.37 * 127.0) / 127.0, "move_x is quantized on write")
