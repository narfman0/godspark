## The 2.5D view of a TileWorld: chunk meshes streamed around a focus point (built on
## WorkerThreadPool), the per-tile light textures, a sky/rock backdrop, actors (ActorBody).
## A pure reader of core state.
##
##   var view := WorldView.new()
##   add_child(view)
##   view.setup(world, light)
##   view.set_focus(Vector2(128, 64))        # tile units, every frame from the camera
##   var body := view.add_actor(7, {"player": "fighter", "name": "Ash"})   # see view/actors/looks.gd
##   view.move_actor(7, pos, facing, ActorBody.state_for(core_body), core_body.vel)
##
## Light: two R8 textures (block and sky fields, raw levels, one texel per tile) cover a
## rectangle around the focus and reach every shader through the global uniforms in
## view/shaders/light.gdshaderinc. Light edits refill the textures and never remesh.
##
## Natural ground is meshed soft (ChunkMesher) and coloured from a material map, a wrapping texture
## of one texel per tile that each chunk's build writes into. Behind and before the tiles stand
## the Backdrops; sky and light take the biome under the focus from them.
class_name WorldView
extends Node3D

const TERRAIN_SHADER := preload("res://view/shaders/terrain.gdshader")
const BACKDROP_SHADER := preload("res://view/shaders/backdrop.gdshader")
const ACTOR_SHADER := preload("res://view/shaders/actor.gdshader")
const T := K.TILE_M
## The backdrop plane sits this far (metres) behind the background walls.
const BACKDROP_Z := -2.5
## The material map, tiles. A power of two past the most the widest zoom keeps meshed.
const MAT_W := 512
const MAT_H := 256
## The least sun factor the picture uses for the sky field (moonlight); see _apply_sun.
const NIGHT_VISUAL := 0.25
const MOON_TINT := Color(0.52, 0.64, 1.0)
const NIGHT_LOW := Color(0.04, 0.06, 0.13)

## Mesh builds in flight at once.
@export var max_tasks := 3
## Main-thread microseconds per frame for light work when the LightEngine is deferred
## (chunk arrivals and cold chunks; at least one chunk's worth is always done).
@export var light_budget_us := 3000
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
var backdrops: Backdrops
var soft := true       ## false: the old block look, for comparison pictures
var _mat_img: Image
var _mat_tex: ImageTexture
var _mat_dirty := false
var _chunks := {}      ## Vector2i -> MeshInstance3D (null while empty)
var _wanted := {}      ## Vector2i -> true
var _dirty := {}       ## Vector2i -> true, needs a (re)build
var _tasks := {}       ## Vector2i -> {"task": int, "out": Dictionary}
var _actors := {}      ## id -> Node3D
## Carried lights the presenter reports: id -> {pos: Vector2 tiles, level, color, radius}.
var carried := {}
## Light-giving tiles of each meshed chunk (ChunkMesher.emitters): Vector2i -> [Vector3i(x, y, id)].
var emitters := {}
## The hour of the day (the sun's angle and colour follow it); the presenter sets it from the clock.
var hour := 12.0
## The sun and the lamp pool (view/world_lights.gd).
var lights: WorldLights
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
	_backdrop.material_override = _backdrop_mat
	_backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_backdrop.position.z = BACKDROP_Z
	_shape_backdrop()
	_backdrop.sorting_offset = -1000.0
	_backdrop_mat.render_priority = -10
	add_child(_backdrop)
	_mat_img = Image.create(MAT_W, MAT_H, false, Image.FORMAT_RGBA8)
	_mat_tex = ImageTexture.create_from_image(_mat_img)
	RenderingServer.global_shader_parameter_set("gs_mat", _mat_tex)
	RenderingServer.global_shader_parameter_set("gs_noise", Backdrops.noise_texture())
	backdrops = Backdrops.new()
	add_child(backdrops)
	backdrops.setup(world)
	keep_clear(0, Vector2.ZERO, 0.0)
	keep_clear(1, Vector2.ZERO, 0.0)
	lights = WorldLights.new()
	add_child(lights)
	lights.setup(self)
	_apply_sun()

