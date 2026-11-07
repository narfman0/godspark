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
	_worm(t)
	_bulette(t)

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

# --- burrowers -----------------------------------------------------------------------------------

## Stone, and two caverns in it: rows y0..y0+13 from xa0 to xa1 and from xb0 to xb1.
static func two_caverns(w: int, h: int, y0: int, xa0: int, xa1: int, xb0: int, xb1: int) -> TileWorld:
	var world := TileWorld.new(w, h, 4)
	var stone := TileDefs.id("stone")
	var wall := TileDefs.wall_id("stone_wall")
	for x in w:
		for y in h:
			var open := y >= y0 and y < y0 + 14 and ((x >= xa0 and x <= xa1) or (x >= xb0 and x <= xb1))
			world.set_fg(x, y, TileDefs.AIR if open else stone, true)
			world.set_bg(x, y, wall, true)
	return world

static func solid_count(world: TileWorld, r: Rect2i) -> int:
	var n := 0
	for x in range(r.position.x, r.end.x):
		for y in range(r.position.y, r.end.y):
			if world.is_solid(x, y):
				n += 1
	return n

static func drops_of(host: WorldHost, base: String) -> int:
	var items := host.system(HostSystem.ITEMS) as ItemsSystem
	var n := 0
	for id: int in items.drops.list:
		var d: Drops.Drop = items.drops.list[id]
		if String(d.item.get("base", "")) == base:
			n += Items.count(d.item)
	return n

## A purple worm wanders through the rock from one cavern to the next: the tiles it takes are gone
## for good, through the world's tile path, no more than its cap a minute, and paid out as rubble.
func _worm(t: TestLog) -> void:
	var world := two_caverns(256, 96, 40, 20, 70, 130, 180)
	var r := rig(world, 40, 40, "underdark")
	var host: WorldHost = r["host"]
	var ms: MonstersSystem = r["ms"]
	var cfg := MonsterBrain.cfg()
	var far0: float = cfg.get("far_tiles", 56.0)
	cfg["far_tiles"] = INF                # no one near: it lives on all the same (tests only)
	var e := ms.spawn("purple-worm", Vector2(60.5, 40.0), {"home": Vector2(60.5, 40.0)})
	t.check(e != null, "a purple worm")
	if e == null:
		cfg["far_tiles"] = far0
		return
	var b := e.brain as MonsterBrain
	t.check(b.burrow != null, "a burrower")
	t.eq(float(b.rec["dig"]), 0.0, "that digs through Burrow alone, not the planner")
	var rock := Rect2i(71, 40, 59, 14)
	var solid0 := solid_count(world, rock)
	host.outbox.clear()
	b.burrow.cap = 40
	b._wander_to = Vector2(155.5, 40.0)
	b._wander_at = 1.0e9
	b._enter(MonsterBrain.State.WANDER)
	for i in K.TICK_HZ * 55:
		host.tick()
	t.check(b.burrow.dug > 0, "it digs (%d tiles in 55 s)" % b.burrow.dug)
	t.check(b.burrow.dug <= 40, "no more than its cap in a minute (%d of 40)" % b.burrow.dug)
	t.check(b.burrow.capped > 0, "and waits on it")
	var gone := solid0 - solid_count(world, rock)
	var tiles := 0
	for ev: Dictionary in host.outbox:
		if int(ev.get("type", -1)) == WorldHost.Ev.TILE and int(ev.get("value", -1)) == TileDefs.AIR:
			tiles += 1
	t.eq(gone, b.burrow.dug, "every tile it took is gone from the rock (%d)" % gone)
	t.check(tiles >= b.burrow.dug, "each sent to clients as a tile change (%d)" % tiles)
	# at its own pace it reaches the far cavern: a tunnel joins the two, and stays
	b.burrow.cap = int(Burrow.row("purple-worm").get("cap_per_min", 240))
	var reached := false
	for i in K.TICK_HZ * 240:
		host.tick()
		if e.body.pos.x >= 131.0:
			reached = true
			break
	var data_cap := int(Burrow.row("purple-worm").get("cap_per_min", 240))
	print("  the worm: %d tiles dug, at %s, %s, capped %d times, rubble on the ground %d" % [b.burrow.dug, e.body.pos, "through" if reached else "not through",
		b.burrow.capped, drops_of(host, "tile:rubble")])
	t.check(reached, "its tunnel reaches the next cavern")
	var open_row := 0
	for x in range(71, 130):
		if not world.is_solid(x, floori(e.body.pos.y) + 2) or not world.is_solid(x, 41) or not world.is_solid(x, 42):
			open_row += 1
	t.check(open_row >= 50, "the tunnel is there behind it (%d of 59 columns open)" % open_row)
	t.check(drops_of(host, "tile:rubble") + b.burrow.owed_n >= b.burrow.dug - 1, "every tile owed as rubble (%d on the ground, %d owed, %d dug)" % [drops_of(host, "tile:rubble"), b.burrow.owed_n, b.burrow.dug])
	# nothing built gives way
	var w2 := two_caverns(128, 96, 40, 10, 40, 90, 120)
	for y in range(36, 60):
		w2.set_fg(41, y, TileDefs.id("dressed_stone"), true)
	var r2 := rig(w2, 20, 40, "underdark")
	var e2: HostEntity = (r2["ms"] as MonstersSystem).spawn("purple-worm", Vector2(30.5, 40.0), {})
	var b2 := e2.brain as MonsterBrain
	b2._wander_to = Vector2(100.5, 40.0)
	b2._wander_at = 1.0e9
	b2._enter(MonsterBrain.State.WANDER)
	var walled := 0
	for i in K.TICK_HZ * 20:
		(r2["host"] as WorldHost).tick()
	for y in range(36, 60):
		if w2.get_fg(41, y) == TileDefs.id("dressed_stone"):
			walled += 1
	t.eq(walled, 24, "a built wall stops it: it digs only natural ground")
	t.check(not Burrow.natural(TileDefs.id("bedrock")) and not Burrow.natural(TileDefs.id("water")) and Burrow.natural(TileDefs.id("stone"))
		and Burrow.natural(TileDefs.id("iron_ore")) and not Burrow.natural(TileDefs.id("timber")), "natural: stone and ore yes; bedrock, water, timber no")
	cfg["far_tiles"] = far0

