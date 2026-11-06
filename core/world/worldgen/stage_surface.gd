## Stage "surface": the heightmap. Layered noise shaped per biome (data/worldgen/biomes.json,
## "height"): a lift, how much of each noise, sharp ridges for mountains and short swells for
## dunes, all blended across biome borders over the climate's ramp. Flat stretches planned for
## settlements (c.flats) are blended in, and neighbouring columns differ by at most the
## biome's step, so the surface stays walkable.
extends RefCounted

const GenContext := preload("gen_context.gd")
const StageBiomes := preload("stage_biomes.gd")
const Barriers := preload("stage_barriers.gd")

const KEYS := ["base", "big", "mid", "fine", "ridge", "dune"]
## Share of the surface band under its top where heights start easing off.
const KNEE := 0.2
const BLEND := 28.0

static func run(c: GenContext, rng: RandomNumberGenerator) -> void:
	var sb: Array = c.bands["surface"]
	var band := float(int(sb[1]) - int(sb[0]))
	var base := c.h * 0.735
	var big := c.noise(rng, 1.0 / 520.0, 3)
	var mid := c.noise(rng, 1.0 / 110.0, 2)
	var fine := c.noise(rng, 1.0 / 22.0, 1)
	var ridges := c.noise(rng, 1.0 / 260.0, 2)
	var dunes := c.noise(rng, 1.0 / 60.0, 1)
	var amp_big := minf(c.h * 0.05, 80.0)
	var amp_mid := 2.0 + minf(c.h * 0.012, 18.0)
	var amp_fine := 1.3
	var amp_ridge := minf(c.h * 0.06, 120.0)
	var amp_dune := 2.0 + minf(c.h * 0.01, 9.0)
	var p := profile(c)
	var top := float(int(sb[1]) - 4)
	var bottom := float(int(sb[0]) + 4)
	var raw := PackedFloat32Array()
	raw.resize(c.w)
	for x in c.w:
		var rn := 1.0 - absf(ridges.get_noise_1d(x)) * 2.2       # sharp at the crests
		var v: float = base + float(p["base"][x]) * band \
				+ float(p["big"][x]) * big.get_noise_1d(x) * 2.0 * amp_big \
				+ float(p["mid"][x]) * mid.get_noise_1d(x) * 1.8 * amp_mid \
				+ float(p["ridge"][x]) * maxf(0.0, rn) * maxf(0.0, rn) * amp_ridge \
				+ float(p["dune"][x]) * sin(dunes.get_noise_1d(x) * 3.0 + x / 24.0) * amp_dune \
				+ float(p["fine"][x]) * fine.get_noise_1d(x) * amp_fine
		raw[x] = _ease_top(v, top, band * KNEE)

	# Barriers draw from an RNG of their own, so they never reshuffle the ground around them.
	var brng := WorldGen.rng_for(c.world_seed, "barrier_plan")
	var held_spans: Array = Barriers.plan_ranges(c, brng, raw, BLEND)
	# Flat stretches, one per slot across the width.
	var n := maxi(2, c.w / 340)
	var slot := c.w / n
	c.flats = []
	for i in n:
		# wide enough for a town (places); small test worlds keep their narrow flats
		var fw := mini(rng.randi_range(96, 150) if c.w >= 1024 else rng.randi_range(48, 80), slot / 2)
		var centre := slot * i + slot / 2 + rng.randi_range(-slot / 5, slot / 5)
		centre = clampi(centre, fw + 8, c.w - fw - 8)
		var x0 := centre - fw / 2
		var x1 := x0 + fw - 1
		if Barriers.reserved_in(c, x0 - int(BLEND), x1 + int(BLEND)):
			continue                       # no town on a range
		var level := 0.0
		for x in range(x0, x1 + 1):
			level += raw[x]
		level = roundf(level / fw)
		if not c.flats.is_empty():      # within a walk of the flat before it
			var prev: Dictionary = c.flats[-1]
			var reach := float(maxi(0, x0 - int(prev["x1"])) * int(p["step"][x0]))
			level = clampf(level, float(prev["y"]) - reach, float(prev["y"]) + reach)
		for x in range(maxi(0, x0 - int(BLEND)), mini(c.w - 1, x1 + int(BLEND)) + 1):
			var d := maxf(x0 - x, x - x1)
			if d <= 0:
				raw[x] = level
			else:
				raw[x] = lerpf(level, raw[x], smoothstep(0.0, 1.0, d / BLEND))
		c.flats.append({"x0": x0, "x1": x1, "y": int(level)})

	held_spans.append_array(Barriers.plan_rivers(c, brng, raw, BLEND))
	for x in c.w:
		c.ground[x] = clampi(roundi(raw[x]), int(bottom), int(top))
	# Never more than the biome's step between neighbours (keeps the surface walkable). The
	# flats hold their level: the slopes around them give way, so a town on a ridge sits in a
	# notch instead of its ground being dragged off level.
	var held := PackedByteArray()
	held.resize(c.w)
	for f: Dictionary in c.flats:
		for x in range(int(f["x0"]), int(f["x1"]) + 1):
			held[x] = 1
	for span: Array in held_spans:
		for x in range(int(span[0]), int(span[1]) + 1):
			held[x] = 1
	for x in range(1, c.w):
		if held[x] == 0:
			var st := int(p["step"][x])
			c.ground[x] = clampi(c.ground[x], c.ground[x - 1] - st, c.ground[x - 1] + st)
	for x in range(c.w - 2, -1, -1):
		if held[x] == 0:
			var st := int(p["step"][x])
			c.ground[x] = clampi(c.ground[x], c.ground[x + 1] - st, c.ground[x + 1] + st)
	for f: Dictionary in c.flats:  # the band clamp may have moved a flat
		f["y"] = c.ground[(int(f["x0"]) + int(f["x1"])) / 2]
	Barriers.raise(c, brng)

## Heights above the knee ease toward the top of the band instead of being cut flat there.
static func _ease_top(v: float, top: float, knee: float) -> float:
	var k := top - knee
	if v <= k:
		return v
	return k + knee * (1.0 - exp(-(v - k) / knee))

## The biomes' height numbers per column (KEYS, blended over the ramp) and step (not blended).
static func profile(c: GenContext) -> Dictionary:
	var out := {}
	var r := StageBiomes.tiles_of(c, "ramp")
	for key: String in KEYS:
		var a := PackedFloat32Array()
		a.resize(c.w)
		var vals: Array = []
		for d: Dictionary in c.biome_defs:
			vals.append(float(d["height"][key]))
		for x in c.w:
			a[x] = vals[c.col_biome[x]]
		out[key] = _smooth(_smooth(a, r / 2), r / 2)   # twice: a soft ramp with no corners
	var st := PackedInt32Array()
	st.resize(c.w)
	for x in c.w:
		st[x] = int(c.biome_defs[c.col_biome[x]]["height"]["step"])
	out["step"] = st
	return out

## Box average of radius r (a running sum), shrinking at the edges.
static func _smooth(a: PackedFloat32Array, r: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(a.size())
	var n := a.size()
	var sum := 0.0
	var k := 0
	for j in range(0, mini(n - 1, r) + 1):
		sum += a[j]
		k += 1
	for i in n:
		out[i] = sum / k
		if i + r + 1 < n:
			sum += a[i + r + 1]
			k += 1
		if i - r >= 0:
			sum -= a[i - r]
			k -= 1
	return out
