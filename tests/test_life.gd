## Life: stance (who fights whom), standing, settlements and parties materialized near
## players with their fights written back to the sim, per-entity dice.
extends RefCounted

class FakeRules extends HostSystem:
	var bonds := {}
	func sys_id() -> int:
		return HostSystem.RULES
	func bond(id: int, key: String) -> int:
		return int(bonds.get("%d:%s" % [id, key], 0))

static var _world: TileWorld

static func world() -> TileWorld:
	if _world == null:
		_world = WorldGen.generate(1024, 512, 4)
	return _world

static func rig(life := true, rules := false) -> Dictionary:
	var w := WorldGen.generate(1024, 512, 4)
	var host := WorldHost.new(w)
	Dice.rng = host.rng
	var out := {"host": host}
	if rules:
		out["rules"] = FakeRules.new()
		host.add_system(out["rules"])
	out["combat"] = CombatSystem.new()
	host.add_system(out["combat"])
	var ms := MonstersSystem.new()
	ms.director_enabled = 0
	ms.lairs_enabled = false
	host.add_system(ms)
	out["ms"] = ms
	if life:
		out["life"] = LifeSystem.new()
		host.add_system(out["life"])
	return out

static func put(host: WorldHost, name: String, pos: Vector2, tough := true) -> HostEntity:
	var e := host.add_player(name, host.entities.size() + 2, {"class": "fighter"})
	e.body.pos = pos
	TileCollision.depenetrate(host.world, e.body)
	if tough:
		e.combatant.stats.max_hp = 9999
		e.combatant.stats.current_hp = 9999
	return e

## The surface settlement nearest the middle of the world.
static func town_of(host: WorldHost) -> int:
	var best := -1
	var bd := INF
	for sid: int in WorldSim._sorted_keys(host.sim.settlements):
		var s: SimSettlement = host.sim.settlements[sid]
		if s.band != "surface":
			continue
		var d := absf(s.x - host.world.width / 2.0)
		if d < bd:
			bd = d
			best = sid
	return best

static func ticks(host: WorldHost, n: int) -> void:
	for i in n:
		host.tick()

func run(t: TestLog) -> void:
	for f: String in ["_stance", "_standing", "_town", "_roads", "_dice"]:
		if not has_method(f):
			continue
		var t0 := Time.get_ticks_msec()
		call(f, t)
		print("  %s: %d ms" % [f, Time.get_ticks_msec() - t0])

# --- 1. stance ---------------------------------------------------------------------------------

