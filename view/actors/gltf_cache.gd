## Runtime glTF loading (GLTFDocument), no editor import. Fetched art lives in git-ignored
## folders with a .gdignore (assets/meshes, assets/monsters, assets/props), so nothing there
## is ever imported: everything goes through here.
##
##   var node := GltfCache.instance("res://assets/meshes/.../SM_Env_Tree_Meadow_01.gltf")  # null if missing
##
## A parsed GLTFState is kept per path, so a second instance of the same file only pays for
## generate_scene() (meshes, materials and textures are shared). Missing files are remembered
## too and never logged: a fresh checkout has none of them, and that is normal.
class_name GltfCache
extends RefCounted

static var _states := {}     ## path -> GLTFState, or null when the file is missing or broken
static var last_error := ""
## Loads attempted / parsed, for tools.
static var stats := {"parsed": 0, "missing": 0, "failed": 0, "usec": 0}

static func exists(path: String) -> bool:
	if path == "":
		return false
	if _states.has(path):
		return _states[path] != null
	return FileAccess.file_exists(path)

## The parsed state, or null (missing or unreadable). Parsing errors are reported once in
## last_error, never pushed to the log.
static func state(path: String) -> GLTFState:
	if _states.has(path):
		return _states[path]
	var st: GLTFState = null
	if not FileAccess.file_exists(path):
		stats["missing"] += 1
		last_error = "missing: " + path
	else:
		var t0 := Time.get_ticks_usec()
		var doc := GLTFDocument.new()
		var s := GLTFState.new()
		var err := doc.append_from_file(path, s)
		stats["usec"] += Time.get_ticks_usec() - t0
		if err == OK:
			st = s
			stats["parsed"] += 1
		else:
			stats["failed"] += 1
			last_error = "%s: GLTFDocument error %s" % [path, error_string(err)]
	_states[path] = st
	return st

## A new scene instance of the file, or null.
static func instance(path: String) -> Node3D:
	var st := state(path)
	if st == null:
		return null
	var doc := GLTFDocument.new()
	var root := doc.generate_scene(st) as Node3D
	if root != null:
		_finish(root)
	return root

## generate_scene() can leave ImporterMeshInstance3D nodes (it does under the headless
## dummy renderer): swap them for MeshInstance3D. Synty LOD chains (<name>_LOD0.._LOD3 as
## siblings) keep only LOD0.
static func _finish(root: Node) -> void:
	for imi: ImporterMeshInstance3D in root.find_children("*", "ImporterMeshInstance3D", true, false):
		var mi := MeshInstance3D.new()
		mi.name = imi.name
		mi.transform = imi.transform
		mi.visible = imi.visible
		if imi.mesh != null:
			mi.mesh = imi.mesh.get_mesh()
		mi.skin = imi.skin
		var parent := imi.get_parent()
		var idx := imi.get_index()
		var kids := imi.get_children()
		for k in kids:
			imi.remove_child(k)
		parent.remove_child(imi)
		parent.add_child(mi)
		parent.move_child(mi, idx)
		for k in kids:
			mi.add_child(k)
		mi.skeleton = imi.skeleton_path
		imi.free()
	for mi: MeshInstance3D in root.find_children("*_LOD?", "MeshInstance3D", true, false):
		var n := String(mi.name)
		if not n.ends_with("_LOD0"):
			mi.get_parent().remove_child(mi)
			mi.free()

## Forget everything (tests, or after a fetch).
static func clear() -> void:
	_states.clear()

## AABB of the visible meshes under n, in n's parent space (n's own transform included).
## Skinned meshes are placed where the skin draws them at rest (see mesh_xform), not by their
## node chain: cooked Synty rigs carry a 0.01-scaled Armature that the bind poses undo.
static func visible_aabb(n: Node) -> AABB:
	var out := AABB()
	var have := false
	var stop: Node = n.get_parent()
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false) + ([n] if n is MeshInstance3D else []):
		if not mi.is_visible_in_tree() and mi.is_inside_tree():
			continue
		if not mi.visible or mi.mesh == null or mi.is_queued_for_deletion():
			continue
		var b: AABB = mesh_xform(mi, stop) * mi.get_aabb()
		out = b if not have else out.merge(b)
		have = true
	return out

## Transform from a mesh's vertices to `stop`'s space (stop = an ancestor, or null for the
## top). Static meshes: the node chain. Skinned meshes: skeleton node * bone rest * bind pose
## of the first bind, which is where the rest pose renders.
static func mesh_xform(mi: MeshInstance3D, stop: Node) -> Transform3D:
	var skel: Skeleton3D = null
	if mi.skin != null and mi.skin.get_bind_count() > 0:
		skel = mi.get_node_or_null(mi.skeleton) as Skeleton3D
	if skel == null:
		return chain(mi, stop)
	var bone := mi.skin.get_bind_bone(0)
	var bname := mi.skin.get_bind_name(0)
	if bname != "":
		bone = skel.find_bone(bname)
	if bone < 0:
		return chain(mi, stop)
	return chain(skel, stop) * skel.get_bone_global_rest(bone) * mi.skin.get_bind_pose(0)

## Product of node transforms from n up to (not including) stop.
static func chain(n: Node, stop: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	while n != null and n != stop:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf
