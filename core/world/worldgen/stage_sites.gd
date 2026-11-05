## The last stages: what the world means rather than what it is made of.
##   "ruins"   carves buried ruin rooms in the caves band.
##   "finish"  surveys the surface (highest solid tile per column) and grows the biome
##             top tile on soil left exposed at the top of a column.
##   "sites"   settlements on the planned flats, deep settlements in settled caverns, the
##             portal chamber, cave lairs, a surface ruin and the buried ruins.
##   "routes"  roads between neighbouring surface settlements, deep roads between deep
##             sites, the ascent route (deep settlement to a surface settlement) and the
##             route down to the portal.
## Site y is the feet row: the first open tile above solid ground.
extends RefCounted

const GenContext := preload("gen_context.gd")
const StageBiomes := preload("stage_biomes.gd")

static func ruins(c: GenContext, rng: RandomNumberGenerator) -> void:
	var cb: Array = c.bands["caves"]
	var n := 1 if c.w < 1024 else 2
	if c.w >= 6000:
		n = 3
	c.buried_rooms = []
	for _try in n * 50:
		if c.buried_rooms.size() >= n:
			break
		var rw := rng.randi_range(18, 26)
		var rh := rng.randi_range(7, 9)
		var x := rng.randi_range(rw + 10, c.w - rw - 10)
		var y := rng.randi_range(cb[0] + 8, cb[1] - 30)
		y = mini(y, c.ground[x] - 30)
		if _touches_built(c, x - 4, y - 4, x + rw + 4, y + rh + 4):
			continue  # never wall off a road or ramp
		c.carve_rect(x, y, x + rw - 1, y + rh - 1)
		c.wall_rect(x, y, x + rw - 1, y + rh - 1, c.W_COBBLE)
		c.fill_rect(x - 1, y - 1, x + rw, y - 1, c.COBBLE)
		# broken walls and a pillar or two
		for k in rng.randi_range(2, 4):
			var px := rng.randi_range(x + 2, x + rw - 3)
			var ph := rng.randi_range(1, rh - 2)
			c.fill_rect(px, y, px, y + ph - 1, c.COBBLE)
		c.fill_rect(x - 1, y, x - 1, y + rng.randi_range(2, rh), c.COBBLE)
		c.fill_rect(x + rw, y, x + rw, y + rng.randi_range(2, rh), c.COBBLE)
		c.buried_rooms.append({"x": x + rw / 2, "y": y, "w": rw})

static func _touches_built(c: GenContext, x0: int, y0: int, x1: int, y1: int) -> bool:
	for r: Dictionary in c.buried_rooms:
		if absi(int(r["x"]) - (x0 + x1) / 2) < 60 and absi(int(r["y"]) - y0) < 30:
			return true
	for y in range(maxi(0, y0), mini(c.h - 1, y1) + 1):
		for x in range(maxi(0, x0), mini(c.w - 1, x1) + 1):
			if c.bg[x + y * c.w] == c.W_COBBLE:
				return true
	return false

static func finish(c: GenContext, _rng: RandomNumberGenerator) -> void:
	c.survey()
	for x in c.w:
		var y := c.surface[x]
		var d: Dictionary = c.biome_defs[c.col_biome[x]]
		if c.fg[x + y * c.w] == TileDefs.id(d["soil"]):
			c.fg[x + y * c.w] = TileDefs.id(d["top"])

static func _biome_for(c: GenContext, x: int, band: String) -> String:
	match band:
		"surface", "sky":
			return StageBiomes.biome_name(c, x)
		"caves":
			return "caves"
		_:
			return "underdark"

static func _add(c: GenContext, kind: String, x: int, y: int, size: int) -> Dictionary:
	var band := c.band_at(y)
	var s := {"id": c.sites.size(), "kind": kind, "x": x, "y": y, "biome": _biome_for(c, x, band),
		"band": band, "size": size}
	c.sites.append(s)
	return s

static func _headroom(c: GenContext, x: int, y: int, tall: int) -> bool:
	for k in tall:
		if c.is_solid(x, y + k):
			return false
	return c.is_solid(x, y - 1)

