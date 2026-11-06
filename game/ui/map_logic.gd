## The world map's pure part: where things go on the map, what the player knows of, and the
## way to a target. Everything is drawn from META (surface, bands, sites) and Deals' ATLAS
## (names, states, route paths, seen sites), never from tiles: a client holds only nearby
## chunks. World y is up; the map's y is down.
class_name MapLogic
extends RefCounted

## A site's feet cell from META, or Vector2.INF.
static func site_xy(meta: Dictionary, sid: int) -> Vector2:
	for s: Dictionary in meta.get("sites", []):
		if int(s["id"]) == sid:
			return Vector2(float(s["x"]), float(s["y"]))
	return Vector2.INF

## Where a quest points: its live `where` (a party, a lair), else its target site, else the
## giver's town. Vector2.INF when nothing is known.
static func quest_target(q: Dictionary, meta: Dictionary) -> Vector2:
	var w: Variant = q.get("where")
	if w is Array and (w as Array).size() == 2:
		return Vector2(float(w[0]), float(w[1]))
	if q.has("target_site"):
		var p := site_xy(meta, int(q["target_site"]))
		if p != Vector2.INF:
			return p
	return site_xy(meta, int(q.get("site", -1)))

## What the player knows of: site id -> "seen" (stood there) or "heard" (named in a rumour or
## a quest). Everything else is not drawn.
static func discovered(seen: Dictionary, rumours: Array, quests: Array) -> Dictionary:
	var out := {}
	for r: Dictionary in rumours:
		if int(r.get("site", -1)) >= 0:
			out[int(r["site"])] = "heard"
	for q: Dictionary in quests:
		for k: String in ["target_site", "site"]:
			if q.has(k) and int(q[k]) >= 0:
				out[int(q[k])] = "heard"
	for sid: Variant in seen:
		out[int(sid)] = "seen"
	return out

## Map position of a world cell: x to the right, depth downward, `zoom` map pixels a tile,
## `origin` the map position of world (0, top).
static func to_map(cell: Vector2, world_h: float, zoom: float, origin: Vector2) -> Vector2:
	return origin + Vector2(cell.x, world_h - cell.y) * zoom

static func from_map(p: Vector2, world_h: float, zoom: float, origin: Vector2) -> Vector2:
	var q := (p - origin) / zoom
	return Vector2(q.x, world_h - q.y)

## The zoom that fits the whole world's width (and height) in a view.
static func fit_zoom(world: Vector2, view: Vector2) -> float:
	return minf(view.x / maxf(1.0, world.x), view.y / maxf(1.0, world.y))

## Origin that keeps a view inside the world, centred on `centre` (a world cell).
static func origin_for(centre: Vector2, world: Vector2, zoom: float, view: Vector2) -> Vector2:
	var c := Vector2(centre.x, world.y - centre.y) * zoom
	var o := view * 0.5 - c
	var size := world * zoom
	o.x = clampf(o.x, view.x - size.x, 0.0) if size.x > view.x else (view.x - size.x) * 0.5
	o.y = clampf(o.y, view.y - size.y, 0.0) if size.y > view.y else (view.y - size.y) * 0.5
	return o

## A route as map points, dropping points closer than `min_px` to the last kept one.
static func polyline(path: Array, world_h: float, zoom: float, origin: Vector2, min_px := 3.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in path.size():
		var c: Vector2 = Vector2(path[i])
		var p := to_map(c, world_h, zoom, origin)
		if out.is_empty() or i == path.size() - 1 or p.distance_to(out[out.size() - 1]) >= min_px:
			out.append(p)
	return out

## The surface line as map points, sampled every `step` columns.
static func surface_line(surface: Array, world_h: float, zoom: float, origin: Vector2, step := 8) -> PackedVector2Array:
	var out := PackedVector2Array()
	var i := 0
	while i < surface.size():
		out.append(to_map(Vector2(i, float(surface[i])), world_h, zoom, origin))
		i += step
	if not surface.is_empty():
		out.append(to_map(Vector2(surface.size() - 1, float(surface[surface.size() - 1])), world_h, zoom, origin))
	return out

## Routes whose two ends are both known (a road you know leads somewhere you know).
static func known_routes(routes: Array, known: Dictionary) -> Array:
	return routes.filter(func(r: Dictionary) -> bool: return known.has(int(r["a"])) and known.has(int(r["b"])))

## Tier as a number for the emblem.
static func tier_n(tier: String) -> int:
	return {"hamlet": 0, "village": 1, "town": 2, "city": 3}.get(tier, 0)

## The site nearest a map point within `radius` px, or -1.
static func pick(sites_px: Dictionary, p: Vector2, radius := 12.0) -> int:
	var best := -1
	var bd := radius
	for sid: int in sites_px:
		var d := (sites_px[sid] as Vector2).distance_to(p)
		if d <= bd:
			bd = d
			best = sid
	return best
