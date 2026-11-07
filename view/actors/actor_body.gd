## One actor on screen: the body Looks.resolve() chose (monster-forge GLB, Synty model or a
## tinted primitive), an optional nameplate, side-view facing with a quick turn, and
## animation driven by a state string. WorldView owns these (add_actor / move_actor).
##
## Node: position = the Body's feet (tile units * K.TILE_M), z = 0 (the actor plane).
## Swings, the roll and the flinch are laid over the state (swing, roll, flinch, hold): they run
## on the view's clock from combat events and never touch the state string. set_rim outlines
## the actor (the target highlight, a monster's wind-up), flash lights it for a moment.
##
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
const RIM := preload("res://view/actors/rim.gdshader")
const FLASH := preload("res://view/actors/flash.gdshader")
static var _rim_mat: ShaderMaterial
static var _flash_mat: ShaderMaterial

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
## Consecutive actions walk along the tempo's moves.
var _combo := 0
var _combo_t := -INF
## Seconds a swing keeps the body turned to `_face` (a swing goes where it is aimed, even
## behind the way the feet run).
var _face_s := 0.0
var _face := 1
## The primitive's stand-in swing: seconds left of a lean, and its length; a spin for the roll.
var _lean := 0.0
var _lean_len := 0.0
var _spin := 0.0
var _spin_len := 0.0
var _rim := Color(0, 0, 0, 0)
var _flash := Color(0, 0, 0, 0)
var _flash_s := 0.0
var _flash_len := 0.0
var _hold := 0.0
var _weapon_bar: Node3D

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
	nameplate.pixel_size = 0.006
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
	_face_s = maxf(0.0, _face_s - delta)
	var moving := absf(vel.x) > float(CombatTempo.section("feel").get("moving_speed", 1.5))
	if _hold > 0.0:
		_hold -= delta
	elif kind != "primitive":
		visual.call("step", delta, moving)
	_step_primitive(delta)
	_step_flash(delta)
	var want := SIDE_YAW * (_face if _face_s > 0.0 else facing)
	if state == "climb":
		want = PI
	var step := (PI / TURN_TIME) * delta
	var d := angle_difference(_yaw, want)
	_yaw = want if absf(d) <= step else _yaw + signf(d) * step
	_apply_yaw()

func _apply_yaw() -> void:
	if turn != null:
		turn.rotation.y = _yaw

# --- what is laid over the state --------------------------------------------------------

## A SWING event's fields. dir: toward its aim. A body with nothing to show just turns and leans.
func swing(ev: Dictionary, dir: Vector2) -> void:
	var f := CombatTempo.section("feel")
	var total := float(ev.get("total", 0.0))
	_face = 1 if dir.x >= 0.0 else -1
	_face_s = maxf(total, 0.25)
	var now := Time.get_ticks_msec() / 1000.0
	if now - _combo_t > float(f.get("combo_reset_s", 1.2)):
		_combo = 0
	_combo_t = now
	var done := false
	var fi := float(f.get("fade_in_s", 0.05))
	var fo := float(f.get("fade_out_s", 0.12))
	match kind:
		"synty":
			done = (visual as CharacterVisual).swing(SwingPlan.build(ev, _combo), fi, fo, SwingPlan.HEAD_START)
		"forge":
			var m := visual as ForgeMonster
			var ranged := int(ev.get("mode", 0)) in [CombatCodec.Mode.RANGED, CombatCodec.Mode.THROW]
			var c := "attack_ranged" if ranged and m.has_clip("attack_ranged") else "attack_melee"
			if int(ev.get("mode", 0)) in [CombatCodec.Mode.AREA, CombatCodec.Mode.CAST, CombatCodec.Mode.SAVE_ACTION]:
				c = "breath" if m.has_clip("breath") else c
			done = m.swing(c, float(ev.get("windup", 0.0)), total, fi, fo)
	if not done and kind == "primitive":
		_lean_len = maxf(total, 0.25)
		_lean = _lean_len
	_combo += maxi(1, int(ev.get("swings", 1)))

func stop_swing() -> void:
	_face_s = 0.0
	_lean = 0.0
	if kind != "primitive":
		visual.call("stop_swing")

