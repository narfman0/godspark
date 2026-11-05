## Parties on the roads as people. When a player is near a sim party's position (route id and
## fraction, through the route's tile path, or a straight line between the sites when the
## world stored none) its members appear there (at most caps.party, a largest-remainder
## sample when bigger): escorts, raiders, guards or monsters as fighters, drovers and migrant
## families as civilians, caravans with up to caps.wagons draft horses as their wagons. Their
## post is the party's point, which the sim keeps moving at its own pace (lockstep: the sim
## stays the truth for position, so watching changes nothing); while its people fight, the
## party is held (`frozen`) and the sim waits. Abstract fights involving it are skipped while
## it is `watched`; the real ones are written back: each death at once
## (WorldSim.party_member_killed), and the outcome of an ambush or a raid on a watched
## settlement through the sim's own SimConflict.*_outcome (loot, relations, chronicle,
## who goes home). Raiders killed while carrying loot drop their share as items.
class_name LifeRoad
extends RefCounted

var life: LifeSystem
## party id -> {ids: {entity id: slug}, wagons: {entity id: true}, hold, arrival, raid, killers, slots}
var active := {}
## "ra:v" -> {ra, v, rid, nr, nv, fv, players: {}}: real-time ambushes being fought
var clashes := {}
var _paths := {}

func _init(l: LifeSystem) -> void:
	life = l

# --- where ---------------------------------------------------------------------------------

func route_cells(h: WorldHost, rid: int) -> Array:
	if not _paths.has(rid):
		_paths[rid] = Places.route_path(h.world, rid)
	return _paths[rid]

## A point t of the way along a route (0 at site a), interpolated along its path.
func route_pos(h: WorldHost, rid: int, t: float) -> Vector2:
	var path := route_cells(h, rid)
	if path.is_empty():
		return Vector2.INF
	if path.size() == 1:
		return Vector2(path[0].x + 0.5, path[0].y)
	var f := clampf(t, 0.0, 1.0) * (path.size() - 1)
	var i := mini(floori(f), path.size() - 2)
	var a: Vector2i = path[i]
	var b: Vector2i = path[i + 1]
	var u := f - i
	return Vector2(lerpf(a.x, b.x, u) + 0.5, roundf(lerpf(a.y, b.y, u)))

func party_pos(h: WorldHost, p: SimParty) -> Vector2:
	var pp := h.sim.party_position(p)
	if int(pp["route"]) >= 0:
		return route_pos(h, int(pp["route"]), float(pp["frac"]))
	return LifeTown.site_pos(h, int(pp["site"]))

## The party's point on the ground (the first floor below, or out of rock).
func ground(h: WorldHost, p: Vector2, slug := "") -> Vector2:
	var ms := life.monsters(h)
	if ms == null or p == Vector2.INF:
		return p
	var q := ms.director._stand_near(h, p + Vector2(0, 2), slug)
	return q if q != Vector2.INF else p

# --- scan ----------------------------------------------------------------------------------

func scan(h: WorldHost, players: Array) -> void:
	var cfg := Life.people_cfg()
	var near := float(cfg.get("near_tiles", 80.0))
	var keep := float(cfg.get("keep_tiles", 112.0))
	var sim := h.sim
	for pid: int in active.keys():
		var p: SimParty = sim.parties.get(pid)
		if p == null:
			if not _busy(pid):
				fold(h, pid)
			continue
		if LifeSystem.nearest(players, party_pos(h, p)) > keep:
			fold(h, pid)
	# a party the sim handed to real time that no one materialized: give it back
	for pid: int in sim.parties:
		var p: SimParty = sim.parties[pid]
		if p.frozen and not active.has(pid):
			var d := LifeSystem.nearest(players, party_pos(h, p))
			if d > keep:
				p.frozen = false
	if players.is_empty():
		return
	var x0 := INF
	var x1 := -INF
	for pl: HostEntity in players:
		x0 = minf(x0, pl.body.pos.x - keep)
		x1 = maxf(x1, pl.body.pos.x + keep)
	for p: SimParty in sim.entities_near(x0, x1)["parties"]:
		var pos := party_pos(h, p)
		if pos == Vector2.INF:
			continue
		var d := LifeSystem.nearest(players, pos)
		if active.has(p.id):
			reconcile(h, p)
		elif d <= near or (p.frozen and d <= keep):
			materialize(h, p)
	_resolve(h)

