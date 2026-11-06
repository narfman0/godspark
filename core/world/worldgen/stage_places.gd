## Stage "places": every settlement site becomes a laid-out place (PlaceBuilder) in the
## style of the culture the sim will put there, with the lots of its starting tier built.
## The sim is built here exactly as the host will build it (WorldSim.from_meta on the same
## sites, routes and seed), so cultures and tiers match without the sim reading places.
## Sites nobody settles get a place with tier "" (laid out and levelled, nothing built):
## a founding stamps it later.
##
## The street (the feet row, site y) is levelled: cut down to it and filled up to it,
## with 1-tile-per-column ramps back to the natural ground at both ends on the surface.
## Columns that would need more than MAX_CUT tiles of cut or fill, or that hold a road or
## ramp (cobble walls), or open caves just under the ground, end a place's span.
extends RefCounted

const GenContext := preload("gen_context.gd")
const Barriers := preload("stage_barriers.gd")

const MAX_CUT := 12
const HALF_MAX := 150
const RAMP_MAX := 60
const STREET_CLEAR := 6
const FILL_MAX := 14
const EDGE_BARE := 64

static func run(c: GenContext, _rng: RandomNumberGenerator) -> void:
	PlaceStyles.ensure()
	Dressing.ensure()
	c.places = {}
	var sim := WorldSim.from_meta({"sites": c.sites, "routes": c.routes, "surface": c.surface}, c.world_seed)
	for s: Dictionary in c.sites:
		if s["kind"] != "settlement":
			continue
		var deep := not String(s["band"]) in ["surface", "sky"]
		var ss: SimSettlement = sim.settlements.get(int(s["id"]))
		var culture := ss.culture if ss != null else default_culture(String(s["band"]))
		var tier := ss.tier if ss != null else ""
		var lim := limits(c, s, deep)
		var place := PlaceBuilder.plan(s, culture, c.world_seed, lim.x, lim.y)
		if place.is_empty():
			continue
		place["tier"] = tier
		_level(c, place, deep)
		for i in (place["lots"] as Array).size():
			if PlaceBuilder.lot_wanted(place["lots"][i], tier):
				apply(c, PlaceBuilder.set_lot(place, i, "built", c.world_seed))
		PlaceBuilder.refresh_buildings(place)
		c.places[str(s["id"])] = place
		if not deep:
			resurvey(c, int(place["street"][0]) - RAMP_MAX - 2, int(place["street"][1]) + RAMP_MAX + 2)

## Who builds on an unsettled site if someone founds it later (the founder's culture wins).
static func default_culture(band: String) -> String:
	match band:
		"surface", "sky":
			return "human"
		"caves":
			return "dwarf"
		_:
			return "drow"

## The columns a place at site s may use: contiguous usable ground around the site, at most
## HALF_MAX each way, short of the midpoint to any neighbouring site and the ascent mouth.
static func limits(c: GenContext, s: Dictionary, deep: bool) -> Vector2i:
	var sx := int(s["x"])
	var y := int(s["y"])
	# the surface stays bare at the world's ends: roads run everywhere between the towns, and
	# the passages stage, which never cuts a road, needs open ground to reach the caves from
	var edge := 4 if deep else mini(EDGE_BARE, c.w / 16)
	var lo := maxi(edge, sx - HALF_MAX)
	var hi := mini(c.w - edge - 1, sx + HALF_MAX)
	for o: Dictionary in c.sites:
		var o_deep := not String(o["band"]) in ["surface", "sky"]
		if int(o["id"]) == int(s["id"]) or o_deep != deep or (deep and absi(int(o["y"]) - y) > 40):
			continue
		# half the way to a neighbour, less half the climb between them (room for the road)
		var ox := int(o["x"])
		var climb := absi(int(o["y"]) - y) / 2 + 4
		if ox < sx:
			lo = maxi(lo, (ox + sx) / 2 + climb)
		elif ox > sx:
			hi = mini(hi, (ox + sx) / 2 - climb)
	if not deep and not c.ascent.is_empty():
		var m := int(c.ascent["x1"])
		if m < sx:
			lo = maxi(lo, m + 12)
		else:
			hi = mini(hi, m - 12)
	var a := sx
	while a - 1 >= lo and _usable(c, a - 1, y, deep) and (deep or c.reserved[a - 1] == 0):
		a -= 1
	var b := sx
	while b + 1 <= hi and _usable(c, b + 1, y, deep) and (deep or c.reserved[b + 1] == 0):
		b += 1
	return Vector2i(a, b)

static func _usable(c: GenContext, x: int, y: int, deep: bool) -> bool:
	var row := c.w
	for yy in range(maxi(1, y - 12), mini(c.h - 1, y + 30)):
		if c.bg[x + yy * row] == c.W_COBBLE and (yy < y - 1 or yy > y + 5 or not deep):
			return false   # a road or ramp passes here
	if deep:
		var fl := c.drop_to_floor(x, y + 3, 10)
		return fl > 0 and absi(fl - y) <= 1
	var nat := c.surface[x]
	if absi(nat - (y - 1)) > MAX_CUT:
		return false
	var low := mini(nat, y - 1)
	for yy in range(low - 3, low):
		if not c.is_solid(x, yy):
			return false
	return true

