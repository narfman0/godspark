## The deep life (docs/tracks/raids-below.md): lairs of the deeps as sim records that materialize,
## by depth and ground (the aboleth only in the deep lake, the purple worm only in the nadir, oozes
## in the wet and fungal deeps); the aboleth in its water with Legendary Actions and charmed
## servants; ropers and cloakers waiting unseen in the dark until a player passes; burrowers that
## really dig, within their cap, leaving rubble.
extends RefCounted

func run(t: TestLog) -> void:
	_tables(t)
	_aboleth(t)
	_roper(t)

# --- rigs ----------------------------------------------------------------------------------------

## A black cave (stone round an open band rows y0..y0+15), with a lake: a basin in its floor full of
## water, from x lake0 to lake1, `deep` rows deep. Sites: a deep settlement far off (the sim needs
## one) and the lair site.
static func cave(w: int, h: int, y0: int, lake0 := -1, lake1 := -1, deep := 6) -> TileWorld:
	var world := TileWorld.new(w, h, 3)
	var stone := TileDefs.id("stone")
	var water := TileDefs.id("water")
	var wall := TileDefs.wall_id("stone_wall")
	for x in w:
		for y in h:
			var open := x >= 4 and x < w - 4 and y >= y0 and y < y0 + 16
			var lake := x >= lake0 and x <= lake1 and y >= y0 - deep and y < y0
			world.set_fg(x, y, water if lake else (TileDefs.AIR if open else stone), true)
			world.set_bg(x, y, wall, true)
	return world

static func rig(world: TileWorld, lair_x: int, lair_y: int, biome: String) -> Dictionary:
	world.meta = {"bands": {"surface": [world.height - 10, world.height], "deeps": [0, world.height - 11]},
		"sites": [{"id": 0, "kind": "lair", "x": lair_x, "y": lair_y, "biome": biome, "band": "deeps", "size": 1},
			{"id": 1, "kind": "settlement", "x": world.width - 20, "y": lair_y, "biome": "underdark", "band": "deeps", "size": 1}],
		"routes": []}
	var host := WorldHost.new(world)
	Dice.rng = host.rng
	var out := {"host": host}
	var rules := RulesSystem.new()
	rules.cheats = true
	host.add_system(rules)
	out["combat"] = CombatSystem.new()
	host.add_system(out["combat"])
	host.add_system(ItemsSystem.new())
	var ms := MonstersSystem.new()
	ms.director_enabled = 0
	ms.nav_fixed_slices = 8
	host.add_system(ms)
	out["ms"] = ms
	host.sim.lairs.clear()
	return out

static func lair(sim: WorldSim, kind: String, monsters: Dictionary) -> SimLair:
	var l := SimLair.new()
	l.id = 0
	l.kind = kind
	l.family = "deeps"
	l.name = "Test " + kind
	l.apex = kind in ["aboleth", "purple_worm"]
	l.monsters = monsters.duplicate()
	l.max_n = 9
	l.hunger = 0.2
	l.x = float(sim.site_by_id[0].x)
	l.biome = String(sim.site_by_id[0].biome)
	sim.lairs[0] = l
	return l

static func player(host: WorldHost, name: String, pos: Vector2) -> HostEntity:
	var e := host.add_player(name, host.entities.size() + 2, {"class": "fighter"})
	e.body.pos = pos
	TileCollision.depenetrate(host.world, e.body)
	e.combatant.stats.max_hp = 9999
	e.combatant.stats.current_hp = 9999
	return e

static func of_lair(ms: MonstersSystem, slug: String) -> Array:
	var out: Array = []
	var rec: Dictionary = ms.lairs.active.get(0, {})
	for id: int in rec.get("ids", {}):
		if String(rec["ids"][id]) == slug and ms.host.entity(id) != null:
			out.append(ms.host.entity(id))
	return out

# --- the tables ----------------------------------------------------------------------------------

