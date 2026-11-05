## Host and client systems: hooks, SYS both ways over loopback (50 ms latency) and real
## ENet, to one / all / near, unknown ids ignored, per-player and world save and restore,
## hit points on the wire (ENT_ADD and VITALS) for monsters and the own player.
extends RefCounted

const Rig := preload("res://tests/net_rig.gd")
const Echo := preload("res://tests/echo_system.gd")

func run(t: TestLog) -> void:
	_hooks(t)
	_loopback(t)
	_enet(t)

func _hooks(t: TestLog) -> void:
	var host := WorldHost.new(TileWorld.make_test())
	var early := host.add_player("ann", 2)
	var sys := Echo.Host.new()
	host.add_system(sys)
	t.eq(host.system(Echo.ID), sys, "system(id) finds it")
	t.eq(host.system(99), null, "an unknown id is null")
	t.eq(sys.host, host, "attached")
	t.eq(sys.added, [early.id], "players already there are announced to a late system")
	var gob := host.add_srd_monster("goblin-warrior", host.spawn + Vector2(-10, 0))
	t.eq(sys.added, [early.id, gob.id], "monsters too")
	host.tick()
	host.tick()
	t.eq(sys.ticks, 2, "ticked every host tick")
	host.drain()
	t.check(host.receive_sys(early.id, Echo.ID, Echo.K.PING, PackedByteArray([9])), "a message for a known system is handled")
	var evs := host.drain()
	t.eq(evs.size(), 1, "one SYS event")
	t.eq([evs[0]["type"], evs[0]["sys"], evs[0]["kind"], evs[0]["to"]], [WorldHost.Ev.SYS, Echo.ID, Echo.K.PONG, early.id], "PONG to ann")
	t.check(not host.receive_sys(early.id, 77, 0, PackedByteArray()), "an unknown system id is refused, not fatal")
	t.check(not host.receive_sys(999, Echo.ID, 0, PackedByteArray()), "an unknown entity too")
	var big := PackedByteArray()
	big.resize(WorldHost.SYS_MAX + 1)
	t.check(not host.send_sys(Echo.ID, 0, big), "an oversized payload is refused")
	host.remove_entity(gob.id)
	t.eq(sys.removed, [gob.id], "entity_removed")

	# rules state on entities
	t.check(early.character != null and early.character.class_slug == "fighter", "a player without a class is a fighter")
	t.eq(early.vitals(), Vector2i(early.character.max_hp(), early.character.max_hp()), "at full hit points")
	var wiz := host.add_player("wen", 3, {"class": "wizard"})
	t.eq(wiz.character.class_slug, "wizard", "a join option picks the class")
	t.eq(host.add_player("odd", 4, {"class": "jester"}).character.class_slug, "fighter", "an unknown class falls back")
	t.eq(gob.combatant.stats.max_hp, 10, "goblin warrior: the stat block's hit points")
	t.eq([gob.stats.size_name, gob.stats.walk, gob.name], ["small", 30.0, "Goblin Warrior"], "body and speed from the stat block")
	var shark := host.add_srd_monster("hunter-shark", host.spawn + Vector2(20, 0))
	t.eq([shark.stats.size_name, shark.stats.walk, shark.stats.swim], ["large", 5.0, 40.0], "a shark: Large, swims 40, walks 5")
	t.eq(host.add_srd_monster("swarm-of-rats", host.spawn).stats.size_name, "medium", "a swarm with no size is Medium")
	t.eq(host.add_srd_monster("no-such-thing", host.spawn), null, "an unknown slug is null")
	t.eq(host.add_monster(MoveStats.player(), host.spawn, null).vitals(), HostEntity.NO_VITALS, "a monster without a combatant has no hit points")
	# Dice: the ticking host's seeded generator
	var other := WorldHost.new(TileWorld.make_test())
	t.check(Dice.rng == other.rng, "the newest host installed its dice")
	host.tick()
	t.check(Dice.rng == host.rng, "a ticking host takes them back (only the host thread rolls)")

