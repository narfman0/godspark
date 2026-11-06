## Retargets Synty POLYGON animation clips (classic rig: Root, Hips, Spine_01,
## UpperLeg_L…) onto any Synty humanoid: the classic rig itself (Dark Fantasy) or the
## UE-style rig (Pelvis, spine_01, Thigh_L… : Fantasy Characters, Dungeon heroes, zombies).
##
## Synty's cooked rigs disagree about skeleton space: the classic rig carries a -90° X Root
## and centimetres, with the Y-up correction folded into its skin bind poses; the UE-style
## files are Y-up metres with bind == rest. So rotations are matched in *bind space*, the
## space the authored T-pose mesh lives in, which both rigs share. Per sample time:
##
##   G_src(b)  = forward kinematics of the clip on the classic skeleton
##   G_dst(b') = G_src(b) · bind_src(b)⁻¹ · bind_dst(b')        (b' = mapped bone)
##   L_dst(b') = G_dst(parent(b'))⁻¹ · G_dst(b')                 (unmapped bones keep rest)
##
## At the bind (T-)pose this reproduces each rig's own bind exactly, and any motion is the
## same world-space rotation on both. The hips also get a translation track: the clip's hip
## offset from its bind position, scaled by the hip-height ratio, so deaths reach the floor.
##
## Ported from glitchbound (scripts/world/anim_retarget.gd). Godspark change: clips and the
## reference character load at runtime through GltfCache (the fetched tree is never imported),
## the reference path comes from data/looks.json ("clips.ref"), a missing file returns null
## quietly, and `strip_root_motion` drops the hips' horizontal travel (side view: the Body
## moves the actor, the clip must run in place).
class_name AnimRetarget
extends RefCounted

## classic-rig bone → UE-style bone. Absent targets fall back to the same name.
const BONE_MAP := {
	"Hips": "Pelvis",
	"Spine_01": "spine_01", "Spine_02": "spine_02", "Spine_03": "spine_03",
	"Neck": "neck_01", "Head": "head",
	"Clavicle_L": "clavicle_l", "Shoulder_L": "UpperArm_L", "Elbow_L": "lowerarm_l", "Hand_L": "Hand_L",
	"Clavicle_R": "clavicle_r", "Shoulder_R": "UpperArm_R", "Elbow_R": "lowerarm_r", "Hand_R": "Hand_R",
	"UpperLeg_L": "Thigh_L", "LowerLeg_L": "calf_l", "Ankle_L": "Foot_L", "Ball_L": "ball_l", "Toes_L": "toes_l",
	"UpperLeg_R": "Thigh_R", "LowerLeg_R": "calf_r", "Ankle_R": "Foot_R", "Ball_R": "ball_r", "Toes_R": "toes_r",
}
const SAMPLE_FPS := 30.0

## The locomotion pack's skinned reference character: bind poses of the classic rig.
## Set from data/looks.json ("clips.ref") by Looks.
static var ref_character := "res://assets/meshes/ANIMATION_Base_Locomotion_SourceFiles_v3/SourceFiles/Character/PolygonSyntyCharacter.glb"

static var _clip_cache: Dictionary = {}
static var _ref_bind: Dictionary = {}  ## bone name → bind global (bone → mesh space)

static func target_bone(target: Skeleton3D, src_bone: String) -> int:
	if BONE_MAP.has(src_bone):
		var i := target.find_bone(BONE_MAP[src_bone])
		if i >= 0:
			return i
	return target.find_bone(src_bone)

static func _global_rest(skel: Skeleton3D, idx: int) -> Transform3D:
	var t := skel.get_bone_rest(idx)
	var p := skel.get_bone_parent(idx)
	while p >= 0:
		t = skel.get_bone_rest(p) * t
		p = skel.get_bone_parent(p)
	return t

