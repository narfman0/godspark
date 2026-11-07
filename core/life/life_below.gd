## Raids from below on screen: the ways up and the surface's answer at them.
##
## A raid from below is a sim raid party (SimBelow) and LifeRoad shows it like any party, along
## its route's tile path: up the way (worldgen's ascent has a meta route path; a link from
## meta.ways gets one here, deep site to the way's bottom, up to its top, on to the surface
## site), out along the surface road to its ambush, and home again. The raiders are their people's
## role blocks (cultures.json roles, make_npc): a drow raid shows spies (raiders), scouts, mages
## and priests by name.
##
## The guards a surface town posts at a way after an ambush (sim.way_watch) stand at its mouth
## while a player is near: the watch's people (their culture's escort blocks), as many as the
## sim counts (at most SHOW), written back one by one when they fall (SimBelow.watch_guard_killed).
##   LifeBelow.mouth(h, way) -> Vector2     the cell where the way comes out on the surface
##   LifeBelow.way_cells(h, way) -> Array   feet cells from the route's site a to site b
class_name LifeBelow
extends RefCounted

## Most guards shown at one watch.
const SHOW := 6

var life: LifeSystem
## way route id -> {ids: {entity id: slug}}
var active := {}
var _mouths := {}
var _cells := {}

func _init(l: LifeSystem) -> void:
	life = l

func reset() -> void:
	_mouths.clear()
	_cells.clear()

# --- where ----------------------------------------------------------------------------------

## Feet cells of a link route from site a to site b: worldgen's own path (the ascent), else for a
## way from meta.ways a walk drawn through its bottom and top ([] when the route is unknown).
func way_cells(h: WorldHost, rid: int) -> Array:
	if _cells.has(rid):
		return _cells[rid]
	var out: Array = []
	if not Places.route(h.world, rid).is_empty():
		out = Places.route_path(h.world, rid)
	else:
		var r: Dictionary = h.sim.route_by_id.get(rid, {})
		if r.has("top") and r.has("bottom"):
			var a := _site_cell(h, int(r.a))
			var b := _site_cell(h, int(r.b))
			var top := Vector2i(int(r.top[0]), int(r.top[1]))
			var bottom := Vector2i(int(r.bottom[0]), int(r.bottom[1]))
			var surface_a := SimData.band_family(h.sim.site_by_id[int(r.a)].band) == "surface"
			var way: Array = []                     # the way's own cells, top to bottom (a sinkhole's rope)
			for q: Variant in r.get("path", []):
				way.append(Vector2i(int(q[0]), int(q[1])))
			if way.is_empty():
				way = [top, bottom]
			if not surface_a:
				way.reverse()
			var pts: Array = [a] + way + [b]
			for i in pts.size() - 1:
				_line(out, pts[i], pts[i + 1])
	_cells[rid] = out
	return out

func _site_cell(h: WorldHost, sid: int) -> Vector2i:
	var s: Dictionary = h.sim.site_by_id.get(sid, {})
	return Vector2i(int(s.get("x", 0)), int(s.get("y", 0)))

static func _line(out: Array, a: Vector2i, b: Vector2i) -> void:
	var n := maxi(absi(b.x - a.x), absi(b.y - a.y))
	for i in n + 1:
		var c := Vector2i(roundi(lerpf(a.x, b.x, float(i) / maxf(n, 1))), roundi(lerpf(a.y, b.y, float(i) / maxf(n, 1))))
		if out.is_empty() or out[out.size() - 1] != c:
			out.append(c)

## Where a way comes out on the surface: meta.ways' top, else the last cell of the route's path,
## walking down from its surface end, that is open to the sky. INF when there is none.
func mouth(h: WorldHost, rid: int) -> Vector2:
	if _mouths.has(rid):
		return _mouths[rid]
	var at := Vector2.INF
	var r: Dictionary = h.sim.route_by_id.get(rid, {})
	if r.has("top") and Places.route(h.world, rid).is_empty():
		at = Vector2(float(r.top[0]) + 0.5, float(r.top[1]))
	else:
		var cells := way_cells(h, rid)
		if not cells.is_empty() and not r.is_empty():
			var from_a := SimData.band_family(h.sim.site_by_id[int(r.a)].band) == "surface"
			var n := cells.size()
			for k in n:
				var c: Vector2i = cells[k if from_a else n - 1 - k]
				if not open_sky(h.world, c):
					break
				at = Vector2(c.x + 0.5, c.y)
	_mouths[rid] = at
	return at

