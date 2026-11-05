## NetSession's host thread: the host keeps its fixed clock while the main thread is blocked,
## host_call runs on the host, halt_host stops it.
extends RefCounted

func run(t: TestLog) -> void:
	var s := NetSession.new()
	t.eq(s.start_host(TileWorld.make_test(256, 128), 0, ""), OK, "offline host starts")
	var seen := []
	s.host_call(func(h: WorldHost) -> void: seen.append(h.tick_count))
	s._process(0.0)                       # starts the thread
	var t0 := Time.get_ticks_msec()
	OS.delay_msec(500)                    # the "renderer" stalls for half a second
	var ticks: int = s.with_host(func() -> int: return s.host.tick_count)
	var expect := (Time.get_ticks_msec() - t0) * K.TICK_HZ / 1000.0
	t.check(ticks >= expect - 4 and ticks <= expect + 3, "host ticked on its own clock while the main thread slept (%d ticks, expected about %.0f)" % [ticks, expect])
	t.eq(seen, [0], "host_call ran once on the host, before a tick")
	s.halt_host()
	var after := s.host.tick_count
	OS.delay_msec(100)
	t.eq(s.host.tick_count, after, "halt_host stops ticking")
	s.stop()
	s.free()
