## Stage "biomes": splits the width into a strip of surface biomes from
## data/worldgen/biomes.json (weighted picks, widths in [min_width, max_width], equal
## neighbours merged). With one biome defined the strip is a single segment.
extends RefCounted

const GenContext := preload("gen_context.gd")
const PATH := "res://data/worldgen/biomes.json"

static func load_defs() -> Array:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	var out: Array = []
	for row: Dictionary in data["biomes"]:
		if row.get("enabled", true):
			out.append(row)
	return out

static func run(c: GenContext, rng: RandomNumberGenerator) -> void:
	c.biome_defs = load_defs()
	var defs := c.biome_defs
	var total := 0.0
	for d: Dictionary in defs:
		total += float(d["weight"])
	var segs: Array = []  # [x0, x1, def index]
	var x := 0
	var prev := -1
	while x < c.w:
		var pick := _pick(defs, total, prev, rng)
		var d: Dictionary = defs[pick]
		var x1 := mini(c.w - 1, x + rng.randi_range(int(d["min_width"]), int(d["max_width"])) - 1)
		if c.w - 1 - x1 < int(d["min_width"]) / 2:
			x1 = c.w - 1  # don't leave a sliver at the edge
		if not segs.is_empty() and segs[-1][2] == pick:
			segs[-1][1] = x1
		else:
			segs.append([x, x1, pick])
		prev = pick
		x = x1 + 1
	c.biomes = []
	for s: Array in segs:
		c.biomes.append({"x0": s[0], "x1": s[1], "biome": defs[s[2]]["name"]})
		for xx in range(s[0], s[1] + 1):
			c.col_biome[xx] = s[2]

static func _pick(defs: Array, total: float, prev: int, rng: RandomNumberGenerator) -> int:
	if defs.size() == 1:
		return 0
	for _try in 8:
		var r := rng.randf() * total
		for i in defs.size():
			r -= float(defs[i]["weight"])
			if r <= 0.0:
				if i != prev:
					return i
				break
	return (prev + 1) % defs.size()

static func biome_name(c: GenContext, x: int) -> String:
	return c.biome_defs[c.col_biome[clampi(x, 0, c.w - 1)]]["name"]
