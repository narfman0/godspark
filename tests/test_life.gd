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
