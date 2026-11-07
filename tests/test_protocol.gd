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

	# protocol 6: class in HELLO, hit points in ENT_ADD, VITALS, SYS
	m = Protocol.decode(Protocol.hello("ann", "wizard"))
	t.eq([m.get("name"), m.get("class")], ["ann", "wizard"], "hello carries a class")
	var h5 := Protocol.hello("ann")
	t.eq(Protocol.decode(h5.slice(0, h5.size() - 1)).get("class"), "", "a hello without the class field decodes (old clients reach the version check)")
	var ea := Protocol.ent_add(7, HostEntity.Kind.MONSTER, Vector2(1, 1), Vector2(2, 3), 1, "Goblin Warrior", 4, 10)
	t.eq(ea.size(), 33 + "Goblin Warrior".length(), "entity add: 33 + name without a look")
	# protocol 7: the compact look
	var look := {"slug": "goblin-warrior", "people": "human:raider", "rank": "champion", "scale": 1.3, "wield": "Scimitar, Dagger", "color": Color.RED, "name": "x"}
	var el := Protocol.decode(Protocol.ent_add(7, HostEntity.Kind.MONSTER, Vector2(1, 1), Vector2(2, 3), 1, "Gob", 4, 10, look))
	t.eq(el.get("look"), {"slug": "goblin-warrior", "people": "human:raider", "rank": "champion", "scale": 1.3, "wield": "Scimitar, Dagger"}, "entity add carries the compact look")
	t.eq(el.get("look"), Protocol.compact_look(look), "compact_look is what decodes")
	t.eq(Protocol.decode(Protocol.ent_add(7, 0, Vector2.ONE, Vector2.ZERO, 0, "x")).get("look"), {}, "no look: empty")
	t.eq(Protocol.decode(Protocol.ent_add(7, 1, Vector2.ONE, Vector2.ZERO, 0, "x", 0, 0, {"slug": "player:wizard"})).get("look"),
		{"slug": "player:wizard"}, "a player's class look")
	var full := Protocol.ent_add(7, 1, Vector2.ONE, Vector2.ZERO, 0, "x", 0, 0, look)
	var refused := 0
	for n in full.size():
		if Protocol.decode(full.slice(0, n)).is_empty():
			refused += 1
	t.eq(refused, full.size(), "every truncated ENT_ADD is refused")
	m = Protocol.decode(ea)
	t.eq([m.get("hp"), m.get("max_hp"), m.get("name")], [4, 10, "Goblin Warrior"], "entity add carries hit points")
	t.eq(Protocol.decode(Protocol.ent_add(7, 0, Vector2.ONE, Vector2.ZERO, 0, "x")).get("max_hp"), 0, "no hit points: max 0")
	var vents := [{"id": 1, "hp": 0, "max_hp": 12}, {"id": 4000000000, "hp": 65535, "max_hp": 65535}]
	var vb := Protocol.vitals(vents)
	t.eq(vb.size(), 2 + 8 * 2, "vitals: 2 + 8 per entity")
	t.eq(Protocol.decode(vb).get("entries"), vents, "vitals round trip")
	t.eq(Protocol.decode(Protocol.vitals([{"id": 1, "hp": -5, "max_hp": 99999}])).get("entries"), [{"id": 1, "hp": 0, "max_hp": 65535}], "vitals clamp to u16")
	var payload := PackedByteArray([1, 2, 3, 250])
	var sm := Protocol.sys(3, 17, payload)
	t.eq(sm.size(), 3 + 4, "sys: 3 + payload")
	m = Protocol.decode(sm)
	t.eq([m.get("type"), m.get("sys"), m.get("kind"), m.get("data")], [Protocol.T.SYS, 3, 17, payload], "sys round trip")
	t.eq(Protocol.decode(Protocol.sys(255, 0, PackedByteArray())).get("data"), PackedByteArray(), "sys with an empty payload")
	t.check(not Protocol.unreliable(Protocol.T.SYS) and not Protocol.unreliable(Protocol.T.VITALS), "sys and vitals are reliable and ordered")
	var big := PackedByteArray()
	big.resize(Protocol.MAX_SYS)
	t.eq(Protocol.decode(Protocol.sys(1, 1, big)).get("data", PackedByteArray()).size(), Protocol.MAX_SYS, "a payload at the cap passes")
	big.resize(Protocol.MAX_SYS + 1)
	t.eq(Protocol.sys(1, 1, big), PackedByteArray(), "over the cap is not encoded")
	var over := PackedByteArray([Protocol.T.SYS, 1, 1])
	over.append_array(big)
	t.eq(Protocol.decode(over), {}, "and not decoded")
	t.eq(Protocol.decode(PackedByteArray([Protocol.T.SYS, 1])), {}, "a truncated sys is rejected")
	t.eq(WorldHost.SYS_MAX, Protocol.MAX_SYS, "host and protocol agree on the cap")
