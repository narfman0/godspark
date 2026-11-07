## Raids from below (docs/tracks/raids-below.md): a deep city plans raids on the surface roads it
## reaches by a way up, the richest and the barrier roads first; the raid waits on the road,
## takes a caravan and carries the goods home into its city's books; the raided town posts guards
## at the way and its patron offers a bounty naming the way down and the city. On screen: the raid
## climbs the way as the city's raiders, scouts, mages and priests, the guards stand at the mouth,
## and two players see the same people.
extends RefCounted

const PB := preload("res://tests/test_peoples_below.gd")

func run(t: TestLog) -> void:
	_planning(t)
	_no_way(t)
	_goods_home(t)
	_answer(t)
	_watch_fights(t)
	_save(t)
	_on_screen(t)

## Three surface towns on a road with a pass between the second and third, a drow city below
## with a way up to the middle town, and a duergar hold beside it.
static func world(seed: int) -> Dictionary:
	var sites := [
		{"id": 0, "kind": "settlement", "x": 300, "y": 700, "biome": "meadow", "band": "surface", "size": 3},
		{"id": 1, "kind": "settlement", "x": 900, "y": 700, "biome": "meadow", "band": "surface", "size": 3},
		{"id": 2, "kind": "settlement", "x": 1500, "y": 700, "biome": "desert", "band": "surface", "size": 3},
		{"id": 3, "kind": "settlement", "x": 950, "y": 150, "biome": "fungal", "band": "deeps", "size": 3},
		{"id": 4, "kind": "settlement", "x": 1400, "y": 150, "biome": "crystal", "band": "deeps", "size": 3}]
	var routes := [{"id": 0, "a": 0, "b": 1, "kind": "road", "length": 620},
		{"id": 1, "a": 1, "b": 2, "kind": "road", "length": 700},
		{"id": 2, "a": 3, "b": 1, "kind": "deep_road", "length": 700},
		{"id": 3, "a": 3, "b": 4, "kind": "deep_road", "length": 460}]
	var barriers := {"ranges": [{"x0": 1150, "x1": 1250}], "rivers": []}
	var sim := WorldSim.new()
	sim._setup(sites, routes, seed, 1800.0, barriers)
	sim.settlements.clear()
	sim.factions.clear()
	var fa := sim._new_faction("human")
	var fb := sim._new_faction("human")
	var fc := sim._new_faction("dragonborn")
	var fd := sim._new_faction("drow")
	var fg := sim._new_faction("duergar")
	for f: SimFaction in [fa, fb, fc, fg]:
		f.temperament = "trader"
	fd.temperament = "raider"
	var towns: Array = [sim._new_settlement(0, "human", fa.id, 900), sim._new_settlement(1, "human", fb.id, 900),
		sim._new_settlement(2, "dragonborn", fc.id, 900)]
	var city := sim._new_settlement(3, "drow", fd.id, 1200)
	var hold := sim._new_settlement(4, "duergar", fg.id, 800)
	var all: Array = [fa, fb, fc, fd, fg]
	for i in all.size():
		(all[i] as SimFaction).capital = [0, 1, 2, 3, 4][i]
		for g: SimFaction in all:
			if all[i] != g:
				(all[i] as SimFaction).relations[g.id] = sim._base_relation(all[i], g)
	return {"sim": sim, "towns": towns, "city": city, "hold": hold}

## Coin sent along a road by a faction, as caravans leave it (SimEconomy._mark_traffic).
static func trade(sim: WorldSim, rid: int, fid: int, coin: float, trips: float) -> void:
	if not sim.route_value.has(rid):
		sim.route_value[rid] = {}
		sim.route_traffic[rid] = {}
	sim.route_value[rid][fid] = coin
	sim.route_traffic[rid][fid] = trips

