## Biomes in the sim: the land sets what a town can feed and sell; goods cross barriers at a cost;
## raids go where the money goes; and generated worlds stay healthy over decades.
extends RefCounted

const FIVE := ["meadow", "forest", "mountain", "desert", "swamp"]
const WIDTH := 8192

func run(t: TestLog) -> void:
	_table(t)
	_alone(t)
	_prices(t)
	_uses(t)
	_cultures(t)
	_trails(t)
	_real_roads(t)
	_raid_choice(t)
	_old_save(t)
	_sweep(t)

## A strip of one town per biome, spaced apart, plus any extra sites and barriers.
func _meta(extra_sites := [], routes := [], barriers := {}) -> Dictionary:
	var sites: Array = []
	for i in FIVE.size():
		sites.append({"id": i, "kind": "settlement", "x": 400 + i * 1500, "y": 700, "biome": FIVE[i], "band": "surface", "size": 96})
	sites.append_array(extra_sites)
	var rs: Array = routes
	if rs.is_empty():
		for i in FIVE.size() - 1:
			rs.append({"id": i, "a": i, "b": i + 1, "kind": "road", "length": 1600})
	var surface: Array = []
	surface.resize(WIDTH)
	return {"surface": surface, "sites": sites, "routes": rs, "barriers": barriers}

## The same town, human and all, in every biome: only the land differs. Fresh factions, no
## neighbours to trade with: the test ticks each one alone.
func _towns(pop: int) -> Array:
	var sim := WorldSim.from_meta(_meta(), 1)
	sim.settlements.clear()
	sim.factions.clear()
	sim.lairs.clear()
	var f := sim._new_faction("human")
	for i in FIVE.size():
		sim._new_settlement(i, "human", f.id, pop)
	return [sim, f]

func _table(t: TestLog) -> void:
	var row := func(id: String) -> Dictionary: return SimData.biome(id, "surface")
	var by := func(key: String) -> Array:
		var ids := FIVE.duplicate()
		ids.sort_custom(func(a, b): return float(row.call(a).get(key, 0.0)) > float(row.call(b).get(key, 0.0)))
		return ids
	t.eq(by.call("food"), ["meadow", "forest", "swamp", "mountain", "desert"], "farms feed the meadow best, the desert worst")
	t.eq(by.call("timber")[0], "forest", "forests give the most timber")
	t.eq(by.call("game")[0], "forest", "and the most game")
	t.eq(by.call("ore")[0], "mountain", "mountains give the most ore")
	t.eq(by.call("stone")[0], "mountain", "and stone")
	t.eq(by.call("salt")[0], "desert", "deserts give the most salt")
	t.eq(by.call("reagents")[0], "swamp", "swamps give the most reagents")
	t.eq(by.call("water")[-1], "desert", "and deserts the least water")
	for id: String in BiomeIds.generated():
		for g: String in SimData.good_names:
			if SimData.goods[g].has("cap"):
				t.check(SimData.biomes[id].has(g), "%s says what it gives of %s" % [id, g])

## Eight years alone. Each town keeps what its land gives and goes short of the rest.
func _alone(t: TestLog) -> void:
	var pack := _towns(1500)
	var sim: WorldSim = pack[0]
	for i in 8 * WorldSim.YEAR_DAYS / WorldSim.ECON_DAYS:
		sim.t += WorldSim.ECON_H
		for id in range(FIVE.size()):
			SimEconomy._tick_settlement(sim, sim.settlements[id], WorldSim.ECON_DAYS)
	var s := {}
	for i in FIVE.size():
		s[FIVE[i]] = sim.settlements[i]
	t.check(s.meadow.pop() > s.forest.pop() and s.forest.pop() > s.swamp.pop() and s.swamp.pop() > s.desert.pop(),
		"a lone town holds what its land feeds: meadow %d, forest %d, swamp %d, mountain %d, desert %d" % [s.meadow.pop(), s.forest.pop(), s.swamp.pop(), s.mountain.pop(), s.desert.pop()])
	t.check(s.mountain.pop() > s.desert.pop(), "the mountain feeds more than the desert")
	t.check(s.meadow.pop() >= 1400, "the meadow holds what it started with, near enough (%d)" % s.meadow.pop())
	t.check(s.desert.pop() < 1200, "the desert can't feed 1500 alone (%d)" % s.desert.pop())
	var per := func(biome: String, g: String) -> float: return float(s[biome].stock[g]) / maxf(s[biome].pop(), 1.0)
	for pair: Array in [["timber", "forest"], ["ore", "mountain"], ["stone", "mountain"], ["salt", "desert"], ["reagents", "swamp"]]:
		var g: String = pair[0]
		var home: String = pair[1]
		for other: String in FIVE:
			if other != home:
				t.check(per.call(home, g) > per.call(other, g), "%s a head: %s %.2f over %s %.2f" % [g, home, per.call(home, g), other, per.call(other, g)])
	t.check(s.forest.cap.game > s.meadow.cap.game, "the forest hunts more than it stocks: a short town eats its game")
	t.check(per.call("desert", "water") < per.call("meadow", "water") * 0.5, "the desert's wells run low (%.1f a head, meadow %.1f)" % [per.call("desert", "water"), per.call("meadow", "water")])

