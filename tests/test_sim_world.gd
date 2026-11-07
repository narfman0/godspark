## from_meta on a worldgen-shaped strip (few sites), entities_near, party positions, tick cost.
extends RefCounted

func _meta() -> Dictionary:
	var sites := [
		{"id": 0, "kind": "settlement", "x": 120, "y": 600, "biome": "meadow", "band": "surface", "size": 3},
		{"id": 1, "kind": "lair", "x": 380, "y": 640, "biome": "forest", "band": "surface", "size": 2},
		{"id": 2, "kind": "settlement", "x": 600, "y": 610, "biome": "forest", "band": "surface", "size": 2},
		{"id": 3, "kind": "settlement", "x": 900, "y": 650, "biome": "hills", "band": "surface", "size": 2},
		{"id": 4, "kind": "portal", "x": 1100, "y": 700, "biome": "hills", "band": "surface", "size": 1},
		{"id": 5, "kind": "settlement", "x": 1350, "y": 620, "biome": "meadow", "band": "surface", "size": 3},
		{"id": 6, "kind": "lair", "x": 1600, "y": 660, "biome": "mountain", "band": "surface", "size": 2},
		{"id": 7, "kind": "settlement", "x": 1850, "y": 640, "biome": "desert", "band": "surface", "size": 2},
		{"id": 8, "kind": "settlement", "x": 700, "y": 200, "biome": "underdark", "band": "deeps", "size": 2},
		{"id": 9, "kind": "lair", "x": 1000, "y": 240, "biome": "caves", "band": "caves", "size": 1},
		{"id": 10, "kind": "settlement", "x": 1450, "y": 180, "biome": "underdark", "band": "deeps", "size": 2},
	]
	var routes := [
		{"id": 0, "a": 0, "b": 2, "kind": "road", "length": 560},
		{"id": 1, "a": 2, "b": 3, "kind": "road", "length": 340},
		{"id": 2, "a": 3, "b": 5, "kind": "road", "length": 520},
		{"id": 3, "a": 5, "b": 7, "kind": "road", "length": 560},
		{"id": 4, "a": 8, "b": 10, "kind": "deep_road", "length": 900},
		{"id": 5, "a": 8, "b": 2, "kind": "deep_road", "length": 520},
		{"id": 6, "a": 9, "b": 10, "kind": "deep_road", "length": 520},
	]
	var surface: Array = []
	surface.resize(2048)
	return {"surface": surface, "sites": sites, "routes": routes}

func run(t: TestLog) -> void:
	var sim := WorldSim.from_meta(_meta(), 3)
	t.check(sim.settlements.size() >= 3, "a small worldgen strip is settled (%d)" % sim.settlements.size())
	t.check(sim.routes.size() >= 7, "unrouted sites get trails (%d routes)" % sim.routes.size())
	var bad: Array[String] = []
	var max_pop := 0
	for y in 60:
		sim.step(WorldSim.YEAR_H)
		bad.append_array(sim.audit())
		max_pop = maxi(max_pop, sim.total_pop())
		if y == 30:
			# Positions of parties are recoverable as (route, fraction).
			for pid in sim.parties:
				var p: SimParty = sim.parties[pid]
				var pos := sim.party_position(p)
				t.check(pos.route == -1 or (sim.route_by_id.has(pos.route) and pos.frac >= 0.0 and pos.frac <= 1.0),
					"party %d has a valid position" % p.id)
	t.check(bad.is_empty(), "no negative stocks or people on a small strip (%s)" % [bad.slice(0, 3)])
	t.check(sim.total_pop() > 0, "the small strip still has people after 60 years")
	t.check(max_pop < 60000, "no runaway growth")
	t.check(int(sim.stats.get("caravans_arrived", 0)) > 0, "caravans trade on a small strip")
	var near := sim.entities_near(0, 700)
	var all := sim.entities_near(-1e9, 1e9)
	t.check(all.settlements.size() == sim.settlements.size() and all.lairs.size() == sim.lairs.size()
		and all.parties.size() == sim.parties.size(), "entities_near over everything returns everything")
	for s in near.settlements:
		t.check(s.x >= 0 and s.x <= 700, "settlement %s lies in range" % s.name)
	# Tick cost: a world with about 100 settlements, averaged over a simulated year.
	# The best of three: other processes run beside this one (tools/test.sh, JOBS files at once),
	# and the machine's real cost is the sample they disturbed least.
	var big := WorldSim.synthetic(200, 1)
	var ms_day := INF
	for rep in 3:
		big = WorldSim.synthetic(200, 1)
		var t0 := Time.get_ticks_usec()
		big.step(WorldSim.YEAR_H)
		ms_day = minf(ms_day, (Time.get_ticks_usec() - t0) / 1000.0 / WorldSim.YEAR_DAYS)
	print("  %d settlements: %.3f ms per simulated day" % [big.settlements.size(), ms_day])
	t.check(ms_day < 4.0, "strategic day for ~100 settlements under 4 ms (%.2f ms; target 2)" % ms_day)
