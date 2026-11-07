## Raids from below: a deep settlement's raiders climb a known way up (a link route between the
## deeps and the surface: worldgen's ascent, meta.ways) to wait on a surface road for a caravan,
## and carry what they take home, where the town's books receive it (SimEconomy.return_home). The
## record is the raid party itself, its plan marked:
##   plan.below   the way's route id (float: plan values are JSON-safe)
##   plan.way     the way's kind ("ascent" for worldgen's ramp, else meta.ways' kind)
##   plan.out_t, plan.due_t, plan.back_t   the schedule in sim hours: set out, at the road, home
## Which roads: the surface ones SimConflict.route_targets weighs (coin a trip, the chance one
## passes, PINCH for a pass or a river crossing, distance), pulled up by the culture's `raids_up`
## (cultures.json; drow and goblinoids) and pushed down when the way is guarded.
##
## The surface answers an ambush from below: the raided caravan's town posts guards at the way
## the raiders used (sim.way_watch), soldiers out of its garrison for WATCH_DAYS. A raid from
## below that climbs or comes down a guarded way fights them at the mouth (SimCombat), and loot
## the guards win back goes to their town. Life shows the guards (LifeBelow), Deals the bounty
## (DealsQuests kind "below").
class_name SimBelow
extends RefCounted

## Days guards stay at a way after an ambush; another ambush through it renews them.
const WATCH_DAYS := 90
## Share of the town's soldiers posted, and the bounds.
const WATCH_SHARE := 0.15
const WATCH_MIN := 3
const WATCH_MAX := 12
## A road reached through a way held by guards hostile to the raiders weighs this much.
const GUARDED := 0.35
## Chance a raid from below runs into the watch at a guarded way (each way through it).
const WATCH_MEETS := 0.7

## Does this people climb to the surface to raid ("raids_up" in cultures.json, a pull: 1 none)?
static func pull(culture: String) -> float:
	return float((SimData.cultures.get(culture, {}) as Dictionary).get("raids_up", 1.0))

## The first link route on a path of site ids, or -1.
static func way_on(sim: WorldSim, path: Array) -> int:
	for i in path.size() - 1:
		var rid := sim.route_id(int(path[i]), int(path[i + 1]))
		if rid >= 0 and int(sim.route_by_id[rid].cls) == WorldSim.LINK:
			return rid
	return -1

## What kind of way a link is: meta.ways' kind, or "ascent" for worldgen's own ramp.
static func way_kind(sim: WorldSim, rid: int) -> String:
	return str((sim.route_by_id.get(rid, {}) as Dictionary).get("way", "ascent"))

## Is the way watched by guards of another faction?
static func guarded_against(sim: WorldSim, way: int, faction: int) -> bool:
	var w: Dictionary = sim.way_watch.get(way, {})
	return not w.is_empty() and int(w.n) > 0 and int(w.faction) != faction

## Weigh route candidates (SimConflict.route_targets rows) for a raid from a deep settlement: a
## surface road needs a way up on the path to it (rows gain it as a fourth element, the rest are
## dropped), weighs `pull` times more, and GUARDED as much through a guarded way. Deep roads are
## left as they are.
static func weigh(sim: WorldSim, s: SimSettlement, cands: Array, mask: int, dist: Dictionary) -> Array:
	var out: Array = []
	var up := pull(s.culture)
	for c: Array in cands:
		if c[0] != "route":
			out.append(c)
			continue
		var r: Dictionary = sim.route_by_id[c[1]]
		if int(r.cls) != WorldSim.ROAD:
			out.append(c)
			continue
		var near: int = r.a if dist.get(r.a, INF) <= dist.get(r.b, INF) else r.b
		var way := way_on(sim, sim.path_between(s.id, near, mask))
		if way < 0:
			continue
		var w: float = c[2] * up
		if guarded_against(sim, way, s.faction):
			w *= GUARDED
		out.append(["route", c[1], w, way])
	return out

## The surface roads a deep settlement's raiders could go for now, richest first, as
## {route, weight, way, crossings}: the same weights the sim draws from (for tools and tests).
static func targets(sim: WorldSim, s: SimSettlement, hungry := false) -> Array:
	var c := SimData.culture(s.culture)
	var mask := sim.mask_for(c.raid_mobility)
	var reach: float = WorldSim.REACH_DAYS.raid * WorldSim.DAY_H * WorldSim.SPEED.raid
	var dist: Dictionary = sim.paths_from(s.id, mask)[0]
	var out: Array = []
	for row: Array in weigh(sim, s, SimConflict.route_targets(sim, s, hungry, mask, dist, reach), mask, dist):
		if row.size() > 3:
			out.append({"route": row[1], "weight": row[2], "way": row[3], "crossings": sim.route_by_id[row[1]].get("crossings", [])})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.weight > b.weight or (a.weight == b.weight and a.route < b.route))
	return out

