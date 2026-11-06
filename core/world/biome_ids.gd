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
