## What the regions' scatter costs, on a cached or generated world: the cold scan of a player's
## held chunks (RegionDressing), the tint and fog maps, and drawing the records.
##   godot --headless -s res://tools/below_bench.gd -- cache=DIR gen=medium seed=1 x=1104 y=951
extends SceneTree

func _initialize() -> void:
	var o := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		o[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var cache := String(o.get("cache", ""))
	var world: TileWorld = WorldSave.load(cache) if cache != "" else WorldGen.generate_named(String(o.get("gen", "medium")), int(o.get("seed", 1)))
	var c := Vector2i(int(o.get("x", 1104)) >> 5, int(o.get("y", 951)) >> 5)
	var rd := RegionDressing.new(world)
	var recs: Array = []
	var slow := 0
	var t0 := Time.get_ticks_usec()
	var n := 0
	# a client's held area: radius 3 of chunks, the interest radius plus the unload slack
	for cy in range(c.y - 3, c.y + 4):
		for cx in range(c.x - 3, c.x + 4):
			var a := Time.get_ticks_usec()
			recs.append_array(rd.records_in(cx, cy))
			slow = maxi(slow, Time.get_ticks_usec() - a)
			n += 1
	var cold := Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	for cy in range(c.y - 3, c.y + 4):
		for cx in range(c.x - 3, c.x + 4):
			rd.records_in(cx, cy)
	var warm := Time.get_ticks_usec() - t0
	var rect := Rect2i(c * K.CHUNK - Vector2i(90, 50), Vector2i(180, 100))
	t0 = Time.get_ticks_usec()
	var fog := BelowLook.fog_bytes(world.meta, rect, BelowLook.FOG_CELL)
	var fog_us := Time.get_ticks_usec() - t0
	var src: Array = []
	for r: Dictionary in recs:
		var l: Variant = DressingView.defs()[r["id"]].get("light")
		if l is Dictionary:
			src.append({"x": r["x"], "y": r["y"], "color": Color.AQUA, "tint": true, "level": 0.6, "reach": 12.0})
	t0 = Time.get_ticks_usec()
	var tint := BelowLook.tint_bytes(src, rect, BelowLook.TINT_CELL)
	var tint_us := Time.get_ticks_usec() - t0
	print("BELOW %d chunks cold %.1f ms (worst chunk %.1f ms), warm %.2f ms, %d records, %d lights; fog map %.2f ms (%d B), tint map %.2f ms (%d B)" % [
		n, cold / 1000.0, slow / 1000.0, warm / 1000.0, recs.size(), src.size(), fog_us / 1000.0, fog.size(), tint_us / 1000.0, tint.size()])
	quit()
