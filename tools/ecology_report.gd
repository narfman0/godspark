## Spawnable roster per depth band and time of day, by CR, so gaps are visible.
##   godot --headless -s res://tools/ecology_report.gd [-- biome=meadow]
##   godot --headless -s res://tools/ecology_report.gd -- biomes=1 [seed=3]
## biomes=1: what actually hunts in each surface biome by day and by night, far from towns and
## near them: 600 packs of the director's own build_pack per case, their shares, and how much of
## one biome's hunting is the same as another's.
extends SceneTree

const BUCKETS := [[0.0, 0.25], [0.5, 1.0], [2.0, 3.0], [4.0, 5.0], [6.0, 8.0], [9.0, 11.0], [12.0, 14.0], [15.0, 17.0], [18.0, 30.0]]

func _initialize() -> void:
	var srd := WorldHost.shared_srd()
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if args.has("biomes"):
		_biomes(srd, int(args.get("seed", 3)))
		quit()
		return
	var hab := Ecology.habitats()
	var counts := {}
	for s: String in hab:
		if s.begins_with("_"):
			continue
		var k := String(hab[s]["spawn"])
		counts[k] = int(counts.get(k, 0)) + 1
	print("ecology rows: %d  by spawn: %s" % [hab.size() - 1, counts])
	var gaps: Array = []
	for band: String in ["sky", "surface", "caves", "deeps", "nadir"]:
		var biome := String(args.get("biome", Ecology.spawning()["band_biome"].get(band, "meadow")))
		var bd: Dictionary = Ecology.spawning()["bands"][band]
		for tm: String in ["day", "night"]:
			var d: Dictionary = bd.get("any", bd.get(tm, {}))
			var cr: Array = d["cr"]
			var all := Ecology.roster(srd, band, biome, tm == "night", 0.0, 30.0)
			var water := Ecology.roster(srd, band, biome, tm == "night", 0.0, 30.0, true)
			print("\n%s / %s (biome %s, budget CR %s-%s, %d kinds, %d more in water)" % [band, tm, biome, cr[0], cr[1], all.size(), water.size()])
			for bk: Array in BUCKETS:
				var names := PackedStringArray()
				for c: Dictionary in all:
					if float(c["cr"]) >= bk[0] - 1e-6 and float(c["cr"]) <= bk[1] + 1e-6:
						names.append(String(c["slug"]))
				var in_band: bool = bk[1] >= float(cr[0]) and bk[0] <= float(cr[1])
				print("  CR %4s-%-4s %s%2d  %s" % [bk[0], bk[1], "*" if in_band else " ", names.size(), ", ".join(names)])
				if in_band and names.size() < 3:
					gaps.append("%s/%s CR %s-%s: %d kinds" % [band, tm, bk[0], bk[1], names.size()])
	print("\nGAPS (CR ranges inside a band's budget with fewer than 3 kinds):")
	for g in gaps:
		print("  " + g)
	quit()


## A host on a small one-biome-at-a-time stand: the director's tables need one, not its ground.
func _biomes(srd: SRDContent, sd: int) -> void:
	var world := TileWorld.make_test(256, 128)
	var host := WorldHost.new(world)
	var ms := MonstersSystem.new()
	ms.director_enabled = 0
	ms.lairs_enabled = false
	host.add_system(ms)
	var dir: SpawnDirector = ms.director
	dir.rng.seed = sd
	var shares := {}
	for biome: String in BiomeIds.generated("surface"):
		for tm: String in ["day", "night"]:
			host.sleep(fposmod((12.0 if tm == "day" else 23.0) - host.clock.hour_of_day(), 24.0))
			var table: Dictionary = Ecology.spawning()["bands"]["surface"][tm]
			var got := {}
			var n := 0
			for i in 600:
				for m: Dictionary in dir.build_pack(host, "surface", biome, table, float(table["pack_cr"])):
					got[m["slug"]] = int(got.get(m["slug"], 0)) + 1
					n += 1
			var rows: Array = got.keys()
			rows.sort_custom(func(a: String, b: String) -> bool: return got[a] > got[b])
			var line := PackedStringArray()
			for s: String in rows.slice(0, 12):
				line.append("%s %d%%" % [s, roundi(100.0 * got[s] / maxf(n, 1.0))])
			print("%-9s %-5s %2d kinds, %s" % [biome, tm, rows.size(), ", ".join(line)])
			var sh := {}
			for s: String in got:
				sh[s] = float(got[s]) / maxf(n, 1.0)
			shares[biome + ":" + tm] = sh
	print("\nshared hunting (sum of the smaller share of each creature, night):")
	var ids := BiomeIds.generated("surface")
	for a: String in ids:
		var row := PackedStringArray()
		for b: String in ids:
			var s := 0.0
			var sa: Dictionary = shares[a + ":night"]
			var sb: Dictionary = shares[b + ":night"]
			for k: String in sa:
				s += minf(float(sa[k]), float(sb.get(k, 0.0)))
			row.append("%3d%%" % roundi(s * 100.0))
		print("%-9s %s" % [a, " ".join(row)])