static func sites(c: GenContext, rng: RandomNumberGenerator) -> void:
	c.sites = []
	# Surface settlements on the flats that survived carving.
	for f: Dictionary in c.flats:
		var x0 := int(f["x0"])
		var x1 := int(f["x1"])
		var level := 0
		for x in range(x0, x1 + 1):
			if c.surface[x] == int(f["y"]):
				level += 1
		var x := (x0 + x1) / 2
		var y := c.surface[x] + 1
		if level * 10 >= (x1 - x0 + 1) * 8 and _headroom(c, x, y, 8):
			_add(c, "settlement", x, y, x1 - x0 + 1)
	# Deep settlements.
	for ci in c.caverns.size():
		var cav: Dictionary = c.caverns[ci]
		if not cav["settled"]:
			continue
		var x := int(cav["x"])
		var y := c.drop_to_floor(x, int(cav["floor"]) + 3)
		if y > 0 and _headroom(c, x, y, 6):
			var s := _add(c, "settlement", x, y, int(cav["rx"]) * 3 / 2)
			cav["site"] = s["id"]
	# Portal.
	if not c.portal.is_empty():
		var px := int(c.portal["x"])
		var py := c.drop_to_floor(px, int(c.portal["y"]) + 2)
		if py > 0:
			var s := _add(c, "portal", px, py, int(c.portal["w"]))
			c.portal["site"] = s["id"]
	# Ruins: one on the surface away from flats and the ascent mouth, plus the buried rooms.
	for _try in 200:
		var x := rng.randi_range(30, c.w - 31)
		var mouth := int(c.ascent.get("x1", -1000))
		if _flat_gap(c, x) < 40 or absi(x - mouth) < 40:
			continue
		var y := c.surface[x] + 1
		if absi(c.surface[x - 3] - c.surface[x + 3]) <= 2 and _headroom(c, x, y, 6):
			_add(c, "ruin", x, y, 12)
			break
	for r: Dictionary in c.buried_rooms:
		var y := c.drop_to_floor(int(r["x"]), int(r["y"]) + 2)
		if y > 0:
			_add(c, "ruin", int(r["x"]), y, int(r["w"]))
	# Cave lairs: open pockets with a floor, spread apart.
	var cb: Array = c.bands["caves"]
	var want := maxi(2, int(5 * c.sx()))
	var spacing := maxi(60, c.w / (want * 2))
	var lairs: Array = []
	for _try in want * 200:
		if lairs.size() >= want:
			break
		var x := rng.randi_range(20, c.w - 21)
		var y0 := rng.randi_range(cb[0] + 4, cb[1] - 4)
		if y0 > c.ground[x] - 16 or c.is_solid(x, y0):
			continue
		var y := c.drop_to_floor(x, y0, 24)
		if y < 0 or c.band_at(y) != "caves" or not _headroom(c, x, y, 4):
			continue
		if c.open_count(x - 6, y, x + 6, y + 5) < 60:
			continue
		var ok := true
		for l: Vector2i in lairs:
			if absi(l.x - x) < spacing:
				ok = false
				break
		if ok:
			lairs.append(Vector2i(x, y))
			_add(c, "lair", x, y, 8)

static func _flat_gap(c: GenContext, x: int) -> int:
	var gap := 1 << 30
	for f: Dictionary in c.flats:
		gap = mini(gap, maxi(0, maxi(int(f["x0"]) - x, x - int(f["x1"]))))
	return gap

static func _route(c: GenContext, a: int, b: int, kind: String, length: int) -> void:
	c.routes.append({"id": c.routes.size(), "a": a, "b": b, "kind": kind, "length": maxi(1, length)})

static func routes(c: GenContext, _rng: RandomNumberGenerator) -> void:
	c.routes = []
	var surface_towns: Array = []
	var deep_towns: Array = []
	for s: Dictionary in c.sites:
		if s["kind"] != "settlement":
			continue
		if s["band"] == "surface" or s["band"] == "sky":
			surface_towns.append(s)
		else:
			deep_towns.append(s)
	var by_x := func(a: Dictionary, b: Dictionary) -> bool: return int(a["x"]) < int(b["x"])
	surface_towns.sort_custom(by_x)
	deep_towns.sort_custom(by_x)
	for i in surface_towns.size() - 1:
		var a: Dictionary = surface_towns[i]
		var b: Dictionary = surface_towns[i + 1]
		var length := 0
		for x in range(int(a["x"]), int(b["x"])):
			length += 1 + absi(c.surface[x + 1] - c.surface[x])
		_route(c, a["id"], b["id"], "road", length)
	for i in deep_towns.size() - 1:
		var a: Dictionary = deep_towns[i]
		var b: Dictionary = deep_towns[i + 1]
		_route(c, a["id"], b["id"], "deep_road", _road_length(c, int(a["x"]), int(b["x"])))
	# Ascent: its deep settlement to the surface settlement nearest the mouth.
	if not c.ascent.is_empty() and not surface_towns.is_empty():
		var cav: Dictionary = c.caverns[int(c.ascent["cavern"])]
		if cav.has("site"):
			var mouth := int(c.ascent["x1"])
			var best: Dictionary = surface_towns[0]
			for s: Dictionary in surface_towns:
				if absi(int(s["x"]) - mouth) < absi(int(best["x"]) - mouth):
					best = s
			var length := absi(int(cav["x"]) - int(c.ascent["x0"])) + int(c.ascent["steps"]) \
					+ absi(mouth - int(best["x"]))
			_route(c, cav["site"], best["id"], "deep_road", length)
	# Down to the portal from the nearest deep settlement along the road.
	if c.portal.has("site") and not deep_towns.is_empty():
		var pcav: Dictionary = c.caverns[int(c.portal["cavern"])]
		var best: Dictionary = deep_towns[0]
		for s: Dictionary in deep_towns:
			if absi(int(s["x"]) - int(pcav["x"])) < absi(int(best["x"]) - int(pcav["x"])):
				best = s
		var length := _road_length(c, int(best["x"]), int(pcav["x"])) \
				+ absi(int(pcav["x"]) - int(c.portal["x0"])) + int(c.portal["steps"]) + int(c.portal["w"]) / 2
		_route(c, best["id"], c.portal["site"], "deep_road", length)

## Walking length along the deep road between two columns (both inside its span).
static func _road_length(c: GenContext, xa: int, xb: int) -> int:
	var lo := clampi(mini(xa, xb), c.road_x0, c.road_x1)
	var hi := clampi(maxi(xa, xb), c.road_x0, c.road_x1)
	var length := 0
	for x in range(lo, hi):
		length += 1 + absi(c.road_floor[x + 1 - c.road_x0] - c.road_floor[x - c.road_x0])
	return length
