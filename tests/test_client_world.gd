extends RefCounted

func run(t: TestLog) -> void:
	_chunks_and_freeze(t)
	_edits(t)
	_interpolation(t)
	_correction(t)

func _setup(world: TileWorld) -> ClientWorld:
	var cw := ClientWorld.new()
	var spawn := Vector2(world.width / 2 + 0.5, world.height / 2)
	cw.setup(world.width, world.height, world.world_seed, 1, "ann", spawn, 0, 2)
	return cw

func _chunks_and_freeze(t: TestLog) -> void:
	var src := TileWorld.make_test()
	var cw := _setup(src)
	var arrived := []
	var changed := []
	cw.chunk_arrived.connect(func(cx: int, cy: int) -> void: arrived.append(Vector2i(cx, cy)))
	cw.world.chunk_changed.connect(func(cx: int, cy: int) -> void: changed.append(Vector2i(cx, cy)))
	var inp := PlayerInput.new()
	inp.move_x = 1.0
	var p0 := cw.body.pos
	for i in 10:
		cw.step(inp)
	t.check(cw.frozen, "with no chunks the player is frozen")
	t.eq(cw.body.pos, p0, "and does not move (would fall through unloaded air otherwise)")
	t.eq(cw.seq, 10, "steps are still counted")
	for c in Interest.around(src, Interest.chunk_of(cw.body.center()), 1):
		t.check(cw.apply_chunk(c.x, c.y, src.chunk_at(c.x, c.y).to_bytes()), "chunk %s decodes" % c)
	t.eq(arrived.size(), 9, "chunk_arrived for each")
	t.eq(changed.size(), 9, "the client TileWorld emits chunk_changed for each (meshes and light rebuild)")
	t.check(cw.area_ready(1) and not cw.area_ready(2), "area_ready by radius")
	for i in 30:
		cw.step(inp)
	t.check(not cw.frozen, "with its chunks present the player moves")
	t.check(cw.body.pos.x > p0.x + 4.0 and cw.body.on_floor, "running on the arrived ground")
	t.eq(cw.loaded_hash(), ChunkHash.of(src, cw.loaded.keys()), "the partial world matches the source over held chunks")
	t.check(not cw.apply_chunk(0, 0, PackedByteArray([1, 2, 3])), "a broken blob is refused")
	t.check(not cw.has_chunk(0, 0), "and not held")
	t.check(not cw.apply_chunk(99, 0, src.chunk_at(0, 0).to_bytes()), "a chunk outside the world is refused")
	var c0: Vector2i = cw.loaded.keys()[0]
	var dropped := []
	cw.chunk_dropped.connect(func(cx: int, cy: int) -> void: dropped.append(Vector2i(cx, cy)))
	cw.drop_chunk(c0.x, c0.y)
	t.eq(dropped, [c0], "drop_chunk forgets it")
	t.eq(cw.world.chunk_at(c0.x, c0.y).fg.count(0) == Chunk.CELLS * 2, true, "and clears its tiles")
	# far tile deltas are ignored
	cw.apply_tile(0, 0, TileWorld.Layer.FG, 3)
	t.eq(cw.world.get_fg(0, 0), 0, "a delta for a chunk not held is ignored")

func _edits(t: TestLog) -> void:
	var src := TileWorld.make_test()
	var cw := _setup(src)
	for c in Interest.around(src, Interest.chunk_of(cw.body.center()), 2):
		cw.apply_chunk(c.x, c.y, src.chunk_at(c.x, c.y).to_bytes())
	var x := int(cw.body.pos.x)
	var gy := src.height / 2 - 1
	var inp := PlayerInput.new()
	inp.dig = true
	inp.target = Vector2i(x, gy)
	var r := cw.step(inp)
	t.eq(r.size(), 1, "pressing dig sends one request")
	t.eq([r[0]["op"], r[0]["x"], r[0]["y"]], [ClientWorld.Op.DIG_START, x, gy], "DIG_START at the target")
	t.eq(cw.step(inp).size(), 0, "holding sends nothing more")
	inp.target = Vector2i(x + 1, gy)
	r = cw.step(inp)
	t.eq([r.size(), r[0]["op"]], [1, ClientWorld.Op.DIG_START], "retargeting starts a new dig")
	cw.apply_edit_result(r[0]["req"], WorldHost.Reason.OUT_OF_REACH, inp.target, 2)
	t.eq(cw.step(inp).size(), 1, "after a refusal a held dig asks again")
	inp.target = Vector2i(x, gy + 5)
	r = cw.step(inp)
	t.eq([r.size(), r[0]["op"]], [1, ClientWorld.Op.DIG_STOP], "moving onto air stops the dig")
	t.eq(cw.step(inp).size(), 0, "and holding on air sends nothing")
	inp.dig = false
	inp.place = true
	inp.place_tile = TileDefs.id("wood")
	inp.target = Vector2i(x + 2, gy + 1)
	r = cw.step(inp)
	t.eq([r.size(), r[0]["op"], r[0]["tile"]], [1, ClientWorld.Op.PLACE, inp.place_tile], "place on press")
	t.eq(cw.step(inp).size(), 0, "not again while held on the same cell")
	inp.target = Vector2i(x + 2, gy + 9)
	t.eq(cw.step(inp).size(), 0, "a cell the local world says is impossible is not asked for")
	inp.target = Vector2i(x - 2, gy + 1)
	t.eq(cw.step(inp).size(), 1, "dragging to a new valid cell places again")
	var st := cw.make_state()
	t.eq([st["epoch"], st["seq"]], [0, cw.seq], "state carries epoch and seq")

