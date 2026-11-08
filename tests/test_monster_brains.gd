## Monster brains, ranks and affixes on small maps with seeded dice: each archetype's defining
## behaviour, pack alerts, leash, fleeing, neutral creatures and Bonds, rank hit points and
## meta, and every affix's effect.
extends RefCounted

const GROUND := 20

class FakeRules extends HostSystem:
	var bonds := {}
	func sys_id() -> int:
		return HostSystem.RULES
	func bond(id: int, key: String) -> int:
		return int(bonds.get(key, 0))

class FakeDrops extends RefCounted:
	var list := {}

class FakeItems extends HostSystem:
	var dropped: Array = []
	var drops := FakeDrops.new()
	func sys_id() -> int:
		return HostSystem.ITEMS
	func drop(pos: Vector2, items: Array, from := 0) -> void:
		dropped.append([pos, items, from])

func run(t: TestLog) -> void:
	_bruiser(t)
	_skirmisher(t)
	_archer(t)
	_lurker(t)
	_pack_alert(t)
	_leash(t)
	_flee(t)
	_neutral(t)
	_bond(t)
	_paths(t)
	_ranks(t)
	_affixes(t)
	_codec(t)
	_raiders(t)

static func world(w := 256, walls := []) -> TileWorld:
	var wd := TileWorld.new(w, 64, 1)
	var stone := TileDefs.id("stone")
	for x in w:
		for y in GROUND:
			wd.set_fg(x, y, stone, true)
	for c: Vector2i in walls:
		wd.set_fg(c.x, c.y, stone, true)
	return wd

static func rig(seed_value := 3, wd: TileWorld = null) -> Dictionary:
	var host := WorldHost.new(wd if wd != null else world())
	host.rng.seed = seed_value
	Dice.rng = host.rng
	var combat := CombatSystem.new()
	host.add_system(combat)
	var ms := MonstersSystem.new()
	host.add_system(ms)
	ms.director_enabled = 0
	return {"host": host, "combat": combat, "ms": ms}

static func hero(r: Dictionary, x := 60.5) -> HostEntity:
	var host: WorldHost = r["host"]
	var e := host.add_player("hero%d" % host.entities.size(), host.entities.size() + 2, {"class": "fighter"})
	e.body.pos = Vector2(x, GROUND)
	e.body.on_floor = true
	r["combat"].actor(e).takeoff_y = GROUND
	return e

static func ticks(r: Dictionary, n: int, f := Callable()) -> void:
	var host: WorldHost = r["host"]
	for i in n:
		host.tick()
		if f.is_valid():
			f.call(i)

func _bruiser(t: TestLog) -> void:
	var r := rig()
	var p := hero(r)
	var e: HostEntity = r["ms"].spawn("goblin-warrior", Vector2(75.5, GROUND), {"brain": "bruiser"})
	var b: MonsterBrain = e.brain
	ticks(r, 150)      # 15 tiles to close: 3.75 s at pace 4 (90 ticks did at the old pace)
	t.check(b.target_id == p.id, "a bruiser notices the player in daylight")
	t.check(absf(e.body.pos.x - p.body.pos.x) < 4.0, "and closes in (%.1f)" % absf(e.body.pos.x - p.body.pos.x))
	t.check(b.attacks > 0, "and attacks (%d)" % b.attacks)

func _skirmisher(t: TestLog) -> void:
	var r := rig(5)
	var p := hero(r)
	p.combatant.stats.max_hp = 500
	p.combatant.stats.current_hp = 500
	var e: HostEntity = r["ms"].spawn("wolf", Vector2(72.5, GROUND))
	var b: MonsterBrain = e.brain
	t.eq(b.archetype, "skirmisher", "a wolf is a skirmisher (ecology)")
	var after := []
	var att := [0]
	ticks(r, 240, func(i: int) -> void:
		if b.attacks > att[0] and not r["combat"].busy(e):
			att[0] = b.attacks
			after.append(absf(e.body.pos.x - p.body.pos.x)))
	t.check(b.attacks >= 1, "the wolf attacks (%d)" % b.attacks)
	# right after an attack it backs off: measure distance 0.6 s after its recovery
	var r2 := rig(5)
	var p2 := hero(r2)
	p2.combatant.stats.max_hp = 500
	p2.combatant.stats.current_hp = 500
	var w: HostEntity = r2["ms"].spawn("wolf", Vector2(72.5, GROUND))
	var wb: MonsterBrain = w.brain
	var seen := {"hit_d": -1.0, "max_d": 0.0, "done": false}
	ticks(r2, 300, func(i: int) -> void:
		if seen["done"]:
			return
		if wb.attacks > 0 and seen["hit_d"] < 0.0:
			seen["hit_d"] = absf(w.body.pos.x - p2.body.pos.x)
		elif seen["hit_d"] >= 0.0:
			seen["max_d"] = maxf(seen["max_d"], absf(w.body.pos.x - p2.body.pos.x))
			if seen["max_d"] > seen["hit_d"] + 3.0:
				seen["done"] = true)
	t.check(seen["max_d"] > seen["hit_d"] + 3.0, "a skirmisher retreats after hitting (%.1f -> %.1f)" % [seen["hit_d"], seen["max_d"]])

