## Peoples below (M6 track 2): the drow, duergar, deep gnomes, kobolds and goblins as cultures with
## homes in the Underdark, their people built from SRD NPC stat blocks with make_npc, their towns,
## deep roads as trade, and how they meet players. docs/tracks/peoples-below.md.
extends RefCounted

const DEEP := ["drow", "duergar", "deep_gnome", "kobold", "goblinoid"]
const ROLES := ["townsfolk", "guard", "merchant", "smith", "priest", "mage", "raider", "scout"]
const TEMPERS := ["trader", "expansionist", "raider", "isolationist"]

func run(t: TestLog) -> void:
	for f: String in ["_cultures", "_homes", "_roles", "_names", "_economy", "_kits", "_town", "_deep_trade", "_ways", "_stance"]:
		if not has_method(f):
			continue
		var t0 := Time.get_ticks_msec()
		call(f, t)
		print("  %s: %d ms" % [f, Time.get_ticks_msec() - t0])

## The heaviest biome weights of a culture, best first.
static func _top(cid: String, n: int) -> Array:
	var b: Dictionary = SimData.culture(cid).biomes
	var keys := b.keys()
	keys.sort_custom(func(x: String, y: String) -> bool: return float(b[x]) > float(b[y]) or (b[x] == b[y] and x < y))
	return keys.slice(0, n)

# --- 1. cultures --------------------------------------------------------------------------------

## Every people's tables speak the biome vocabulary and the goods table; the deep peoples' homes
## are underground, where the brief puts them.
func _cultures(t: TestLog) -> void:
	SimData.ensure()
	for cid: String in SimData.culture_ids:
		var c: Dictionary = SimData.cultures[cid]
		for b: String in c.biomes:
			t.check(BiomeIds.has(b), "%s weighs canonical biome %s" % [cid, b])
		for key: String in ["makes", "wants"]:
			for g: String in c.get(key, {}):
				t.check(SimData.goods.has(g), "%s %s a good that exists: %s" % [cid, key, g])
				t.check(float(c[key][g]) > 0.0, "%s %s %s by a positive factor" % [cid, key, g])
		for k: String in c.temperament:
			t.check(k in TEMPERS, "%s temperament %s is one the sim's wars know" % [cid, k])
	for cid: String in DEEP:
		t.check(SimData.cultures.has(cid), "%s is a culture" % cid)
		t.check("deeps" in (SimData.culture(cid).bands as Array), "%s settles the deeps" % cid)
		for b: String in _top(cid, 1 if cid == "goblinoid" else 2):
			t.eq(BiomeIds._rows[b]["family"], "underground", "%s's best land is underground (%s)" % [cid, b])
		t.check(SimData.is_deep(cid) or cid == "goblinoid", "%s is a people of the deep" % cid)
	t.eq(_top("drow", 2), ["underdark", "fungal"], "drow: the underdark and the fungal forests")
	var duergar := _top("duergar", 2)
	duergar.sort()
	t.eq(duergar, ["crystal", "magma"], "duergar: crystal caverns and magma")
	var gnome := _top("deep_gnome", 2)
	gnome.sort()
	t.eq(gnome, ["caves", "crystal"], "deep gnomes: crystal caverns and caves")
	var kob := _top("kobold", 2)
	kob.sort()
	t.eq(kob, ["caves", "magma"], "kobolds: magma and caves")
	t.eq(_top("goblinoid", 1), ["caves"], "goblins: the caves")
	# what they make: the brief's goods, all real goods
	t.check(SimData.make_f("drow", "reagents") > 1.0 and SimData.make_f("drow", "crystal") > 1.0, "drow make reagents and crystal")
	t.check(SimData.make_f("duergar", "ore") > 1.0 and SimData.make_f("duergar", "stone") > 1.0, "duergar make ore and stone")
	t.check(SimData.make_f("deep_gnome", "crystal") > 1.0, "deep gnomes make crystal")
	t.check(SimData.make_f("kobold", "ore") > 1.0, "kobolds make ore")
	t.check(SimData.want_f("drow", "food") > 1.0 and SimData.want_f("drow", "timber") > 1.0, "drow want grain and timber")
	t.eq(SimData.make_f("human", "ore"), 1.0, "a people that names nothing makes as its land gives")
	t.check(SimData.goods.has("crystal") and SimData.raw_goods.has("crystal"), "crystal is a raw good")
	# duergar and deep gnomes are dwarves and gnomes: SRD 5.2.1 has no lineage for them
	t.eq(SimData.culture("duergar").species, "dwarf", "duergar are dwarves")
	t.eq(SimData.culture("deep_gnome").species, "gnome", "deep gnomes are gnomes")
	t.check(not SimData.monsters.has("duergar") and not SimData.monsters.has("deep-gnome"), "SRD 5.2.1 has no duergar or deep gnome stat block")
	t.eq(Life.people_key("duergar", "guard", "warrior-infantry"), "dwarf:deep:guard", "a duergar guard is drawn as a dwarf of the deep")
	t.eq(Life.people_key("drow", "guard", "warrior-infantry"), "elf:drow:guard", "a drow guard keeps the lineage key")
	t.eq(Life.people_key("dwarf", "guard", "guard"), "dwarf:guard", "a dwarf of the surface is unchanged")
	t.eq(Looks.resolve({"people": "dwarf:deep:guard"})["key"], "people:dwarf:deep:guard", "and has a look row")
	t.eq(Looks.resolve({"people": "gnome:deep:nonesuch"})["key"], "people:gnome:deep", "a deep gnome's unknown role falls back to the deep row")

