## Scratch state for one WorldGen run. Tiles and walls live in flat u8 grids
## (index x + y * w, y up, (0, 0) bottom-left) because GDScript per-cell calls into
## TileWorld are slow; to_world() packs them into chunks at the end.
## Stages read and write the grids and leave notes (flats, caverns, road...) for later ones.
extends RefCounted

## Depth bands, bottom to top, with the fraction of the height where each one starts.
const BAND_CUTS := [["nadir", 0.0], ["deeps", 0.14], ["caves", 0.42], ["surface", 0.66], ["sky", 0.83]]
## Clear height of the deep road and ramps, in tiles.
const ROAD_H := 6
const RAMP_H := 5

var w: int
var h: int
var world_seed: int
var opts: Dictionary
var fg := PackedByteArray()        ## tile id per cell (ids < 256 during generation)
var bg := PackedByteArray()        ## wall id per cell
var ground := PackedInt32Array()   ## planned surface height per column (before carving)
var surface := PackedInt32Array()  ## highest solid tile per column (survey())
var bed := PackedInt32Array()      ## rows below this are bedrock, per column
var col_biome := PackedByteArray() ## index into biome_defs per column
var col_top := PackedByteArray()   ## top tile per column (layers), with seams and snow
var col_soil := PackedByteArray()  ## soil tile per column (layers), for patching the ground
var biome_defs: Array = []
var biomes: Array = []             ## meta strip [{x0, x1, biome, temp}]
var climate := {}                  ## meta: {order}
var seams: Array = []              ## biome borders [{x, a, b}], a and b index biome_defs
var bands := {}                    ## name -> [y0, y1], inclusive
var flats: Array = []              ## planned settlement ground [{x0, x1, y}]
var caverns: Array = []            ## [{x, cy, rx, ry, floor, settled}]
var road_x0 := -1                  ## deep road: floor (first open row) per column x0..x1
var road_x1 := -1
var road_floor := PackedInt32Array()
var ascent := {}                   ## {cavern, x0, y0, x1, y1, steps, path: [Vector2i] feet cells}
var portal := {}                   ## {cavern, x, y, w, steps, x0, path: [Vector2i] feet cells}
var buried_rooms: Array = []       ## [{x, y, w}]
var sites: Array = []
var routes: Array = []
var objects := PackedInt32Array()  ## dressing records, flat (id, x, y, variant)
var places := {}                   ## meta.places: site id (String) -> place (PlaceBuilder)

var AIR := 0
var BEDROCK: int
var STONE: int
var SLATE: int
var DIRT: int
var GRASS: int
var COBBLE: int
var W_STONE: int
var W_SLATE: int
var W_COBBLE: int
var solid: PackedByteArray

func _init(width: int, height: int, seed_value: int, options: Dictionary) -> void:
	TileDefs.ensure()
	w = width
	h = height
	world_seed = seed_value
	opts = options
	fg.resize(w * h)
	bg.resize(w * h)
	ground.resize(w)
	surface.resize(w)
	bed.resize(w)
	col_biome.resize(w)
	BEDROCK = TileDefs.id("bedrock")
	STONE = TileDefs.id("stone")
	SLATE = TileDefs.id("slate")
	DIRT = TileDefs.id("dirt")
	GRASS = TileDefs.id("grass")
	COBBLE = TileDefs.id("cobblestone")
	W_STONE = TileDefs.wall_id("stone_wall")
	W_SLATE = TileDefs.wall_id("slate_wall")
	W_COBBLE = TileDefs.wall_id("cobble_wall")
	solid = TileDefs.solid
	var cuts: Array = []
	for b: Array in BAND_CUTS:
		cuts.append(int(h * float(b[1])))
	cuts.append(h)
	for i in range(BAND_CUTS.size() - 1, -1, -1):  # top first, for readable JSON
		bands[BAND_CUTS[i][0]] = [cuts[i], cuts[i + 1] - 1]

func band_at(y: int) -> String:
	for name: String in bands:
		var b: Array = bands[name]
		if y >= b[0] and y <= b[1]:
			return name
	return "nadir"

func band_h(name: String) -> int:
	return bands[name][1] - bands[name][0] + 1

## Scale factor against the dev world (2048x1024), for counts and sizes.
func sx() -> float:
	return w / 2048.0

func sy() -> float:
	return h / 1024.0

func noise(rng: RandomNumberGenerator, freq: float, octaves := 1,
		type := FastNoiseLite.TYPE_SIMPLEX_SMOOTH) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = rng.randi() & 0x7fffffff
	n.noise_type = type
	n.frequency = freq
	if octaves > 1:
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = octaves
	else:
		n.fractal_type = FastNoiseLite.FRACTAL_NONE
	return n

