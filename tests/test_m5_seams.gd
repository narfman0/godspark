## What the M5 tracks left at their seams: shops carry the new goods at sane prices, a lair is named
## for what comes out of it, a river's name keeps off a town's, a swamp has open water on a real
## world, and a body shows its weapon from the moment it is seen.
extends RefCounted

const Rig := preload("res://tests/net_rig.gd")
const GOODS := ["salt", "stone", "reagents", "game", "water"]

func run(t: TestLog) -> void:
	var world := WorldGen.generate_named("dev", 15)
	var sim := WorldSim.from_meta(world.meta, 15)
	sim.step(24 * 90)
	_shelves(t, sim)
	_no_coin_press(t, sim)
	_lair_names(t, sim)
	_labels(t)
	_water(t)
	_wield(t)

## Every new good has a shelf row and a trade item, and is on a shelf where the land gives it.
func _shelves(t: TestLog, sim: WorldSim) -> void:
	var rows: Array = Deals.prices()["shelves"]
	for g: String in GOODS:
		var row: Array = rows.filter(func(r: Dictionary) -> bool: return String(r["good"]) == g and String(r["base"]).begins_with("trade:"))
		t.eq(row.size(), 1, "a shelf row for %s" % g)
		t.check(Items.exists("trade:" + g), "and a trade item")
		t.eq(DealsShop.good_of(Items.make("trade:" + g)), [g, 1.0], "which is one unit of the good")
	var seen := {}
	var bad: Array = []
	for sid: int in WorldSim._sorted_keys(sim.settlements):
		for l: Dictionary in DealsShop.shelves(sim, sid):
			if int(l["n"]) > 0:
				seen[l["good"]] = true
			if int(l["each"]) < 1 or int(l["n"]) < 0:
				bad.append(l)
	t.eq(bad, [], "nothing on any shelf is free or below zero")
	for g: String in GOODS:
		t.check(seen.has(g), "%s is on a shelf somewhere" % g)

## In no town, at no standing, does selling a good back pay what buying it cost.
func _no_coin_press(t: TestLog, sim: WorldSim) -> void:
	var press: Array = []
	var dear_salt := 0.0
	var cheap_salt := INF
	for sid: int in WorldSim._sorted_keys(sim.settlements):
		var s: SimSettlement = sim.settlements[sid]
		for mods: Dictionary in [{}, {"standing": 100, "bond": 1, "patron": 3, "price_mult": 0.5}]:
			for l: Dictionary in DealsShop.shelves(sim, sid):
				if not String(l["item"]["base"]).begins_with("trade:"):
					continue
				var buy := DealsShop.price(int(l["each"]), DealsShop.buy_mult(mods))
				var each := DealsShop.sell_for(sim, sid, l["item"], mods)
				var sell := maxi(1, floori(each)) if each >= 0.5 else 0
				if sell >= buy and buy > 1:
					press.append("%s at %s: buy %d, sell %d" % [l["good"], s.name, buy, sell])
		dear_salt = maxf(dear_salt, SimEconomy.price(s, "salt"))
		cheap_salt = minf(cheap_salt, SimEconomy.price(s, "salt"))
	t.eq(press, [], "no town sells a good for less than it pays")
	t.check(dear_salt > cheap_salt * 1.5, "and the price of salt still differs by the land (%.2f to %.2f)" % [cheap_salt, dear_salt])
	var ref := 0.0
	for s: SimSettlement in sim.settlements.values():
		ref = maxf(ref, s.price_ref)
	t.check(ref > 0.0 and ref < float(SimData.goods["food"]["base"]) * 6.0, "price_ref stays a food price (%.2f), and only the famine line reads it" % ref)

## A lair's name follows the body lair_kin gives it, and every swap has a name.
func _lair_names(t: TestLog, sim: WorldSim) -> void:
	var l := SimLair.new()
	l.family = "surface"
	l.kind = "wolves"
	l.biome = "desert"
	t.eq(SimConflict._lair_what(l), "hyena pack", "a wolf pack in the desert is a hyena pack in the chronicle")
	l.biome = "forest"
	t.eq(SimConflict._lair_what(l), "wolf pack", "and a wolf pack in the forest")
	var kin: Dictionary = Ecology.spawning()["lair_kin"]
	for row: Dictionary in SimData.lairs["surface"]:
		for biome: String in kin:
			if biome.begins_with("_"):
				continue
			var lead := String(row["members"][0][0])
			if (kin[biome] as Dictionary).has(lead):
				t.check((row.get("in", {}) as Dictionary).has(biome), "%s in %s has a name of its own" % [row["id"], biome])
	var named := 0
	for lair: SimLair in sim.lairs.values():
		t.eq(lair.biome, String(sim.site_by_id[lair.id].get("biome", "")), "a lair knows its biome")
		named += 1
	t.check(named > 0, "lairs on a real world (%d)" % named)

