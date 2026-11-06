extends RefCounted

const DT := 1.0 / 60.0
const Col := preload("res://tests/test_collision.gd")

func run(t: TestLog) -> void:
	var world := Col.flat(64)
	var stone := TileDefs.id("stone")
	var body := Body.for_size("medium")
	body.pos = Vector2(20.5, 8)          # box x 19.75..21.25, y 8..10.5

	# dig
	t.check(TileEdit.can_dig(world, body, 20, 7), "can dig the tile under the feet")
	t.check(TileEdit.can_dig(world, body, 20, 4), "can dig 4 rows down (gap 3)")
	t.check(not TileEdit.can_dig(world, body, 20, 2), "cannot dig 6 rows down (gap 5)")
	t.check(TileEdit.can_dig(world, body, 25, 7), "can dig 4 tiles to the side (gap 3.75)")
	t.check(not TileEdit.can_dig(world, body, 26, 7), "cannot dig past reach to the side (gap 4.75)")
	t.check(not TileEdit.can_dig(world, body, 24, 4), "reach is a circle: a corner 3.75 x 3 away is out (4.8)")
	t.check(not TileEdit.can_dig(world, body, 20, 9), "cannot dig air")
	world.set_fg(21, 7, TileDefs.id("bedrock"), true)
	t.check(not TileEdit.can_dig(world, body, 21, 7), "cannot dig bedrock")
	t.check(not TileEdit.can_dig(world, body, -1, 7), "cannot dig outside the world")
	var big := Body.for_size("gargantuan")
	big.pos = Vector2(20.5, 8)
	t.check(TileEdit.can_dig(world, big, 28, 7), "a bigger body reaches further")

	# a staircase built up into the air holds on diagonally, tread to tread
	var sw := Col.flat(64)
	var sr := TileDefs.id("stairs_r")
	t.check(TileEdit.can_place(sw, body, 22, 8, sr, []), "a first stair tread on the ground")
	sw.set_fg(22, 8, sr, true)
	t.check(TileEdit.can_place(sw, body, 23, 9, sr, []), "the next tread up holds on to the one below it diagonally")
	t.check(not TileEdit.can_place(sw, body, 23, 9, TileDefs.id("platform"), []), "a walkway there does not")
	t.check(not TileEdit.can_place(sw, body, 24, 10, sr, []), "nor a tread with no tread beside it")

	t.eq(TileEdit.dig_time(stone), 1.0, "stone takes 1 s bare-handed")
	t.eq(TileEdit.dig_time(stone, 2.0), 0.5, "a power-2 tool halves it")
	t.eq(TileEdit.dig_time(TileDefs.id("dirt")), 0.4, "dirt is exactly 0.4 s despite float32 hardness")
	var dp := TileEdit.DigProgress.new()
	var steps := 0
	while not dp.update(Vector2i(1, 1), TileDefs.id("dirt"), 1.0 / 60.0):
		steps += 1
	t.eq(steps + 1, 24, "dirt digs in 24 controller steps at 60 Hz")
	var host_dp := TileEdit.DigProgress.new()
	var ticks := 1
	while not host_dp.update(Vector2i(1, 1), TileDefs.id("dirt"), 1.0 / K.TICK_HZ):
		ticks += 1
	t.eq(ticks, 12, "and in 12 host ticks at 30 Hz")
	t.eq(TileEdit.dig_time(TileDefs.id("bedrock")), INF, "bedrock never breaks")
	t.eq(TileEdit.dig_time(TileDefs.AIR), INF, "air is not dug")

	# dig progress
	var dig := TileEdit.DigProgress.new()
	var done_at := -1
	for i in 120:
		if dig.update(Vector2i(20, 7), stone, DT):
			done_at = i + 1
			break
	t.eq(done_at, 60, "a held dig on stone completes on the 60th step (1 s)")
	for i in 30:
		dig.update(Vector2i(20, 7), stone, DT)
	t.check(absf(dig.fraction() - 0.5) < 1e-6, "progress fraction reads 0.5 halfway")
	dig.update(Vector2i(22, 7), stone, DT)
	t.check(absf(dig.fraction() - 1.0 / 60.0) < 1e-6, "changing the target starts over")
	t.check(not dig.update(Vector2i(22, 7), TileDefs.id("dirt"), DT) and dig.elapsed == DT, "a different tile at the target starts over")

	# place
	var wood := TileDefs.id("wood")
	t.check(TileEdit.can_place(world, body, 23, 8, wood, [body]), "can place on the ground next to you")
	t.check(not TileEdit.can_place(world, body, 23, 9, wood, [body]), "cannot place floating in air")
	world.set_bg(23, 9, TileDefs.wall_id("stone_wall"), true)
	t.check(TileEdit.can_place(world, body, 23, 9, wood, [body]), "can place in air on a background wall")
	t.check(not TileEdit.can_place(world, body, 20, 8, wood, [body]), "cannot place a solid tile inside your own body")
	var other := Body.for_size("small")
	other.pos = Vector2(23.5, 8)
	t.check(not TileEdit.can_place(world, body, 23, 8, wood, [body, other]), "cannot place a solid tile inside another body")
	t.check(TileEdit.can_place(world, body, 22, 8, wood, [body, other]), "a cell only touching bodies' edges is free")
	t.check(TileEdit.can_place(world, body, 20, 8, TileDefs.id("ladder"), [body]), "a ladder can go where you stand")
	t.check(not TileEdit.can_place(world, body, 20, 7, wood, [body]), "cannot place into an occupied cell")
	t.check(not TileEdit.can_place(world, body, 30, 8, wood, [body]), "cannot place out of reach")
	t.check(not TileEdit.can_place(world, body, 23, 8, TileDefs.AIR, [body]), "placing air is not placing")