## Over many draws, deep sites go to the peoples their land suits: underdark by its weights today,
## and each underground biome by its own once worldgen makes them.
func _homes(t: TestLog) -> void:
	BiomeIds.ensure()
	var sim := WorldSim.synthetic(24, 3)
	var picks := {}
	for b: String in ["underdark", "fungal", "crystal", "magma", "caves", "deep_lake"]:
		picks[b] = {}
		for i in 600:
			var c: String = sim._pick_culture({"biome": b, "band": "deeps"}, "")
			picks[b][c] = int(picks[b].get(c, 0)) + 1
		for c: String in picks[b]:
			t.check(SimData.culture(c).bands.has("deeps"), "%s on %s settles the deeps" % [c, b])
	print("  deep picks: %s" % [picks])
	var most := func(b: String) -> String:
		var best := ""
		for c: String in picks[b]:
			if best == "" or int(picks[b][c]) > int(picks[b][best]):
				best = c
		return best
	t.eq(most.call("underdark"), "drow", "the drow hold the underdark")
	t.eq(most.call("fungal"), "drow", "and the fungal forests")
	t.eq(most.call("magma"), "duergar", "duergar hold the magma")
	t.check(most.call("crystal") in ["duergar", "deep_gnome"], "duergar and deep gnomes the crystal caverns (%s)" % most.call("crystal"))
	t.check(int(picks.crystal.get("deep_gnome", 0)) > int(picks.crystal.get("drow", 0)), "deep gnomes before drow in the crystal")
	t.check(int(picks.magma.get("kobold", 0)) > int(picks.underdark.get("kobold", 0)), "kobolds to the magma")
	t.eq(int(picks.underdark.get("dwarf", 0)), 0, "dwarves of the surface leave the deeps to the duergar")
	# a real world: every deep settlement is a deep people, on the biome its site has
	var w := WorldGen.generate(1024, 512, 5)
	var host := WorldSim.from_meta(w.meta, 5)
	var deep_n := 0
	for sid: int in host.settlements:
		var s: SimSettlement = host.settlements[sid]
		if s.band == "surface":
			continue
		deep_n += 1
		var site: Dictionary = host.site_by_id[sid]
		t.eq(BiomeIds._rows[String(site.biome)]["family"], "underground", "deep site %d has an underground biome (%s)" % [sid, site.biome])
		t.check(SimData.culture(s.culture).bands.has("deeps"), "%s at deep site %d settles the deeps" % [s.culture, sid])
	t.check(deep_n > 0, "the world has deep settlements (%d)" % deep_n)

# --- roles: make_npc for every people -----------------------------------------------------------

func _roles(t: TestLog) -> void:
	var srd := WorldHost.shared_srd()
	for cid: String in DEEP:
		var c: Dictionary = SimData.culture(cid)
		for role: String in ROLES:
			var slug := Life.role_slug(cid, role)
			t.check(SimData.has_monster(slug), "%s %s is SRD stat block %s" % [cid, role, slug])
			var npc: Combatant = srd.make_npc(slug, String(c.species), String(c.lineage))
			t.check(npc != null, "%s %s builds" % [cid, role])
			if npc == null:
				continue
			var dv := int(npc.senses.get("darkvision", 0))
			match cid:
				"drow":
					t.eq(dv, 120, "drow %s: Darkvision 120 ft (Drow lineage)" % role)
					t.check(npc.name.begins_with("Drow "), "named as a drow (%s)" % npc.name)
				"duergar":
					t.eq(dv, 120, "duergar %s: a dwarf's Darkvision 120 ft" % role)
					t.check(npc.stats.has_resistance(SRD.DamageType.POISON), "duergar %s: Dwarven Resilience" % role)
				"deep_gnome":
					t.eq(dv, 60, "deep gnome %s: a gnome's Darkvision 60 ft" % role)
					t.eq(npc.size, "small", "deep gnome %s is Small" % role)
				"kobold":
					t.eq(dv, 60, "kobold %s: Darkvision 60 ft (its block)" % role)
				"goblinoid":
					t.check(dv >= 60, "goblin %s: Darkvision (its block)" % role)
	# Sunlight Sensitivity where SRD 5.2.1 gives it: the Kobold Warrior's block; the 5.2.1 Drow
	# lineage gives Darkvision 120 and Dancing Lights, not Sunlight Sensitivity.
	var kob: Dictionary = srd.pack.get_row("monster", "kobold-warrior")
	var traits: Array = (kob.get("data", {}).get("traits", []) as Array).map(func(x: Dictionary) -> String: return String(x.get("name", "")))
	t.check("Sunlight Sensitivity" in traits, "the kobold warrior's block has Sunlight Sensitivity")
	var elf: Dictionary = srd.pack.get_row("species", "elf")
	t.check(not JSON.stringify(elf).contains("Sunlight Sensitivity"), "the SRD 5.2.1 elf (and its Drow lineage) has none")
	# the town's people take their roles from the culture
	t.eq(Life.role_slug("drow", "priest"), "priest", "a drow priest is the Priest block")
	t.eq(Life.role_slug("drow", "merchant"), "noble", "a drow merchant is the Noble block")
	t.eq(Life.role_slug("human", "priest"), "priest-acolyte", "a human priest is still an acolyte")
	t.eq(Life.role_slug("human", "keeper"), "commoner", "and a human keeper a commoner")
	t.eq(Life.role_slug("gnoll", "priest"), "hyena", "a monstrous people with no table uses its people block")
	t.check("mage" in Life.first_roles("drow", "city"), "a drow city shows its mages")
	t.eq(Life.first_roles("human", "town"), Life.people_cfg()["first_roles"]["town"], "others show the default roles")

# --- names --------------------------------------------------------------------------------------