func _stance(t: TestLog) -> void:
	# without Life nothing changes
	var r0 := rig(false)
	var h0: WorldHost = r0["host"]
	var c0: CombatSystem = r0["combat"]
	var p0 := put(h0, "solo", h0.spawn)
	var g0: HostEntity = (r0["ms"] as MonstersSystem).spawn("goblin-warrior", h0.spawn + Vector2(4, 0))
	var g1: HostEntity = (r0["ms"] as MonstersSystem).spawn("guard", h0.spawn + Vector2(6, 0))
	t.check(c0.hostile(p0, g0) and c0.hostile(p0, g1) and not c0.hostile(g0, g1), "without Life: players vs monsters only")

	var r := rig(true, true)
	var host: WorldHost = r["host"]
	var life: LifeSystem = r["life"]
	var combat: CombatSystem = r["combat"]
	var ms: MonstersSystem = r["ms"]
	var sid := town_of(host)
	t.check(sid >= 0, "a surface town")
	var s: SimSettlement = host.sim.settlements[sid]
	var sp := LifeTown.site_pos(host, sid)
	var p := put(host, "visitor", sp + Vector2(0, 3))
	ticks(host, 70)
	var guards := life.actors_at(sid).filter(func(e: HostEntity) -> bool: return e.get_meta("sim")["role"] == "guard")
	t.check(not guards.is_empty(), "the town's guards are there (%d)" % guards.size())
	if guards.is_empty():
		return
	var guard: HostEntity = guards[0]
	t.eq(life.faction_of(guard), str(s.faction), "a guard carries its sim faction")
	t.eq(life.faction_of(p), "players", "players are players")
	t.eq(life.stance(p, guard), Life.NEUTRAL, "a stranger is neutral to the guards")
	t.check(not combat.hostile(p, guard), "combat asks Life: not a foe")
	# goblins attack guards and guards fight back
	var gob := ms.spawn("goblin-warrior", guard.body.pos + Vector2(5, 0))
	t.eq(life.faction_of(gob), "wild", "a spawned monster is wild")
	t.eq(life.stance(gob, guard), Life.HOSTILE, "goblin and guard are foes")
	var g_hp := guard.combatant.current_hp
	var b_hp := gob.combatant.current_hp
	var gob_id := gob.id
	for i in 900:
		host.tick()
		if host.entity(gob_id) == null or gob.combatant.current_hp < b_hp and guard.combatant.current_hp < g_hp:
			break
	t.check(host.entity(gob_id) == null or gob.combatant.current_hp < b_hp, "the guards hit the goblin")
	var gb := (gob.brain as MonsterBrain) if gob.brain != null else null
	t.check(gb == null or gb.attacks > 0 or host.entity(gob_id) == null or gob.combatant.current_hp <= 0, "the goblin attacked the guards")
	# good standing: ignored; bad standing: attacked
	life.add_standing(p.id, str(s.faction), 50, "test")
	t.eq(life.stance(p, guard), Life.FRIENDLY, "good standing: friendly")
	var hp := p.combatant.current_hp
	p.body.pos = guard.body.pos + Vector2(2, 0)
	ticks(host, 240)
	t.eq(p.combatant.current_hp, hp, "guards leave a friend alone")
	life.add_standing(p.id, str(s.faction), -150, "test")
	t.eq(life.standing(p.id, str(s.faction)), -100, "standing is clamped")
	t.eq(life.stance(p, guard), Life.HOSTILE, "bad standing: hostile")
	var hit := false
	for i in 900:
		p.body.pos = guard.body.pos + Vector2(2, 0)
		host.tick()
		if p.combatant.current_hp < hp:
			hit = true
			break
	t.check(hit, "guards attack a player with bad standing")
	life.add_standing(p.id, str(s.faction), 100, "test")
	# a raider party fights a caravan escort
	var fids: Array = WorldSim._sorted_keys(host.sim.factions)
	var fa: int = fids[0]
	var fb: int = fids[1] if fids.size() > 1 else fids[0]
	if fa != fb:
		(host.sim.factions[fa] as SimFaction).relations[fb] = -90.0
		(host.sim.factions[fb] as SimFaction).relations[fa] = -90.0
		var at := sp + Vector2(30, 3)
		var raider := life.spawn_person(host, {"culture": "human", "slug": "bandit", "role": "raider", "pos": at, "fighter": true,
			"faction": fa, "sim": {"kind": "party", "id": 99001, "role": "raider", "party": "raid"}})
		var escort := life.spawn_person(host, {"culture": "human", "slug": "guard", "role": "escort", "pos": at + Vector2(3, 0),
			"fighter": true, "faction": fb, "sim": {"kind": "party", "id": 99002, "role": "escort", "party": "caravan"}})
		t.eq(life.stance(raider, escort), Life.HOSTILE, "raiders and a caravan's escort are foes")
		var rh := raider.combatant.current_hp
		var eh := escort.combatant.current_hp
		for i in 900:
			host.tick()
			if raider.combatant.current_hp < rh and escort.combatant.current_hp < eh:
				break
		t.check(raider.combatant.current_hp < rh and escort.combatant.current_hp < eh, "they fight each other")
	# areas and sweeps spare neutral people; an aimed blow is allowed and makes enemies
	var folk := life.actors_at(sid).filter(func(e: HostEntity) -> bool: return e.get_meta("sim")["role"] != "guard")
	if not folk.is_empty():
		var f: HostEntity = folk[0]
		life.add_standing(p.id, str(s.faction), -int(life.standing(p.id, str(s.faction))), "reset")
		t.eq(life.stance(p, f), Life.NEUTRAL, "townsfolk are neutral to a stranger")
		var before := life.standing(p.id, str(s.faction))
		combat.damage(p.id, f, 1, "bludgeoning")
		t.eq(life.stance(p, f), Life.HOSTILE, "attacking one on purpose makes it hostile")
		t.eq(life.stance(p, guard), Life.HOSTILE, "and its faction's guards")
		t.check(life.standing(p.id, str(s.faction)) < before, "and costs standing")
	# wolves ignore a player with a strong enough wolf Bond
	var rules: FakeRules = r["rules"]
	var p2 := put(host, "friend-of-wolves", sp + Vector2(-60, 3))
	var wolf := ms.spawn("wolf", p2.body.pos + Vector2(6, 0))
	t.eq(life.stance(p2, wolf), Life.HOSTILE, "wolves are hostile without a Bond")
	rules.bonds["%d:beast:wolf" % p2.id] = 1
	life._cache.clear()
	t.eq(life.stance(p2, wolf), Life.FRIENDLY, "a wolf Bond makes them friendly")
	var hp2 := p2.combatant.current_hp
	ticks(host, 300)
	t.eq(p2.combatant.current_hp, hp2, "the wolf leaves its friend alone")

