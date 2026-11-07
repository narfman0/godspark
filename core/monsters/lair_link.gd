## Lairs are real: when a player's interest area reaches a sim lair's site, exactly the
## creatures the sim says live there (SimLair.monsters, slug -> count) are spawned at the site
## as one pack (the largest leads; an apex lair's or a CR 5+ leader is a boss, in its lair: its
## Legendary Actions take the lair's count), with the site as
## their home. Kills are written back at once (WorldSim.lair_killed: the sim's own cleared-lair
## logic and chronicle line apply when it empties). While materialized the sim stays the truth:
## every second the spawned creatures are reconciled with its counts (a hunting pack left,
## the lair bred, another lair moved in). When no player is near, survivors fold back: they are
## simply removed, since the sim still counts them. Nothing extra is saved.
## Where each stands (docs/tracks/raids-below.md): a creature of the water (ecology medium water,
## the aboleth) in the nearest deep water; one that waits in the dark (brains.json dark_ambush) in the
## nearest spot of the light field's DARK; the rest at the site. A row's `charmed` members come out
## as people (make_npc, a species of the row's by a hash) Charmed by the leader and fighting for it.
class_name LairLink
extends RefCounted

## Tiles: a lair is materialized when a player is this close (x and y), kept until farther
## than KEEP.
const NEAR := 80.0
const KEEP := 112.0
const EVERY := 1.0

var sys: MonstersSystem
## site id -> {ids: {entity id: slug}, pack, kind}
var active := {}
var _t := 0.0
var stats := {"materialized": 0, "folded": 0, "kills": 0, "reconciled": 0}

func _init(s: MonstersSystem) -> void:
	sys = s

func tick(h: WorldHost, dt: float) -> void:
	_t += dt
	if _t < EVERY:
		return
	_t = 0.0
	var sim := h.sim
	var players: Array = []
	for p: HostEntity in h.entities.values():
		if p.is_player():
			players.append(p)
	# fold back lairs no one is near
	for sid: int in active.keys():
		var site := _site(h, sid)
		if site.is_empty() or _nearest(players, site) > KEEP:
			fold(h, sid)
	if players.is_empty():
		return
	for lid: int in WorldSim._sorted_keys(sim.lairs):
		var site := _site(h, lid)
		if site.is_empty():
			continue
		var d := _nearest(players, site)
		if active.has(lid):
			reconcile(h, lid)
		elif d <= NEAR:
			materialize(h, lid)

func _site(h: WorldHost, sid: int) -> Dictionary:
	var s: Variant = h.sim.site_by_id.get(sid)
	return s if s is Dictionary else {}

static func site_pos(site: Dictionary) -> Vector2:
	return Vector2(float(site["x"]) + 0.5, float(site.get("y", 0)))

static func _nearest(players: Array, site: Dictionary) -> float:
	var best := INF
	var sp := site_pos(site)
	for p: HostEntity in players:
		var d := p.body.pos - sp
		best = minf(best, maxf(absf(d.x), absf(d.y)))
	return best

## Spawn the lair's creatures (sim counts) at its site.
func materialize(h: WorldHost, lid: int) -> void:
	var l: SimLair = h.sim.lairs.get(lid)
	if l == null:
		return
	var site := _site(h, lid)
	var rec := {"ids": {}, "pack": sys.new_pack(), "kind": l.kind}
	active[lid] = rec
	stats["materialized"] += 1
	# the largest leads
	var lead := ""
	var best := -1.0
	for slug: String in _sorted(l.monsters):
		var cr := Ecology.cr_of(h.srd, slug)
		if cr > best:
			best = cr
			lead = slug
	var slot := 0
	for slug: String in _sorted(l.monsters):
		for i in int(l.monsters[slug]):
			_spawn_one(h, lid, l, site, slug, slug == lead and i == 0, slot)
			slot += 1

func _spawn_one(h: WorldHost, lid: int, l: SimLair, site: Dictionary, slug: String, leader: bool, slot: int) -> HostEntity:
	var rec: Dictionary = active[lid]
	var home := site_pos(site)
	var off := Vector2(((slot % 7) - 3) * 1.8, 0.0)
	var body := body_of(slug, String(site.get("biome", "")))
	var pos := Vector2.INF
	if String(Ecology.row(body).get("medium", "")) == "water":
		pos = water_near(h, home)
	elif body in (MonsterBrain.cfg().get("dark_ambush", []) as Array):
		pos = dark_near(h, home + off, body)
	var placed := pos != Vector2.INF          # its own spot is its home: the water, the dark
	if pos == Vector2.INF:
		pos = sys.director._stand_near(h, home + off + Vector2(0, 2), body)
	if pos == Vector2.INF:
		pos = home
	var rank := "standard"
	if leader and (l.apex or Ecology.cr_of(h.srd, slug) >= 5.0):
		rank = "boss"
	var opts := {"rank": rank, "pack": rec["pack"], "slot": slot, "home": pos if placed else home, "lair": lid, "leader": leader}
	var def := lair_def(l)
	var thrall := false
	for m: Variant in def.get("charmed", []):
		thrall = thrall or str(m[0]) == slug
	if thrall:
		var species: Array = def.get("species", ["human"])
		var sp := String(species[absi(hash([lid, slot, slug])) % species.size()])
		var npc: Variant = h.srd.call("make_npc", slug, sp, "") if h.srd.has_method("make_npc") else null
		if npc != null:
			opts["combatant"] = npc
		var culture := sp if SimData.cultures.has(sp) else ""
		if culture != "":
			opts["people"] = Life.people_key(culture, "guard", slug, hash([lid, slot]) % 2 == 0)
		var r := Life.rng_for([h.world.world_seed, "thrall", lid, slot])
		opts["name"] = "%s, thrall of %s" % [SimNames.make(r, culture if SimData.names.has(culture) else "place", {}), l.name]
	var e := sys.spawn(body, pos, opts)
	if e != null:
		rec["ids"][e.id] = slug
		if rank == "boss":
			e.set_meta("in_lair", true)          # its Legendary Actions take the lair's count
			rec["boss"] = e.id
		if thrall:
			rec["thralls"] = int(rec.get("thralls", 0)) + 1
			_charm(h, lid, e)
	return e