func _names(t: TestLog) -> void:
	for cid: String in ["duergar", "deep_gnome"]:
		t.check(SimData.names.has(cid), "%s has a name syllable set" % cid)
		var r := RandomNumberGenerator.new()
		r.seed = 7
		var n := SimNames.make(r, cid, {})
		t.check(n.length() >= 3, "%s name: %s" % [cid, n])
	var blob := (JSON.stringify(SimData.names) + FileAccess.get_file_as_string("res://data/setting/names.json")).to_lower()
	for bad in ["menzo", "gracklstugh", "blingden", "svirf", "ched nasad", "ust natha", "eryndlyn", "sschind", "llurth"]:
		t.check(not blob.contains(bad), "names avoid '%s'" % bad)
	for cid: String in DEEP:
		var title := SimNames.title(cid, "Zaerrith")
		t.check(title.contains("Zaerrith") and title != "Zaerrith", "%s settlements below have a style: %s" % [cid, title])
		t.eq(SimNames.title(cid, "Zaerrith"), title, "the same name gets the same title")
	t.eq(SimNames.title("drow", "Zaerrith", "surface"), "Zaerrith", "a surface settlement is just its name")
	t.eq(SimNames.kind_word("drow"), "city", "drow live in cities")
	t.eq(SimNames.kind_word("duergar"), "hold", "duergar in holds")
	t.eq(SimNames.kind_word("deep_gnome"), "warren", "deep gnomes in warrens")

# --- goods: what they make and want -------------------------------------------------------------

## A town of a people that makes a good holds more of it and sells it cheaper; what it wants it
## keeps more of and pays more for; crystal is cut into fine goods before ore is.
func _economy(t: TestLog) -> void:
	var sites := [{"id": 0, "kind": "settlement", "x": 100, "y": 150, "biome": "underdark", "band": "deeps", "size": 2},
		{"id": 1, "kind": "settlement", "x": 600, "y": 150, "biome": "underdark", "band": "deeps", "size": 2}]
	var sim := WorldSim.new()
	sim._setup(sites, [{"id": 0, "a": 0, "b": 1, "kind": "deep_road", "length": 500}], 3, 1000.0)
	sim.settlements.clear()
	sim.factions.clear()
	var fa := sim._new_faction("drow")
	var fb := sim._new_faction("duergar")
	var drow := sim._new_settlement(0, "drow", fa.id, 400)
	var dg := sim._new_settlement(1, "duergar", fb.id, 400)
	t.check(float(drow.land.reagents) > float(SimData.biomes.underdark.reagents), "the drow's land gives them more reagents")
	t.eq(float(SimData.biomes.underdark.reagents), 0.7, "and the biome's own row is untouched")
	t.check(drow.cap.reagents > dg.cap.reagents, "a drow town yields more reagents than a duergar one on the same rock")
	t.check(dg.cap.ore > drow.cap.ore, "and the duergar more ore")
	t.check(SimEconomy.target(drow, "timber") > SimEconomy.target(dg, "timber") * 1.2, "the drow keep more timber in store")
	drow.stock.reagents = SimEconomy.target(drow, "reagents")
	dg.stock.reagents = SimEconomy.target(dg, "reagents")
	t.check(SimEconomy.price(drow, "reagents") < SimEconomy.price(dg, "reagents"), "reagents are cheaper among the drow")
	# crystal before ore: the same town with and without crystal in store
	drow.stock.crystal = 50.0
	drow.stock.ore = 50.0
	drow.stock.luxuries = 0.0
	var twin := SimSettlement.from_dict(drow.to_dict())
	sim._derive_settlement(twin)
	twin.stock.crystal = 0.0
	drow.cap["crystal"] = 0.0          # none dug this tick: what is cut is what was in store
	twin.cap["crystal"] = 0.0
	var pop0 := drow.pop()
	SimEconomy._tick_settlement(sim, drow, WorldSim.ECON_DAYS)
	SimEconomy._tick_settlement(sim, twin, WorldSim.ECON_DAYS)
	t.check(drow.stock.luxuries > 0.0 and is_equal_approx(drow.stock.luxuries, twin.stock.luxuries), "fine goods are made with crystal or without")
	t.check(drow.stock.crystal < 50.0, "with it, from crystal")
	var spared: float = drow.stock.ore - twin.stock.ore
	var worn := pop0 * float(SimData.goods.crystal.use) * WorldSim.ECON_DAYS / WorldSim.YEAR_DAYS
	t.check(spared > 0.05, "and the ore it would have taken stays in the heap (%.3f)" % spared)
	t.check(absf((50.0 - drow.stock.crystal) - (spared + worn)) < 0.001, "crystal cut for it, ore for ore, besides what lamps wear (%.3f = %.3f + %.3f)" % [50.0 - drow.stock.crystal, spared, worn])
	# relations: the drow are estranged from everyone, as before; duergar and deep gnomes are not
	t.eq(sim._base_relation(fa, fb) - (-10.0 if fa.temperament == "raider" or fb.temperament == "raider" else 0.0), -20.0, "drow and duergar start estranged")
	var fg := sim._new_faction("deep_gnome")
	var fh := sim._new_faction("human")
	t.eq(sim._base_relation(fg, fh), -10.0 if "raider" in [fg.temperament, fh.temperament] else 0.0, "deep gnomes and humans start even")

# --- 2. deep settlements are real towns ---------------------------------------------------------

## A cave: solid rock with a cavern 16 rows high over a floor at y0 - 1, open from x 4 to w - 4.
static func cave_world(w: int, h: int, y0: int) -> TileWorld:
	var world := TileWorld.new(w, h, 1)
	var stone := TileDefs.id("stone")
	var wall := TileDefs.wall_id("stone_wall")
	for x in w:
		for y in h:
			var open := x >= 4 and x < w - 4 and y >= y0 and y < y0 + 16
			world.set_fg(x, y, TileDefs.AIR if open else stone, true)
			world.set_bg(x, y, wall, true)
	return world

static func apply_writes(world: TileWorld, wr: Dictionary) -> void:
	var cells: PackedInt32Array = wr["cells"]
	for i in range(0, cells.size(), 4):
		if not world.in_bounds(cells[i], cells[i + 1]):
			continue
		if cells[i + 2] >= 0:
			world.set_fg(cells[i], cells[i + 1], cells[i + 2], true)
		if cells[i + 3] >= 0:
			world.set_bg(cells[i], cells[i + 1], cells[i + 3], true)

