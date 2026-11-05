extends RefCounted

func run(t: TestLog) -> void:
	var m := Protocol.decode(Protocol.hello("Ann the Bold"))
	t.eq(m.get("type"), Protocol.T.HELLO, "hello type")
	t.eq(m.get("magic"), Protocol.MAGIC, "hello magic")
	t.eq(m.get("version"), Protocol.VERSION, "hello version")
	t.eq(m.get("name"), "Ann the Bold", "hello name")
	t.eq(Protocol.decode(Protocol.hello("x".repeat(200))).get("name", "").length(), Protocol.MAX_STR, "names are capped")
	t.eq(Protocol.decode(Protocol.hello("Zoë")).get("name"), "Zoë", "utf-8 names survive")

	var st := Protocol.state(65535, 123456, Vector2(1000.5, 63.25), Vector2(-13.0, 33.75), 0xA5)
	t.eq(st.size(), 20, "state is 20 bytes")
	m = Protocol.decode(st)
	t.eq([m.get("epoch"), m.get("seq"), m.get("pos"), m.get("vel"), m.get("flags")],
			[65535, 123456, Vector2(1000.5, 63.25), Vector2(-13.0, 33.75), 0xA5], "state round trip")
	m = Protocol.decode(Protocol.state(0, 0, Vector2.ZERO, Vector2(0.01, 9999.0), 0))
	t.check(absf(m["vel"].x - 0.0) <= 1.0 / 64.0 and m["vel"].y == 32767.0 / 64.0, "velocity quantized to 1/64 and clamped")

	m = Protocol.decode(Protocol.edit(7, ClientWorld.Op.PLACE, 16383, -5, 9))
	t.eq([m.get("req"), m.get("op"), m.get("x"), m.get("y"), m.get("tile")], [7, ClientWorld.Op.PLACE, 16383, -5, 9], "edit round trip")
	t.eq(Protocol.edit(1, 0, 0, 0, 0).size(), 12, "edit is 12 bytes")
	t.eq(Protocol.decode(Protocol.bye(Protocol.Why.FINAL)).get("reason"), Protocol.Why.FINAL, "bye")
	t.eq(Protocol.decode(Protocol.check_req("final")).get("tag"), "final", "check request")

	var w := Protocol.welcome(42, 8192, 2560, -1234567890123, Vector2(4096.5, 1800), 3, 30, 15, 2)
	t.eq(w.size(), 36, "welcome is 36 bytes")
	m = Protocol.decode(w)
	t.eq([m.get("id"), m.get("width"), m.get("height"), m.get("seed"), m.get("pos"), m.get("epoch"), m.get("tick_hz"), m.get("snapshot_hz"), m.get("radius")],
			[42, 8192, 2560, -1234567890123, Vector2(4096.5, 1800), 3, 30, 15, 2], "welcome round trip")
	m = Protocol.decode(Protocol.reject(Protocol.Why.FULL, "full"))
	t.eq([m.get("type"), m.get("reason"), m.get("text")], [Protocol.T.REJECT, Protocol.Why.FULL, "full"], "reject")
	m = Protocol.decode(Protocol.kick(Protocol.Why.TIMEOUT, ""))
	t.eq([m.get("type"), m.get("reason"), m.get("text")], [Protocol.T.KICK, Protocol.Why.TIMEOUT, ""], "kick with empty text")

	var world := TileWorld.make_test()
	var blob := world.chunk_at(3, 1).to_bytes()
	m = Protocol.decode(Protocol.chunk(3, 1, blob))
	t.eq([m.get("cx"), m.get("cy"), m.get("blob")], [3, 1, blob], "chunk round trip")
	var c := Chunk.new(3, 1)
	c.from_bytes(m["blob"])
	t.eq(c.fg, world.chunk_at(3, 1).fg, "chunk blob decodes to the same tiles")

	var coords: Array[Vector2i] = [Vector2i(0, 0), Vector2i(511, 127), Vector2i(-1, 3)]
	m = Protocol.decode(Protocol.unload(coords))
	t.eq(m.get("coords"), coords, "unload round trip")

	var d := PackedInt32Array([1, 2, 0, 3, 16383, 4095, 2, 255, 0, 0, 1, 65535])
	var tb := Protocol.tiles(d)
	t.eq(tb.size(), 3 + 7 * 3, "tiles: 3 + 7 per delta")
	t.eq(Protocol.decode(tb).get("deltas"), d, "tiles round trip")

	m = Protocol.decode(Protocol.ent_add(99, HostEntity.Kind.MONSTER, Vector2(2.5, 3.5), Vector2(10.25, 20), 3, "goblin"))
	t.eq([m.get("id"), m.get("kind"), m.get("size"), m.get("pos"), m.get("flags"), m.get("name")],
			[99, HostEntity.Kind.MONSTER, Vector2(2.5, 3.5), Vector2(10.25, 20), 3, "goblin"], "entity add round trip")
	t.eq(Protocol.decode(Protocol.ent_remove(99)).get("id"), 99, "entity remove")

	var entries := [{"id": 1, "pos": Vector2(1.5, 2), "vel": Vector2(13, 0), "flags": 3},
			{"id": 70000, "pos": Vector2(8000.125, 2000.5), "vel": Vector2(0, -40), "flags": 0}]
	var sb := Protocol.snapshot(4000000000, entries)
	t.eq(sb.size(), 6 + 17 * 2, "snapshot: 6 + 17 per entity")
	m = Protocol.decode(sb)
	t.eq(m.get("tick"), 4000000000, "snapshot tick (u32)")
	t.eq(m.get("entries"), entries, "snapshot entries round trip")

	m = Protocol.decode(Protocol.correct(5, Vector2(3, 4), Vector2(0, -1.5)))
	t.eq([m.get("epoch"), m.get("pos"), m.get("vel")], [5, Vector2(3, 4), Vector2(0, -1.5)], "correct round trip")
	m = Protocol.decode(Protocol.result(77, WorldHost.Reason.OUT_OF_REACH, 10, 11, 3))
	t.eq([m.get("req"), m.get("reason"), m.get("x"), m.get("y"), m.get("tile")], [77, WorldHost.Reason.OUT_OF_REACH, 10, 11, 3], "result round trip")

	var digest := ChunkHash.raw(world, coords.slice(0, 1))
	m = Protocol.decode(Protocol.check("pre", coords, digest, Vector2(1, 2)))
	t.eq([m.get("tag"), m.get("coords"), m.get("digest"), m.get("pos")], ["pre", coords, digest, Vector2(1, 2)], "check round trip")

	# malformed input
	t.eq(Protocol.decode(PackedByteArray()), {}, "empty packet is rejected")
	t.eq(Protocol.decode(PackedByteArray([200, 1, 2])), {}, "unknown type is rejected")
	t.eq(Protocol.decode(st.slice(0, 19)), {}, "truncated state is rejected")
	var long := st.duplicate()
	long.append(0)
	t.eq(Protocol.decode(long), {}, "trailing bytes are rejected")
	var bad_tiles := Protocol.tiles(d)
	bad_tiles.encode_u16(1, 50)
	t.eq(Protocol.decode(bad_tiles), {}, "a tile count larger than the packet is rejected")
	var bad_str := Protocol.hello("abc")
	bad_str[7] = 60
	t.eq(Protocol.decode(bad_str), {}, "a string length past the end is rejected")
	var all_ok := true
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 300:
		var junk := PackedByteArray()
		junk.resize(rng.randi_range(0, 40))
		for k in junk.size():
			junk[k] = rng.randi_range(0, 255)
		var r: Variant = Protocol.decode(junk)
		all_ok = all_ok and r is Dictionary
	t.check(all_ok, "random junk never crashes the decoder")