## A thrall is Charmed by the lair's leader (an effect with the leader as its source, so the leader
## knows it holds someone: CombatSystem.holds_any), and fights for it: one of its pack.
func _charm(h: WorldHost, lid: int, e: HostEntity) -> void:
	var boss := h.entity(int((active.get(lid, {}) as Dictionary).get("boss", 0)))
	if e.combatant == null:
		return
	var src := boss.combatant.name if boss != null and boss.combatant != null else "the lair"
	e.combatant.effects.add({"id": "thrall", "type": "condition", "condition": "charmed", "source": src, "of": e.combatant.name})
	e.set_meta("thrall", true)

## The lairs.json row of a lair, {} if gone from the table.
static func lair_def(l: SimLair) -> Dictionary:
	for d: Dictionary in SimData.lairs.get(l.family, []):
		if String(d.get("id", "")) == l.kind:
			return d
	return {}

## The bottom of the nearest deep water (two tiles or more) to p within 60 x 30 tiles: where a
## creature of the water waits. INF without any.
static func water_near(h: WorldHost, p: Vector2) -> Vector2:
	var water := TileDefs.id("water")
	var best := Vector2.INF
	var bd := INF
	var x0 := floori(p.x)
	var y0 := floori(p.y)
	for dx in range(-60, 61):
		var x := x0 + dx
		for y in range(maxi(y0 - 30, 1), y0 + 31):
			if h.world.get_fg(x, y) != water or h.world.get_fg(x, y + 1) != water or h.world.get_fg(x, y - 1) == water:
				continue
			var d := Vector2(x, y).distance_to(p)
			if d < bd:
				bd = d
				best = Vector2(x + 0.5, y)
	return best

## The nearest spot near p where the slug's body stands in the light field's DARK, INF without one.
func dark_near(h: WorldHost, p: Vector2, slug: String) -> Vector2:
	var combat := h.system(HostSystem.COMBAT) as CombatSystem
	if combat == null:
		return Vector2.INF
	for k in 13:
		var dx := float((k + 1) / 2) * 3.0 * (1.0 if k % 2 == 1 else -1.0)
		var at := sys.director._stand_near(h, p + Vector2(dx, 2.0), slug)
		if at != Vector2.INF and combat.sight.field_category(at + Vector2(0, 1)) == LightEngine.Category.DARK:
			return at
	return Vector2.INF

## What comes out of a lair for a creature the sim asked for: the sim picks by depth, not ground,
## so one that does not live in this biome comes as its kin (spawning.json lair_kin). rec["ids"]
## keeps the sim's slug: its ledger never sees the swap.
static func body_of(slug: String, biome: String) -> String:
	var kin: Dictionary = Ecology.spawning().get("lair_kin", {}).get(biome, {})
	return String(kin.get(slug, slug))

## Make the spawned creatures match the sim's counts again.
func reconcile(h: WorldHost, lid: int) -> void:
	var l: SimLair = h.sim.lairs.get(lid)
	if l == null:
		fold(h, lid)
		return
	var rec: Dictionary = active[lid]
	var alive := {}
	for id: int in rec["ids"]:
		var slug: String = rec["ids"][id]
		alive[slug] = int(alive.get(slug, 0)) + 1
	var site := _site(h, lid)
	for slug: String in _sorted(alive):
		var extra := int(alive[slug]) - int(l.monsters.get(slug, 0))
		if extra > 0:
			for id: int in (rec["ids"] as Dictionary).keys():
				if extra <= 0:
					break
				if rec["ids"][id] == slug:
					rec["ids"].erase(id)
					h.remove_entity(id)
					extra -= 1
					stats["reconciled"] += 1
	for slug: String in _sorted(l.monsters):
		var missing := int(l.monsters[slug]) - int(alive.get(slug, 0))
		for i in missing:
			_spawn_one(h, lid, l, site, slug, false, (rec["ids"] as Dictionary).size())
			stats["reconciled"] += 1

## Survivors go home: removed here, still counted by the sim.
func fold(h: WorldHost, lid: int) -> void:
	var rec: Dictionary = active.get(lid, {})
	active.erase(lid)
	if rec.is_empty():
		return
	for id: int in (rec["ids"] as Dictionary).keys():
		h.remove_entity(id)
	stats["folded"] += 1

## A lair creature died: one fewer in the sim.
func killed(e: HostEntity, b: MonsterBrain) -> void:
	var lid := int(b.rec["lair"])
	var rec: Dictionary = active.get(lid, {})
	var ledger := b.slug
	if not rec.is_empty():
		ledger = String((rec["ids"] as Dictionary).get(e.id, b.slug))
		(rec["ids"] as Dictionary).erase(e.id)
	var h := sys.host
	if h.sim != null and h.sim.lair_killed(lid, ledger):
		stats["kills"] += 1

func removed(e: HostEntity, b: MonsterBrain) -> void:
	var lid := int(b.rec["lair"])
	if lid >= 0 and active.has(lid):
		(active[lid]["ids"] as Dictionary).erase(e.id)

static func _sorted(d: Dictionary) -> Array:
	var k := d.keys()
	k.sort()
	return k