## Each people's town below, built from its kit in a dark cave: its own style, an emissive lamp,
## its pieces from the dungeon packs, and its street lit by its lamps alone.
func _kits(t: TestLog) -> void:
	PlaceStyles.ensure()
	Dressing.ensure()
	var styles := {}
	for cid: String in DEEP:
		var sn := PlaceStyles.style_for(cid, "deeps")
		styles[sn] = true
		var st := PlaceStyles.style(sn)
		var lamp := int(st["ids"]["lamp"])
		t.check(TileDefs.emit[lamp] > 0, "%s (%s) lights its town with an emissive tile (%s)" % [cid, sn, st["palette"]["lamp"]])
		var kit := String(st["kit"])
		t.check(PlaceStyles.kit(kit).size() > 0, "%s builds with kit %s" % [cid, kit])
		var world := cave_world(448, 64, 20)
		var site := {"id": 1, "x": 210, "y": 20, "band": "deeps", "kind": "settlement"}
		var place := PlaceBuilder.plan(site, cid, 9, 6, 441)
		t.eq(String(place.get("style", "")), sn, "%s's place is in its style" % cid)
		place["tier"] = "town"
		var pieces := 0
		for i in (place["lots"] as Array).size():
			if PlaceBuilder.lot_wanted(place["lots"][i], "town"):
				var wr := PlaceBuilder.set_lot(place, i, "built", 9)
				apply_writes(world, wr)
				for o: Array in wr["objects"]:
					pieces += 1
					t.check(Dressing.id(Dressing.name_of(int(o[0]))) == int(o[0]), "a %s piece is a dressing id" % cid)
		PlaceBuilder.refresh_buildings(place)
		t.check(pieces >= 4, "%s's town is furnished from its kit (%d pieces)" % [cid, pieces])
		var light := LightEngine.new(world)
		light.sun = 1.0
		var st_row: Array = place["street"]
		var lit := 0
		var n := 0
		# the built town: its buildings and the street beside them (lots of a higher tier are
		# still empty ground, dark as any cave)
		var cols := {}
		for lot: Dictionary in place["lots"]:
			if String(lot["state"]) == "built":
				for x in range(int(lot["x"]) - 2, int(lot["x"]) + int(lot["w"]) + 2):
					cols[x] = true
		for x: int in cols:
			n += 1
			if light.category_at(x, int(st_row[2]) + 1) != LightEngine.Category.DARK:
				lit += 1
		var sky := 0
		for x in range(int(st_row[0]), int(st_row[1]) + 1):
			sky = maxi(sky, light.sky_at(x, int(st_row[2]) + 1))
		t.eq(sky, 0, "no sun reaches the %s town" % cid)
		print("  %s town: %d of %d street columns of the built town lit by its lamps, %d pieces" % [cid, lit, n, pieces])
		t.check(lit * 20 >= n * 19, "%s: its street is lit by its own lamps (%d of %d columns)" % [cid, lit, n])
		var dark_world := cave_world(448, 64, 20)
		var dl := LightEngine.new(dark_world)
		t.eq(dl.category_at(210, 21), LightEngine.Category.DARK, "the same cave unbuilt is dark")
	t.check(styles.size() == DEEP.size(), "every deep people builds in its own style (%s)" % [styles.keys()])
	t.eq(PlaceStyles.style_for("goblinoid", "surface"), "raider", "goblins on the surface still camp in tents")

## A generated world's drow city and duergar hold: people at their posts on the real place, lit,
## a shop with the people's goods, a smith, work, and lines of their own.
func _town(t: TestLog) -> void:
	# dev 27 (was 4: with the underground regions of M6 track deep, dev 4's second deep town
	# stands in a fungal region and its people are kobolds)
	var w := WorldGen.generate_named("dev", 27)
	var host := WorldHost.new(w)
	Dice.rng = host.rng
	host.add_system(CombatSystem.new())
	var ms := MonstersSystem.new()
	ms.director_enabled = 0
	ms.lairs_enabled = false
	ms.nav_fixed_slices = 8
	host.add_system(ms)
	var life := LifeSystem.new()
	host.add_system(life)
	var seen := {}
	for sid: int in WorldSim._sorted_keys(host.sim.settlements):
		var s: SimSettlement = host.sim.settlements[sid]
		if s.band == "surface" or Places.place(w, sid).is_empty():
			continue
		seen[s.culture] = true
		var place := Places.place(w, sid)
		t.eq(String(place["style"]), PlaceStyles.style_for(s.culture, "deeps"), "%s's town %s is built in its style" % [s.culture, s.name])
		var p := host.add_player("visitor%d" % sid, sid + 2, {"class": "fighter"})
		p.body.pos = LifeTown.site_pos(host, sid) + Vector2(0, 2)
		TileCollision.depenetrate(host.world, p.body)
		for i in 70:
			host.tick()
		t.check(life.town.active.has(sid) and s.watched, "%s %s materializes" % [s.culture, s.name])
		var people := life.actors_at(sid)
		var roles := {}
		for e: HostEntity in people:
			roles[String(e.get_meta("sim")["role"])] = true
		t.check(roles.has("keeper") and roles.has("merchant") and roles.has("guard"), "%s %s has a keeper, a merchant and guards (%s)" % [s.culture, s.name, roles.keys()])
		var light := LightEngine.new(w)
		var x0 := int(place["street"][0])
		var x1 := int(place["street"][1])
		var dark := 0
		var outside := 0
		var stuck := 0
		for e: HostEntity in people:
			var c := Vector2i(floori(e.body.pos.x), floori(e.body.pos.y) + 1)
			if light.category_at(c.x, c.y) == LightEngine.Category.DARK:
				dark += 1
			if c.x < x0 - 2 or c.x > x1 + 2:
				outside += 1
			if w.is_solid(c.x, c.y):
				stuck += 1
		t.eq(stuck, 0, "nobody in %s stands in a wall" % s.name)
		t.eq(outside, 0, "everyone in %s is on its street" % s.name)
		t.check(dark * 10 <= people.size(), "the people of %s stand in lamplight (%d of %d in the dark)" % [s.name, dark, people.size()])
		var look_ok := true
		for e: HostEntity in people:
			if not SimData.culture(s.culture).monstrous and String(e.look.get("people", "")) == "":
				look_ok = false
		t.check(look_ok, "%s's people are drawn as their people" % s.culture)
		t.check(DealsShop.has_store(w, sid) or DealsShop.has_smithy(w, sid), "%s has a store or a smithy (a village has one, a town both)" % s.name)
		var made := ""
		var best := 0.0
		for g: String in SimData.makes.get(s.culture, {}):
			if float(SimData.makes[s.culture][g]) > best:
				best = float(SimData.makes[s.culture][g])
				made = g
		var shelf_goods := {}
		for l: Dictionary in DealsShop.shelves(host.sim, sid):
			if int(l["n"]) > 0:
				shelf_goods[String(l["good"])] = true
		t.check(shelf_goods.has(made), "%s's store sells what they make, %s (%s)" % [s.name, made, shelf_goods.keys()])
		var rack := DealsShop.rack(host.sim, w.world_seed, sid, 0, {})
		t.check(rack.size() > 0, "and its smith has a rack (%d)" % rack.size())
		var offers := DealsQuests.offers(host.sim, w.world_seed, sid, 0)
		t.check(offers.size() > 0, "and work on offer (%d)" % offers.size())
		var own: Array = Deals.lines()["culture"].get(s.culture, [])
		var said := false
		for hr in 24:
			for d in 6:
				var ln := DealsTalk.line(host.sim, w.world_seed + d, {"id": "x%d" % d, "role": "keeper", "name": "K", "culture": s.culture}, sid, float(hr))
				for o: String in own:
					if ln.contains(o):
						said = true
		t.check(said, "%s talk with lines of their own" % s.culture)
		host.remove_entity(p.id)
		for i in 5:
			host.tick()
	t.check(seen.has("drow") and seen.has("duergar"), "dev 27 holds a drow and a duergar town (%s)" % [seen.keys()])

