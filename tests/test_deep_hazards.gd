## The deep lake and the lava (M6 track deep, item 2): a player swims the lake and climbs out
## on the far beach; deep water is a wall to a walker's nav and open to a swimmer's; lava is a
## wall to every body's nav and burns what touches it through CombatSystem, SRD fire damage
## (data/combat.json lava), so fire immunity holds. docs/tracks/deep.md.
extends RefCounted

const Combat := preload("res://tests/test_combat.gd")
const Ev := CombatCodec.Ev

func run(t: TestLog) -> void:
	_swim_the_lake(t)
	_nav_water(t)
	_nav_lava(t)
	_chase_at_lava(t)
	_sunlight(t)
	_burn(t)

## The real controller from the west beach into the water, across it holding right and jump
## (stroke at the surface), and out up the east beach.
func _swim_the_lake(t: TestLog) -> void:
	var w := WorldGen.generate_named("dev", 2)
	var lk: Dictionary = w.meta["descent"]["lake"]
	if lk.is_empty():
		t.check(false, "dev seed 2 has a lake")
		return
	var st := MoveStats.player()
	var b := st.make_body()
	var water := int(lk["water"])
	b.pos = Vector2(float(lk["x0"]) + 3.5, water + 5)
	TileCollision.update_contacts(w, b)
	var inp := PlayerInput.new()
	var dt := 1.0 / MoveStats.step_hz()
	var swam := 0.0
	var deepest := b.pos.y
	var out := false
	var steps := 0
	for i in MoveStats.step_hz() * 240:
		steps = i
		inp.move_x = 1.0
		inp.jump = b.swimming
		inp.jump_pressed = false
		PlayerController.step(w, b, inp, st, dt)
		if b.swimming:
			swam += dt
		deepest = minf(deepest, b.pos.y)
		if b.pos.x >= float(lk["x1"]) - 3.0 and b.on_floor and not b.swimming:
			out = true
			break
	t.check(swam > 5.0, "the body swims the lake (%.1f s in the water)" % swam)
	t.check(deepest < water, "it went into the water (lowest feet row %.1f, water at %d)" % [deepest, water])
	t.check(out, "and climbs out on the east beach (%s after %.1f s)" % [b.pos, steps * dt])
	t.check(b.pos.y >= water + 4.9, "standing on the beach above the water (%.1f)" % b.pos.y)

func _nav_water(t: TestLog) -> void:
	var pool := NavMaps.build([
		"S..................G",
		"####~~~~~~~~~~~~####",
		"####~~~~~~~~~~~~####",
		"####~~~~~~~~~~~~####",
		"####################"])
	var walker := NavMaps.run(pool, NavMaps.stats("medium"), 900)
	t.check(not walker["reached"], "a walker with no swim speed does not cross deep water (%s)" % walker["why"])
	var prof := MonsterNav.profile(NavMaps.stats("medium"))
	t.check(not prof.swimmer, "a plain walker is no swimmer")
	var s := MonsterNav.start(pool["world"], prof, pool["start"], Vector2(14.5, 9.0), Vector2i(1, 1), false)
	while not s.step(10000):
		pass
	t.check(s.result() == null, "nor plans to the bottom of the pool")
	var otter := NavMaps.stats("medium", {"walk": 30, "swim": 30})
	t.check(MonsterNav.profile(otter).swimmer, "a swim speed makes a swimmer")
	var across := NavMaps.build([
		"S...................",
		"####~~~~~~~~~~~~####",
		"####~~~~~~~~~~~~####",
		"####~~~~~~~~~~G~####",
		"####################"])
	var r := NavMaps.run(across, otter, 1200)
	t.check(r["reached"], "a swimmer crosses it to the far side's bottom (%s)" % r["why"])
	var wet := 0
	if r["path"] != null:
		for n: Vector2i in (r["path"] as NavPath).nodes:
			if (across["world"] as TileWorld).get_liquid(n.x + 1, n.y + 1) & 15 >= 8:
				wet += 1
	t.check(wet > 3, "through the water (%d nodes in it)" % wet)
	var puddle := NavMaps.build([
		"S..................G",
		"####~~~~~~~~~~~~####",
		"####################"])
	t.check(NavMaps.run(puddle, NavMaps.stats("medium"), 900)["reached"], "a walker wades water a row deep")