func materialize(h: WorldHost, p: SimParty) -> void:
	active[p.id] = {"ids": {}, "wagons": {}, "hold": false, "arrival": false, "raid": {}, "killers": {}, "slot": 0}
	p.watched = true
	life.stats["parties"] += 1
	reconcile(h, p)

## Party roles: fighters by kind; the culture's people block among `people` are civilians.
func roster(p: SimParty) -> Dictionary:
	var cap := int(Life.people_cfg()["caps"]["party"])
	var want: Dictionary = p.members.duplicate()
	if p.size() > cap:
		var recipe: Array = []
		for k: String in WorldSim._sorted_keys(p.members):
			recipe.append([k, float(p.members[k])])
		want = SimData.allocate(recipe, cap)
	return want

func reconcile(h: WorldHost, p: SimParty) -> void:
	var rec: Dictionary = active[p.id]
	var want := roster(p)
	var have := {}
	for id: int in (rec["ids"] as Dictionary).keys():
		var slug: String = rec["ids"][id]
		if int(have.get(slug, 0)) >= int(want.get(slug, 0)):
			rec["ids"].erase(id)
			life.unspawn(h, id)
			continue
		have[slug] = int(have.get(slug, 0)) + 1
	var point := ground(h, party_pos(h, p))
	if point == Vector2.INF:
		return
	var pslug := SimConflict.people_slug(p.culture)
	var civ_left := mini(p.people, int(p.members.get(pslug, 0)))
	for id: int in rec["ids"]:
		var e := h.entity(id)
		if e != null and e.brain is LifeBrain and not (e.brain as LifeBrain).fighter:
			civ_left -= 1
	for slug: String in WorldSim._sorted_keys(want):
		for i in int(want[slug]) - int(have.get(slug, 0)):
			var civ := slug == pslug and civ_left > 0 and p.kind != "pack"
			if civ:
				civ_left -= 1
			_spawn_member(h, p, slug, civ, point)
	if p.kind == "caravan":
		var nw := mini(p.wagons, int(Life.people_cfg()["caps"]["wagons"]))
		for id: int in (rec["wagons"] as Dictionary).keys():
			if (rec["wagons"] as Dictionary).size() <= nw:
				break
			rec["wagons"].erase(id)
			life.unspawn(h, id)
		while (rec["wagons"] as Dictionary).size() < nw:
			if not _spawn_wagon(h, p, point):
				break
	_posts(h, p, point)

func _slot_x(slot: int) -> float:
	return float((slot + 1) / 2) * 1.8 * (1.0 if slot % 2 == 1 else -1.0)

func _spawn_member(h: WorldHost, p: SimParty, slug: String, civ: bool, point: Vector2) -> void:
	var rec: Dictionary = active[p.id]
	var cfg := Life.people_cfg()
	var slot := int(rec["slot"])
	rec["slot"] = slot + 1
	var role := String(cfg["civilian_role"].get(p.kind, "drover")) if civ else String(cfg["party_role"].get(p.kind, "escort"))
	var pos := ground(h, point + Vector2(_slot_x(slot), 0), slug)
	var r := Life.rng_for([h.world.world_seed, "party", p.id, slot])
	var culture := p.culture if SimData.cultures.has(p.culture) else ""
	var given := SimNames.make(r, culture if SimData.names.has(culture) else "place", {}) if culture != "" else ""
	var opts := {"culture": culture, "slug": slug, "role": role, "pos": pos, "post": pos, "fighter": not civ,
		"faction": p.faction if p.kind != "pack" else -1, "sim": {"kind": "party", "id": p.id, "role": role, "party": p.kind},
		"talk": civ or p.kind in ["caravan", "patrol"], "friendly": p.kind in ["caravan", "migrants", "settlers", "patrol"],
		"name": given + (", " + role if given != "" else ""), "span": 3.0, "female": r.randf() < 0.5}
	var e := life.spawn_person(h, opts)
	if e != null:
		rec["ids"][e.id] = slug
		e.set_meta("slot", slot)

func _spawn_wagon(h: WorldHost, p: SimParty, point: Vector2) -> bool:
	var rec: Dictionary = active[p.id]
	var slug := String(Life.people_cfg().get("wagon", "draft-horse"))
	var slot := int(rec["slot"])
	rec["slot"] = slot + 1
	var pos := ground(h, point + Vector2(_slot_x(slot), 0), slug)
	var e := life.spawn_person(h, {"culture": "", "slug": slug, "role": "wagon", "pos": pos, "post": pos, "fighter": false,
		"faction": p.faction, "sim": {"kind": "party", "id": p.id, "role": "wagon", "party": p.kind},
		"talk": false, "friendly": true, "name": "Wagon of %s" % SimConflict._home_name(h.sim, p), "span": 1.0})
	if e == null:
		return false
	e.look["wagon"] = true
	e.set_meta("slot", slot)
	rec["wagons"][e.id] = true
	return true

