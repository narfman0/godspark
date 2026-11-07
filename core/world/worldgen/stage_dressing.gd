## Stage "dressing": tile-anchored decoration records (data/dressing.json, ids from its
## append-only `ids` list). Surface: a pass along every column's top, weighted picks among
## the objects allowed for the column's biome and top tile, footprints that fit (level
## support, open cells), at the biome's own density; settlement grounds only get footprint-1
## objects (grass, flowers). A second pass lays understory (where.pass "under") on footprints
## of its own, so ferns grow among the trunks. Caves: random sample points in the cave, deep and
## nadir bands drop to a floor and place cave objects there. Before any of that, pools of water
## in the biomes that have them (`ponds` in the data): the only tiles this stage changes. It runs
## last, so no other stage's RNG changes, and a pool only lowers level open ground off roads
## and out of places, by steps a body walks.
extends RefCounted

const GenContext := preload("gen_context.gd")
const StageBiomes := preload("stage_biomes.gd")

## Chance per surface column to try an object, in a biome the data does not name.
const SURFACE_DENSITY := 0.45
## One cave sample point per this many tiles of the underground bands.
const CAVE_SAMPLE := 700
## Chance a sampled cave floor gets an object.
const CAVE_DENSITY := 0.35

static func run(c: GenContext, rng: RandomNumberGenerator) -> void:
	Dressing.ensure()
	var taken := {}
	var surface: Array = []
	var under: Array = []
	var cave: Array = []
	for i in Dressing.count():
		var d := Dressing.def(i)
		var where: Dictionary = d.get("where", {})
		if Dressing.is_ceiling(i):
			continue        # nothing hangs yet
		if String(where.get("band", "surface")) == "place":
			continue        # building pieces: placed by the places stage only
		if String(where.get("band", "surface")) == "cave":
			cave.append(i)
		elif String(where.get("pass", "")) == "under":
			under.append(i)
		else:
			surface.append(i)
	var settled := _settled(c)
	_ponds(c, rng, settled)
	var density: Dictionary = Dressing.table("density")
	_surface(c, rng, surface, taken, settled, density)
	_surface(c, rng, under, {}, settled, density.get("under", {}))
	_caves(c, rng, cave, taken)

## [x0, x1] of every settlement's grounds.
static func _settled(c: GenContext) -> Array:
	var settled: Array = []
	for s: Dictionary in c.sites:
		if s.get("kind") == "settlement" and s.get("band") in ["surface", "sky"]:
			var half := int(s.get("size", 40)) / 2 + 4
			var p: Dictionary = c.places.get(str(s["id"]), {})
			if p.is_empty():
				settled.append(Vector2i(int(s["x"]) - half, int(s["x"]) + half))
			else:   # a laid-out place: its street and a margin
				settled.append(Vector2i(int(p["street"][0]) - 4, int(p["street"][1]) + 4))
	return settled

static func _in(settled: Array, x: int) -> bool:
	for r: Vector2i in settled:
		if x >= r.x and x <= r.y:
			return true
	return false

## Pools: a run of level columns with the biome's top tile, nothing reserved, nothing built, rock
## under it, is lowered and filled with water. One row at the rim, `depth` in the middle.
static func _ponds(c: GenContext, rng: RandomNumberGenerator, settled: Array) -> void:
	var d: Dictionary = Dressing.table("ponds")
	if d.is_empty():
		return
	var on := TileDefs.id(String(d.get("on", "")))
	var water := TileDefs.id("water")
	var wr: Array = d.get("width", [5, 12])
	var deep := int(d.get("depth", 2))
	var biomes: Array = d.get("biomes", [])
	var x := 8
	while x < c.w - 40:
		var step := int(d.get("every", 60))
		var w := rng.randi_range(int(wr[0]), int(wr[1]))
		var at := x + rng.randi_range(0, step / 2)
		x += step
		if at + w + 2 >= c.w or not StageBiomes.biome_name(c, at) in biomes or _in(settled, at) or _in(settled, at + w):
			continue
		if _pool_fits(c, at - 1, w + 2, deep, on):
			for dx in w:
				var cx := at + dx
				var rows := 1 if dx == 0 or dx == w - 1 else deep
				var top := c.surface[cx]
				for k in rows:
					c.fg[cx + (top - k) * c.w] = water
				c.surface[cx] = top - rows

