## Tile-anchored decorations (trees, bushes, rocks, grass, flowers, cave fungi, crystals) from
## data/dressing.json, drawn as one MultiMesh per (object, mesh part), lit by the tile light
## textures like everything else (LitMaterials). Pure view: it draws the records it is given.
##
##   var dv := DressingView.new(); add_child(dv)
##   dv.set_objects([{"id": "tree_birch", "x": 120, "y": 64}, ...])   # x, y: the footprint's
##                                                                       # bottom-left cell
##   DressingView.scatter(world, x0, x1, seed)   # deterministic demo placement (no core RNG)
##
## Records are what the core should eventually own and replicate (tile-object records:
## {id, x, y}, plus a variant byte if wanted); this node only needs that list. Objects whose
## model is not fetched are skipped silently (dressing has no primitive fallback).
class_name DressingView
extends Node3D

const FILE := "res://data/dressing.json"

static var _defs := {}
## id -> {parts: [{mesh, xform}], top: float (model height above its origin, m)} or {} if missing
static var _models := {}

var records: Array = []
var counts := {}     ## id -> instances drawn

static func defs() -> Dictionary:
	if _defs.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		_defs = d.get("objects", {}) if d is Dictionary else {}
	return _defs

## The parts of an object's model with lit materials, or {} when its file is missing.
static func model_parts(id: String) -> Dictionary:
	if _models.has(id):
		return _models[id]
	var out := parts_of(defs().get(id, {}))
	_models[id] = out
	return out

## The same for any row with a model and textures: {parts, top}, or {} when its file is missing.
static func parts_of(def: Dictionary) -> Dictionary:
	var out := {}
	var inst := GltfCache.instance(String(def.get("model", ""))) if not def.is_empty() else null
	if inst != null:
		var parts: Array = []
		var top := 0.0
		for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh == null or not mi.visible:
				continue
			var xf := GltfCache.mesh_xform(mi, inst)
			var mesh: Mesh = _retexture(mi.mesh, def.get("textures", {}))
			parts.append({"mesh": LitMaterials.lit_mesh(mesh), "xform": xf})
			top = maxf(top, (xf * mi.get_aabb()).end.y)
		inst.free()
		if not parts.is_empty() and top > 0.0001:
			out = {"parts": parts, "top": top}
	return out

## dressing.json "textures": {material name: png or "#hex" colour, "*": png for materials
## with no texture}.
## Some cooked Synty files lost their atlas (POLYGON_Nature's trees and bushes have UVs into
## PolygonNature_01.png but reference no image); this puts it back, opaque.
static func _retexture(mesh: Mesh, map: Dictionary) -> Mesh:
	if map.is_empty():
		return mesh
	var out: Mesh = mesh.duplicate()
	for s in out.get_surface_count():
		var m := out.surface_get_material(s) as BaseMaterial3D
		if m == null:
			continue
		var path := String(map.get(m.resource_name, ""))
		if path == "" and m.albedo_texture == null:
			path = String(map.get("*", ""))
		if path == "":
			continue
		var nm: BaseMaterial3D = m.duplicate()
		if path.begins_with("#"):
			nm.albedo_texture = null      # a flat colour instead
			nm.albedo_color = Color.from_string(path, Color.WHITE)
		else:
			var tex := _texture(path)
			if tex == null:
				continue
			nm.albedo_texture = tex
		nm.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		out.surface_set_material(s, nm)
	return out

static var _textures := {}
static func _texture(path: String) -> Texture2D:
	if not _textures.has(path):
		var img := Image.load_from_file(path) if FileAccess.file_exists(path) else null
		_textures[path] = ImageTexture.create_from_image(img) if img != null else null
	return _textures[path]

## Replace everything drawn with these records ([{id, x, y}]).
func set_objects(recs: Array) -> void:
	records = recs
	for c in get_children():
		c.queue_free()
	counts.clear()
	var by_id := {}
	for r: Dictionary in recs:
		var id := String(r.get("id", ""))
		if not by_id.has(id):
			by_id[id] = []
		by_id[id].append(r)
	for id: String in by_id:
		var def: Dictionary = defs().get(id, {})
		var m := model_parts(id)
		if def.is_empty() or m.is_empty():
			continue
		var xforms: Array[Transform3D] = []
		for r: Dictionary in by_id[id]:
			xforms.append(placement(def, m["top"], int(r["x"]), int(r["y"])))
		for p: Dictionary in m["parts"]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = p["mesh"]
			mm.instance_count = xforms.size()
			for i in xforms.size():
				mm.set_instance_transform(i, xforms[i] * (p["xform"] as Transform3D))
			var mmi := MultiMeshInstance3D.new()
			mmi.name = id
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.set_instance_shader_parameter("tint", Color.from_string(String(def.get("tint", "#ffffff")), Color.WHITE))
			add_child(mmi)
		counts[id] = xforms.size()