## Send a raid from below now (tests, tools and cheats; the sim's own raids go out through
## SimConflict._maybe_raid): n raiders from deep settlement s to wait on surface road rid, by the way
## on the path. Null when there is no way to it.
static func launch(sim: WorldSim, s: SimSettlement, rid: int, n := 8) -> SimParty:
	var c := SimData.culture(s.culture)
	var mask := sim.mask_for(c.raid_mobility)
	var r: Dictionary = sim.route_by_id.get(rid, {})
	if r.is_empty() or int(r.cls) != WorldSim.ROAD:
		return null
	var dist: Dictionary = sim.paths_from(s.id, mask)[0]
	var near: int = r.a if dist.get(r.a, INF) <= dist.get(r.b, INF) else r.b
	var far: int = r.b if near == r.a else r.a
	var path := sim.path_between(s.id, near, mask)
	var way := way_on(sim, path)
	if path.is_empty() or way < 0:
		return null
	var p := sim.new_party("raid", s.faction, s.culture, s.id, SimData.allocate(c.raiders, mini(n, maxi(s.soldiers, 1))))
	p.target = rid
	p.plan = {"mode": "route", "motive": "plunder"}
	path.append(far)
	p.path = path
	p.leg = 0
	p.frac = 0.0
	p.dest = far
	p.route = sim.route_id(path[0], path[1])
	p.state = "travel"
	s.soldiers = maxi(s.soldiers - p.size(), 0)
	s.out_raids += 1
	sim.stats_add("raids_sent", 1)
	mark(sim, p, way)
	return p

## Mark a raid party bound for a surface road as a raid from below and give it its schedule.
static func mark(sim: WorldSim, p: SimParty, way: int) -> void:
	p.plan["below"] = float(way)
	p.plan["way"] = way_kind(sim, way)
	var out_h := 0.0
	for i in p.path.size() - 1:
		var rid := sim.route_id(p.path[i], p.path[i + 1])
		if rid < 0:
			continue
		var h := sim.leg_hours(p.kind, rid)
		out_h += h * (0.5 if rid == p.target else 1.0)
	p.plan["out_t"] = float(sim.t)
	p.plan["due_t"] = float(sim.t) + out_h
	p.plan["back_t"] = float(sim.t) + out_h * 2.0 + SimConflict.AMBUSH_DAYS * WorldSim.DAY_H
	sim.stats_add("raids_below", 1)

static func is_below(p: SimParty) -> bool:
	return p != null and p.kind == "raid" and p.plan.has("below")

static func way_of(p: SimParty) -> int:
	return int(p.plan.get("below", -1.0))

## An ambush by raiders from below is over (SimConflict.ambush_outcome): count it, and the town
## the raided caravan came from posts guards at the way they used.
static func ambushed(sim: WorldSim, ra: SimParty, v: SimParty, won: bool, units: int, coin: int) -> void:
	sim.stats_add("below_ambushes", 1)
	if won:
		sim.stats_add("below_wins", 1)
		sim.stats_add("below_taken", units)
		sim.stats_add("below_coin_taken", coin)
	var way := way_of(ra)
	if not sim.route_by_id.has(way):
		return
	var sid := v.home
	if not sim.settlements.has(sid) or sim.settlements[sid].band != "surface":
		sid = surface_end(sim, way)
	if sim.settlements.has(sid):
		post_watch(sim, sid, way)

## The surface site of a link route.
static func surface_end(sim: WorldSim, way: int) -> int:
	var r: Dictionary = sim.route_by_id.get(way, {})
	if r.is_empty():
		return -1
	return int(r.a) if SimData.band_family(sim.site_by_id[r.a].band) == "surface" else int(r.b)

## The deep site of a link route.
static func deep_end(sim: WorldSim, way: int) -> int:
	var r: Dictionary = sim.route_by_id.get(way, {})
	if r.is_empty():
		return -1
	return int(r.b) if int(r.a) == surface_end(sim, way) else int(r.a)

## A town posts guards at a way (or renews the watch it has there): soldiers out of its
## garrison until the watch ends.
static func post_watch(sim: WorldSim, sid: int, way: int) -> void:
	var s: SimSettlement = sim.settlements[sid]
	var w: Dictionary = sim.way_watch.get(way, {})
	var until := float(sim.t + WATCH_DAYS * WorldSim.DAY_H)
	if not w.is_empty() and int(w.home) == sid and int(w.faction) == s.faction:
		w["until"] = maxf(float(w.until), until)
		return
	if not w.is_empty():
		return          # another town holds it
	var n := clampi(int(s.soldiers * WATCH_SHARE), WATCH_MIN, WATCH_MAX)
	if s.soldiers < n + 4:
		return
	s.soldiers -= n
	sim.way_watch[way] = {"home": sid, "faction": s.faction, "culture": s.culture, "n": n, "n0": n, "until": until, "since": float(sim.t)}
	sim.stats_add("way_watches", 1)
	sim.log_event("way_watched", {"site": s.name, "n": n, "way": sim.route_name(way), "wayid": way})