func _planning(t: TestLog) -> void:
	var d := world(7)
	var sim: WorldSim = d["sim"]
	var city: SimSettlement = d["city"]
	var towns: Array = d["towns"]
	t.eq(int(sim.route_by_id[2].cls), WorldSim.LINK, "the drow city's road up is a link: its way to the surface")
	t.eq(sim.route_by_id[1].get("crossings", []), ["pass"], "the second road goes over the pass")
	t.eq(sim.route_by_id[0].get("crossings", []), [], "the first is flat")
	t.check(sim.factions[city.faction].rel(towns[0].faction) < 25.0, "the drow would raid the surface peoples (relation %.0f)" % sim.factions[city.faction].rel(towns[0].faction))
	# the same coin a trip on both roads: the pass pinches its wagons, so it weighs more
	trade(sim, 0, towns[0].faction, 4000.0, 10.0)
	trade(sim, 1, towns[1].faction, 4000.0, 10.0)
	var tg := SimBelow.targets(sim, city)
	t.eq(tg.size(), 2, "the city's raiders can reach both surface roads by its way up (%d)" % tg.size())
	if tg.size() == 2:
		t.eq(int(tg[0]["route"]), 1, "the pass road first, at the same coin")
		t.eq(int(tg[0]["way"]), 2, "by the link")
		t.check(float(tg[0]["weight"]) > float(tg[1]["weight"]) * 1.5, "a pass is worth a good deal more (%.3f against %.3f)" % [tg[0]["weight"], tg[1]["weight"]])
	# the richest road wins: the flat road carrying five times the coin a trip
	trade(sim, 0, towns[0].faction, 20000.0, 10.0)
	tg = SimBelow.targets(sim, city)
	t.eq(int(tg[0]["route"]) if not tg.is_empty() else -1, 0, "a richer flat road outweighs the pass")
	# the city's own raid decisions: surface roads only by the way, picked by weight
	var picks := {}
	var below := 0
	for i in 4000:
		city.out_raids = 0
		city.cooldowns.erase("raid")
		city.soldiers = 140
		var before := sim.next_party
		SimConflict._maybe_raid(sim, city)
		for pid: int in range(before, sim.next_party):
			if not sim.parties.has(pid):
				continue
			var p: SimParty = sim.parties[pid]
			var key := "route %d" % p.target if p.plan.get("mode", "") == "route" else "settlement %d" % p.target
			picks[key] = int(picks.get(key, 0)) + 1
			if SimBelow.is_below(p):
				below += 1
				if below <= 3:
					t.check(int(p.plan["below"]) == 2 and str(p.plan["way"]) == "ascent" and float(p.plan["due_t"]) > float(p.plan["out_t"]) \
							and float(p.plan["back_t"]) > float(p.plan["due_t"]), "raid %d: its way, kind and schedule" % pid)
					t.check(p.path.has(1) and p.path[0] == city.id, "raid %d climbs to the middle town's side" % pid)
			sim.remove_party(p)
	print("  4000 raid decisions of a drow city: %s, %d from below" % [picks, below])
	t.check(below >= 30, "the city raids the surface by its way up (%d)" % below)
	t.check(int(picks.get("route 0", 0)) > int(picks.get("route 1", 0)), "the richest road most often (%s)" % [picks])

func _no_way(t: TestLog) -> void:
	var d := world(7)
	var sim: WorldSim = d["sim"]
	var city: SimSettlement = d["city"]
	var towns: Array = d["towns"]
	trade(sim, 0, towns[0].faction, 4000.0, 10.0)
	# the same world with no way up: nothing on the surface to raid from below
	var sites: Array = sim.sites.duplicate(true)
	var routes: Array = []
	for r: Dictionary in sim.routes:
		if int(r.id) != 2:
			routes.append({"id": r.id, "a": r.a, "b": r.b, "kind": r.kind, "length": r.length})
	var sim2 := WorldSim.new()
	sim2._setup(sites, routes, 7, 1800.0)
	var deep: SimSettlement = null
	for sid: int in sim2.settlements:
		if sim2.settlements[sid].band != "surface":
			deep = sim2.settlements[sid]
	if deep != null:
		trade(sim2, 0, 1, 4000.0, 10.0)
		var any_road := false
		for row: Dictionary in SimBelow.targets(sim2, deep):
			any_road = true
		t.check(not any_road, "without a way up the deeps raid no surface road")
	else:
		t.check(true, "no deep settlement in the way-less world")
	t.check(SimBelow.pull("drow") > 1.0 and SimBelow.pull("goblinoid") > 1.0 and SimBelow.pull("duergar") == 1.0,
		"drow and goblinoids are pulled up to raid; duergar are not")