## Noise sampled over a gw x gh window starting at (x0, y0), one byte per cell,
## 128 = 0.0, row-major. Sampled in C++ through get_image, so it is cheap.
static func noise_bytes(n: FastNoiseLite, x0: int, y0: int, gw: int, gh: int) -> PackedByteArray:
	n.offset = Vector3(x0, y0, 0)
	return n.get_image(gw, gh, false, false, false).get_data()

func is_solid(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= w or y >= h:
		return true
	return solid[fg[x + y * w]] != 0

func set_tile(x: int, y: int, id: int) -> void:
	if x >= 0 and y >= 0 and x < w and y < h:
		fg[x + y * w] = id

## Air in a disc, never through bedrock or the bottom row.
func carve_disc(cx: int, cy: int, r: float) -> void:
	var ri := int(ceil(r))
	for dy in range(-ri, ri + 1):
		var y := cy + dy
		if y < 1 or y >= h:
			continue
		var half := int(sqrt(maxf(0.0, r * r - dy * dy)) + 0.35)
		var row := y * w
		for x in range(maxi(0, cx - half), mini(w - 1, cx + half) + 1):
			if fg[row + x] != BEDROCK:
				fg[row + x] = AIR

## Air in an inclusive rectangle, never through bedrock or the bottom row.
func carve_rect(x0: int, y0: int, x1: int, y1: int) -> void:
	for y in range(maxi(1, y0), mini(h - 1, y1) + 1):
		var row := y * w
		for x in range(maxi(0, x0), mini(w - 1, x1) + 1):
			if fg[row + x] != BEDROCK:
				fg[row + x] = AIR

func fill_rect(x0: int, y0: int, x1: int, y1: int, id: int, only_air := false) -> void:
	for y in range(maxi(0, y0), mini(h - 1, y1) + 1):
		var row := y * w
		for x in range(maxi(0, x0), mini(w - 1, x1) + 1):
			if not only_air or fg[row + x] == AIR:
				fg[row + x] = id

func wall_rect(x0: int, y0: int, x1: int, y1: int, id: int) -> void:
	for y in range(maxi(0, y0), mini(h - 1, y1) + 1):
		var row := y * w
		for x in range(maxi(0, x0), mini(w - 1, x1) + 1):
			bg[row + x] = id

## One column of a road or ramp: open rows y..y+tall-1, paving at y-1, built wall behind.
## bridge: pave over open air too (the level deep road); ramps only pave over rock, so a
## sloped pavement never walls off a cavern it crosses.
func carve_road_column(x: int, y: int, tall: int, bridge := true) -> void:
	if x < 0 or x >= w:
		return
	carve_rect(x, y, x, y + tall - 1)
	wall_rect(x, y, x, y + tall - 1, W_COBBLE)
	if y - 1 >= 1:
		var i := x + (y - 1) * w
		if fg[i] != BEDROCK and (bridge or fg[i] != AIR):
			fg[i] = COBBLE

## Highest solid tile per column into `surface`.
func survey() -> void:
	for x in w:
		var y := h - 1
		while y > 0 and solid[fg[x + y * w]] == 0:
			y -= 1
		surface[x] = y

## First open cell at or below (x, y) that has solid ground under it; -1 if none.
func drop_to_floor(x: int, y: int, limit := 64) -> int:
	var yy := y
	if is_solid(x, yy):
		return -1  # started inside rock
	for i in limit:
		if yy <= 0:
			return -1
		if is_solid(x, yy - 1) and not is_solid(x, yy):
			return yy
		yy -= 1
	return -1

## Count of open cells in the inclusive box.
func open_count(x0: int, y0: int, x1: int, y1: int) -> int:
	var n := 0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if not is_solid(x, y):
				n += 1
	return n

func to_world() -> TileWorld:
	var world := TileWorld.new(w, h, world_seed)
	# u8 grid -> u16 little-endian: R8 to RG8 conversion leaves G (the high byte) at 0.
	var fimg := Image.create_from_data(w, h, false, Image.FORMAT_R8, fg)
	fimg.convert(Image.FORMAT_RG8)
	var bimg := Image.create_from_data(w, h, false, Image.FORMAT_R8, bg)
	for cy in world.chunks_y:
		for cx in world.chunks_x:
			var r := Rect2i(cx * K.CHUNK, cy * K.CHUNK, K.CHUNK, K.CHUNK)
			var c := world.chunk_at(cx, cy)
			c.fg = fimg.get_region(r).get_data()
			c.bg = bimg.get_region(r).get_data()
	for i in range(0, objects.size(), 4):
		var ox := objects[i + 1]
		var oy := objects[i + 2]
		world.chunk_at(ox >> 5, oy >> 5).add_object(objects[i], ox & 31, oy & 31, objects[i + 3])
	world.meta = {
		"surface": Array(surface),
		"biomes": biomes.duplicate(true),
		"climate": climate.duplicate(true),
		"bands": bands.duplicate(true),
		"sites": sites.duplicate(true),
		"routes": routes.duplicate(true),
		"places": places.duplicate(true),
	}
	return world