## Nothing solid above a cell, all the way up.
static func open_sky(w: TileWorld, c: Vector2i) -> bool:
	for y in range(c.y + 3, w.height):
		if w.is_solid(c.x, y):
			return false
	return true

# --- the watch at the mouth -----------------------------------------------------------------

func scan(h: WorldHost, players: Array) -> void:
	var cfg := Life.people_cfg()
	var near := float(cfg.get("near_tiles", 80.0))
	var keep := float(cfg.get("keep_tiles", 112.0))
	var sim := h.sim
	for way: int in active.keys():
		var pos := mouth(h, way)
		if not sim.way_watch.has(way) or pos == Vector2.INF or LifeSystem.nearest(players, pos) > keep:
			fold(h, way)
	for way: int in WorldSim._sorted_keys(sim.way_watch):
		var pos := mouth(h, way)
		if pos == Vector2.INF:
			continue
		if active.has(way):
			reconcile(h, way)
		elif LifeSystem.nearest(players, pos) <= near:
			active[way] = {"ids": {}}
			reconcile(h, way)

func reconcile(h: WorldHost, way: int) -> void:
	var w: Dictionary = h.sim.way_watch.get(way, {})
	var rec: Dictionary = active[way]
	var want := mini(int(w.get("n", 0)), SHOW)
	var ids: Dictionary = rec["ids"]
	for id: int in ids.keys():
		if ids.size() <= want:
			break
		ids.erase(id)
		life.unspawn(h, id)
	if ids.size() >= want:
		return
	var c: Dictionary = SimData.cultures.get(str(w.get("culture", "human")), SimData.cultures["human"])
	var slugs := SimData.allocate(c.escort, want)
	var have := {}
	for id: int in ids:
		have[ids[id]] = int(have.get(ids[id], 0)) + 1
	var at := mouth(h, way)
	var slot := 0
	for slug: String in WorldSim._sorted_keys(slugs):
		for i in int(slugs[slug]) - int(have.get(slug, 0)):
			while _slot_taken(h, ids, slot):
				slot += 1
			_spawn_guard(h, way, w, slug, at, slot)
			slot += 1

func _slot_taken(h: WorldHost, ids: Dictionary, slot: int) -> bool:
	for id: int in ids:
		var e := h.entity(id)
		if e != null and int(e.get_meta("slot", -1)) == slot:
			return true
	return false

func _spawn_guard(h: WorldHost, way: int, w: Dictionary, slug: String, at: Vector2, slot: int) -> void:
	var off := float((slot + 1) / 2) * 2.0 * (1.0 if slot % 2 == 1 else -1.0)
	var pos := life.road.ground(h, at + Vector2(off, 0.0), slug, at)
	var culture := str(w.get("culture", "human"))
	var r := Life.rng_for([h.world.world_seed, "watch", way, slot, life.generation("w%d" % way)])
	var given := SimNames.make(r, culture if SimData.names.has(culture) else "place", {})
	var home: String = h.sim._site_label(int(w.home)) if h.sim.site_by_id.has(int(w.home)) else "the town"
	var e := life.spawn_person(h, {"culture": culture, "slug": slug, "role": "guard", "pos": pos, "post": pos,
		"faction": int(w.faction), "sim": {"kind": "watch", "id": way, "role": "guard"}, "fighter": true,
		"name": "%s, watch of %s" % [given, home], "talk": false, "friendly": true, "span": 2.5})
	if e != null:
		e.set_meta("slot", slot)
		e.set_meta("torch", true)        # a watch at a cave mouth keeps a light
		active[way]["ids"][e.id] = slug

func fold(h: WorldHost, way: int) -> void:
	var rec: Dictionary = active.get(way, {})
	active.erase(way)
	for id: int in (rec.get("ids", {}) as Dictionary).keys():
		life.unspawn(h, id)

## A guard of a watch fell: one fewer in the sim.
func died(h: WorldHost, way: int, e: HostEntity) -> void:
	if active.has(way):
		(active[way]["ids"] as Dictionary).erase(e.id)
	life.bump("w%d" % way)
	if SimBelow.watch_guard_killed(h.sim, way):
		life.stats["watch_deaths"] = int(life.stats.get("watch_deaths", 0)) + 1

func actors_at(h: WorldHost, way: int) -> Array[HostEntity]:
	var out: Array[HostEntity] = []
	for id: int in ((active.get(way, {}) as Dictionary).get("ids", {}) as Dictionary):
		if h.entity(id) != null:
			out.append(h.entity(id))
	return out
