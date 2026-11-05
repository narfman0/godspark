extends RefCounted

func run(t: TestLog) -> void:
	var world := TileWorld.make_test()
	var ground := world.height / 2
	var mid := world.width / 2
	t.eq(world.get_fg(0, ground - 1), TileDefs.id("grass"), "grass on top of the ground")
	t.eq(world.get_fg(0, 0), TileDefs.id("stone"), "stone at the bottom")
	t.check(world.is_solid(0, ground - 1), "ground is solid")
	t.check(not world.is_solid(0, ground), "air above the ground")
	t.check(not world.is_solid(mid + 12, ground - 3), "the pit is open")
	t.check(world.is_solid(-1, 5) and world.is_solid(5, world.height), "outside the grid reads as solid bedrock")

	var seen: Array = []
	world.tile_changed.connect(func(x, y, layer, old, now): seen.append([x, y, layer, old, now]))
	t.check(world.set_fg(3, ground, TileDefs.id("wood")), "set_fg reports a change")
	t.check(not world.set_fg(3, ground, TileDefs.id("wood")), "setting the same value is not a change")
	t.eq(seen, [[3, ground, TileWorld.Layer.FG, 0, TileDefs.id("wood")]], "tile_changed carries old and new")
	t.check(world.chunk_at(0, ground / K.CHUNK).modified, "an edit marks the chunk modified")
	t.check(not world.set_fg(-1, 0, 1), "out of bounds writes are refused")

	var other := TileWorld.make_test()
	t.check(world.content_hash() != other.content_hash(), "an edit changes the content hash")
	other.set_fg(3, ground, TileDefs.id("wood"))
	t.eq(world.content_hash(), other.content_hash(), "equal worlds hash equal")

	var c := world.chunk_at(0, ground / K.CHUNK)
	var copy := Chunk.new(c.cx, c.cy)
	copy.from_bytes(c.to_bytes())
	t.check(copy.fg == c.fg and copy.bg == c.bg and copy.liquid == c.liquid, "a chunk survives to_bytes/from_bytes")