# --- 3. deep roads as trade ---------------------------------------------------------------------

## A drow city and a duergar hold on one deep road, the drow linked up to a human town: who sends
## what where, and the books of one caravan.
static func deep_world(seed: int) -> Dictionary:
	var sites := [
		{"id": 0, "kind": "settlement", "x": 300, "y": 700, "biome": "meadow", "band": "surface", "size": 3},
		{"id": 1, "kind": "settlement", "x": 600, "y": 150, "biome": "underdark", "band": "deeps", "size": 3},
		{"id": 2, "kind": "settlement", "x": 1100, "y": 150, "biome": "underdark", "band": "deeps", "size": 3}]
	var routes := [{"id": 0, "a": 1, "b": 2, "kind": "deep_road", "length": 600},
		{"id": 1, "a": 1, "b": 0, "kind": "deep_road", "length": 700}]
	var sim := WorldSim.new()
	sim._setup(sites, routes, seed, 1600.0)
	sim.settlements.clear()
	sim.factions.clear()
	var fh := sim._new_faction("human")
	var fd := sim._new_faction("drow")
	var fg := sim._new_faction("duergar")
	fh.temperament = "trader"
	fd.temperament = "trader"
	fg.temperament = "trader"
	var town := sim._new_settlement(0, "human", fh.id, 900)
	var city := sim._new_settlement(1, "drow", fd.id, 900)
	var hold := sim._new_settlement(2, "duergar", fg.id, 900)
	for f: SimFaction in [fh, fd, fg]:
		f.capital = {fh: 0, fd: 1, fg: 2}[f]
		for g: SimFaction in [fh, fd, fg]:
			if f != g:
				f.relations[g.id] = sim._base_relation(f, g)
	return {"sim": sim, "town": town, "city": city, "hold": hold}

