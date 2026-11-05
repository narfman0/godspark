## The 2.5D view of a TileWorld: chunk meshes streamed around a focus point (built on
## WorkerThreadPool), the per-tile light textures, a sky/rock backdrop, placeholder actors.
## A pure reader of core state.
##
##   var view := WorldView.new()
##   add_child(view)
##   view.setup(world, light)
##   view.set_focus(Vector2(128, 64))        # tile units, every frame from the camera
##   var body := view.add_actor(7, {"kind": "hero", "size": Vector2(1.5, 2.5), "color": Color.TAN})
##   view.move_actor(7, pos, facing)
##
## Light: two R8 textures (block and sky fields, raw levels, one texel per tile) cover a
## rectangle around the focus and reach every shader through the global uniforms in
## view/shaders/light.gdshaderinc. Light edits refill the textures and never remesh.
class_name WorldView
extends Node3D

const TERRAIN_SHADER := preload("res://view/shaders/terrain.gdshader")
const BACKDROP_SHADER := preload("res://view/shaders/backdrop.gdshader")
const ACTOR_SHADER := preload("res://view/shaders/actor.gdshader")
const T := K.TILE_M
## The backdrop plane sits this far (metres) behind the background walls.
const BACKDROP_Z := -1.2

## Mesh builds in flight at once.
@export var max_tasks := 3
## Half-size, in tiles, of the area to keep meshed and lit around the focus. CameraRig
## keeps this in step with what it can see.
var view_half := Vector2(40, 24)
var focus := Vector2.ZERO

var world: TileWorld
var light: LightEngine

var _terrain_mat: ShaderMaterial
var _backdrop_mat: ShaderMaterial
var _actor_mat: ShaderMaterial
var _backdrop: MeshInstance3D
var _chunks := {}      ## Vector2i -> MeshInstance3D (null while empty)
var _wanted := {}      ## Vector2i -> true
var _dirty := {}       ## Vector2i -> true, needs a (re)build
var _tasks := {}       ## Vector2i -> {"task": int, "out": Dictionary}
var _actors := {}      ## id -> Node3D
var _light_rect := Rect2i()
var _light_dirty := true
var _img_block: Image
var _img_sky: Image
var _tex_block: ImageTexture
var _tex_sky: ImageTexture
## Timings, microseconds: chunk builds on workers, main-thread snapshot and mesh upload,
## light texture refills (including any lazy light computation).
var stats := {"build": PackedInt32Array(), "snapshot": PackedInt32Array(),
	"upload": PackedInt32Array(), "light": PackedInt32Array()}

func setup(w: TileWorld, l: LightEngine) -> void:
	world = w
	light = l
	_terrain_mat = ShaderMaterial.new()
	_terrain_mat.shader = TERRAIN_SHADER
	_backdrop_mat = ShaderMaterial.new()
	_backdrop_mat.shader = BACKDROP_SHADER
	_actor_mat = ShaderMaterial.new()
	_actor_mat.shader = ACTOR_SHADER
	world.tile_changed.connect(_on_tile_changed)
	world.chunk_changed.connect(_on_chunk_changed)
	light.light_changed.connect(_on_light_changed)
	RenderingServer.global_shader_parameter_set("gs_tile_m", T)
	_backdrop = MeshInstance3D.new()
	var quad := QuadMesh.new()
	var margin := 200.0
	quad.size = Vector2(world.width + margin * 2, world.height + margin * 2) * T
	_backdrop.mesh = quad
	_backdrop.position = Vector3(world.width * 0.5 * T, world.height * 0.5 * T, BACKDROP_Z)
	_backdrop.material_override = _backdrop_mat
	_backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_backdrop)
	_apply_sun()

## Stream chunk meshes and light around pos (tile units).
func set_focus(pos: Vector2) -> void:
	focus = pos
	var lo := Vector2i(((pos - view_half) / K.CHUNK).floor()) - Vector2i.ONE
	var hi := Vector2i(((pos + view_half) / K.CHUNK).floor()) + Vector2i.ONE
	lo = lo.clamp(Vector2i.ZERO, Vector2i(world.chunks_x - 1, world.chunks_y - 1))
	hi = hi.clamp(Vector2i.ZERO, Vector2i(world.chunks_x - 1, world.chunks_y - 1))
	_wanted.clear()
	for cy in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			var key := Vector2i(cx, cy)
			_wanted[key] = true
			if not _chunks.has(key) and not _tasks.has(key):
				_dirty[key] = true
	# Unload with one chunk of slack, so moving back and forth does not thrash.
	for key: Vector2i in _chunks.keys():
		if key.x < lo.x - 1 or key.x > hi.x + 1 or key.y < lo.y - 1 or key.y > hi.y + 1:
			var mi: MeshInstance3D = _chunks[key]
			if mi != null:
				mi.queue_free()
			_chunks.erase(key)
	# Light texture: recentre when the visible area leaves the inner part of the rectangle.
	var need := Rect2i(Vector2i((pos - view_half).floor()) - Vector2i(4, 4),
		Vector2i((view_half * 2).ceil()) + Vector2i(8, 8))
	if not _light_rect.encloses(need):
		var half := Vector2i((view_half + Vector2(24, 24)).ceil())
		half = (half + Vector2i(15, 15)) / 16 * 16
		var origin := (Vector2i(pos.floor()) - half) / 8 * 8
		_light_rect = Rect2i(origin, half * 2)
		_light_dirty = true