func _prices(t: TestLog) -> void:
	var pack := _towns(1000)
	var sim: WorldSim = pack[0]
	var s := {}
	for i in FIVE.size():
		s[FIVE[i]] = sim.settlements[i]
		for g: String in SimData.good_names:
			s[FIVE[i]].stock[g] = SimEconomy.target(s[FIVE[i]], g)
	t.check(SimEconomy.price(s.mountain, "ore") < SimEconomy.price(s.meadow, "ore"), "at the same stock, ore is cheap where it is dug")
	t.check(SimEconomy.price(s.desert, "salt") < SimEconomy.price(s.forest, "salt"), "and salt where it is panned")
	t.check(SimEconomy.price(s.meadow, "food") < SimEconomy.price(s.desert, "food"), "grain costs more in the desert")
	t.check(SimEconomy.price(s.desert, "water") > SimEconomy.price(s.swamp, "water"), "and water")
	t.eq(SimEconomy.price(s.meadow, "tools"), SimEconomy.price(s.desert, "tools"), "goods no land gives cost the same at the same stock")
	t.check(SimEconomy.stock_cap(s.desert, "salt") > SimEconomy.stock_cap(s.meadow, "salt"), "a town stockpiles what its land gives, to sell")
	t.check(SimEconomy.stock_cap(s.mountain, "ore") > SimEconomy.stock_cap(s.forest, "ore"), "the mountain piles up more ore")

## What each new good is for.
func _uses(t: TestLog) -> void:
	# Salt keeps the granary from spoiling.
	var pack := _towns(1000)
	var sim: WorldSim = pack[0]
	var salted: SimSettlement = sim.settlements[0]
	var bare: SimSettlement = sim.settlements[4]
	sim.t = WorldSim.ECON_H
	for s: SimSettlement in [salted, bare]:
		s.cap = {"food": 0.0, "timber": 0.0, "ore": 0.0, "stone": 0.0, "salt": 0.0, "reagents": 0.0, "game": 0.0, "water": 0.0}
		s.stock.food = 50000.0
	salted.stock.salt = 1000.0
	bare.stock.salt = 0.0
	SimEconomy._tick_settlement(sim, salted, 5)
	SimEconomy._tick_settlement(sim, bare, 5)
	t.check(salted.stock.food > bare.stock.food, "salted food keeps (%.0f against %.0f)" % [salted.stock.food, bare.stock.food])
	# Game feeds a town when the grain runs out.
	pack = _towns(1000)
	sim = pack[0]
	sim.t = WorldSim.ECON_H
	var hunters: SimSettlement = sim.settlements[1]
	var town: SimSettlement = sim.settlements[0]
	for s: SimSettlement in [hunters, town]:
		s.cap.food = 0.0
		s.stock.food = 0.0
		s.stock.game = 0.0
	hunters.stock.game = 1000.0
	SimEconomy._tick_settlement(sim, hunters, 5)
	SimEconomy._tick_settlement(sim, town, 5)
	t.eq(hunters.hungry, 0, "a town with game eats it when the food is gone")
	t.eq(town.hungry, 1, "a town with neither goes hungry")
	t.check(hunters.stock.game < 1000.0, "the game went down")
	# Water waters the fields.
	pack = _towns(1000)
	sim = pack[0]
	sim.t = WorldSim.ECON_H
	var wet: SimSettlement = sim.settlements[3]
	var dry: SimSettlement = sim.settlements[0]
	wet.cap = dry.cap.duplicate()
	wet.land = dry.land
	wet.seasonal = false
	dry.seasonal = false
	wet.cap.water = 0.0
	dry.cap.water = 0.0
	wet.stock.water = 100000.0
	dry.stock.water = 0.0
	var wet0: float = wet.stock.food
	var dry0: float = dry.stock.food
	SimEconomy._tick_settlement(sim, wet, 5)
	SimEconomy._tick_settlement(sim, dry, 5)
	t.check(wet.stock.food - wet0 > dry.stock.food - dry0, "a watered field yields more than a dry one")
	# Stone keeps the walls up.
	var v: SimSettlement = sim.settlements[1]
	v.tier = "town"
	v.stock.stone = SimEconomy.target(v, "stone")
	t.eq(SimConflict.wall_ac(v), 2, "a town in repair has its walls")
	v.stock.stone = 0.0
	t.eq(SimConflict.wall_ac(v), 1, "a town out of stone has let them go")
	v.tier = "hamlet"
	t.eq(SimConflict.wall_ac(v), 0, "and nothing goes below no walls")