## Level the street: the row under it solid (street tile), cut above, fill below.
static func _level(c: GenContext, place: Dictionary, deep: bool) -> void:
	var st := PlaceStyles.style(String(place["style"]))
	var street: int = st["ids"]["street"]
	var x0 := int(place["street"][0])
	var x1 := int(place["street"][1])
	var y := int(place["street"][2])
	var clear := {}
	for i in (place["lots"] as Array).size():
		var r := PlaceBuilder.lot_rect(place, i)
		for x in range(r.position.x, r.end.x):
			clear[x] = maxi(int(clear.get(x, 0)), r.end.y - y + 1)
	var lo := x0
	var hi := x1
	for x: int in clear:
		lo = mini(lo, x)
		hi = maxi(hi, x)
	for x in range(lo, hi + 1):
		var top := y + maxi(STREET_CLEAR, int(clear.get(x, 0)))
		if not deep:
			top = maxi(top, c.surface[x])
		for yy in range(y, mini(c.h - 2, top) + 1):
			c.fg[x + yy * c.w] = c.AIR
			if not deep:
				c.bg[x + yy * c.w] = 0
		if x >= x0 and x <= x1:
			c.fg[x + (y - 1) * c.w] = street
		elif not c.is_solid(x, y - 1):
			c.fg[x + (y - 1) * c.w] = c.DIRT if deep else c.col_soil[x]
		var yy := y - 2
		while yy > 1 and yy >= y - FILL_MAX and not c.is_solid(x, yy):
			c.fg[x + yy * c.w] = c.DIRT if deep else c.col_soil[x]
			yy -= 1
		if not deep:
			c.surface[x] = y - 1
	if not deep:
		_ramp(c, hi + 1, 1, y - 1)
		_ramp(c, lo - 1, -1, y - 1)
	else:
		_ramp_deep(c, hi + 1, 1, y)
		_ramp_deep(c, lo - 1, -1, y)

## Grade the ground from the street's level back to the natural surface, one tile per column.
static func _ramp(c: GenContext, x_start: int, dir: int, level: int) -> void:
	var prev := level
	var x := x_start
	for k in RAMP_MAX:
		if x < 1 or x >= c.w - 1 or c.reserved[x] != 0:
			return
		var nat := c.surface[x]
		if absi(nat - prev) <= 1:
			return
		var nw := prev + signi(nat - prev)
		var top := c.col_top[x]
		if nw > nat:
			for yy in range(nat, nw + 1):
				c.fg[x + yy * c.w] = c.col_soil[x]
		else:
			for yy in range(nw + 1, nat + 1):
				c.fg[x + yy * c.w] = c.AIR
				c.bg[x + yy * c.w] = 0
		c.fg[x + nw * c.w] = top
		c.surface[x] = nw
		prev = nw
		x += dir

## In a cavern: from the street's feet row y, step the floor one tile per column back to
## the natural floor (fill below, cut above, with 4 clear rows over the new feet cell).
static func _ramp_deep(c: GenContext, x_start: int, dir: int, y: int) -> void:
	var prev := y
	var x := x_start
	for k in RAMP_MAX:
		if x < 1 or x >= c.w - 1:
			return
		var fl := c.drop_to_floor(x, prev + 4, 16)
		if fl > 0 and absi(fl - prev) <= 1:
			return
		for yy in range(maxi(1, prev - 12), mini(c.h - 1, prev + 8)):
			if c.bg[x + yy * c.w] == c.W_COBBLE:
				return   # a road or ramp runs here: it carries on, leave it open
		var nw := prev + (signi(fl - prev) if fl > 0 else 0)
		for yy in range(nw, nw + 4):
			c.fg[x + yy * c.w] = c.AIR
		if not c.is_solid(x, nw - 1):
			var yy := nw - 1
			while yy > 1 and yy >= nw - FILL_MAX and not c.is_solid(x, yy):
				c.fg[x + yy * c.w] = c.STONE
				yy -= 1
		prev = nw
		x += dir

static func apply(c: GenContext, wr: Dictionary) -> void:
	var cells: PackedInt32Array = wr["cells"]
	for i in range(0, cells.size(), 4):
		var x := cells[i]
		var y := cells[i + 1]
		if x < 0 or y < 0 or x >= c.w or y >= c.h:
			continue
		if cells[i + 2] >= 0:
			c.fg[x + y * c.w] = cells[i + 2]
		if cells[i + 3] >= 0:
			c.bg[x + y * c.w] = cells[i + 3]
	for o: Array in wr["objects"]:
		c.objects.append_array(PackedInt32Array([o[0], o[1], o[2], o[3]]))

## Highest solid tile per column again, over [a, b].
static func resurvey(c: GenContext, a: int, b: int) -> void:
	for x in range(maxi(0, a), mini(c.w - 1, b) + 1):
		var y := c.h - 1
		while y > 0 and c.solid[c.fg[x + y * c.w]] == 0:
			y -= 1
		c.surface[x] = y