func add_actor(id: int, look: Dictionary) -> Node3D:
	remove_actor(id)
	var size: Vector2 = look.get("size", Vector2(1.5, 2.5))
	var color: Color = look.get("color", Color(0.8, 0.7, 0.55))
	var root := Node3D.new()
	root.name = "actor_%d" % id
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = minf(size.x * 0.5, size.y * 0.5) * T
	cap.height = size.y * T
	cap.radial_segments = 12
	cap.rings = 4
	body.mesh = cap
	body.position.y = size.y * 0.5 * T
	body.material_override = _actor_mat
	body.set_instance_shader_parameter("tint", color)
	body.name = "body"
	root.add_child(body)
	var nose := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(size.x * 0.35, size.y * 0.12, size.x * 0.35) * T
	nose.mesh = box
	nose.position = Vector3(size.x * 0.5 * T, size.y * 0.78 * T, 0)
	nose.material_override = _actor_mat
	nose.set_instance_shader_parameter("tint", color.darkened(0.45))
	root.add_child(nose)
	root.set_meta("size", size)
	add_child(root)
	_actors[id] = root
	return root

## facing: +1 right, -1 left. state "dead" lays the placeholder down.
func move_actor(id: int, pos: Vector2, facing: int, state := "idle") -> void:
	var root: Node3D = _actors.get(id)
	if root == null:
		return
	root.position = Vector3(pos.x * T, pos.y * T, 0)
	root.rotation = Vector3(0, 0 if facing >= 0 else PI, PI * 0.5 if state == "dead" else 0.0)

func remove_actor(id: int) -> void:
	var root: Node3D = _actors.get(id)
	if root != null:
		root.queue_free()
		_actors.erase(id)

## The tile under a screen position, picked on the blocks' front plane.
func tile_at_screen(screen_pos: Vector2) -> Vector2i:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector2i(-1, -1)
	var o := cam.project_ray_origin(screen_pos)
	var d := cam.project_ray_normal(screen_pos)
	if absf(d.z) < 1e-6:
		return Vector2i(-1, -1)
	var t := (ChunkMesher.FRONT * T - o.z) / d.z
	var hit := o + d * t
	return Vector2i(floori(hit.x / T), floori(hit.y / T))

## Sky colour for a sun value, for the environment background.
static func sky_color(sun: float) -> Color:
	var night := Color(0.012, 0.016, 0.04)
	var dusk := Color(0.55, 0.32, 0.25)
	var day := Color(0.36, 0.58, 0.9)
	if sun < 0.4:
		return night.lerp(dusk, sun / 0.4)
	return dusk.lerp(day, (sun - 0.4) / 0.6)

## Nothing queued, nothing building, light textures current.
func is_idle() -> bool:
	if not _tasks.is_empty() or _light_dirty:
		return false
	for key: Vector2i in _dirty:
		if _wanted.has(key):
			return false
	return true

func chunk_count() -> int:
	return _chunks.size()

func _process(_delta: float) -> void:
	if world == null:
		return
	_collect()
	_launch()
	_apply_sun()
	if _light_dirty:
		_refill_light()

func _exit_tree() -> void:
	for key: Vector2i in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[key]["task"])
	_tasks.clear()

func _collect() -> void:
	for key: Vector2i in _tasks.keys():
		var job: Dictionary = _tasks[key]
		if not WorkerThreadPool.is_task_completed(job["task"]):
			continue
		WorkerThreadPool.wait_for_task_completion(job["task"])
		_tasks.erase(key)
		var out: Dictionary = job["out"]
		stats["build"].append(out.get("usec", 0))
		if not _wanted.has(key) or _dirty.has(key):
			continue  # gone out of view, or edited again since: the next build wins
		var t0 := Time.get_ticks_usec()
		var arrays: Array = out.get("arrays", [])
		var mi: MeshInstance3D = _chunks.get(key)
		if arrays.is_empty():
			if mi != null:
				mi.queue_free()
			_chunks[key] = null
			continue
		if mi == null:
			mi = MeshInstance3D.new()
			mi.material_override = _terrain_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = Vector3(key.x * K.CHUNK * T, key.y * K.CHUNK * T, 0)
			mi.name = "chunk_%d_%d" % [key.x, key.y]
			add_child(mi)
			_chunks[key] = mi
		mi.mesh = ChunkMesher.to_mesh(arrays)
		stats["upload"].append(Time.get_ticks_usec() - t0)