func _interpolation(t: TestLog) -> void:
	var cw := _setup(TileWorld.make_test())
	var added := []
	cw.actor_added.connect(func(id: int, _look: Dictionary) -> void: added.append(id))
	cw.add_remote(5, HostEntity.Kind.PLAYER, "bob", Vector2(1.5, 2.5), Vector2(100, 64), 0)
	cw.add_remote(1, HostEntity.Kind.PLAYER, "me", Vector2(1.5, 2.5), Vector2(100, 64), 0)
	t.eq(added, [5], "a remote is added (never the own id)")
	cw.apply_snapshot(30, [{"id": 5, "pos": Vector2(100, 64), "vel": Vector2(15, 0), "flags": 1}])
	cw.apply_snapshot(32, [{"id": 5, "pos": Vector2(101, 64), "vel": Vector2(15, 0), "flags": 1},
			{"id": 77, "pos": Vector2.ZERO, "vel": Vector2.ZERO, "flags": 0}])
	t.check(not cw.remotes.has(77), "unknown ids in a snapshot are ignored")
	# clock ~ 1.0 + a bit; render time = clock - 0.1
	cw.clock = 1.0 + 1.0 / 30.0 + 0.1      # render exactly halfway between tick 30 and 32
	var s := cw.sample_remote(5)
	t.check((s["pos"] as Vector2).distance_to(Vector2(100.5, 64)) < 1e-4, "halfway between snapshots is interpolated (%s)" % s["pos"])
	cw.clock = 1.0 + 2.0 / 30.0 + 0.1 + 0.05
	s = cw.sample_remote(5)
	t.check((s["pos"] as Vector2).distance_to(Vector2(101.75, 64)) < 1e-3, "past the newest it extrapolates with velocity")
	cw.clock = 5.0
	s = cw.sample_remote(5)
	t.check((s["pos"] as Vector2).distance_to(Vector2(101 + 15 * ClientWorld.MAX_EXTRAPOLATE, 64)) < 1e-3, "extrapolation is capped")
	cw.clock = 0.5
	t.eq(cw.sample_remote(5)["pos"], Vector2(100, 64), "before the oldest sample it holds the oldest")
	cw.apply_snapshot(31, [{"id": 5, "pos": Vector2(500, 64), "vel": Vector2.ZERO, "flags": 1}])
	t.eq(cw.remotes[5].samples.size(), 2, "an out-of-order snapshot is dropped")
	var moved := {}
	cw.actor_moved.connect(func(id: int, pos: Vector2, _f: int, _s: String) -> void: moved[id] = pos)
	cw.present()
	t.check(moved.has(1) and moved.has(5), "present moves the own player and the remotes")
	var removed := []
	cw.actor_removed.connect(func(id: int) -> void: removed.append(id))
	cw.remove_remote(5)
	cw.remove_remote(5)
	t.eq(removed, [5], "removed once")

func _correction(t: TestLog) -> void:
	var cw := _setup(TileWorld.make_test())
	cw.body.vel = Vector2(10, 5)
	cw.body.jumping = true
	var got := []
	cw.corrected.connect(func(p: Vector2) -> void: got.append(p))
	cw.apply_correction(3, Vector2(50.5, 64), Vector2.ZERO)
	t.eq([cw.epoch, cw.body.pos, cw.body.vel, cw.body.jumping, cw.corrections], [3, Vector2(50.5, 64), Vector2.ZERO, false, 1], "a correction snaps the body and adopts the epoch")
	t.eq(got, [Vector2(50.5, 64)], "and is announced")
	t.eq(cw.make_state()["epoch"], 3, "later states carry the new epoch")
