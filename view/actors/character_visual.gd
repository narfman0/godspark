## A Synty model as an actor's body: loaded at runtime (GltfCache), re-materialed to read the
## tile light (LitMaterials), scaled to a height with its feet at the origin, and, for
## humanoids, driven by the Synty animation packs retargeted onto its rig (AnimRetarget).
## Ported from glitchbound's scripts/world/character_visual.gd; the model table moved to
## data/looks.json, and the outline, fill light and CharacterBody3D coupling were dropped.
##
##   var cv := CharacterVisual.new()
##   if cv.setup(model_def, clip_table, 1.8): add_child(cv)    # false: files missing
##   cv.play("run", 1.3)       # idle | walk | run | sprint | jump | fall | attack | hit | death
##
## The model faces +Z (Synty's own front). ActorBody turns it.
## One-shots (attack, hit) return to the last looping clip and emit `finished`; death holds.
##
## Swings (SwingPlan segments) are a SwingLayer over the locomotion, so the legs can keep
## running under them; the AnimationPlayer is stepped by hand from step() to come first.
##   cv.swing(plan, fade_in, fade_out); cv.set_weapon("longsword")
class_name CharacterVisual
extends Node3D

signal finished(clip: String)

const ONESHOTS := ["attack", "hit", "jump"]
const HOLDS := ["death"]
## Clips whose hip travel is kept (falls forward); the rest run in place.
const KEEP_ROOT := ["death"]

var model: Node3D
var anim: AnimationPlayer
var height_m := 1.8
var clip := ""
var _loop_clip := "idle"
var _oneshot := false
var _static_anim := ""
var skeleton: Skeleton3D
var layer: SwingLayer
var weapon := ""
var _weapon_node: Node3D
var _rig_id := ""

## def: {path, show?, set?, clip?}; clips: data/looks.json "clips". Returns false (and
## builds nothing) when the model file is not there.
func setup(def: Dictionary, clips: Dictionary, height: float) -> bool:
	var path: String = def.get("path", "")
	model = GltfCache.instance(path)
	if model == null:
		return false
	model.name = "Model"
	add_child(model)
	var show: Array = def.get("show", [])
	if not show.is_empty():
		for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			mi.visible = String(mi.name) in show
			if not mi.visible:
				mi.queue_free()   # a multi-character file: keep only this one's meshes
	LitMaterials.apply(model)
	height_m = height
	_fit_height(height)
	var rig_set: String = def.get("set", "")
	if rig_set != "" and clips.has(rig_set):
		_build_animations(path, clips[rig_set], clips.get("actions", {}))
	else:
		_own_animation(def)
	play("idle")
	return true

func has_clip(c: String) -> bool:
	return anim != null and anim.has_animation(c)

## Plays a clip (falls back: sprint -> run -> walk, fall -> jump -> idle). speed scales
## playback. A running one-shot is not interrupted by locomotion.
func play(c: String, speed := 1.0) -> void:
	if anim == null:
		clip = c
		return
	if _static_anim != "":
		anim.speed_scale = speed if c in ["walk", "run", "sprint"] else 1.0
		return
	var want := _resolve(c)
	if want == "":
		return
	var one := want in ONESHOTS
	if _oneshot and clip != "jump" and not one and not want in HOLDS:
		_loop_clip = want
		return
	if want == clip and (anim.is_playing() or want in HOLDS):
		if not one:
			anim.speed_scale = speed
		return   # a held clip (death) plays once and keeps its last pose
	if want == "jump" and clip == "fall":
		return   # a jump that already turned into a fall stays a fall
	if not one and not want in HOLDS:
		_loop_clip = want
	_oneshot = one
	clip = want
	anim.play(want, 0.0 if want in HOLDS else 0.15)
	anim.speed_scale = speed if not one else 1.0

func _resolve(c: String) -> String:
	var chain: Array = {"sprint": ["sprint", "run", "walk"], "run": ["run", "walk"],
		"walk": ["walk", "run"], "fall": ["fall", "jump", "idle"], "jump": ["jump", "fall", "idle"],
		"death": ["death"], "attack": ["attack"], "hit": ["hit"]}.get(c, [c, "idle"])
	for x: String in chain:
		if anim.has_animation(x):
			return x
	return ""

func _on_finished(a: StringName) -> void:
	var s := String(a)
	if s in ONESHOTS:
		_oneshot = false
		clip = ""
		play(_loop_clip if s != "jump" else "fall")
		finished.emit(s)
	elif s in HOLDS:
		finished.emit(s)

func _fit_height(h: float) -> void:
	var box := _skinned_aabb()
	if box.size.y > 0.01:
		var s := h / box.size.y
		model.scale = Vector3.ONE * s
		model.position.y = -box.position.y * s

## Rest-pose AABB of the visible meshes in the model's own space (skinned meshes where the
## skin draws them; Synty item attachments on bones are left out, they are small).
func _skinned_aabb() -> AABB:
	var out := AABB()
	var first := true
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if not mi.visible or mi.is_queued_for_deletion() or mi.mesh == null:
			continue
		if mi.get_parent() is BoneAttachment3D:
			continue
		var b: AABB = GltfCache.mesh_xform(mi, model) * mi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out

