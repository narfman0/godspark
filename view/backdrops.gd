## What stands behind the play plane and in front of it, from data/backdrops.json: view only.
##
## Behind: the sky, then ribbons of the world's distance (ranges, far, mid) and a near row of
## instanced silhouettes on a last ribbon, all real geometry at real depth behind the tiles, so
## the camera's own perspective makes the parallax. Their colours and shapes change along the
## width with the biome under them and blend across seams. A layer's height is
##     gs_anchor * (1 - k) + ground(x) * k + shape(x)
## with gs_anchor the smoothed ground under the camera and ground(x) its own smoothed ground: a far
## layer keeps to the horizon wherever you stand, and the world's real range stands up in it as
## you near it.
##
## In front: sparse props on planes before the tiles. They fade out in a dither around the player
## and the target (WorldView.keep_clear) and when the camera goes underground.
##
## WorldView owns one. Worlds with no meta.surface read as flat at mid height, with no biome
## strip as one meadow. Without fetched art the near row is its ribbon alone and the foreground
## is empty.
##
##   var b := Backdrops.new(); add_child(b); b.setup(world)
##   b.update(focus_in_tiles)            # every frame: anchor, tints, streaming
##   b.tint_at(x)                        # {sky_top, sky_low, haze, light}: multipliers
class_name Backdrops
extends Node3D

const FILE := "res://data/backdrops.json"
const LAYER_SHADER := preload("res://view/shaders/layer.gdshader")
const FORE_SHADER := preload("res://view/shaders/fore.gdshader")
const SKY_SHADER := preload("res://view/shaders/sky.gdshader")
const T := K.TILE_M
## How far behind the play plane the sky rides, metres (inside CameraRig's far).
const SKY_Z := 2600.0
## Tiles past the world's ends the ribbons run, so no end shows.
const MARGIN := 1600
## Columns in one piece of a ribbon.
const RIBBON_COLS := 64
## Rows of ground over the camera before the foreground has fully gone.
const FORE_FADE_ROWS := 14.0

static var _data := {}
## Noise for the terrain and the sky, made once.
static var _noise_tex: ImageTexture

var world: TileWorld
var _ground := PackedFloat32Array()      ## per column, raw
var _strip: Array = []                   ## [{x0, x1, biome}]
var _sky: MeshInstance3D
var _sky_mat: ShaderMaterial
var _near_mat: ShaderMaterial
var _fore_mats: Array[ShaderMaterial] = []
var _parts := {}                         ## "model|use" -> {parts, top}
var _segs := {}                          ## "near:3" -> Node3D
var _smooth_anchor := PackedFloat32Array()
var _near_g := PackedFloat32Array()
var _sites: Array[Vector2i] = []         ## [x0, x1] of settled grounds, no foreground there
var counts := {"ribbons": 0, "near": 0, "fore": 0}
## The last anchor (tiles) and foreground fade, for tests.
var anchor := 0.0
var fore_fade := 1.0

static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		_data = d if d is Dictionary else {}
	return _data

## RGBA noise, tiling, 256 square: r, g broad (warps and clouds), b strata, a grain.
static func noise_texture() -> ImageTexture:
	if _noise_tex != null:
		return _noise_tex
	var src: Array[PackedByteArray] = []
	for i in 4:
		var n := FastNoiseLite.new()
		n.seed = 11 + i * 7
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 3 if i < 3 else 2
		n.frequency = [0.012, 0.014, 0.02, 0.09][i]
		var layer := n.get_seamless_image(256, 256, false, false, 0.15, true)
		layer.convert(Image.FORMAT_L8)
		src.append(layer.get_data())
	var bytes := PackedByteArray()
	bytes.resize(256 * 256 * 4)
	for p in 256 * 256:
		for ch in 4:
			bytes[p * 4 + ch] = src[ch][p]
	var img := Image.create_from_data(256, 256, false, Image.FORMAT_RGBA8, bytes)
	img.generate_mipmaps()
	_noise_tex = ImageTexture.create_from_image(img)
	return _noise_tex

func setup(w: TileWorld) -> void:
	world = w
	rebuild()

## After the world's meta changed (a client's arrives after its world).
func rebuild() -> void:
	for c in get_children():
		c.free()
	_segs.clear()
	_near_g = PackedFloat32Array()
	counts = {"ribbons": 0, "near": 0, "fore": 0}
	_read_world()
	_build_sky()
	var d := data()
	# a client's meta comes after its world: this runs again then
	if d.is_empty() or (world.sparse and not world.meta.has("surface")):
		return
	var layers: Array = d.get("layers", [])
	for l: Dictionary in layers:
		_add_ribbon(l)
	var near: Dictionary = d.get("near", {})
	_add_ribbon(near)
	_near_mat = _material(near, true)
	_smooth_anchor = _smoothed(int((layers[0] as Dictionary).get("smooth", 120)) / 3)

