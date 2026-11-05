## Stage "surface": the heightmap. Rolling hills from layered noise, scaled per biome,
## with flat stretches planned for settlements (c.flats) blended into the hills.
extends RefCounted

const GenContext := preload("gen_context.gd")

static func run(c: GenContext, rng: RandomNumberGenerator) -> void:
	var sb: Array = c.bands["surface"]
	var base := c.h * 0.735
	var big := c.noise(rng, 1.0 / 520.0, 3)
	var mid := c.noise(rng, 1.0 / 110.0, 2)
	var fine := c.noise(rng, 1.0 / 22.0, 1)
	var amp_big := minf(c.h * 0.05, 80.0)
	var amp_mid := 2.0 + minf(c.h * 0.012, 18.0)
	var amp_fine := 1.3
	# Per-column hill factor from the biome, box-smoothed so biome edges don't step.
	var hill := PackedFloat32Array()
	hill.resize(c.w)
	for x in c.w:
		hill[x] = float(c.biome_defs[c.col_biome[x]].get("hill", 1.0))
	hill = _smooth(hill, 32)
	# Mountains: ridged peaks where a slow mask noise is high.
	var mask := c.noise(rng, 1.0 / 700.0)
	var peaks := c.noise(rng, 1.0 / 240.0, 2)
	var amp_peak := minf(c.h * 0.06, 70.0)
	var raw := PackedFloat32Array()
	raw.resize(c.w)
	for x in c.w:
		var m := clampf((mask.get_noise_1d(x) - 0.1) * 3.0, 0.0, 1.0)
		var peak := smoothstep(0.0, 1.0, clampf(peaks.get_noise_1d(x) * 1.5 + 0.5, 0.0, 1.0))
		raw[x] = base + hill[x] * (big.get_noise_1d(x) * 2.0 * amp_big + mid.get_noise_1d(x) * 1.8 * amp_mid
				+ m * peak * amp_peak) + fine.get_noise_1d(x) * amp_fine

	# Flat stretches, one per slot across the width.
	var n := maxi(2, c.w / 340)
	var slot := c.w / n
	var blend := 28.0
	c.flats = []
	for i in n:
		var fw := mini(rng.randi_range(48, 80), slot / 2)
		var centre := slot * i + slot / 2 + rng.randi_range(-slot / 5, slot / 5)
		centre = clampi(centre, fw + 8, c.w - fw - 8)
		var x0 := centre - fw / 2
		var x1 := x0 + fw - 1
		var level := 0.0
		for x in range(x0, x1 + 1):
			level += raw[x]
		level = roundf(level / fw)
		for x in range(maxi(0, x0 - int(blend)), mini(c.w - 1, x1 + int(blend)) + 1):
			var d := maxf(x0 - x, x - x1)
			if d <= 0:
				raw[x] = level
			else:
				raw[x] = lerpf(level, raw[x], smoothstep(0.0, 1.0, d / blend))
		c.flats.append({"x0": x0, "x1": x1, "y": int(level)})

	for x in c.w:
		c.ground[x] = clampi(roundi(raw[x]), sb[0] + 4, sb[1] - 4)
	# No cliffs taller than 3 tiles between neighbours (keeps the surface walkable).
	for x in range(1, c.w):
		c.ground[x] = clampi(c.ground[x], c.ground[x - 1] - 3, c.ground[x - 1] + 3)
	for x in range(c.w - 2, -1, -1):
		c.ground[x] = clampi(c.ground[x], c.ground[x + 1] - 3, c.ground[x + 1] + 3)
	for f: Dictionary in c.flats:  # the band clamp may have moved a flat
		f["y"] = c.ground[(int(f["x0"]) + int(f["x1"])) / 2]

static func _smooth(a: PackedFloat32Array, r: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(a.size())
	for i in a.size():
		var s := 0.0
		var k := 0
		for j in range(maxi(0, i - r), mini(a.size() - 1, i + r) + 1):
			s += a[j]
			k += 1
		out[i] = s / k
	return out
