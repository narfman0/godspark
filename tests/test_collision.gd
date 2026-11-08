extends RefCounted

const DT := 1.0 / 60.0

func run(t: TestLog) -> void:
	_corner(t)
	_depenetrate(t)
	_rest(t)
	_tunnelling(t)
	_gaps(t)
	_world_edge(t)
	_one_way(t)
	_helpers(t)
	_raycast(t)

## Stone below y = floor_y, air above.
static func flat(w := 64, h := 64, floor_y := 8) -> TileWorld:
	var world := TileWorld.new(w, h, 1)
	var stone := TileDefs.id("stone")
	for x in w:
		for y in floor_y:
			world.set_fg(x, y, stone, true)
	return world

static func fill(world: TileWorld, x0: int, y0: int, x1: int, y1: int, id: int) -> void:
	for x in range(x0, x1):
		for y in range(y0, y1):
			world.set_fg(x, y, id, true)

func _rest(t: TestLog) -> void:
	var world := flat()
	var stats := MoveStats.player()
	var body := stats.make_body()
	body.pos = Vector2(10.5, 8)
	var drift := false
	for i in 600:
		PlayerController.step(world, body, PlayerInput.new(), stats, DT)
		if body.pos != Vector2(10.5, 8) or not body.on_floor:
			drift = true
	t.check(not drift, "a Medium body rests on flat ground for 600 steps without moving or leaving the floor")
	t.eq(body.vel, Vector2.ZERO, "resting velocity is zero")

	# a Gargantuan body (7 tiles wide) resting across a bumpy floor
	var bumpy := flat()
	bumpy.set_fg(20, 8, TileDefs.id("stone"), true)
	var g_stats := MoveStats.from_srd({"walk": 40}, "gargantuan")
	var big := g_stats.make_body()
	big.pos = Vector2(21.0, 9)
	for i in 600:
		PlayerController.step(bumpy, big, PlayerInput.new(), g_stats, DT)
	t.eq(big.pos, Vector2(21.0, 9), "a Gargantuan body rests on a one-tile bump without sinking or drifting")

	# falling from a height lands exactly on the boundary
	var faller := stats.make_body()
	faller.pos = Vector2(30.3, 40.37)
	for i in 300:
		PlayerController.step(world, faller, PlayerInput.new(), stats, DT)
	t.eq(faller.pos, Vector2(30.3, 8), "a fall lands with feet exactly on the tile top")

func _tunnelling(t: TestLog) -> void:
	var world := flat()
	fill(world, 30, 8, 31, 20, TileDefs.id("stone"))      # 1-tile wall
	var body := Body.for_size("medium")
	body.pos = Vector2(20.5, 8)
	body.vel = Vector2(10000, 0)
	TileCollision.move(world, body, DT)
	t.eq(body.right(), 30.0, "10000 t/s rightward stops flush against a 1-tile wall")
	t.eq(body.vel.x, 0.0, "the blocked velocity is zeroed")
	t.check(body.on_wall and body.wall_dir == 1, "on_wall to the right after hitting it")

	body.pos = Vector2(40.5, 8)
	body.vel = Vector2(-10000, 0)
	TileCollision.move(world, body, DT)
	t.eq(body.left(), 31.0, "10000 t/s leftward stops flush against the same wall")

	var slab := flat()
	fill(slab, 0, 30, 64, 31, TileDefs.id("wood"))        # 1-tile thick floor
	body.pos = Vector2(10.25, 50)
	body.vel = Vector2(0, -10000)
	TileCollision.move(slab, body, DT)
	t.eq(body.pos.y, 31.0, "falling at 10000 t/s lands on a 1-tile slab")
	t.check(body.on_floor, "on_floor after landing")
	body.pos = Vector2(10.25, 20)
	body.vel = Vector2(0, 10000)
	TileCollision.move(slab, body, DT)
	t.eq(body.top(), 30.0, "rising at 10000 t/s stops under the slab")
	t.check(body.on_ceiling, "on_ceiling after the bump")

	# diagonal at very high speed: x first then y, never inside a solid
	body.pos = Vector2(5.5, 12)
	body.vel = Vector2(5000, -5000)
	TileCollision.move(world, body, DT)
	t.check(not TileCollision.overlaps_solid(world, body.rect()), "a diagonal high-speed move never ends inside a solid")
	t.eq(body.pos, Vector2(29.25, 8), "it ends in the corner of wall and floor")

