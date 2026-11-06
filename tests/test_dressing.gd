## Dressing records in core: worldgen places them deterministically, chunks and saves carry
## them, the host removes one whose support is dug (or whose footprint is built into) and
## clients are told.
extends RefCounted

const Rig := preload("res://tests/net_rig.gd")

func run(t: TestLog) -> void:
	_defs(t)
	_chunk_blob(t)
	_worldgen(t)
	_host(t)

func _defs(t: TestLog) -> void:
	t.eq(Dressing.name_of(0), "tree_generic", "id 0 is the first entry of the ids list")
	t.eq(Dressing.id("stalagmite"), 12, "ids are stable list positions")
	t.eq(Dressing.footprint(Dressing.id("tree_large")), Vector2i(6, 12), "footprint from the data")
	t.eq(Dressing.count(), DressingView.defs().size(), "every object in the view's table has an id")

func _chunk_blob(t: TestLog) -> void:
	var c := Chunk.new(1, 2)
	c.fg.encode_u16(10, 3)
	var plain := c.to_bytes()
	t.check(plain[0] != Chunk.OBJ_MARK, "a chunk without objects keeps the old blob format")
	c.add_object(3, 4, 5, 200)
	c.add_object(12, 31, 0, 7)
	var blob := c.to_bytes()
	t.eq(blob[0], Chunk.OBJ_MARK, "with objects the blob is marked")
	var back := Chunk.new(1, 2)
	back.from_bytes(blob)
	t.eq(back.object_count(), 2, "objects round-trip")
	t.eq(back.object_at(1), Vector4i(12, 31, 0, 7), "record fields round-trip")
	t.eq(back.fg, c.fg, "tiles still round-trip")
	var old := Chunk.new(0, 0)
	old.from_bytes(plain)
	t.eq(old.fg.size(), Chunk.CELLS * 2, "an old blob still decodes")
	var bad := blob.duplicate()
	bad.encode_u16(1, 9)
	var b2 := Chunk.new(0, 0)
	b2.from_bytes(bad)
	t.check(b2.fg.size() != Chunk.CELLS * 2, "a blob whose count disagrees is refused")
	back.remove_object(0)
	t.eq(back.object_count(), 1, "remove_object")
	t.eq(back.object_at(0).x, 12, "keeps the rest")

func _worldgen(t: TestLog) -> void:
	var a := WorldGen.generate(1024, 512, 5)
	var b := WorldGen.generate(1024, 512, 5)
	var surf := 0
	var cave := 0
	var bad := 0
	var same := true
	for cy in a.chunks_y:
		for cx in a.chunks_x:
			same = same and a.chunk_at(cx, cy).objects == b.chunk_at(cx, cy).objects
			for r: Dictionary in Dressing.records_in(a, cx, cy):
				if String(Dressing.def(r["id"])["where"].get("band", "surface")) == "cave":
					cave += 1
				else:
					surf += 1
				if not Dressing.holds(a, r["id"], r["x"], r["y"]):
					bad += 1
	t.check(same, "the same seed places the same dressing")
	t.check(surf > 40, "the surface is dressed (%d objects; only the meadow has a set so far)" % surf)
	t.check(cave > 10, "caves are dressed (%d objects)" % cave)
	t.eq(bad, 0, "every object stands on solid ground with a clear footprint")
	t.check(WorldGen.last_timings.has("dressing"), "the stage is timed (%d ms)" % WorldGen.last_timings.get("dressing", -1))
	var dir := OS.get_user_data_dir().path_join("test_dressing_save")
	t.eq(WorldSave.save(a, dir), OK, "a dressed world saves")
	var back := WorldSave.load(dir)
	t.eq(back.content_hash(), a.content_hash(), "and loads with its objects (content_hash covers them)")
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))

func _host(t: TestLog) -> void:
	var world := TileWorld.make_test(256, 128)
	var g := world.height / 2
	var mid := world.width / 2
	var tree := Dressing.id("tree_round")
	var bush := Dressing.id("bush")
	world.chunk_at((mid - 6) >> 5, g >> 5).add_object(tree, (mid - 6) & 31, g & 31, 1)
	world.chunk_at((mid + 3) >> 5, g >> 5).add_object(bush, (mid + 3) & 31, g & 31, 2)
	var rig := Rig.new(world, 0.05)
	var ann := rig.add_client("ann")
	rig.until(func() -> bool: return ann.cw != null and ann.cw.area_ready(), 5.0)
	var held := func(cw: ClientWorld) -> int:
		var n := 0
		for c: Vector2i in cw.loaded:
			n += cw.world.chunk_at(c.x, c.y).object_count()
		return n
	t.eq(held.call(ann.cw), 2, "chunks arrive with their objects")
	var changes := []
	ann.cw.world.objects_changed.connect(func(cx: int, cy: int) -> void: changes.append(Vector2i(cx, cy)))
	# Digging a tile beside the tree's footprint changes nothing.
	rig.host.world.set_fg(mid - 7, g - 1, TileDefs.AIR)
	rig.run(0.3)
	t.eq(held.call(ann.cw), 2, "digging next to a tree leaves it")
	# Digging one of the tiles it stands on removes it, for everyone.
	rig.inputs[0].dig = true
	rig.inputs[0].target = Vector2i(mid - 4, g - 1)
	rig.until(func() -> bool: return rig.host.world.get_fg(mid - 4, g - 1) == TileDefs.AIR, 3.0)
	rig.inputs[0].dig = false
	rig.run(0.3)
	t.eq(rig.host.world.chunk_at((mid - 6) >> 5, g >> 5).object_count(), 0, "the host removes a tree whose ground is dug")
	t.eq(held.call(ann.cw), 1, "and the client is told")
	t.check(not changes.is_empty(), "objects_changed fires on the client")
	# A block placed into the bush's footprint removes the bush.
	rig.inputs[0].place = true
	rig.inputs[0].place_tile = TileDefs.id("wood")
	rig.inputs[0].target = Vector2i(mid + 4, g)
	rig.frame()
	rig.inputs[0].place = false
	rig.run(0.4)
	t.eq(held.call(ann.cw), 0, "a block placed into a bush removes it")
	t.check(rig.in_sync(0), "client and host digests (objects included) match")
	var m := Protocol.decode(Protocol.objects(3, 4, PackedByteArray([1, 0, 2, 3, 4])))
	t.eq([m.get("cx"), m.get("cy"), m.get("records")], [3, 4, PackedByteArray([1, 0, 2, 3, 4])], "OBJECTS round-trips")
	t.eq(Protocol.decode(Protocol.objects(3, 4, PackedByteArray([1, 0, 2, 3, 4])).slice(0, 9)), {}, "a short OBJECTS is refused")
