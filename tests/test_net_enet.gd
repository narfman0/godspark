## A real ENet host and client inside this process, on localhost: handshake, initial area,
## a dig, a check, a clean leave. Wall-clock driven (a few hundred ms).
extends RefCounted

func run(t: TestLog) -> void:
	var host := WorldHost.new(TileWorld.make_test(512, 128))
	var server := EnetTransport.new()
	var port := 0
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 8:
		var p := rng.randi_range(30000, 60000)
		if server.listen(p, 4, "127.0.0.1") == OK:
			port = p
			break
	t.check(port != 0, "ENet server listens on localhost")
	if port == 0:
		return
	var ep := HostEndpoint.new(host, server)
	var ct := EnetTransport.new()
	t.eq(ct.connect_to("127.0.0.1", port), OK, "client connects")
	var client := ClientEndpoint.new(ct, "ann")
	var inp := PlayerInput.new()
	var clock := [0.0, 0.0]   # host accumulator, elapsed
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

	t.check(until.call(func() -> bool: return client.cw != null and client.cw.area_ready(), 5.0),
			"welcome and the initial area arrive over ENet (%.0f ms to area)" % (client.area_at * 1000.0))
	var cw := client.cw
	var x := int(cw.body.pos.x)
	var gy := 63
	inp.dig = true
	inp.target = Vector2i(x + 1, gy)
	t.check(until.call(func() -> bool: return cw.world.get_fg(x + 1, gy) == TileDefs.AIR, 3.0), "a dig completes and comes back")
	inp.dig = false
	t.eq(host.world.get_fg(x + 1, gy), TileDefs.AIR, "on the host too")
	var got := []
	client.check_result.connect(func(tag: String, ok: bool, _line: String) -> void: got.append([tag, ok]))
	client.request_check("enet")
	t.check(until.call(func() -> bool: return not got.is_empty(), 2.0), "check answered")
	t.eq(got, [["enet", true]], "the client's chunks match the host's")
	t.check(until.call(func() -> bool: return host.entity(cw.my_id) != null and host.entity(cw.my_id).states_accepted > 10, 2.0),
			"position updates arrive and are accepted")
	client.leave()
	t.check(until.call(func() -> bool: return ep.playing_count() == 0, 2.0), "a clean leave reaches the host")
	t.check(host.records.has("ann"), "and her record is kept")
	server.close()