## A monster close and level with its prey does not walk straight into the lava between them
## (MonsterBrain's direct chase): the line over a pool is clear, the walk is not.
func _chase_at_lava(t: TestLog) -> void:
	var m := NavMaps.build([
		"..........................",
		"..........................",
		"..S.........G.............",
		"#####LLLLLLL##############",
		"##########################"])
	var world: TileWorld = m["world"]
	var host := WorldHost.new(world)
	var combat := CombatSystem.new()
	host.add_system(combat)
	var ms := MonstersSystem.new()
	ms.director_enabled = 0
	ms.lairs_enabled = false
	ms.nav_fixed_slices = 8
	host.add_system(ms)
	var p := host.add_player("prey", 2)
	host.teleport(p, Vector2(m["goal"]))
	var e := ms.spawn("goblin-warrior", Vector2(m["start"]))
	t.check(e != null, "a goblin to chase with")
	if e == null:
		return
	var burnt := false
	for k in 300:
		p.body.pos = Vector2(m["goal"])
		host.tick()
		burnt = burnt or CombatSystem.touches_lava(world, e.body)
	t.check(not burnt, "it never steps into the lava (ended at %s)" % e.body.pos)

## Sunlight Sensitivity is read off the stat block, and takes Disadvantage in sunlight: a kobold
## warrior by day on open ground, not at night, not underground. No drow lineage has it in 5.2.1.
func _sunlight(t: TestLog) -> void:
	var world := TileWorld.new(128, 128)
	for x in 128:
		for y in 40:
			world.set_fg(x, y, TileDefs.id("stone"), true)
	var host := WorldHost.new(world)
	var combat := CombatSystem.new()
	host.add_system(combat)
	var ms := MonstersSystem.new()
	ms.director_enabled = 0
	ms.lairs_enabled = false
	host.add_system(ms)
	var kobold := ms.spawn("kobold-warrior", Vector2(30.5, 40.0))
	var orc := ms.spawn("goblin-warrior", Vector2(34.5, 40.0))
	t.check(combat.sight.sun_shy(kobold), "a kobold warrior has Sunlight Sensitivity")
	t.check(not combat.sight.sun_shy(orc), "a goblin warrior does not")
	for slug: String in ["drider", "specter", "wight", "wraith"]:
		var row: Dictionary = host.srd.pack.get_row("monster", slug)
		t.check(str(row).contains("Sunlight Sensitivity"), "%s's block has it" % slug)
	host.clock.ticks = 12 * WorldClock.TICKS_PER_HOUR
	var noon := combat.sight.in_sunlight(Vector2(30.5, 41.0))
	t.check(noon, "open ground at noon is sunlight")
	t.check(not combat.sight.in_sunlight(Vector2(30.5, 20.0)), "solid rock is not")
	host.clock.ticks = 0
	t.check(not combat.sight.in_sunlight(Vector2(30.5, 41.0)), "nor midnight")
	host.clock.ticks = 12 * WorldClock.TICKS_PER_HOUR
	var opts := {}
	combat._sight_opts(combat.actors[kobold.id], combat.actors[orc.id], opts)
	t.check(bool(opts.get("disadvantage", false)), "a kobold warrior swinging at noon has Disadvantage")
	opts = {}
	combat._sight_opts(combat.actors[orc.id], combat.actors[kobold.id], opts)
	t.check(not bool(opts.get("disadvantage", false)), "a goblin warrior beside it does not")

