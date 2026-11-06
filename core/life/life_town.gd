## Settlements as people. When a player is near a sim settlement its guards (the real
## garrison, at most caps.guards shown: exactly garrison() when it is that small, else a
## largest-remainder sample of the culture's guard recipe) and a shown sample of its
## townsfolk (a number by tier, never more than its civilians; the first by tier are the
## keeper, smith, merchants and priest) appear at Places anchors, or spread over the site
## when the world has no places. They keep a daily round by the world clock. Deaths are
## written back at once (WorldSim.settlement_person_killed); every scan the shown people are
## reconciled with the sim (caravans take soldiers as escort, the town grows); past keep_tiles
## they fold back (removed: the sim still counts them). The sim's settlement is `watched`
## meanwhile, so raids arriving are fought here in real time.
class_name LifeTown
extends RefCounted

var life: LifeSystem
## site id -> {guards: {entity id: slug}, folk: {slot: entity id}, posts: {slot: {...}}, n0: ...}
var active := {}

func _init(l: LifeSystem) -> void:
	life = l

func scan(h: WorldHost, players: Array) -> void:
	var near := float(Life.people_cfg().get("near_tiles", 80.0))
	var keep := float(Life.people_cfg().get("keep_tiles", 112.0))
	for sid: int in active.keys():
		if not h.sim.settlements.has(sid) or LifeSystem.nearest(players, site_pos(h, sid)) > keep:
			fold(h, sid)
	for sid: int in WorldSim._sorted_keys(h.sim.settlements):
		if active.has(sid):
			reconcile(h, sid)
		elif not players.is_empty() and LifeSystem.nearest(players, site_pos(h, sid)) <= near:
			materialize(h, sid)

static func site_pos(h: WorldHost, sid: int) -> Vector2:
	var s: Dictionary = h.sim.site_by_id.get(sid, {})
	return Vector2(float(s.get("x", 0)) + 0.5, float(s.get("y", 0)))

func materialize(h: WorldHost, sid: int) -> void:
	var s: SimSettlement = h.sim.settlements[sid]
	active[sid] = {"guards": {}, "folk": {}, "posts": {}, "torch": false}
	s.watched = true
	life.stats["towns"] += 1
	reconcile(h, sid)

## Make the shown people match the sim again.
func reconcile(h: WorldHost, sid: int) -> void:
	var rec: Dictionary = active[sid]
	var s: SimSettlement = h.sim.settlements[sid]
	var cfg := Life.people_cfg()
	# guards
	var cap := int(cfg["caps"]["guards"])
	var want: Dictionary = s.garrison() if s.soldiers <= cap else SimData.allocate(SimData.culture(s.culture).guards, cap)
	var have := {}
	for id: int in (rec["guards"] as Dictionary).keys():
		var slug: String = rec["guards"][id]
		if int(have.get(slug, 0)) >= int(want.get(slug, 0)):
			rec["guards"].erase(id)        # off duty (the garrison shrank or went with a caravan)
			life.unspawn(h, id)
			continue
		have[slug] = int(have.get(slug, 0)) + 1
	var gi := 0
	for slug: String in WorldSim._sorted_keys(want):
		for i in int(want[slug]) - int(have.get(slug, 0)):
			_spawn_guard(h, sid, s, slug, (rec["guards"] as Dictionary).size() + gi)
			gi += 1
	# townsfolk
	var n := mini(int(cfg["townsfolk"].get(s.tier, 4)), s.workers + s.dependants)
	for slot: int in (rec["folk"] as Dictionary).keys():
		if slot >= n:
			life.unspawn(h, int(rec["folk"][slot]))
			rec["folk"].erase(slot)
	for slot in n:
		if not (rec["folk"] as Dictionary).has(slot):
			_spawn_folk(h, sid, s, slot)
	_round(h, sid)

