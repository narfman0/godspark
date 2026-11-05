## Stage "dressing": tile-anchored decoration records (data/dressing.json, ids from its
## append-only `ids` list). Surface: a pass along every column's top, weighted picks among
## the objects allowed for the column's biome and top tile, footprints that fit (level
## support, open cells); settlement grounds only get footprint-1 objects (grass, flowers).
## Caves: random sample points in the cave, deep and nadir bands drop to a floor and place
## cave objects there. Runs last, so no other stage's RNG or tiles change.
extends RefCounted

const GenContext := preload("gen_context.gd")
const StageBiomes := preload("stage_biomes.gd")

## Chance per surface column to try an object.
const SURFACE_DENSITY := 0.45
## One cave sample point per this many tiles of the underground bands.
const CAVE_SAMPLE := 700
## Chance a sampled cave floor gets an object.
const CAVE_DENSITY := 0.35

static func run(c: GenContext, rng: RandomNumberGenerator) -> void:
	Dressing.ensure()
	c.objects = PackedInt32Array()
	var taken := {}
	var surface: Array = []
	var cave: Array = []
	for i in Dressing.count():
		var d := Dressing.def(i)
		var where: Dictionary = d.get("where", {})
		if Dressing.is_ceiling(i):
			continue        # nothing hangs yet
		if String(where.get("band", "surface")) == "cave":
			cave.append(i)
		else:
			surface.append(i)
	_surface(c, rng, surface, taken)
	_caves(c, rng, cave, taken)

static func _surface(c: GenContext, rng: RandomNumberGenerator, ids: Array, taken: Dictionary) -> void:
	var settled: Array = []   # [x0, x1] of settlement grounds
	for s: Dictionary in c.sites:
		if s.get("kind") == "settlement" and s.get("band") in ["surface", "sky"]:
			var half := int(s.get("size", 40)) / 2 + 4
			settled.append(Vector2i(int(s["x"]) - half, int(s["x"]) + half))
	var x := 0
	while x < c.w:
		var top := c.surface[x]
		var fy := top + 1
		if top < 1 or fy >= c.h - 1 or rng.randf() > SURFACE_DENSITY:
			x += 1
			continue
		var under := TileDefs.names[c.fg[x + top * c.w]]
		var biome := StageBiomes.biome_name(c, x)
		var in_town := false
		for r: Vector2i in settled:
			if x >= r.x and x <= r.y:
				in_town = true
		var pick := _pick(c, rng, ids, x, fy, under, biome, in_town, taken)
		if pick < 0:
			x += 1
			continue
		_add(c, rng, pick, x, fy, taken)
		x += Dressing.footprint(pick).x

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
		if not _fits(c, fp, x, fy, taken):
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

## Level solid support under every footprint column and open, untaken footprint cells.
static func _fits(c: GenContext, fp: Vector2i, x: int, y: int, taken: Dictionary) -> bool:
	if x < 0 or x + fp.x > c.w or y < 1 or y + fp.y > c.h:
		return false
	for dx in fp.x:
		if c.solid[c.fg[x + dx + (y - 1) * c.w]] == 0:
			return false
		for dy in fp.y:
			var i := x + dx + (y + dy) * c.w
			if c.fg[i] != c.AIR or taken.has(i):
				return false
	return true

static func _add(c: GenContext, rng: RandomNumberGenerator, id: int, x: int, y: int, taken: Dictionary, v := -1) -> void:
	var fp := Dressing.footprint(id)
	for dx in fp.x:
		for dy in fp.y:
			taken[x + dx + (y + dy) * c.w] = true
	c.objects.append_array(PackedInt32Array([id, x, y, (rng.randi() if v < 0 else v) & 0xff]))
