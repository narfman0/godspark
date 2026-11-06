## Plays a SwingPlan over the locomotion a body's AnimationPlayer already wrote this frame:
## bones are read from the clip's tracks and laid over the pose with a short fade in and out.
## The legs keep running while the body moves (only the bones above `upper_from` take the
## swing) and join in when it stands. The layer owns its clock: what holds step() holds it.
##
##   layer = SwingLayer.new(skeleton)
##   layer.add_clip("light", animation, skeleton_path_prefix)
##   layer.start(plan, fade_in, fade_out, skip)
##   layer.step(dt, moving)                    # each frame, after the AnimationPlayer
class_name SwingLayer
extends RefCounted

## A swing's clock jumping more than this inside a clip, or changing clips, crosses over.
const JUMP := 0.2
const CROSS := 0.05

var skel: Skeleton3D
## clip name -> [rot rows [bone, track, upper], pos rows [bone, track], Animation]
var clips := {}
var plan: Array = []
var t := -1.0
var fade_in := 0.05
var fade_out := 0.1
## The share of the pose below the waist this swing takes (1 standing, 0 running).
var lower := 1.0
var _end := 0.0
var _upper := {}
var _clip := ""
var _time := 0.0
var _from := ["", 0.0]
var _cross := 0.0

func _init(s: Skeleton3D, upper_from: PackedStringArray = []) -> void:
	skel = s
	for i in s.get_bone_count():
		var p := s.get_bone_parent(i)
		_upper[i] = upper_from.is_empty() or s.get_bone_name(i) in upper_from or (p >= 0 and bool(_upper.get(p, false)))

func has_clip(name: String) -> bool:
	return clips.has(name)

## Index a clip's tracks by bone. The Animation may come from a retarget or a forge file.
func add_clip(name: String, a: Animation) -> void:
	var rot: Array = []
	var pos: Array = []
	for tr in a.get_track_count():
		var path := a.track_get_path(tr)
		var bone := String(path.get_concatenated_subnames())
		if bone == "":
			bone = String(path.get_name(path.get_name_count() - 1))
		var b := skel.find_bone(bone)
		if b < 0:
			continue
		match a.track_get_type(tr):
			Animation.TYPE_ROTATION_3D:
				rot.append([b, tr, bool(_upper.get(b, true))])
			Animation.TYPE_POSITION_3D:
				pos.append([b, tr])
	clips[name] = [rot, pos, a]

func active() -> bool:
	return t >= 0.0

## skip: seconds of the plan already gone.
func start(new_plan: Array, f_in := 0.05, f_out := 0.1, skip := 0.0) -> void:
	plan = new_plan
	fade_in = f_in
	fade_out = f_out
	_end = SwingPlan.length(plan)
	t = skip
	_clip = ""
	_cross = 0.0

## End now, with a short fade (a cancelled wind-up).
func stop() -> void:
	if active() and t < _end - fade_out:
		_end = t + fade_out

func weight() -> float:
	var w := 1.0
	if fade_in > 0.0:
		w = minf(w, t / fade_in)
	if fade_out > 0.0:
		w = minf(w, (_end - t) / fade_out)
	return clampf(w, 0.0, 1.0)

## After the base animation has been advanced this frame. moving: the body is travelling.
func step(dt: float, moving: bool) -> void:
	if not active():
		return
	lower = move_toward(lower, 0.0 if moving else 1.0, dt * 8.0)
	t += dt
	if t >= _end:
		t = -1.0
		plan = []
		return
	var at := SwingPlan.at(plan, t)
	var name := String(at.get("clip", ""))
	if name != _clip or absf(float(at.get("time", 0.0)) - _time) > JUMP:
		# a move that does not pick up where the last one stopped: cross over from that pose
		if _clip != "" and clips.has(_clip):
			_from = [_clip, _time]
			_cross = CROSS
		_clip = name
	_time = float(at.get("time", 0.0))
	var w := weight()
	if _cross > 0.0:
		_cross = maxf(0.0, _cross - dt)
		_lay(_from[0], _from[1], w)
	_lay(name, _time, w * (1.0 - _cross / CROSS))

func _lay(clip: String, time: float, w: float) -> void:
	var row: Array = clips.get(clip, [])
	if row.is_empty():
		return
	var a: Animation = row[2]
	time = minf(time, a.length)
	for r: Array in row[0]:
		var k := w if bool(r[2]) else w * lower
		if k <= 0.001:
			continue
		var b: int = r[0]
		skel.set_bone_pose_rotation(b, skel.get_bone_pose_rotation(b).slerp(a.rotation_track_interpolate(r[1], time), k))
	var kl := w * lower
	if kl > 0.001:
		for r: Array in row[1]:
			var b: int = r[0]
			skel.set_bone_pose_position(b, skel.get_bone_pose_position(b).lerp(a.position_track_interpolate(r[1], time), kl))
