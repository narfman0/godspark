## Stage "caves": noise caves (blobs plus long "spaghetti" ridges, densest in the caves
## band, sparse deeper), long worm tunnels in the upper underground, and a few entrance
## worms that break the surface away from settlement flats.
extends RefCounted

const GenContext := preload("gen_context.gd")

static func run(c: GenContext, rng: RandomNumberGenerator) -> void:
	_noise_caves(c, rng)
	_worms(c, rng)
	_entrances(c, rng)

static func _noise_caves(c: GenContext, rng: RandomNumberGenerator) -> void:
	var blob := c.noise(rng, 1.0 / 52.0, 3)
	var ridge := c.noise(rng, 1.0 / 120.0, 2)
	ridge.domain_warp_enabled = true
	ridge.domain_warp_amplitude = 18.0
	ridge.domain_warp_frequency = 1.0 / 60.0
	var ridge2 := c.noise(rng, 1.0 / 140.0, 1)
	var top := 0
	for x in c.w:
		top = maxi(top, c.ground[x])
	var a := GenContext.noise_bytes(blob, 0, 0, c.w, top + 1)
	var b := GenContext.noise_bytes(ridge, 0, 0, c.w, top + 1)
	var b2 := GenContext.noise_bytes(ridge2, 0, 0, c.w, top + 1)
	# Per-row thresholds: blob > ta, or ridge within tb of zero.
	var ta := PackedInt32Array()
	var tb := PackedInt32Array()
	ta.resize(top + 1)
	tb.resize(top + 1)
	for y in top + 1:
		match c.band_at(y):
			"nadir":
				ta[y] = 190; tb[y] = 4
			"deeps":
				ta[y] = 180; tb[y] = 7
			"caves":
				ta[y] = 168; tb[y] = 10
			_:
				ta[y] = 176; tb[y] = 8
	# Crust: no noise caves within ~12 tiles of the ground.
	var limit := PackedInt32Array()
	limit.resize(c.w)
	var ncrust := c.noise(rng, 1.0 / 40.0)
	for x in c.w:
		limit[x] = c.ground[x] - 12 - int((ncrust.get_noise_1d(x) + 1.0) * 5.0)
	var w := c.w
	var fg := c.fg
	var air := c.AIR
	var bedrock := c.BEDROCK
	for y in range(1, top + 1):
		var t1 := ta[y]
		var t2 := tb[y]
		var row := y * w
		for x in w:
			if y > limit[x]:
				continue
			var i := row + x
			# ridge2 gates the spaghetti so tunnels come in clusters, not everywhere
			if a[i] > t1 or (absi(b[i] - 128) < t2 and b2[i] > 104):
				if fg[i] != bedrock:
					fg[i] = air

static func _worm(c: GenContext, rng: RandomNumberGenerator, x: float, y: float, ang: float,
		steps: int, r: float, ymin: int, ymax_off: int, wander: float, keep_level: bool) -> void:
	var dir := 1.0 if cos(ang) >= 0.0 else -1.0
	for i in steps:
		c.carve_disc(int(x), int(y), r)
		ang += rng.randf_range(-wander, wander)
		if keep_level:
			# pull back toward horizontal in the current direction
			var level := 0.0 if dir > 0.0 else PI
			ang = lerp_angle(ang, level, 0.06)
		else:
			ang = clampf(ang, -PI + 0.35, -0.35)  # keep heading down
		x += cos(ang) * 1.6
		y += sin(ang) * 1.6
		r = clampf(r + rng.randf_range(-0.25, 0.25), 1.8, 3.6)
		var gx := clampi(int(x), 0, c.w - 1)
		var ymax := c.ground[gx] - ymax_off
		if y > ymax:
			y = ymax
			ang = -absf(ang) if keep_level else ang
		if y < ymin:
			y = ymin
		if x < 4 or x > c.w - 5:
			break

static func _worms(c: GenContext, rng: RandomNumberGenerator) -> void:
	var cb: Array = c.bands["caves"]
	var n := maxi(3, int(14 * c.sx() * c.sy()))
	for i in n:
		var x := rng.randf_range(16, c.w - 16)
		var y := rng.randf_range(cb[0] + 10, cb[1])
		var ang := rng.randf_range(-0.35, 0.35) + (0.0 if rng.randf() < 0.5 else PI)
		var steps := int(rng.randi_range(160, 420) * clampf(c.sx(), 0.5, 1.0))
		_worm(c, rng, x, y, ang, steps, rng.randf_range(2.0, 3.2), cb[0] - int(c.band_h("deeps") * 0.3), 16, 0.22, true)
	# Fewer, longer, wider ones through the deeps.
	var db: Array = c.bands["deeps"]
	for i in maxi(2, int(7 * c.sx() * c.sy())):
		var x := rng.randf_range(16, c.w - 16)
		var y := rng.randf_range(db[0] + 10, db[1] - 10)
		var ang := rng.randf_range(-0.3, 0.3) + (0.0 if rng.randf() < 0.5 else PI)
		var steps := int(rng.randi_range(200, 520) * clampf(c.sx(), 0.5, 1.0))
		_worm(c, rng, x, y, ang, steps, rng.randf_range(2.6, 3.6), db[0] + 6, c.ground[int(x)] - db[1] + 4, 0.2, true)

static func _entrances(c: GenContext, rng: RandomNumberGenerator) -> void:
	var n := maxi(2, int(5 * c.sx()))
	var cb: Array = c.bands["caves"]
	var placed := 0
	for _try in n * 20:
		if placed >= n:
			break
		var x := rng.randi_range(40, c.w - 41)
		if _near_flat(c, x, 50):
			continue
		var dir := 1.0 if rng.randf() < 0.5 else -1.0
		var ang := -PI / 2.0 + dir * rng.randf_range(0.35, 0.75)
		var target := rng.randi_range(cb[0] + c.band_h("caves") / 3, cb[1] - 10)
		var steps := int((c.ground[x] - target) / 1.2)
		# Steer away from flats: the worm drifts sideways by about steps * cos(ang).
		var end_x := x + int(cos(ang) * 1.6 * steps)
		if end_x < 20 or end_x > c.w - 20:
			continue
		_worm(c, rng, x, c.ground[x] + 2, ang, steps, rng.randf_range(2.2, 3.0), cb[0], -4, 0.12, false)
		placed += 1

static func _near_flat(c: GenContext, x: int, margin: int) -> bool:
	for f: Dictionary in c.flats:
		if x >= int(f["x0"]) - margin and x <= int(f["x1"]) + margin:
			return true
	return false
