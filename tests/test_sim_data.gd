## Sim data tables: every stat block named exists in SRD 5.2.1; cultures and lairs are complete.
extends RefCounted

func run(t: TestLog) -> void:
	SimData.ensure()
	var missing: Array = []
	for slug in SimData.all_referenced_slugs():
		if not SimData.monsters.has(slug):
			missing.append(slug)
	t.check(missing.is_empty(), "every culture/lair slug exists in monsters.json (missing: %s)" % [missing])
	t.check(SimData.all_referenced_slugs().size() > 80, "tables reference many stat blocks")
	for cid in SimData.culture_ids:
		var c: Dictionary = SimData.cultures[cid]
		for key in ["guards", "escort", "raiders", "army", "bands", "mobility", "raid_mobility", "temperament", "faction_forms"]:
			t.check(c.has(key) and not (c[key] as Variant == null), "%s has %s" % [cid, key])
		t.check(SimData.names.has(cid), "%s has a name syllable set" % cid)
	# Drow are the Elf lineage, built from NPC stat blocks.
	var drow: Dictionary = SimData.cultures.drow
	t.eq(drow.species, "elf", "drow are elves")
	t.eq(drow.lineage, "drow", "drow lineage flagged")
	t.check(not SimData.monsters.has("drow"), "SRD has no drow stat block (raiders are composed)")
	for band in ["surface", "caves", "deeps", "portal"]:
		t.check(SimData.lairs.has(band) and SimData.lairs[band].size() > 0, "lair table for %s" % band)
	for g in ["food", "timber", "ore", "tools", "luxuries"]:
		t.check(SimData.goods.has(g), "good %s defined" % g)
	# Allocation is integral and exact.
	var a := SimData.allocate(SimData.cultures.drow.raiders, 17)
	t.eq(SimData.count(a), 17, "allocate gives exactly n units")
	t.eq(SimData.allocate([["guard", 1]], 0), {}, "allocate 0 is empty")
	# Multiattack parse.
	t.eq(int(SimData.monster("owlbear").attacks), 2, "owlbear makes two attacks")
	t.eq(int(SimData.monster("purple-worm").attacks), 2, "purple worm: bite + stinger")
	# No published-setting names in the syllable tables.
	var blob := JSON.stringify(SimData.names).to_lower()
	for bad in ["menzo", "baenre", "waterdeep", "neverwinter", "faerun", "underdark\"", "drizzt", "lolth", "gauntlgrym", "yeen"]:
		t.check(not blob.contains(bad), "names.json avoids '%s'" % bad)
