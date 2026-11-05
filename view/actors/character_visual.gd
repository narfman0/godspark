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
