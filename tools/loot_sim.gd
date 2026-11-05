## What N kills of a monster at a rank drop, to eyeball loot rates.
##   godot --headless -s res://tools/loot_sim.gd -- monster=goblin-warrior rank=elite n=1000 band=caves seed=1
##   godot --headless -s res://tools/loot_sim.gd -- table      # every rank for a few monsters
## rank: minion standard elite champion boss; band: sky surface caves deeps nadir.
extends SceneTree

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	Items.ensure()
	if args.has("table"):
		print("monster            rank       items/kill  coin/kill  gear  mat  potion  magic  spark  (per 1000 kills)")
		for slug: String in ["goblin-warrior", "wolf", "skeleton", "bandit-captain", "ogre", "young-red-dragon"]:
			for rank: String in ItemGen.RANKS:
				var r := sim(slug, rank, "caves", 1000, 1)
				print("%-18s %-10s %10.2f %10.1f %5d %4d %7d %6d %6d" % [slug, rank, r["items"] / 1000.0, r["coin"] / 1000.0,
						r["cat"].get("gear", 0), r["cat"].get("material", 0), r["cat"].get("potion", 0), r["cat"].get("magic", 0), r["cat"].get("spark", 0)])
		quit(0)
		return
	var slug := String(args.get("monster", "goblin-warrior"))
	var rank := String(args.get("rank", "standard"))
	var band := String(args.get("band", "surface"))
	var n := int(args.get("n", "1000"))
	var r := sim(slug, rank, band, n, int(args.get("seed", "1")))
	var info := Loot.victim_info(slug, rank, band)
	print("%d kills of %s (%s, CR %s, %s) at rank %s in the %s band" % [n, slug, info["type"], info["cr"],
			Loot.data()["bands"][Loot.band_of(info["cr"])]["name"], rank, band])
	print("  coin: %d in total, %.1f per kill, %d%% of kills" % [r["coin"], r["coin"] / float(n), roundi(100.0 * r["coin_kills"] / n)])
	print("  items: %d (%.2f per kill), %d stacks' worth of count %d, value %d" % [r["items"], r["items"] / float(n), r["items"], r["count"], r["value"]])
	print("  by kind: %s" % [r["cat"]])
	print("  spark ranks [I, II, III]: %s" % [r["spark_ranks"]])
	var top: Array = r["bases"].keys()
	top.sort_custom(func(a: String, b: String) -> bool: return r["bases"][a] > r["bases"][b])
	print("  most common:")
	for b: String in top.slice(0, 12):
		print("    %5d  %s" % [r["bases"][b], b])
	print("  a few named:")
	for s: String in r["names"].slice(0, 10):
		print("    ", s)
	quit(0)

static func sim(slug: String, rank: String, band: String, n: int, seed_v: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var info := Loot.victim_info(slug, rank, band)
	var out := {"coin": 0, "coin_kills": 0, "items": 0, "count": 0, "value": 0, "cat": {}, "bases": {}, "spark_ranks": [0, 0, 0], "names": []}
	for i in n:
		for it: Dictionary in Loot.roll(rng, info):
			if it["base"] == "coin":
				out["coin"] += int(it["count"])
				out["coin_kills"] += 1
				continue
			out["items"] += 1
			out["count"] += int(it["count"])
			out["value"] += Items.value(it) * int(it["count"])
			var c := "spark" if it.has("spark") else ("magic" if it.has("magic") and not String(it["magic"]).ends_with("1-2-or-3") and it["magic"] != "potions-of-healing"
					else ("potion" if it.get("magic") == "potions-of-healing" else ("gear" if String(Items.row(it["base"]).get("kind")) in ["weapon", "armor", "shield"] else "material")))
			out["cat"][c] = int(out["cat"].get(c, 0)) + 1
			out["bases"][it["base"]] = int(out["bases"].get(it["base"], 0)) + 1
			if it.has("spark"):
				out["spark_ranks"][int(it["spark"]["rank"])] += 1
			if c in ["gear", "magic"] and (out["names"] as Array).size() < 10:
				out["names"].append(ItemGen.name(it))
	return out