func _cultures(t: TestLog) -> void:
	SimData.ensure()
	t.check(SimData.fit("dwarf", "mountain") > SimData.fit("dwarf", "meadow"), "dwarves favour mountains")
	t.check(SimData.fit("halfling", "meadow") > SimData.fit("halfling", "desert"), "halflings meadows")
	t.check(SimData.fit("dragonborn", "desert") > SimData.fit("dragonborn", "forest"), "dragonborn deserts")
	t.check(SimData.fit("elf", "forest") > SimData.fit("elf", "mountain"), "elves forests")
	t.check(SimData.fit("drow", "underdark") >= SimData.fit("dwarf", "underdark"), "the drow hold the underdark first")
	# Over many draws, each biome is settled by the peoples it suits.
	var sim := WorldSim.from_meta(_meta(), 1)
	var picks := {}
	for b: String in FIVE:
		picks[b] = {}
		for i in 400:
			var c: String = sim._pick_culture({"biome": b, "band": "surface"}, "")
			picks[b][c] = int(picks[b].get(c, 0)) + 1
	t.check(int(picks.mountain.get("dwarf", 0)) > int(picks.desert.get("dwarf", 0)) * 4, "dwarves go to the mountain, not the desert")
	t.check(int(picks.meadow.get("halfling", 0)) > int(picks.mountain.get("halfling", 0)) * 4, "halflings to the meadow")
	var deep := {}
	for i in 400:
		var c: String = sim._pick_culture({"biome": "underdark", "band": "deeps"}, "")
		deep[c] = int(deep.get(c, 0)) + 1
	t.check(int(deep.get("drow", 0)) > int(deep.get("dwarf", 0)), "deep sites read their weights: %s" % [deep])
	# A run of kin stops where the land stops suiting them.
	var stayed := 0
	for i in 400:
		if sim._pick_culture({"biome": "desert", "band": "surface"}, "elf") == "elf":
			stayed += 1
	t.check(stayed < 80, "elves don't follow their neighbours into the desert (%d of 400)" % stayed)

