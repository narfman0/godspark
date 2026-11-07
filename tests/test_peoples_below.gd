## Peoples below (M6 track 2): the drow, duergar, deep gnomes, kobolds and goblins as cultures with
## homes in the Underdark, their people built from SRD NPC stat blocks with make_npc, their towns,
## deep roads as trade, and how they meet players. docs/tracks/peoples-below.md.
extends RefCounted

const DEEP := ["drow", "duergar", "deep_gnome", "kobold", "goblinoid"]
const ROLES := ["townsfolk", "guard", "merchant", "smith", "priest", "mage", "raider", "scout"]
const TEMPERS := ["trader", "expansionist", "raider", "isolationist"]

func run(t: TestLog) -> void:
	for f: String in ["_cultures", "_homes", "_roles", "_names", "_economy"]:
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
