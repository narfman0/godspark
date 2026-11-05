## The tile grid of one realm: the single source of truth for terrain. Pure data, no nodes.
## Tile (0, 0) is bottom-left, y grows upward. Everything outside the grid reads as bedrock.
##
## Dense (the default; hosts, worldgen, saves): every chunk exists. Sparse (a client's
## mirror, `TileWorld.new(w, h, seed, true)`): chunks exist only between `ensure_chunk` and
## `unload_chunk`. An UNLOADED cell is one whose chunk does not exist. It reads as
## `bedrock` from get_fg (solid and unbreakable, so nothing walks, digs or builds into it),
## 0 from get_bg and get_liquid, and ignores writes. Light and the mesher do not use get_fg
## for it: `light_fg` reads it as air above `sky_line` (the column's surface height from the
## host, so sunlight still reaches a surface whose sky is not loaded) and as bedrock below,
## and the view draws no mesh for it. content_hash treats it as an all-zero chunk.
##
##   var world := TileWorld.new(2048, 1024, seed)
##   world.set_fg(x, y, TileDefs.id("stone"))     # emits tile_changed
##   world.is_solid(x, y)
class_name TileWorld
extends RefCounted

enum Layer { FG, BG, LIQUID }

## One cell changed through a set_* call. Bulk writes with `quiet` skip it; whoever
## does them calls `chunk_changed` for what they touched.
signal tile_changed(x: int, y: int, layer: Layer, old: int, now: int)
## A whole chunk was rewritten (generation, load, a chunk arriving from the host).
signal chunk_changed(cx: int, cy: int)

var width: int
var height: int
var world_seed: int
var chunks_x: int
var chunks_y: int
## What worldgen knows beyond tiles: surface heights, biome strip, depth bands, sites and
## routes. Plain data that survives JSON (schema in docs/architecture.md).
var meta := {}
## True when chunks are allocated lazily (see the header).
var sparse := false
## Per column: unloaded cells above this y read as air to light_fg (sparse worlds). Empty:
## every unloaded cell reads as bedrock.
var sky_line := PackedInt32Array()
var _chunks: Array[Chunk] = []
var _bedrock: int
var _loaded_count := 0

func _init(w: int, h: int, seed_value := 0, sparse_ := false) -> void:
	assert(w % K.CHUNK == 0 and h % K.CHUNK == 0, "world size must be a multiple of the chunk size")
	TileDefs.ensure()
	_bedrock = TileDefs.id("bedrock")
	width = w
	height = h
	world_seed = seed_value
	chunks_x = w / K.CHUNK
	chunks_y = h / K.CHUNK
	sparse = sparse_
	_chunks.resize(chunks_x * chunks_y)
	if not sparse:
		for cy in chunks_y:
			for cx in chunks_x:
				_chunks[cx + cy * chunks_x] = Chunk.new(cx, cy)
		_loaded_count = chunks_x * chunks_y

func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height

## The chunk, or null when it is unloaded (sparse worlds) or outside the grid.
func chunk_at(cx: int, cy: int) -> Chunk:
	if cx < 0 or cy < 0 or cx >= chunks_x or cy >= chunks_y:
		return null
	return _chunks[cx + cy * chunks_x]

func has_chunk(cx: int, cy: int) -> bool:
	return chunk_at(cx, cy) != null

## True when (x, y) is inside the grid and its chunk exists.
func is_loaded(x: int, y: int) -> bool:
	return in_bounds(x, y) and _chunks[(x >> 5) + (y >> 5) * chunks_x] != null

## Chunks that exist (all of them in a dense world).
func loaded_count() -> int:
	return _loaded_count

## The chunk, allocating an empty (all air) one if it is unloaded. Emits nothing: the caller
## fills it and emits chunk_changed.
func ensure_chunk(cx: int, cy: int) -> Chunk:
	var i := cx + cy * chunks_x
	if _chunks[i] == null:
		_chunks[i] = Chunk.new(cx, cy)
		_loaded_count += 1
	return _chunks[i]

## Free a chunk (sparse worlds only) and emit chunk_changed. False if it was not loaded.
func unload_chunk(cx: int, cy: int) -> bool:
	if not sparse or chunk_at(cx, cy) == null:
		return false
	_chunks[cx + cy * chunks_x] = null
	_loaded_count -= 1
	chunk_changed.emit(cx, cy)
	return true

