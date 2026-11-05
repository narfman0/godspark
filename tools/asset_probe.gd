## Prints the AABB (size and min corner, metres) of each glTF given, or of every glTF under a
## directory, loaded at runtime (GltfCache, no import). Also bone count, mesh nodes and
## embedded animations, for rig surveys. Ported from glitchbound.
##   godot --headless -s res://tools/asset_probe.gd -- res://assets/meshes/<Pack>/x.gltf [res://dir/] [meshes]
extends SceneTree

func _initialize() -> void:
	var paths: Array[String] = []
	var show_meshes := false
	for a in OS.get_cmdline_user_args():
		if a == "meshes":
			show_meshes = true
		elif a.ends_with("/"):
			_collect(a, paths)
		else:
			paths.append(a)
	for p in paths:
		var inst := GltfCache.instance(p)
		if inst == null:
			print("%-58s LOAD FAILED (%s)" % [p.get_file(), GltfCache.last_error])
			continue
		var box := GltfCache.visible_aabb(inst)
		var skels := inst.find_children("*", "Skeleton3D", true, false)
		var bones := (skels[0] as Skeleton3D).get_bone_count() if skels.size() > 0 else 0
		var aps := inst.find_children("*", "AnimationPlayer", true, false)
		var anims := (aps[0] as AnimationPlayer).get_animation_list().size() if aps.size() > 0 else 0
		print("%-50s size %s min %s bones %d anims %d" % [p.get_file().get_basename(),
			box.size.snapped(Vector3.ONE * 0.01), box.position.snapped(Vector3.ONE * 0.01), bones, anims])
		if show_meshes:
			for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
				var b := GltfCache.visible_aabb(mi)
				print("    %-40s size %s skin %s" % [mi.name, b.size.snapped(Vector3.ONE * 0.01), mi.skin != null])
			if bones > 0:
				var sk: Skeleton3D = skels[0]
				var names := PackedStringArray()
				for i in mini(sk.get_bone_count(), 12):
					names.append(sk.get_bone_name(i))
				print("    bones: ", ", ".join(names), " ...")
		inst.free()
	quit()

func _collect(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gltf") or f.ends_with(".glb"):
			out.append(dir + f)
	for d in DirAccess.get_directories_at(dir):
		_collect(dir + d + "/", out)