## A site with no route gets a trail, and a trail over a barrier pays what a road does.
func _trails(t: TestLog) -> void:
	var barriers := {"ranges": [{"id": 0, "x0": 2000, "x1": 2500}], "rivers": [{"id": 0, "kind": "ford", "x0": 3100, "x1": 3130}]}
	# A lair just east of the range: town 1 (x 1900) is nearest by column, over the pass, and
	# town 2 (x 3400) is nearer on foot, over a ford.
	var lair := {"id": 5, "kind": "lair", "x": 2600, "y": 700, "biome": "mountain", "band": "surface", "size": 8}
	var flat := WorldSim.from_meta(_meta([lair]), 1)
	var hard := WorldSim.from_meta(_meta([lair], [], barriers), 1)
	var a: Dictionary = _trail_of(flat, 5)
	var b: Dictionary = _trail_of(hard, 5)
	t.eq(a.b, 1, "with no barrier the lair's trail goes to the nearest town")
	t.eq(b.b, 2, "over a pass the nearer town by the walk is the one on its own side")
	t.eq(b.crossings, ["ford"], "that trail crosses the river")
	# The same two sites with and without a range between them.
	var pass_len := 0.05 * WIDTH
	t.check(is_equal_approx(float(SimData.crossing_cost["pass"]), 0.05), "the sim reads the barrier table's cost")
	var lean := {"id": 7, "kind": "lair", "x": 2600, "y": 700, "biome": "mountain", "band": "surface", "size": 8}
	var pair: Array = [{"id": 0, "kind": "settlement", "x": 1900, "y": 700, "biome": "meadow", "band": "surface", "size": 96}, lean]
	var m1 := {"surface": _sized(), "sites": pair, "routes": []}
	var m2 := {"surface": _sized(), "sites": pair, "routes": [], "barriers": {"ranges": [{"id": 0, "x0": 2000, "x1": 2500}]}}
	var s1 := WorldSim.from_meta(m1, 1)
	var s2 := WorldSim.from_meta(m2, 1)
	t.eq(s1.routes.size(), 1, "one trail joins the two")
	var r1: Dictionary = s1.routes[0]
	var r2: Dictionary = s2.routes[0]
	t.check(is_equal_approx(float(r2.length) - float(r1.length), pass_len), "a pass adds 5%% of the width to a trail (%.0f, %.0f)" % [r1.length, r2.length])
	t.check(s2.route_hours[r2.id] > s1.route_hours[r1.id], "and to its planning hours")
	t.check(s2.route_travel_h[r2.id] > s1.route_travel_h[r1.id], "and to the wagons' real hours")
	t.eq(r2.crossings, ["pass"], "and it says what it crosses")
	t.eq(r1.crossings, [], "the flat trail crosses nothing")
	# Underground goes under: a deep trail costs no more for the range over it.
	var deep := [{"id": 0, "kind": "settlement", "x": 1900, "y": 200, "biome": "underdark", "band": "deeps", "size": 96},
		{"id": 1, "kind": "lair", "x": 2600, "y": 200, "biome": "caves", "band": "caves", "size": 8}]
	var d2 := WorldSim.from_meta({"surface": _sized(), "sites": deep, "routes": [], "barriers": {"ranges": [{"id": 0, "x0": 2000, "x1": 2500}]}}, 1)
	t.eq(d2.routes[0].crossings, [], "a deep route crosses nothing on the surface")
	# And a saved route remembers what it crosses.
	var back := WorldSim.from_dict(JSON.parse_string(JSON.stringify(s2.to_dict())))
	t.eq(back.routes[0].crossings, ["pass"], "crossings survive a save")

func _sized() -> Array:
	var surface: Array = []
	surface.resize(WIDTH)
	return surface

func _trail_of(sim: WorldSim, sid: int) -> Dictionary:
	for r in sim.routes:
		if r.has("trail") and r.a == sid:
			return r
	return {}

## On a real world the roads already hold their crossings' cost; the sim names them and adds
## nothing, and its cultures are the ones the places were built for.
func _real_roads(t: TestLog) -> void:
	var w := WorldGen.generate_named("dev", 2)
	var sim := WorldSim.from_meta(w.meta, 2)
	var saw_pass := false
	for r in sim.routes:
		if r.has("trail"):
			continue
		var was: Dictionary = {}
		for m: Dictionary in w.meta.routes:
			if int(m.id) == r.id:
				was = m
		t.eq(int(r.length), int(was.length), "road %d keeps worldgen's length" % r.id)
		if "pass" in r.crossings:
			saw_pass = true
			var a: Dictionary = sim.site_by_id[r.a]
			var b: Dictionary = sim.site_by_id[r.b]
			var per := float(r.length) / absf(a.x - b.x)
			t.check(per > 1.2, "a road over the pass is long for its columns (%.2f)" % per)
	t.check(saw_pass, "dev seed 2 has a road over a pass")
	for k: String in w.meta.places:
		var sid := int(k)
		if sim.settlements.has(sid):
			t.eq(String(w.meta.places[k].culture), sim.settlements[sid].culture, "the place at site %d is built for who lives there" % sid)