func _archer(t: TestLog) -> void:
	var r := rig(7)
	var p := hero(r)
	p.combatant.stats.max_hp = 500
	p.combatant.stats.current_hp = 500
	var e: HostEntity = r["ms"].spawn("goblin-warrior", Vector2(90.5, GROUND), {"brain": "archer"})
	var b: MonsterBrain = e.brain
	var minimum := [INF]
	ticks(r, 150, func(i: int) -> void: minimum[0] = minf(minimum[0], absf(e.body.pos.x - p.body.pos.x)))
	t.check(b.attacks > 0, "an archer shoots (%d)" % b.attacks)
	t.check(minimum[0] > 5.0, "and keeps its distance (closest %.1f)" % minimum[0])

func _lurker(t: TestLog) -> void:
	var r := rig(9)
	var p := hero(r, 40.5)
	var e: HostEntity = r["ms"].spawn("darkmantle", Vector2(52.5, GROUND))
	var b: MonsterBrain = e.brain
	t.eq(b.archetype, "lurker", "a darkmantle is a lurker")
	var x0 := e.body.pos.x
	ticks(r, 90)
	t.check(absf(e.body.pos.x - x0) < 0.5 and b.attacks == 0, "a lurker waits while prey is far (moved %.2f)" % absf(e.body.pos.x - x0))
	p.body.pos.x = 49.0
	ticks(r, 90)
	t.check(b.state == MonsterBrain.State.CHASE and b.attacks > 0, "and strikes when prey comes close (%d)" % b.attacks)

func _pack_alert(t: TestLog) -> void:
	var r := rig(11)
	var p := hero(r, 30.5)
	var ms: MonstersSystem = r["ms"]
	var pid := ms.new_pack()
	var a := ms.spawn("goblin-warrior", Vector2(60.5, GROUND), {"pack": pid, "slot": 0})
	var c := ms.spawn("goblin-warrior", Vector2(85.5, GROUND), {"pack": pid, "slot": 1})
	t.check(55.0 > float(MonsterBrain.cfg()["sight_tiles"]) and 55.0 > float(MonsterBrain.cfg()["hear_tiles"]), "the packmate is beyond sight and hearing")
	ticks(r, 30)
	t.check(a.brain.target_id == p.id, "the near goblin sees the player")
	t.check(c.brain.target_id == p.id, "and alerts its packmate")

func _leash(t: TestLog) -> void:
	var r := rig(13)
	var p := hero(r, 200.5)
	var e: HostEntity = r["ms"].spawn("goblin-warrior", Vector2(150.5, GROUND), {"home": Vector2(100.5, GROUND)})
	var b: MonsterBrain = e.brain
	b.target_id = p.id
	b.state = MonsterBrain.State.CHASE
	ticks(r, 10)
	t.eq(b.state, MonsterBrain.State.RETURN, "past its leash it goes home")
	ticks(r, 450)      # 50 tiles home: 12.5 s at pace 4 (200 ticks did at the old pace)
	t.check(absf(e.body.pos.x - 100.5) < 8.0, "and gets there (%.1f)" % e.body.pos.x)

