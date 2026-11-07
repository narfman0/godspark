## Dressing the underground regions by their tiles, view side: a deterministic scatter over a
## chunk's floors and ceilings from the data/dressing.json rows with where.band "below". Core keeps
## no records of it, so it costs no world bytes and moves no seed; every client derives the same
## objects from the same tiles, and a dug floor loses its mushroom when its chunk is read again.
## (stage_dressing's own cave pass cannot do this: one sample in 700 tiles, and it passes no biome.)
##
## A row matches a cell by where: biomes (region names, BiomeIds.region_at; empty means any region)
## and on (tile names it stands on, or hangs from for anchor ceiling). `gap` keeps a large row to
## one try per that many columns. data/dressing.json "below": density per region, the chance a
## floor or ceiling cell tries at all; a row's where.chance replaces it (drow rows, on dark_stone,
## which only their style uses, stand on a city's roofs whatever the region), and where.back and
## where.not_back name the walls it may or may not stand before (a room has one, a roof does not).
## A ceiling cell tries at below.ceiling of that.
##
##   var rd := RegionDressing.new(world)    # follows the world's edits
##   rd.records_in(cx, cy)                  # [{id: name, x, y}], cached per chunk
##   RegionDressing.matches(def, "fungal", "mycelium")
##   RegionDressing.backed(def, "dark_wall")   # may it stand before this wall?
class_name RegionDressing
extends RefCounted

const SALT := 0x5a17
const BAND := "below"

static var _rows: Array = []      ## [{id, def, ceiling, fp}] sorted by id
static var _cands := {}           ## "biome|under|ceiling" -> rows

var world: TileWorld
var _cache := {}                  ## Vector2i -> records
var _top := -1                    ## first row above every region

## Every below row, id-sorted so all clients walk them alike.
static func rows() -> Array:
	if _rows.is_empty():
		var ids: Array = DressingView.defs().keys()
		ids.sort()
		for id: String in ids:
			var d: Dictionary = DressingView.defs()[id]
			if String(d.get("where", {}).get("band", "")) != BAND:
				continue
			var fp: Array = d.get("footprint", [1, 1])
			_rows.append({"id": id, "def": d, "ceiling": String(d.get("anchor", "ground")) == "ceiling",
				"fp": Vector2i(int(fp[0]), int(fp[1]))})
	return _rows

## Does a row grow in this region on this tile?
static func matches(def: Dictionary, biome: String, under: String) -> bool:
	var w: Dictionary = def.get("where", {})
	var bl: Array = w.get("biomes", [])
	var on: Array = w.get("on", [])
	return (bl.is_empty() or biome in bl) and (on.is_empty() or under in on)

## May a row stand in a cell with this wall behind it ("" none)?
static func backed(def: Dictionary, wall: String) -> bool:
	var w: Dictionary = def.get("where", {})
	var want: Array = w.get("back", [])
	return (want.is_empty() or wall in want) and not wall in (w.get("not_back", []) as Array)

## The rows that may be tried in this region on this tile, ceiling rows or ground rows.
static func candidates(biome: String, under: String, ceiling: bool) -> Array:
	var key := "%s|%s|%s" % [biome, under, ceiling]
	if _cands.has(key):
		return _cands[key]
	var out: Array = []
	for r: Dictionary in rows():
		if bool(r["ceiling"]) == ceiling and matches(r["def"], biome, under):
			out.append(r)
	_cands[key] = out
	return out

## How often a floor or ceiling cell of a region tries (data/dressing.json below.density).
static func density(biome: String) -> float:
	return float(Dressing.table("below").get("density", {}).get(biome, 0.0))

## The chance a cell tries this row.
static func chance(def: Dictionary, biome: String, ceiling: bool) -> float:
	var c := float(def.get("where", {}).get("chance", density(biome)))
	return c * float(Dressing.table("below").get("ceiling", 1.0)) if ceiling else c

## A column a row with a gap may use: one per `gap` columns, the same on every floor.
static func on_gap(x: int, gap: int) -> bool:
	if gap <= 1:
		return true
	return posmod(x, gap) == posmod(hash(Vector2i(floori(float(x) / gap), SALT)), gap)

func _init(w: TileWorld) -> void:
	world = w
	_read_top()
	world.chunk_changed.connect(_forget_chunk)
	world.tile_changed.connect(_forget_tile)

func meta_changed() -> void:
	_cache.clear()
	_read_top()