func _loopback(t: TestLog) -> void:
	var world := TileWorld.make_test(1024, 128)
	var rig := Rig.new(world, 0.05)
	var hsys := Echo.Host.new()
	rig.host.add_system(hsys)
	var logs: Array[String] = []
	rig.ep.log_fn = func(s: String) -> void: logs.append(s)
	var mid := world.width / 2
	var ground := world.height / 2
	rig.host.records["carl"] = {"name": "carl", "pos": [mid + 160.5, ground]}
	var csys: Array = []
	var names := ["ann", "bob", "carl"]
	for i in names.size():
		var c := rig.add_client(names[i])
		var cs := Echo.Client.new()
		csys.append(cs)
		c.welcomed.connect(func(cw: ClientWorld) -> void: cw.add_system(cs))
	rig.clients[0].player_class = "wizard"
	var ready := rig.until(func() -> bool:
		return rig.clients.all(func(c: ClientEndpoint) -> bool: return c.cw != null and c.cw.area_ready()), 6.0)
	t.check(ready >= 0.0, "three clients joined")
	var ann := rig.cw(0)
	var bob := rig.cw(1)
	var carl := rig.cw(2)
	t.eq(rig.host_entity(0).character.class_slug, "wizard", "ann asked for a wizard in HELLO")
	t.eq(rig.host_entity(1).character.class_slug, "fighter", "bob got the default")
	var f0: int = csys[0].frames
	rig.run(0.2)
	t.eq(csys[0].frames - f0, 12, "client systems get a frame per client frame")
	t.eq(ann.system(Echo.ID), csys[0], "cw.system(id)")

	# client to host, host to one
	ann.send_sys(Echo.ID, Echo.K.PING, PackedByteArray([1, 2, 3]))
	t.check(rig.until(func() -> bool: return not csys[0].kinds(Echo.K.PONG).is_empty(), 1.0) >= 0.0, "ann's PING is answered")
	t.eq(csys[0].last_pong(), [1, 1, PackedByteArray([1, 2, 3])], "PONG: her count, the total, her bytes")
	rig.run(0.3)
	t.check(csys[1].kinds(Echo.K.PONG).is_empty() and csys[2].kinds(Echo.K.PONG).is_empty(), "nobody else gets ann's PONG")
	# host to all, host to near
	bob.send_sys(Echo.ID, Echo.K.SHOUT, PackedByteArray([7]))
	bob.send_sys(Echo.ID, Echo.K.NEAR, PackedByteArray([8]))
	rig.run(0.4)
	t.eq(csys.map(func(c: Echo.Client) -> int: return c.kinds(Echo.K.SHOUT).size()), [1, 1, 1], "SHOUT reaches every player")
	t.eq(csys.map(func(c: Echo.Client) -> int: return c.kinds(Echo.K.NEAR).size()), [1, 1, 0], "NEAR reaches ann and bob, not far carl")
	t.eq(csys[0].got.map(func(g: Array) -> int: return g[0]), [Echo.K.PONG, Echo.K.SHOUT, Echo.K.NEAR], "in order")
	# unknown ids, both ways
	ann.send_sys(77, 1, PackedByteArray([1]))
	ann.send_sys(77, 2, PackedByteArray([1]))
	rig.host.send_sys(201, 0, PackedByteArray([5]), WorldHost.ALL)
	rig.run(0.3)
	t.eq(logs.filter(func(s: String) -> bool: return s.begins_with("ignored SYS for unknown system 77")).size(), 1, "the host logs an unknown system once")
	t.check(rig.ep.playing_count() == 3 and rig.clients.all(func(c: ClientEndpoint) -> bool: return c.phase == ClientEndpoint.Phase.PLAYING),
			"nobody is kicked for it, and clients ignore one too")
	ann.send_sys(Echo.ID, Echo.K.PING, PackedByteArray())
	rig.until(func() -> bool: return csys[0].kinds(Echo.K.PONG).size() == 2, 1.0)
	t.eq(csys[0].last_pong().slice(0, 2), [2, 2], "the stream goes on after them")

	# hit points: a goblin near ann and bob, far from carl
	var gob := rig.host.add_srd_monster("goblin-warrior", Vector2(mid - 10.5, ground))
	rig.run(0.4)
	t.eq(ann.vitals_of(gob.id), Vector2i(10, 10), "ENT_ADD brings the goblin's hit points")
	t.eq(carl.vitals_of(gob.id), Vector2i(-1, -1), "carl does not see it")
	var heard: Array = []
	ann.vitals_changed.connect(func(id: int, hp: int, mx: int) -> void: heard.append([id, hp, mx]))
	gob.combatant.stats.current_hp = 4
	var me := rig.host_entity(0)
	me.combatant.stats.current_hp = 2
	t.check(rig.until(func() -> bool: return ann.vitals_of(gob.id) == Vector2i(4, 10) and ann.hp == 2, 1.0) >= 0.0, "damage reaches ann (VITALS)")
	t.eq(bob.vitals_of(gob.id), Vector2i(4, 10), "and bob")
	t.eq(ann.max_hp, me.combatant.stats.max_hp, "ann knows her own max")
	t.eq(bob.vitals_of(ann.my_id), Vector2i(2, me.combatant.stats.max_hp), "bob sees ann hurt")
	t.check([gob.id, 4, 10] in heard and [ann.my_id, 2, me.combatant.stats.max_hp] in heard, "vitals_changed fires for both")
	var vit := _count(rig.clients[0], Protocol.T.VITALS)
	rig.run(0.5)
	t.eq(_count(rig.clients[0], Protocol.T.VITALS), vit, "nothing more is sent while nothing changes")

	# save, quit, load, rejoin
	me.character.level = 7
	me.combatant.stats.current_hp = 5
	var dir := OS.get_user_data_dir().path_join("test_systems_save")
	_rm(dir)
	t.eq(rig.host.save(dir), OK, "host saved (players and host.json)")
	var rec: Dictionary = rig.host.records["ann"]
	t.eq(rec["systems"][str(Echo.ID)], {"pings": 2}, "ann's record holds the system's part")
	t.eq(rec["character"]["hp"], 5, "and her character's hit points")
	var rig2 := Rig.new(world, 0.05)
	t.eq(rig2.host.load_players(dir), 3, "players loaded")
	t.check(rig2.host.load_state(dir), "host state loaded before the system exists")
	var hsys2 := Echo.Host.new()
	rig2.host.add_system(hsys2)
	t.eq(hsys2.total, 2, "world state handed over when the system is added")
	var a2 := rig2.add_client("ann")
	var cs2 := Echo.Client.new()
	a2.welcomed.connect(func(cw: ClientWorld) -> void: cw.add_system(cs2))
	t.check(rig2.until(func() -> bool: return a2.cw != null and a2.cw.area_ready(), 5.0) >= 0.0, "ann rejoins")
	var e2 := rig2.host_entity(0)
	t.eq([e2.character.class_slug, e2.character.level, e2.vitals().x], ["wizard", 7, 5], "her character comes back (class, level, hit points)")
	t.eq(e2.vitals().y, e2.character.max_hp(), "max hit points from the level")
	t.check(rig2.until(func() -> bool: return a2.cw.hp == 5, 1.0) >= 0.0, "and her client hears them")
	a2.cw.send_sys(Echo.ID, Echo.K.PING, PackedByteArray())
	t.check(rig2.until(func() -> bool: return not cs2.kinds(Echo.K.PONG).is_empty(), 1.0) >= 0.0, "PING after the rejoin")
	t.eq(cs2.last_pong().slice(0, 2), [3, 3], "her count and the world's total survived")
	_rm(dir)