func _flee(t: TestLog) -> void:
	var r := rig(15)
	var p := hero(r)
	p.combatant.stats.max_hp = 999
	p.combatant.stats.current_hp = 999
	var g: HostEntity = r["ms"].spawn("goblin-warrior", Vector2(70.5, GROUND))
	var s: HostEntity = r["ms"].spawn("skeleton", Vector2(50.5, GROUND))
	ticks(r, 20)
	g.combatant.stats.current_hp = 1
	s.combatant.stats.current_hp = 1
	var gx := absf(g.body.pos.x - p.body.pos.x)
	ticks(r, 75)
	t.eq(g.brain.state, MonsterBrain.State.FLEE, "a goblin flees at low HP")
	t.check(absf(g.body.pos.x - p.body.pos.x) > gx + 2.0, "and runs away")
	t.check(s.brain.state != MonsterBrain.State.FLEE, "a skeleton never flees")
	# once: as fast as the pursuer, a wounded runner that kept running could never be caught
	var fled := {"left": false, "again": false}
	for i in 450:
		ticks(r, 2)
		if g.brain.state != MonsterBrain.State.FLEE:
			fled["left"] = true
		elif fled["left"]:
			fled["again"] = true
	t.check(fled["left"], "the flight ends")
	t.check(not fled["again"], "and it does not run a second time")

func _neutral(t: TestLog) -> void:
	var r := rig(17)
	var p := hero(r)
	var e: HostEntity = r["ms"].spawn("deer", Vector2(68.5, GROUND))
	var b: MonsterBrain = e.brain
	t.check(e.has_meta("friendly"), "a neutral creature does not block rests (meta friendly)")
	ticks(r, 90)
	t.eq(b.target_id, 0, "a deer stays neutral near a player")
	r["combat"].damage(p.id, e, 1, "slashing")
	ticks(r, 5)
	t.eq(b.target_id, p.id, "until attacked")

func _bond(t: TestLog) -> void:
	var r := rig(19)
	var rules := FakeRules.new()
	r["host"].add_system(rules)
	var p := hero(r)
	var e: HostEntity = r["ms"].spawn("wolf", Vector2(70.5, GROUND))
	rules.bonds["beast:wolf"] = 1
	ticks(r, 60)
	t.eq(e.brain.target_id, 0, "a Bond with wolves keeps a wolf friendly")
	rules.bonds.clear()
	ticks(r, 30)
	t.eq(e.brain.target_id, p.id, "without it, the wolf hunts")

func _paths(t: TestLog) -> void:
	# a wall between: the monster must path (jump the step) instead of walking straight
	var walls := []
	for y in range(GROUND, GROUND + 4):
		walls.append(Vector2i(66, y))
	for x in range(66, 80):
		for y in range(GROUND, GROUND + 4):
			walls.append(Vector2i(x, y))
	var r := rig(21, world(256, walls))
	var p := hero(r, 72.5)
	p.body.pos.y = GROUND + 4
	p.combatant.stats.max_hp = 999
	p.combatant.stats.current_hp = 999
	var e: HostEntity = r["ms"].spawn("goblin-warrior", Vector2(50.5, GROUND), {"brain": "bruiser"})
	var got := [false]
	ticks(r, 240, func(i: int) -> void:
		if e.body.pos.y >= GROUND + 3.9 and e.body.on_floor and absf(e.body.pos.x - p.body.pos.x) < 4.0:
			got[0] = true)
	t.check(got[0], "a monster climbs onto a ledge to reach the player (at %s)" % e.body.pos)
	t.check(r["ms"].stats["plans"] > 0, "through the planner (%d plans)" % r["ms"].stats["plans"])

func _ranks(t: TestLog) -> void:
	var r := rig(23)
	var ms: MonstersSystem = r["ms"]
	var m := ms.spawn("ogre", Vector2(90.5, GROUND), {"rank": "minion"})
	t.eq(m.vitals(), Vector2i(1, 1), "a minion has 1 HP")
	t.eq(m.get_meta("xp_mult"), 0.25, "minion XP multiplier in meta")
	t.eq(m.look.get("rank"), "minion", "rank mirrored to look")
	var p := hero(r)
	r["combat"].damage(p.id, m, 1, "slashing")
	t.check(m.combatant.current_hp <= 0, "a minion dies to any hit that lands")
	var el := ms.spawn("ogre", Vector2(100.5, GROUND), {"rank": "elite"})
	t.eq(el.vitals().y, 8 * 10 + 24, "an elite ogre has the hit dice's maximum (8d10+24 = 104)")
	var ch := ms.spawn("ogre", Vector2(110.5, GROUND), {"rank": "champion", "affixes": ["frenzied", "gilded"]})
	t.eq(ch.vitals().y, 208, "a champion has double that")
	t.check(float(ch.look.get("scale", 1.0)) > 1.2, "and is visibly larger")
	t.check(String(ch.name).begins_with("Frenzied Gilded"), "its affixes are in its name (%s)" % ch.name)
	var st := ms.spawn("ogre", Vector2(120.5, GROUND))
	t.eq(st.vitals().y, 68, "a standard ogre is as written")
	t.eq(String(st.get_meta("rank")), "standard", "rank in meta")