func get_fg(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return _bedrock
	var c := _chunks[(x >> 5) + (y >> 5) * chunks_x]
	if c == null:
		return _bedrock
	return c.fg.decode_u16(((x & 31) + (y & 31) * K.CHUNK) * 2)

## get_fg for light: an unloaded cell is air above sky_line and bedrock at or below it.
func light_fg(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return _bedrock
	var c := _chunks[(x >> 5) + (y >> 5) * chunks_x]
	if c == null:
		return TileDefs.AIR if x < sky_line.size() and y > sky_line[x] else _bedrock
	return c.fg.decode_u16(((x & 31) + (y & 31) * K.CHUNK) * 2)

## True if an unloaded chunk lies wholly above sky_line (light_fg reads it as air).
func unloaded_is_sky(cx: int, cy: int) -> bool:
	if sky_line.size() < width:
		return false
	var y0 := cy * K.CHUNK
	for x in range(cx * K.CHUNK, (cx + 1) * K.CHUNK):
		if sky_line[x] >= y0:
			return false
	return true

func get_bg(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return 0
	var c := _chunks[(x >> 5) + (y >> 5) * chunks_x]
	return 0 if c == null else c.bg[(x & 31) + (y & 31) * K.CHUNK]

func get_liquid(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return 0
	var c := _chunks[(x >> 5) + (y >> 5) * chunks_x]
	return 0 if c == null else c.liquid[(x & 31) + (y & 31) * K.CHUNK]

func is_solid(x: int, y: int) -> bool:
	return TileDefs.solid[get_fg(x, y)] != 0

func is_opaque(x: int, y: int) -> bool:
	return TileDefs.opaque[get_fg(x, y)] != 0

## Returns false when out of bounds or already that value.
func set_fg(x: int, y: int, id: int, quiet := false) -> bool:
	return _write(Layer.FG, x, y, id, quiet)

func set_bg(x: int, y: int, id: int, quiet := false) -> bool:
	return _write(Layer.BG, x, y, id, quiet)

func set_liquid(x: int, y: int, value: int, quiet := false) -> bool:
	return _write(Layer.LIQUID, x, y, value, quiet)

func _write(layer: Layer, x: int, y: int, value: int, quiet: bool) -> bool:
	if not in_bounds(x, y):
		return false
	var c := _chunks[(x >> 5) + (y >> 5) * chunks_x]
	if c == null:
		return false
	var i := (x & 31) + (y & 31) * K.CHUNK
	var old: int
	match layer:
		Layer.FG:
			old = c.fg.decode_u16(i * 2)
			if old == value:
				return false
			c.fg.encode_u16(i * 2, value)
		Layer.BG:
			old = c.bg[i]
			if old == value:
				return false
			c.bg[i] = value
		Layer.LIQUID:
			old = c.liquid[i]
			if old == value:
				return false
			c.liquid[i] = value
	if not quiet:
		c.modified = true
		tile_changed.emit(x, y, layer, old, value)
	return true

## Highest solid tile per column (-1 for an empty column): what worldgen stores as
## meta.surface. Dense worlds only (unloaded cells read as bedrock).
func scan_surface() -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(width)
	for x in width:
		var y := height - 1
		while y >= 0 and not is_solid(x, y):
			y -= 1
		out[x] = y
	return out

## Hex digest of every layer of every chunk: two worlds with the same digest are identical.
func content_hash() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var blank: Chunk = null
	for c in _chunks:
		if c == null:
			if blank == null:
				blank = Chunk.new(0, 0)
			c = blank
		ctx.update(c.fg)
		ctx.update(c.bg)
		ctx.update(c.liquid)
	return ctx.finish().hex_encode()

## A small fixed world for tests and demos: flat ground at half height with stone under
## dirt under grass, a pit, a few wooden platforms, a cave pocket and one torch.
static func make_test(w := 256, h := 128) -> TileWorld:
	var world := TileWorld.new(w, h, 1)
	var dirt := TileDefs.id("dirt")
	var grass := TileDefs.id("grass")
	var stone := TileDefs.id("stone")
	var wood := TileDefs.id("wood")
	var ground := h / 2
	for x in w:
		for y in ground:
			var id := stone
			if y == ground - 1:
				id = grass
			elif y >= ground - 4:
				id = dirt
			world.set_fg(x, y, id, true)
			world.set_bg(x, y, TileDefs.wall_id("dirt_wall" if y >= ground - 4 else "stone_wall"), true)
	var mid := w / 2
	for x in range(mid + 10, mid + 16):          # pit, 6 wide and 5 deep
		for y in range(ground - 5, ground):
			world.set_fg(x, y, TileDefs.AIR, true)
	for i in 3:                                   # platforms stepping up to the left
		for x in range(mid - 12 - i * 8, mid - 6 - i * 8):
			world.set_fg(x, ground + 3 + i * 3, wood, true)
	for x in range(mid - 8, mid + 4):             # cave pocket under the surface
		for y in range(ground - 14, ground - 9):
			world.set_fg(x, y, TileDefs.AIR, true)
	world.set_fg(mid - 2, ground - 14, TileDefs.id("torch"), true)
	return world