func _labels(t: TestLog) -> void:
	var town := Rect2(100, 40, 60, 14)
	t.eq(MapLogic.free_row(Rect2(0, 0, 40, 16), [town], [0.0, 16.0]), 0.0, "a label in the clear stays")
	t.eq(MapLogic.free_row(Rect2(110, 38, 40, 16), [town], [0.0, 16.0, 32.0]), 16.0, "a label on a town's moves off it")
	t.check(is_nan(MapLogic.free_row(Rect2(110, 38, 40, 16), [Rect2(0, 0, 400, 400)], [0.0, 16.0])), "and is dropped when nothing clears")
	t.eq(MapLogic.fit_x(-200.0, 60.0, 800.0), 6.0, "a label past the map's edge is held inside it")
	t.eq(MapLogic.fit_x(400.0, 60.0, 800.0), 370.0, "and one on the map stays centred")

## Water in the swamp on real worlds, a road through it at wading depth, and its path on the bed.
func _water(t: TestLog) -> void:
	var water := TileDefs.id("water")
	for sd: int in [1, 4, 15]:
		var w := WorldGen.generate_named("dev", sd)
		var seg: Dictionary = {}
		for s: Dictionary in w.meta["biomes"]:
			if s["biome"] == "swamp":
				seg = s
		var wet := 0
		for x in range(int(seg["x0"]), int(seg["x1"]) + 1):
			for y in range(int(w.meta["surface"][x]) - 2, int(w.meta["surface"][x]) + 3):
				if w.get_fg(x, y) == water:
					wet += 1
					break
		t.check(wet >= 5, "dev seed %d's swamp has open water (%d columns of %d)" % [sd, wet, int(seg["x1"]) - int(seg["x0"]) + 1])
		var floorless := 0
		var deep := 0
		for r: Dictionary in w.meta["routes"]:
			if r["kind"] != "road":
				continue
			var path := Places.route_path(w, int(r["id"]))
			for c: Vector2i in path:
				if c.x >= int(seg["x0"]) and c.x <= int(seg["x1"]):
					var under := w.get_fg(c.x, c.y - 1)
					if under == water:
						deep += 1
					elif TileDefs.solid[under] == 0 and TileDefs.platform[under] == 0 and TileDefs.ladder[under] == 0:
						floorless += 1
		t.eq(floorless, 0, "dev seed %d: a road through a swamp stands on something" % sd)
		t.eq(deep, 0, "and wades, it does not swim")
		var a := WorldGen.generate_named("dev", sd)
		t.eq(a.content_hash(), w.content_hash(), "dev seed %d: still a pure function of the seed" % sd)

## A remote player and a Synty NPC carry a weapon in the look ENT_ADD gave them, before any SWING.
func _wield(t: TestLog) -> void:
	var w := WorldGen.generate(1024, 512, 5)
	var rig := Rig.new(w, 0.0)
	Systems.install_host(rig.host)
	(rig.host.system(HostSystem.MONSTERS) as MonstersSystem).director_enabled = 0
	rig.add_client("ann")
	rig.add_client("bob")
	for c: ClientEndpoint in rig.clients:
		c.player_class = "fighter"
		c.welcomed.connect(func(cw: ClientWorld) -> void: Systems.install_client(cw))
	rig.until(func() -> bool: return rig.cw(0) != null and rig.cw(1) != null and rig.cw(1).area_ready() and rig.cw(0).area_ready(), 10.0)
	var ms: MonstersSystem = rig.host.system(HostSystem.MONSTERS)
	var at := rig.host_entity(0).body.pos + Vector2(4, 0)
	var bandit: HostEntity = ms.spawn("bandit", at, {})
	t.check(bandit != null, "a bandit spawns")
	rig.run(1.0)
	var bob_id := rig.host_entity(1).id
	t.check(rig.cw(0).remotes.has(bob_id), "ann sees bob")
	if rig.cw(0).remotes.has(bob_id):
		var look: Dictionary = rig.cw(0).remotes[bob_id].look
		t.check(not Looks.weapon(String(look.get("wield", ""))).is_empty(), "with his weapon, before any swing (%s)" % look.get("wield", ""))
	if bandit != null and rig.cw(0).remotes.has(bandit.id):
		var names := String(rig.cw(0).remotes[bandit.id].look.get("wield", "")).split(", ", false)
		t.check(Array(names).any(func(n: String) -> bool: return not Looks.weapon(n).is_empty()), "and the bandit with hers (%s)" % [names])
	else:
		t.check(false, "ann sees the bandit")
