## What the underground regions do to the picture, from data/backdrops.json "below" and the tile
## rows of data/looks.json "lights": all view, nothing in core reads it.
##
## Each light its colour. The field is one level per tile with no colour, so the shaders drew every
## emissive tile by torchlight. Here a coarse map over the light rectangle (gs_below_tint, one texel
## per TINT_CELL tiles, colour premultiplied by how much of the light there is that source's) gives
## the field's block light the colour of what lights it: a fungal dome teal, crystal blue, the lake's
## moss green, lava red, a drow street violet. Where no tile asks for a tint (`tint` in its lights
## row: the surface, a plain torch-lit cave) the map stays clear and nothing changes. The own carried
## light keeps its own colour near the hand (gs_own_lamp).
##
## Fog of the deep. A second map (gs_below_fog, one texel per FOG_CELL tiles) holds each region's fog
## colour and density, so fog changes across a seam as the rock does. A sheet just in front of the
## walls (view/shaders/deep_fog.gdshader) draws it: thin mist with drifting motes, lit where the
## field is lit, with a faint ambient of the region's own. The dark stays dark.
##
## The lake's water gives its own faint light (gs_lake: terrain.gdshader), since nothing on the shore
## reaches it.
##
## Rock glow. Rock and walls near a deep region's light take a faint glow of the region's colour
## (`rock`, `rock_glow` in its row; gs_below_rock, at FOG_CELL), so a lit cavern sits in tinted
## shadow, not in a black void. The plain underdark has none: unlit is black there.
##
## Glowing props. A dressing row with `light` lights the picture: the nearest of them are sources in
## the view's own light field (ViewPresenter's LightEngine, which is not the host's: combat reads its
## own, so a prop's light is never a rule), lamps for WorldLights, and tints.
##
##   var b := BelowLook.new(); view.add_child(b); b.setup(view)      # WorldView does this
##   BelowLook.row("fungal")                       # {fog, density, ambient, motes, ...}
##   BelowLook.tint_bytes(sources, rect, cell)     # the tint map's bytes, pure
##   BelowLook.fog_bytes(meta, rect, cell)         # the fog map's bytes, pure
##   BelowLook.rock_bytes(meta, rect, cell)        # the rock glow map's bytes, pure
##   b.set_props(records)                          # DressingView does this: {id, x, y} records
class_name BelowLook
extends Node3D

const FOG_SHADER := preload("res://view/shaders/deep_fog.gdshader")
const T := K.TILE_M
const TINT_CELL := 4
const FOG_CELL := 8
## Light ids of the props in the view's field, past any entity's or carried light's.
const PROP_ID := 0x40000000
## Field lights changed in a frame: each is a flood.
const PROPS_PER_FRAME := 2
## Tiles the focus moves before the nearest props are chosen again.
const PROP_MOVE := 8.0
## Seconds between tint maps while chunks keep arriving.
const TINT_EVERY := 0.25
## How far a tinted source's colour carries, tiles, at the strongest level.
const TINT_REACH := 15.0

var view: WorldView
var _rect := Rect2i()
var _tint_img: Image
var _tint_tex: ImageTexture
var _fog_img: Image
var _fog_tex: ImageTexture
var _rock_img: Image
var _rock_tex: ImageTexture
var _sheet: MeshInstance3D
var _sheet_mat: ShaderMaterial
var _tint_dirty := true
var _fog_dirty := true
var _wait := 0.0
## What the sheet is doing now, eased toward the region under the focus (for tests, tools too).
var ambient := 0.0
var motes := Vector4.ZERO
## Tinted sources in the last tint map.
var tinted := 0
## Every glowing prop drawn: [{key, pos, color, level, radius}].
var props: Array = []
## Those in the field now: key -> slot; what is wanted next: [prop], nearest first.
var _field := {}
var _want: Array = []
var _chosen_at := Vector2.INF

static func data() -> Dictionary:
	return Backdrops.data().get("below", {})

## A region's look; {} for anything not in the table (the caves, the surface).
static func row(biome: String) -> Dictionary:
	return (data().get("regions", {}) as Dictionary).get(biome, {})

## The colour a tile's light casts, and whether it asks for a tint at all: {color, tint}.
static func tile_light(name: String) -> Dictionary:
	var r: Variant = LightSources.table().get("tile:" + name)
	if r is Dictionary:
		return {"color": Color(String(r.get("color", "#ffa458"))), "tint": bool(r.get("tint", false))}
	return {"color": Color("#ffa458"), "tint": false}