## The ambush on the road, and the walk home: the goods land in the city's stores.
func _goods_home(t: TestLog) -> void:
	var d := world(9)
	var sim: WorldSim = d["sim"]
	var city: SimSettlement = d["city"]
	var towns: Array = d["towns"]
	trade(sim, 1, towns[1].faction, 6000.0, 10.0)
	var ra := SimBelow.launch(sim, city, 1, 10)
	t.check(ra != null, "a raid from below sets out for the pass road")
	if ra == null:
		return
	t.eq(ra.path, [3, 1, 2] as Array[int], "up the way to the middle town, then out along the pass road")
	# it walks up and waits halfway along the road
	for h in 2000:
		SimConflict.tick_parties(sim, 1)
		if ra.state == "ambush":
			break
	t.eq(ra.state, "ambush", "it reaches the road and lies in wait")
	t.eq(ra.route, 1, "on the pass road")
	# a caravan from the middle town comes by
	var v := sim.new_party("caravan", towns[1].faction, "human", 1, SimData.allocate(SimData.culture("human").escort, 2))
	SimEconomy._add_member(v.members, "commoner", 2)
	v.people = 2
	v.cargo = {"salt": 60, "timber": 40}
	v.coin = 30.0
	v.wagons = 1
	t.check(sim.send(v, 2, WorldSim.ROAD), "a caravan sets out over the pass")
	towns[1].out_caravans += 1
	var chron := sim.chronicle.size()
	SimConflict.ambush_outcome(sim, ra, v, 1, [], true, 0, 0)
	var taken := 0
	for g: String in ra.cargo:
		taken += int(ra.cargo[g])
	t.check(taken > 0, "the raiders took goods (%s) and coin (%.0f)" % [ra.cargo, ra.coin])
	var line := ""
	for i in range(chron, sim.chronicle.size()):
		if String(sim.chronicle[i].kind) == "ambush":
			line = sim.describe(sim.chronicle[i])
			t.check(bool(sim.chronicle[i].get("below", false)) and int(sim.chronicle[i].get("wayid", -1)) == 2 and int(sim.chronicle[i].get("home", -1)) == city.id,
				"the chronicle knows it came from below, by which way, from where")
	print("  " + line)
	t.check(line.contains("came up"), "and says so")
	t.eq(String(ra.plan.get("leg", "")), "home", "loaded, the raiders turn for home")
	sim.way_watch.clear()         # the watch the ambush brought on is tested below
	var stock0 := city.stock.duplicate()
	var wealth0 := city.wealth
	var cargo: Dictionary = ra.cargo.duplicate()
	var coin := ra.coin
	var soldiers0 := city.soldiers
	var n := ra.size() - ra.people        # its fighters; captives join the workers
	var pid := ra.id
	for h in 3000:
		SimConflict.tick_parties(sim, 1)
		if not sim.parties.has(pid):
			break
	t.check(not sim.parties.has(pid), "the raid comes home")
	var ok := true
	for g: String in cargo:
		ok = ok and is_equal_approx(float(city.stock[g]) - float(stock0[g]), float(cargo[g]))
	t.check(ok, "every unit it carried is in the city's stores (%s)" % [cargo])
	t.check(is_equal_approx(city.wealth - wealth0, coin), "and the coin in its treasury (%.0f)" % coin)
	t.eq(city.soldiers - soldiers0, n, "its raiders back in the garrison (%d, and %d captives)" % [n, int(ra.plan.get("captives", 0.0))])
	t.eq(int(sim.stats.get("below_goods_home", 0)), taken, "the sim counts the goods carried home")
	t.eq(sim.audit(), [] as Array[String], "the books balance")

