## Predicted digs and places on the client, rollback, and correction smoothing. Loopback at
## 100 ms one-way latency; every case ends with the clients' digests equal to the host's.
extends RefCounted

const Rig := preload("res://tests/net_rig.gd")

func run(t: TestLog) -> void:
	_loopback(t)
	_timeout(t)
	_smoothing(t)

func _loopback(t: TestLog) -> void:
	var world := TileWorld.make_test(512, 128)
	var rig := Rig.new(world, 0.1)
	var mid := world.width / 2
	var g := world.height / 2
	var wood := TileDefs.id("wood")
	var ann := rig.add_client("ann")
	var bob := rig.add_client("bob")
	rig.until(func() -> bool: return ann.cw != null and bob.cw != null and ann.cw.area_ready() and bob.cw.area_ready(), 5.0)
	rig.run(0.5)

	# A place shows at once for the placer and a round trip later for the other.
	var at := Vector2i(mid - 3, g)
	rig.inputs[0].place = true
	rig.inputs[0].place_tile = wood
	rig.inputs[0].target = at
	rig.frame()
	rig.inputs[0].place = false
	t.eq(ann.cw.world.get_fg(at.x, at.y), wood, "a place is shown on the placer's next frame")
	t.eq(bob.cw.world.get_fg(at.x, at.y), TileDefs.AIR, "not yet on the other client")
	var seen := rig.until(func() -> bool: return bob.cw.world.get_fg(at.x, at.y) == wood, 1.0)
	t.check(seen >= 0.15, "the other sees it about a round trip later (%.2f s)" % seen)
	rig.run(0.3)
	t.eq(ann.cw.pending_count(), 0, "the prediction is settled by the host's answer")
	t.check(rig.in_sync(0) and rig.in_sync(1), "in sync after a predicted place")

	# A dig is shown when the digger's own clock says it is done, before the host's word.
	var d := Vector2i(mid - 4, g - 1)
	rig.inputs[0].dig = true
	rig.inputs[0].target = d
	var local := rig.until(func() -> bool: return ann.cw.world.get_fg(d.x, d.y) == TileDefs.AIR, 2.0)
	var host_has := rig.host.world.get_fg(d.x, d.y)
	t.check(local >= 0.38 and local <= 0.45, "the digger sees the dig at its dig time (%.2f s)" % local)
	t.check(host_has != TileDefs.AIR, "before the host has finished it")
	rig.inputs[0].dig = false
	rig.run(0.5)
	t.eq(ann.cw.world.get_fg(d.x, d.y), TileDefs.AIR, "the host agrees")
	t.check(rig.in_sync(0) and rig.in_sync(1), "in sync after a predicted dig")

	# A predicted place the host refuses (a solid block where bob stands: ann's client only
	# checks her own body) is rolled back.
	rig.inputs[1].move_x = 1.0                             # bob steps a few tiles away
	rig.run(0.2)
	rig.inputs[1].move_x = 0.0
	rig.run(0.5)
	var bf := Vector2i(floori(rig.host_entity(1).body.pos.x), g)
	rig.inputs[0].place = true
	rig.inputs[0].target = bf
	rig.frame()
	rig.inputs[0].place = false
	var shown := ann.cw.world.get_fg(bf.x, bf.y)
	rig.run(0.5)
	t.eq(shown, wood, "a block placed on bob is shown at first")
	t.eq(ann.cw.world.get_fg(bf.x, bf.y), TileDefs.AIR, "and taken back when the host refuses it")
	t.eq(ann.cw.rolled_back, 1, "one rollback")
	t.check(rig.in_sync(0), "in sync after the rollback")

	# A predicted dig that the host then refuses: the tile became bedrock on the host while
	# ann's prediction was in flight. The delta arrives while the cell is pending, the result
	# refuses the dig, and ann ends up with the host's bedrock.
	var r := Vector2i(mid - 5, g - 1)
	rig.inputs[0].dig = true
	rig.inputs[0].target = r
	rig.until(func() -> bool: return ann.cw.world.get_fg(r.x, r.y) == TileDefs.AIR, 2.0)
	rig.inputs[0].dig = false
	t.check(rig.host.world.get_fg(r.x, r.y) != TileDefs.AIR and ann.cw.pending_count() == 1, "ann predicted a dig the host has not finished")
	rig.host.world.set_fg(r.x, r.y, TileDefs.id("bedrock"))
	rig.frame()
	t.eq(ann.cw.world.get_fg(r.x, r.y), TileDefs.AIR, "a host delta does not overwrite a pending prediction")
	rig.run(0.6)
	t.eq(ann.cw.world.get_fg(r.x, r.y), TileDefs.id("bedrock"), "the refused dig settles to the host's tile")
	t.eq(ann.cw.rolled_back, 2, "a second rollback")
	t.check(rig.in_sync(0) and rig.in_sync(1), "in sync after a refused dig")

	# Both dig the same tile at once: one wins, the other is told NOTHING_THERE; both end
	# with it dug and nothing applied twice.
	var s := Vector2i(mid, g - 2)
	rig.host.world.set_fg(s.x, s.y + 1, TileDefs.AIR)      # open it from above for both
	rig.run(0.3)
	var reasons := []
	ann.cw.edit_result.connect(func(_q: int, why: int, a: Vector2i, _k: int) -> void:
		if a == s:
			reasons.append(why))
	bob.cw.edit_result.connect(func(_q: int, why: int, a: Vector2i, _k: int) -> void:
		if a == s:
			reasons.append(why))
	for i in 2:
		rig.inputs[i].dig = true
		rig.inputs[i].target = s
	rig.run(1.2)
	for i in 2:
		rig.inputs[i].dig = false
	rig.run(0.4)
	reasons.sort()
	t.eq(reasons, [WorldHost.Reason.OK, WorldHost.Reason.NOTHING_THERE], "one dig wins, the other finds nothing there")
	t.eq(rig.host.world.get_fg(s.x, s.y), TileDefs.AIR, "the tile is dug on the host")
	t.eq(ann.cw.pending_count() + bob.cw.pending_count(), 0, "no prediction left open")
	t.check(rig.in_sync(0) and rig.in_sync(1), "both in sync after digging the same tile")
	t.eq(ann.cw.loaded_hash(), rig.host_hash_for(0), "identical digests (ann)")
	t.eq(bob.cw.loaded_hash(), rig.host_hash_for(1), "identical digests (bob)")

