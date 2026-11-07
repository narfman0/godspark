## Godot's lights over the tile light field, for the look: a sun (or moon) with shadows that
## follows the clock, and a pool of lamps with shadows on the nearest light sources (emissive
## tiles from the chunks' emitter lists, carried lights). The field still decides where light
## may fall (view/shaders/lit.gdshaderinc); these give it direction and shadow. Tunables in
## data/lighting.json "view": fill, toon, wrap, shine, sun, moon, lamps, max_lights,
## shadow_quality (off | low | high) and its table. Atmosphere too: dust in sunlit shafts (a sheet
## that follows the camera, view/shaders/dust.gdshader) and bloom on the bright (the environment's
## glow), each with an off switch.
##
##   var lights := WorldLights.new(); view.add_child(lights); lights.setup(view)
##   WorldLights.sun_dir(14.0)          # toward the sun at 14:00 (the moon at night)
##   WorldLights.pick(cands, focus, 24) # the nearest sources, nearest first
class_name WorldLights
extends Node3D

const T := K.TILE_M
const DUST_SHADER := preload("res://view/shaders/dust.gdshader")

var view: WorldView
var sun: DirectionalLight3D
var quality := "low"
var max_lights := 24
var _q := {}
var _pool: Array[OmniLight3D] = []
var _keys: Array[String] = []        ## pool index -> source key ("" free)
var _env_id := 0
var _time := 0.0
var _dust: MeshInstance3D
## The sources lit last frame, nearest first: [{key, pos, color, radius, level}] (for tests, tools).
var lit: Array = []
## Do the world's dressing (trees, rocks, plants) cast shadows, by the quality's "dressing".
## DressingView reads it when it builds.
static var dressing_casts := true

func setup(v: WorldView) -> void:
	view = v
	var d := LightSources.view()
	max_lights = int(d.get("max_lights", 24))
	set_quality(String(d.get("shadow_quality", "low")))
	sun = DirectionalLight3D.new()
	sun.name = "sun"
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.shadow_bias = float(_sun_d().get("shadow_bias", 0.05))
	sun.shadow_normal_bias = float(_sun_d().get("shadow_normal_bias", 1.0))
	sun.light_specular = 0.0
	add_child(sun)
	var lit_v := Vector4(float(d.get("fill", 0.5)), float(d.get("toon", 0.6)), float(d.get("wrap", 0.3)), float(d.get("shine", 0.35)))
	RenderingServer.global_shader_parameter_set("gs_lit", lit_v)
	_apply_quality()
	var dd: Dictionary = d.get("dust", {})
	if bool(dd.get("on", true)):
		_dust = MeshInstance3D.new()
		_dust.name = "dust"
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		_dust.mesh = q
		var m := ShaderMaterial.new()
		m.shader = DUST_SHADER
		m.set_shader_parameter("strength", float(dd.get("strength", 0.3)))
		m.set_shader_parameter("rays", float(dd.get("rays", 1.0)))
		m.set_shader_parameter("motes", float(dd.get("motes", 1.0)))
		m.set_shader_parameter("width", float(dd.get("width_tiles", 5.0)))
		_dust.material_override = m
		_dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_dust)

## off | low | high (data/lighting.json shadow_quality and shadows): sun and lamp shadows.
func set_quality(q: String) -> void:
	var table: Dictionary = LightSources.setting("shadows", {})
	quality = q if table.has(q) else "low"
	_q = table.get(quality, {"sun": true, "sun_size": 2048, "lamps": 4, "atlas": 2048, "soft": false, "cube": false})
	dressing_casts = bool(_q.get("dressing", true))
	if sun != null:
		_apply_quality()

func _apply_quality() -> void:
	sun.shadow_enabled = bool(_q.get("sun", true))
	RenderingServer.directional_shadow_atlas_set_size(int(_q.get("sun_size", 2048)), true)
	var soft := RenderingServer.SHADOW_QUALITY_SOFT_LOW if bool(_q.get("soft", false)) else RenderingServer.SHADOW_QUALITY_HARD
	RenderingServer.directional_soft_shadow_filter_set_quality(soft)
	RenderingServer.positional_soft_shadow_filter_set_quality(soft)
	var vp := get_viewport()
	if vp != null:
		vp.positional_shadow_atlas_size = int(_q.get("atlas", 2048))
		vp.positional_shadow_atlas_16_bits = true
	for o in _pool:
		o.omni_shadow_mode = OmniLight3D.SHADOW_CUBE if bool(_q.get("cube", false)) else OmniLight3D.SHADOW_DUAL_PARABOLOID

static func _sun_d() -> Dictionary:
	return LightSources.setting("sun", {})

