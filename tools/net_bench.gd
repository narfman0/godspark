## Net measurements: chunk blob sizes, 4-player host tick cost and bandwidth over loopback,
## and time to the initial area over real ENet on localhost.
##   godot --headless -s res://tools/net_bench.gd [-- seconds=20]
## Until Track A's worldgen lands, "noisy" is a stand-in: noise caves, ore specks, dirt
## and stone bands, background walls, some water.
extends SceneTree

const Rig := preload("res://tests/net_rig.gd")

func _initialize() -> void:
	var opts := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			opts[kv[0]] = kv[1]
	var seconds := float(opts.get("seconds", 20))
	_chunk_sizes()
	_four_players(seconds)
	_enet_join()
	quit(0)

static func noisy_world(w: int, h: int, seed_value: int) -> TileWorld:
	var world := TileWorld.new(w, h, seed_value)
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = 0.04
	var hn := FastNoiseLite.new()
	hn.seed = seed_value + 1
	hn.frequency = 0.01
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var stone := TileDefs.id("stone")
	var dirt := TileDefs.id("dirt")
	var grass := TileDefs.id("grass")
	for x in w:
		var top := int(h * 0.6 + hn.get_noise_1d(x) * 20.0)
		for y in mini(top, h):
			var id := stone if y < top - 6 else (grass if y == top - 1 else dirt)
			if y < top - 8 and n.get_noise_2d(x, y) > 0.35:
				id = TileDefs.AIR
				if y < h * 0.3 and rng.randf() < 0.3:
					world.set_liquid(x, y, 15, true)
			elif id == stone and rng.randf() < 0.03:
				id = TileDefs.id("wood")     # stands in for ore
			world.set_fg(x, y, id, true)
			world.set_bg(x, y, 2 if y < top - 6 else 1, true)
	return world

func _chunk_sizes() -> void:
	var test := TileWorld.make_test(1024, 256)
	var noisy := noisy_world(1024, 256, 7)
	print("== chunk blob sizes (Chunk.to_bytes, zstd; raw is 4096 bytes)")
	for pair: Array in [["make_test", test], ["noisy", noisy]]:
		var w: TileWorld = pair[1]
		var sizes := PackedInt32Array()
		var t0 := Time.get_ticks_usec()
		for cy in w.chunks_y:
			for cx in w.chunks_x:
				sizes.append(w.chunk_at(cx, cy).to_bytes().size())
		var us := float(Time.get_ticks_usec() - t0) / sizes.size()
		sizes.sort()
		var sum := 0
		for s in sizes:
			sum += s
		print("  %-9s %d chunks: min %d, median %d, mean %.0f, p95 %d, max %d bytes; encode %.1f us/chunk" % [pair[0],
				sizes.size(), sizes[0], sizes[sizes.size() / 2], float(sum) / sizes.size(), sizes[int(sizes.size() * 0.95)], sizes[-1], us])
	# the band players actually stand in: surface +- 2 chunks
	var band := PackedInt32Array()
	for cy in range(3, 7):
		for cx in noisy.chunks_x:
			band.append(noisy.chunk_at(cx, cy).to_bytes().size())
	var bs := 0
	for s in band:
		bs += s
	print("  noisy, rows 3-6 (surface and caves): mean %.0f bytes" % (float(bs) / band.size()))