## No answer at all (lost link): a prediction is rolled back after PREDICT_TIMEOUT, and a
## delta that arrived meanwhile is what it rolls back to.
func _timeout(t: TestLog) -> void:
	var src := TileWorld.make_test()
	var cw := ClientWorld.new()
	var spawn := Vector2(src.width / 2 + 0.5, src.height / 2)
	cw.setup(src.width, src.height, 1, 1, "ann", spawn, 0, 2)
	for c in Interest.around(src, Interest.chunk_of(cw.body.center()), 2):
		cw.apply_chunk(c.x, c.y, src.chunk_at(c.x, c.y).to_bytes())
	var inp := PlayerInput.new()
	var at := Vector2i(int(spawn.x) - 3, int(spawn.y))
	inp.place = true
	inp.place_tile = TileDefs.id("wood")
	inp.target = at
	var reqs := cw.step(inp)
	t.eq(reqs.size(), 1, "the place is sent")
	t.eq(cw.world.get_fg(at.x, at.y), TileDefs.id("wood"), "and shown")
	cw.apply_tile(at.x, at.y, TileWorld.Layer.FG, TileDefs.id("stone"))
	t.eq(cw.world.get_fg(at.x, at.y), TileDefs.id("wood"), "a delta for the cell is held back")
	inp.place = false
	for i in roundi(ClientWorld.PREDICT_TIMEOUT * 60) + 2:
		cw.step(inp)
	t.eq(cw.world.get_fg(at.x, at.y), TileDefs.id("stone"), "after the timeout the cell shows the host's value")
	t.eq(cw.pending_count(), 0, "and nothing is pending")

## Host corrections: the body snaps, the drawn position blends over a few frames.
func _smoothing(t: TestLog) -> void:
	var cw := ClientWorld.new()
	cw.setup(256, 128, 1, 1, "ann", Vector2(100.5, 64), 0, 2)
	var moved := []
	cw.actor_moved.connect(func(_id: int, pos: Vector2, _f: int, _s: String) -> void: moved.append(pos))
	cw.body.pos = Vector2(103.5, 64)
	cw.apply_correction(1, Vector2(100.5, 64), Vector2.ZERO)
	t.eq(cw.body.pos, Vector2(100.5, 64), "the simulated body snaps")
	cw.present()
	t.check(moved[-1].distance_to(Vector2(103.5, 64)) < 0.01, "the picture starts where it was")
	for i in 3:
		cw.advance(1.0 / 60.0)
	cw.present()
	t.check(moved[-1].x > 100.6 and moved[-1].x < 103.0, "and blends over a few frames (%.2f)" % moved[-1].x)
	for i in 15:
		cw.advance(1.0 / 60.0)
	cw.present()
	t.eq(moved[-1], Vector2(100.5, 64), "and lands on the body within 0.3 s")
	cw.body.pos = Vector2(200.5, 64)
	cw.apply_correction(2, Vector2(100.5, 64), Vector2.ZERO)
	t.eq(cw.view_pos(), Vector2(100.5, 64), "a long jump is not blended")