## Unit vector toward the sun by day, the moon by night, at an hour: each crosses from the east
## (+x) at its rise to the west at its set, highest halfway, always a little in front of the play
## plane (+z) so the faces the camera sees take it.
static func sun_dir(hour: float) -> Vector3:
	var s := _sun_d() if is_day(hour) else (_sun_d().merged(LightSources.setting("moon", {}), true))
	var a := arc(hour)
	var up := maxf(sin(a) * float(s.get("height", 1.6)), float(s.get("least_up", 0.12)))
	return Vector3(cos(a), up, float(s.get("front", 0.55))).normalized()

## How far the sun (by day) or the moon (by night) is along its arc: 0 at its rise, PI at its set.
static func arc(hour: float) -> float:
	var rise := (WorldClock.DAWN.x + WorldClock.DAWN.y) * 0.5
	var down := (WorldClock.DUSK.x + WorldClock.DUSK.y) * 0.5
	var t := fposmod(hour, 24.0)
	if t >= rise and t <= down:
		return PI * (t - rise) / (down - rise)
	return PI * fposmod(t - down, 24.0) / (24.0 - (down - rise))

## True while the sun is up (the directional light is the sun), false while it is the moon.
static func is_day(hour: float) -> bool:
	var t := fposmod(hour, 24.0)
	return t >= (WorldClock.DAWN.x + WorldClock.DAWN.y) * 0.5 and t <= (WorldClock.DUSK.x + WorldClock.DUSK.y) * 0.5

## The directional light's colour and energy at an hour: {color, energy, day}. Warm and low near
## the horizon, white at noon; by night the moon, blue and faint; nothing at the moment one hands
## over to the other, so the shadows never jump.
static func sun_light(hour: float) -> Dictionary:
	var s := _sun_d()
	var m: Dictionary = LightSources.setting("moon", {})
	var height := sin(arc(hour))
	var fade := smoothstep(0.0, 0.18, height)
	if is_day(hour):
		var warm := Color(String(s.get("low_color", "#ffa070"))).lerp(Color(String(s.get("color", "#fff6ea"))), smoothstep(0.1, 0.7, height))
		return {"color": warm, "energy": float(s.get("energy", 0.7)) * fade, "day": true}
	return {"color": Color(String(m.get("color", "#8aa4ff"))), "energy": float(m.get("energy", 0.18)) * fade, "day": false}

## The n candidates nearest focus (tiles), nearest first. A candidate is a Dictionary with pos.
static func pick(cands: Array, focus: Vector2, n: int) -> Array:
	var sorted := cands.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["pos"] as Vector2).distance_squared_to(focus) < (b["pos"] as Vector2).distance_squared_to(focus))
	return sorted.slice(0, maxi(n, 0))

func _process(delta: float) -> void:
	if view == null:
		return
	_time += delta
	_env()
	_sun()
	_lamps()
	if _dust != null:
		var half := view.view_half + Vector2(4, 4)
		var z := float(LightSources.setting("dust", {}).get("z_tiles", -0.3))
		_dust.position = Vector3(view.focus.x * T, view.focus.y * T, z * T)
		_dust.scale = Vector3(half.x * 2.0 * T, half.y * 2.0 * T, 1.0)

## Light comes only from the sun, the lamps and the field's fill: no ambient, no sky reflections,
## so nothing glows in a cave. Glow (bloom) from data. Once per environment.
func _env() -> void:
	var w := get_world_3d()
	var env := w.environment if w != null else null
	if env == null or env.get_instance_id() == _env_id:
		return
	_env_id = env.get_instance_id()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.ambient_light_energy = 0.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	var b: Dictionary = LightSources.setting("bloom", {})
	env.glow_enabled = bool(b.get("on", true))
	if env.glow_enabled:
		env.glow_intensity = float(b.get("intensity", 0.6))
		env.glow_strength = float(b.get("strength", 1.0))
		env.glow_bloom = float(b.get("bloom", 0.0))
		env.glow_hdr_threshold = float(b.get("threshold", 1.0))
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
		var levels: Array = b.get("levels", [2, 3, 4, 5])
		for i in 7:
			env.set_glow_level(i, 1.0 if (i + 1) in levels else 0.0)

func _sun() -> void:
	var dir := sun_dir(view.hour)
	var l := sun_light(view.hour)
	sun.basis = Basis.looking_at(-dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD)
	sun.light_color = (l["color"] as Color) * view.biome_light()
	sun.light_energy = float(l["energy"])
	sun.visible = sun.light_energy > 0.001 and sky_in_view()
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam != null:
		sun.directional_shadow_max_distance = absf(cam.global_position.z) + float(_sun_d().get("shadow_reach_m", 30.0))

