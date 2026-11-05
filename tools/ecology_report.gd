## Spawnable roster per depth band and time of day, by CR, so gaps are visible.
##   godot --headless -s res://tools/ecology_report.gd [-- biome=meadow]
extends SceneTree

const BUCKETS := [[0.0, 0.25], [0.5, 1.0], [2.0, 3.0], [4.0, 5.0], [6.0, 8.0], [9.0, 11.0], [12.0, 14.0], [15.0, 17.0], [18.0, 30.0]]

func _initialize() -> void:
	var srd := WorldHost.shared_srd()
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
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