## The dark behind the caves only has work to do under the ground, so with the surface line
## known it stops a little over it: the sky above costs no pixels. Without it, the whole world.
func _shape_backdrop() -> void:
	var margin := 200
	var surf: Variant = world.meta.get("surface", null)
	var v := PackedVector3Array()
	var idx := PackedInt32Array()
	var known: bool = (surf is Array or surf is PackedInt32Array) and surf.size() == world.width
	var step := 16 if known else world.width
	for i in range(0, world.width / step + 1):
		var x := mini(i * step, world.width)
		var top := world.height + margin
		if known:
			top = 0
			for c in range(maxi(x - step, 0), mini(x + step, world.width)):
				top = maxi(top, int(surf[c]))
			top += 6
		var x0 := (x if i > 0 else -margin) if x < world.width else world.width + margin
		v.append(Vector3(x0 * T, top * T, 0.0))
		v.append(Vector3(x0 * T, -margin * T, 0.0))
		if i > 0:
			var k := i * 2
			idx.append_array([k - 2, k - 1, k, k, k - 1, k + 1])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_backdrop.mesh = mesh

## The world's meta changed (a client's comes after its world): rebuild what reads it.
func meta_changed() -> void:
	if backdrops != null:
		backdrops.rebuild()
		_shape_backdrop()

## Keep the foreground off a spot on the play plane (tiles): 0 the player, 1 the target. radius 0
## lets it go; negative takes the data's.
func keep_clear(slot: int, pos: Vector2, radius := -1.0) -> void:
	if radius < 0.0:
		radius = float(Backdrops.data().get("fore", {}).get("keep_tiles", 7.0))
	RenderingServer.global_shader_parameter_set("gs_keep_a" if slot == 0 else "gs_keep_b", Vector4(pos.x, pos.y, radius, 0.0))

## A carried light at pos (tiles, the hand): row from LightSources ({level, color, radius});
## {} puts it out. The LightEngine field is the presenter's to set; this is the picture's lamp.
func carry(id: int, pos: Vector2, row: Dictionary) -> void:
	if row.is_empty():
		carried.erase(id)
	else:
		carried[id] = {"pos": pos, "level": int(row["level"]), "color": row["color"], "radius": float(row["radius"])}

## The own Darkvision: the dark within `tiles` of pos is drawn in grey (0: none).
func darkvision(pos: Vector2, tiles: float) -> void:
	var grey := float(LightSources.setting("darkvision_grey", 0.3))
	RenderingServer.global_shader_parameter_set("gs_darkvision", Vector4(pos.x, pos.y, tiles, grey))

## Stream chunk meshes and light around pos (tile units).
func set_focus(pos: Vector2) -> void:
	focus = pos
	backdrops.update(pos)
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
			emitters.erase(key)
	# Light texture: recentre when the visible area leaves the inner part of the rectangle.
	var need := Rect2i(Vector2i((pos - view_half).floor()) - Vector2i(4, 4),
		Vector2i((view_half * 2).ceil()) + Vector2i(8, 8))
	if not _light_rect.encloses(need):
		var half := Vector2i((view_half + Vector2(24, 24)).ceil())
		half = (half + Vector2i(15, 15)) / 16 * 16
		var origin := (Vector2i(pos.floor()) - half) / 8 * 8
		_light_rect = Rect2i(origin, half * 2)
		_light_dirty = true

## An actor's body from its look (view/actors/looks.gd resolves it: a monster-forge GLB, a
## Synty model or a tinted primitive with a nameplate). look: {slug, people, player, key,
## name, size: Vector2, size_name, type, color, tint, scale, height_m, nameplate} or the
## original {kind, size, color}. Returns the ActorBody (a Node3D); its feet are its origin.
func add_actor(id: int, look: Dictionary) -> Node3D:
	remove_actor(id)
	var root := ActorBody.build(look, _actor_mat)
	root.name = "actor_%d" % id
	if bool(look.get("wagon", false)):
		_add_cart(root)
	root.set_meta("size", root.size)
	add_child(root)
	_actors[id] = root
	return root