# --- 2. standing ---------------------------------------------------------------------------------

static func _life_msgs(host: WorldHost, to: int) -> Array:
	var out: Array = []
	for m: Dictionary in host.outbox:
		if int(m.get("type", -1)) == WorldHost.Ev.SYS and int(m["sys"]) == HostSystem.LIFE and (int(m["to"]) == to or int(m["to"]) == WorldHost.ALL):
			out.append(m)
	return out

func _standing(t: TestLog) -> void:
	var r := rig(true, true)
	var host: WorldHost = r["host"]
	var life: LifeSystem = r["life"]
	var combat: CombatSystem = r["combat"]
	var ms: MonstersSystem = r["ms"]
	var rules: FakeRules = r["rules"]
	var sid := town_of(host)
	var s: SimSettlement = host.sim.settlements[sid]
	var f := str(s.faction)
	var sp := LifeTown.site_pos(host, sid)
	var p := put(host, "hero", sp + Vector2(0, 3))
	host.outbox.clear()
	ticks(host, 70)
	t.eq(life.standing(p.id, f), 0, "standing starts at 0")
	# the client mirror: the factions table with names
	var lc := LifeClient.new()
	for m: Dictionary in _life_msgs(host, p.id):
		lc.handle(int(m["kind"]), m["data"])
	t.check(lc.factions.has(f) and String(lc.factions[f]["name"]) == host.sim.faction_name(s.faction), "the client knows the factions by name")
	t.check(not lc.people_at(sid).is_empty(), "and who the town's people are (%d)" % lc.people_at(sid).size())
	var seen := []
	lc.standing_changed.connect(func(fid: String, v: int, why: String) -> void: seen.append([fid, v, why]))
	# killing its enemies near its people: a gain
	var guards := life.actors_at(sid).filter(func(e: HostEntity) -> bool: return e.get_meta("sim")["role"] == "guard")
	var gob := ms.spawn("goblin-warrior", (guards[0] as HostEntity).body.pos + Vector2(3, 0) if not guards.is_empty() else sp)
	host.outbox.clear()
	combat.damage(p.id, gob, 9999, "force")
	ticks(host, 3)
	t.check(life.standing(p.id, f) > 0, "killing a goblin by its guards raises standing (%d)" % life.standing(p.id, f))
	for m: Dictionary in _life_msgs(host, p.id):
		lc.handle(int(m["kind"]), m["data"])
	t.check(not seen.is_empty() and seen[-1][0] == f and seen[-1][1] == life.standing(p.id, f), "the owner hears it: %s" % [seen])
	t.eq(lc.standing(f), life.standing(p.id, f), "the mirror matches")
	# killing its people: a large loss
	var folk := life.actors_at(sid).filter(func(e: HostEntity) -> bool: return e.get_meta("sim")["role"] != "guard")
	var before := life.standing(p.id, f)
	combat.damage(p.id, folk[0], 9999, "force")
	ticks(host, 3)
	t.check(life.standing(p.id, f) <= before - 20, "killing a townsperson costs dearly (%d -> %d)" % [before, life.standing(p.id, f)])
	var said := false
	for e: Dictionary in host.sim.chronicle:
		if e["kind"] == "slain_by_players":
			said = true
	t.check(said, "and the chronicle remembers it")
	# a Bond with the people sets a floor
	rules.bonds["%d:people:%s" % [p.id, s.culture]] = 1
	t.check(life.standing(p.id, f) >= int(Life.num("bond_floor", 30)), "a Bond sets a floor (%d)" % life.standing(p.id, f))
	rules.bonds.clear()
	# a lair that preyed on them
	if not host.sim.lairs.is_empty():
		var lid: int = WorldSim._sorted_keys(host.sim.lairs)[0]
		s.grievance[lid] = 5.0
		var l: SimLair = host.sim.lairs[lid]
		var slug: String = WorldSim._sorted_keys(l.monsters)[0]
		var m := ms.spawn(slug, sp + Vector2(-40, 3), {"lair": lid})
		var b2 := life.standing(p.id, f)
		combat.damage(p.id, m, 99999, "force")
		ticks(host, 3)
		t.check(life.standing(p.id, f) > b2, "killing a creature of a lair that preyed on them raises standing (%d -> %d)" % [b2, life.standing(p.id, f)])
	# add_standing for the Deals track, saved with the player
	life.add_standing(p.id, f, 7, "a deal")
	var saved := life.save_player(p)
	var v := life.standing(p.id, f)
	var life2 := LifeSystem.new()
	life2._host = weakref(host)
	life2.load_player(p, JSON.parse_string(JSON.stringify(saved)))
	t.eq(life2.standing(p.id, f), v, "standing survives a save and load (%d)" % v)