func fold(h: WorldHost, sid: int) -> void:
	var rec: Dictionary = active.get(sid, {})
	active.erase(sid)
	if h.sim.settlements.has(sid):
		h.sim.settlements[sid].watched = false
	if rec.is_empty():
		return
	for id: int in (rec["guards"] as Dictionary).keys():
		life.unspawn(h, id)
	for slot: int in rec["folk"]:
		life.unspawn(h, int(rec["folk"][slot]))
	life.stats["folded"] += 1

# --- who and where --------------------------------------------------------------------------

## A townsperson for a slot: role, stat block, name, all from a hash of (world seed, site,
## slot, generation); a death bumps the slot's generation, so the next is someone new.
func folk_def(h: WorldHost, sid: int, s: SimSettlement, slot: int) -> Dictionary:
	var cfg := Life.people_cfg()
	var gen := life.generation("s%d:%d" % [sid, slot])
	var r := Life.rng_for([h.world.world_seed, "folk", sid, slot, gen])
	var firsts: Array = cfg["first_roles"].get(s.tier, [])
	var role := String(firsts[slot]) if slot < firsts.size() else "townsfolk"
	var c := SimData.culture(s.culture)
	var slug := String(cfg["role_slug"].get(role, ""))
	if slug == "" or bool(c.get("monstrous", false)) or not h.srd.pack.has_row("monster", slug):
		slug = String(c["people"])
	var given := SimNames.make(r, s.culture if SimData.names.has(s.culture) else "place", {})
	var female := r.randf() < 0.5
	return {"role": role, "slug": slug, "name": "%s the %s" % [given, role.capitalize()] if role != "townsfolk" else given,
		"female": female}

## Feet positions for a role at a site: Places anchors, or a spread over the site.
func _cells(h: WorldHost, sid: int, role: String) -> Array:
	return Places.anchors(h.world, sid, role)

func _has_places(h: WorldHost, sid: int) -> bool:
	return not Places.place(h.world, sid).is_empty()

## Where slot k of a role list stands; without places, spread around the site centre.
func _spot(h: WorldHost, sid: int, cells: Array, k: int, spread: float, slug: String) -> Vector2:
	var c: Vector2i = cells[k % cells.size()]
	var p := Vector2(c.x + 0.5, c.y)
	if not _has_places(h, sid) or cells.size() == 1:
		# spread over the site, keeping 24 tiles around its centre clear (the spawn point of a
		# spawn town, where joining players dig and build)
		var m := (k * 7) % 13 - 6
		var off := float(m) * spread / 6.0
		if absf(off) < 24.0:
			off += 24.0 * (1.0 if m >= 0 else -1.0)
		p.x += off
	var ms := life.monsters(h)
	if ms != null:
		var q := ms.director._stand_near(h, p + Vector2(0, 2), slug)
		if q != Vector2.INF:
			return q
	return p

func _spawn_guard(h: WorldHost, sid: int, s: SimSettlement, slug: String, k: int) -> void:
	var cells := _cells(h, sid, "guard")
	var pos := _spot(h, sid, cells, k, 14.0, slug)
	var r := Life.rng_for([h.world.world_seed, "guard", sid, k, life.generation("g%d" % sid)])
	var given := SimNames.make(r, s.culture if SimData.names.has(s.culture) else "place", {})
	var e := life.spawn_person(h, {"culture": s.culture, "slug": slug, "role": "guard", "pos": pos, "post": pos,
		"faction": s.faction, "sim": {"kind": "settlement", "id": sid, "role": "guard"}, "fighter": true,
		"name": "%s, guard of %s" % [given, s.name], "talk": true, "friendly": true, "span": 3.0})
	if e != null:
		active[sid]["guards"][e.id] = slug

func _spawn_folk(h: WorldHost, sid: int, s: SimSettlement, slot: int) -> void:
	var d := folk_def(h, sid, s, slot)
	var posts := _posts(h, sid, slot, d)
	var pos: Vector2 = posts[_phase(h)]
	var e := life.spawn_person(h, {"culture": s.culture, "slug": d["slug"], "role": d["role"], "pos": pos, "post": pos,
		"safe": posts["night"], "faction": s.faction, "sim": {"kind": "settlement", "id": sid, "role": d["role"], "slot": slot},
		"fighter": false, "name": d["name"], "talk": true, "friendly": true, "female": d["female"]})
	if e != null:
		active[sid]["folk"][slot] = e.id