func _tables(t: TestLog) -> void:
	SimData.ensure()
	var rows := {}
	for fam: String in ["caves", "deeps"]:
		for d: Dictionary in SimData.lairs[fam]:
			rows[String(d["id"])] = d
	var lake := {"biome": "deep_lake", "band": "deeps"}
	var rock := {"biome": "underdark", "band": "deeps"}
	var fungal := {"biome": "fungal", "band": "deeps"}
	var nadir := {"biome": "magma", "band": "nadir"}
	t.check(WorldSim.lair_weight(rows["aboleth"], lake) > 0.0, "the aboleth lairs in the deep lake")
	t.eq(WorldSim.lair_weight(rows["aboleth"], rock), 0.0, "and nowhere else")
	t.check(WorldSim.lair_weight(rows["purple_worm"], nadir) > 0.0 and WorldSim.lair_weight(rows["purple_worm"], rock) == 0.0,
		"the purple worm (CR 15) only in the nadir")
	t.check(WorldSim.lair_weight(rows["puddings"], fungal) > WorldSim.lair_weight(rows["puddings"], rock), "oozes like the fungal wet")
	t.check(WorldSim.lair_weight(rows["oozes"], {"biome": "fungal", "band": "caves"}) > WorldSim.lair_weight(rows["oozes"], {"biome": "caves", "band": "caves"}),
		"in the caves too")
	t.check(rows.has("gricks") and rows.has("darkmantles") and rows.has("ropers") and rows.has("cloakers"), "grick and darkmantle packs, ropers, cloakers")
	# every member is an SRD block of the band's CR range, as the spawn director has them
	var bands: Dictionary = Ecology.spawning()["bands"]
	var srd := WorldHost.shared_srd()
	for id: String in ["ropers", "cloakers", "puddings", "aboleth", "gricks", "darkmantles", "oozes"]:
		var d: Dictionary = rows[id]
		var band := "caves" if (SimData.lairs["caves"] as Array).has(d) else "deeps"
		var cr: Array = bands[band]["any"]["cr"]
		var lead := 0.0
		for m: Array in d["members"]:
			t.check(srd.pack.has_row("monster", String(m[0])), "%s: %s is an SRD block" % [id, m[0]])
			lead = maxf(lead, Ecology.cr_of(srd, String(m[0])))
		t.check(lead >= float(cr[0]) and lead <= float(cr[1]), "%s leads with CR %s, in the %s's %s" % [id, lead, band, cr])
	# the sim draws an aboleth sea at a lake site and never at a plain one
	var sites := [{"id": 0, "kind": "lair", "x": 100, "y": 150, "biome": "deep_lake", "band": "deeps", "size": 1},
		{"id": 1, "kind": "lair", "x": 300, "y": 150, "biome": "underdark", "band": "deeps", "size": 1},
		{"id": 2, "kind": "settlement", "x": 500, "y": 150, "biome": "underdark", "band": "deeps", "size": 1}]
	var sim := WorldSim.new()
	sim._setup(sites, [], 5, 600.0)
	var at_lake := {}
	var at_rock := {}
	var thralls_ok := true
	for i in 300:
		sim.t += 1                  # a lair drawn again by the new rules draws on (seed, site, hour)
		var a := sim._spawn_lair(0, "deeps", false)
		at_lake[a.kind] = int(at_lake.get(a.kind, 0)) + 1
		if a.kind == "aboleth":
			var n := int(a.monsters.get("warrior-infantry", 0)) + int(a.monsters.get("scout", 0))
			thralls_ok = thralls_ok and n >= 2 and n <= 4 and int(a.monsters.get("aboleth", 0)) == 1
		var b := sim._spawn_lair(1, "deeps", false)
		at_rock[b.kind] = int(at_rock.get(b.kind, 0)) + 1
	print("  lairs at a lake site: %s; on plain rock: %s" % [at_lake, at_rock])
	t.check(int(at_lake.get("aboleth", 0)) > 0, "an aboleth sea at the lake (%d of 300)" % int(at_lake.get("aboleth", 0)))
	t.eq(int(at_rock.get("aboleth", 0)), 0, "none on rock")
	t.eq(int(at_rock.get("purple_worm", 0)) + int(at_lake.get("purple_worm", 0)), 0, "no purple worm above the nadir")
	t.check(thralls_ok, "each aboleth has 2 to 4 thralls")