func _build_animations(rig_id: String, loco: Dictionary, actions: Dictionary) -> void:
	var skels: Array = model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	var skel: Skeleton3D = skels[0]
	skeleton = skel
	_rig_id = rig_id
	layer = SwingLayer.new(skel, PackedStringArray(SwingPlan.conf().get("upper_from", [])))
	# The file's own player (a T-pose "Take 001") would fight ours.
	for ap: AnimationPlayer in model.find_children("*", "AnimationPlayer", true, false):
		ap.stop()
		ap.queue_free()
	anim = AnimationPlayer.new()
	anim.name = "AnimationPlayer"
	model.add_child(anim)
	var skel_path := str(model.get_path_to(skel))
	var lib := AnimationLibrary.new()
	for c: String in loco:
		var a: Animation = AnimRetarget.load_clip(loco[c], skel_path, skel, rig_id, c != "jump", model, true)
		if a:
			lib.add_animation(c, a)
	for c: String in actions:
		var a: Animation = AnimRetarget.load_clip(actions[c], skel_path, skel, rig_id, false, model, not c in KEEP_ROOT)
		if a:
			lib.add_animation(c, a)
	if lib.get_animation_list().is_empty():
		anim.queue_free()
		anim = null
		return
	anim.add_animation_library("", lib)
	anim.animation_finished.connect(_on_finished)
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL

## Retargeted swing clips, on first need (a town full of rigs never loads the ones it does
## not swing). Returns false when the clip's file is not there.
func load_swing_clip(name: String) -> bool:
	if layer == null:
		return false
	if layer.has_clip(name):
		return true
	var path := String(SwingPlan.conf().get("clips", {}).get(name, ""))
	var a: Animation = AnimRetarget.load_clip(path, str(model.get_path_to(skeleton)), skeleton, _rig_id, false, model, true, SwingPlan.span(name))
	if a == null:
		return false
	layer.add_clip(name, a)
	return true

## Play a plan over the movement. False when this body has no clip for it.
func swing(plan: Array, f_in: float, f_out: float, skip := 0.0) -> bool:
	if layer == null or plan.is_empty():
		return false
	for seg: Dictionary in plan:
		if not load_swing_clip(String(seg["clip"])):
			return false
	layer.start(plan, f_in, f_out, skip)
	return true

func stop_swing() -> void:
	if layer != null:
		layer.stop()

## Each frame, from the actor: the movement first, then what lies over it.
func step(delta: float, moving: bool) -> void:
	if anim == null or _static_anim != "":
		return
	anim.advance(delta)
	layer.step(delta, moving)

## The weapon in the hand: an SRD slug, "" for none. Its row in data/looks.json "weapons", or a
## plain bar when it has none or the file is missing.
func set_weapon(slug: String) -> void:
	if slug == weapon or skeleton == null:
		return
	weapon = slug
	if _weapon_node != null:
		_weapon_node.get_parent().remove_child(_weapon_node)
		_weapon_node.queue_free()
		_weapon_node = null
	if slug == "":
		return
	var row := Looks.weapon(slug)
	var left := bool(row.get("left", false))
	var bone_name := "Hand_L" if left else "Hand_R"
	var bone := skeleton.find_bone(bone_name)
	if bone < 0:
		return
	var binds := AnimRetarget.bind_globals(model, skeleton)
	var bind: Transform3D = binds.get(bone_name, Transform3D.IDENTITY)
	var conf: Dictionary = Looks.table().get("weapons", {})
	var grip: Dictionary = conf.get("grip", {})
	var mesh := WeaponMesh.build(row, height_m / 1.8)
	var rot: Array = row.get("rot_deg", grip.get("rot_deg", [90, 0, 0]))
	var off: Array = grip.get("offset_m", [0, 0, 0])
	# bone -> the T-posed mesh's space, which every rig shares: from there a grip is one number
	var to_bone := bind.affine_inverse()
	var world_per_unit := (GltfCache.chain(skeleton, self) * skeleton.get_bone_global_rest(bone) * to_bone).basis.get_scale().x
	var r := Basis.from_euler(Vector3(deg_to_rad(float(rot[0])), deg_to_rad(float(rot[1])), deg_to_rad(float(rot[2]))))
	var at := Vector3(float(off[0]) * (-1.0 if left else 1.0), float(off[1]), float(off[2])) / world_per_unit
	var att := BoneAttachment3D.new()
	att.bone_name = bone_name
	skeleton.add_child(att)
	var hold_node := Node3D.new()
	hold_node.transform = to_bone * Transform3D(r.scaled(Vector3.ONE / world_per_unit), bind.origin + at)
	att.add_child(hold_node)
	hold_node.add_child(mesh)
	_weapon_node = att

## Static Synty creatures (SIMPLE animals) carry one baked take; play it only when the
## model def names it (clip: true), else hold the bind pose.
func _own_animation(def: Dictionary) -> void:
	var aps: Array = model.find_children("*", "AnimationPlayer", true, false)
	if aps.is_empty():
		return
	var ap: AnimationPlayer = aps[0]
	if not def.get("clip", false) or ap.get_animation_list().is_empty():
		ap.stop()
		return
	anim = ap
	_static_anim = ap.get_animation_list()[0]
	ap.get_animation(_static_anim).loop_mode = Animation.LOOP_LINEAR
	ap.play(_static_anim)