## The three places of a person's day: work (its role's anchor; townsfolk the square), the
## square at dusk, its home door at night.
func _posts(h: WorldHost, sid: int, slot: int, d: Dictionary) -> Dictionary:
	var rec: Dictionary = active[sid]
	if (rec["posts"] as Dictionary).has(slot):
		return rec["posts"][slot]
	var role := String(d["role"])
	var slug := String(d["slug"])
	var homes: Array = []
	for b: Dictionary in Places.buildings(h.world, sid, "home"):
		if b.has("door"):
			homes.append(Vector2i(int(b["door"][0]), int(b["door"][1])))
	if homes.is_empty():
		homes = _cells(h, sid, "townsfolk")
	var square := _cells(h, sid, "townsfolk")
	var work := _cells(h, sid, role) if role != "townsfolk" else square
	var p := {"work": _spot(h, sid, work, slot, 18.0, slug), "dusk": _spot(h, sid, square, slot + 5, 10.0, slug),
		"night": _spot(h, sid, homes, slot + 11, 24.0, slug)}
	rec["posts"][slot] = p
	return p

static func _phase_at(hour: float) -> String:
	var hrs: Dictionary = Life.people_cfg().get("hours", {})
	var w: Array = hrs.get("work", [6.0, 18.0])
	var dk: Array = hrs.get("dusk", [18.0, 21.0])
	if hour >= float(w[0]) and hour < float(w[1]):
		return "work"
	if hour >= float(dk[0]) and hour < float(dk[1]):
		return "dusk"
	return "night"

func _phase(h: WorldHost) -> String:
	return _phase_at(h.clock.hour_of_day())

## The daily round: posts by the hour; guards carry torches at night.
func _round(h: WorldHost, sid: int) -> void:
	var rec: Dictionary = active[sid]
	var phase := _phase(h)
	for slot: int in rec["folk"]:
		var e := h.entity(int(rec["folk"][slot]))
		if e == null or not (e.brain is LifeBrain) or not (rec["posts"] as Dictionary).has(slot):
			continue
		var b: LifeBrain = e.brain
		b.post = rec["posts"][slot][phase]
		b.post_span = 2.0 if phase == "work" else (5.0 if phase == "dusk" else 0.8)
	var night := phase == "night"
	if night != bool(rec["torch"]):
		rec["torch"] = night
		for id: int in rec["guards"]:
			var g := h.entity(id)
			if g == null:
				continue
			if night:
				g.set_meta("torch", true)
				g.look["light"] = "torch"
			else:
				g.remove_meta("torch")
				g.look.erase("light")

## One of its people died: written back to the sim at once.
func died(h: WorldHost, sid: int, e: HostEntity, info: Dictionary) -> void:
	var rec: Dictionary = active.get(sid, {})
	var soldier := String(info.get("role", "")) == "guard"
	if not rec.is_empty():
		if soldier:
			(rec["guards"] as Dictionary).erase(e.id)
			life.bump("g%d" % sid)
		else:
			var slot := int(info.get("slot", -1))
			if int((rec["folk"] as Dictionary).get(slot, -1)) == e.id:
				rec["folk"].erase(slot)
				(rec["posts"] as Dictionary).erase(slot)
			life.bump("s%d:%d" % [sid, slot])
	if h.sim.settlement_person_killed(sid, soldier):
		life.stats["town_deaths"] += 1
		life.road.town_loss(sid, soldier)

func actors_at(h: WorldHost, sid: int) -> Array[HostEntity]:
	var out: Array[HostEntity] = []
	var rec: Dictionary = active.get(sid, {})
	if rec.is_empty():
		return out
	for id: int in rec["guards"]:
		if h.entity(id) != null:
			out.append(h.entity(id))
	for slot: int in rec["folk"]:
		if h.entity(int(rec["folk"][slot])) != null:
			out.append(h.entity(int(rec["folk"][slot])))
	return out
