## The host's WorldSim: built from worldgen meta, follows the clock under a per-tick budget,
## its new chronicle lines reach clients, and it saves and restores exactly with the host.
extends RefCounted

const Rig := preload("res://tests/net_rig.gd")

func run(t: TestLog) -> void:
	var world := WorldGen.generate_named("dev", 3)
	var rig := Rig.new(world, 0.02)
	var host := rig.host
	t.check(host.sim != null, "a generated world gets a WorldSim")
	t.check(WorldHost.new(TileWorld.make_test(128, 64)).sim == null, "the test world (no sites) does not")
	var ann := rig.add_client("ann")
	rig.until(func() -> bool: return ann.cw != null and ann.cw.area_ready(), 5.0)
	rig.run(0.5)
	t.eq(host.sim.t, host.clock.whole_hours() - host.sim_origin, "sim hours follow game hours")
	# A year passes at once: the sim catches up a budget at a time, never all in one tick.
	host.sleep(24.0 * 360)
	var ticks := 0
	while host.sim_behind() > 0 and ticks < 5000:
		rig.frame()
		rig.frame()
		ticks += 1
	t.eq(host.sim_behind(), 0, "the sim catches up with the clock (%d host ticks for a year)" % ticks)
	t.check(ticks > 1, "over more than one tick")
	var mx := 0
	for u in host.sim_usec:
		mx = maxi(mx, u)
	t.check(mx < WorldHost.SIM_BUDGET_US + 25000, "no tick spends much past its budget (max %d us)" % mx)
	print("  sim catch-up: a year in %d host ticks, max %d us per tick, %d entries" % [ticks, mx, host.sim.chronicle.size()])
	rig.run(0.5)
	t.check(host.sim.chronicle.size() > 0, "history happened (%d entries)" % host.sim.chronicle.size())
	t.eq(host.chronicle_sent, host.sim.chronicle.size(), "every new entry was sent")
	t.check(ann.cw.chronicle.size() > 0, "the client received chronicle lines (%d)" % ann.cw.chronicle.size())
	t.eq(ann.cw.chronicle[-1], host.sim.describe(host.sim.chronicle[-1]), "the newest line is the host's newest entry")
	# A late joiner gets the last few lines, as history: nothing on the news feed.
	var bob := rig.add_client("bob")
	var fed := {"news": [], "old": []}
	bob.welcomed.connect(func(cw: ClientWorld) -> void:
		cw.chronicle_lines.connect(func(l: PackedStringArray) -> void: fed["news"].append_array(l))
		cw.chronicle_history.connect(func(l: PackedStringArray) -> void: fed["old"].append_array(l)))
	rig.until(func() -> bool: return bob.cw != null and bob.cw.area_ready(), 5.0)
	rig.run(0.2)
	t.eq(bob.cw.chronicle.size(), mini(WorldHost.CHRONICLE_ON_JOIN, host.sim.chronicle.size()), "a joiner is sent the recent history")
	t.eq((fed["news"] as Array).size(), 0, "none of it as news")
	t.eq((fed["old"] as Array).size(), bob.cw.chronicle.size(), "all of it as history")
	# What happens after arriving is news: to bob, and to ann.
	var ann_news := {"n": 0}
	ann.cw.chronicle_lines.connect(func(l: PackedStringArray) -> void: ann_news["n"] += l.size())
	var was := host.sim.chronicle.size()
	host.sim.log_event("raid_repelled", {"raiders": "dwarven", "rfrom": "Hazakdun", "site": "Clovergreen", "by": "defenders"})
	host.sleep(2.0)
	rig.run(0.5)
	t.check(host.sim.chronicle.size() > was, "something happens")
	t.check((fed["news"] as Array).size() >= 1, "and it reaches the feed of a player who was there (%d)" % (fed["news"] as Array).size())
	t.check(int(ann_news["n"]) >= 1, "of both")
	# A sim still catching up when a player arrives: its lines from before that are history.
	var cara := rig.add_client("cara")
	host.sleep(30.0 * 24.0)
	var fed_c := {"news": [], "old": []}
	cara.welcomed.connect(func(cw: ClientWorld) -> void:
		cw.chronicle_lines.connect(func(l: PackedStringArray) -> void: fed_c["news"].append_array(l))
		cw.chronicle_history.connect(func(l: PackedStringArray) -> void: fed_c["old"].append_array(l)))
	var guard := 0
	while host.sim_behind() > 0 and guard < 5000:
		rig.frame()
		guard += 1
	rig.run(0.3)
	print("  catching up as a player arrives: %d lines of history, %d of news" % [(fed_c["old"] as Array).size(), (fed_c["news"] as Array).size()])
	t.eq((fed_c["news"] as Array).size(), 0, "a sim catching up as a player arrives: none of it is news")

	# Exact save and restore: a restored host steps on to the same state as the original.
	var dir := OS.get_user_data_dir().path_join("test_host_sim")
	t.eq(host.save_state(dir), OK, "host state saves")
	var back := WorldHost.new(world)
	t.check(back.load_state(dir), "and loads")
	t.eq(var_to_bytes(back.sim.to_dict()), var_to_bytes(host.sim.to_dict()), "the restored sim is identical")
	t.eq(back.sim_origin, host.sim_origin, "with its origin")
	t.eq(back.clock.ticks, host.clock.ticks, "and the clock")
	host.sleep(24.0 * 10)
	back.sleep(24.0 * 10)
	for i in 400:
		host.tick()
		back.tick()
	t.eq(var_to_bytes(back.sim.to_dict()), var_to_bytes(host.sim.to_dict()), "and stays identical as both step on")
	for f in ["host.json", "sim.bin"]:
		DirAccess.remove_absolute(dir.path_join(f))
	t.eq(Protocol.decode(Protocol.chronicle(PackedStringArray(["old"]), true)).get("history"), true, "history is marked")
	var ok := Protocol.decode(Protocol.chronicle(PackedStringArray(["Year 1, spring: a thing", "é"])))
	t.eq(ok.get("lines"), PackedStringArray(["Year 1, spring: a thing", "é"]), "CHRONICLE round-trips")
	t.eq(Protocol.decode(Protocol.chronicle(PackedStringArray(["abc"])).slice(0, 4)), {}, "a short CHRONICLE is refused")

func _sent_lines(c: ClientEndpoint) -> int:
	return c.cw.chronicle.size()