func _launch() -> void:
	if _dirty.is_empty() or _tasks.size() >= max_tasks:
		return
	var keys: Array = _dirty.keys()
	var c := focus / K.CHUNK
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (Vector2(a) + Vector2(0.5, 0.5)).distance_squared_to(c) < (Vector2(b) + Vector2(0.5, 0.5)).distance_squared_to(c))
	for key: Vector2i in keys:
		if _tasks.size() >= max_tasks:
			break
		if not _wanted.has(key):
			_dirty.erase(key)
			continue
		if _tasks.has(key):
			continue  # rebuild after the one in flight lands
		_dirty.erase(key)
		var t0 := Time.get_ticks_usec()
		var snap := ChunkMesher.snapshot(world, key.x, key.y)
		stats["snapshot"].append(Time.get_ticks_usec() - t0)
		var out := {}
		var task := WorkerThreadPool.add_task(func() -> void:
			var s := Time.get_ticks_usec()
			out["arrays"] = ChunkMesher.build_arrays(snap)
			out["usec"] = Time.get_ticks_usec() - s, false, "chunk mesh")
		_tasks[key] = {"task": task, "out": out}

func _mark(cx: int, cy: int) -> void:
	if cx < 0 or cy < 0 or cx >= world.chunks_x or cy >= world.chunks_y:
		return
	var key := Vector2i(cx, cy)
	if _wanted.has(key) or _chunks.has(key):
		_dirty[key] = true

func _on_tile_changed(x: int, y: int, layer: int, _old: int, _now: int) -> void:
	if layer == TileWorld.Layer.LIQUID:
		return
	var cx := x >> 5
	var cy := y >> 5
	_mark(cx, cy)
	if layer != TileWorld.Layer.FG:
		return
	var lx := x & 31
	var ly := y & 31
	var dx := -1 if lx == 0 else (1 if lx == K.CHUNK - 1 else 0)
	var dy := -1 if ly == 0 else (1 if ly == K.CHUNK - 1 else 0)
	if dx != 0:
		_mark(cx + dx, cy)
	if dy != 0:
		_mark(cx, cy + dy)
	if dx != 0 and dy != 0:
		_mark(cx + dx, cy + dy)

func _on_chunk_changed(cx: int, cy: int) -> void:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			_mark(cx + dx, cy + dy)

func _on_light_changed(rect: Rect2i) -> void:
	if rect.intersects(_light_rect):
		_light_dirty = true

func _refill_light() -> void:
	var t0 := Time.get_ticks_usec()
	light.ensure_region(_light_rect)
	_light_dirty = false
	var size := _light_rect.size
	var blk := light.region_bytes(_light_rect, false)
	var sky := light.region_bytes(_light_rect, true)
	if _img_block == null or _img_block.get_size() != size:
		_img_block = Image.create_from_data(size.x, size.y, false, Image.FORMAT_R8, blk)
		_img_sky = Image.create_from_data(size.x, size.y, false, Image.FORMAT_R8, sky)
		_tex_block = ImageTexture.create_from_image(_img_block)
		_tex_sky = ImageTexture.create_from_image(_img_sky)
		RenderingServer.global_shader_parameter_set("gs_light_block", _tex_block)
		RenderingServer.global_shader_parameter_set("gs_light_sky", _tex_sky)
	else:
		_img_block.set_data(size.x, size.y, false, Image.FORMAT_R8, blk)
		_img_sky.set_data(size.x, size.y, false, Image.FORMAT_R8, sky)
		_tex_block.update(_img_block)
		_tex_sky.update(_img_sky)
	RenderingServer.global_shader_parameter_set("gs_light_rect",
		Vector4(_light_rect.position.x, _light_rect.position.y, size.x, size.y))
	stats["light"].append(Time.get_ticks_usec() - t0)

func _apply_sun() -> void:
	var s := light.sun
	RenderingServer.global_shader_parameter_set("gs_sun", s)
	var warm := Color(1.0, 0.62, 0.42).lerp(Color(1.0, 0.97, 0.92), clampf((s - 0.2) / 0.6, 0.0, 1.0))
	RenderingServer.global_shader_parameter_set("gs_sky_tint", warm)
	var top := sky_color(s)
	_backdrop_mat.set_shader_parameter("sky_top", top)
	_backdrop_mat.set_shader_parameter("sky_low", top.lerp(Color(0.85, 0.85, 0.9) * maxf(s, 0.05), 0.45))