## The dodge roll's look: the clip over dur seconds, or a tucked spin of a body without one.
func roll(dur: float) -> void:
	_face_s = 0.0
	var done := false
	if kind == "synty":
		var fade: Array = CombatTempo.section("feel").get("roll_fade_s", [0.03, 0.06])
		done = (visual as CharacterVisual).swing(SwingPlan.single("roll", dur), float(fade[0]), float(fade[1]))
	if not done:
		_spin_len = dur
		_spin = dur

## A blow landed on this actor.
func flinch() -> void:
	var f := CombatTempo.section("feel")
	var s := float(f.get("flinch_s", 0.35))
	match kind:
		"synty":
			var cv := visual as CharacterVisual
			if cv.layer != null and not cv.layer.active():
				cv.swing(SwingPlan.single("flinch", s), 0.02, 0.1)
		"forge":
			(visual as ForgeMonster).flash_clip("hit", s, 0.02, 0.1)
		_:
			_lean_len = s * 0.6
			_lean = _lean_len

## The hit-stop: this body's animation stands still for s seconds of view time.
func hold(s: float) -> void:
	_hold = maxf(_hold, s)

## The weapon in the hand (an SRD slug, or a shown name; "" for none).
func set_weapon(what: String) -> void:
	var slug := what.strip_edges().to_lower().replace(" ", "-")
	if kind != "primitive":
		visual.call("set_weapon", slug)
		_geos_dirty = true
		return
	if _weapon_bar != null:
		_weapon_bar.queue_free()
		_weapon_bar = null
	if slug == "":
		return
	_weapon_bar = WeaponMesh.build(Looks.weapon(slug) if not Looks.weapon(slug).is_empty() else {}, size.y * K.TILE_M / 1.8)
	_weapon_bar.position = Vector3(0, size.y * 0.5 * K.TILE_M, size.x * 0.55 * K.TILE_M)
	_weapon_bar.rotation.x = deg_to_rad(60.0)
	visual.add_child(_weapon_bar)
	_geos_dirty = true

var _geos: Array = []
var _geos_dirty := true

func _surfaces() -> Array:
	if _geos_dirty:
		_geos_dirty = false
		_geos = find_children("*", "GeometryInstance3D", true, false).filter(func(g: Node) -> bool: return not g is Label3D)
	return _geos

## Outline this actor (alpha 0: none). One colour at a time.
func set_rim(c: Color) -> void:
	if c == _rim:
		return
	_rim = c
	if _flash_s <= 0.0:
		_apply_overlay()

## Light the whole body in `c` for s seconds, fading.
func flash(c: Color, s: float) -> void:
	_flash = c
	_flash_s = s
	_flash_len = maxf(s, 0.01)
	_apply_overlay()

func _apply_overlay() -> void:
	if _rim_mat == null:
		_rim_mat = ShaderMaterial.new()
		_rim_mat.shader = RIM
		_rim_mat.set_shader_parameter("width_m", float(CombatTempo.section("feel").get("rim_m", 0.035)))
		_flash_mat = ShaderMaterial.new()
		_flash_mat.shader = FLASH
	var over: Material = null
	if _flash_s > 0.0:
		over = _flash_mat
	elif _rim.a > 0.0:
		over = _rim_mat
	for g: GeometryInstance3D in _surfaces():
		if is_instance_valid(g):
			g.material_overlay = over
			if over == _rim_mat:
				g.set_instance_shader_parameter("rim", _rim)

func _step_flash(delta: float) -> void:
	if _flash_s <= 0.0:
		return
	_flash_s -= delta
	var c := _flash
	c.a *= clampf(_flash_s / _flash_len, 0.0, 1.0) * 0.5 + 0.5
	if _flash_s <= 0.0:
		_apply_overlay()
		return
	for g: GeometryInstance3D in _surfaces():
		if is_instance_valid(g):
			g.set_instance_shader_parameter("flash", c)

func _step_primitive(delta: float) -> void:
	if kind != "primitive" or state == "death":
		return
	if _lean > 0.0:
		_lean = maxf(0.0, _lean - delta)
		visual.rotation.x = sin((1.0 - _lean / _lean_len) * PI) * 0.6
	if _spin > 0.0:
		_spin = maxf(0.0, _spin - delta)
		visual.rotation.x = (1.0 - _spin / _spin_len) * TAU

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