## Raiders go for the richer train, and a barrier makes a road worth more to them.
func _raid_choice(t: TestLog) -> void:
	var sites: Array = []
	for i in 6:
		sites.append({"id": i, "kind": "settlement", "x": 400 + i * 400, "y": 700, "biome": "meadow", "band": "surface", "size": 96})
	var roads: Array = []
	for i in 5:
		roads.append({"id": i, "a": i, "b": i + 1, "kind": "road", "length": 400})
	var sim := WorldSim.from_meta({"surface": _sized(), "sites": sites, "routes": roads}, 3)
	sim.settlements.clear()
	sim.factions.clear()
	var robbers := sim._new_faction("bandit")
	robbers.temperament = "raider"
	var traders := sim._new_faction("human")
	robbers.relations[traders.id] = -50.0
	traders.relations[robbers.id] = -50.0
	var den := sim._new_settlement(2, "bandit", robbers.id, 400)
	sim._new_settlement(0, "human", traders.id, 800)
	var mask := sim.mask_for(SimData.culture("bandit").raid_mobility)
	var dist: Dictionary = sim.paths_from(2, mask)[0]
	var reach := 240.0
	var weight := func(rid: int) -> float:
		for c: Array in SimConflict.route_targets(sim, den, false, mask, dist, reach):
			if c[1] == rid:
				return float(c[2])
		return 0.0
	# Routes 1 and 2 touch the den, so the walk to them is the same.
	sim.route_traffic = {1: {traders.id: 8.0}, 2: {traders.id: 8.0}}
	sim.route_value = {1: {traders.id: 8.0 * 900.0}, 2: {traders.id: 8.0 * 100.0}}
	t.check(weight.call(1) > weight.call(2) * 5.0, "a raid prefers the richer route (%.1f against %.1f)" % [weight.call(1), weight.call(2)])
	# Many cheap carts against a few rich trains.
	sim.route_traffic = {1: {traders.id: 4.0}, 2: {traders.id: 40.0}}
	sim.route_value = {1: {traders.id: 4.0 * 900.0}, 2: {traders.id: 40.0 * 60.0}}
	t.check(weight.call(1) > weight.call(2), "value, not traffic: a few rich trains beat many carts (%.1f against %.1f)" % [weight.call(1), weight.call(2)])
	# A rumour of one train long ago is worth less than a steady road.
	sim.route_traffic = {1: {traders.id: 0.3}, 2: {traders.id: 8.0}}
	sim.route_value = {1: {traders.id: 0.3 * 900.0}, 2: {traders.id: 8.0 * 900.0}}
	t.check(weight.call(1) < weight.call(2), "a train that may not come is worth less than one that will")
	# Same cargo, same walk: the road with a pass on it is the better place to wait.
	sim.route_traffic = {1: {traders.id: 8.0}, 2: {traders.id: 8.0}}
	sim.route_value = {1: {traders.id: 8.0 * 500.0}, 2: {traders.id: 8.0 * 500.0}}
	sim.route_by_id[1]["crossings"] = ["pass"]
	t.check(weight.call(1) > weight.call(2) * 1.5, "wagons pinched on a pass draw raiders (%.1f against %.1f)" % [weight.call(1), weight.call(2)])
	# Friends' cargo draws nobody.
	sim.route_value = {1: {robbers.id: 80000.0}}
	sim.route_traffic = {1: {robbers.id: 8.0}}
	t.eq(weight.call(1), 0.0, "raiders don't rob their own caravans")
	# The chance is real: picked through the same weights, the rich road takes most raids.
	sim.route_traffic = {1: {traders.id: 8.0}, 2: {traders.id: 8.0}}
	sim.route_value = {1: {traders.id: 8.0 * 900.0}, 2: {traders.id: 8.0 * 100.0}}
	sim.route_by_id[1]["crossings"] = []
	var sent := {1: 0, 2: 0}
	for i in 400:
		den.soldiers = 60
		den.out_raids = 0
		den.cooldowns.erase("raid")
		den.stock.food = SimEconomy.target(den, "food")
		sim.parties.clear()
		# Force the launch: drive is a chance, the choice is what is under test.
		var before := sim.next_party
		for tries in 400:
			SimConflict._maybe_raid(sim, den)
			if sim.next_party != before:
				break
		for pid in sim.parties:
			var p: SimParty = sim.parties[pid]
			if p.kind == "raid" and sent.has(p.target):
				sent[p.target] += 1
	t.check(sent[1] > sent[2] * 3, "raids sent: rich road %d, poor road %d" % [sent[1], sent[2]])

