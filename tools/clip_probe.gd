## Where a swing lands in an animation clip: plays each clip on its own skeleton and prints
## its length, the time the tip of a sword held in the right hand moves fastest (the visible
## contact: the times of data/looks.json "swings" moves come from here) and a coarse speed curve.
##   godot --headless -s res://tools/clip_probe.gd -- res://assets/meshes/<Pack>/clip.gltf [...]
##   godot --headless -s res://tools/clip_probe.gd -- swings      every clip in data/looks.json "swings"
##   godot --headless -s res://tools/clip_probe.gd -- forge=goblin-warrior   a forge monster's attack clips
## forge: the same for a monster-forge creature (ForgeMonster.contact_of decides at runtime).
extends SceneTree

const STEP := 1.0 / 60.0
## Metres from the hand to the sword's tip, along the forearm.
const BLADE := 0.8
## Below this share of the peak speed the tip counts as still.
const MOVING := 0.12

func _initialize() -> void:
	var paths: Array[String] = []
	var forge: Array[String] = []
	for a in OS.get_cmdline_user_args():
		if a == "swings":
			for p: Variant in Looks.table().get("swings", {}).get("clips", {}).values():
				paths.append(String(p))
		elif a.begins_with("forge="):
			forge.append(a.substr(6))
		else:
			paths.append(a)
	for p in paths:
		_probe(p)
	for f in forge:
		_forge(f)
	GltfCache.clear()
	quit(0)

## Forward kinematics of a clip at `time`, from its tracks: bone index -> pose in skeleton space.
static func _pose(a: Animation, sk: Skeleton3D, rot: Dictionary, pos: Dictionary, time: float) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	out.resize(sk.get_bone_count())
	for i in sk.get_bone_count():
		var rest := sk.get_bone_rest(i)
		var name := sk.get_bone_name(i)
		var b := rest.basis
		var o := rest.origin
		if rot.has(name):
			b = Basis(a.rotation_track_interpolate(rot[name], time))
		if pos.has(name):
			o = a.position_track_interpolate(pos[name], time)
		var p := sk.get_bone_parent(i)
		out[i] = Transform3D(b, o) if p < 0 else out[p] * Transform3D(b, o)
	return out

static func _tracks(a: Animation) -> Array:
	var rot := {}
	var pos := {}
	for t in a.get_track_count():
		var path := String(a.track_get_path(t))
		var bone := path.get_slice(":", 1)
		if bone == "":
			bone = path.get_file()
		match a.track_get_type(t):
			Animation.TYPE_ROTATION_3D: rot[bone] = t
			Animation.TYPE_POSITION_3D: pos[bone] = t
	return [rot, pos]

func _probe(path: String) -> void:
	var inst := GltfCache.instance(path)
	if inst == null:
		print("%-48s LOAD FAILED (%s)" % [path.get_file(), GltfCache.last_error])
		return
	var players := inst.find_children("*", "AnimationPlayer", true, false)
	var skels := inst.find_children("*", "Skeleton3D", true, false)
	if players.is_empty() or skels.is_empty():
		print("%-48s no animation" % path.get_file())
		inst.free()
		return
	var ap: AnimationPlayer = players[0]
	var sk: Skeleton3D = skels[0]
	var a := ap.get_animation(ap.get_animation_list()[0])
	var tr := _tracks(a)
	var hand := sk.find_bone("Hand_R")
	var elbow := sk.find_bone("Elbow_R")
	var hips := sk.find_bone("Hips")
	if hand < 0 or elbow < 0 or hips < 0:
		print("%-48s not the classic rig: %s" % [path.get_file(), sk.get_bone_name(0)])
		inst.free()
		return
	var last := Vector3.INF
	var curve: Array[float] = []
	var best := 0.0
	var best_t := 0.0
	var scale := AnimRetarget.scene_space(sk, inst).basis.get_scale().x
	var t := 0.0
	while t <= a.length + 1e-6:
		var g := _pose(a, sk, tr[0], tr[1], t)
		var fwd := (g[hand].origin - g[elbow].origin).normalized()
		var tip := (g[hand].origin - g[hips].origin) * scale + fwd * BLADE
		if last != Vector3.INF:
			var v := (tip - last).length() / STEP
			curve.append(v)
			if v > best:
				best = v
				best_t = t
		last = tip
		t += STEP
	var marks := PackedStringArray()
	var buckets := 20
	for i in buckets:
		var from := i * curve.size() / buckets
		var to := maxi(from + 1, (i + 1) * curve.size() / buckets)
		var m := 0.0
		for k in range(from, mini(to, curve.size())):
			m = maxf(m, curve[k])
		marks.append("%d" % roundi(m))
	# the swing proper: where the tip starts to move and where it has stopped, around the peak
	var i0 := int(best_t / STEP) - 1
	var from := i0
	while from > 0 and curve[from] > best * MOVING:
		from -= 1
	var to := i0
	while to < curve.size() - 1 and curve[to] > best * MOVING:
		to += 1
	print("%-46s len %.3f start %.3f contact %.3f end %.3f peak %.1f m/s  %s" % [path.get_file().get_basename(), a.length, from * STEP, best_t,
		to * STEP, best, " ".join(marks)])
	inst.free()

func _forge(id: String) -> void:
	var m := ForgeMonster.load_monster(id)
	if m == null:
		print("%s: %s" % [id, ForgeMonster.last_error])
		return
	for c: String in m.clips():
		if c.begins_with("attack") or c == "breath":
			var a := m.anim.get_animation(c)
			var at := m.contact_of(c)
			print("%-16s %-14s len %.3f contact %.3f (%.0f%%) tracks %d" % [id, c, a.length, at, 100.0 * at / maxf(a.length, 0.001), a.get_track_count()])
	m.free()