## Every member's post follows the party's point (the sim moves it); far behind (a sleep,
## a jump of the clock): put back beside it.
func _posts(h: WorldHost, p: SimParty, point: Vector2) -> void:
	var rec: Dictionary = active[p.id]
	var combat := h.system(HostSystem.COMBAT)
	var dest := point
	if bool(rec["arrival"]):
		dest = LifeTown.site_pos(h, p.path[p.path.size() - 1])
	var ids: Array = (rec["ids"] as Dictionary).keys() + (rec["wagons"] as Dictionary).keys()
	for id: int in ids:
		var e := h.entity(id)
		if e == null or not (e.brain is LifeBrain):
			continue
		var b: LifeBrain = e.brain
		b.post = dest + Vector2(_slot_x(int(e.get_meta("slot", 0))), 0)
		var fighting: bool = combat != null and bool(combat.call("in_combat", e))
		if not fighting and e.body.pos.distance_to(b.post) > 40.0:
			var q := ground(h, b.post, String(e.look.get("slug", "")))
			if q != Vector2.INF:
				h.teleport(e, q)

func fold(h: WorldHost, pid: int) -> void:
	var rec: Dictionary = active.get(pid, {})
	active.erase(pid)
	var p: SimParty = h.sim.parties.get(pid)
	if p != null:
		p.watched = false
		if bool(rec.get("hold", false)) or bool(rec.get("arrival", false)):
			p.frozen = false        # the sim's own rules take over (an arrival fight resolves there)
		if p.size() == 0:
			SimConflict._after_fight(h.sim, p)
	for k: String in clashes.keys():
		if int(clashes[k]["ra"]) == pid or int(clashes[k]["v"]) == pid:
			_end_clash(h, k)
	if rec.is_empty():
		return
	for id: int in (rec["ids"] as Dictionary).keys() + (rec["wagons"] as Dictionary).keys():
		life.unspawn(h, id)
	life.stats["folded"] += 1

# --- fights --------------------------------------------------------------------------------

func _busy(pid: int) -> bool:
	for k: String in clashes:
		if int(clashes[k]["ra"]) == pid or int(clashes[k]["v"]) == pid:
			return true
	var rec: Dictionary = active.get(pid, {})
	return not rec.is_empty() and not (rec["raid"] as Dictionary).is_empty()

## Two parties' people came to blows (combat damage between them): with raiders on one side,
## a real-time ambush that ends by the sim's break rules.
func clash(h: WorldHost, pa: int, pb: int, by_player := 0) -> void:
	var sim := h.sim
	var a: SimParty = sim.parties.get(pa)
	var b: SimParty = sim.parties.get(pb)
	if a == null or b == null:
		return
	if b.kind == "raid" and a.kind != "raid":
		var t := a
		a = b
		b = t
	if a.kind != "raid":
		return
	var key := "%d:%d" % [a.id, b.id]
	if not clashes.has(key):
		clashes[key] = {"ra": a.id, "v": b.id, "rid": a.route, "nr": a.size(), "nv": b.size(),
			"fv": b.size() - b.people, "players": {}, "ra_obj": a, "v_obj": b}
		life.stats["clashes"] += 1
	if by_player != 0:
		clashes[key]["players"][by_player] = true

## A raid or pack the sim handed over on arrival at a watched settlement.
func _start_raid(h: WorldHost, p: SimParty, rec: Dictionary) -> void:
	var sid: int = p.path[p.path.size() - 1]
	var s: SimSettlement = h.sim.settlements.get(sid)
	rec["arrival"] = true
	rec["raid"] = {"site": sid, "n0": p.size(), "g0": s.soldiers if s != null else 0, "killed": 0, "soldiers": 0,
		"players": {}, "party": p}
	life.stats["raids"] += 1

func town_loss(sid: int, soldier: bool) -> void:
	for pid: int in active:
		var r: Dictionary = active[pid]["raid"]
		if not r.is_empty() and int(r["site"]) == sid:
			r["killed"] = int(r["killed"]) + 1
			if soldier:
				r["soldiers"] = int(r["soldiers"]) + 1