## RGBA8 over rect, one texel per `cell` tiles (rows bottom to top, as the rect): colour
## premultiplied by alpha, alpha how much tinted light falls there. sources: [{x, y, color, reach,
## level (0-1)}]. Several sources in one cell count once at their strongest, so a lava pool costs what
## a lamp does. Empty when no source asks for a tint (tint false on every one).
static func tint_bytes(sources: Array, rect: Rect2i, cell: int) -> PackedByteArray:
	var w := ceili(float(rect.size.x) / cell)
	var h := ceili(float(rect.size.y) / cell)
	var out := PackedByteArray()
	out.resize(w * h * 4)
	var any := false
	var seeds := {}
	for s: Dictionary in sources:
		any = any or bool(s.get("tint", true))
		var c := Vector2i(floori(float(int(s["x"]) - rect.position.x) / cell), floori(float(int(s["y"]) - rect.position.y) / cell))
		if c.x < -8 or c.y < -8 or c.x >= w + 8 or c.y >= h + 8:
			continue
		var was: Dictionary = seeds.get(c, {})
		if was.is_empty() or float(s["level"]) > float(was["level"]):
			seeds[c] = s
	if not any:
		return out
	var r := PackedFloat32Array()
	r.resize(w * h * 4)
	for c: Vector2i in seeds:
		var s: Dictionary = seeds[c]
		var rad := float(s["reach"]) / cell
		var col: Color = s["color"]
		var k := float(s["level"])
		var n := ceili(rad)
		for dy in range(-n, n + 1):
			var ty := c.y + dy
			if ty < 0 or ty >= h:
				continue
			for dx in range(-n, n + 1):
				var tx := c.x + dx
				if tx < 0 or tx >= w:
					continue
				var f := 1.0 - sqrt(float(dx * dx + dy * dy)) / maxf(rad, 0.5)
				if f <= 0.0:
					continue
				var i := (tx + ty * w) * 4
				var a := f * k
				r[i] += col.r * a
				r[i + 1] += col.g * a
				r[i + 2] += col.b * a
				r[i + 3] += a
	for i in w * h:
		var a := r[i * 4 + 3]
		if a <= 0.0:
			continue
		var s := minf(a, 1.0) / a       # colour stays the mean, alpha saturates
		out[i * 4] = clampi(roundi(r[i * 4] * s * 255.0), 0, 255)
		out[i * 4 + 1] = clampi(roundi(r[i * 4 + 1] * s * 255.0), 0, 255)
		out[i * 4 + 2] = clampi(roundi(r[i * 4 + 2] * s * 255.0), 0, 255)
		out[i * 4 + 3] = clampi(roundi(minf(a, 1.0) * 255.0), 0, 255)
	return out

## RGBA8 over rect, one texel per `cell` tiles: a region's fog colour premultiplied by its density.
## Zero outside the regions.
static func fog_bytes(meta: Dictionary, rect: Rect2i, cell: int) -> PackedByteArray:
	var w := ceili(float(rect.size.x) / cell)
	var h := ceili(float(rect.size.y) / cell)
	var out := PackedByteArray()
	out.resize(w * h * 4)
	if BiomeIds.regions(meta).is_empty():
		return out
	for ty in h:
		var y := rect.position.y + ty * cell + cell / 2
		for tx in w:
			var reg := BiomeIds.region_at(meta, rect.position.x + tx * cell + cell / 2, y)
			if reg.is_empty():
				continue
			var l := row(String(reg["biome"]))
			if l.is_empty():
				continue
			var d := float(l.get("density", 0.0))
			var c := Color(String(l.get("fog", "#000000")))
			var i := (tx + ty * w) * 4
			out[i] = clampi(roundi(c.r * d * 255.0), 0, 255)
			out[i + 1] = clampi(roundi(c.g * d * 255.0), 0, 255)
			out[i + 2] = clampi(roundi(c.b * d * 255.0), 0, 255)
			out[i + 3] = clampi(roundi(d * 255.0), 0, 255)
	return out

## RGBA8 over rect, one texel per `cell` tiles: a region's rock glow, its `rock` colour times
## `rock_glow` (premultiplied), alpha the glow. Zero outside the regions and where a row has none.
static func rock_bytes(meta: Dictionary, rect: Rect2i, cell: int) -> PackedByteArray:
	var w := ceili(float(rect.size.x) / cell)
	var h := ceili(float(rect.size.y) / cell)
	var out := PackedByteArray()
	out.resize(w * h * 4)
	if BiomeIds.regions(meta).is_empty():
		return out
	for ty in h:
		var y := rect.position.y + ty * cell + cell / 2
		for tx in w:
			var reg := BiomeIds.region_at(meta, rect.position.x + tx * cell + cell / 2, y)
			if reg.is_empty():
				continue
			var l := row(String(reg["biome"]))
			var g := clampf(float(l.get("rock_glow", 0.0)), 0.0, 1.0)
			if g <= 0.0:
				continue
			var c := Color(String(l.get("rock", "#000000")))
			var i := (tx + ty * w) * 4
			out[i] = clampi(roundi(c.r * g * 255.0), 0, 255)
			out[i + 1] = clampi(roundi(c.g * g * 255.0), 0, 255)
			out[i + 2] = clampi(roundi(c.b * g * 255.0), 0, 255)
			out[i + 3] = clampi(roundi(g * 255.0), 0, 255)
	return out