## A bulette senses a walker on the cavern floor, goes down into the rock, along under it, and comes
## up beside it with its Deadly Leap.
func _bulette(t: TestLog) -> void:
	var world := cave(256, 96, 40)
	var r := rig(world, 40, 40, "caves")
	var host: WorldHost = r["host"]
	var ms: MonstersSystem = r["ms"]
	var combat: CombatSystem = r["combat"]
	combat.record = true
	var e := ms.spawn("bulette", Vector2(120.5, 40.0), {})
	var p := player(host, "prey", Vector2(150.5, 40.0))
	var b := e.brain as MonsterBrain
	t.check(b.burrow != null, "a bulette burrows")
	var leapt := false
	var under := false
	for i in K.TICK_HZ * 90:
		host.tick()
		if e.body.pos.y < 38.0:
			under = true
		if b.leaps > 0:
			leapt = true
			break
	print("  the bulette: %d tiles dug, %s, at %s, the prey at %s, %d leaps" % [b.burrow.dug, "went under" if under else "stayed up", e.body.pos, p.body.pos, b.leaps])
	t.check(b.burrow.dug > 0, "it digs (%d tiles)" % b.burrow.dug)
	t.check(under, "down under the floor")
	t.check(leapt, "and comes up at its prey with a leap")
	t.check(e.body.pos.distance_to(p.body.pos) < 6.0, "beside it (%.1f tiles)" % e.body.pos.distance_to(p.body.pos))
	var leap_swing := false
	for ev: Dictionary in combat.recorded:
		if int(ev.get("kind", -1)) == CombatCodec.Ev.SWING and String(ev.get("what", "")).contains("Deadly Leap"):
			leap_swing = true
	t.check(leap_swing, "its Deadly Leap")
	for i in K.TICK_HZ * 3:
		host.tick()
	var hit := false
	for ev: Dictionary in combat.recorded:
		if int(ev.get("src", 0)) == e.id and int(ev.get("dst", 0)) == p.id and int(ev.get("kind", -1)) in [CombatCodec.Ev.SAVE, CombatCodec.Ev.DAMAGE]:
			hit = true
	t.check(hit, "that lands on the prey (a save, damage)")
	t.check(b.burrow.dug <= int(Burrow.row("bulette").get("cap_per_min", 150)) * 2, "within its cap (%d)" % b.burrow.dug)