## Does the sky reach anything in view? Some column's open sky starts at or under the top of the
## view (a few tiles' margin for covered light). Deep underground it does not, and the sun and its
## shadow map cost nothing there.
func sky_in_view() -> bool:
	if view.light == null:
		return true
	var half := view.view_half + Vector2(6, 6)
	var top := view.focus.y + half.y
	var x := floori(view.focus.x - half.x)
	while x <= ceili(view.focus.x + half.x):
		if view.light.sky_top(x) <= top:
			return true
		x += 2
	return false

## Every source near the view: the emissive tiles of the meshed chunks, the glowing props and the
## carried lights.
func candidates() -> Array:
	var out: Array = []
	var lamps: Dictionary = LightSources.setting("lamps", {})
	var flick: Dictionary = lamps.get("flicker", {})
	var half := view.view_half + Vector2(16, 16)
	var area := Rect2(view.focus - half, half * 2.0)
	for key: Vector2i in view.emitters:
		if not area.intersects(Rect2(Vector2(key * K.CHUNK), Vector2(K.CHUNK, K.CHUNK))):
			continue
		for e: Vector3i in view.emitters[key]:
			var p := Vector2(e.x + 0.5, e.y + 0.75)
			if not area.has_point(p):
				continue
			var name := TileDefs.names[e.z]
			var level := LightEngine.emit_level(TileDefs.emit[e.z])
			var r := LightSources.row("tile:" + name)
			var col: Color = r["color"] if not r.is_empty() else TileDefs.colors[e.z].lerp(Color(1.0, 0.7, 0.4), 0.35)
			out.append({"key": "t%d,%d" % [e.x, e.y], "pos": p, "color": col, "level": level,
				"radius": LightSources.reach(level), "flicker": float(flick.get(name, 0.0))})
	for p: Dictionary in view.below.lit_props() if view.below != null else []:
		out.append({"key": p["key"], "pos": p["pos"], "color": p["color"], "level": p["level"],
			"radius": p["radius"], "flicker": 0.0})
	for id: int in view.carried:
		var c: Dictionary = view.carried[id]
		out.append({"key": "c%d" % id, "pos": c["pos"], "color": c["color"], "level": c["level"],
			"radius": c["radius"], "flicker": float(flick.get("carried", 0.0))})
	return out

func _lamps() -> void:
	var lamps: Dictionary = LightSources.setting("lamps", {})
	lit = pick(candidates(), view.focus, max_lights)
	var want := {}
	for c: Dictionary in lit:
		want[c["key"]] = c
	# Keep a source on the lamp it had, so a lamp's shadow map is not thrown away every frame.
	for i in _keys.size():
		if _keys[i] != "" and not want.has(_keys[i]):
			_keys[i] = ""
	var placed := {}
	for i in _keys.size():
		if _keys[i] != "":
			placed[_keys[i]] = i
	var shadows := int(_q.get("lamps", 4))
	var energy := float(lamps.get("energy", 1.6))
	var z := float(lamps.get("z_tiles", 1.2)) * T
	for rank in lit.size():
		var c: Dictionary = lit[rank]
		var i: int = placed.get(c["key"], -1)
		if i < 0:
			i = _free_lamp()
			_keys[i] = c["key"]
		var o := _pool[i]
		var p: Vector2 = c["pos"]
		o.position = Vector3(p.x * T, p.y * T, z)
		o.light_color = c["color"]
		o.omni_range = float(c["radius"]) * T * float(lamps.get("range_k", 1.0)) + 0.5
		o.omni_attenuation = float(lamps.get("attenuation", 0.7))
		var f := float(c["flicker"])
		var ph := float(hash(c["key"]) % 1000) * 0.01
		var k := 1.0 + f * (sin(_time * 7.3 + ph) * 0.6 + sin(_time * 12.9 + ph * 2.3) * 0.4)
		o.light_energy = energy * k * clampf(float(c["level"]) / LightEngine.TORCH, 0.4, 1.5)
		o.shadow_enabled = rank < shadows
		o.visible = true
	for i in _keys.size():
		if _keys[i] == "":
			_pool[i].visible = false

func _free_lamp() -> int:
	for i in _keys.size():
		if _keys[i] == "":
			return i
	var o := OmniLight3D.new()
	o.name = "lamp_%d" % _pool.size()
	o.light_specular = 0.0
	o.shadow_bias = float(LightSources.setting("lamps", {}).get("shadow_bias", 0.08))
	o.shadow_normal_bias = float(LightSources.setting("lamps", {}).get("shadow_normal_bias", 1.0))
	o.omni_shadow_mode = OmniLight3D.SHADOW_CUBE if bool(_q.get("cube", false)) else OmniLight3D.SHADOW_DUAL_PARABOLOID
	add_child(o)
	_pool.append(o)
	_keys.append("")
	return _pool.size() - 1
