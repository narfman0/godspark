## One actor on screen: the body Looks.resolve() chose (monster-forge GLB, Synty model or a
## tinted primitive), an optional nameplate, side-view facing with a quick turn, and
## animation driven by a state string. WorldView owns these (add_actor / move_actor).
##
## Node: position = the Body's feet (tile units * K.TILE_M), z = 0 (the actor plane).
##   ActorBody
##     turn          yaws: the body faces +Z inside it; turned toward +-X (a little toward
##                   the camera so faces read), or away from the camera on a ladder
##       <visual>    ForgeMonster | CharacterVisual | primitive capsule + nose
##     nameplate     Label3D over the box (when the plan asks for one)
##
## States (move_actor's `state`; see docs/tracks/assets.md):
##   idle, walk, run (picked from horizontal speed: walk / run / sprint clips, speed-scaled),
##   jump (rising), fall, climb (ladder or wall), swim, fly,
##   attack, hit (one-shots, fired when the state changes to them), death / dead (held).
## ActorBody.state_for(body) derives one from a core Body.
class_name ActorBody
extends Node3D

## Yaw toward +X when facing right; < PI/2 so the model turns its front a little to the
## camera (which looks down -Z from +Z).
const SIDE_YAW := PI * 0.5 - 0.3
const TURN_TIME := 0.12
## Authored clip speeds (m/s) for a 1.8 m Synty character.
const WALK_MPS := 1.4
const RUN_MPS := 3.6
const SPRINT_MPS := 6.0

var plan: Dictionary = {}
var size := Vector2(1.5, 2.5)
var kind := "primitive"         ## forge | synty | primitive
var visual: Node3D              ## the body node under `turn`
var turn: Node3D
var nameplate: Label3D
var state := "idle"
var facing := 1
var vel := Vector2.ZERO         ## tiles/s, from move_actor or estimated from positions
var _yaw := SIDE_YAW
var _last_pos := Vector2.INF
var _last_usec := 0
var _explicit_vel := false

## Builds the actor for a look. primitive_mat: the placeholder shader material (WorldView's).
static func build(look: Dictionary, primitive_mat: Material, has_file: Callable = Callable()) -> ActorBody:
	var a := ActorBody.new()
	a.plan = Looks.resolve(look, has_file)
	a.size = a.plan["size"]
	a.turn = Node3D.new()
	a.turn.name = "turn"
	a.add_child(a.turn)
	match String(a.plan["body"]):
		"forge":
			a._build_forge()
		"synty":
			a._build_synty()
	if a.visual == null:
		a._build_primitive(primitive_mat, a.plan.get("color", Color(0.8, 0.7, 0.55)))
	if a.plan.get("nameplate", false) and String(a.plan.get("name", "")) != "":
		a._build_nameplate(String(a.plan["name"]))
	a._apply_yaw()
	return a

func _build_forge() -> void:
	var m := ForgeMonster.load_monster(String(plan["slug"]))
	if m == null:
		return
	# Native metres; shrink (never grow) so it stays near its collision box.
	var t := K.TILE_M
	var h := maxf(m.aabb.size.y, 0.01)
	var long := maxf(maxf(m.aabb.size.x, m.aabb.size.z), 0.01)
	var s := minf(1.0, minf(size.y * t * 1.15 / h, size.x * t * 2.2 / long)) * float(plan.get("scale", 1.0))
	m.scale = Vector3.ONE * s
	LitMaterials.set_tint(m, plan.get("tint", Color.WHITE))
	m.name = "forge"
	turn.add_child(m)
	visual = m
	kind = "forge"
	m.play("idle")

func _build_synty() -> void:
	var cv := CharacterVisual.new()
	if not cv.setup(plan["model_def"], Looks.table().get("clips", {}), float(plan["height_m"])):
		cv.free()
		return
	LitMaterials.set_tint(cv, plan.get("tint", Color.WHITE))
	cv.name = "synty"
	turn.add_child(cv)
	visual = cv
	kind = "synty"