func _deep_trade(t: TestLog) -> void:
	var d := deep_world(11)
	var sim: WorldSim = d["sim"]
	var city: SimSettlement = d["city"]
	var hold: SimSettlement = d["hold"]
	t.eq(int(sim.route_by_id[0].cls), WorldSim.DEEP, "the road between the deep towns is a deep road")
	t.eq(int(sim.route_by_id[1].cls), WorldSim.LINK, "the way up is a link")
	t.check(sim.factions[city.faction].rel(hold.faction) < -15.0, "drow and duergar have no love for each other (%.0f)" % sim.factions[city.faction].rel(hold.faction))
	# one caravan, every unit and coin accounted for (once the city has something to spare)
	sim.step(WorldSim.YEAR_H)
	var p: SimParty = null
	var stock0: Dictionary = {}
	for tries in 40:
		var had := {}
		for pid in sim.parties:
			had[pid] = true
		SimEconomy.build_market(sim)
		stock0 = city.stock.duplicate()
		SimEconomy._plan_caravan(sim, city)
		for pid in sim.parties:
			if not had.has(pid) and sim.parties[pid].kind == "caravan" and sim.parties[pid].home == city.id:
				p = sim.parties[pid]
		if p != null:
			break
		sim.step(WorldSim.ECON_H)
	t.check(p != null, "the drow send a caravan")
	if p != null:
		var good := String(p.plan["good"])
		print("  a drow caravan: %s %d to %s" % [good, int(p.cargo[good]), sim.settlements[p.dest].name])
		t.check(is_equal_approx(float(stock0[good]) - float(city.stock[good]), float(p.cargo[good])), "what it carries left the city's stores")
		var dst: SimSettlement = sim.settlements[p.dest]
		var dstock: Dictionary = dst.stock.duplicate()
		var dwealth := dst.wealth
		var cargo0: Dictionary = p.cargo.duplicate()
		var coin0 := p.coin
		p.path = [city.id, dst.id] as Array[int]
		p.leg = 0
		SimEconomy.caravan_arrive(sim, p)
		var ok := true
		for g: String in SimData.good_names:
			var moved := (float(dst.stock[g]) - float(dstock[g])) + (float(p.cargo.get(g, 0)) - float(cargo0.get(g, 0)))
			if absf(moved) > 0.001:
				ok = false
				print("  %s: %.3f unaccounted" % [g, moved])
		t.check(ok, "at market every unit sold or bought is in one store or the other")
		t.check(absf((dwealth - dst.wealth) - (p.coin - coin0)) < 0.01, "and every coin (%.1f paid, %.1f taken)" % [dwealth - dst.wealth, p.coin - coin0])
		t.check(p.coin > coin0, "the caravan sold its load")
		var back: Dictionary = p.cargo.duplicate()
		var cstock: Dictionary = city.stock.duplicate()
		var cwealth := city.wealth
		var coin1 := p.coin
		p.path = [dst.id, city.id] as Array[int]
		p.leg = 0
		p.plan["leg"] = "home"
		SimEconomy.return_home(sim, p)
		var home_ok := true
		for g: String in back:
			home_ok = home_ok and is_equal_approx(float(city.stock[g]) - float(cstock[g]), float(back[g]))
		t.check(home_ok, "home again, the return load is in the city's stores (%s)" % [back])
		t.check(is_equal_approx(city.wealth - cwealth, coin1), "and the takings in its treasury")
	t.eq(sim.audit(), [] as Array[String], "the books balance")
	# ten years: the deep road and the way up carry what each side makes to who wants it
	d = deep_world(5)
	sim = d["sim"]
	sim.ledger_on = true
	sim.step(10 * WorldSim.YEAR_H)
	var deep_row: Dictionary = sim.ledger.get(0, {})
	var link_row: Dictionary = sim.ledger.get(1, {})
	print("  deep road: %d trips, %d coin, %s" % [int(deep_row.get("trips", 0)), int(deep_row.get("value", 0.0)), deep_row.get("goods", {})])
	print("  link: %d trips, %d coin, %s" % [int(link_row.get("trips", 0)), int(link_row.get("value", 0.0)), link_row.get("goods", {})])
	t.check(int(deep_row.get("trips", 0)) >= 5, "caravans go along the deep road (%d trips)" % int(deep_row.get("trips", 0)))
	t.check(int(link_row.get("trips", 0)) >= 5, "and up the way to the surface (%d trips)" % int(link_row.get("trips", 0)))
	var up := 0
	var down := 0
	var below := 0
	for k: String in sim.flows:
		var part := k.split("|")
		var units := int(sim.flows[k][0])
		if part[1] == "underdark" and part[2] == "meadow" and part[0] in ["ore", "reagents", "crystal", "stone"]:
			up += units
		if part[1] == "meadow" and part[2] == "underdark" and part[0] in ["food", "timber"]:
			down += units
		if part[1] == "underdark" and part[2] == "underdark" and part[0] in ["ore", "reagents", "crystal", "stone", "food", "timber", "tools", "luxuries"]:
			below += units
	t.check(up > 0, "the surface gets ore, reagents or crystal from below (%d units)" % up)
	t.check(down > 0, "and the deep peoples grain or timber from above (%d units)" % down)
	t.check(below > 0, "and the deep towns trade with each other (%d units)" % below)
	t.eq(sim.audit(), [] as Array[String], "ten years on the books still balance")
	var shares := SimHealth.route_shares(sim)
	t.eq(int(shares.deep.routes), 1, "the sweep counts the deep road")
	t.eq(int(shares.link.routes), 1, "and the link")
	t.eq(int(shares.deep.trips), int(deep_row.get("trips", 0)), "with its trips")

## A way down worldgen knows of (meta.ways, the descent track's seam) is a link the sim's
## caravans can use; one that joins towns a route already joins adds nothing.
func _ways(t: TestLog) -> void:
	var sites := [
		{"id": 0, "kind": "settlement", "x": 300, "y": 700, "biome": "meadow", "band": "surface", "size": 2},
		{"id": 1, "kind": "settlement", "x": 1500, "y": 700, "biome": "forest", "band": "surface", "size": 2},
		{"id": 2, "kind": "settlement", "x": 600, "y": 150, "biome": "underdark", "band": "deeps", "size": 2},
		{"id": 3, "kind": "settlement", "x": 1400, "y": 150, "biome": "fungal", "band": "deeps", "size": 2}]
	var routes := [{"id": 0, "a": 0, "b": 1, "kind": "road", "length": 1300}, {"id": 1, "a": 2, "b": 3, "kind": "deep_road", "length": 900},
		{"id": 2, "a": 2, "b": 0, "kind": "deep_road", "length": 700}]
	var surface: Array = []
	surface.resize(2000)
	var meta := {"sites": sites, "routes": routes, "surface": surface,
		"ways": [{"kind": "sinkhole", "top": [1450, 690], "bottom": [1420, 160]}, {"kind": "cave", "top": [320, 690], "bottom": [580, 160]}]}
	var sim := WorldSim.from_meta(meta, 3)
	var links := 0
	var way: Dictionary = {}
	for r: Dictionary in sim.routes:
		if int(r.cls) == WorldSim.LINK:
			links += 1
		if r.has("way"):
			way = r
	t.eq(links, 2, "the ascent and the sinkhole: two links (%d)" % links)
	t.eq(String(way.get("way", "")), "sinkhole", "the new one names its way")
	t.check([int(way.get("a", -1)), int(way.get("b", -1))].has(3) and [int(way.get("a", -1)), int(way.get("b", -1))].has(1), "and joins the towns at its ends")
	var back := WorldSim.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	var kept := false
	for r: Dictionary in back.routes:
		kept = kept or String(r.get("way", "")) == "sinkhole"
	t.check(kept, "a save keeps it")
	var none := WorldSim.from_meta({"sites": sites, "routes": routes, "surface": surface}, 3)
	t.eq(none.routes.size(), sim.routes.size() - 1, "without ways the world is as before")