## A save from before the new goods loads, with none of them in stock.
func _old_save(t: TestLog) -> void:
	var sim := WorldSim.synthetic(16, 5)
	sim.step(WorldSim.YEAR_H)
	var d: Dictionary = JSON.parse_string(JSON.stringify(sim.to_dict()))
	d.erase("route_value")
	for sd: Dictionary in d.settlements:
		for g: String in ["stone", "salt", "reagents", "game", "water"]:
			(sd.stock as Dictionary).erase(g)
	for r: Dictionary in d.routes:
		r.erase("crossings")
	var old := WorldSim.from_dict(d)
	for sid in old.settlements:
		t.check(old.settlements[sid].stock.has("salt"), "an old town gets its new stocks")
		break
	old.step(WorldSim.YEAR_H)
	t.eq(old.audit(), [] as Array[String], "and runs on clean")

## Generated worlds over decades. The numbers the track reports come from tools/run_history.gd;
## these are the bars they must clear.
func _sweep(t: TestLog) -> void:
	var total := {}
	var seeds := [1, 2, 3, 4, 5, 6]
	var trips_over := 0
	var worlds_over := 0
	for seed in seeds:
		var sim := WorldSim.from_meta(WorldGen.generate_named("dev", seed).meta, seed)
		var h := SimHealth.observe(sim, 60)
		t.eq(h.bad, 0, "dev %d: the audit stays clean" % seed)
		t.check(not h.collapsed, "dev %d: no collapse (%d to %d)" % [seed, h.pop0, h.pop1])
		t.check(not h.exploded, "dev %d: no explosion (max %d from %d)" % [seed, h.pop_max, h.pop0])
		t.check(h.settl1 >= 3, "dev %d: towns stand at the end (%d)" % [seed, h.settl1])
		if h.routes.barrier.routes > 0:
			worlds_over += 1
			trips_over += int(h.routes.barrier.trips)
		for b in h.biomes:
			if not total.has(b):
				total[b] = {"seasons": 0, "hungry": 0, "short": 0, "rich": 0, "people": 0, "towns": 0, "top": 0}
			for k in ["seasons", "hungry", "short", "rich", "people", "towns"]:
				total[b][k] += h.biomes[b][k]
			total[b].top = maxi(total[b].top, h.biomes[b].top)
	for b in total:
		var r: Dictionary = total[b]
		var seasons := maxf(r.seasons, 1.0)
		t.check(r.hungry / seasons < 0.1, "%s is not always starving (%.1f%% of seasons hungry)" % [b, 100.0 * r.hungry / seasons])
		t.check(r.short / seasons < 0.3, "nor always short (%.1f%%)" % (100.0 * r.short / seasons))
		t.check(r.rich / seasons < 0.85, "nor always rich (%.1f%%)" % (100.0 * r.rich / seasons))
	var per_place := func(b: String) -> float: return float(total[b].people) / maxf(total[b].seasons, 1.0)
	for b: String in ["forest", "desert", "swamp"]:
		t.check(per_place.call("meadow") >= per_place.call(b), "a meadow town (%.0f) outgrows a %s one (%.0f)" % [per_place.call("meadow"), b, per_place.call(b)])
	t.check(total.desert.top >= 400, "the desert holds a real town (largest %d)" % total.desert.top)
	t.check(worlds_over > 0 and trips_over > worlds_over * 50, "caravans still cross barriers (%d trips in %d worlds)" % [trips_over, worlds_over])