# --- 3. settlements ------------------------------------------------------------------------------

static func _roles(life: LifeSystem, sid: int) -> Dictionary:
	var out := {}
	for e: HostEntity in life.actors_at(sid):
		var r := String(e.get_meta("sim")["role"])
		out[r] = int(out.get(r, 0)) + 1
	return out

static func _guard_slugs(life: LifeSystem, sid: int) -> Dictionary:
	var out := {}
	for e: HostEntity in life.actors_at(sid):
		if e.get_meta("sim")["role"] == "guard":
			var sl := String(e.look["slug"])
			out[sl] = int(out.get(sl, 0)) + 1
	return out

func _town(t: TestLog) -> void:
	var r := rig()
	var host: WorldHost = r["host"]
	var life: LifeSystem = r["life"]
	var combat: CombatSystem = r["combat"]
	var sid := town_of(host)
	var s: SimSettlement = host.sim.settlements[sid]
	var sp := LifeTown.site_pos(host, sid)
	var p := put(host, "visitor", sp + Vector2(0, 3))
	t.check(not s.watched, "not watched before anyone comes")
	ticks(host, 70)
	t.check(life.town.active.has(sid) and s.watched, "the settlement materializes and is watched")
	var cap := int(Life.people_cfg()["caps"]["guards"])
	var want_g: Dictionary = s.garrison() if s.soldiers <= cap else SimData.allocate(SimData.culture(s.culture).guards, cap)
	t.eq(_guard_slugs(life, sid), want_g, "guards are the garrison (%d soldiers)" % s.soldiers)
	var n_folk := mini(int(Life.people_cfg()["townsfolk"][s.tier]), s.workers + s.dependants)
	var roles := _roles(life, sid)
	var folk := 0
	for k: String in roles:
		if k != "guard":
			folk += int(roles[k])
	t.eq(folk, n_folk, "a %s shows %d townsfolk" % [s.tier, n_folk])
	t.check(roles.has("keeper"), "with a keeper (%s)" % [roles])
	var any: HostEntity = life.actors_at(sid)[0]
	t.check(any.get_meta("talk", false) and any.get_meta("friendly", false) and String(any.get_meta("sim")["kind"]) == "settlement",
		"people carry sim, faction, talk and friendly meta")
	t.check(String(any.look.get("people", "")) != "" or bool(SimData.culture(s.culture).monstrous), "and a people look (%s)" % any.look.get("people", ""))
	# night: home, guards with torches
	host.sleep(fposmod(23.0 - host.clock.hour_of_day(), 24.0))
	ticks(host, 70)
	var torch := false
	for e: HostEntity in life.actors_at(sid):
		if e.get_meta("sim")["role"] == "guard" and e.has_meta("torch"):
			torch = true
	t.check(torch, "guards carry torches at night")
	var homes := true
	for e: HostEntity in life.actors_at(sid):
		if e.brain is LifeBrain and not (e.brain as LifeBrain).fighter:
			homes = homes and (e.brain as LifeBrain).post == (e.brain as LifeBrain).safe
	t.check(homes, "townsfolk head home at night")
	# conservation: kill two guards and a townsperson
	var soldiers0 := s.soldiers
	var civ0 := s.workers + s.dependants
	var killed_names := []
	var gk := 0
	var fk := 0
	for e: HostEntity in life.actors_at(sid):
		var role := String(e.get_meta("sim")["role"])
		if role == "guard" and gk < 2:
			combat.damage(p.id, e, 9999, "force")
			gk += 1
		elif role != "guard" and fk < 1:
			killed_names.append(e.name)
			combat.damage(p.id, e, 9999, "force")
			fk += 1
	ticks(host, 3)
	t.eq(s.soldiers, soldiers0 - 2, "two guards dead: the garrison is two smaller")
	t.eq(s.workers + s.dependants, civ0 - 1, "a townsperson dead: one fewer in the sim")
	# the townsfolk saw it
	var alarmed := 0
	for e: HostEntity in life.actors_at(sid):
		if e.brain is LifeBrain and not (e.brain as LifeBrain).fighter and (e.brain as LifeBrain).alarmed_until > 0.0:
			alarmed += 1
	t.check(alarmed > 0, "townsfolk nearby are alarmed (%d)" % alarmed)
	ticks(host, 200)
	# fold back and come again
	p.body.pos = sp + Vector2(400, 0)
	TileCollision.depenetrate(host.world, p.body)
	ticks(host, 70)
	t.check(not life.town.active.has(sid) and not s.watched, "folded back when the player left")
	t.eq(life.actors_at(sid).size(), 0, "no one left standing there")
	t.eq(s.soldiers, soldiers0 - 2, "fold-back keeps the garrison")
	t.eq(s.workers + s.dependants, civ0 - 1, "and the people")
	p.body.pos = sp + Vector2(0, 3)
	TileCollision.depenetrate(host.world, p.body)
	ticks(host, 70)
	want_g = s.garrison() if s.soldiers <= cap else SimData.allocate(SimData.culture(s.culture).guards, cap)
	t.eq(_guard_slugs(life, sid), want_g, "re-materialized guards match the sim (%d soldiers)" % s.soldiers)
	n_folk = mini(int(Life.people_cfg()["townsfolk"][s.tier]), s.workers + s.dependants)
	roles = _roles(life, sid)
	folk = 0
	for k: String in roles:
		if k != "guard":
			folk += int(roles[k])
	t.eq(folk, n_folk, "and the townsfolk")
	var back := false
	for e: HostEntity in life.actors_at(sid):
		if e.name in killed_names:
			back = true
	t.check(not back, "the dead do not come back (%s)" % [killed_names])
	t.eq(host.sim.audit(), [], "the sim's books are sound")