# --- 4. hostility and toll ----------------------------------------------------------------------

static func full_rig(seed: int) -> Dictionary:
	var w := WorldGen.generate_named("dev", seed)
	var host := WorldHost.new(w)
	Dice.rng = host.rng
	var out := {"host": host}
	out["rules"] = RulesSystem.new()
	host.add_system(out["rules"])
	(out["rules"] as RulesSystem).cheats = true
	out["combat"] = CombatSystem.new()
	host.add_system(out["combat"])
	out["items"] = ItemsSystem.new()
	host.add_system(out["items"])
	var ms := MonstersSystem.new()
	ms.director_enabled = 0
	ms.lairs_enabled = false
	ms.nav_fixed_slices = 8
	host.add_system(ms)
	out["ms"] = ms
	out["life"] = LifeSystem.new()
	host.add_system(out["life"])
	out["deals"] = DealsSystem.new()
	host.add_system(out["deals"])
	return out

static func player(host: WorldHost, name: String, pos: Vector2) -> HostEntity:
	var e := host.add_player(name, host.entities.size() + 2, {"class": "fighter"})
	e.body.pos = pos
	TileCollision.depenetrate(host.world, e.body)
	e.combatant.stats.max_hp = 9999
	e.combatant.stats.current_hp = 9999
	return e

static func first_of(host: WorldHost, culture: String) -> int:
	for sid: int in WorldSim._sorted_keys(host.sim.settlements):
		var s: SimSettlement = host.sim.settlements[sid]
		if s.culture == culture and s.band != "surface" and not Places.place(host.world, sid).is_empty():
			return sid
	return -1

