## The world clock: day length, sun curve (night is SRD Darkness on open ground), saving
## with the host, and clients mirroring it over the protocol.
extends RefCounted

const Rig := preload("res://tests/net_rig.gd")

func run(t: TestLog) -> void:
	var c := WorldClock.new()
	t.eq(c.hour_of_day(), 8.0, "a new world starts at 08:00")
	t.eq(WorldClock.TICKS_PER_HOUR * WorldClock.HOURS_PER_DAY, K.DAY_SECONDS * K.TICK_HZ, "a day is K.DAY_SECONDS of host ticks")
	c.advance(WorldClock.TICKS_PER_HOUR * 4)
	t.eq(c.hour_of_day(), 12.0, "advance counts ticks")
	c.sleep(14.5)
	t.eq(c.day(), 1, "sleeping past midnight is the next day")
	t.eq(WorldClock.describe(c.hours()), "Day 1, 02:30", "describe")
	t.eq(WorldClock.sun_at(12.0), 1.0, "noon is full sun")
	t.eq(WorldClock.sun_at(0.0), WorldClock.MOON, "midnight is moonlight")
	var night_level := roundi(LightEngine.SUN * WorldClock.MOON)
	t.eq(LightEngine.category_of(night_level), LightEngine.Category.DARK, "open ground at night is Darkness for the rules (level %d)" % night_level)
	t.eq(LightEngine.category_of(roundi(LightEngine.SUN * WorldClock.sun_at(7.0))), LightEngine.Category.BRIGHT, "bright after dawn")
	var smooth := true
	var prev := WorldClock.sun_at(0.0)
	for i in 24 * 60:
		var s := WorldClock.sun_at(i / 60.0)
		smooth = smooth and absf(s - prev) < 0.02
		prev = s
	t.check(smooth, "the sun changes by under 2% per game minute")

	# saved and restored with the host
	var dir := OS.get_user_data_dir().path_join("test_clock")
	var host := WorldHost.new(TileWorld.make_test(128, 64))
	host.sleep(30.25)
	t.check(host.clock_jumped, "a sleep is flagged for the net layer")
	t.eq(host.save(dir), OK, "host saves")
	var back := WorldHost.new(TileWorld.make_test(128, 64))
	t.check(back.load_state(dir), "and loads its state")
	t.eq(back.clock.ticks, host.clock.ticks, "the clock round-trips exactly")
	DirAccess.remove_absolute(dir.path_join("host.json"))
	t.eq(Protocol.decode(Protocol.clock(123456789012)).get("ticks"), 123456789012, "CLOCK round-trips")
	t.eq(Protocol.decode(Protocol.clock(5).slice(0, 5)), {}, "a short CLOCK is refused")

	# clients mirror it
	var rig := Rig.new(TileWorld.make_test(256, 128), 0.05)
	var ann := rig.add_client("ann")
	rig.until(func() -> bool: return ann.cw != null and ann.cw.area_ready(), 5.0)
	rig.run(2.0)
	var diff := absf(ann.cw.hours() - rig.host.clock.hours()) * WorldClock.TICKS_PER_HOUR
	t.check(diff < 4.0, "a client's clock follows the host's (%.1f ticks apart, 50 ms latency)" % diff)
	rig.host.sleep(10.0)
	rig.run(0.3)
	diff = absf(ann.cw.hours() - rig.host.clock.hours()) * WorldClock.TICKS_PER_HOUR
	t.check(diff < 4.0, "and jumps with it at once (%.1f ticks apart)" % diff)