func _read_world() -> void:
	_ground.resize(world.width)
	var surf: Variant = world.meta.get("surface", null)
	if (surf is PackedInt32Array or surf is Array) and surf.size() == world.width:
		for x in world.width:
			_ground[x] = float(surf[x])
	else:
		_ground.fill(float(world.height) * 0.5)
	_strip.clear()
	for s: Variant in world.meta.get("biomes", []):
		if s is Dictionary:
			_strip.append({"x0": int(s["x0"]), "x1": int(s["x1"]), "biome": String(s["biome"])})
	_sites.clear()
	var margin := int(data().get("fore", {}).get("town_margin", 24))
	for s: Variant in world.meta.get("sites", []):
		if s is Dictionary and s.get("kind") == "settlement" and String(s.get("band", "surface")) in ["surface", "sky"]:
			var r := int(s.get("size", 60)) / 2 + margin
			_sites.append(Vector2i(int(s["x"]) - r, int(s["x"]) + r))

## Moving average of the ground, half-width r.
func _smoothed(r: int) -> PackedFloat32Array:
	var n := _ground.size()
	var sum := PackedFloat64Array()
	sum.resize(n + 1)
	for i in n:
		sum[i + 1] = sum[i] + _ground[i]
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var a := maxi(i - r, 0)
		var b := mini(i + r + 1, n)
		out[i] = float(sum[b] - sum[a]) / float(b - a)
	return out

## The biomes at x and how much of the second: [a, b, share of b]. Blended blend_tiles each way
## of a seam.
func biomes_at(x: float) -> Array:
	if _strip.is_empty():
		return ["meadow", "meadow", 0.0]
	var blend := float(data().get("blend_tiles", 110))
	for i in _strip.size():
		var s: Dictionary = _strip[i]
		if x > float(s["x1"]) + blend and i + 1 < _strip.size():
			continue
		var a := String(s["biome"])
		if i + 1 < _strip.size() and x > float(s["x1"]) - blend:
			return [a, String(_strip[i + 1]["biome"]), smoothstep(-blend, blend, x - float(s["x1"]))]
		return [a, a, 0.0]
	return ["meadow", "meadow", 0.0]

## Multipliers for the sky and light at x: {sky_top, sky_low, haze, light} as Colors.
func tint_at(x: float) -> Dictionary:
	var ab := biomes_at(x)
	var bs: Dictionary = data().get("biomes", {})
	var a: Dictionary = bs.get(ab[0], {})
	var b: Dictionary = bs.get(ab[1], {})
	var f: float = ab[2]
	var out := {}
	for key: String in ["sky_top", "sky_low", "haze", "light"]:
		var ca: Array = a.get(key, [1, 1, 1])
		var cb: Array = b.get(key, [1, 1, 1])
		out[key] = Color(lerpf(ca[0], cb[0], f), lerpf(ca[1], cb[1], f), lerpf(ca[2], cb[2], f))
	return out

# --- ribbons ----------------------------------------------------------------------------------

