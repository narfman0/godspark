## Builds an actor for every row of data/looks.json (or the keys given) and prints what it got:
## forge / synty / primitive, height, clips and load time. Headless is fine.
##   godot --headless -s res://tools/check_looks.gd [-- people:elf:drow wolf player:fighter]
extends SceneTree

func _initialize() -> void:
	var keys: Array = OS.get_cmdline_user_args()
	var t := Looks.table()
	if keys.is_empty():
		keys = t["looks"].keys()
	var counts := {}
	var mat := ShaderMaterial.new()
	var total := 0
	for k: String in keys:
		var look := {"key": k}
		if Looks.creatures().has(k):
			look = {"slug": k}
		var t0 := Time.get_ticks_usec()
		var a := ActorBody.build(look, mat)
		var us := Time.get_ticks_usec() - t0
		total += us
		root.add_child(a)
		var clips := ""
		if a.visual is CharacterVisual and (a.visual as CharacterVisual).anim:
			clips = ",".join((a.visual as CharacterVisual).anim.get_animation_list())
		elif a.visual is ForgeMonster:
			clips = ",".join((a.visual as ForgeMonster).clips())
		var box := GltfCache.visible_aabb(a)
		if a.visual is CharacterVisual:
			var cv := a.visual as CharacterVisual
			box = cv.model.transform * cv._skinned_aabb()
		print("%-28s %-9s %-14s h %.2f m (box %.2f)  %5.0f ms  %s" % [k, a.kind, a.plan.get("model", ""),
			box.size.y, a.size.y * K.TILE_M, us / 1000.0, clips])
		counts[a.kind] = counts.get(a.kind, 0) + 1
		a.free()
	print("bodies: %s, total %.1f s; gltf %s" % [counts, total / 1e6, GltfCache.stats])
	GltfCache.clear()
	quit()