# --- the aboleth in its lake ---------------------------------------------------------------------

func _aboleth(t: TestLog) -> void:
	var world := cave(256, 96, 40, 110, 150, 8)
	var r := rig(world, 128, 40, "deep_lake")
	var host: WorldHost = r["host"]
	var ms: MonstersSystem = r["ms"]
	var combat: CombatSystem = r["combat"]
	var l := lair(host.sim, "aboleth", {"aboleth": 1, "chuul": 1, "warrior-infantry": 2, "scout": 1})
	var p := player(host, "diver", Vector2(104, 41))
	for i in 40:
		host.tick()
	t.check(ms.lairs.active.has(0), "the lair materializes when a player comes near")
	var ab: Array = of_lair(ms, "aboleth")
	t.eq(ab.size(), 1, "the aboleth is there")
	if ab.is_empty():
		return
	var a: HostEntity = ab[0]
	t.eq(world.get_fg(floori(a.body.pos.x), floori(a.body.pos.y) + 1), TileDefs.id("water"), "in the water of the deep lake (%s)" % a.body.pos)
	t.eq(String(a.get_meta("rank", "")), "boss", "a boss")
	t.check(bool(a.get_meta("in_lair", false)), "in its lair")
	var c := a.combatant
	t.eq(MonsterActions.legendary_left(c, true), 4, "four Legendary Action uses in its lair")
	# the charmed servants
	var thralls: Array = []
	for id: int in ms.lairs.active[0]["ids"]:
		var e := host.entity(id)
		if e != null and bool(e.get_meta("thrall", false)):
			thralls.append(e)
	t.eq(thralls.size(), 3, "its three thralls, as the sim counts them")
	var charmed := 0
	for e: HostEntity in thralls:
		if e.combatant.conditions.has(SRD.Condition.CHARMED):
			charmed += 1
	t.eq(charmed, thralls.size(), "every one Charmed")
	t.check(thralls.all(func(e: HostEntity) -> bool: return e.name.contains("thrall of")), "named for it (%s)" % [thralls.map(func(e: HostEntity) -> String: return e.name)])
	t.check(thralls.all(func(e: HostEntity) -> bool: return e.combatant.effects.of_type("condition").any(func(x: Dictionary) -> bool: return String(x.get("source", "")) == c.name)),
		"by the aboleth")
	t.check(thralls.all(func(e: HostEntity) -> bool: return (e.brain as MonsterBrain).pack_id == (a.brain as MonsterBrain).pack_id), "fighting in its pack")
	t.check(not thralls.is_empty() and String(thralls[0].look.get("people", "")) != "", "drawn as people (%s)" % (thralls[0].look.get("people", "") if not thralls.is_empty() else ""))
	t.check(combat.holds_any(a), "it holds someone Charmed")
	# Legendary Actions between its own: Lash at a foe in reach, Psychic Drain when hurt
	p.body.pos = a.body.pos + Vector2(-4.0, 0.0)
	TileCollision.depenetrate(world, p.body)
	var act := combat.actor(a)
	act.action_ready = combat.now + 5.0
	act.seq = {}
	var ok := combat.legendary(a, p)
	t.check(ok, "with its action spent, it takes a Legendary Action at the diver")
	t.eq(MonsterActions.legendary_left(c, true), 3, "one use spent")
	t.check(not combat.legendary(a, p), "not again at once (gap and the swing)")
	act.seq = {}
	act.legendary_ready = 0.0
	c.stats.current_hp = c.stats.max_hp - 30
	var hp := c.current_hp
	var swings := int(combat.counts.get("legendary", 0))
	t.check(combat.legendary(a, p), "hurt, another")
	t.check(c.current_hp > hp, "Psychic Drain first: it regains hit points (%d -> %d)" % [hp, c.current_hp])
	t.eq(int(combat.counts.get("legendary", 0)), swings + 1, "counted")
	act.seq = {}
	act.legendary_ready = 0.0
	combat.legendary(a, p)
	act.seq = {}
	act.legendary_ready = 0.0
	combat.legendary(a, p)
	act.seq = {}
	act.legendary_ready = 0.0
	t.check(not combat.legendary(a, p), "four uses in its lair, then none")
	act.round_at = combat.now
	combat._round(act)
	t.eq(MonsterActions.legendary_left(c, true), 4, "all back at the start of its round")
	# a thrall killed is one fewer in the sim
	var n0 := int(l.monsters.get("warrior-infantry", 0)) + int(l.monsters.get("scout", 0))
	combat.damage(p.id, thralls[0], 9999, SRD.DamageType.SLASHING)
	for i in 10:
		host.tick()
	t.eq(int(l.monsters.get("warrior-infantry", 0)) + int(l.monsters.get("scout", 0)), n0 - 1, "a thrall killed is written back")

