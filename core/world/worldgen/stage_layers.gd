## Stage "layers": fills each column under its ground height. Bedrock floor (2-4 rows),
## slate below the deeps line, stone, a soil layer (biome soil) and the biome top tile.
## Background walls behind everything under the top tile. Some soil pockets in the
## upper stone.
extends RefCounted

const GenContext := preload("gen_context.gd")

static func run(c: GenContext, rng: RandomNumberGenerator) -> void:
	var nbed := c.noise(rng, 1.0 / 30.0)
	var nsoil := c.noise(rng, 1.0 / 60.0, 2)
	var nslate := c.noise(rng, 1.0 / 90.0, 2)
	var slate_line := int(c.bands["deeps"][1])
	var caves_top := int(c.bands["caves"][1])
	var caves_bot := int(c.bands["caves"][0])
	# Soil pockets in stone, from the caves band up.
	var blobs := c.noise(rng, 1.0 / 26.0, 2)
	var top_y := 0
	for x in c.w:
		top_y = maxi(top_y, c.ground[x])
	var pocket := GenContext.noise_bytes(blobs, 0, caves_bot, c.w, top_y - caves_bot + 1)

	var w := c.w
	var fg := c.fg
	var bg := c.bg
	for x in w:
		var s := c.ground[x]
		var d: Dictionary = c.biome_defs[c.col_biome[x]]
		var top := TileDefs.id(d["top"])
		var soil := TileDefs.id(d["soil"])
		var soil_wall := TileDefs.wall_id(d["soil_wall"])
		var bed := 2 + int((nbed.get_noise_1d(x) + 1.0) * 1.0)
		c.bed[x] = bed
		var soil_depth := 6 + int((nsoil.get_noise_1d(x) + 1.0) * 4.0)
		var sl := slate_line + int(nslate.get_noise_1d(x) * 10.0)
		var soil_top := s - soil_depth
		for y in range(0, bed):
			fg[x + y * w] = c.BEDROCK
			bg[x + y * w] = c.W_SLATE
		for y in range(bed, mini(sl, s)):
			fg[x + y * w] = c.SLATE
			bg[x + y * w] = c.W_SLATE
		for y in range(sl, soil_top + 1):
			fg[x + y * w] = c.STONE
			bg[x + y * w] = c.W_STONE
		for y in range(maxi(soil_top + 1, bed), s):
			fg[x + y * w] = soil
			bg[x + y * w] = soil_wall
		fg[x + s * w] = top
		# Soil pockets: more of them near the top of the caves band.
		for y in range(maxi(caves_bot, sl), mini(soil_top + 1, caves_top + 40)):
			var v := pocket[x + (y - caves_bot) * w]
			if v > 214 - (y - caves_bot) * 22 / maxi(1, caves_top - caves_bot):
				fg[x + y * w] = soil
				bg[x + y * w] = soil_wall