func _resolve(h: WorldHost) -> void:
	var sim := h.sim
	var brk: Dictionary = Life.people_cfg().get("break", {})
	var combat := h.system(HostSystem.COMBAT)
	# raids on watched settlements
	for pid: int in active.keys():
		var rec: Dictionary = active[pid]
		var p: SimParty = sim.parties.get(pid)
		if p != null and p.frozen and not bool(rec["hold"]) and not bool(rec["arrival"]):
			_start_raid(h, p, rec)
		var r: Dictionary = rec["raid"]
		if not r.is_empty():
			var party: SimParty = r["party"]
			var lost := int(r["n0"]) - party.size()
			var won := -1
			if party.size() == 0 or lost >= ceili(int(r["n0"]) * float(brk.get("raid_attackers", 0.4))):
				won = 0
			else:
				var s: SimSettlement = sim.settlements.get(int(r["site"]))
				if s == null or s.soldiers == 0 or int(r["soldiers"]) >= maxi(1, ceili(int(r["g0"]) * float(brk.get("raid_defenders", 0.35)))):
					won = 1
			if won >= 0:
				var s2: SimSettlement = sim.settlements.get(int(r["site"]))
				party.frozen = false
				rec["arrival"] = false
				rec["raid"] = {}
				if s2 != null:
					if party.kind == "pack":
						SimConflict.pack_outcome(sim, party, s2, won == 1, int(r["killed"]), lost)
					else:
						SimConflict.raid_outcome(sim, party, s2, won == 1, int(r["killed"]), lost)
					if won == 0:
						for pl: int in r["players"]:
							life.add_standing(pl, str(s2.faction), int(Life.num("repel_raid", 15)), "drove off a raid on " + s2.name)
				elif party.size() == 0:
					SimConflict._after_fight(sim, party)
				life.stats["raids_done"] += 1
		# hold the party while its people fight
		p = sim.parties.get(pid)
		if p == null:
			continue
		var fighting := false
		if combat != null:
			for id: int in rec["ids"]:
				var e := h.entity(id)
				# a foe in sight and blows exchanged (a fall does not count)
				if e != null and e.brain is MonsterBrain and (e.brain as MonsterBrain).target_id != 0 \
						and bool(combat.call("in_combat", e)):
					fighting = true
					break
		var want := fighting or _busy(pid)
		if want and not bool(rec["arrival"]):
			if not bool(rec["hold"]):
				life.stats["holds"] = int(life.stats.get("holds", 0)) + 1
				if life.debug:
					var foes := []
					for id: int in rec["ids"]:
						var e := h.entity(id)
						if e != null and e.brain is MonsterBrain and (e.brain as MonsterBrain).target_id != 0:
							var fo := h.entity((e.brain as MonsterBrain).target_id)
							if fo != null:
								foes.append("%s(%s) vs %s(%s)" % [e.name, Life.faction_of(e), fo.name, Life.faction_of(fo)])
					print("LIFE hold party %d (%s) fighting=%s %s" % [pid, p.kind, fighting, foes])
			p.frozen = true
			rec["hold"] = true
		elif bool(rec["hold"]) and not bool(rec["arrival"]):
			p.frozen = false
			rec["hold"] = false
		var point := ground(h, party_pos(h, p))
		if point != Vector2.INF:
			_posts(h, p, point)
	# ambushes fought in real time
	for k: String in clashes.keys():
		var c: Dictionary = clashes[k]
		var ra: SimParty = c["ra_obj"]
		var v: SimParty = c["v_obj"]
		var lost_r := int(c["nr"]) - ra.size()
		var lost_v := int(c["nv"]) - v.size()
		var won := -1
		if ra.size() == 0 or lost_r >= ceili(int(c["nr"]) * float(brk.get("ambush_attackers", 0.5))):
			won = 0
		elif v.size() - v.people <= 0 or lost_v >= ceili(int(c["nv"]) * float(brk.get("ambush_victims", 0.6))):
			won = 1
		if won < 0:
			continue
		clashes.erase(k)
		for pid: int in [ra.id, v.id]:
			if active.has(pid):
				active[pid]["hold"] = false
		ra.frozen = false
		v.frozen = false
		if v.kind in ["caravan", "migrants", "settlers"]:
			SimConflict.ambush_outcome(sim, ra, v, int(c["rid"]), [], won == 1, lost_r, lost_v)
		else:
			SimConflict._after_fight(sim, ra)
			SimConflict._after_fight(sim, v)
		life.stats["ambushes_done"] += 1
		if won == 0 and v.kind == "caravan":
			for pl: int in c["players"]:
				life.add_standing(pl, str(v.faction), int(Life.num("protect_caravan", 10)), "saved a caravan of " + SimConflict._home_name(sim, v))