# --- ropers in the dark --------------------------------------------------------------------------

func _roper(t: TestLog) -> void:
	var world := cave(256, 96, 40)
	var r := rig(world, 100, 40, "underdark")
	var host: WorldHost = r["host"]
	var ms: MonstersSystem = r["ms"]
	var combat: CombatSystem = r["combat"]
	lair(host.sim, "ropers", {"roper": 1})
	var p := player(host, "walker", Vector2(150, 41))
	for i in 60:
		host.tick()
	var ropers: Array = of_lair(ms, "roper")
	t.eq(ropers.size(), 1, "a roper in its gallery")
	if ropers.is_empty():
		return
	var ro: HostEntity = ropers[0]
	var b := ro.brain as MonsterBrain
	t.eq(combat.sight.field_category(ro.body.rect().get_center()), LightEngine.Category.DARK, "where the light field is DARK")
	t.eq(b.state, MonsterBrain.State.LURK, "it waits")
	t.check(combat.is_hidden(ro) and ro.combatant.conditions.has(SRD.Condition.INVISIBLE), "unseen: hidden, the SRD's Invisible")
	t.check(not combat.sight.can_see(p, ro), "the walker does not see it, torch and all")
	# walking past, ten tiles off: it still waits
	p.body.pos = ro.body.pos + Vector2(12.0, 0.0)
	TileCollision.depenetrate(world, p.body)
	for i in 30:
		host.tick()
	t.eq(b.state, MonsterBrain.State.LURK, "twelve tiles off, it still waits")
	# into its reach: it springs
	p.body.pos = ro.body.pos + Vector2(3.0, 0.0)
	TileCollision.depenetrate(world, p.body)
	var hp0 := p.combatant.current_hp
	var sprang := false
	for i in K.TICK_HZ * 6:
		host.tick()
		if b.attacks > 0:
			sprang = true
	t.check(sprang, "a player passing within reach: it attacks (%d attacks)" % b.attacks)
	t.check(b.state != MonsterBrain.State.LURK, "no longer waiting")
	t.check(not combat.is_hidden(ro), "and seen once it has struck")
	print("  the roper: %d attacks, the walker %d -> %d HP" % [b.attacks, hp0, p.combatant.current_hp])
	# light by a waiting roper: seen
	var world2 := cave(256, 96, 40)
	var r2 := rig(world2, 100, 40, "underdark")
	var host2: WorldHost = r2["host"]
	var c2: CombatSystem = r2["combat"]
	lair(host2.sim, "ropers", {"roper": 1})
	player(host2, "far", Vector2(170, 41))
	for i in 40:
		host2.tick()
	var lit_ropers: Array = of_lair(r2["ms"], "roper")
	t.check(lit_ropers.size() == 1 and c2.is_hidden(lit_ropers[0]), "another roper waits hidden")
	if lit_ropers.size() == 1:
		var at: Vector2 = lit_ropers[0].body.pos
		world2.set_fg(floori(at.x) + 2, floori(at.y), TileDefs.id("torch"))
		for i in 20:
			host2.tick()
		t.check(c2.sight.field_category(lit_ropers[0].body.rect().get_center()) != LightEngine.Category.DARK, "a torch set down beside it lights it")
		t.check(not c2.is_hidden(lit_ropers[0]), "and it is seen")