func _enet(t: TestLog) -> void:
	var host := WorldHost.new(TileWorld.make_test(512, 128))
	var hsys := Echo.Host.new()
	host.add_system(hsys)
	var server := EnetTransport.new()
	var port := 0
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 8:
		var p := rng.randi_range(30000, 60000)
		if server.listen(p, 4, "127.0.0.1") == OK:
			port = p
			break
	t.check(port != 0, "ENet server listens")
	if port == 0:
		return
	var ep := HostEndpoint.new(host, server)
	var ct := EnetTransport.new()
	ct.connect_to("127.0.0.1", port)
	var client := ClientEndpoint.new(ct, "ann")
	client.player_class = "rogue"
	var cs := Echo.Client.new()
	client.welcomed.connect(func(cw: ClientWorld) -> void: cw.add_system(cs))
	var inp := PlayerInput.new()
	var clock := [0.0, 0.0]
	var pump := func() -> void:
		var dt := 1.0 / 120.0
		OS.delay_usec(int(dt * 1e6))
		clock[1] += dt
		clock[0] += dt
		while clock[0] >= 1.0 / K.TICK_HZ:
			clock[0] -= 1.0 / K.TICK_HZ
			ep.tick()
		client.frame(dt, inp)
	var until := func(cond: Callable, limit: float) -> bool:
		var start: float = clock[1]
		while clock[1] - start < limit:
			if cond.call():
				return true
			pump.call()
		return cond.call()
	t.check(until.call(func() -> bool: return client.cw != null and client.cw.area_ready(), 5.0), "joined over ENet")
	var gob := host.add_srd_monster("goblin-warrior", host.spawn + Vector2(-8, 0))
	client.cw.send_sys(Echo.ID, Echo.K.PING, PackedByteArray([42]))
	client.cw.send_sys(Echo.ID, Echo.K.SHOUT, PackedByteArray([43]))
	t.check(until.call(func() -> bool: return cs.got.size() >= 2, 2.0), "PING and SHOUT answered over ENet")
	t.eq(cs.got.map(func(g: Array) -> int: return g[0]), [Echo.K.PONG, Echo.K.SHOUT], "in order")
	t.eq(cs.last_pong(), [1, 1, PackedByteArray([42])], "PONG intact")
	t.check(until.call(func() -> bool: return client.cw.vitals_of(gob.id) == Vector2i(10, 10), 1.0), "the goblin's hit points arrive over ENet")
	var me := host.entity(client.cw.my_id)
	t.eq(me.character.class_slug, "rogue", "class from HELLO over ENet")
	t.check(until.call(func() -> bool: return client.cw.max_hp == me.character.max_hp(), 1.0), "own hit points too (%d)" % client.cw.max_hp)
	client.leave()
	until.call(func() -> bool: return ep.playing_count() == 0, 2.0)
	t.eq(host.records["ann"]["systems"][str(Echo.ID)], {"pings": 1}, "her system state is kept on leave")
	server.close()

func _count(c: ClientEndpoint, type: int) -> int:
	var row: Array = c.received_by_type.get(type, [0, 0])
	return row[0]

static func _rm(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_rm(dir.path_join(sub))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
