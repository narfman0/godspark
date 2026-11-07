## A generated world's content hash, for proving a change moved no world.
##   godot --headless -s res://tools/world_hash.gd -- gen=dev seed=4
extends SceneTree

func _initialize() -> void:
	var o := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		o[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var w := WorldGen.generate_named(String(o.get("gen", "dev")), int(o.get("seed", 1)))
	print("HASH %s %s %s" % [o.get("gen", "dev"), o.get("seed", 1), w.content_hash()])
	quit()
