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
