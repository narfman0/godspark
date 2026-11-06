## The ecology table: every SRD monster has a row, every row is an SRD monster, the values are
## from the documented sets, and the notable placements hold.
extends RefCounted

const BANDS := ["sky", "surface", "caves", "deeps", "nadir"]
const BRAINS := ["bruiser", "skirmisher", "archer", "caster", "heavy", "swarm", "lurker", "flier", "ambusher"]

func run(t: TestLog) -> void:
	var srd := WorldHost.shared_srd()
	var hab := Ecology.habitats()
	var slugs := {}
	for r: Dictionary in srd.pack.rows("monster"):
		slugs[String(r["slug"])] = true
	t.eq(slugs.size(), 330, "the addon has 330 monsters")
	var missing := []
	for s: String in slugs:
		if not hab.has(s):
			missing.append(s)
	t.eq(missing, [], "every SRD monster has an ecology row")
	var bad := []
	for s: String in hab:
		if s.begins_with("_"):
			continue
		if not slugs.has(s):
			bad.append(s + ": not an SRD slug")
			continue
		var r: Dictionary = hab[s]
		for b: String in r["biomes"]:
			if not BiomeIds.has(b):
				bad.append("%s: biome %s" % [s, b])
		for b: String in r["bands"]:
			if not b in BANDS:
				bad.append("%s: band %s" % [s, b])
		if not String(r["brain"]) in BRAINS:
			bad.append("%s: brain %s" % [s, r["brain"]])
		if not String(r["time"]) in ["day", "night", "any"]:
			bad.append("%s: time" % s)
		if not String(r["hostility"]) in ["hostile", "neutral"]:
			bad.append("%s: hostility" % s)
		if not String(r["spawn"]) in ["wild", "lair", "portal", "people", "none"]:
			bad.append("%s: spawn" % s)
		for l: String in r.get("leader_of", []):
			if not hab.has(l):
				bad.append("%s: leads unknown %s" % [s, l])
		if r["spawn"] == "portal" and (r.get("planes", []) as Array).is_empty():
			bad.append("%s: extraplanar without planes" % s)
	t.eq(bad, [], "every row is well formed")
	t.eq(Ecology.row("aboleth")["spawn"], "lair", "aboleth: lair only")
	t.eq(Ecology.row("aboleth")["bands"], ["nadir"], "aboleth: the nadir")
	t.eq(Ecology.row("aboleth").get("medium", ""), "water", "aboleth: in water")
	t.eq(Ecology.row("darkmantle").get("perch", ""), "ceiling", "darkmantle: on cave ceilings")
	t.check("caves" in Ecology.row("darkmantle")["bands"], "darkmantle: caves")
	t.eq(Ecology.row("wolf")["time"], "night", "wolves: night")
	t.check(int(Ecology.row("wolf")["pack"][1]) >= 4, "wolves: packs")
	t.eq(Ecology.row("young-red-dragon")["spawn"], "lair", "dragons: lair only")
	t.eq(Ecology.row("balor")["spawn"], "portal", "fiends: portal only")
	t.eq(Ecology.row("skeleton")["flee"], false, "undead never flee")
	t.eq(Ecology.row("goblin-warrior")["flee"], true, "goblins flee")
	t.eq(Ecology.row("deer")["hostility"], "neutral", "deer are neutral")
	t.eq(Ecology.row("wolf").get("bond", ""), "beast:wolf", "wolves answer to a Bond with wolves")
	# every band has something to spawn by night
	for band: String in ["surface", "caves", "deeps", "nadir"]:
		var bd: Dictionary = Ecology.spawning()["bands"][band]
		var d: Dictionary = bd.get("any", bd.get("night", {}))
		var cr: Array = d["cr"]
		var biome := String(Ecology.spawning()["band_biome"].get(band, "meadow"))
		var n := Ecology.roster(srd, band, biome, true, float(cr[0]), float(cr[1])).size()
		t.check(n >= 5, "%s has a roster at night (%d kinds)" % [band, n])
	t.check(Ecology.affixes().size() - 1 >= 10, "at least 10 affixes")
	t.eq(Ecology.max_hp(srd, "ogre"), 104, "max HP from hit dice")