func _build_primitive(mat: Material, color: Color) -> void:
	var t := K.TILE_M
	var root := Node3D.new()
	root.name = "primitive"
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = minf(size.x * 0.5, size.y * 0.5) * t
	cap.height = size.y * t
	cap.radial_segments = 12
	cap.rings = 4
	body.mesh = cap
	body.position.y = size.y * 0.5 * t
	body.material_override = mat
	body.set_instance_shader_parameter("tint", color)
	body.name = "body"
	root.add_child(body)
	var nose := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(size.x * 0.35, size.y * 0.12, size.x * 0.35) * t
	nose.mesh = box
	# The body faces +Z inside `turn`: the nose sits on its front.
	nose.position = Vector3(0, size.y * 0.78 * t, size.x * 0.5 * t)
	nose.material_override = mat
	nose.set_instance_shader_parameter("tint", color.darkened(0.45))
	nose.name = "nose"
	root.add_child(nose)
	turn.add_child(root)
	visual = root
	kind = "primitive"

func _build_nameplate(text: String) -> void:
	nameplate = Label3D.new()
	nameplate.name = "nameplate"
	nameplate.text = text
	nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nameplate.pixel_size = 0.004
	nameplate.font_size = 40
	nameplate.outline_size = 10
	nameplate.modulate = Color(1, 1, 1, 0.85)
	nameplate.no_depth_test = false
	nameplate.position = Vector3(0, size.y * K.TILE_M + 0.3, 0)
	add_child(nameplate)

## pos: feet, tile units. v: tiles/s (Vector2.INF: estimate from successive positions).
func update(pos: Vector2, new_facing: int, new_state: String, v := Vector2.INF) -> void:
	var now := Time.get_ticks_usec()
	if v != Vector2.INF:
		vel = v
		_explicit_vel = true
	elif _last_pos != Vector2.INF and not _explicit_vel:
		var dt := (now - _last_usec) / 1e6
		if dt > 0.0005:
			vel = vel.lerp((pos - _last_pos) / dt, 0.5)
	_last_pos = pos
	_last_usec = now
	position = Vector3(pos.x * K.TILE_M, pos.y * K.TILE_M, 0)
	if new_facing != 0:
		facing = 1 if new_facing > 0 else -1
	set_state(new_state)

func set_state(s: String) -> void:
	if s == "dead":
		s = "death"
	var changed := s != state
	state = s
	if kind == "primitive":
		visual.rotation.z = PI * 0.5 if s == "death" else 0.0
		return
	if s in ["attack", "hit"] and not changed:
		return   # one-shots fire on entry only
	var clip := s
	var speed := 1.0
	var h: float = float(plan.get("height_m", 1.8))
	var k := (h if h > 0.0 else 1.8) / 1.8
	var mps := absf(vel.x) * K.TILE_M
	match s:
		"idle", "walk", "run":
			if mps < 0.25:
				clip = "idle"
			elif mps < 2.2 * k:
				clip = "walk"
				speed = clampf(mps / (WALK_MPS * k), 0.6, 1.8)
			elif mps < 5.0 * k:
				clip = "run"
				speed = clampf(mps / (RUN_MPS * k), 0.7, 1.6)
			else:
				clip = "sprint"
				speed = clampf(mps / (SPRINT_MPS * k), 0.8, 1.8)
		"climb":
			clip = "walk"
			speed = clampf(absf(vel.y) * K.TILE_M / (WALK_MPS * k), 0.0, 1.8)
		"swim":
			clip = "swim" if kind == "forge" else "walk"
			speed = 0.7
	visual.call("play", clip, speed)

func _process(delta: float) -> void:
	var want := SIDE_YAW * facing
	if state == "climb":
		want = PI
	var step := (PI / TURN_TIME) * delta
	var d := angle_difference(_yaw, want)
	_yaw = want if absf(d) <= step else _yaw + signf(d) * step
	_apply_yaw()

func _apply_yaw() -> void:
	if turn != null:
		turn.rotation.y = _yaw

## Snap the turn (no animation), e.g. right after spawning.
func snap_facing() -> void:
	_yaw = PI if state == "climb" else SIDE_YAW * facing
	_apply_yaw()

## The state a core Body is in, for move_actor.
static func state_for(body: Body) -> String:
	if body.climbing or body.clinging:
		return "climb"
	if body.swimming:
		return "swim"
	if body.flying and not body.on_floor:
		return "fly"
	if not body.on_floor:
		return "jump" if body.vel.y > 0.0 else "fall"
	return "run" if absf(body.vel.x) > 0.3 else "idle"