static func _noise(sd: int, scale: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = sd
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 3
	n.frequency = 1.0 / scale
	return n

func _shape(layer: String, biome: String) -> Dictionary:
	return data().get("biomes", {}).get(biome, {}).get("layers", {}).get(layer, {})

## One layer's height over its anchor at x, from a biome's shape.
static func _height(sh: Dictionary, x: float, roll: FastNoiseLite, rag: FastNoiseLite) -> float:
	var amp := float(sh.get("amp", 0.0))
	var across := x * 300.0 / float(sh.get("scale", 300.0))
	var h := (roll.get_noise_1d(across) * 0.5 + 0.5) * amp
	var ridge := float(sh.get("ridge", 0.0))
	if ridge > 0.0:
		h += (1.0 - absf(rag.get_noise_1d(across)) * 2.0) * ridge
	var mesa := float(sh.get("mesa", 0.0))
	if mesa > 0.0:
		var tops := floorf(h / maxf(amp, 1.0) * 3.0 + 0.5) / 3.0 * amp
		h = lerpf(h, tops, mesa)
	var teeth := float(sh.get("teeth", 0.0))
	if teeth > 0.0:
		var q := x / float(sh.get("every", 8.0)) + rag.get_noise_1d(x * 7.0) * 0.6
		h += absf(fposmod(q, 1.0) * 2.0 - 1.0) * teeth * (0.7 + 0.5 * (roll.get_noise_1d(q * 90.0) + 0.5))
	return h

func _add_ribbon(l: Dictionary) -> void:
	var layer := String(l.get("layer", l.get("name", "")))
	var step := int(l.get("step", 8))
	var ground := _smoothed(int(l.get("smooth", 60)))
	var roll := _noise(hash([world.world_seed, layer, 1]), 300.0)
	var rag := _noise(hash([world.world_seed, layer, 2]), 300.0)
	var base := float(l.get("base", 0.0))
	var drop := float(l.get("drop", 400.0))
	var fade := float(l.get("fade", 40.0))
	var z := -float(l.get("depth", 100.0)) * T
	var bs: Dictionary = data().get("biomes", {})
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	var x := -MARGIN
	var from := x
	var n := 0
	var mat := _material(l, false)
	while x <= world.width + MARGIN:
		var cx := clampi(x, 0, world.width - 1)
		var ab := biomes_at(float(cx))
		var sa := _shape(layer, ab[0])
		var sb := _shape(layer, ab[1])
		var f: float = ab[2]
		var h := lerpf(_height(sa, float(x), roll, rag), _height(sb, float(x), roll, rag), f) + base
		var ca := Color.from_string(String(sa.get("color", "#6f8090")), Color.GRAY)
		var cb := Color.from_string(String(sb.get("color", "#6f8090")), Color.GRAY)
		var c := ca.lerp(cb, f).srgb_to_linear()
		var ta := Color.from_string(String(sa.get("snow", sa.get("color", "#6f8090"))), Color.GRAY)
		var tb := Color.from_string(String(sb.get("snow", sb.get("color", "#6f8090"))), Color.GRAY)
		var top_c := ta.lerp(tb, f).srgb_to_linear()
		var mist := lerpf(float(bs.get(ab[0], {}).get("mist", 0.5)), float(bs.get(ab[1], {}).get("mist", 0.5)), f)
		var g := ground[cx]
		verts.append(Vector3(x * T, h * T, z))
		cols.append(top_c)
		uv2.append(Vector2(g, 0.0))
		verts.append(Vector3(x * T, (h - fade * 0.3) * T, z))
		cols.append(c.lerp(top_c, 0.3))
		uv2.append(Vector2(g, mist * 0.25))
		verts.append(Vector3(x * T, (h - fade) * T, z))
		cols.append(c)
		uv2.append(Vector2(g, mist))
		verts.append(Vector3(x * T, -drop * T, z))
		cols.append(c)
		uv2.append(Vector2(g, 1.0))
		if n > 0:
			var v := n * 4
			for b in 3:
				idx.append_array([v - 4 + b, v + b, v - 3 + b, v - 3 + b, v + b, v + 1 + b])
		n += 1
		x += step
		# A stretch at a time, so what is out of view is culled; the next starts on this column.
		if n > RIBBON_COLS or x > world.width + MARGIN:
			_ribbon_piece(layer, mat, verts, cols, uv2, idx, from, x - step, z)
			var last := verts.size() - 4
			verts = verts.slice(last)
			cols = cols.slice(last)
			uv2 = uv2.slice(last)
			idx = PackedInt32Array()
			from = x - step
			n = 1
	counts["ribbons"] += 1

func _ribbon_piece(layer: String, mat: Material, verts: PackedVector3Array, cols: PackedColorArray, uv2: PackedVector2Array,
		idx: PackedInt32Array, x0: int, x1: int, z: float) -> void:
	if idx.is_empty():
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "ribbon_%s_%d" % [layer, x0]
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the shader moves it by the anchor: cull on a box as tall as the world and more
	mi.custom_aabb = AABB(Vector3(x0 * T, -1000.0, z - 40.0), Vector3((x1 - x0) * T, world.height * T + 2000.0, 80.0))
	add_child(mi)

func _material(l: Dictionary, instanced: bool, tex: Texture2D = null) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = LAYER_SHADER
	m.set_shader_parameter("k", float(l.get("k", 0.5)))
	m.set_shader_parameter("layer_haze", float(l.get("haze", 0.2)))
	m.set_shader_parameter("instanced", instanced)
	m.set_shader_parameter("has_mask", tex != null)
	if tex != null:
		m.set_shader_parameter("mask", tex)
	return m

func _build_sky() -> void:
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = SKY_SHADER
	_sky = MeshInstance3D.new()
	_sky.name = "sky"
	var quad := QuadMesh.new()
	quad.size = Vector2(4000.0, 2400.0)
	_sky.mesh = quad
	_sky.material_override = _sky_mat
	_sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sky.position.z = -SKY_Z
	_sky.custom_aabb = AABB(Vector3(-2000, -1200, -1), Vector3(4000, 2400, 2))
	add_child(_sky)

func sky(top: Color, low: Color, cloud: Color, night: float) -> void:
	if _sky_mat == null:
		return
	_sky_mat.set_shader_parameter("sky_top", top)
	_sky_mat.set_shader_parameter("sky_low", low)
	_sky_mat.set_shader_parameter("cloud", cloud)
	_sky_mat.set_shader_parameter("night", night)

# --- per frame --------------------------------------------------------------------------------

## The anchor, the sky's place, the foreground's fade, and at most one new segment.
func update(focus: Vector2) -> void:
	if world == null or _ground.is_empty():
		return
	var cx := clampi(int(focus.x), 0, world.width - 1)
	anchor = _smooth_anchor[cx] if _smooth_anchor.size() == world.width else _ground[cx]
	RenderingServer.global_shader_parameter_set("gs_anchor", anchor)
	if _sky != null:
		_sky.position = Vector3(focus.x * T, focus.y * T, -SKY_Z)
		_sky_mat.set_shader_parameter("scroll", Vector2(focus.x * 0.0009, 0.0))
	var under := _ground[cx] - focus.y          # rows of ground over the camera
	var fade := clampf(1.0 - (under - 2.0) / FORE_FADE_ROWS, 0.0, 1.0)
	if fade != fore_fade:
		fore_fade = fade
		for m in _fore_mats:
			m.set_shader_parameter("fade", fade)
	var d := data()
	var near: Dictionary = d.get("near", {})
	var fore: Dictionary = d.get("fore", {})
	if near.is_empty():
		return
	var made := _stream("near", int(near.get("segment", 96)), focus.x, 2)
	if not made and fore_fade > 0.0:
		_stream("fore", int(fore.get("segment", 128)), focus.x, 1)

## Keep the segments around x, free the rest. Builds one missing segment a call.
func _stream(kind: String, size: int, x: float, reach: int) -> bool:
	var at := floori(x / float(size))
	for key: String in _segs.keys():
		if key.begins_with(kind) and absi(int(key.get_slice(":", 1)) - at) > reach + 1:
			(_segs[key] as Node).queue_free()
			_segs.erase(key)
	for off in reach + 1:
		for s: int in [at + off, at - off]:
			var key := "%s:%d" % [kind, s]
			if s < 0 or s * size >= world.width or _segs.has(key):
				continue
			var n := _near_segment(s, size) if kind == "near" else _fore_segment(s, size)
			add_child(n)
			_segs[key] = n
			return true
	return false

## A model's parts for a use: its surfaces under a material of ours, its masks kept.
func _model(model: String, use: String) -> Dictionary:
	var key := model + "|" + use
	if _parts.has(key):
		return _parts[key]
	var out := {}
	var raw := DressingView.parts_of(data().get("models", {}).get(model, {}))
	if not raw.is_empty():
		var parts: Array = []
		for p: Dictionary in raw["parts"]:
			var mesh: Mesh = (p["mesh"] as Mesh).duplicate()
			for s in mesh.get_surface_count():
				var src := mesh.surface_get_material(s) as ShaderMaterial
				var tex: Texture2D = null
				if src != null and src.shader.code.contains("#define GS_SCISSOR"):
					tex = src.get_shader_parameter("albedo_tex")
				if use == "fore":
					var m := ShaderMaterial.new()
					m.shader = FORE_SHADER
					m.set_shader_parameter("has_mask", tex != null)
					m.set_shader_parameter("fade", fore_fade)
					if tex != null:
						m.set_shader_parameter("mask", tex)
					_fore_mats.append(m)
					mesh.surface_set_material(s, m)
				else:
					mesh.surface_set_material(s, _material(data().get("near", {}), true, tex) if tex != null else _near_mat)
			parts.append({"mesh": mesh, "xform": p["xform"]})
		out = {"parts": parts, "top": raw["top"]}
	_parts[key] = out
	return out

static func _pick(list: Array, roll: float) -> Array:
	var total := 0.0
	for e: Array in list:
		total += float(e[1])
	roll *= total
	for e: Array in list:
		roll -= float(e[1])
		if roll <= 0.0:
			return e
	return list[-1]

func _near_ground() -> PackedFloat32Array:
	if _near_g.size() != world.width:
		_near_g = _smoothed(int(data().get("near", {}).get("smooth", 40)))
	return _near_g

## One stretch of the near row: props picked per spot from the biome there (dithered across a
## seam), sitting on the near ribbon, coloured like it.
func _near_segment(seg: int, size: int) -> Node3D:
	var root := Node3D.new()
	root.name = "near_%d" % seg
	var near: Dictionary = data().get("near", {})
	var ground := _near_ground()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world.world_seed, "near", seg])
	var z := -float(near.get("depth", 68)) * T
	var groups := {}        # model -> [[transform, custom]]
	var x := float(seg * size) + rng.randf() * 4.0
	var bs: Dictionary = data().get("biomes", {})
	while x < float((seg + 1) * size):
		var ab := biomes_at(x)
		var biome: String = ab[1] if rng.randf() < float(ab[2]) else ab[0]
		var pr: Dictionary = bs.get(biome, {}).get("props", {})
		var list: Array = pr.get("list", [])
		if not list.is_empty():
			var e := _pick(list, rng.randf())
			var m := _model(String(e[0]), "near")
			if not m.is_empty():
				var fit := float(e[2]) * float(pr.get("scale", 1.5)) * rng.randf_range(0.8, 1.2)
				var s := fit * T / float(m["top"])
				var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s * 0.6))
				var cx := clampi(int(x), 0, world.width - 1)
				var col := Color.from_string(String(_shape("near", biome).get("color", "#405040")), Color.GRAY).srgb_to_linear()
				var dz := rng.randf_range(-6.0, 6.0) * T
				var xf := Transform3D(b, Vector3(x * T, float(near.get("base", 1)) * T * 0.4, z + dz))
				var rows: Array = groups.get(e[0], [])
				rows.append([xf, Color(ground[cx], col.r, col.g, col.b)])
				groups[e[0]] = rows
		x += float(pr.get("spacing", 12.0)) * rng.randf_range(0.6, 1.4)
	for model: String in groups:
		_instances(root, _model(model, "near"), groups[model], z)
		counts["near"] += (groups[model] as Array).size()
	return root