## The surface answers: guards at the way, and the patron's bounty naming the way and the city.
func _answer(t: TestLog) -> void:
	var d := world(11)
	var sim: WorldSim = d["sim"]
	var city: SimSettlement = d["city"]
	var towns: Array = d["towns"]
	var town: SimSettlement = towns[1]
	var ra := SimBelow.launch(sim, city, 1, 10)
	var v := sim.new_party("caravan", town.faction, "human", 1, {"guard": 2, "commoner": 2})
	v.people = 2
	v.cargo = {"salt": 50}
	sim.send(v, 2, WorldSim.ROAD)
	var g0 := town.soldiers
	t.check(sim.way_watch.is_empty(), "no one watches the way before")
	SimConflict.ambush_outcome(sim, ra, v, 1, [], true, 0, 0)
	var w: Dictionary = sim.way_watch.get(2, {})
	t.check(not w.is_empty(), "the raided town posts guards at the way the raiders used")
	if not w.is_empty():
		t.eq(int(w.home), town.id, "its own")
		t.check(int(w.n) >= SimBelow.WATCH_MIN and town.soldiers == g0 - int(w.n), "%d guards out of its garrison (%d -> %d)" % [int(w.n), g0, town.soldiers])
	var weight_guarded: float = (SimBelow.targets(sim, city)[0] as Dictionary).get("weight", 0.0) if not SimBelow.targets(sim, city).is_empty() else 0.0
	var watch := sim.way_watch[2] as Dictionary if sim.way_watch.has(2) else {}
	sim.way_watch.erase(2)
	var weight_open: float = (SimBelow.targets(sim, city)[0] as Dictionary).get("weight", 0.0) if not SimBelow.targets(sim, city).is_empty() else 0.0
	if not watch.is_empty():
		sim.way_watch[2] = watch
	t.check(weight_guarded < weight_open or weight_open == 0.0, "a guarded way makes the surface less tempting (%.4f against %.4f)" % [weight_guarded, weight_open])
	# the patron's bounty
	var day := Deals.day(sim)
	var offers := DealsQuests.offers(sim, 11, town.id, day)
	var q: Dictionary = {}
	for o: Dictionary in offers:
		if String(o["kind"]) == "below":
			q = o
	t.check(not q.is_empty(), "the raided town's patron offers a bounty")
	if q.is_empty():
		return
	print("  %s: %s %s" % [q["title"], q["why"], q["goal"]])
	t.check(bool(q.get("patron", false)), "patron work")
	t.eq(int(q["target"]["city"]), city.id, "on the raiders' home city")
	t.eq(int(q["target"]["way"]), 2, "by the way they used")
	t.check(String(q["goal"]).contains(sim.route_name(2)), "the goal names the way down")
	t.check(String(q["goal"]).contains(city.name), "and the city")
	# found by a player standing in the city: ready; in the city of another people: not
	var far := func(_pos: Vector2, _tiles: float) -> Array: return []
	var nobody := func(_sid: int, _m: float) -> Array: return []
	var there := func(sid: int, _m: float) -> Array: return ["hero"] if sid == city.id else []
	var qa := q.duplicate(true)
	qa["state"] = "active"
	t.eq(DealsQuests.check(sim, qa, {"near": far, "at": nobody, "party_pos": func(_p: SimParty) -> Vector2: return Vector2.INF}), "", "nothing yet")
	t.eq(DealsQuests.check(sim, qa, {"near": far, "at": there, "party_pos": func(_p: SimParty) -> Vector2: return Vector2.INF}), "ready", "found the city: ready to turn in")
	t.check(DealsQuests.still_valid(sim, q), "valid while the city stands")
	# watches go home when they run out
	var g1 := town.soldiers
	var n := int(sim.way_watch[2].n) if sim.way_watch.has(2) else 0
	sim.t += (SimBelow.WATCH_DAYS + 1) * WorldSim.DAY_H
	SimBelow.tick_watches(sim)
	t.check(not sim.way_watch.has(2), "after %d days the watch ends" % SimBelow.WATCH_DAYS)
	t.eq(town.soldiers, g1 + n, "and its guards come home")
	t.eq(sim.audit(), [] as Array[String], "the books balance")