func _gaps(t: TestLog) -> void:
	# a horizontal tunnel 3 tiles high through a thick wall
	var world := flat()
	fill(world, 30, 11, 40, 40, TileDefs.id("stone"))
	var out := {}
	for size_name in ["medium", "large"]:
		var stats := MoveStats.from_srd({"walk": 30}, size_name)
		var body := stats.make_body()
		body.pos = Vector2(20, 8)
		var p := PlayerInput.new()
		p.move_x = 1.0
		for i in ceili(30.0 / stats.run_speed / DT):
			PlayerController.step(world, body, p, stats, DT)
		out[size_name] = body.pos.x
	t.check(out["medium"] > 45.0, "Medium walks through a 3-high tunnel (x %.2f)" % out["medium"])
	t.eq(out["large"], 30.0 - 1.25, "Large is stopped at the 3-high tunnel mouth")

	# a vertical shaft 2 tiles wide in a floor
	var shaft := flat()
	fill(shaft, 0, 20, 30, 21, TileDefs.id("stone"))
	fill(shaft, 32, 20, 64, 21, TileDefs.id("stone"))
	var ys := {}
	for size_name in ["medium", "large"]:
		var stats := MoveStats.from_srd({"walk": 30}, size_name)
		var body := stats.make_body()
		body.pos = Vector2(31.0, 30)
		for i in 240:
			PlayerController.step(shaft, body, PlayerInput.new(), stats, DT)
		ys[size_name] = body.pos.y
	t.eq(ys["medium"], 8.0, "Medium drops through a 2-wide shaft")
	t.eq(ys["large"], 21.0, "Large is held by the 2-wide shaft's rim")

func _world_edge(t: TestLog) -> void:
	var world := flat()
	var body := Body.for_size("medium")
	body.pos = Vector2(3.0, 8)
	body.vel = Vector2(-500, 0)
	TileCollision.move(world, body, DT)
	t.eq(body.left(), 0.0, "the left world edge is solid")
	body.pos = Vector2(60.0, 8)
	body.vel = Vector2(500, 0)
	TileCollision.move(world, body, DT)
	t.eq(body.right(), 64.0, "the right world edge is solid")
	body.pos = Vector2(30.0, 50)
	body.vel = Vector2(0, 5000)
	TileCollision.move(world, body, DT)
	t.eq(body.top(), 64.0, "the top world edge is solid")

func _one_way(t: TestLog) -> void:
	var world := flat()
	fill(world, 20, 14, 30, 15, TileDefs.id("platform"))
	var body := Body.for_size("medium")
	body.pos = Vector2(25, 20)
	body.vel = Vector2(0, -400)
	TileCollision.move(world, body, DT)
	t.eq(body.pos.y, 15.0, "a platform stops a body falling onto it")
	t.check(body.on_floor, "on_floor on a platform")
	t.eq(TileCollision.ground_under(world, body), TileDefs.id("platform"), "ground_under names the platform")
	t.check(TileCollision.on_platform_only(world, body), "standing on platform only")
	body.pos = Vector2(25, 10)
	body.vel = Vector2(0, 400)
	TileCollision.move(world, body, DT)
	t.check(body.pos.y > 15.0, "a platform does not stop a body rising through it")
	body.pos = Vector2(15, 13)
	body.vel = Vector2(600, 0)
	TileCollision.move(world, body, DT)
	t.eq(body.pos.x, 25.0, "a platform does not block sideways")
	body.pos = Vector2(25, 15)
	body.drop_y = 15
	body.vel = Vector2(0, -800)
	TileCollision.move(world, body, DT)
	t.eq(body.pos.y, 8.0, "with drop_y set the body falls through the platform")

func _helpers(t: TestLog) -> void:
	var world := flat()
	t.check(TileCollision.overlaps_solid(world, Rect2(3, 7.5, 1, 1)), "overlaps_solid sees the ground")
	t.check(not TileCollision.overlaps_solid(world, Rect2(3, 8, 1, 1)), "touching the ground is not overlapping")
	t.check(TileCollision.overlaps_solid(world, Rect2(-0.5, 20, 1, 1)), "outside the world is solid")
	var body := Body.for_size("medium")
	body.pos = Vector2(10.5, 8)
	t.eq(TileCollision.ground_under(world, body), TileDefs.id("stone"), "ground_under on stone")
	body.pos = Vector2(10.5, 9.5)
	t.eq(TileCollision.ground_under(world, body), -1, "ground_under in the air is -1")
	world.set_liquid(10, 8, 15, true)
	world.set_liquid(10, 9, 8, true)
	body.pos = Vector2(10.5, 8)
	var wet := TileCollision.liquid_fraction(world, body)
	t.check(absf(wet - (1.0 + 8.0 / 15.0) / 2.5) < 1e-5, "liquid_fraction counts partial cells (%.3f)" % wet)