## A caravan's wagon (Life: a draft horse with look.wagon): a plain cart box on two wheels
## hitched behind the horse. Primitive until a cart model is fetched.
func _add_cart(root: Node3D) -> void:
	var cart := Node3D.new()
	cart.name = "cart"
	root.add_child(cart)
	root.set_meta("cart", cart)
	var wood_src := StandardMaterial3D.new()
	wood_src.albedo_color = Color(0.45, 0.3, 0.18)
	var wood := LitMaterials.lit_for(wood_src)
	var bed := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.6 * T, 1.1 * T, 1.4 * T)
	bed.mesh = box
	bed.material_override = wood
	bed.position = Vector3(-2.4 * T, 1.05 * T, 0.0)
	cart.add_child(bed)
	var cover := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.75 * T
	cyl.bottom_radius = 0.75 * T
	cyl.height = 2.4 * T
	cover.mesh = cyl
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.85, 0.8, 0.68)
	cover.material_override = LitMaterials.lit_for(cloth)
	cover.rotation = Vector3(0.0, 0.0, PI / 2.0)
	cover.position = Vector3(-2.4 * T, 1.7 * T, 0.0)
	cart.add_child(cover)
	for wx: float in [-3.3, -1.5]:
		var wheel := MeshInstance3D.new()
		var wm := CylinderMesh.new()
		wm.top_radius = 0.5 * T
		wm.bottom_radius = 0.5 * T
		wm.height = 0.2 * T
		wheel.mesh = wm
		wheel.material_override = wood
		wheel.rotation = Vector3(PI / 2.0, 0.0, 0.0)
		wheel.position = Vector3(wx * T, 0.5 * T, 0.75 * T)
		cart.add_child(wheel)

## Rest a cart on the road behind its horse: its pivot is the hitch; the tail goes up or down to
## the floor under it (the horse's own feet are on the floor already).
func _settle_cart(root: ActorBody, pos: Vector2, facing: int) -> void:
	var cart: Node3D = root.get_meta("cart")
	if world == null or cart == null:
		return
	# the actor's model turns by itself; the cart is a sibling of it, so it swings round here
	var side := facing if facing != 0 else int(root.get_meta("cart_side", 1))
	root.set_meta("cart_side", side)
	cart.scale.x = float(side)
	var tail := pos.x - 2.4 * float(side)
	var x := floori(tail)
	var y := floori(pos.y) + 3
	var floor_y := INF
	for k in 8:
		var id := world.get_fg(x, y - 1 - k)
		if TileDefs.solid[id] != 0 or TileDefs.platform[id] != 0:
			floor_y = float(y - k)
			break
	var dy := clampf(floor_y - pos.y, -2.0, 2.0) if floor_y != INF else 0.0
	var want := -atan2(dy, 2.4) * float(side)
	cart.rotation.z = lerp_angle(cart.rotation.z, want, 0.2)

## facing: +1 right, -1 left (0 keeps the last). state: idle | walk | run | jump | fall |
## climb | swim | fly | attack | hit | death ("dead" = death): see ActorBody. vel (tiles/s)
## picks walk / run / sprint and scales the clip; left out, it is estimated from positions.
func move_actor(id: int, pos: Vector2, facing: int, state := "idle", vel := Vector2.INF) -> void:
	var root: ActorBody = _actors.get(id)
	if root == null:
		return
	root.update(pos, facing, state, vel)
	if root.has_meta("cart"):
		_settle_cart(root, pos, facing)

## The ActorBody for an id, or null.
func get_actor(id: int) -> ActorBody:
	return _actors.get(id)

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

## The biome's light colour under the focus (data/backdrops.json light), for the sun's colour.
func biome_light() -> Color:
	return backdrops.tint_at(focus.x)["light"] if backdrops != null else Color.WHITE

## Sky colour for a sun value, for the environment background.
static func sky_color(sun: float) -> Color:
	var night := Color(0.012, 0.016, 0.04)
	var dusk := Color(0.32, 0.3, 0.52)
	var day := Color(0.36, 0.58, 0.9)
	if sun < 0.4:
		return night.lerp(dusk, sun / 0.4)
	return dusk.lerp(day, (sun - 0.4) / 0.6)