func _stance(t: TestLog) -> void:
	var r := full_rig(27)       # was 4: see _town
	var host: WorldHost = r["host"]
	var life: LifeSystem = r["life"]
	var deals: DealsSystem = r["deals"]
	var city := first_of(host, "drow")
	var hold := first_of(host, "duergar")
	t.check(city >= 0 and hold >= 0, "dev 27 has a drow city and a duergar hold with places")
	if city < 0 or hold < 0:
		return
	var cs: SimSettlement = host.sim.settlements[city]
	var f := str(cs.faction)
	var place := Places.place(host.world, city)
	var street: Array = place["street"]
	var mid := Vector2((float(street[0]) + float(street[1])) / 2.0 + 0.5, float(street[2]))
	var span := life.town_span(city)
	var gate := Vector2(span.x + 2.5, float(street[2]))
	var p := player(host, "stranger", gate)
	for i in 70:
		host.tick()
	var people := life.actors_at(city)
	t.check(people.size() > 0, "the drow city is shown")
	var guard: HostEntity = null
	for e: HostEntity in people:
		if String(e.get_meta("sim")["role"]) == "guard" and guard == null:
			guard = e
	t.check(guard != null, "with guards")
	if guard == null:
		return
	var due := life.toll_due(p, city)
	t.eq(due, int(SimData.culture("drow").stance.toll.coin[cs.tier]), "a stranger owes the %s's toll (%d coin)" % [cs.tier, due])
	t.eq(life.stance(p, guard), Life.NEUTRAL, "at the gate the drow are neutral")
	t.eq(life.toll_due(p, hold), 0, "the duergar ask no toll")
	# past the gate unpaid: a grace to find a guard, then they turn
	p.body.pos = mid
	TileCollision.depenetrate(host.world, p.body)
	for i in K.TICK_HZ * 2:
		host.tick()
	t.check(life.inside_gate(city, p.body.pos), "the stranger is past the gate")
	t.eq(life.stance(p, guard), Life.NEUTRAL, "for a while they let it pass")
	for i in K.TICK_HZ * 21:
		host.tick()
	t.eq(life.stance(p, guard), Life.HOSTILE, "unpaid past the grace, the city turns on the stranger")
	p.body.pos = gate
	TileCollision.depenetrate(host.world, p.body)
	for i in K.TICK_HZ * 2:
		host.tick()
	t.eq(life.stance(p, guard), Life.NEUTRAL, "back at the gate, neutral again")
	for i in K.TICK_HZ * 15:          # the fight cools
		host.tick()
	# pay at the gate: talk to a guard there
	guard.body.pos = gate + Vector2(2.0, 0.0)
	TileCollision.depenetrate(host.world, guard.body)
	p.character.inventory.coin = 500
	var wealth0 := cs.wealth
	t.eq(deals.talk(p, guard.id), "", "the stranger talks to the guard")
	var ids: Array = deals.options(p, deals.talks[p.id]).map(func(o: Dictionary) -> String: return String(o["id"]))
	t.check("toll" in ids, "the guard asks the toll (%s)" % [ids])
	t.check(not "toll_favour" in ids, "no favour to call in at standing 0")
	t.eq(deals.choose(p, "toll"), "", "pays it")
	t.eq(p.character.inventory.coin, 500 - due, "the coin left the purse")
	t.check(absf(cs.wealth - (wealth0 + due)) < 0.01, "and went to the city (%.1f -> %.1f)" % [wealth0, cs.wealth])
	t.eq(life.toll_due(p, city), 0, "paid for the day")
	p.body.pos = mid
	TileCollision.depenetrate(host.world, p.body)
	for i in K.TICK_HZ * 25:
		host.tick()
	t.eq(life.stance(p, guard), Life.NEUTRAL, "paid, the stranger walks the city in peace")
	# trading in the city earns standing with it
	var seller: HostEntity = null
	var shop := "shop" if DealsShop.has_store(host.world, city) else "smith"
	for e: HostEntity in life.actors_at(city):
		var role := String(e.get_meta("sim")["role"])
		if (shop == "shop" and role == "merchant") or (shop == "smith" and role == "smith"):
			seller = e
	t.check(seller != null, "the city has someone to trade with (%s)" % shop)
	if seller != null:
		seller.body.pos = p.body.pos + Vector2(2.0, 0.0)
		TileCollision.depenetrate(host.world, seller.body)
		p.character.inventory.coin = 5000
		var st_before := life.standing(p.id, f)
		t.eq(deals.talk(p, seller.id), "", "the stranger talks to the %s" % seller.get_meta("sim")["role"])
		t.eq(deals.choose(p, shop), "", "and opens the %s" % shop)
		var spent := 0
		for l: Dictionary in deals.listings(p, city, "store" if shop == "shop" else "smith"):
			if int(l["n"]) > 0 and spent < 120 and int(l["price"]) <= 5000 - spent:
				if deals.buy(p, String(l["id"]), 1) == "":
					spent += int(l["price"])
		print("  bought %d coin in %s" % [spent, cs.name])
		t.eq(life.standing(p.id, f) - st_before, floori(spent * Life.num("trade_per_coin", 0.02)), "trade earns standing with the drow (%d coin)" % spent)
		deals.choose(p, "bye")
	var saved := life.save_player(p)
	host.sim.t += 2 * WorldSim.DAY_H
	t.check(life.toll_due(p, city) > 0, "two days on the toll is due again")
	host.sim.t -= 2 * WorldSim.DAY_H
	var p3 := player(host, "returning", gate)
	life.load_player(p3, saved)
	t.eq(life.toll_due(p3, city), 0, "a paid toll survives a save")
	# a favour instead of coin
	var p2 := player(host, "known", gate)
	life.add_standing(p2.id, f, 12, "test")
	guard.body.pos = p2.body.pos + Vector2(2.0, 0.0)
	TileCollision.depenetrate(host.world, guard.body)
	t.eq(deals.talk(p2, guard.id), "", "a known face talks to the guard")
	ids = deals.options(p2, deals.talks[p2.id]).map(func(o: Dictionary) -> String: return String(o["id"]))
	t.check("toll_favour" in ids, "and may call in a favour (%s)" % [ids])
	t.eq(deals.choose(p2, "toll_favour"), "", "does")
	t.eq(life.standing(p2.id, f), 12 - int(SimData.culture("drow").stance.toll.standing), "the favour costs standing")
	t.eq(life.toll_due(p2, city), 0, "and pays the toll")
	life.add_standing(p2.id, f, 30, "test")
	t.eq(life.toll_due(p2, city), 0, "a friend of the city pays none")
	# abroad: a drow on the surface falls on strangers until they have earned better
	var surf := -1
	for sid: int in WorldSim._sorted_keys(host.sim.settlements):
		if host.sim.settlements[sid].band == "surface":
			surf = sid
			break
	var spot := LifeTown.site_pos(host, surf) + Vector2(0, 2)
	var drow := life.spawn_person(host, {"culture": "drow", "slug": "warrior-infantry", "role": "escort", "pos": spot, "post": spot,
		"faction": cs.faction, "sim": {"kind": "party", "id": -1, "role": "escort", "party": "caravan"}, "fighter": true})
	var walker := player(host, "walker", spot + Vector2(4, 0))
	t.eq(SimData.band_family(life.band_at(drow.body.pos.y)), "surface", "a drow escort on the surface")
	t.eq(life.stance(walker, drow), Life.HOSTILE, "attacks a stranger on sight")
	t.eq(life.stance(p2, drow), Life.FRIENDLY, "but not a friend of its city")
	life.trade_standing(walker.id, f, 400.0)
	t.eq(life.standing(walker.id, f), 8, "trade earns standing (400 coin: 8)")
	t.eq(life.stance(walker, drow), Life.HOSTILE, "not yet enough")
	life.trade_standing(walker.id, f, 100.0)
	host.tick()
	t.eq(life.stance(walker, drow), Life.NEUTRAL, "standing 10 from trade: the surface drow let the trader be")
	life.trade_standing(walker.id, f, 100000.0)
	t.eq(life.standing(walker.id, f), int(Life.num("trade_cap", 20)), "trade alone earns at most trade_cap")
	var at_home: HostEntity = guard
	var fresh := player(host, "fresh", gate)
	t.eq(life.stance(fresh, at_home), Life.NEUTRAL, "a drow at home is neutral to a fresh stranger")
	# fighting back abroad costs nothing; killing one at home does
	var combat: CombatSystem = r["combat"]
	var st0 := life.standing(fresh.id, f)
	fresh.body.pos = spot + Vector2(2, 0)
	combat.damage(fresh.id, drow, 9999, "force")
	for i in 3:
		host.tick()
	t.eq(life.standing(fresh.id, f), st0, "killing a drow who fell on you abroad costs no standing")
	# the wary deep peoples
	var hs: SimSettlement = host.sim.settlements[hold]
	var hf := str(hs.faction)
	var hp := player(host, "visitor", LifeTown.site_pos(host, hold) + Vector2(0, 2))
	for i in 70:
		host.tick()
	var dwarf: HostEntity = null
	for e: HostEntity in life.actors_at(hold):
		dwarf = e
	t.check(dwarf != null, "the duergar hold is shown")
	if dwarf != null:
		t.eq(life.stance(hp, dwarf), Life.NEUTRAL, "duergar are wary, not hostile")
		life.add_standing(hp.id, hf, 40, "test")
		t.eq(life.stance(hp, dwarf), Life.NEUTRAL, "at 40 still only neutral (a human town would be friendly at 30)")
		life.add_standing(hp.id, hf, 10, "test")
		t.eq(life.stance(hp, dwarf), Life.FRIENDLY, "at 50 friendly")
	t.check(life.culture_stance(str(hs.faction)).get("abroad", "") == "", "duergar don't attack on sight abroad")
	for c: String in ["kobold", "goblinoid", "human", "dwarf"]:
		t.check(not SimData.culture(c).has("stance"), "%s meet players as they always have" % c)