func _watch_fights(t: TestLog) -> void:
	var d := world(13)
	var sim: WorldSim = d["sim"]
	var city: SimSettlement = d["city"]
	var town: SimSettlement = d["towns"][1]
	town.soldiers = 200
	SimBelow.post_watch(sim, town.id, 2)
	t.check(sim.way_watch.has(2), "guards posted")
	var fights := 0
	for i in 12:
		city.soldiers = 200
		var ra := SimBelow.launch(sim, city, 1, 6)
		if ra == null:
			continue
		for h in 400:
			SimConflict.tick_parties(sim, 1)
			if not sim.parties.has(ra.id) or ra.route != 2:
				break
		if sim.way_watch.has(2) and int(sim.way_watch[2].n) <= 0:
			sim.way_watch[2]["n"] = 8
	fights = int(sim.stats.get("watch_fights", 0))
	t.check(fights >= 4, "raids climbing a guarded way meet the watch at the mouth (%d of 12)" % fights)
	var lines := sim.chronicle.filter(func(e: Dictionary) -> bool: return String(e.kind) == "watch_fight")
	if not lines.is_empty():
		print("  " + sim.describe(lines[0]))
	t.eq(sim.audit(), [] as Array[String], "the books balance")

func _save(t: TestLog) -> void:
	var d := world(15)
	var sim: WorldSim = d["sim"]
	var town: SimSettlement = d["towns"][1]
	SimBelow.post_watch(sim, town.id, 2)
	var back := WorldSim.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	t.eq(back.way_watch.size(), 1, "a watch survives a save")
	t.eq(int(back.way_watch[2].n) if back.way_watch.has(2) else -1, int(sim.way_watch[2].n), "with its guards")
	var plain := world(15)["sim"] as WorldSim
	t.check(not plain.to_dict().has("way_watch"), "a world with no watch saves as before")

# --- on screen ------------------------------------------------------------------------------

