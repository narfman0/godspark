## Host + clients over in-process queues with 50 ms latency: join, streaming, edits, interest
## filtering, corrections, late join, disconnects. No sockets.
extends RefCounted

const Rig := preload("res://tests/net_rig.gd")

func run(t: TestLog) -> void:
	var world := TileWorld.make_test(1024, 128)
	var rig := Rig.new(world, 0.05)
	var mid := world.width / 2
	var ground := world.height / 2
	var ann := rig.add_client("ann")
	var bob := rig.add_client("bob")
	var took := rig.until(func() -> bool: return ann.cw != null and bob.cw != null and ann.cw.area_ready() and bob.cw.area_ready(), 5.0)
	t.check(took >= 0.0, "both clients receive their initial area (%.2f s simulated at 50 ms latency)" % took)
	t.eq(ann.cw.loaded.size(), 20, "a 5x5 chunk interest area, clipped to the 4-chunk-tall world")
	t.check(rig.in_sync(0) and rig.in_sync(1), "both partial worlds match the host")
	rig.run(0.3)
	t.check(ann.cw.remotes.has(bob.cw.my_id) and bob.cw.remotes.has(ann.cw.my_id), "nearby players see each other")

	# ann digs the grass under bob's right foot: both see it
	var tx := mid + 1
	rig.inputs[0].dig = true
	rig.inputs[0].target = Vector2i(tx, ground - 1)
	var dug := rig.until(func() -> bool: return bob.cw.world.get_fg(tx, ground - 1) == TileDefs.AIR, 3.0)
	t.check(dug >= 0.4, "the dig takes its time and then reaches the other client (%.2f s)" % dug)
	t.eq(ann.cw.world.get_fg(tx, ground - 1), TileDefs.AIR, "and the digger")
	rig.inputs[0].dig = false
	# then places a block
	rig.inputs[0].place = true
	rig.inputs[0].place_tile = TileDefs.id("wood")
	rig.inputs[0].target = Vector2i(mid - 2, ground)
	var placed := rig.until(func() -> bool: return bob.cw.world.get_fg(mid - 2, ground) == TileDefs.id("wood"), 2.0)
	t.check(placed >= 0.0, "a placed block reaches the other client")
	rig.inputs[0].place = false
	rig.run(0.2)
	t.check(rig.in_sync(0) and rig.in_sync(1), "still in sync after edits")

	# interest: carl joins five chunks to the right, out of range
	rig.host.records["carl"] = {"name": "carl", "pos": [mid + 160.5, ground]}
	var carl := rig.add_client("carl")
	t.check(rig.until(func() -> bool: return carl.cw != null and carl.cw.area_ready(), 5.0) >= 0.0, "carl gets his own area far away")
	t.eq(carl.cw.body.pos, Vector2(mid + 160.5, ground), "carl spawns at his record")
	var far_tiles := _count(carl, Protocol.T.TILES)
	rig.inputs[0].dig = true
	rig.inputs[0].target = Vector2i(mid - 1, ground - 1)
	rig.until(func() -> bool: return ann.cw.world.get_fg(mid - 1, ground - 1) == TileDefs.AIR, 3.0)
	rig.inputs[0].dig = false
	rig.run(0.3)
	t.eq(_count(carl, Protocol.T.TILES), far_tiles, "a far player's edit is not sent to carl")
	t.check(not carl.cw.has_chunk(mid >> 5, (ground - 1) >> 5), "carl does not hold ann's chunk")
	t.check(not carl.cw.remotes.has(ann.cw.my_id), "nor see ann")
	t.check(not ann.cw.remotes.has(carl.cw.my_id), "nor ann him")
	# carl walks to the others
	rig.inputs[2].move_x = -1.0
	var met := rig.until(func() -> bool: return carl.cw.remotes.has(ann.cw.my_id) and carl.cw.has_chunk(mid >> 5, (ground - 1) >> 5), 15.0)
	t.check(met >= 0.0, "walking over, carl gets ann's chunk and sees her (%.1f s)" % met)
	rig.inputs[2].move_x = 0.0
	rig.run(0.3)
	t.eq(carl.cw.world.get_fg(mid - 1, ground - 1), TileDefs.AIR, "with ann's earlier edit in it")
	t.check(_count(carl, Protocol.T.UNLOAD) > 0, "and the chunks he left behind were unloaded")
	t.check(rig.in_sync(2), "carl in sync")
	t.eq(carl.cw.corrections, 0, "honest walking is never corrected")

	# a cheating client teleports and is put back
	var before := ann.cw.body.pos
	ann.cw.body.pos += Vector2(60, 10)
	var fixed := rig.until(func() -> bool: return ann.cw.corrections > 0, 1.0)
	t.check(fixed >= 0.0, "a teleport is corrected within a round trip (%.2f s)" % fixed)
	t.check(ann.cw.body.pos.distance_to(before) < 1.0, "back where the host last saw it")
	rig.run(0.5)
	t.eq(ann.cw.corrections, 1, "and only once")
	t.check(rig.host_entity(0).body.pos.distance_to(ann.cw.body.pos) < 0.5, "host and client agree again")

	# late join after edits
	var dave := rig.add_client("dave")
	t.check(rig.until(func() -> bool: return dave.cw != null and dave.cw.area_ready(), 5.0) >= 0.0, "dave joins late")
	t.eq(dave.cw.world.get_fg(tx, ground - 1), TileDefs.AIR, "and receives the dug tile")
	t.eq(dave.cw.world.get_fg(mid - 2, ground), TileDefs.id("wood"), "and the placed block")
	t.check(rig.in_sync(3), "dave in sync")

	# a fifth is refused, and a taken name too
	var eve := rig.add_client("eve")
	var refused := [-1]
	eve.rejected.connect(func(r: int, _s: String) -> void: refused[0] = r)
	var ann2 := rig.add_client("ann")
	var refused2 := [-1]
	ann2.rejected.connect(func(r: int, _s: String) -> void: refused2[0] = r)
	rig.run(0.3)
	t.eq(refused[0], Protocol.Why.FULL, "a fifth player is refused: full")
	t.eq(refused2[0], Protocol.Why.NAME_TAKEN, "a second ann is refused: name taken")

	# bob drops without a word; dave leaves cleanly
	var bob_id := bob.cw.my_id
	rig.cut(1)
	rig.run(0.3)
	t.check(not ann.cw.remotes.has(bob_id), "a dropped player disappears for the others")
	t.check(rig.host.entity(bob_id) == null, "and from the host")
	t.check(rig.host.records.has("bob"), "his position is kept")
	var dave_id := dave.cw.my_id
	dave.leave()
	rig.run(0.3)
	t.check(rig.host.entity(dave_id) == null and not ann.cw.remotes.has(dave_id), "a clean leave removes the player")
	t.eq(rig.ep.playing_count(), 2, "two left playing")

	# a peer that never says hello is dropped
	var mute := rig.hub.transport(50)
	rig.hub.join(50)
	rig.run(5.5)
	var mute_gone := false
	for ev: Array in mute.poll():
		mute_gone = mute_gone or ev[0] == NetTransport.DISCONNECT
	t.check(mute_gone and not rig.ep.peers.has(50), "a silent peer is dropped after the handshake timeout")

	# version mismatch
	var old := rig.hub.transport(51)
	rig.hub.join(51)
	rig.run(0.1)
	old.poll()
	var bad := Protocol.hello("old")
	bad.encode_u16(5, Protocol.VERSION + 1)
	old.send(NetTransport.SERVER, bad, true)
	rig.run(0.2)
	var why := -1
	for ev: Array in old.poll():
		if ev[0] == NetTransport.PACKET:
			var m := Protocol.decode(ev[2])
			if m.get("type") == Protocol.T.REJECT:
				why = m["reason"]
	t.eq(why, Protocol.Why.VERSION, "a different protocol version is refused")

	rig.run(0.5)
	t.check(rig.in_sync(0) and rig.in_sync(2), "the remaining clients end in sync with the host")
	t.eq(ann.cw.loaded_hash(), rig.host_hash_for(0), "identical digests")

func _count(c: ClientEndpoint, type: int) -> int:
	var row: Array = c.received_by_type.get(type, [0, 0])
	return row[0]
