## Stage "biomes": lays the surface biomes of data/worldgen/biomes.json along the climate.
## The width runs cold (x = 0) to hot; the world picks one of the climate orders and draws
## each biome's share of the width, so the order reads as a journey and worlds differ in
## their widths and in which order they take. No biome ends below min_share. Writes
## c.col_biome, c.biomes (meta strip), c.climate (meta), and c.seams (the borders, for the
## stages that blend across them). With one biome enabled the strip is a single segment.
extends RefCounted

const GenContext := preload("gen_context.gd")
const PATH := "res://data/worldgen/biomes.json"

static var _data := {}

static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _data

static func load_defs() -> Array:
	var out: Array = []
	for row: Dictionary in data()["biomes"]:
		if row.get("enabled", true):
			out.append(row)
	return out

## A number of tiles from {share, tiles: [lo, hi]}: a fraction of the width, clamped.
static func tiles_of(c: GenContext, key: String) -> int:
	var d: Dictionary = data()["climate"][key]
	return clampi(int(c.w * float(d["share"])), int(d["tiles"][0]), int(d["tiles"][1]))

static func run(c: GenContext, rng: RandomNumberGenerator) -> void:
	c.biome_defs = load_defs()
	var only: String = c.opts.get("only_biome", "")      # one biome across the width (scenario tests)
	if only != "":
		c.biome_defs = c.biome_defs.filter(func(d: Dictionary) -> bool: return d["name"] == only)
	var defs := c.biome_defs
	var climate: Dictionary = data()["climate"]
	var orders: Array = climate["orders"]
	var order: Dictionary = orders[rng.randi_range(0, orders.size() - 1)]
	var picked := order_indices(defs, order)
	var shares := draw_shares(defs, picked, float(climate["min_share"]), rng)
	c.climate = {"order": order["name"]}
	c.biomes = []
	c.seams = []
	var x0 := 0
	var used := 0.0
	for i in picked.size():
		used += float(shares[i])
		var x1 := c.w - 1 if i == picked.size() - 1 else roundi(used * c.w) - 1
		var name: String = defs[picked[i]]["name"]
		c.biomes.append({"x0": x0, "x1": x1, "biome": name, "temp": snappedf(temperature(c, (x0 + x1) / 2), 0.01)})
		for xx in range(x0, x1 + 1):
			c.col_biome[xx] = picked[i]
		if i > 0:
			c.seams.append({"x": x0, "a": picked[i - 1], "b": picked[i]})
		x0 = x1 + 1

## The enabled biomes in an order's sequence, as indices into defs. Biomes the order doesn't
## name (a row added before its orders are) go on at the hot end.
static func order_indices(defs: Array, order: Dictionary) -> Array:
	var out: Array = []
	for name: String in order["biomes"]:
		for i in defs.size():
			if defs[i]["name"] == name:
				out.append(i)
	for i in defs.size():
		if not i in out:
			out.append(i)
	return out

## Each picked biome's share of the width: drawn from its [lo, hi], normalised to sum to 1,
## and none below min_share (what a thin one gains comes off the wide ones in proportion).
static func draw_shares(defs: Array, picked: Array, min_share: float, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var total := 0.0
	for i: int in picked:
		var s: Array = defs[i]["share"]
		var v := rng.randf_range(float(s[0]), float(s[1]))
		out.append(v)
		total += v
	for i in out.size():
		out[i] = float(out[i]) / total
	var floor_at := minf(min_share, 1.0 / out.size())
	for _pass in out.size():
		var short := 0.0
		var spare := 0.0
		for v: float in out:
			short += maxf(0.0, floor_at - v)
			spare += maxf(0.0, v - floor_at)
		if short <= 0.0:
			break
		for i in out.size():
			var v: float = out[i]
			out[i] = floor_at if v <= floor_at else v - (v - floor_at) * short / spare
	return out

## The climate curve: 0 at the cold edge, 1 at the hot edge.
static func temperature(c: GenContext, x: int) -> float:
	return clampf(float(x) / maxf(1.0, c.w - 1), 0.0, 1.0)

static func biome_name(c: GenContext, x: int) -> String:
	return c.biome_defs[c.col_biome[clampi(x, 0, c.w - 1)]]["name"]