# --- 4. parties on the roads ------------------------------------------------------------------------

static func advance(host: WorldHost, hours: float) -> void:
	host.sleep(hours)
	var guard := 0
	while host.sim_behind() > 0 and guard < 2000:
		host.tick()
		guard += 1
	ticks(host, 65)

## A settlement next to sid by road (its caravans' reach), or -1.
static func neighbour(host: WorldHost, sid: int) -> int:
	for e: Array in host.sim.adj.get(sid, []):
		if host.sim.settlements.has(int(e[0])) and int(e[0]) != sid:
			return int(e[0])
	var best := -1
	for o: int in WorldSim._sorted_keys(host.sim.settlements):
		if o != sid and not host.sim.path_between(sid, o, WorldSim.ROAD | WorldSim.DEEP | WorldSim.LINK).is_empty():
			if best < 0 or absf(host.sim.settlements[o].x - host.sim.settlements[sid].x) < absf(host.sim.settlements[best].x - host.sim.settlements[sid].x):
				best = o
	return best

static func follow(host: WorldHost, life: LifeSystem, p: HostEntity, pid: int) -> void:
	var sp: SimParty = host.sim.parties.get(pid)
	if sp == null:
		return
	p.body.pos = life.road.ground(host, life.road.party_pos(host, sp)) + Vector2(0, 0.5)
	TileCollision.depenetrate(host.world, p.body)