## The highest row anything grows on: the regions' top, or the caves' for a city in them. -1 with no
## regions: a small or old world is left as it was.
func _read_top() -> void:
	_top = -1
	var regs := BiomeIds.regions(world.meta)
	for r: Dictionary in regs:
		_top = maxi(_top, int(r["y1"]))
	var caves: Variant = world.meta.get("bands", {}).get("caves", null)
	if caves is Array and not regs.is_empty():
		_top = maxi(_top, int((caves as Array)[1]))

func _forget_chunk(cx: int, cy: int) -> void:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			_cache.erase(Vector2i(cx + dx, cy + dy))

func _forget_tile(x: int, y: int, layer: int, _old: int, _now: int) -> void:
	if layer == TileWorld.Layer.FG:
		_forget_chunk(x >> 5, y >> 5)

## Does an edit at row y touch anything this draws?
func covers(y: int) -> bool:
	return y <= _top + 32

## A chunk's records. [] above the regions. Not cached while a neighbour is missing on a client:
## a footprint may reach into it.
func records_in(cx: int, cy: int) -> Array:
	var key := Vector2i(cx, cy)
	if _cache.has(key):
		return _cache[key]
	if cy * K.CHUNK > _top or _top < 0:
		return []
	var whole := true
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var nx := cx + dx
			var ny := cy + dy
			if nx >= 0 and ny >= 0 and nx < world.chunks_x and ny < world.chunks_y and not world.has_chunk(nx, ny):
				whole = false
	var out := _scan(cx, cy)
	if whole:
		_cache[key] = out
	return out

func _scan(cx: int, cy: int) -> Array:
	var out: Array = []
	var taken := {}
	var x0 := cx * K.CHUNK
	var y0 := cy * K.CHUNK
	var air := TileDefs.AIR
	var solid := TileDefs.solid
	var names := TileDefs.names
	for ly in K.CHUNK:
		var y := y0 + ly
		for lx in K.CHUNK:
			var x := x0 + lx
			if world.get_fg(x, y) != air or world.get_liquid(x, y) != 0:
				continue
			var below := world.get_fg(x, y - 1)
			var above := world.get_fg(x, y + 1)
			if solid[below] != 0:
				_try(out, taken, x, y, names[below], false)
			if solid[above] != 0:
				_try(out, taken, x, y, names[above], true)
	return out

func _try(out: Array, taken: Dictionary, x: int, y: int, under: String, ceiling: bool) -> void:
	var h := hash(Vector3i(x, y, SALT + (1 if ceiling else 0)))
	var region := BiomeIds.region_at(world.meta, x, y)
	var biome := String(region.get("biome", ""))    # "" in the caves: only rows for any region
	var roll := float(h & 0xffff) / 65535.0
	var bg := world.get_bg(x, y)
	var wall := TileDefs.wall_names[bg] if bg > 0 and bg < TileDefs.wall_names.size() else ""
	var cands: Array = []
	var total := 0.0
	for r: Dictionary in candidates(biome, under, ceiling):
		var fy: int = y - (r["fp"] as Vector2i).y + 1 if ceiling else y
		if roll <= chance(r["def"], biome, ceiling) and on_gap(x, int((r["def"] as Dictionary).get("gap", 0))) \
				and backed(r["def"], wall) and _fits(r, x, fy, taken):
			cands.append(r)
			total += float((r["def"] as Dictionary).get("weight", 1))
	if cands.is_empty():
		return
	var pick := float((h >> 16) & 0x7fff) / 32767.0 * total
	var chosen: Dictionary = cands[-1]
	for r: Dictionary in cands:
		pick -= float((r["def"] as Dictionary).get("weight", 1))
		if pick <= 0.0:
			chosen = r
			break
	var fp: Vector2i = chosen["fp"]
	var fy: int = y - fp.y + 1 if ceiling else y
	for dx in fp.x:
		for dy in fp.y:
			taken[Vector2i(x + dx, fy + dy)] = true
	out.append({"id": chosen["id"], "x": x, "y": fy})

## Every footprint cell open and free, level support along its width.
func _fits(r: Dictionary, x: int, y: int, taken: Dictionary) -> bool:
	var fp: Vector2i = r["fp"]
	var ceiling: bool = r["ceiling"]
	for dx in fp.x:
		if not world.is_solid(x + dx, y + fp.y if ceiling else y - 1):
			return false
		for dy in fp.y:
			var c := Vector2i(x + dx, y + dy)
			if taken.has(c) or world.get_fg(c.x, c.y) != TileDefs.AIR or world.get_liquid(c.x, c.y) != 0:
				return false
	return true