## Each econ tick: watches that ran out go home (what is left of them).
static func tick_watches(sim: WorldSim) -> void:
	for way: int in WorldSim._sorted_keys(sim.way_watch):
		var w: Dictionary = sim.way_watch[way]
		if float(w.until) > float(sim.t) and int(w.n) > 0 and sim.settlements.has(int(w.home)):
			continue
		sim.way_watch.erase(way)
		if sim.settlements.has(int(w.home)) and sim.settlements[int(w.home)].faction == int(w.faction):
			sim.settlements[int(w.home)].soldiers += int(w.n)
		elif int(w.n) > 0:
			sim.stats_add("scattered", int(w.n))

## Each party tick: a raid from below passing a guarded way meets the watch at the mouth, once on
## the way up and once on the way down.
static func tick_parties(sim: WorldSim) -> void:
	if sim.way_watch.is_empty():
		return
	for pid: int in WorldSim._sorted_keys(sim.parties):
		var p: SimParty = sim.parties.get(pid)
		if not is_below(p) or p.state != "travel" or p.frozen or p.held or p.watched:
			continue
		if not sim.way_watch.has(p.route):
			continue
		var leg := str(p.plan.get("leg", "out"))
		var key := "met_" + leg
		if p.plan.has(key):
			continue
		p.plan[key] = 1.0
		var w: Dictionary = sim.way_watch[p.route]
		if int(w.n) <= 0 or int(w.faction) == p.faction or sim.rng.randf() > WATCH_MEETS:
			continue
		_watch_fight(sim, p, w, p.route)

static func watch_members(w: Dictionary) -> Dictionary:
	var c: Dictionary = SimData.cultures.get(str(w.get("culture", "human")), SimData.cultures["human"])
	return SimData.allocate(c.escort, int(w.n))

static func _watch_fight(sim: WorldSim, p: SimParty, w: Dictionary, way: int) -> void:
	var guards := watch_members(w)
	var res := SimCombat.resolve(sim.rng, p.members, guards, {"a_break": 0.45, "b_break": 0.5, "b_ac": 1})
	var lost := SimConflict.party_losses(p, res.a_dead)
	var killed := 0
	for k: String in res.b_dead:
		killed += int(res.b_dead[k])
	w["n"] = maxi(int(w.n) - killed, 0)
	var won: bool = res.winner == "b" or p.size() == 0
	sim.stats_add("battles", 1)
	sim.stats_add("watch_fights", 1)
	var back := 0
	if won and sim.settlements.has(int(w.home)):
		# the guards take back what the raiders carry, into their town's stores
		var home: SimSettlement = sim.settlements[int(w.home)]
		for g: String in WorldSim._sorted_keys(p.cargo):
			home.stock[g] = float(home.stock.get(g, 0.0)) + float(p.cargo[g])
			back += int(p.cargo[g])
		p.cargo.clear()
		home.wealth += p.coin
		p.coin = 0.0
		sim.stats_add("watch_wins", 1)
		sim.stats_add("watch_recovered", back)
	SimConflict._rel_hit(sim, int(w.faction), p.faction, 5.0)
	sim.log_event("watch_fight", {"site": sim._site_label(int(w.home)), "raiders": SimConflict._adj(p.culture),
		"rfrom": SimConflict._home_name(sim, p), "way": sim.route_name(way), "won": won, "lost": lost, "killed": killed,
		"back": back, "leg": str(p.plan.get("leg", "out"))})
	if p.size() == 0:
		SimConflict._wiped(sim, p)
	elif won and str(p.plan.get("leg", "out")) == "out":
		SimEconomy._go_home(sim, p)

## A raid from below came home: what it carried is in the town's stores now (return_home did
## that); count it.
static func came_home(sim: WorldSim, p: SimParty) -> void:
	var units := 0
	for g: String in p.cargo:
		units += int(p.cargo[g])
	sim.stats_add("below_home", 1)
	sim.stats_add("below_goods_home", units)
	sim.stats_add("below_coin_home", int(p.coin))
	if units > 0 or p.coin >= 1.0:
		sim.log_event("raid_home", {"raiders": SimConflict._adj(p.culture), "site": sim._site_label(p.home), "goods": units,
			"coin": int(p.coin), "way": sim.route_name(way_of(p))})

## A guard at a watch fell in real time (Life). False if none was left.
static func watch_guard_killed(sim: WorldSim, way: int) -> bool:
	var w: Dictionary = sim.way_watch.get(way, {})
	if w.is_empty() or int(w.n) <= 0:
		return false
	w["n"] = int(w.n) - 1
	sim.stats_add("real_deaths", 1)
	return true

# ── save ──────────────────────────────────────────────────────────────────────

static func watch_to_dict(sim: WorldSim) -> Dictionary:
	var out := {}
	for k: int in sim.way_watch:
		out[str(k)] = (sim.way_watch[k] as Dictionary).duplicate()
	return out

static func watch_from_dict(sim: WorldSim, d: Dictionary) -> void:
	sim.way_watch.clear()
	for k: String in d:
		var w: Dictionary = d[k]
		sim.way_watch[int(k)] = {"home": int(w.home), "faction": int(w.faction), "culture": str(w.get("culture", "human")),
			"n": int(w.n), "n0": int(w.get("n0", w.n)), "until": float(w.until), "since": float(w.get("since", 0.0))}