func _roads(t: TestLog) -> void:
	# a) a watched caravan arrives exactly as an unwatched one
	var ra := rig()
	var rb := rig()
	var ha: WorldHost = ra["host"]
	var hb: WorldHost = rb["host"]
	var la: LifeSystem = ra["life"]
	var lb: LifeSystem = rb["life"]
	var sid := town_of(ha)
	var to := neighbour(ha, sid)
	t.check(to >= 0, "a neighbour town (%d -> %d)" % [sid, to])
	if to < 0:
		return
	var pa := la.cheat_party("caravan", sid, to, 0.93)
	var pb := lb.cheat_party("caravan", sid, to, 0.93)
	t.check(pa > 0 and pa == pb, "the same caravan on both")
	var p := put(ha, "watcher", ha.spawn)
	follow(ha, la, p, pa)
	ticks(ha, 65)
	ticks(hb, 65)
	t.check(la.road.active.has(pa) and ha.sim.parties[pa].watched, "the caravan materializes near the player")
	var acts := la.actors_of(pa)
	var wagons := acts.filter(func(e: HostEntity) -> bool: return e.look.get("wagon", false))
	t.check(acts.size() >= 3 and wagons.size() == 1, "escort, drovers and a wagon (%d actors)" % acts.size())
	var stock_a0: float = ha.sim.settlements[to].stock["food"]
	for k in 12:
		advance(ha, 6.0)
		advance(hb, 6.0)
		follow(ha, la, p, pa)
		if not ha.sim.parties.has(pa) or String(ha.sim.parties[pa].plan.get("leg", "")) == "home":
			break
	t.check(ha.sim.parties.has(pa) == false or String(ha.sim.parties[pa].plan.get("leg", "")) == "home", "it arrived")
	t.check(ha.sim.settlements[to].stock["food"] != stock_a0, "the market's food changed (%.1f -> %.1f)" % [stock_a0, ha.sim.settlements[to].stock["food"]])
	t.eq(ha.sim.settlements[to].stock, hb.sim.settlements[to].stock, "the stocks are exactly what an unwatched arrival makes")
	t.eq(ha.sim.settlements[to].wealth, hb.sim.settlements[to].wealth, "and the coin")
	t.check(ha.sim.to_dict().hash() == hb.sim.to_dict().hash(), "the whole sim is the same")

	# b) a raid intercepted and wiped out by players never happens
	var r := rig()
	var host: WorldHost = r["host"]
	var life: LifeSystem = r["life"]
	var combat: CombatSystem = r["combat"]
	var from := neighbour(host, sid)
	var rid := life.cheat_party("raid", from, sid, 0.5, 5)
	var hero := put(host, "hero", host.spawn)
	follow(host, life, hero, rid)
	ticks(host, 65)
	t.check(life.road.active.has(rid), "the raid materializes on the road")
	var f := str(host.sim.settlements[sid].faction)
	var st0 := life.standing(hero.id, f)
	var raid_events := 0
	for e: Dictionary in host.sim.chronicle:
		if e["kind"] == "raid":
			raid_events += 1
	for k in 10:
		for e: HostEntity in life.actors_of(rid):
			if e.combatant != null and e.combatant.current_hp > 0:
				combat.damage(hero.id, e, 9999, "force")
		ticks(host, 3)
		if not host.sim.parties.has(rid):
			break
		ticks(host, 62)
	t.check(not host.sim.parties.has(rid), "the raiders are gone from the sim")
	advance(host, 24.0)
	var raid_events2 := 0
	for e: Dictionary in host.sim.chronicle:
		if e["kind"] == "raid":
			raid_events2 += 1
	t.eq(raid_events2, raid_events, "the raid never happens")
	t.check(life.standing(hero.id, f) > st0, "standing with the town rises (%d -> %d)" % [st0, life.standing(hero.id, f)])
	t.eq(host.sim.audit(), [], "books sound")

	# c) a raid that wins at a watched town takes cargo in the sim
	var r2 := rig()
	var h2: WorldHost = r2["host"]
	var l2: LifeSystem = r2["life"]
	var c2: CombatSystem = r2["combat"]
	var town: SimSettlement = h2.sim.settlements[sid]
	var watcher := put(h2, "watcher", LifeTown.site_pos(h2, sid) + Vector2(0, 3))
	watcher.combatant.stats.max_hp = 9999
	ticks(h2, 65)
	town.stock["food"] = maxf(town.stock["food"], 500.0)
	var raid := l2.cheat_party("raid", from, sid, 0.999, 8)
	var food0: float = town.stock["food"]
	advance(h2, 6.0)
	t.check(h2.sim.parties.has(raid) and h2.sim.parties[raid].frozen, "the raid arrives and is handed to real time")
	t.check(l2.road.active.has(raid) and not (l2.road.active[raid]["raid"] as Dictionary).is_empty(), "Life fights it")
	var attacker := -1
	for e: HostEntity in l2.actors_of(raid):
		attacker = e.id
	for k in 40:
		if not h2.sim.parties.has(raid) or not h2.sim.parties[raid].frozen:
			break
		for e: HostEntity in l2.actors_at(sid):
			if e.get_meta("sim")["role"] == "guard" and e.combatant.current_hp > 0:
				c2.damage(attacker, e, 9999, "force")
		ticks(h2, 65)
	var won := false
	for e: Dictionary in h2.sim.chronicle:
		if e["kind"] == "raid" and bool(e["won"]):
			won = true
	t.check(won, "the raiders won (the chronicle says so)")
	t.check(h2.sim.parties.has(raid) and not h2.sim.parties[raid].cargo.is_empty(), "and carry the town's goods as cargo")
	t.check(town.stock["food"] < food0, "the town lost food (%.0f -> %.0f)" % [food0, town.stock["food"]])
	# players kill the laden raiders: the loot drops
	var dropped0: int = l2.stats["dropped"]
	for e: HostEntity in l2.actors_of(raid):
		if e.combatant != null and e.combatant.current_hp > 0:
			c2.damage(watcher.id, e, 9999, "force")
			break
	ticks(h2, 3)
	t.check(int(l2.stats["dropped"]) > dropped0, "a laden raider drops its share of the loot")
	t.eq(h2.sim.audit(), [], "books sound")

	# d) fold-back in the middle keeps position and losses; e) save and load in the middle
	var r3 := rig()
	var h3: WorldHost = r3["host"]
	var l3: LifeSystem = r3["life"]
	var c3: CombatSystem = r3["combat"]
	var cid := l3.cheat_party("caravan", sid, to, 0.4, 6)
	var w3 := put(h3, "w", h3.spawn)
	follow(h3, l3, w3, cid)
	ticks(h3, 65)
	var cp: SimParty = h3.sim.parties[cid]
	var n0 := cp.size()
	var victim: HostEntity = null
	for e: HostEntity in l3.actors_of(cid):
		if e.brain is LifeBrain and (e.brain as LifeBrain).fighter:
			victim = e
	c3.damage(w3.id, victim, 9999, "force")
	ticks(h3, 3)
	t.eq(cp.size(), n0 - 1, "a dead escort is one fewer in the sim")
	ticks(h3, 400)
	var frac := cp.frac
	var leg := cp.leg
	var size_mid := cp.size()
	# save and load the sim in the middle
	var saved: Variant = bytes_to_var(var_to_bytes(h3.sim.to_dict()))
	h3.sim = WorldSim.from_dict(saved)
	ticks(h3, 65)
	t.check(l3.road.active.has(cid) and h3.sim.parties[cid].watched, "after a load the caravan materializes again from the sim")
	t.eq(h3.sim.parties[cid].size(), size_mid, "with its losses")
	var shown := 0
	for e: HostEntity in l3.actors_of(cid):
		if not e.look.get("wagon", false):
			shown += 1
	t.eq(shown, mini(size_mid, int(Life.people_cfg()["caps"]["party"])), "and the same people shown")
	w3.body.pos += Vector2(500, 0)
	TileCollision.depenetrate(h3.world, w3.body)
	ticks(h3, 65)
	var cp2: SimParty = h3.sim.parties[cid]
	t.check(not l3.road.active.has(cid) and not cp2.watched and not cp2.frozen, "folded back")
	t.check(cp2.leg == leg and is_equal_approx(cp2.frac, frac), "at the same place on the road")
	t.eq(cp2.size(), size_mid, "with the same people")
	t.eq(l3.actors_of(cid).size(), 0, "and no actors left")
