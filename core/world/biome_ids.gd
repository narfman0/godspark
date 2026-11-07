## The canonical biome ids from data/biomes.json: the one vocabulary worldgen, the sim, cultures,
## habitats and dressing all speak.
##   BiomeIds.has("mountain")   BiomeIds.ids()   BiomeIds.generated("surface")
class_name BiomeIds
extends RefCounted

const PATH := "res://data/biomes.json"

static var _rows := {}

static func ensure() -> void:
	if not _rows.is_empty():
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	for row: Dictionary in data["biomes"]:
		_rows[String(row["id"])] = row

static func has(id: String) -> bool:
	ensure()
	return _rows.has(id)

## Every id, in table order. family "" means all of them.
static func ids(family := "") -> PackedStringArray:
	ensure()
	var out := PackedStringArray()
	for id: String in _rows:
		if family == "" or _rows[id]["family"] == family:
			out.append(id)
	return out

## The ids worldgen makes today.
static func generated(family := "") -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in ids(family):
		if _rows[id]["generated"]:
			out.append(id)
	return out

## The surface strip of a world's meta.biomes: the rows with no band, west to east.
static func strip(meta: Dictionary) -> Array:
	return (meta.get("biomes", []) as Array).filter(func(s: Variant) -> bool: return s is Dictionary and not (s as Dictionary).has("band"))

## The underground regions of a world's meta.biomes (M6): rows with a band (deeps, nadir) and
## bounds x0, x1, y0, y1, the plain underdark between the named biomes. Empty for a world with
## none (under 2048 wide, old saves).
static func regions(meta: Dictionary) -> Array:
	return (meta.get("biomes", []) as Array).filter(func(s: Variant) -> bool: return s is Dictionary and (s as Dictionary).has("band"))

## The underground region row at a cell, or {}.
static func region_at(meta: Dictionary, x: float, y: float) -> Dictionary:
	for s: Variant in meta.get("biomes", []):
		if s is Dictionary and (s as Dictionary).has("band") and x >= float(s["x0"]) and x < float(s["x1"]) + 1.0 \
				and y >= float(s["y0"]) and y < float(s["y1"]) + 1.0:
			return s
	return {}
