## Dressing objects in core: the stable id table and placement rules from data/dressing.json,
## and the rule that keeps records honest when tiles change. Records live in their anchor
## cell's chunk (Chunk.objects); the view draws them (view/actors/dressing_view.gd).
##
## A record is (id, x, y, variant) with (x, y) the footprint's bottom-left cell. A ground
## object stands on the solid tiles under its footprint; a ceiling object hangs under the
## solid tiles over it. Removing a supporting tile, or putting a solid tile into the
## footprint, removes the object. Objects never block movement.
##
##   Dressing.id("tree_round"); Dressing.name_of(3); Dressing.footprint(id)
##   Dressing.records_in(world, cx, cy)      # [{id, x, y, v}]
##   Dressing.on_tile_changed(world, x, y)   # removes what lost support; returns chunks changed
class_name Dressing
extends RefCounted

const FILE := "res://data/dressing.json"

static var _ids := PackedStringArray()
static var _by_name := {}
static var _defs: Array = []      ## per id: the def Dictionary
static var _fp: Array[Vector2i] = []
static var _ceiling := PackedByteArray()
static var _tables := {}          ## the file's other top-level keys

static func ensure() -> void:
	if not _ids.is_empty():
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
	assert(d is Dictionary and d.has("ids"), "data/dressing.json needs an ids list")
	var objs: Dictionary = d.get("objects", {})
	_tables = d
	for n: String in d["ids"]:
		_by_name[n] = _ids.size()
		_ids.append(n)
		var def: Dictionary = objs.get(n, {})
		_defs.append(def)
		var fp: Array = def.get("footprint", [1, 1])
		_fp.append(Vector2i(int(fp[0]), int(fp[1])))
		_ceiling.append(1 if String(def.get("anchor", "ground")) == "ceiling" else 0)

## A top-level table of the file: density, ponds. {} if it has none.
static func table(key: String) -> Dictionary:
	ensure()
	var v: Variant = _tables.get(key, {})
	return v if v is Dictionary else {}

static func count() -> int:
	ensure()
	return _ids.size()

## The id for a name, -1 if unknown.
static func id(n: String) -> int:
	ensure()
	return _by_name.get(n, -1)

static func name_of(i: int) -> String:
	ensure()
	return _ids[i] if i >= 0 and i < _ids.size() else ""

static func def(i: int) -> Dictionary:
	ensure()
	return _defs[i] if i >= 0 and i < _defs.size() else {}

static func footprint(i: int) -> Vector2i:
	ensure()
	return _fp[i] if i >= 0 and i < _fp.size() else Vector2i.ONE

static func is_ceiling(i: int) -> bool:
	ensure()
	return i >= 0 and i < _ceiling.size() and _ceiling[i] != 0

## Records of one chunk in world coordinates: [{id, x, y, v}].
static func records_in(world: TileWorld, cx: int, cy: int) -> Array:
	var out: Array = []
	var c := world.chunk_at(cx, cy)
	if c == null:
		return out
	for i in c.object_count():
		var r := c.object_at(i)
		out.append({"id": r.x, "x": cx * K.CHUNK + r.y, "y": cy * K.CHUNK + r.z, "v": r.w})
	return out

## True if the object still has its support and a clear footprint in `world`.
static func holds(world: TileWorld, i: int, x: int, y: int) -> bool:
	var fp := footprint(i)
	var sy := y + fp.y if is_ceiling(i) else y - 1
	for dx in fp.x:
		if not world.is_solid(x + dx, sy):
			return false
		for dy in fp.y:
			if world.is_solid(x + dx, y + dy):
				return false
	return true

## After the tile at (x, y) changed: remove every object it supported or now blocks.
## Returns the chunk coordinates whose object lists changed (marked modified).
static func on_tile_changed(world: TileWorld, x: int, y: int) -> Array[Vector2i]:
	ensure()
	var changed: Array[Vector2i] = []
	# Anchors that can involve (x, y): footprints are at most a chunk wide and tall.
	var r := Rect2i(x - K.CHUNK + 1, y - K.CHUNK, K.CHUNK, K.CHUNK + 2)
	for cy in range(r.position.y >> 5, ((r.end.y - 1) >> 5) + 1):
		for cx in range(r.position.x >> 5, ((r.end.x - 1) >> 5) + 1):
			var c := world.chunk_at(cx, cy)
			if c == null or c.objects.is_empty():
				continue
			var hit := false
			for i in range(c.object_count() - 1, -1, -1):
				var o := c.object_at(i)
				var ox := cx * K.CHUNK + o.y
				var oy := cy * K.CHUNK + o.z
				var fp := footprint(o.x)
				if x < ox or x >= ox + fp.x or y < oy - 1 or y > oy + fp.y:
					continue
				if not holds(world, o.x, ox, oy):
					c.remove_object(i)
					hit = true
			if hit:
				c.modified = true
				changed.append(Vector2i(cx, cy))
	return changed
