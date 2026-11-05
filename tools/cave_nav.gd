## Cave reachability over several generated worlds: the monsters track's cave nav test
## (tests/test_monster_nav.gd _caves: a Medium walker and a Large climber, air-connected
## spots ~40 tiles apart in the caves band) per seed, and the totals.
##   godot --headless -s res://tools/cave_nav.gd -- [seeds=3,5,7,11,13] [pairs=24]
extends SceneTree

func _initialize() -> void:
	var opts := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		opts[kv[0]] = kv[1] if kv.size() > 1 else ""
	var test: Object = load("res://tests/test_monster_nav.gd").new()
	var tot := [[0, 0], [0, 0]]
	for s in String(opts.get("seeds", "3,5,7,11,13")).split(","):
		var r: Array = test.call("_caves", TestLog.new(), int(s), int(opts.get("pairs", 24)))
		for k in 2:
			tot[k][0] += int(r[k][0])
			tot[k][1] += int(r[k][1])
		print("seed %s: medium %d/%d, large %d/%d" % [s, r[0][0], r[0][1], r[1][0], r[1][1]])
	print("CAVENAV medium %d/%d (%.0f%%), large %d/%d (%.0f%%)" % [tot[0][0], tot[0][1], 100.0 * tot[0][0] / maxi(1, tot[0][1]),
		tot[1][0], tot[1][1], 100.0 * tot[1][0] / maxi(1, tot[1][1])])
	quit()
