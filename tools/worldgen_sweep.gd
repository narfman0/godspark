## Runs the worldgen invariant checks from tests/test_worldgen.gd over many seeds.
##   godot --headless -s res://tools/worldgen_sweep.gd -- <width> <height> <seeds> [first_seed]
extends SceneTree

func _initialize() -> void:
	var checks = load("res://tests/test_worldgen.gd").new()
	var args := OS.get_cmdline_user_args()
	var w := int(args[0])
	var h := int(args[1])
	var n := int(args[2])
	var first := int(args[3]) if args.size() > 3 else 1000
	var fails := 0
	for sd in range(first, first + n):
		var t := TestLog.new()
		checks._check_world(t, WorldGen.generate(w, h, sd), "%dx%d seed %d" % [w, h, sd])
		fails += t.failures.size()
	print("SWEEP %dx%d %d seeds: %d failures" % [w, h, n, fails])
	quit(0 if fails == 0 else 1)