func _raycast(t: TestLog) -> void:
	var world := flat()
	fill(world, 30, 8, 31, 20, TileDefs.id("stone"))
	var h := TileCollision.raycast(world, Vector2(10.5, 10.5), Vector2(50.5, 10.5))
	t.check(h["hit"], "a ray across the wall hits")
	t.eq(h["tile"], Vector2i(30, 10), "it hits the wall tile")
	t.eq(h["normal"], Vector2i(-1, 0), "with the wall's left face normal")
	t.check(absf(h["point"].x - 30.0) < 1e-4 and absf(h["distance"] - 19.5) < 1e-4, "at the wall face")
	var m := TileCollision.raycast(world, Vector2(10.5, 10.5), Vector2(25.5, 18.2))
	t.check(not m["hit"], "a ray through open air misses")
	var d := TileCollision.raycast(world, Vector2(10.5, 20.5), Vector2(14.2, 2.0))
	t.check(d["hit"] and d["tile"].y == 7 and d["normal"] == Vector2i(0, 1), "a downward diagonal hits the ground top")
	var inside := TileCollision.raycast(world, Vector2(5.5, 3.5), Vector2(5.5, 20))
	t.check(inside["hit"] and inside["distance"] == 0.0, "a ray starting inside stone hits at once")
	var plat := flat()
	fill(plat, 0, 12, 64, 13, TileDefs.id("platform"))
	t.check(not TileCollision.raycast(plat, Vector2(5, 20), Vector2(5, 9))["hit"], "platforms don't block rays")

## A body spawned inside solid tiles is pushed out to the nearest free spot.
func _depenetrate(t: TestLog) -> void:
	var world := TileWorld.make_test()
	var g := world.height / 2
	var b := Body.for_size("medium")
	b.pos = Vector2(40.5, g - 2.3)          # buried 2.3 tiles deep in the ground
	t.check(TileCollision.depenetrate(world, b), "a buried body is moved")
	t.eq(b.pos, Vector2(40.5, g), "onto the ground right above it")
	t.check(not TileCollision.overlaps_solid(world, b.rect()), "and is free")
	t.check(not TileCollision.depenetrate(world, b), "a free body is left alone")
	var stone := TileDefs.id("stone")
	for y in range(g, g + 6):
		world.set_fg(60, y, stone, true)      # a 1-wide pillar on the ground
	b.pos = Vector2(60.5, g)
	TileCollision.depenetrate(world, b)
	t.check(not TileCollision.overlaps_solid(world, b.rect()), "a body inside a pillar gets out")
	t.check(absf(b.pos.x - 60.5) <= 2.0 and b.pos.y == g, "sideways, not on top of it (%s)" % b.pos)
	var host := WorldHost.new(world)
	host.spawn = Vector2(40.5, g - 5)
	var p := host.add_player("ann", 2)
	t.check(not TileCollision.overlaps_solid(world, p.body.rect()), "a player spawned in rock starts free (%s)" % p.body.pos)

## The corner snag: a fast diagonal fall whose feet are just under a ledge top lands on it
## instead of sliding down its side. A tall wall still stops the body.
func _corner(t: TestLog) -> void:
	var world := TileWorld.new(64, 64)
	var stone := TileDefs.id("stone")
	for x in range(20, 30):
		for y in range(0, 10):
			world.set_fg(x, y, stone, true)     # a ledge, top at y = 10, left side at x = 20
	for x in range(0, 64):
		world.set_fg(x, 0, stone, true)
	var b := Body.for_size("medium")
	b.pos = Vector2(19.15, 9.8)               # right edge 0.1 short of the side, feet 0.2 under the top
	b.vel = Vector2(13.0, -30.0)
	TileCollision.move(world, b, 1.0 / 60.0)
	t.eq(b.pos.y, 10.0, "a diagonal fall just under a ledge top lands on it (%s)" % b.pos)
	t.check(b.on_floor and b.pos.x > 19.36, "standing on it, having kept its full move right (%s)" % b.pos)
	var c := Body.for_size("medium")
	c.pos = Vector2(19.15, 8.0)               # feet 2 under the top: that is the side
	c.vel = Vector2(13.0, -30.0)
	TileCollision.move(world, c, 1.0 / 60.0)
	t.check(c.pos.y < 8.0 and c.pos.x <= 19.25 + 0.001, "lower down it still hits the side (%s)" % c.pos)
	for y in range(10, 20):
		world.set_fg(20, y, stone, true)        # make the ledge a tall wall
	var d := Body.for_size("medium")
	d.pos = Vector2(19.15, 9.8)
	d.vel = Vector2(13.0, -30.0)
	TileCollision.move(world, d, 1.0 / 60.0)
	t.check(d.pos.y < 9.8 and absf(d.pos.x - 19.25) < 0.001, "a tall wall is not climbed (%s)" % d.pos)
