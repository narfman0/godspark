## Stage "layers": fills each column under its ground height. Bedrock floor (2-4 rows),
## slate below the deeps line, stone, the biome's stone from just under the surface band up, a soil
## layer (biome soil) and the biome top tile. Background walls behind everything under the top
## tile. Some soil pockets in the upper stone. Across a biome border the skin dithers and the
## rock interleaves in fingers, so a seam is never a vertical line. Writes c.col_top and
## c.col_soil, the tiles later stages use to patch the ground.
extends RefCounted

const GenContext := preload("gen_context.gd")
const StageBiomes := preload("stage_biomes.gd")

static func run(c: GenContext, rng: RandomNumberGenerator) -> void:
	var nbed := c.noise(rng, 1.0 / 30.0)
	var nsoil := c.noise(rng, 1.0 / 60.0, 2)
	var nslate := c.noise(rng, 1.0 / 90.0, 2)
	var nfloor := c.noise(rng, 1.0 / 70.0, 2)
	var nsnow := c.noise(rng, 1.0 / 40.0, 2)
	var nskin := c.noise(rng, 1.0 / 14.0, 2)
	var nfinger := c.noise(rng, 1.0 / 16.0, 2)
	var slate_line := int(c.bands["deeps"][1])
	var caves_top := int(c.bands["caves"][1])
	var caves_bot := int(c.bands["caves"][0])
	var sb: Array = c.bands["surface"]
	var band := float(int(sb[1]) - int(sb[0]))
	var rock_base := int(sb[0]) - int(band * 0.25)    # biome stone reaches a little under the surface band
	# Soil pockets in stone, from the caves band up.
	var blobs := c.noise(rng, 1.0 / 26.0, 2)
	var top_y := 0
	for x in c.w:
		top_y = maxi(top_y, c.ground[x])
	var pocket := GenContext.noise_bytes(blobs, 0, caves_bot, c.w, top_y - caves_bot + 1)

	var defs: Array = []
	for d: Dictionary in c.biome_defs:
		var depth: Array = d["soil_depth"]
		var snow: Dictionary = d.get("snow", {})
		defs.append({"top": TileDefs.id(d["top"]), "soil": TileDefs.id(d["soil"]), "stone": TileDefs.id(d["stone"]),
			"soil_wall": TileDefs.wall_id(d["soil_wall"]), "stone_wall": TileDefs.wall_id(d["stone_wall"]),
			"soil_lo": int(depth[0]), "soil_range": int(depth[1]) - int(depth[0]),
			"snow": TileDefs.id(snow["tile"]) if not snow.is_empty() else -1,
			"snow_y": int(sb[0]) + band * float(snow.get("above", 1.0))})
	var skin := _skins(c, rng, nskin)
	var seam := StageBiomes.tiles_of(c, "seam")
	# Finger noise around each border: one byte per cell of a window over the seam.
	var fingers: Array = []
	var fy0 := rock_base - 28
	var fh := top_y - fy0 + 1
	for s: Dictionary in c.seams:
		fingers.append(GenContext.noise_bytes(nfinger, int(s["x"]) - 2 * seam, fy0, 4 * seam, fh))
	var seam_at := PackedInt32Array()     # per column: index of the border it lies on, or -1
	seam_at.resize(c.w)
	seam_at.fill(-1)
	for i in c.seams.size():
		var sx := int(c.seams[i]["x"])
		for x in range(maxi(0, sx - 2 * seam), mini(c.w, sx + 2 * seam)):
			seam_at[x] = i

	c.col_top.resize(c.w)
	c.col_soil.resize(c.w)
	var w := c.w
	var fg := c.fg
	var bg := c.bg
	var stone := c.STONE
	var slate := c.SLATE
	var w_stone := c.W_STONE
	var w_slate := c.W_SLATE
	for x in w:
		var s := c.ground[x]
		var d: Dictionary = defs[skin[x]]
		var top: int = d["top"]
		if int(d["snow"]) >= 0 and s + nsnow.get_noise_1d(x) * band * 0.08 > float(d["snow_y"]):
			top = d["snow"]
		var soil: int = d["soil"]
		var soil_wall: int = d["soil_wall"]
		c.col_top[x] = top
		c.col_soil[x] = soil
		var bed := 2 + int((nbed.get_noise_1d(x) + 1.0) * 1.0)
		c.bed[x] = bed
		var soil_depth := int(d["soil_lo"]) + int((nsoil.get_noise_1d(x) + 1.0) * 0.5 * int(d["soil_range"]))
		var sl := slate_line + int(nslate.get_noise_1d(x) * 10.0)
		var soil_top := s - soil_depth
		var rock_floor := rock_base + int(nfloor.get_noise_1d(x) * 24.0)
		for y in range(0, bed):
			fg[x + y * w] = c.BEDROCK
			bg[x + y * w] = w_slate
		for y in range(bed, mini(sl, s)):
			fg[x + y * w] = slate
			bg[x + y * w] = w_slate
		for y in range(sl, mini(rock_floor, soil_top + 1)):
			fg[x + y * w] = stone
			bg[x + y * w] = w_stone
		var si := seam_at[x]
		if si < 0:
			var rock: int = d["stone"]
			var rock_wall: int = d["stone_wall"]
			for y in range(maxi(sl, rock_floor), soil_top + 1):
				fg[x + y * w] = rock
				bg[x + y * w] = rock_wall
			for y in range(maxi(soil_top + 1, bed), s):
				fg[x + y * w] = soil
				bg[x + y * w] = soil_wall
		else:
			# Near a border each cell asks which side of a wandering line it is on.
			var sm: Dictionary = c.seams[si]
			var a: Dictionary = defs[sm["a"]]
			var b: Dictionary = defs[sm["b"]]
			var sx := int(sm["x"])
			var cells: PackedByteArray = fingers[si]
			var col := x - (sx - 2 * seam)
			for y in range(maxi(sl, rock_floor), s):
				var off := (int(cells[col + (y - fy0) * 4 * seam]) - 128) * 2 * seam / 90
				var e: Dictionary = b if x + off >= sx else a
				var is_soil := y > soil_top
				fg[x + y * w] = e["soil"] if is_soil else e["stone"]
				bg[x + y * w] = e["soil_wall"] if is_soil else e["stone_wall"]
		fg[x + s * w] = top
		# Soil pockets: more of them near the top of the caves band.
		for y in range(maxi(caves_bot, sl), mini(soil_top + 1, caves_top + 40)):
			var v := pocket[x + (y - caves_bot) * w]
			if v > 214 - (y - caves_bot) * 22 / maxi(1, caves_top - caves_bot):
				fg[x + y * w] = soil
				bg[x + y * w] = soil_wall

## Per column, the biome (index into biome_defs) whose skin it wears: its own, or across a
## border a dither that leans from one to the other in patches.
static func _skins(c: GenContext, rng: RandomNumberGenerator, n: FastNoiseLite) -> PackedByteArray:
	var out := c.col_biome.duplicate()
	var seam := StageBiomes.tiles_of(c, "seam")
	for s: Dictionary in c.seams:
		var sx := int(s["x"])
		for x in range(maxi(0, sx - seam), mini(c.w, sx + seam)):
			var t := (x - sx + seam) / (2.0 * seam)            # 0 all a, 1 all b
			var roll := t + n.get_noise_1d(x) * 0.7 + rng.randf_range(-0.2, 0.2)
			out[x] = s["b"] if roll >= 0.5 else s["a"]
	return out