## The way up of a dev world with a drow city (dev 4: its ascent from the city), a raid from it
## climbing, the guards at the mouth, two players seeing the same people.
func _on_screen(t: TestLog) -> void:
	var r := PB.full_rig(4)
	var host: WorldHost = r["host"]
	var life: LifeSystem = r["life"]
	var sim := host.sim
	var city := -1
	var way := -1
	for rid: int in WorldSim._sorted_keys(sim.route_by_id):
		var rr: Dictionary = sim.route_by_id[rid]
		if int(rr.cls) != WorldSim.LINK:
			continue
		var deep := SimBelow.deep_end(sim, rid)
		if sim.settlements.has(deep) and SimBelow.pull(sim.settlements[deep].culture) > 1.0:
			city = deep
			way = rid
	t.check(city >= 0, "dev 4 has a deep city of raiders with a way up (%s)" % (sim.settlements[city].name if city >= 0 else "-"))
	if city < 0:
		return
	var cs: SimSettlement = sim.settlements[city]
	cs.soldiers = maxi(cs.soldiers, 40)
	# a world just begun has sent no caravans yet: give its surface roads some trade
	for rid: int in WorldSim._sorted_keys(sim.route_by_id):
		var rr: Dictionary = sim.route_by_id[rid]
		if int(rr.cls) == WorldSim.ROAD and sim.settlements.has(int(rr.a)) and not sim.route_value.has(rid):
			trade(sim, rid, sim.settlements[int(rr.a)].faction, 3000.0, 8.0)
	var targets := SimBelow.targets(sim, cs, true)
	t.check(not targets.is_empty(), "it has surface roads to raid (%d)" % targets.size())
	var mouth := life.below.mouth(host, way)
	t.check(mouth != Vector2.INF, "the way comes out on the surface at %s" % mouth)
	var cells := life.below.way_cells(host, way)
	t.check(cells.size() > 10, "and has a walk (%d cells)" % cells.size())
	# a raid on the way up, halfway
	var pid := life.cheat_below(city, -1, "way", 0.5, 8)
	t.check(pid > 0, "a raid from below on its way up")
	if pid <= 0:
		return
	var p: SimParty = sim.parties[pid]
	var at := life.road.party_pos(host, p)
	t.check(at != Vector2.INF, "it has a place on the way (%s)" % at)
	var a := PB.player(host, "watcher", at + Vector2(-20, 0))
	var b := PB.player(host, "second", at + Vector2(22, 0))
	for i in 60:
		host.tick()
	var people := life.actors_of(pid)
	t.check(people.size() >= 4, "its people walk on screen (%d)" % people.size())
	var roles := {}
	for e: HostEntity in people:
		roles[e.name.get_slice(", ", 1)] = true
	t.check(people.all(func(e: HostEntity) -> bool: return Life.faction_of(e) == str(cs.faction)), "all of the city's faction")
	print("  the raid: %s" % [people.map(func(e: HostEntity) -> String: return e.name)])
	t.check(roles.has("raider") or roles.has("scout") or roles.has("mage") or roles.has("priest"), "named by their roles (%s)" % [roles.keys()])
	t.eq(life.stance(a, people[0]) if not people.is_empty() else -1, Life.HOSTILE, "raiders are foes to a stranger")
	# both players are near: the same entities, sent to both (host entities are one set)
	var near_a := 0
	var near_b := 0
	for e: HostEntity in people:
		if e.body.pos.distance_to(a.body.pos) < 80.0:
			near_a += 1
		if e.body.pos.distance_to(b.body.pos) < 80.0:
			near_b += 1
	t.check(near_a == people.size() and near_b == people.size(), "both players have the same raiders in view (%d, %d of %d)" % [near_a, near_b, people.size()])
	# a kill on the surface costs no standing (they fall on strangers abroad)
	var s0 := life.standing(a.id, str(cs.faction))
	var victim: HostEntity = null
	for e: HostEntity in people:
		if SimData.band_family(life.band_at(e.body.pos.y)) == "surface":
			victim = e
	if victim != null:
		host.system(HostSystem.COMBAT).call("damage", a.id, victim, 9999, SRD.DamageType.SLASHING)
		for i in 10:
			host.tick()
		t.eq(life.standing(a.id, str(cs.faction)), s0, "killing a raider on the surface costs no standing")
	else:
		t.check(true, "no raider on the surface yet to test standing with")
	# the guards at the mouth
	var town := SimBelow.surface_end(sim, way)
	if sim.settlements.has(town):
		sim.settlements[town].soldiers = maxi(sim.settlements[town].soldiers, 40)
		SimBelow.post_watch(sim, town, way)
	t.check(sim.way_watch.has(way), "the town at the mouth watches the way")
	a.body.pos = mouth + Vector2(-6, 2)
	TileCollision.depenetrate(host.world, a.body)
	b.body.pos = mouth + Vector2(6, 2)
	TileCollision.depenetrate(host.world, b.body)
	for i in 70:
		host.tick()
	var guards := life.below.actors_at(host, way)
	t.eq(guards.size(), mini(int(sim.way_watch[way].n), LifeBelow.SHOW) if sim.way_watch.has(way) else -1, "the guards stand at the mouth (%d)" % guards.size())
	var close := 0
	for e: HostEntity in guards:
		if e.body.pos.distance_to(mouth) < 12.0:
			close += 1
	t.check(guards.all(func(e: HostEntity) -> bool: return e.has_meta("torch")), "keeping a light")
	t.eq(close, guards.size(), "all of them by the mouth")
	if not guards.is_empty():
		var n0 := int(sim.way_watch[way].n)
		host.system(HostSystem.COMBAT).call("damage", 0, guards[0], 9999, SRD.DamageType.SLASHING)
		for i in 10:
			host.tick()
		t.eq(int(sim.way_watch[way].n) if sim.way_watch.has(way) else 0, n0 - 1, "a guard who falls is one fewer in the sim")
	t.eq(sim.audit(), [] as Array[String], "the books balance")