func _nav_lava(t: TestLog) -> void:
	var f := MonsterNav.cell_flags(NavMaps.build(["L"])["world"], NavMaps.OX, NavMaps.OY)
	t.check(f & MonsterNav.HAZARD != 0 and f & MonsterNav.SOLID == 0, "lava is a hazard, not a floor")
	var wide := NavMaps.build([
		"S..............................G",
		"######LLLLLLLLLLLLLLLLLLLL######",
		"######LLLLLLLLLLLLLLLLLLLL######",
		"################################"])
	for st: MoveStats in [NavMaps.stats("medium"), NavMaps.stats("medium", {"walk": 30, "swim": 30}), NavMaps.stats("large", {"walk": 40, "climb": 30})]:
		var r := NavMaps.run(wide, st, 900)
		t.check(not r["reached"], "%s %s: no way over lava wider than a jump (%s)" % [st.size_name, st.walk, r["why"]])
	var bridged := NavMaps.build([
		"S..............G",
		"################",
		"####LLLLLLLL####",
		"################"])
	var rb := NavMaps.run(bridged, NavMaps.stats("medium"), 900)
	t.check(rb["reached"], "a bridge over it is walked (%s)" % rb["why"])
	var narrow := NavMaps.build([
		"S.........G",
		"####LL#####",
		"####LL#####",
		"###########"])
	var rn := NavMaps.run(narrow, NavMaps.stats("medium"), 900)
	t.check(rn["reached"], "a walker jumps a pool two wide (%s)" % rn["why"])
	var w: TileWorld = narrow["world"]
	var prof := MonsterNav.profile(NavMaps.stats("medium"))
	var inside := 0
	if rn["path"] != null:
		for n: Vector2i in (rn["path"] as NavPath).nodes:
			for cy in range(n.y, n.y + prof.ch):
				for cx in range(n.x, n.x + prof.cw):
					if TileDefs.burn[w.get_fg(cx, cy)] != 0:
						inside += 1
	t.eq(inside, 0, "and no node of its path stands in the lava")

## A body in lava takes 2d6 fire at once and again each round it stays; a fire elemental takes
## none; out of it, no more.
func _burn(t: TestLog) -> void:
	var world := Combat.flat_world()
	var lava := TileDefs.id("lava")
	for x in range(56, 66):
		world.set_fg(x, Combat.GROUND, lava, true)
	var r := Combat.rig(81, world)
	var h := Combat.hero(r, "fighter", 5)
	var hp := h.combatant.current_hp
	t.check(CombatSystem.touches_lava(world, h.body), "the hero's box touches the lava")
	Combat.ticks(r, 1)
	var dmg := Combat.evs(r, Ev.DAMAGE, 0, h.id)
	t.eq(dmg.size(), 1, "lava burns at once")
	if dmg.size() == 1:
		t.check(int(dmg[0]["amount"]) >= 2 and int(dmg[0]["amount"]) <= 12, "2d6 (%d)" % dmg[0]["amount"])
		t.eq(int(dmg[0]["dtype"]), SRD.DamageType.FIRE, "fire damage")
	t.check(h.combatant.current_hp < hp, "the hero is hurt (%d of %d)" % [h.combatant.current_hp, hp])
	Combat.ticks(r, K.TICK_HZ)
	t.eq(Combat.evs(r, Ev.DAMAGE, 0, h.id).size(), 1, "not again within the round")
	Combat.ticks(r, int(K.ROUND_SECONDS * K.TICK_HZ))
	t.eq(Combat.evs(r, Ev.DAMAGE, 0, h.id).size(), 2, "again the next round it stays in it")
	h.body.pos.x = 120.5
	Combat.ticks(r, int(K.ROUND_SECONDS * K.TICK_HZ) * 2)
	t.eq(Combat.evs(r, Ev.DAMAGE, 0, h.id).size(), 2, "and no more once out of it")
	var r2 := Combat.rig(82, world)
	var fire := Combat.monster(r2, "fire-elemental", 60.5)
	var fhp := fire.combatant.current_hp
	Combat.ticks(r2, int(K.ROUND_SECONDS * K.TICK_HZ) + 2)
	t.eq(fire.combatant.current_hp, fhp, "a fire elemental wades it unhurt (immune to fire)")
