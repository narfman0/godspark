## Tile and wall definitions from data/tiles.json, as flat arrays indexed by id.
##   TileDefs.id("stone")  TileDefs.solid[id]  TileDefs.wall_id("stone_wall")
class_name TileDefs
extends RefCounted

const PATH := "res://data/tiles.json"

const AIR := 0

static var names: PackedStringArray = []
static var solid: PackedByteArray = []       ## blocks movement
static var opaque: PackedByteArray = []      ## blocks light
static var emit: PackedByteArray = []        ## light given off, 0-15
static var hardness: PackedFloat32Array = [] ## seconds to dig bare-handed; negative = unbreakable
static var colors: PackedColorArray = []
static var wall_names: PackedStringArray = []
static var wall_colors: PackedColorArray = []
static var _ids := {}
static var _wall_ids := {}
static var _loaded := false

static func ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	var tiles: Array = data["tiles"]
	var n := 0
	for row: Dictionary in tiles:
		n = maxi(n, int(row["id"]) + 1)
	names.resize(n)
	solid.resize(n)
	opaque.resize(n)
	emit.resize(n)
	hardness.resize(n)
	colors.resize(n)
	for row: Dictionary in tiles:
		var i := int(row["id"])
		names[i] = row["name"]
		solid[i] = 1 if row.get("solid", false) else 0
		opaque[i] = 1 if row.get("opaque", false) else 0
		emit[i] = int(row.get("emit", 0))
		hardness[i] = float(row.get("hardness", 0.0))
		colors[i] = Color(row.get("color", "#ff00ff"))
		_ids[row["name"]] = i
	var walls: Array = data["walls"]
	n = 0
	for row: Dictionary in walls:
		n = maxi(n, int(row["id"]) + 1)
	wall_names.resize(n)
	wall_colors.resize(n)
	for row: Dictionary in walls:
		var i := int(row["id"])
		wall_names[i] = row["name"]
		wall_colors[i] = Color(row.get("color", "#000000"))
		_wall_ids[row["name"]] = i

static func id(tile_name: String) -> int:
	ensure()
	assert(_ids.has(tile_name), "unknown tile: " + tile_name)
	return _ids[tile_name]

static func wall_id(wall_name: String) -> int:
	ensure()
	assert(_wall_ids.has(wall_name), "unknown wall: " + wall_name)
	return _wall_ids[wall_name]