## Every column of the run stands level on the pool's tile, with open air over it, and three
## rows of solid under the deepest water, so no pool opens onto a cave.
static func _pool_fits(c: GenContext, x: int, w: int, deep: int, on: int) -> bool:
	var y := c.surface[x]
	for cx in range(x, x + w):
		if c.surface[cx] != y or c.fg[cx + y * c.w] != on or c.fg[cx + (y + 1) * c.w] != c.AIR:
			return false
		if c.reserved.size() > cx and c.reserved[cx] != 0:
			return false
		for k in range(1, deep + 4):
			if c.solid[c.fg[cx + (y - k) * c.w]] == 0:
				return false
	return true

static func _surface(c: GenContext, rng: RandomNumberGenerator, ids: Array, taken: Dictionary, settled: Array,
		density: Dictionary) -> void:
	if ids.is_empty():
		return
	var x := 0
	while x < c.w:
		var top := c.surface[x]
		var fy := top + 1
		var biome := StageBiomes.biome_name(c, x)
		if top < 1 or fy >= c.h - 1 or rng.randf() > float(density.get(biome, SURFACE_DENSITY)):
			x += 1
			continue
		var under := TileDefs.names[c.fg[x + top * c.w]]
		var pick := _pick(c, rng, ids, x, fy, under, biome, _in(settled, x), taken)
		if pick < 0:
			x += 1
			continue
		_add(c, rng, pick, x, fy, taken)
		x += maxi(Dressing.footprint(pick).x, int(Dressing.def(pick).get("gap", 0)))

static func _caves(c: GenContext, rng: RandomNumberGenerator, ids: Array, taken: Dictionary) -> void:
	if ids.is_empty():
		return
	var y0 := int(c.bands.get("nadir", [0, 0])[0]) + 2
	var y1 := int(c.bands.get("caves", [0, c.h / 2])[1])
	var n := c.w * (y1 - y0) / CAVE_SAMPLE
	for k in n:
		var x := rng.randi_range(1, c.w - 8)
		var y := rng.randi_range(y0, y1)
		var roll := rng.randf()
		var v := rng.randi()
		if c.solid[c.fg[x + y * c.w]] != 0 or roll > CAVE_DENSITY:
			continue
		var fy := c.drop_to_floor(x, y, 40)
		if fy < 2 or fy >= c.surface[x] - 4:
			continue
		var under := TileDefs.names[c.fg[x + (fy - 1) * c.w]]
		var pick := _pick(c, rng, ids, x, fy, under, "", false, taken)
		if pick >= 0:
			_add(c, rng, pick, x, fy, taken, v)

## A weighted pick among ids that may stand at (x, fy) on `under`, or -1.
static func _pick(c: GenContext, rng: RandomNumberGenerator, ids: Array, x: int, fy: int, under: String,
		biome: String, in_town: bool, taken: Dictionary) -> int:
	var cands: Array = []
	var total := 0.0
	for i: int in ids:
		var d := Dressing.def(i)
		var where: Dictionary = d.get("where", {})
		var bl: Array = where.get("biomes", [])
		if biome != "" and not bl.is_empty() and not biome in bl:
			continue
		var on: Array = where.get("on", [])
		if not on.is_empty() and not under in on:
			continue
		var fp := Dressing.footprint(i)
		if in_town and fp.x * fp.y > 1:
			continue
		if not _fits(c, fp, x, fy, taken, bool(where.get("wet", false))):
			continue
		cands.append(i)
		total += float(d.get("weight", 1))
	if cands.is_empty():
		return -1
	var r := rng.randf() * total
	for i: int in cands:
		r -= float(Dressing.def(i).get("weight", 1))
		if r <= 0.0:
			return i
	return cands[-1]

## Level solid support under every footprint column and open, untaken footprint cells. A wet
## object (reeds) may stand in water.
static func _fits(c: GenContext, fp: Vector2i, x: int, y: int, taken: Dictionary, wet := false) -> bool:
	var water := TileDefs.id("water") if wet else -1
	if x < 0 or x + fp.x > c.w or y < 1 or y + fp.y > c.h:
		return false
	for dx in fp.x:
		if c.solid[c.fg[x + dx + (y - 1) * c.w]] == 0:
			return false
		for dy in fp.y:
			var i := x + dx + (y + dy) * c.w
			if (c.fg[i] != c.AIR and c.fg[i] != water) or taken.has(i):
				return false
	return true

static func _add(c: GenContext, rng: RandomNumberGenerator, id: int, x: int, y: int, taken: Dictionary, v := -1) -> void:
	var fp := Dressing.footprint(id)
	for dx in fp.x:
		for dy in fp.y:
			taken[x + dx + (y + dy) * c.w] = true
	c.objects.append_array(PackedInt32Array([id, x, y, (rng.randi() if v < 0 else v) & 0xff]))
