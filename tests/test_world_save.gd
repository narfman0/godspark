extends RefCounted

func run(t: TestLog) -> void:
	var dir := "user://test_world_save"
	_wipe(dir)
	var world := WorldGen.generate(512, 256, 11)
	world.set_fg(10, 200, TileDefs.id("wood"))  # one player edit: the chunk is modified
	t.eq(WorldSave.save(world, dir), OK, "save succeeds")
	t.check(FileAccess.file_exists(dir.path_join("world.json")), "world.json written")
	t.check(not FileAccess.file_exists(dir.path_join("world.json.tmp")), "no temp file left behind")

	var back := WorldSave.load(dir)
	t.check(back != null, "load succeeds")
	if back == null:
		return
	t.eq(back.content_hash(), world.content_hash(), "tiles round-trip")
	t.check(back.meta == world.meta, "meta round-trips")
	t.check(back.meta["surface"][0] is int, "meta numbers come back as ints")
	t.eq([back.width, back.height, back.world_seed], [world.width, world.height, world.world_seed], "size and seed")
	t.check(back.chunk_at(0, 200 / K.CHUNK).modified and not back.chunk_at(5, 0).modified, "modified flags round-trip")

	# saving again over an existing save works
	back.set_fg(11, 200, TileDefs.id("wood"))
	t.eq(WorldSave.save(back, dir), OK, "save over an existing save")
	t.eq(WorldSave.load(dir).content_hash(), back.content_hash(), "second save loads")

	t.eq(WorldSave.load("user://no_such_world_here"), null, "missing dir loads as null")
	var f := FileAccess.open(dir.path_join("r_0_0.bin"), FileAccess.WRITE)
	f.store_buffer("GSR1junk".to_ascii_buffer())
	f.close()
	t.eq(WorldSave.load(dir), null, "truncated region loads as null")
	f = FileAccess.open(dir.path_join("world.json"), FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	t.eq(WorldSave.load(dir), null, "corrupt world.json loads as null")
	_wipe(dir)

func _wipe(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(dir)
