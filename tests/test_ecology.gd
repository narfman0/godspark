## The ecology table: every SRD monster has a row, every row is an SRD monster, the values are
## from the documented sets, and the notable placements hold.
extends RefCounted

const BANDS := ["sky", "surface", "caves", "deeps", "nadir"]
const BRAINS := ["bruiser", "skirmisher", "archer", "caster", "heavy", "swarm", "lurker", "flier", "ambusher"]

func run(t: TestLog) -> void:
	_biomes(t)
	_rest(t)

## What hunts where is the biome's own: a desert is not a swamp, and the director asks for the
## ground it stands on.
func _biomes(t: TestLog) -> void:
	var srd := WorldHost.shared_srd()
	var slugs := func(b: String, night: bool, hi: float) -> Array:
		return Ecology.roster(srd, "surface", b, night, 0.0, hi).map(func(r: Dictionary) -> String: return r["slug"])
	for night: bool in [false, true]:
		var desert: Array = slugs.call("desert", night, 3.0)
		var swamp: Array = slugs.call("swamp", night, 3.0)
		var both := 0
		for s: String in desert:
			both += 1 if s in swamp else 0
		t.check(both * 3 < mini(desert.size(), swamp.size()), "desert and swamp share little %s (%d of %d and %d)" % ["by night" if night else "by day", both, desert.size(), swamp.size()])
	for b: String in BiomeIds.generated("surface"):
		t.check((slugs.call(b, false, 1.0) as Array).size() >= 5, "%s has a day's hunting (%s)" % [b, slugs.call(b, false, 1.0)])
		t.check((slugs.call(b, true, 3.0) as Array).size() >= 8, "%s has a night's" % b)
	t.check("camel" in slugs.call("desert", false, 3.0) and not "camel" in slugs.call("swamp", false, 3.0), "camels in the desert only")
	t.check("giant-goat" in slugs.call("mountain", false, 3.0) and not "giant-goat" in slugs.call("meadow", false, 3.0), "goats on the mountain")
	t.eq(LairLink.body_of("wolf", "desert"), "hyena", "a wolf pack in the desert comes as hyenas")
	t.eq(LairLink.body_of("wolf", "forest"), "wolf", "and as wolves in the forest")
	for b: String in Ecology.spawning()["lair_kin"]:
		if b.begins_with("_"):
			continue
		for from: String in Ecology.spawning()["lair_kin"][b]:
			var to := String(Ecology.spawning()["lair_kin"][b][from])
			t.check(b in (Ecology.row(to)["biomes"] as Array), "%s in the %s lives there" % [to, b])
			t.check(absf(Ecology.cr_of(srd, to) - Ecology.cr_of(srd, from)) <= 3.0, "%s stands in for %s at about its strength" % [to, from])
	var w := WorldGen.generate_named("dev", 3)
	var h := WorldHost.new(w)
	var ms := MonstersSystem.new()
	ms.director_enabled = 0
	ms.lairs_enabled = false
	h.add_system(ms)
	for s: Dictionary in BiomeIds.strip(w.meta):
		var x := (float(s["x0"]) + float(s["x1"])) * 0.5
		t.eq(ms.director.biome_at(h, x, "surface"), s["biome"], "the director reads the ground at %d" % int(x))
		var pack: Array = ms.director.build_pack(h, "surface", s["biome"], {"cr": [0, 3], "pack_cr": 4.0}, 4.0)
		for m: Dictionary in pack:
			t.check(String(s["biome"]) in (Ecology.row(String(m["slug"]))["biomes"] as Array), "%s lives in the %s" % [m["slug"], s["biome"]])

func _rest(t: TestLog) -> void:
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
