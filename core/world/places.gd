## What worldgen and the sim know about places, read from `world.meta`: the buildings of each
## settlement site and the tile path of each route. Pure lookups; everything is JSON-safe.
## A world made before places existed simply has none (empty answers).
##
##   Places.place(world, site_id)   -> {site, rect: [x, y, w, h], culture, tier, buildings: [...]}
##   building: {kind, rect: [x, y, w, h], door: [x, y], anchors: {role: [[x, y], ...]}}
##     kind: home | smithy | market | tavern | shrine | gate | hall | store | ruin
##     anchors: where a person of that role stands or works (smith, merchant, keeper,
##              priest, guard, townsfolk); cells are feet positions (open, floor below)
##   Places.route_path(world, route_id) -> [[x, y], ...]  feet cells from site a to site b
class_name Places
extends RefCounted

static func all(world: TileWorld) -> Dictionary:
	return world.meta.get("places", {})

## The place at a site, {} if the site has none.
static func place(world: TileWorld, site_id: int) -> Dictionary:
	return all(world).get(str(site_id), {})

static func buildings(world: TileWorld, site_id: int, kind := "") -> Array:
	var out := []
	for b: Dictionary in place(world, site_id).get("buildings", []):
		if kind == "" or b.get("kind", "") == kind:
			out.append(b)
	return out

## Feet cells for a role at a site: the buildings' anchors, else the site itself.
static func anchors(world: TileWorld, site_id: int, role: String) -> Array:
	var out := []
	for b: Dictionary in place(world, site_id).get("buildings", []):
		for cell: Array in b.get("anchors", {}).get(role, []):
			out.append(Vector2i(int(cell[0]), int(cell[1])))
	if out.is_empty():
		var s := site(world, site_id)
		if not s.is_empty():
			out.append(Vector2i(int(s["x"]), int(s["y"])))
	return out

static func site(world: TileWorld, site_id: int) -> Dictionary:
	for s: Dictionary in world.meta.get("sites", []):
		if int(s["id"]) == site_id:
			return s
	return {}

static func route(world: TileWorld, route_id: int) -> Dictionary:
	for r: Dictionary in world.meta.get("routes", []):
		if int(r["id"]) == route_id:
			return r
	return {}

## The route as feet cells from site a to site b; a straight two-point path between the
## sites when worldgen stored none.
static func route_path(world: TileWorld, route_id: int) -> Array:
	var r := route(world, route_id)
	var out := []
	for cell: Array in r.get("path", []):
		out.append(Vector2i(int(cell[0]), int(cell[1])))
	if out.is_empty() and not r.is_empty():
		for sid: int in [int(r["a"]), int(r["b"])]:
			var s := site(world, sid)
			if not s.is_empty():
				out.append(Vector2i(int(s["x"]), int(s["y"])))
	return out

## The cell a fraction of the way along a route (0 at site a, 1 at site b).
static func route_point(world: TileWorld, route_id: int, t: float) -> Vector2i:
	var path := route_path(world, route_id)
	if path.is_empty():
		return Vector2i.ZERO
	return path[clampi(roundi(t * (path.size() - 1)), 0, path.size() - 1)]