func _affixes(t: TestLog) -> void:
	var r := rig(25)
	var ms: MonstersSystem = r["ms"]
	var combat: CombatSystem = r["combat"]
	var items := FakeItems.new()
	r["host"].add_system(items)
	var p := hero(r)
	p.combatant.stats.max_hp = 999
	p.combatant.stats.current_hp = 999
	# frenzied: a faster action, same wind-up
	var f := ms.spawn("goblin-warrior", Vector2(62.5, GROUND), {"affixes": ["frenzied"]})
	var g := ms.spawn("goblin-warrior", Vector2(58.5, GROUND))
	t.check(combat.actor(f).pace > 1.0, "frenzied sets combat's pace")
	combat.start_attack(f, -1, p.body.rect().get_center())
	combat.start_attack(g, -1, p.body.rect().get_center())
	t.check(float(combat.actor(f).seq["total"]) < float(combat.actor(g).seq["total"]), "a frenzied action is shorter")
	t.eq(combat.actor(f).seq["contacts"][0], combat.actor(g).seq["contacts"][0], "with the same readable wind-up")
	# shielded: a ward first, regrown out of combat
	var s := ms.spawn("goblin-warrior", Vector2(120.5, GROUND), {"affixes": ["shielded"]})
	var ward := s.combatant.stats.temp_hp
	t.check(ward >= 8, "shielded starts with a ward (%d)" % ward)
	combat.damage(p.id, s, 5, "slashing")
	t.eq(s.combatant.current_hp, 10, "the ward takes the hit")
	s.body.pos.x = 200.5
	s.brain = null          # keep it out of the fight; affixes still tick
	ticks(r, 30 * 14)
	t.eq(s.combatant.stats.temp_hp, ward, "and regrows out of combat")
	# gilded: coins on hit
	var gd := ms.spawn("goblin-warrior", Vector2(130.5, GROUND), {"affixes": ["gilded"]})
	combat.damage(p.id, gd, 2, "slashing")
	t.check(items.dropped.size() == 1 and String(items.dropped[0][1][0]["base"]) == "coin", "gilded sheds coin when hit")
	# thorned: the melee attacker is hurt
	var th := ms.spawn("goblin-warrior", Vector2(61.5, GROUND), {"affixes": ["thorned"]})
	var hp0 := p.combatant.current_hp
	combat.damage(p.id, th, 2, "slashing")
	t.check(p.combatant.current_hp < hp0, "thorned hurts its melee attacker")
	# tethered: half goes to a packmate
	var pid := ms.new_pack()
	var t1 := ms.spawn("ogre", Vector2(140.5, GROUND), {"affixes": ["tethered"], "pack": pid})
	var t2 := ms.spawn("ogre", Vector2(144.5, GROUND), {"pack": pid})
	combat.damage(p.id, t1, 20, "slashing")
	t.eq(t1.combatant.current_hp, 58, "tethered keeps half of a hit")
	t.eq(t2.combatant.current_hp, 58, "and its packmate takes the other half")
	# lantern-eater: torches near it go out
	var w: TileWorld = r["host"].world
	w.set_fg(150, GROUND + 1, TileDefs.id("torch"))
	ms.spawn("goblin-warrior", Vector2(152.5, GROUND), {"affixes": ["lantern_eater"]})
	ticks(r, 60)
	t.eq(w.get_fg(150, GROUND + 1), TileDefs.AIR, "a lantern-eater eats a torch")
	# magnetic: loot slides toward it
	var drop := {"pos": Vector2(170.5, GROUND), "vel": Vector2.ZERO, "rest": true}
	var d := Drops.Drop.new()
	d.pos = Vector2(170.5, GROUND)
	d.rest = true
	items.drops.list[1] = d
	ms.spawn("goblin-warrior", Vector2(176.5, GROUND), {"affixes": ["magnetic"]})
	ticks(r, 20)
	t.check(d.vel.x > 0.0 and not d.rest, "a magpie pulls loot toward itself")
	# splitting: two minions on death
	var sp := ms.spawn("ogre", Vector2(190.5, GROUND), {"affixes": ["splitting"]})
	var before := ms.mons.size()
	combat.damage(p.id, sp, 999, "slashing")
	ticks(r, 2)
	t.eq(ms.stats["split"], 2, "splitting leaves two")
	var kids := 0
	for id: int in ms.mons:
		var mb: MonsterBrain = ms.mons[id]
		if mb.slug == "ogre" and mb.rank == "minion":
			kids += 1
			t.eq(r["host"].entity(id).stats.size_name, "medium", "smaller than a Large ogre")
	t.eq(kids, 2, "minions of its kind")
	# tunnelling: its paths dig soft tiles
	var tu := ms.spawn("goblin-warrior", Vector2(220.5, GROUND), {"affixes": ["tunnelling"]})
	t.check(ms.profile_of(tu).dig > 0.0, "tunnelling digs (nav profile)")
	# skittering: runs faster
	var sk := ms.spawn("goblin-warrior", Vector2(230.5, GROUND), {"affixes": ["skittering"]})
	t.check(sk.stats.run_speed > MoveStats.pace() * 1.04, "skittering runs faster (%.1f)" % sk.stats.run_speed)
	# howling: more of its pack come when it sees prey (needs off-screen room)
	var r2 := rig(27, world(512))
	var p2 := hero(r2, 250.5)
	var hw: HostEntity = r2["ms"].spawn("wolf", Vector2(262.5, GROUND), {"affixes": ["howling"], "pack": r2["ms"].new_pack()})
	ticks(r2, 30)
	t.check(int(r2["ms"].stats["howls"]) >= 2, "a howler calls its pack (%d came)" % int(r2["ms"].stats["howls"]))
	t.check(r2["ms"].affix_pool("aboleth").size() < r2["ms"].affix_pool("wolf").size(), "the affix pool depends on the creature")