## World transform of one placed object: fitted to fit_h tiles, centred on its footprint,
## on its plane z, squashed in depth, with a per-cell jitter in scale and yaw.
static func placement(def: Dictionary, top_m: float, x: int, y: int) -> Transform3D:
	var t := K.TILE_M
	var fp: Array = def.get("footprint", [1, 1])
	var h := hash(Vector2i(x, y))
	var r1 := float(h & 0xffff) / 65535.0
	var r2 := float((h >> 16) & 0xffff) / 65535.0
	var s := float(def.get("fit_h", 1.0)) * t / top_m
	s *= 1.0 + float(def.get("jitter", 0.0)) * (r1 * 2.0 - 1.0)
	var yaw := deg_to_rad(float(def.get("turn", 0.0))) + (0.0 if def.get("still", false) else (r2 * 2.0 - 1.0) * 0.6)
	var b := Basis.from_scale(Vector3(1, 1, float(def.get("depth", 1.0)))) * Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3.ONE * s)
	var pos := Vector3((x + float(fp[0]) * 0.5) * t, y * t, float(def.get("z", 0.0)) * t)
	if String(def.get("anchor", "ground")) == "ceiling":
		b = Basis(Vector3.FORWARD, PI) * b
		pos.y = (y + float(fp[1])) * t
	return Transform3D(b, pos)

## Deterministic demo scatter over columns x0..x1: surface objects on the first floor from the
## top of each column, cave objects on floors further down. Respects footprints (air) and
## support (solid under every footprint column). biome: the surface biome to match (the test
## world is all meadow). A stand-in until worldgen places dressing records in core.
static func scatter(world: TileWorld, x0: int, x1: int, seed: int, biome := "meadow", density := 0.45) -> Array:
	var out: Array = []
	TileDefs.ensure()
	var ids: Array = defs().keys()
	ids.sort()
	var taken := {}   # Vector2i -> true
	for band in ["surface", "cave"]:
		var x := x0
		while x <= x1:
			var floors := _floors(world, x)
			var list: Array = floors.slice(0, 1) if band == "surface" else floors.slice(1)
			var placed_w := 1
			for fy: int in list:
				var hx := hash(Vector3i(x, fy, seed))
				if float(hx & 0xffff) / 65535.0 > (density if band == "surface" else density * 0.5):
					continue
				var uid := world.get_fg(x, fy - 1)
				var under := TileDefs.names[uid] if uid >= 0 and uid < TileDefs.names.size() else ""
				var cands: Array = []
				var total := 0.0
				for id: String in ids:
					var d: Dictionary = defs()[id]
					var w: Dictionary = d.get("where", {})
					if String(w.get("band", "surface")) != band:
						continue
					var bl: Array = w.get("biomes", [])
					if band == "surface" and not bl.is_empty() and not biome in bl:
						continue
					var on: Array = w.get("on", [])
					if under != "" and not on.is_empty() and not under in on:
						continue
					if not _fits(world, d, x, fy, taken):
						continue
					cands.append(id)
					total += float(d.get("weight", 1))
				if cands.is_empty():
					continue
				var pick := float((hx >> 16) & 0xffff) / 65535.0 * total
				var chosen: String = cands[-1]
				for id: String in cands:
					pick -= float(defs()[id].get("weight", 1))
					if pick <= 0.0:
						chosen = id
						break
				var fp: Array = defs()[chosen].get("footprint", [1, 1])
				for dx in int(fp[0]):
					for dy in int(fp[1]):
						taken[Vector2i(x + dx, fy + dy)] = true
				out.append({"id": chosen, "x": x, "y": fy})
				if band == "surface":
					placed_w = int(fp[0])
			x += placed_w
	return out

## y of every floor in column x (an air cell with a solid tile under it), top first.
static func _floors(world: TileWorld, x: int) -> Array:
	var out: Array = []
	for y in range(world.height - 1, 0, -1):
		if not world.is_solid(x, y) and world.get_fg(x, y) == TileDefs.AIR and world.is_solid(x, y - 1):
			out.append(y)
	return out

static func _fits(world: TileWorld, d: Dictionary, x: int, y: int, taken: Dictionary) -> bool:
	var fp: Array = d.get("footprint", [1, 1])
	for dx in int(fp[0]):
		if not world.is_solid(x + dx, y - 1):
			return false
		for dy in int(fp[1]):
			var c := Vector2i(x + dx, y + dy)
			if taken.has(c) or world.get_fg(c.x, c.y) != TileDefs.AIR:
				return false
	return true