func setup(v: WorldView) -> void:
	view = v
	var clear := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	_tint_tex = ImageTexture.create_from_image(clear)
	_fog_tex = ImageTexture.create_from_image(clear)
	_rock_tex = ImageTexture.create_from_image(clear)
	RenderingServer.global_shader_parameter_set("gs_below_tint", _tint_tex)
	RenderingServer.global_shader_parameter_set("gs_below_fog", _fog_tex)
	RenderingServer.global_shader_parameter_set("gs_below_rock", _rock_tex)
	RenderingServer.global_shader_parameter_set("gs_own_lamp", Vector4.ZERO)
	_sheet = MeshInstance3D.new()
	_sheet.name = "deep_fog"
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	_sheet.mesh = q
	_sheet_mat = ShaderMaterial.new()
	_sheet_mat.shader = FOG_SHADER
	_sheet.material_override = _sheet_mat
	_sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sheet.visible = false
	add_child(_sheet)
	meta_changed()

## The world's meta arrived or changed: the lake and the regions may be new.
func meta_changed() -> void:
	_fog_dirty = true
	var lake: Dictionary = (view.world.meta.get("descent", {}) as Dictionary).get("lake", {})
	if lake.is_empty():
		RenderingServer.global_shader_parameter_set("gs_lake", Vector4(0.0, -1.0, 0.0, 0.0))
	else:
		RenderingServer.global_shader_parameter_set("gs_lake", Vector4(float(lake["x0"]), float(lake["x1"]), float(lake["water"]), float(lake["bed"])))
	var l := row("deep_lake")
	RenderingServer.global_shader_parameter_set("gs_lake_glow", Color(String(l.get("water", "#1f8f80"))))

## The light rectangle moved or grew.
func rect_changed(r: Rect2i) -> void:
	if r != _rect:
		_rect = r
		_tint_dirty = true
		_fog_dirty = true

func emitters_changed() -> void:
	_tint_dirty = true

## The dressing's records: which of them glow (a row's `light`).
func set_props(records: Array) -> void:
	props.clear()
	var defs := DressingView.defs()
	for r: Dictionary in records:
		var d: Dictionary = defs.get(String(r.get("id", "")), {})
		var l: Variant = d.get("light")
		if not (l is Dictionary):
			continue
		var fp: Array = d.get("footprint", [1, 1])
		var level := int(l.get("level", 40))
		props.append({"key": "p%d,%d" % [int(r["x"]), int(r["y"])],
			"pos": Vector2(float(r["x"]) + float(fp[0]) * 0.5, float(r["y"]) + float(l.get("y", 1.0))),
			"color": Color(String(l.get("color", "#ffffff"))), "level": level, "radius": LightSources.reach(level)})
	_chosen_at = Vector2.INF
	_tint_dirty = true

## The glowing props in the field now, as lamps for WorldLights.
func lit_props() -> Array:
	var out: Array = []
	for p: Dictionary in _want:
		if _field.has(p["key"]):
			out.append(p)
	return out

## The field holds what was chosen, nothing queued.
func props_settled() -> bool:
	return _chosen_at != Vector2.INF and _queue_empty()

func _queue_empty() -> bool:
	if _field.size() != _want.size():
		return false
	for p: Dictionary in _want:
		if not _field.has(p["key"]):
			return false
	return true

## Every light-giving tile and prop near the rectangle, as tint_bytes takes it.
func sources() -> Array:
	var out: Array = []
	var cache := {}
	var area := Rect2(_rect.grow(int(TINT_REACH)))
	for p: Dictionary in props:
		if area.has_point(p["pos"]):
			out.append({"x": int((p["pos"] as Vector2).x), "y": int((p["pos"] as Vector2).y), "color": p["color"], "tint": true,
				"level": clampf(float(p["level"]) / LightEngine.TORCH, 0.2, 1.0), "reach": float(p["radius"]) + 3.0})
	for key: Vector2i in view.emitters:
		var box := Rect2i(key * K.CHUNK, Vector2i(K.CHUNK, K.CHUNK)).grow(int(TINT_REACH))
		if not box.intersects(_rect):
			continue
		for e: Vector3i in view.emitters[key]:
			var l: Dictionary = cache.get(e.z, {})
			if l.is_empty():
				l = tile_light(TileDefs.names[e.z])
				l["level"] = float(TileDefs.emit[e.z]) / 15.0
				l["reach"] = TINT_REACH * (0.5 + 0.5 * float(l["level"]))
				cache[e.z] = l
			out.append({"x": e.x, "y": e.y, "color": l["color"], "tint": l["tint"], "level": l["level"], "reach": l["reach"]})
	return out