func _codec(t: TestLog) -> void:
	var infos := [{"id": 7, "rank": "champion", "slug": "wolf", "people": "", "scale": 1.3, "flags": 5, "affixes": ["frenzied", "gilded"]},
		{"id": 9, "rank": "minion", "slug": "bandit", "people": "elf:drow:raider", "scale": 1.0, "flags": 0, "affixes": []}]
	var back := MonstersCodec.read_info(MonstersCodec.write_info(infos))
	t.eq(back.size(), 2, "INFO round trip: count")
	t.eq(back[0]["rank"], "champion", "INFO: rank")
	t.eq(back[0]["affixes"], ["frenzied", "gilded"], "INFO: affixes")
	t.eq(back[1]["people"], "elf:drow:raider", "INFO: people")
	t.check(absf(float(back[0]["scale"]) - 1.3) < 0.01, "INFO: scale")
	var bad := MonstersCodec.write_info(infos).slice(0, 9)
	t.check(MonstersCodec.read_info(bad).size() <= 1, "INFO: truncated input is safe")
	t.eq(MonstersCodec.read_gone(MonstersCodec.write_gone([3, 4])), [3, 4], "GONE round trip")

func _raiders(t: TestLog) -> void:
	var r := rig(31)
	var ms: MonstersSystem = r["ms"]
	var cfg: Dictionary = Ecology.spawning()["raiders"]["drow"]
	var pack := ms.director.raider_pack(r["host"], "drow", cfg, 40.0)
	t.check(pack.size() >= 3, "a drow raider party (%d)" % pack.size())
	var names := []
	for m: Dictionary in pack:
		names.append(m.get("name", ""))
		t.check(String(m["people"]).begins_with("elf:drow:"), "people look key %s" % m["people"])
	t.check(String(names[0]).begins_with("Drow "), "NPCs from make_npc (%s)" % names[0])
	var e := ms.spawn(String(pack[0]["slug"]), Vector2(80.5, GROUND), pack[0])
	t.eq(String(e.look.get("people", "")), String(pack[0]["people"]), "the look carries people")
	t.eq(r["combat"].sight.darkvision_tiles(e), K.ft(120.0), "a drow sees 120 ft in the dark")
	t.eq(e.brain.bond_key, "people:drow", "a Bond with the drow makes them friendly")