func _four_players(seconds: float) -> void:
	print("== 4 players over loopback (50 ms latency), %.0f s simulated, noisy 1024x256 world" % seconds)
	var rig := Rig.new(noisy_world(1024, 256, 7), 0.05)
	var dirs := [1.0, -1.0, 1.0, -1.0]
	for i in 4:
		rig.add_client("p%d" % i)
	rig.until(func() -> bool:
		for c in rig.clients:
			if c.cw == null or not c.cw.area_ready():
				return false
		return true, 10.0)
	var area := []
	for c in rig.clients:
		area.append("%.0f" % (c.area_at * 1000.0))
	print("  initial area (simulated, 50 ms one way): %s ms" % ", ".join(area))
	rig.ep.tick_usec.clear()
	var snap0 := []
	var down0 := []
	for i in 4:
		var p: HostEndpoint.PeerState = rig.ep.peers[rig.ids[i]]
		snap0.append(p.snapshot_bytes)
		down0.append(p.bytes_out)
	var up0 := 0
	for c in rig.clients:
		up0 += c.transport.bytes_out
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var frames := roundi(seconds * 60.0)
	for f in frames:
		for i in 4:
			var inp := rig.inputs[i]
			# wander: mostly run, turn now and then, jump, dig what is in front
			if rng.randf() < 0.01:
				dirs[i] = -dirs[i]
			inp.move_x = dirs[i] if f % 240 < 200 else 0.0
			inp.jump = rng.randf() < 0.05 or (rig.cw(i).body.on_wall)
			inp.jump_pressed = inp.jump
			var b := rig.cw(i).body
			inp.dig = f % 240 >= 200
			inp.target = Vector2i(floori(b.pos.x + 2 * dirs[i]), floori(b.pos.y) - 1)
		rig.frame()
	var ticks := rig.ep.tick_usec
	var sorted := ticks.duplicate()
	sorted.sort()
	var sum := 0
	for u in ticks:
		sum += u
	print("  host tick (HostEndpoint.tick incl. WorldHost): mean %.0f us, median %d, p99 %d, max %d over %d ticks" % [
			float(sum) / ticks.size(), sorted[sorted.size() / 2], sorted[int(sorted.size() * 0.99)], sorted[-1], ticks.size()])
	for i in 4:
		var p: HostEndpoint.PeerState = rig.ep.peers[rig.ids[i]]
		print("  p%d: snapshots %.0f B/s, all host->client %.0f B/s, sees %d remotes, %d chunks sent total, corrections %d, at %s" % [i,
				(p.snapshot_bytes - snap0[i]) / seconds, (p.bytes_out - down0[i]) / seconds, rig.cw(i).remotes.size(),
				p.chunks_sent, rig.cw(i).corrections, rig.cw(i).body.pos.round()])
	var up := 0
	for c in rig.clients:
		up += c.transport.bytes_out
	print("  client->host: %.0f B/s per player" % ((up - up0) / seconds / 4.0))
	var ok := true
	for i in 4:
		ok = ok and rig.in_sync(i)
	print("  all four in sync with the host: %s" % ok)
	print("  traffic:\n" + rig.ep.traffic_report())

func _enet_join() -> void:
	print("== join over real ENet on localhost, noisy 1024x256 world")
	var host := WorldHost.new(noisy_world(1024, 256, 7))
	var server := EnetTransport.new()
	var port := 0
	for p in range(41000, 41020):
		if server.listen(p, 4, "127.0.0.1") == OK:
			port = p
			break
	var ep := HostEndpoint.new(host, server)
	var ct := EnetTransport.new()
	ct.connect_to("127.0.0.1", port)
	var client := ClientEndpoint.new(ct, "ann")
	var inp := PlayerInput.new()
	var acc := 0.0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 5000:
		OS.delay_usec(2000)
		var dt := 0.002
		acc += dt
		while acc >= 1.0 / K.TICK_HZ:
			acc -= 1.0 / K.TICK_HZ
			ep.tick()
		client.frame(dt, inp)
		if client.area_at > 0.0:
			break
	var bytes := 0
	var row: Array = client.received_by_type.get(Protocol.T.CHUNK, [0, 0])
	bytes = row[1]
	print("  welcome after %.0f ms, %d chunks (radius %d) after %.0f ms; %d chunk messages, %d bytes" % [
			client.welcome_at * 1000.0, client.cw.loaded.size() if client.cw else 0, ep.radius, client.area_at * 1000.0, row[0], bytes])
	client.leave()
	server.close()