## Colour near the horizon (bottom of the screen) for a sun value.
static func horizon_color(sun: float) -> Color:
	var night := Color(0.03, 0.03, 0.07)
	var dusk := Color(0.95, 0.52, 0.3)
	var day := Color(0.72, 0.84, 0.95)
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
	if _mat_dirty:
		_mat_dirty = false
		_mat_tex.update(_mat_img)
	_launch()
	_apply_sun()
	if light.deferred and light.backlog() > 0:
		_light_dirty = true
	if _light_dirty:
		_refill_light()

func _exit_tree() -> void:
	for key: Vector2i in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[key]["task"])
	_tasks.clear()
	GltfCache.clear()   # loaded-model templates live outside the tree

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
		_write_mat(key, out.get("mat", PackedByteArray()))
		var em: Array = out.get("emit", [])
		if em.is_empty():
			emitters.erase(key)
		else:
			emitters[key] = em
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
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
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
		if not world.has_chunk(key.x, key.y):
			# Unloaded on a sparse client world: nothing to draw until it arrives.
			var old: MeshInstance3D = _chunks.get(key)
			if old != null:
				old.queue_free()
			_chunks[key] = null
			emitters.erase(key)
			continue
		var t0 := Time.get_ticks_usec()
		var snap := ChunkMesher.snapshot(world, key.x, key.y, soft)
		stats["snapshot"].append(Time.get_ticks_usec() - t0)
		var out := {}
		var task := WorkerThreadPool.add_task(func() -> void:
			var s := Time.get_ticks_usec()
			out["arrays"] = ChunkMesher.build_arrays(snap)
			out["emit"] = ChunkMesher.emitters(snap)
			if snap["soft"]:
				out["mat"] = ChunkMesher.material_bytes(snap)
			out["usec"] = Time.get_ticks_usec() - s, false, "chunk mesh")
		_tasks[key] = {"task": task, "out": out}

## A chunk's texels into the wrapping map. They keep their tiles' coordinates modulo its size.
func _write_mat(key: Vector2i, bytes: PackedByteArray) -> void:
	if bytes.is_empty():
		bytes.resize(K.CHUNK * K.CHUNK * 4)
	var img := Image.create_from_data(K.CHUNK, K.CHUNK, false, Image.FORMAT_RGBA8, bytes)
	_mat_img.blit_rect(img, Rect2i(0, 0, K.CHUNK, K.CHUNK), Vector2i((key.x * K.CHUNK) % MAT_W, (key.y * K.CHUNK) % MAT_H))
	_mat_dirty = true

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
	if light.deferred:
		# What is not lit yet reads dark for a frame or two; the nearest chunks come first.
		_light_dirty = not light.process(light_budget_us, _light_rect)
	else:
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
	var b: Dictionary = backdrops.tint_at(focus.x)
	# Moonlight: the rules sun at night (WorldClock.MOON) leaves open ground in Darkness, as
	# the SRD has it, but a black screen is unplayable, so the picture draws the sky field at
	# no less than NIGHT_VISUAL (about 15% brightness through gs_curve), tinted blue. Caves
	# have no sky field and stay black.
	RenderingServer.global_shader_parameter_set("gs_sun", maxf(s, NIGHT_VISUAL))
	var warm := Color(1.0, 0.62, 0.42).lerp(Color(1.0, 0.97, 0.92), clampf((s - 0.2) / 0.6, 0.0, 1.0))
	warm = warm.lerp(MOON_TINT, 1.0 - smoothstep(0.05, 0.3, s))
	RenderingServer.global_shader_parameter_set("gs_sky_tint", warm * (b["light"] as Color))
	# Dusk's orange is for dusk: by moonlight the low sky and the haze go a deep blue.
	var dark := 1.0 - smoothstep(0.08, 0.32, s)
	var horizon := horizon_color(s).lerp(NIGHT_LOW, dark)
	var top := sky_color(s) * (b["sky_top"] as Color)
	var low := horizon * (b["sky_low"] as Color)
	var day := smoothstep(0.1, 0.6, s)
	RenderingServer.global_shader_parameter_set("gs_haze", horizon * (b["haze"] as Color))
	backdrops.sky(top, low, low.lerp(Color(1.0, 0.98, 0.95), 0.6 * day).lerp(NIGHT_LOW * 1.7, dark), dark)