## The skeleton node's transform relative to `stop` (its scene root), e.g. a cooked
## "Armature" parent carrying a 0.01 scale and a Z-up→Y-up rotation.
static func scene_space(skel: Skeleton3D, stop: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = skel
	while n != null and n != stop:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t

## Bind globals (bone → scene space) of every bone a skin binds under `root`; bones no skin
## binds get their rest relative to the nearest bound ancestor.
static func bind_globals(root: Node, skel: Skeleton3D) -> Dictionary:
	var out := {}
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.skin == null:
			continue
		for i in mi.skin.get_bind_count():
			var bone := mi.skin.get_bind_name(i)
			if bone == "":
				bone = skel.get_bone_name(mi.skin.get_bind_bone(i))
			if not out.has(bone):
				out[bone] = mi.skin.get_bind_pose(i).affine_inverse()
	var space := scene_space(skel, root)
	for i in skel.get_bone_count():
		var name := skel.get_bone_name(i)
		if out.has(name):
			continue
		var p := skel.get_bone_parent(i)
		var parent_g: Transform3D = out.get(skel.get_bone_name(p), space * _global_rest(skel, p)) if p >= 0 else space
		out[name] = parent_g * skel.get_bone_rest(i)
	return out

static func _load_reference() -> bool:
	if not _ref_bind.is_empty():
		return true
	var inst: Node = GltfCache.instance(ref_character)
	if inst == null:
		return false
	var skels: Array = inst.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		_ref_bind = bind_globals(inst, skels[0])
	inst.free()
	return not _ref_bind.is_empty()

## A retargeted Animation for `target` (tracks addressed by skeleton_path from the
## AnimationPlayer's root node). model_root owns target's skins. rig_id keys the cache.
## span (from, to seconds): sample only that stretch of the clip, its times kept.
static func load_clip(clip_path: String, skeleton_path: String, target: Skeleton3D,
		rig_id: String, loop := true, model_root: Node = null, strip_root_motion := true, span := Vector2.ZERO) -> Animation:
	var cache_key := "%s|%s|%s|%s" % [clip_path, skeleton_path, rig_id, span]
	if _clip_cache.has(cache_key):
		return _clip_cache[cache_key]
	if not GltfCache.exists(clip_path) or not _load_reference():
		return null
	var inst := GltfCache.instance(clip_path)
	if inst == null:
		return null
	var players: Array = inst.find_children("*", "AnimationPlayer", true, false)
	var skels: Array = inst.find_children("*", "Skeleton3D", true, false)
	if players.is_empty() or skels.is_empty():
		inst.free()
		return null
	var src_player: AnimationPlayer = players[0]
	var src_skel: Skeleton3D = skels[0]
	var list := src_player.get_animation_list()
	if list.is_empty():
		inst.free()
		return null
	var src: Animation = src_player.get_animation(list[0])
	var dst_bind := bind_globals(model_root if model_root else target, target)

	# Source tracks per bone
	var rot_track := {}
	var pos_track := {}
	for t in src.get_track_count():
		var bone := String(src.track_get_path(t)).get_slice(":", 1)
		match src.track_get_type(t):
			Animation.TYPE_ROTATION_3D: rot_track[bone] = t
			Animation.TYPE_POSITION_3D: pos_track[bone] = t

	# Destination bones driven by a source bone (dst idx → src name), in parent-first order
	var drive := {}
	for i in src_skel.get_bone_count():
		var sname := src_skel.get_bone_name(i)
		if not rot_track.has(sname) or not _ref_bind.has(sname):
			continue
		var d := target_bone(target, sname)
		if d >= 0 and dst_bind.has(target.get_bone_name(d)):
			drive[d] = sname

	var out := Animation.new()
	out.length = src.length
	out.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var out_track := {}
	for d: int in drive:
		var idx := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(idx, "%s:%s" % [skeleton_path, target.get_bone_name(d)])
		out_track[d] = idx
	var src_hips := src_skel.find_bone("Hips")
	var dst_hips := target_bone(target, "Hips")
	var hips_idx := -1
	var k_h := 1.0
	if pos_track.has("Hips") and src_hips >= 0 and dst_hips >= 0 and _ref_bind.has("Hips"):
		hips_idx = out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(hips_idx, "%s:%s" % [skeleton_path, target.get_bone_name(dst_hips)])
		var src_h := absf((_ref_bind["Hips"] as Transform3D).origin.y)
		var dst_h := absf((dst_bind[target.get_bone_name(dst_hips)] as Transform3D).origin.y)
		k_h = dst_h / src_h if src_h > 0.0001 else 1.0

	var src_space := scene_space(src_skel, inst)
	var dst_space := scene_space(target, model_root if model_root else target)
	var src_scale := src_space.basis.get_scale().x
	var dst_scale := dst_space.basis.get_scale().x
	var src_rot := src_space.basis.orthonormalized()
	var dst_rot := dst_space.basis.orthonormalized()
	var t0 := clampf(span.x, 0.0, src.length)
	var t1 := src.length if span == Vector2.ZERO else minf(span.y, src.length)
	var n := maxi(1, int(ceil((t1 - t0) * SAMPLE_FPS)))
	for f in n + 1:
		var time := minf(t0 + f / SAMPLE_FPS, t1)
		# Source forward kinematics in scene space (Synty skeletons list parents first)
		var rs: Array[Basis] = []
		var ps: Array[Vector3] = []
		rs.resize(src_skel.get_bone_count())
		ps.resize(src_skel.get_bone_count())
		for i in src_skel.get_bone_count():
			var sname := src_skel.get_bone_name(i)
			var lr := src_skel.get_bone_rest(i).basis.orthonormalized()
			var lp := src_skel.get_bone_rest(i).origin
			if rot_track.has(sname):
				lr = Basis(src.rotation_track_interpolate(rot_track[sname], time))
			if pos_track.has(sname):
				lp = src.position_track_interpolate(pos_track[sname], time)
			var p := src_skel.get_bone_parent(i)
			if p >= 0:
				rs[i] = rs[p] * lr
				ps[i] = ps[p] + rs[p] * (lp * src_scale)
			else:
				rs[i] = src_rot * lr
				ps[i] = src_space * lp
		# Destination: driven bones take the source's bind-relative rotation
		var rd: Array[Basis] = []
		var pd: Array[Vector3] = []
		rd.resize(target.get_bone_count())
		pd.resize(target.get_bone_count())
		for d in target.get_bone_count():
			var p := target.get_bone_parent(d)
			var rest := target.get_bone_rest(d)
			var parent_r: Basis = rd[p] if p >= 0 else dst_rot
			pd[d] = (pd[p] + rd[p] * (rest.origin * dst_scale)) if p >= 0 else dst_space * rest.origin
			if drive.has(d):
				var sname: String = drive[d]
				var s_i := src_skel.find_bone(sname)
				rd[d] = rs[s_i] * (_ref_bind[sname] as Transform3D).basis.orthonormalized().inverse() \
					* (dst_bind[target.get_bone_name(d)] as Transform3D).basis.orthonormalized()
				out.rotation_track_insert_key(out_track[d], time,
					(parent_r.inverse() * rd[d]).orthonormalized().get_rotation_quaternion())
			else:
				rd[d] = parent_r * rest.basis.orthonormalized()
		if hips_idx >= 0:
			# Hip offset from the T-(bind) pose, scaled to the target's hip height
			var off: Vector3 = ps[src_hips] - (_ref_bind["Hips"] as Transform3D).origin
			if strip_root_motion:
				off.x = 0.0
				off.z = 0.0
			var want := (dst_bind[target.get_bone_name(dst_hips)] as Transform3D).origin + off * k_h
			var p := target.get_bone_parent(dst_hips)
			var local := (rd[p].inverse() * (want - pd[p]) / dst_scale) if p >= 0 else dst_space.affine_inverse() * want
			out.position_track_insert_key(hips_idx, time, local)
	inst.free()
	_clip_cache[cache_key] = out
	return out
