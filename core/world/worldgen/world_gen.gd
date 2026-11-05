## Deterministic world generator: named stages run in order over one GenContext. Each
## stage gets an RNG derived from (seed, stage name), so adding a stage never reshuffles
## the others. Noise is FastNoiseLite with seeds drawn from that RNG.
##
##   var world := WorldGen.generate(2048, 1024, 42)
##   var world := WorldGen.generate_named("dev", 42)
##   WorldGen.last_timings   # {stage: msec} of the last run
##
## opts: {"stop_after": "<stage name>"} stops early (debugging); meta is still filled.
class_name WorldGen
extends RefCounted

const GenContext := preload("gen_context.gd")
const Biomes := preload("stage_biomes.gd")
const Surface := preload("stage_surface.gd")
const Layers := preload("stage_layers.gd")
const Caves := preload("stage_caves.gd")
const Deeps := preload("stage_deeps.gd")
const Ores := preload("stage_ores.gd")
const Sites := preload("stage_sites.gd")
const DressingStage := preload("stage_dressing.gd")

## [name, script, static method]. Append new stages where they belong; names are the RNG
## keys, so renaming a stage changes every world.
const STAGES := [
	["biomes", Biomes, "run"],
	["surface", Surface, "run"],
	["layers", Layers, "run"],
	["caves", Caves, "run"],
	["caverns", Deeps, "caverns"],
	["deep_road", Deeps, "deep_road"],
	["ascent", Deeps, "ascent"],
	["portal", Deeps, "portal"],
	["ruins", Sites, "ruins"],
	["ores", Ores, "run"],
	["finish", Sites, "finish"],
	["sites", Sites, "sites"],
	["routes", Sites, "routes"],
	["dressing", DressingStage, "run"],
]

const SIZES := {
	"dev": Vector2i(2048, 1024),
	"small": Vector2i(4096, 1536),
	"medium": Vector2i(8192, 2560),
	"large": Vector2i(16384, 4096),
}

static var last_timings := {}

static func generate(width: int, height: int, world_seed: int, opts := {}) -> TileWorld:
	var c := GenContext.new(width, height, world_seed, opts)
	last_timings = {}
	var stop: String = opts.get("stop_after", "")
	var total := Time.get_ticks_usec()
	for st: Array in STAGES:
		var t0 := Time.get_ticks_usec()
		(st[1] as Script).call(st[2], c, rng_for(world_seed, st[0]))
		last_timings[st[0]] = (Time.get_ticks_usec() - t0) / 1000
		if st[0] == stop:
			break
	if stop != "" and stop != "routes" and stop != "dressing":
		c.survey()
	var t1 := Time.get_ticks_usec()
	var world := c.to_world()
	last_timings["pack"] = (Time.get_ticks_usec() - t1) / 1000
	last_timings["total"] = (Time.get_ticks_usec() - total) / 1000
	return world

static func generate_named(size_name: String, world_seed: int, opts := {}) -> TileWorld:
	var s: Vector2i = SIZES[size_name]
	return generate(s.x, s.y, world_seed, opts)

static func rng_for(world_seed: int, stage: String) -> RandomNumberGenerator:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(("godspark/%d/%s" % [world_seed, stage]).to_utf8_buffer())
	var rng := RandomNumberGenerator.new()
	rng.seed = ctx.finish().decode_s64(0)
	return rng

## The world's tile and wall ids as u8 grids (index x + y * width), e.g. for maps.
## Ids above 255 wrap; worldgen only makes ids below 64.
static func grids(world: TileWorld) -> Array:
	var fimg := Image.create_empty(world.width, world.height, false, Image.FORMAT_RG8)
	var bimg := Image.create_empty(world.width, world.height, false, Image.FORMAT_R8)
	var r := Rect2i(0, 0, K.CHUNK, K.CHUNK)
	for cy in world.chunks_y:
		for cx in world.chunks_x:
			var c := world.chunk_at(cx, cy)
			var at := Vector2i(cx * K.CHUNK, cy * K.CHUNK)
			fimg.blit_rect(Image.create_from_data(K.CHUNK, K.CHUNK, false, Image.FORMAT_RG8, c.fg), r, at)
			bimg.blit_rect(Image.create_from_data(K.CHUNK, K.CHUNK, false, Image.FORMAT_R8, c.bg), r, at)
	fimg.convert(Image.FORMAT_R8)
	return [fimg.get_data(), bimg.get_data()]