func _end_clash(h: WorldHost, k: String) -> void:
	var c: Dictionary = clashes[k]
	clashes.erase(k)
	for p: SimParty in [c["ra_obj"], c["v_obj"]]:
		p.frozen = false
		if p.size() == 0:
			SimConflict._after_fight(h.sim, p)

## One of its people died: loot share dropped (raiders), then written back.
func died(h: WorldHost, pid: int, e: HostEntity, info: Dictionary, killers: Array) -> void:
	var rec: Dictionary = active.get(pid, {})
	var sim := h.sim
	var p: SimParty = sim.parties.get(pid)
	if not rec.is_empty():
		(rec["ids"] as Dictionary).erase(e.id)
		if (rec["wagons"] as Dictionary).has(e.id):
			rec["wagons"].erase(e.id)
			if p != null:
				p.wagons = maxi(0, p.wagons - 1)
			return
	if p == null:
		return
	var slug := String(e.look.get("slug", ""))
	if p.kind in ["raid", "army"] and (not p.cargo.is_empty() or p.coin >= 1.0):
		_drop_share(h, p, e.body.pos)
	var players: Array = killers.filter(func(id: int) -> bool: return h.entity(id) != null and h.entity(id).is_player())
	if not rec.is_empty():
		for pl: int in players:
			rec["killers"][pl] = true
			if not (rec["raid"] as Dictionary).is_empty():
				rec["raid"]["players"][pl] = true
	for k: String in clashes:
		if int(clashes[k]["ra"]) == pid or int(clashes[k]["v"]) == pid:
			for pl: int in players:
				clashes[k]["players"][pl] = true
	var keep := _busy(pid)
	if sim.party_member_killed(pid, slug, not keep):
		life.stats["party_deaths"] += 1
	# a raid wiped out on the road by players never happens
	if not sim.parties.has(pid) and p.kind == "raid" and not rec.is_empty() and not (rec["killers"] as Dictionary).is_empty():
		for f: int in _raid_victims(sim, p):
			for pl: int in rec["killers"]:
				life.add_standing(pl, str(f), int(Life.num("repel_raid", 15)), "stopped a raid")
		life.stats["raids_stopped"] += 1

## Factions a raid was going for: its target settlement's, or those at its target route's ends.
static func _raid_victims(sim: WorldSim, p: SimParty) -> Array:
	var out: Array = []
	var sites: Array = []
	if String(p.plan.get("mode", "")) == "route" and sim.route_by_id.has(p.target):
		sites = [int(sim.route_by_id[p.target].a), int(sim.route_by_id[p.target].b)]
	else:
		sites = [p.target]
	for sid: int in sites:
		if sim.settlements.has(sid) and sim.settlements[sid].faction != p.faction and not sim.settlements[sid].faction in out:
			out.append(sim.settlements[sid].faction)
	return out

## A raider falls with its share of the party's loot: goods and coin out of the sim's load,
## onto the ground (Items) as trade goods (or their worth in coin while Items has no rows
## for them).
func _drop_share(h: WorldHost, p: SimParty, pos: Vector2) -> void:
	var n := maxi(p.size(), 1)
	var items: Array = []
	for g: String in WorldSim._sorted_keys(p.cargo):
		var k := int(p.cargo[g]) / n if n > 1 else int(p.cargo[g])
		k = h.sim.party_take_cargo(p.id, g, k)
		if k > 0:
			items.append(LifeSystem.good_item(g, k))
	var c := int(p.coin) / n if n > 1 else int(p.coin)
	c = h.sim.party_take_cargo(p.id, "coin", c)
	if c > 0:
		items.append(Items.coin(c))
	life.stats["dropped"] += items.size()
	var it := h.system(HostSystem.ITEMS)
	if it != null and it.has_method("drop") and not items.is_empty():
		it.call("drop", pos + Vector2(0, 1), items, 0)

func actors_of(h: WorldHost, pid: int) -> Array[HostEntity]:
	var out: Array[HostEntity] = []
	var rec: Dictionary = active.get(pid, {})
	if rec.is_empty():
		return out
	for id: int in (rec["ids"] as Dictionary).keys() + (rec["wagons"] as Dictionary).keys():
		if h.entity(id) != null:
			out.append(h.entity(id))
	return out