func _refill_tint() -> void:
	_tint_dirty = false
	var src := sources()
	tinted = 0
	for s: Dictionary in src:
		tinted += 1 if bool(s["tint"]) else 0
	var w := ceili(float(_rect.size.x) / TINT_CELL)
	var h := ceili(float(_rect.size.y) / TINT_CELL)
	var bytes := tint_bytes(src, _rect, TINT_CELL)
	_tint_img = _put(_tint_img, _tint_tex, w, h, bytes, "gs_below_tint")

func _refill_fog() -> void:
	_fog_dirty = false
	var w := ceili(float(_rect.size.x) / FOG_CELL)
	var h := ceili(float(_rect.size.y) / FOG_CELL)
	_fog_img = _put(_fog_img, _fog_tex, w, h, fog_bytes(view.world.meta, _rect, FOG_CELL), "gs_below_fog")
	_rock_img = _put(_rock_img, _rock_tex, w, h, rock_bytes(view.world.meta, _rect, FOG_CELL), "gs_below_rock")

func _put(img: Image, tex: ImageTexture, w: int, h: int, bytes: PackedByteArray, global: String) -> Image:
	if img == null or img.get_size() != Vector2i(w, h):
		img = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, bytes)
		tex.set_image(img)
		RenderingServer.global_shader_parameter_set(global, tex)
	else:
		img.set_data(w, h, false, Image.FORMAT_RGBA8, bytes)
		tex.update(img)
	return img

func _process(delta: float) -> void:
	if view == null or _rect.size.x <= 0:
		return
	_wait -= delta
	if _tint_dirty and _wait <= 0.0:
		_wait = TINT_EVERY
		_refill_tint()
	if _fog_dirty:
		_refill_fog()
	_own_lamp()
	_props()
	_follow(delta)

## Keep the nearest glowing props in the field, a few floods a frame.
func _props() -> void:
	if view.focus.distance_to(_chosen_at) > PROP_MOVE:
		_chosen_at = view.focus
		var n := int(Dressing.table("below").get("field_lights", 14))
		_want = WorldLights.pick(props, view.focus, n)
	var keep := {}
	for p: Dictionary in _want:
		keep[p["key"]] = true
	var budget := PROPS_PER_FRAME
	for k: String in _field.keys():
		if budget > 0 and not keep.has(k):
			view.light.remove_light(int(_field[k]))
			_field.erase(k)
			budget -= 1
	var used := {}
	for k: String in _field:
		used[int(_field[k])] = true
	var slot := PROP_ID
	for p: Dictionary in _want:
		if budget <= 0:
			break
		if _field.has(p["key"]):
			continue
		while used.has(slot):
			slot += 1
		used[slot] = true
		_field[p["key"]] = slot
		view.light.add_light(slot, (p["pos"] as Vector2).x, (p["pos"] as Vector2).y, int(p["level"]))
		budget -= 1

## The carried light nearest the focus keeps its own colour near it.
func _own_lamp() -> void:
	var best := Vector4.ZERO
	var bd := INF
	for id: int in view.carried:
		var c: Dictionary = view.carried[id]
		var d := (c["pos"] as Vector2).distance_squared_to(view.focus)
		if d < bd:
			bd = d
			best = Vector4((c["pos"] as Vector2).x, (c["pos"] as Vector2).y, float(c["radius"]), 1.0)
	RenderingServer.global_shader_parameter_set("gs_own_lamp", best)

func _follow(delta: float) -> void:
	var reg := BiomeIds.region_at(view.world.meta, view.focus.x, view.focus.y)
	var l := row(String(reg.get("biome", "")))
	_sheet.visible = not l.is_empty() or ambient > 0.002
	if not _sheet.visible:
		return
	var k := 1.0 - exp(-delta * 1.5)
	ambient = lerpf(ambient, float(l.get("ambient", 0.0)), k)
	var m: Array = l.get("motes", [0.0, 0.0, 0.0, 0.0])
	motes = motes.lerp(Vector4(float(m[0]), float(m[1]), float(m[2]), float(m[3])), k)
	_sheet_mat.set_shader_parameter("ambient", ambient)
	_sheet_mat.set_shader_parameter("motes", motes)
	var half := view.view_half + Vector2(4, 4)
	var z := float(data().get("z_tiles", -0.44))
	_sheet.position = Vector3(view.focus.x * T, view.focus.y * T, z * T)
	_sheet.scale = Vector3(half.x * 2.0 * T, half.y * 2.0 * T, 1.0)
