## Tile and wall definitions from data/tiles.json, as flat arrays indexed by id.
##   TileDefs.id("stone")  TileDefs.solid[id]  TileDefs.wall_id("stone_wall")
class_name TileDefs
extends RefCounted

const PATH := "res://data/tiles.json"

const AIR := 0

static var names: PackedStringArray = []
static var solid: PackedByteArray = []       ## blocks movement from every side
static var platform: PackedByteArray = []    ## one-way: blocks movement only from above (Track C)
static var ladder: PackedByteArray = []      ## climbable, not solid; top rung acts as a platform (Track C)
static var rope: PackedByteArray = []        ## a hanging rope: climbable like a ladder (also ladder); one per column run (core/world/rope.gd)
static var stairs: PackedByteArray = []      ## one-way stair treads: 1 rises to the right, 2 to the left (also platform)
static var opaque: PackedByteArray = []      ## blocks light
static var emit: PackedByteArray = []        ## light given off, 0-15
static var hardness: PackedFloat32Array = [] ## seconds to dig bare-handed; negative = unbreakable
static var burn: PackedByteArray = []        ## lava: burns what touches it (data/combat.json lava), a wall to walkers' nav
static var shape: PackedStringArray = []     ## how the mesher draws a light that stands in a cell: cap, crystal, moss ("" a post)
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
	platform.resize(n)
	ladder.resize(n)
	stairs.resize(n)
	rope.resize(n)
	opaque.resize(n)
	emit.resize(n)
	hardness.resize(n)
	burn.resize(n)
	shape.resize(n)
	colors.resize(n)
	for row: Dictionary in tiles:
		var i := int(row["id"])
		names[i] = row["name"]
		solid[i] = 1 if row.get("solid", false) else 0
		platform[i] = 1 if row.get("platform", false) else 0
		ladder[i] = 1 if row.get("ladder", false) else 0
		stairs[i] = int(row.get("stairs", 0))
		rope[i] = 1 if row.get("rope", false) else 0
		opaque[i] = 1 if row.get("opaque", false) else 0
		emit[i] = int(row.get("emit", 0))
		hardness[i] = float(row.get("hardness", 0.0))
		burn[i] = 1 if row.get("burn", false) else 0
		shape[i] = String(row.get("shape", ""))
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
