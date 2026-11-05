## A monster synced from monster-forge (tools/sync_monsters.py), loaded at runtime.
## Trimmed port of godot-dnd's scripts/monster.gd: one skeleton, LOD0 only, every
## anims/<clip>.glb bound to it by bone name, a RESET animation so un-keyed bones return to
## rest. Not ported (yet): LOD1-3, props and sockets, swarm units.
##
##   var m := ForgeMonster.load_monster("wolf")    # null if not synced (see last_error)
##   add_child(m); m.play("walk")
##
## Contract (monster-forge): metres, origin at the feet, +Y up, the creature faces -Z. This
## node turns the model by PI, so like every actor visual it faces +Z.
class_name ForgeMonster
extends Node3D

const ROOT := "res://assets/monsters"
const LOOPING := ["idle", "walk", "run", "move", "fly", "swim", "hover"]
const HOLD_LAST := ["death"]
const MOVE_CLIPS := ["walk", "run", "move", "swim", "fly", "hover"]

static var last_error := ""

var id := ""
var info: Dictionary = {}
var model: Node3D
var skeleton: Skeleton3D
var anim: AnimationPlayer
var aabb := AABB()          ## LOD0 rest-pose AABB, model space (metres)
var current_clip := ""
var _loop_clip := "idle"

static func dir_of(monster_id: String) -> String:
	return "%s/%s" % [ROOT, monster_id]

static func is_synced(monster_id: String) -> bool:
	return monster_id != "" and FileAccess.file_exists(dir_of(monster_id) + "/monster.json")

static func load_monster(monster_id: String) -> ForgeMonster:
	last_error = ""
	if not is_synced(monster_id):
		last_error = "%s: not synced" % monster_id
		return null
	var dir := dir_of(monster_id)
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(dir + "/monster.json"))
	if not parsed is Dictionary:
		last_error = "%s/monster.json invalid" % dir
		return null
	var lod0_file: String = parsed.get("lods", {}).get("0", {}).get("file", "model_rigged.glb")
	var mdl := GltfCache.instance("%s/%s" % [dir, lod0_file])
	if mdl == null:
		last_error = GltfCache.last_error
		return null
	var m := ForgeMonster.new()
	m.name = monster_id
	m.id = monster_id
	m.info = parsed
	mdl.name = "model"
	mdl.rotation.y = PI      # forge faces -Z; actor visuals face +Z
	m.model = mdl
	m.add_child(mdl)
	if not m._setup(dir):
		m.free()
		return null
	return m

func _setup(dir: String) -> bool:
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if skels.size() != 1:
		last_error = "%s: expected 1 Skeleton3D, found %d" % [id, skels.size()]
		return false
	skeleton = skels[0]
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		last_error = "%s: no mesh" % id
		return false
	aabb = GltfCache.visible_aabb(model)
	aabb = model.transform.affine_inverse() * aabb   # model space, before our turn
	LitMaterials.apply(model)
	for ap: AnimationPlayer in model.find_children("*", "AnimationPlayer", true, false):
		ap.queue_free()
	anim = AnimationPlayer.new()
	anim.name = "AnimationPlayer"
	anim.deterministic = true   # un-keyed bones fall back to RESET
	add_child(anim)
	var lib := AnimationLibrary.new()
	for c in info.get("clips", []):
		_add_clip(lib, dir, String(c))
	lib.add_animation("RESET", _reset_animation())
	anim.add_animation_library("", lib)
	anim.animation_finished.connect(_on_finished)
	return true

## Every bone keyed at rest (runtime GLTFDocument adds no RESET; see godot-dnd docs).
func _reset_animation() -> Animation:
	var a := Animation.new()
	a.length = 0.001
	var sp := String(get_path_to(skeleton))
	for b in skeleton.get_bone_count():
		var rest := skeleton.get_bone_rest(b)
		var path := NodePath("%s:%s" % [sp, skeleton.get_bone_name(b)])
		var t := a.add_track(Animation.TYPE_POSITION_3D)
		a.track_set_path(t, path)
		a.position_track_insert_key(t, 0.0, rest.origin)
		t = a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(t, path)
		a.rotation_track_insert_key(t, 0.0, rest.basis.get_rotation_quaternion())
		t = a.add_track(Animation.TYPE_SCALE_3D)
		a.track_set_path(t, path)
		a.scale_track_insert_key(t, 0.0, rest.basis.get_scale())
	return a

func _add_clip(lib: AnimationLibrary, dir: String, c: String) -> void:
	var sc := GltfCache.instance("%s/anims/%s.glb" % [dir, c])
	if sc == null:
		return
	var players := sc.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty() or (players[0] as AnimationPlayer).get_animation_list().is_empty():
		sc.free()
		return
	var ap: AnimationPlayer = players[0]
	var names := ap.get_animation_list()
	var skel_path := String(get_path_to(skeleton))
	for n in names:
		var a: Animation = ap.get_animation(n).duplicate(true)
		for t in range(a.get_track_count() - 1, -1, -1):
			var p := a.track_get_path(t)
			var bone := String(p.get_concatenated_subnames())
			if bone == "":
				bone = String(p.get_name(p.get_name_count() - 1))
			if skeleton.find_bone(bone) >= 0:
				a.track_set_path(t, NodePath("%s:%s" % [skel_path, bone]))
			else:
				a.remove_track(t)
		a.loop_mode = Animation.LOOP_LINEAR if c in LOOPING else Animation.LOOP_NONE
		lib.add_animation(c if names.size() == 1 else "%s:%s" % [c, n], a)
	sc.free()

func clips() -> PackedStringArray:
	var out := PackedStringArray()
	if anim:
		for n in anim.get_animation_list():
			if n != "RESET":
				out.append(n)
	return out

func move_clip() -> String:
	var have := clips()
	for c in MOVE_CLIPS:
		if c in have:
			return c
	return ""

func has_clip(c: String) -> bool:
	return anim != null and anim.has_animation(c)

## Same vocabulary as CharacterVisual.play: idle, walk, run, sprint, jump, fall, swim, fly,
## climb, attack, hit, death. Unknown or missing clips fall back to the move clip or idle.
func play(state: String, speed := 1.0) -> void:
	if anim == null:
		return
	var c := state
	match state:
		"walk", "run", "sprint", "climb":
			c = move_clip()
		"jump", "fall":
			c = "fly" if has_clip("fly") else "idle"
		"swim":
			c = "swim" if has_clip("swim") else move_clip()
		"fly":
			c = "fly" if has_clip("fly") else move_clip()
		"attack":
			c = "attack_melee"
	if c == "" or not anim.has_animation(c):
		c = "idle" if anim.has_animation("idle") else ""
	if c == "":
		return
	var one := not c in LOOPING
	if not one:
		_loop_clip = c
	if c == current_clip and anim.is_playing():
		anim.speed_scale = speed if not one else 1.0
		return
	if current_clip != "" and not current_clip in LOOPING and anim.is_playing() and not one:
		_loop_clip = c   # let the one-shot finish
		return
	current_clip = c
	anim.play(c, 0.15)
	anim.speed_scale = speed if not one else 1.0

func _on_finished(a: StringName) -> void:
	if String(a) in HOLD_LAST:
		return
	if not String(a) in LOOPING:
		current_clip = _loop_clip
		anim.play(_loop_clip, 0.15)