## One stretch of the foreground: few props, each on the real ground (or up in the air, for a
## branch), in front of the plane. None over a town.
func _fore_segment(seg: int, size: int) -> Node3D:
	var root := Node3D.new()
	root.name = "fore_%d" % seg
	var f: Dictionary = data().get("fore", {})
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world.world_seed, "fore", seg])
	var zr: Array = f.get("z", [7.0, 13.0])
	var bs: Dictionary = data().get("biomes", {})
	var groups := {}
	var x := float(seg * size) + rng.randf() * 20.0
	while x < float((seg + 1) * size):
		var ab := biomes_at(x)
		var biome: String = ab[1] if rng.randf() < float(ab[2]) else ab[0]
		var fd: Dictionary = bs.get(biome, {}).get("fore", {})
		var list: Array = fd.get("list", [])
		var cx := clampi(int(x), 0, world.width - 1)
		var town := false
		for r: Vector2i in _sites:
			town = town or (cx >= r.x and cx <= r.y)
		if not list.is_empty() and not town:
			var e := _pick(list, rng.randf())
			var m := _model(String(e[0]), "fore")
			if not m.is_empty():
				var s := float(e[2]) * T / float(m["top"]) * rng.randf_range(0.85, 1.2)
				var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s))
				var z := rng.randf_range(float(zr[0]), float(zr[1])) * T
				var y := (_ground[cx] + float(e[3])) * T
				var col := Color.from_string(String(_shape("near", biome).get("color", "#303830")), Color.GRAY).srgb_to_linear().darkened(0.35)
				var rows: Array = groups.get(e[0], [])
				rows.append([Transform3D(b, Vector3(x * T, y, z)), Color(col.r, col.g, col.b, 1.0)])
				groups[e[0]] = rows
		x += float(fd.get("spacing", 60.0)) * rng.randf_range(0.6, 1.5)
	for model: String in groups:
		_instances(root, _model(model, "fore"), groups[model], 8.0 * T)
		counts["fore"] += (groups[model] as Array).size()
	return root

## One MultiMesh per part of a model. rows: [[transform, custom], ...].
func _instances(root: Node3D, m: Dictionary, rows: Array, z: float) -> void:
	for p: Dictionary in m["parts"]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = p["mesh"]
		mm.instance_count = rows.size()
		var lo := INF
		var hi := -INF
		for i in rows.size():
			var xf: Transform3D = rows[i][0]
			mm.set_instance_transform(i, xf * (p["xform"] as Transform3D))
			mm.set_instance_custom_data(i, rows[i][1])
			lo = minf(lo, xf.origin.x)
			hi = maxf(hi, xf.origin.x)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = AABB(Vector3(lo - 60.0, -1000.0, z - 60.0), Vector3(hi - lo + 120.0, world.height * T + 2000.0, 120.0))
		root.add_child(mmi)
