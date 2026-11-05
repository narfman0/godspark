extends RefCounted

const R := WorldHost.Reason

func run(t: TestLog) -> void:
	_join_and_spawn(t)
	_digging(t)
	_placing(t)
	_validation(t)
	_monster_slot(t)
	_saving(t)
	_dice(t)

static func events_of(evs: Array[Dictionary], type: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in evs:
		if int(e["type"]) == type:
			out.append(e)
	return out

func _join_and_spawn(t: TestLog) -> void:
	var host := WorldHost.new(TileWorld.make_test())
	var ground := host.world.height / 2
	t.eq(host.spawn, Vector2(host.world.width / 2 + 0.5, ground), "spawn stands on the ground in the middle")
	var a := host.add_player("ann", 7)
	t.eq(a.body.pos, host.spawn, "a new player spawns at the spawn point")
	t.check(a.body.on_floor, "and stands on the floor")
	t.eq(a.owner, 7, "owned by its peer")
	var evs := host.drain()
	t.eq(events_of(evs, WorldHost.Ev.JOIN).size(), 1, "join event")
	t.eq(host.drain().size(), 0, "drain empties the outbox")
	t.eq(host.player_named("ann"), a, "found by name")
	host.remove_entity(a.id)
	t.eq(events_of(host.drain(), WorldHost.Ev.LEAVE).size(), 1, "leave event")
	t.check(host.records.has("ann"), "a leaving player leaves a record")
	host.records["ann"]["pos"] = [40.5, ground]
	var a2 := host.add_player("ann", 8)
	t.eq(a2.body.pos, Vector2(40.5, ground), "rejoining restores the recorded position")
	t.check(a2.id != a.id, "with a fresh entity id")
	host.records["bob"] = {"name": "bob", "pos": [40.5, ground - 3]}
	t.eq(host.add_player("bob", 9).body.pos, Vector2(40.5, ground), "a record inside rock steps out to the nearest free spot")

func _digging(t: TestLog) -> void:
	var host := WorldHost.new(TileWorld.make_test())
	var w := host.world
	var a := host.add_player("ann", 2)
	var x := int(a.body.pos.x)
	var gy := w.height / 2 - 1          # grass under the feet
	host.drain()
	t.eq(host.request_dig(a.id, 1, x, gy), R.OK, "a dig in reach starts")
	var ticks := 0
	var done := false
	while ticks < 60 and not done:
		host.tick()
		ticks += 1
		done = w.get_fg(x, gy) == TileDefs.AIR
	var need := 12   # grass: 0.4 s at 30 Hz, exactly
	t.eq(ticks, need, "grass is dug after its dig time (%d ticks)" % need)
	var evs := host.drain()
	var tiles := events_of(evs, WorldHost.Ev.TILE)
	t.eq(tiles.size(), 1, "one tile event")
	t.eq([tiles[0]["x"], tiles[0]["y"], tiles[0]["value"]], [x, gy, TileDefs.AIR], "tile event says air")
	var res := events_of(evs, WorldHost.Ev.EDIT_RESULT)
	t.eq([res.size(), res[0]["req"], res[0]["reason"], res[0]["owner"]], [1, 1, R.OK, 2], "dig result OK to the owner")

	# not before its time
	t.eq(host.request_dig(a.id, 2, x + 1, gy), R.OK, "second dig starts")
	for i in need - 1:
		host.tick()
	t.check(w.get_fg(x + 1, gy) != TileDefs.AIR, "not done one tick early")
	host.stop_dig(a.id)
	host.tick()
	host.tick()
	t.check(w.get_fg(x + 1, gy) != TileDefs.AIR, "letting go stops the dig")
	t.eq(host.request_dig(a.id, 3, x + 1, gy), R.OK, "restarting")
	host.tick()
	t.check(w.get_fg(x + 1, gy) != TileDefs.AIR, "a restarted dig starts from zero")
	host.drain()

	# refusals
	t.eq(host.request_dig(a.id, 4, x + 20, gy), R.OUT_OF_REACH, "out of reach is refused")
	t.eq(host.request_dig(a.id, 5, x, gy + 3), R.NOTHING_THERE, "air is refused")
	w.set_fg(x - 1, gy, TileDefs.id("bedrock"))
	t.eq(host.request_dig(a.id, 6, x - 1, gy), R.UNBREAKABLE, "bedrock is refused")
	t.eq(host.request_dig(a.id, 7, -3, gy), R.OUT_OF_BOUNDS, "outside the world is refused")
	t.eq(host.request_dig(99, 8, x, gy), R.NO_ENTITY, "unknown entity")
	var refusals := events_of(host.drain(), WorldHost.Ev.EDIT_RESULT)
	t.eq(refusals.size(), 4, "each refusal is reported")
	t.eq(refusals[0]["reason"], R.OUT_OF_REACH, "with its reason")

	# a dig that walks out of reach stops
	t.eq(host.request_dig(a.id, 9, x + 2, gy), R.OK, "dig next to you")
	host.tick()
	a.body.pos.x += 12.0
	host.tick()
	var st := events_of(host.drain(), WorldHost.Ev.EDIT_RESULT)
	t.eq(st.size() == 1 and st[0]["reason"] == R.OUT_OF_REACH, true, "walking away cancels the dig with OUT_OF_REACH")

	# two players digging the same tile: one wins, the other is told it is gone
	a.body.pos.x -= 12.0
	var b := host.add_player("bob", 3)
	host.drain()
	host.request_dig(a.id, 10, x + 3, gy)
	host.request_dig(b.id, 11, x + 3, gy)
	for i in need + 2:
		host.tick()
	var both := events_of(host.drain(), WorldHost.Ev.EDIT_RESULT)
	t.eq(both.size(), 2, "both diggers get a result")
	t.eq(both.map(func(e: Dictionary) -> int: return e["reason"]), [R.OK, R.NOTHING_THERE], "first wins, second finds nothing")

func _placing(t: TestLog) -> void:
	var host := WorldHost.new(TileWorld.make_test())
	var w := host.world
	var a := host.add_player("ann", 2)
	var b := host.add_player("bob", 3)
	var x := int(a.body.pos.x)
	var gy := w.height / 2
	var wood := TileDefs.id("wood")
	b.body.pos = Vector2(x + 4.5, gy)
	host.drain()
	t.eq(host.request_place(a.id, 1, x + 2, gy, wood), R.OK, "place on the ground next to you")
	t.eq(w.get_fg(x + 2, gy), wood, "the tile is there")
	t.eq(host.request_place(a.id, 2, x + 2, gy, wood), R.OCCUPIED, "placing on a tile is refused")
	t.eq(host.request_place(a.id, 3, x + 4, gy, wood), R.BLOCKED, "placing a solid tile inside another player is refused")
	t.eq(host.request_place(a.id, 4, x + 4, gy, TileDefs.id("torch")), R.OK, "a torch may go where someone stands")
	t.eq(host.request_place(a.id, 5, x - 2, gy + 4, wood), R.NO_ANCHOR, "floating in air is refused")
	t.eq(host.request_place(a.id, 6, x + 30, gy, wood), R.OUT_OF_REACH, "out of reach is refused")
	t.eq(host.request_place(a.id, 7, x - 2, gy, TileDefs.id("bedrock")), R.BAD_TILE, "players cannot place bedrock")
	t.eq(host.request_place(a.id, 8, x - 2, gy, 7), R.BAD_TILE, "an undefined tile id is refused")
	t.eq(host.request_place(a.id, 9, x - 2, gy, 999), R.BAD_TILE, "an out-of-range tile id is refused")
	t.eq(host.request_place(b.id, 10, x + 2, gy + 1, wood), R.OK, "bob stacks on ann's block")
	var evs := host.drain()
	t.eq(events_of(evs, WorldHost.Ev.TILE).size(), 3, "three tile events")
	t.eq(events_of(evs, WorldHost.Ev.EDIT_RESULT).size(), 10, "every place request gets a result")

func _validation(t: TestLog) -> void:
	var host := WorldHost.new(TileWorld.make_test())
	var a := host.add_player("ann", 2)
	var p0 := a.body.pos
	var SC := WorldHost.StateCheck
	host.tick()
	host.tick()
	# 4 ticks = 8 steps of running: 13 t/s * 8/60 = 1.7 tiles
	host.tick()
	host.tick()
	t.eq(host.submit_state(a.id, 0, 8, p0 + Vector2(1.7, 0), Vector2(13, 0), 3), SC.OK, "a legal run is accepted")
	t.eq(a.body.pos, p0 + Vector2(1.7, 0), "and moves the host's body")
	t.eq(host.submit_state(a.id, 0, 8, p0, Vector2.ZERO, 3), SC.STALE, "a repeated seq is stale")
	t.eq(host.submit_state(a.id, 0, 6, p0, Vector2.ZERO, 3), SC.STALE, "an older seq is stale")
	host.tick()
	t.eq(host.submit_state(a.id, 0, 10, p0 + Vector2(1.7, 3.0), Vector2(0, 30), 3), SC.OK, "a jump's rise is accepted")
	host.drain()
	host.tick()
	var at := a.body.pos
	t.eq(host.submit_state(a.id, 0, 12, at + Vector2(50, 0), Vector2.ZERO, 3), SC.TOO_FAST, "a teleport is refused")
	t.eq(a.body.pos, at, "the body stays where it was")
	t.eq(a.epoch, 1, "the epoch moves on")
	var cor := events_of(host.drain(), WorldHost.Ev.CORRECT)
	t.eq(cor.size(), 1, "one correction")
	t.eq([cor[0]["owner"], cor[0]["epoch"], cor[0]["pos"]], [2, 1, at], "sent to the owner with the new epoch and the good position")
	t.eq(host.submit_state(a.id, 0, 14, at, Vector2.ZERO, 3), SC.STALE, "states from before the correction are ignored")
	host.tick()
	t.eq(host.submit_state(a.id, 1, 16, at + Vector2(0.4, 0), Vector2.ZERO, 3), SC.OK, "the corrected client is accepted again")
	host.tick()
	var under := Vector2(at.x, host.world.height / 2 - 0.5)
	t.eq(host.submit_state(a.id, 1, 18, under, Vector2.ZERO, 3), SC.IN_SOLID, "a position inside rock is refused")
	t.eq(host.submit_state(a.id, 2, 20, Vector2(-5, 70), Vector2.ZERO, 3), SC.OUT_OF_BOUNDS, "outside the world is refused")
	t.eq(host.submit_state(a.id, 3, 22, Vector2(NAN, 70), Vector2.ZERO, 3), SC.OUT_OF_BOUNDS, "NaN is refused")
	t.eq(a.corrections, 4, "four corrections counted")
	# the clock is the host's: a client claiming lots of steps cannot move further
	host.tick()
	t.eq(host.submit_state(a.id, 4, 22 + 600, a.body.pos + Vector2(20, 0), Vector2.ZERO, 3), SC.TOO_FAST,
			"claiming 10 s of steps after 1 host tick does not buy distance")
	# a long fall over real time is fine
	var b := host.add_player("bob", 3)
	b.body.pos = Vector2(40.5, 120)
	for i in 30:
		host.tick()
	t.eq(host.submit_state(b.id, 0, 60, Vector2(40.5, 85), Vector2(0, -40), 0), SC.OK, "a 35-tile fall in a second is fine")

func _monster_slot(t: TestLog) -> void:
	var host := WorldHost.new(TileWorld.make_test())
	var stats := MoveStats.from_srd({"walk": 30}, "small")
	var brain := WalkRight.new()
	var m := host.add_monster(stats, host.spawn + Vector2(-20, 0), brain, {"name": "goblin"})
	var x0 := m.body.pos.x
	for i in 30:
		host.tick()
	t.check(m.body.pos.x > x0 + 5.0, "a host-simulated monster walks with its brain (%.1f tiles)" % (m.body.pos.x - x0))
	t.eq(brain.calls, 30, "brain thinks once per tick")
	t.eq(m.kind, HostEntity.Kind.MONSTER, "kind monster")
	t.check(m.flags & HostEntity.F_FLOOR != 0, "its flags are kept for snapshots")

func _saving(t: TestLog) -> void:
	var dir := OS.get_user_data_dir().path_join("test_world_host_save")
	_rm(dir)
	var host := WorldHost.new(TileWorld.make_test())
	var a := host.add_player("Ann/../x", 2)
	a.body.pos = Vector2(33.5, 64)
	host.add_player("bob", 3).body.pos = Vector2(90.5, 64)
	var called := [0]
	host.world_saver = func(_w: TileWorld, d: String) -> Error:
		called[0] += 1
		return OK if d == dir else FAILED
	t.eq(host.save(dir), OK, "save")
	t.eq(called[0], 1, "the world saver seam is called")
	t.check(FileAccess.file_exists(dir.path_join("players/Ann____x.json")), "player files are keyed by a file-safe name")
	var host2 := WorldHost.new(TileWorld.make_test())
	t.eq(host2.load_players(dir), 2, "two players loaded")
	t.eq(host2.add_player("Ann/../x", 5).body.pos, Vector2(33.5, 64), "ann comes back where she was")
	t.eq(host2.add_player("bob", 6).body.pos, Vector2(90.5, 64), "and bob")
	t.eq(WorldHost.new(TileWorld.make_test()).load_players(dir.path_join("nope")), 0, "a missing dir loads nothing")
	_rm(dir)

func _dice(t: TestLog) -> void:
	var h1 := WorldHost.new(TileWorld.make_test())
	var r1 := [Dice.roll_d20(), Dice.roll_d20(), Dice.roll_d20()]
	var h2 := WorldHost.new(TileWorld.make_test())
	var r2 := [Dice.roll_d20(), Dice.roll_d20(), Dice.roll_d20()]
	t.eq(r1, r2, "dice are seeded from the world seed")
	t.check(Dice.rng == h2.rng and h1.rng != h2.rng, "the newest host owns Dice.rng")

static func _rm(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_rm(dir.path_join(sub))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)

class WalkRight extends RefCounted:
	var calls := 0
	func think(_host: WorldHost, _e: HostEntity, _dt: float) -> PlayerInput:
		calls += 1
		var p := PlayerInput.new()
		p.move_x = 1.0
		return p
