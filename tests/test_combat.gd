## Combat on the host: tempo and the swing state machine, physical hit shapes (arcs,
## projectiles, areas, cover), seeded reproducibility, Extra Attack and Multiattack, spells
## end to end (slots, concentration, durations, Shield), fall damage, conditions, death.
extends RefCounted

const Ev := CombatCodec.Ev

class FakeRules extends HostSystem:
	var kills: Array = []
	var dropped: Array = []
	func sys_id() -> int:
		return HostSystem.RULES
	func on_kill(victim: HostEntity, killers: Array) -> void:
		kills.append([victim.id, killers.duplicate()])
	func player_dropped(e: HostEntity) -> void:
		dropped.append(e.id)
	func is_downed(e: HostEntity) -> bool:
		return e.id in dropped and e.combatant.current_hp <= 0

class FakeItems extends HostSystem:
	var kills: Array = []
	func sys_id() -> int:
		return HostSystem.ITEMS
	func on_kill(victim: HostEntity) -> void:
		kills.append(victim.id)

const GROUND := 20

func run(t: TestLog) -> void:
	_tempo(t)
	_shapes(t)
	_swing_timing(t)
	_no_touch_no_roll(t)
	_projectiles(t)
	_cover_and_areas(t)
	_reproducible(t)
	_extra_attack(t)
	_multiattack(t)
	_spells(t)
	_shield(t)
	_concentration_and_durations(t)
	_fall(t)
	_conditions(t)
	_death(t)
	_brain(t)

# --- helpers --------------------------------------------------------------------------------

static func flat_world(w := 256) -> TileWorld:
	var world := TileWorld.new(w, 64, 1)
	var stone := TileDefs.id("stone")
	for x in w:
		for y in GROUND:
			world.set_fg(x, y, stone, true)
	return world

static func rig(seed_value := 1, world: TileWorld = null) -> Dictionary:
	var host := WorldHost.new(world if world != null else flat_world())
	host.rng.seed = seed_value
	Dice.rng = host.rng
	var combat := CombatSystem.new()
	host.add_system(combat)
	combat.record = true
	return {"host": host, "combat": combat}

static func hero(r: Dictionary, cls := "fighter", level := 1, x := 60.5, name := "hero") -> HostEntity:
	var host: WorldHost = r["host"]
	var e := host.add_player(name, host.entities.size() + 2, {"class": cls})
	var ch := e.character
	while ch.level < level:
		ch.gain_level()
	ch.auto_choices(host.srd)
	ch.hp = ch.max_hp()
	e.combatant = ch.make_combatant(host.srd)
	e.body.pos = Vector2(x, GROUND)
	e.body.on_floor = true
	r["combat"].actor(e).takeoff_y = GROUND
	return e

static func monster(r: Dictionary, slug: String, x: float, hp := -1, brain: Object = null) -> HostEntity:
	var host: WorldHost = r["host"]
	var m := host.add_srd_monster(slug, Vector2(x, GROUND), brain)
	if hp > 0:
		m.combatant.stats.max_hp = hp
		m.combatant.stats.current_hp = hp
	return m

static func ticks(r: Dictionary, n: int) -> void:
	for i in n:
		r["host"].tick()
		r["host"].drain()

static func evs(r: Dictionary, kind: int, src := -1, dst := -1) -> Array:
	return r["combat"].recorded.filter(func(ev: Dictionary) -> bool:
		return int(ev["kind"]) == kind and (src < 0 or int(ev["src"]) == src) and (dst < 0 or int(ev["dst"]) == dst))

static func rolls_against(r: Dictionary, dst: int) -> int:
	return evs(r, Ev.HIT, -1, dst).size() + evs(r, Ev.MISS, -1, dst).size() + evs(r, Ev.CRIT, -1, dst).size() \
		+ evs(r, Ev.SAVE, -1, dst).size()

static func center(e: HostEntity) -> Vector2:
	return e.body.rect().get_center()

# --- tests ----------------------------------------------------------------------------------

func _tempo(t: TestLog) -> void:
	var srd := WorldHost.shared_srd()
	t.eq(CombatTempo.weapon_class(srd, srd.make_weapon("dagger")), "light", "dagger is light")
	t.eq(CombatTempo.weapon_class(srd, srd.make_weapon("greatsword")), "heavy", "greatsword is heavy")
	t.eq(CombatTempo.weapon_class(srd, srd.make_weapon("longsword")), "plain", "longsword one-handed is plain")
	t.eq(CombatTempo.weapon_class(srd, srd.make_weapon("longsword"), true), "versatile_two", "longsword two-handed")
	t.eq(CombatTempo.weapon_class(srd, srd.make_weapon("longbow")), "heavy_bow", "longbow")
	t.eq(CombatTempo.weapon_class(srd, srd.make_weapon("light-crossbow")), "loading", "crossbows load")
	t.eq(CombatTempo.weapon_class(srd, srd.make_weapon("javelin"), false, true), "thrown", "a thrown javelin")
	t.eq(CombatTempo.weapon_class(srd, srd.make_monster("goblin-warrior").weapon), "monster", "stat-block attacks use the monster tempo")
	t.eq(CombatTempo.weapon_class(srd, null), "unarmed", "no weapon")
	var light := CombatTempo.timeline(CombatTempo.weapon_tempo("light"), 1)
	t.check(is_equal_approx(light["total"], 0.5) and is_equal_approx(light["contacts"][0], 0.15), "light: contact at 0.15 s, 0.5 s per swing (2 a second)")
	var two := CombatTempo.timeline(CombatTempo.weapon_tempo("light"), 2)
	t.check(is_equal_approx(two["total"], 0.5), "Extra Attack keeps the action's time")
	t.check(two["contacts"].size() == 2 and two["contacts"][1] > two["contacts"][0] and two["contacts"][1] < 0.5, "second contact inside the action")
	var four := CombatTempo.timeline(CombatTempo.weapon_tempo("light"), 4)
	t.check(four["contacts"][3] <= 0.5 - 0.08 + 1e-6, "four swings still leave the minimum recovery")
	t.check(CombatTempo.reach_ft(srd, srd.make_weapon("glaive")) == 10.0 and CombatTempo.reach_ft(srd, srd.make_weapon("mace")) == 5.0, "reach from the Reach property")
	t.eq(CombatTempo.duration_s("1 round"), 2.0, "a round is 2 s")
	t.eq(CombatTempo.duration_s("Concentration, up to 1 minute"), 20.0, "a minute is 20 s")
	t.eq(CombatTempo.duration_s("Concentration, up to 10 minutes"), 120.0, "ten minutes is 2 real minutes")
	t.eq(CombatTempo.duration_s("1 hour"), 300.0, "an hour is 5 real minutes")
	t.eq(CombatTempo.duration_s("24 hours"), 1200.0, "a day is a game day")
	t.eq(CombatTempo.duration_s("Instantaneous"), -1.0, "instantaneous is not timed")

func _shapes(t: TestLog) -> void:
	var att := Rect2(10, 20, 1.5, 2.5)
	var right := Vector2.RIGHT
	t.check(HitShapes.in_arc(att, right, 2.0, 70.0, Rect2(13.4, 20, 1.5, 2.5)), "1.9 tiles in front: in a 5 ft reach")
	t.check(not HitShapes.in_arc(att, right, 2.0, 70.0, Rect2(13.6, 20, 1.5, 2.5)), "2.1 tiles: out of reach")
	t.check(HitShapes.in_arc(att, right, 4.0, 70.0, Rect2(15.4, 20, 1.5, 2.5)), "3.9 tiles with Reach (10 ft)")
	t.check(not HitShapes.in_arc(att, right, 2.0, 70.0, Rect2(7.0, 20, 1.5, 2.5)), "behind: not in the arc")
	t.check(HitShapes.in_arc(att, Vector2.LEFT, 2.0, 70.0, Rect2(7.0, 20, 1.5, 2.5)), "facing it: in the arc")
	t.check(not HitShapes.in_arc(att, right, 2.0, 70.0, Rect2(10.2, 23.8, 1.0, 1.0)), "straight overhead is outside a forward arc")
	t.eq(HitShapes.segment_box(Vector2(0, 1), Vector2(10, 1), Rect2(4, 0, 2, 2)), 0.4, "segment meets a box at its near face")
	t.eq(HitShapes.segment_box(Vector2(0, 5), Vector2(10, 5), Rect2(4, 0, 2, 2)), -1.0, "and misses one off its line")
	var o := Vector2(0, 0)
	t.check(HitShapes.in_area(SRD.AoEShape.SPHERE, o, right, 8.0, 0, Rect2(7.5, -1, 1, 2)), "sphere reaches a box at its rim")
	t.check(not HitShapes.in_area(SRD.AoEShape.SPHERE, o, right, 8.0, 0, Rect2(8.5, -1, 1, 2)), "not past it")
	t.check(HitShapes.in_area(SRD.AoEShape.CONE, o, right, 6.0, 0, Rect2(4, 1.5, 1, 1)), "cone: wide enough 4 tiles out")
	t.check(not HitShapes.in_area(SRD.AoEShape.CONE, o, right, 6.0, 0, Rect2(1, 2.5, 1, 1)), "cone: narrow near the origin")
	t.check(not HitShapes.in_area(SRD.AoEShape.CONE, o, right, 6.0, 0, Rect2(-3, -0.5, 1, 1)), "cone: nothing behind")
	t.check(HitShapes.in_area(SRD.AoEShape.LINE, o, right, 20.0, 2.0, Rect2(18, -0.5, 1, 1)), "line: far along it")
	t.check(not HitShapes.in_area(SRD.AoEShape.LINE, o, right, 20.0, 2.0, Rect2(10, 2.0, 1, 1)), "line: not beside it")
	t.check(HitShapes.in_area(SRD.AoEShape.CUBE, o, right, 6.0, 0, Rect2(5, 2.5, 1, 1)) and not HitShapes.in_area(SRD.AoEShape.CUBE, o, right, 6.0, 0, Rect2(-2, 0, 1, 1)),
		"cube: in front of its face, not behind")
	var d := HitShapes.ballistic_dir(Vector2.ZERO, Vector2(20, 0), 45.0, 22.0)
	var tt := 20.0 / (45.0 * d.x)
	t.check(absf(45.0 * d.y * tt - 11.0 * tt * tt) < 0.05, "a lobbed arrow passes through its aim point")

func _swing_timing(t: TestLog) -> void:
	var r := rig()
	var combat: CombatSystem = r["combat"]
	var h := hero(r)                     # fighter: longsword and shield (plain: 0.2 + 0.4 s)
	var g := monster(r, "goblin-warrior", 62.6, 500)
	ticks(r, 1)
	t.check(combat.start_attack(h, -1, center(g)), "attack starts")
	t.check(not combat.start_attack(h, -1, center(g)), "not again mid-swing")
	t.eq(evs(r, Ev.SWING, h.id).size(), 1, "one SWING event")
	var sw: Dictionary = evs(r, Ev.SWING, h.id)[0]
	t.check(is_equal_approx(sw["windup"], 0.2) and is_equal_approx(sw["total"], 0.6), "SWING carries wind-up 0.2 and total 0.6 s")
	ticks(r, 5)
	t.eq(rolls_against(r, g.id), 0, "nothing rolls during the wind-up (5 ticks)")
	ticks(r, 1)
	t.eq(rolls_against(r, g.id), 1, "the contact frame rolls once (tick 6 = 0.2 s)")
	t.check(not combat.start_attack(h, -1, center(g)), "recovery: still busy")
	ticks(r, 11)
	t.check(not combat.start_attack(h, -1, center(g)), "not before 0.6 s")
	ticks(r, 1)
	t.check(combat.start_attack(h, -1, center(g)), "ready again at 0.6 s")
	# cancel in the wind-up: nothing rolls, the action is not spent
	ticks(r, 2)
	combat.cancel(h)
	ticks(r, 10)
	t.eq(rolls_against(r, g.id), 1, "a cancelled wind-up never rolls")
	t.check(combat.start_attack(h, -1, center(g)), "and the action is free at once")

func _no_touch_no_roll(t: TestLog) -> void:
	var r := rig()
	var combat: CombatSystem = r["combat"]
	var h := hero(r)
	var far := monster(r, "goblin-warrior", 66.0, 500)    # gap ~4.5 tiles: beyond 5 ft
	ticks(r, 1)
	combat.start_attack(h, -1, center(far))
	ticks(r, 20)
	t.eq(rolls_against(r, far.id), 0, "out of reach: never rolled against")
	t.eq(far.combatant.current_hp, 500, "and untouched")
	var behind := monster(r, "goblin-warrior", 58.4, 500)
	combat.start_attack(h, -1, center(h) + Vector2(5, 0))
	ticks(r, 20)
	t.eq(rolls_against(r, behind.id), 0, "behind the swing: never rolled against")
	combat.start_attack(h, -1, center(behind))
	ticks(r, 20)
	t.eq(rolls_against(r, behind.id), 1, "turned toward it: rolled")
	t.check(combat.counts["whiffs"] >= 2, "whiffs counted")

func _projectiles(t: TestLog) -> void:
	var world := flat_world()
	for y in range(GROUND, GROUND + 6):
		world.set_fg(70, y, TileDefs.id("stone"), true)    # a wall between archer and goblin
	var r := rig(3, world)
	var combat: CombatSystem = r["combat"]
	var h := hero(r)
	h.combatant.weapon = r["host"].srd.make_weapon("shortbow")
	var g := monster(r, "goblin-warrior", 80.5, 500)
	ticks(r, 1)
	t.check(combat.start_attack(h, -1, center(g)), "loose an arrow")
	ticks(r, 40)
	var imp := evs(r, Ev.IMPACT, h.id)
	t.eq(imp.size(), 1, "one impact")
	t.check(imp.size() == 1 and int(imp[0]["dst"]) == 0 and Vector2(imp[0]["pos"]).x <= 70.05, "stopped at the wall")
	t.eq(rolls_against(r, g.id), 0, "the goblin behind the wall is never rolled against")
	# two goblins in a line: the first one takes it
	var r2 := rig(4)
	var c2: CombatSystem = r2["combat"]
	var h2 := hero(r2)
	h2.combatant.weapon = r2["host"].srd.make_weapon("shortbow")
	var g1 := monster(r2, "goblin-warrior", 74.5, 500)
	var g2 := monster(r2, "goblin-warrior", 78.5, 500)
	ticks(r2, 1)
	c2.start_attack(h2, -1, center(g2))
	ticks(r2, 40)
	t.eq(rolls_against(r2, g1.id), 1, "the first body in the path is rolled against")
	t.eq(rolls_against(r2, g2.id), 0, "the one behind it is not")
	t.eq(evs(r2, Ev.PROJECTILE, h2.id).size(), 1, "PROJECTILE event for clients")

func _cover_and_areas(t: TestLog) -> void:
	var world := flat_world()
	var stone := TileDefs.id("stone")
	var from := Vector2(60, GROUND + 1.75)
	var box := Rect2(70, GROUND, 2.5, 3.5)        # sample rows at 20.35, 21.75, 23.15
	t.eq(HitShapes.cover(world, from, box), SRD.Cover.NONE, "open ground: no cover")
	world.set_fg(69, GROUND, stone, true)        # a 1-tile wall right in front: the low third
	t.eq(HitShapes.cover(world, from, box), SRD.Cover.HALF, "a low wall: half cover")
	world.set_fg(69, GROUND + 1, stone, true)
	t.eq(HitShapes.cover(world, from, box), SRD.Cover.THREE_QUARTERS, "a taller wall: three-quarters")
	world.set_fg(69, GROUND + 2, stone, true)
	world.set_fg(69, GROUND + 3, stone, true)
	t.eq(HitShapes.cover(world, from, box), SRD.Cover.FULL, "a full wall: total cover")
	# a cone of Burning Hands with a wall in front of one goblin
	var w2 := flat_world()
	for y in range(GROUND, GROUND + 8):
		w2.set_fg(58, y, stone, true)
	var r := rig(5, w2)
	var combat: CombatSystem = r["combat"]
	var wiz := hero(r, "wizard", 1, 60.5)
	wiz.character.build["spells"] = ["burning-hands"]
	var open := monster(r, "goblin-warrior", 63.5, 500)
	var walled := monster(r, "goblin-warrior", 56.5, 500)
	ticks(r, 1)
	t.eq(combat.cast(wiz, "burning-hands", 1, center(open)), "", "Burning Hands cast")
	ticks(r, 30)
	t.eq(evs(r, Ev.SAVE, wiz.id, open.id).size(), 1, "the goblin in the cone saves")
	t.eq(rolls_against(r, walled.id), 0, "the one behind the caster and a wall does not")
	combat.cast(wiz, "burning-hands", 1, center(walled))
	ticks(r, 30)
	t.eq(evs(r, Ev.SAVE, wiz.id, walled.id).size(), 0, "a cone into a wall stops there")

func _reproducible(t: TestLog) -> void:
	var a := _scripted_fight(11)
	var b := _scripted_fight(11)
	var c := _scripted_fight(12)
	t.check(a.size() > 10, "a scripted fight produced events (%d)" % a.size())
	t.eq(a, b, "same seed: the same fight, event for event")
	t.check(a != c, "another seed: another fight")

func _scripted_fight(seed_value: int) -> Array:
	var r := rig(seed_value)
	var combat: CombatSystem = r["combat"]
	var h := hero(r)
	var g := monster(r, "goblin-warrior", 63.0, -1, CombatBrain.new())
	for i in 150:
		if g.combatant.current_hp > 0:
			combat.start_attack(h, -1, center(g))
		ticks(r, 1)
	return combat.recorded.map(func(ev: Dictionary) -> String: return "%d %s" % [ev["t"], CombatCodec.describe(ev)])

func _extra_attack(t: TestLog) -> void:
	var r := rig(7)
	var combat: CombatSystem = r["combat"]
	var h := hero(r, "fighter", 25)
	t.eq(h.combatant.kit.attacks_per_action(), 2, "level 25 fighter (class 6) has Extra Attack")
	var g := monster(r, "goblin-warrior", 62.6, 500)
	ticks(r, 1)
	combat.start_attack(h, -1, center(g))
	t.eq(int(evs(r, Ev.SWING, h.id)[0]["swings"]), 2, "the SWING announces a 2-swing combo")
	ticks(r, 18)
	t.eq(rolls_against(r, g.id), 2, "two attack rolls in one action")
	var low := hero(r, "fighter", 5, 40.5, "low")
	t.eq(low.combatant.kit.attacks_per_action(), 1, "level 5 fighter (class 2): one")

func _multiattack(t: TestLog) -> void:
	var srd := WorldHost.shared_srd()
	var bear := MonsterMoves.of(srd, "brown-bear")
	var names: Array = bear["multi"].map(func(i: int) -> String: return bear["actions"][i]["name"])
	t.eq(names, ["Bite", "Claw"], "brown bear: Bite and Claw")
	var drake := MonsterMoves.of(srd, "red-dragon-wyrmling")
	t.eq(drake["multi"].size(), 2, "wyrmling: two Rends")
	t.check(drake["actions"].any(func(a: Dictionary) -> bool: return a["kind"] == "save" and a["save"]["area_shape"] == "cone"), "and a Fire Breath cone")
	var r := rig(8)
	var combat: CombatSystem = r["combat"]
	var h := hero(r, "fighter", 1)
	h.combatant.stats.max_hp = 500
	h.combatant.stats.current_hp = 500
	var b := monster(r, "brown-bear", 63.4)
	ticks(r, 1)
	t.eq(combat.targets_in_reach(b), [h], "the bear reaches the hero")
	t.check(combat.start_attack(b, -1, center(h)), "Multiattack starts")
	var sw: Dictionary = evs(r, Ev.SWING, b.id)[0]
	t.check(int(sw["swings"]) == 2 and is_equal_approx(sw["windup"], 0.5), "two swings behind a 0.5 s telegraph")
	ticks(r, 14)
	t.eq(rolls_against(r, h.id), 0, "nothing lands during the telegraph")
	ticks(r, 30)
	t.eq(rolls_against(r, h.id), 2, "Bite and Claw both rolled")
	# breath: a save action with an area, then not ready until it recharges
	var r2 := rig(9)
	var c2: CombatSystem = r2["combat"]
	var h2 := hero(r2)
	h2.combatant.stats.max_hp = 500
	h2.combatant.stats.current_hp = 500
	var d := monster(r2, "red-dragon-wyrmling", 64.0)
	ticks(r2, 1)
	var breath := -1
	for i in c2.actions_of(d).size():
		if c2.actions_of(d)[i]["kind"] == "save":
			breath = i
	t.check(c2.start_attack(d, breath, center(h2)), "Fire Breath starts")
	ticks(r2, 40)
	t.eq(evs(r2, Ev.SAVE, d.id, h2.id).size(), 1, "the hero makes a Dex save")
	t.check(not c2.start_attack(d, breath, center(h2)), "spent until it recharges")

func _spells(t: TestLog) -> void:
	var r := rig(21)
	var combat: CombatSystem = r["combat"]
	var host: WorldHost = r["host"]
	var wiz := hero(r, "wizard", 25, 60.5, "wiz")
	wiz.character.build["spells"] = ["fire-bolt", "magic-missile", "burning-hands", "thunderwave", "fireball", "shield"]
	var cler := hero(r, "cleric", 25, 58.5, "cler")
	cler.character.build["spells"] = ["sacred-flame", "cure-wounds", "healing-word", "bless"]
	var g := monster(r, "goblin-warrior", 75.5, 500)
	var g2 := monster(r, "goblin-warrior", 77.5, 500)
	ticks(r, 31)
	var list := combat.spells_of(wiz)
	t.eq(list[0]["slug"], "fire-bolt", "attack and save spells come first in the list")
	var slots0 := wiz.combatant.energy_slots.slots_remaining_at(1)
	# Fire Bolt: a bolt that flies and rolls a spell attack at impact
	t.eq(combat.cast(wiz, "fire-bolt", 0, center(g)), "", "Fire Bolt")
	ticks(r, 30)
	t.eq(evs(r, Ev.PROJECTILE, wiz.id).size(), 1, "Fire Bolt flies")
	t.eq(rolls_against(r, g.id), 1, "and rolls one spell attack against the goblin")
	# Magic Missile: 3 darts at the creature nearest the aim, the slot spent at contact
	var d0 := evs(r, Ev.DAMAGE, wiz.id, g.id).size()
	t.eq(combat.cast(wiz, "magic-missile", 1, center(g)), "", "Magic Missile")
	t.eq(wiz.combatant.energy_slots.slots_remaining_at(1), slots0, "no slot spent during the wind-up")
	ticks(r, 9)
	t.eq(wiz.combatant.energy_slots.slots_remaining_at(1), slots0 - 1, "one level-1 slot spent at the contact frame")
	ticks(r, 30)
	t.eq(evs(r, Ev.DAMAGE, wiz.id, g.id).size() - d0, 3, "three darts, three damage rolls")
	t.eq(evs(r, Ev.PROJECTILE, wiz.id).size(), 4, "each dart flies (and the Fire Bolt before)")
	# Burning Hands, Thunderwave (push), Fireball
	host.entity(g.id).body.pos = Vector2(64.0, GROUND)
	host.entity(g2.id).body.pos = Vector2(65.5, GROUND)
	ticks(r, 3)
	var before := rolls_against(r, g2.id)
	t.eq(combat.cast(wiz, "thunderwave", 1, center(g)), "", "Thunderwave")
	ticks(r, 20)
	t.eq(rolls_against(r, g2.id) - before, 1, "Thunderwave: a save for each creature in the cube")
	t.check(not evs(r, Ev.PUSH).is_empty(), "a failed save pushes (PUSH event)")
	var x0 := g.body.pos.x
	host.entity(g.id).body.pos = Vector2(78.0, GROUND)
	host.entity(g2.id).body.pos = Vector2(81.0, GROUND)
	ticks(r, 1)
	t.eq(combat.cast(wiz, "fireball", 3, Vector2(80, GROUND + 1)), "", "Fireball at a point")
	var n0 := evs(r, Ev.SAVE, wiz.id).size()
	ticks(r, 20)
	t.eq(evs(r, Ev.SAVE, wiz.id).size() - n0, 2, "Fireball: a Dex save for both goblins in the sphere, none for the casters 20 tiles away")
	t.eq(wiz.combatant.energy_slots.slots_remaining_at(3), wiz.combatant.energy_slots.slots_max_at(3) - 1, "a level-3 slot spent")
	t.check(x0 >= 64.0, "pushed away, not toward")
	# Cleric: Sacred Flame (save), Bless (3 allies), Cure Wounds (touch), Healing Word (bonus)
	host.entity(g.id).body.pos = Vector2(70.0, GROUND)
	ticks(r, 31)
	n0 = evs(r, Ev.SAVE, cler.id, g.id).size()
	t.eq(combat.cast(cler, "sacred-flame", 0, center(g)), "", "Sacred Flame")
	ticks(r, 20)
	t.eq(evs(r, Ev.SAVE, cler.id, g.id).size() - n0, 1, "Sacred Flame: a Dex save, no attack roll")
	t.eq(combat.cast(cler, "bless", 1, center(wiz)), "", "Bless")
	ticks(r, 20)
	t.check(wiz.combatant.effects.has_id("bless-bonus_die") and cler.combatant.effects.has_id("bless-bonus_die"), "Bless on the wizard and the cleric")
	t.check(not evs(r, Ev.EFFECT, -1, wiz.id).filter(func(ev: Dictionary) -> bool: return ev["what"] == "bless-bonus_die" and ev["on"]).is_empty(), "EFFECT event for Bless")
	wiz.combatant.stats.current_hp = 5
	t.eq(combat.cast(cler, "cure-wounds", 1, center(wiz)), "", "Cure Wounds")
	ticks(r, 20)
	t.check(wiz.combatant.current_hp > 5 and evs(r, Ev.HEAL, cler.id, wiz.id).size() == 1, "Cure Wounds heals the wizard (within touch)")
	wiz.combatant.stats.current_hp = 5
	t.eq(combat.cast(cler, "healing-word", 1, center(wiz)), "", "Healing Word (bonus action)")
	t.eq(combat.cast(cler, "healing-word", 1, center(wiz)), "busy", "not twice at once")
	ticks(r, 20)
	t.check(wiz.combatant.current_hp > 5, "Healing Word heals")
	t.eq(combat.cast(cler, "healing-word", 1, center(wiz)), "bonus action not ready", "the bonus action's 2 s timer")
	t.eq(combat.cast(cler, "fireball", 3, center(g)), "not prepared", "unprepared spells are refused")
	t.eq(CombatSystem.spell_support(r["host"].srd.make_spell("spiritual-weapon")), "summons a force (needs a host-side summon)", "summons refused with a reason")
	t.eq(CombatSystem.spell_support(r["host"].srd.make_spell("misty-step")), "teleport (would move a client-owned body)", "teleports refused with a reason")

func _shield(t: TestLog) -> void:
	var r := rig(31)
	var combat: CombatSystem = r["combat"]
	var wiz := hero(r, "wizard", 1, 60.5, "wiz")
	wiz.character.build["spells"] = ["shield"]
	wiz.combatant.stats.max_hp = 300
	wiz.combatant.stats.current_hp = 300
	var b := monster(r, "brown-bear", 63.4)
	ticks(r, 1)
	var ac := wiz.combatant.armor_class
	combat.start_attack(b, -1, center(wiz))
	ticks(r, 5)
	t.eq(combat.cast(wiz, "shield", 1, center(wiz)), "", "Shield during the bear's telegraph")
	t.eq(wiz.combatant.armor_class, ac + 5, "at once: +5 AC (a reaction has no wind-up)")
	t.check(combat.actor(wiz).reaction_ready > combat.now + 1.9, "the reaction timer runs 2 s")
	ticks(r, 30)
	var hits: Array = evs(r, Ev.HIT, b.id, wiz.id) + evs(r, Ev.MISS, b.id, wiz.id)
	t.check(hits.size() == 2 and hits.all(func(ev: Dictionary) -> bool: return int(ev["ac"]) == ac + 5), "both bear attacks face the shielded AC")
	t.eq(combat.cast(wiz, "shield", 1, center(wiz)), "reaction not ready", "no second reaction within 2 s")
	ticks(r, 30)
	t.eq(wiz.combatant.armor_class, ac, "Shield ends after its round (2 s)")
	t.eq(combat.cast(wiz, "shield", 1, center(wiz)), "", "and the reaction is back")

func _concentration_and_durations(t: TestLog) -> void:
	var r := rig(41)
	var combat: CombatSystem = r["combat"]
	var cler := hero(r, "cleric", 1, 60.5, "cler")
	cler.character.build["spells"] = ["bless"]
	cler.combatant.stats.max_hp = 300
	cler.combatant.stats.current_hp = 300
	ticks(r, 31)
	combat.cast(cler, "bless", 1, center(cler))
	ticks(r, 20)
	t.check(combat.actor(cler).conc.is_concentrating and cler.combatant.effects.has_id("bless-bonus_die"), "Bless: concentrating, blessed")
	ticks(r, 19 * 30 - 20 - 3)
	t.check(cler.combatant.effects.has_id("bless-bonus_die"), "still there at about 19 s (rounds pass, the table rules)")
	ticks(r, 60)
	t.check(not cler.combatant.effects.has_id("bless-bonus_die") and not combat.actor(cler).conc.is_concentrating, "gone after its minute (20 s), Concentration ended")
	t.check(not evs(r, Ev.EFFECT, -1, cler.id).filter(func(ev: Dictionary) -> bool: return not ev["on"]).is_empty(), "EFFECT off sent")
	# damage breaks it: DC 30 cannot be made
	combat.cast(cler, "bless", 1, center(cler))
	ticks(r, 20)
	t.check(cler.combatant.effects.has_id("bless-bonus_die"), "blessed again")
	combat.damage(0, cler, 60, "fire")
	t.check(not combat.actor(cler).conc.is_concentrating and not cler.combatant.effects.has_id("bless-bonus_die"), "60 damage breaks Concentration and ends Bless")
	t.check(not evs(r, Ev.EFFECT, 0, cler.id).filter(func(ev: Dictionary) -> bool: return String(ev["what"]) == "concentration:bless").is_empty(), "EFFECT concentration off")

func _fall(t: TestLog) -> void:
	var r := rig(51)
	var h := hero(r)
	ticks(r, 1)
	var hp := h.combatant.current_hp
	h.body.on_floor = false
	h.body.pos.y = GROUND + 3
	ticks(r, 1)
	h.body.on_floor = true
	h.body.pos.y = GROUND
	ticks(r, 1)
	t.eq(h.combatant.current_hp, hp, "a jump down from the same level (net drop 0) does no damage")
	h.body.pos.y = GROUND + 20
	ticks(r, 1)
	h.body.on_floor = false
	ticks(r, 1)
	h.body.pos.y = GROUND + 3
	ticks(r, 1)
	h.body.pos.y = GROUND
	h.body.on_floor = true
	ticks(r, 1)
	var dmg := evs(r, Ev.DAMAGE, 0, h.id)
	t.eq(dmg.size(), 1, "a 20-tile (50 ft) fall deals damage once")
	t.check(dmg.size() == 1 and int(dmg[0]["amount"]) >= 5 and int(dmg[0]["amount"]) <= 30, "5d6 bludgeoning")
	var r2 := rig(52)
	var h2 := hero(r2)
	ticks(r2, 1)
	h2.body.pos.y = GROUND + 4
	ticks(r2, 1)
	h2.body.on_floor = false
	ticks(r2, 1)
	h2.body.pos.y = GROUND
	h2.body.on_floor = true
	ticks(r2, 1)
	t.eq(evs(r2, Ev.DAMAGE, 0, h2.id).size(), 0, "10 ft is free")
	# a brainless monster falls (the host only steps bodies with a brain)
	var gob: HostEntity = r2["host"].add_srd_monster("goblin-warrior", Vector2(90.5, GROUND + 12), null)
	ticks(r2, 60)
	t.check(absf(gob.body.pos.y - GROUND) < 0.01 and gob.body.on_floor, "a brainless monster falls to the ground")
	t.check(gob.combatant.current_hp < 10 or not evs(r2, Ev.DAMAGE, 0, gob.id).is_empty(), "and takes fall damage (30 ft)")

func _conditions(t: TestLog) -> void:
	var r := rig(61)
	var combat: CombatSystem = r["combat"]
	var g := monster(r, "goblin-warrior", 70.5, 500)
	var h := hero(r)
	ticks(r, 1)
	var inp := PlayerInput.new()
	inp.move_x = 1.0
	inp.jump = true
	inp.jump_pressed = true
	g.combatant.conditions.add(SRD.Condition.RESTRAINED)
	combat.damage(h.id, g, 1, "slashing")     # anything that touches it re-reads its conditions
	ticks(r, 1)
	var out := combat.filter_input(g, inp)
	t.check(out.move_x == 0.0 and not out.jump, "Restrained: speed 0, no jump")
	t.check(not evs(r, Ev.CONDITION, -1, g.id).filter(func(ev: Dictionary) -> bool: return ev["cond"] == SRD.Condition.RESTRAINED and ev["on"]).is_empty(), "CONDITION event")
	g.combatant.conditions.remove(SRD.Condition.RESTRAINED)
	g.combatant.conditions.add(SRD.Condition.PRONE)
	combat.damage(h.id, g, 1, "slashing")
	ticks(r, 1)
	inp.move_x = 1.0
	out = combat.filter_input(g, inp)
	t.check(is_equal_approx(out.move_x, 0.5) or absf(out.move_x - 0.5) < 0.01, "Prone: crawl at half speed")
	ticks(r, 31)
	t.check(not g.combatant.conditions.has(SRD.Condition.PRONE), "stands up after a second")
	g.combatant.conditions.add(SRD.Condition.STUNNED)
	t.check(not combat.can_act(g) and not combat.start_attack(g), "Stunned: no actions")
	g.combatant.conditions.remove(SRD.Condition.STUNNED)
	# Frightened: no step toward the source
	g.combatant.effects.add({"id": "fear-test", "type": "condition", "condition": "frightened", "source": h.combatant.name,
		"expires": "", "of": g.combatant.name})
	combat.damage(h.id, g, 1, "slashing")
	ticks(r, 1)
	inp.move_x = -1.0
	t.eq(combat.filter_input(g, inp).move_x, 0.0, "Frightened: cannot move closer to the source")
	inp.move_x = 1.0
	t.eq(combat.filter_input(g, inp).move_x, 1.0, "but can move away")

func _death(t: TestLog) -> void:
	var r := rig(71)
	var combat: CombatSystem = r["combat"]
	var host: WorldHost = r["host"]
	var h := hero(r)
	var g := monster(r, "goblin-warrior", 62.6)
	ticks(r, 1)
	combat.damage(h.id, g, 100, "slashing")
	t.eq(evs(r, Ev.DEATH, -1, g.id).size(), 1, "0 HP: DEATH")
	ticks(r, 30)
	t.check(host.entities.has(g.id), "lingers")
	ticks(r, 20)
	t.check(not host.entities.has(g.id), "removed after the linger (no rules or items system: still fine)")
	var rules := FakeRules.new()
	var items := FakeItems.new()
	host.add_system(rules)
	host.add_system(items)
	var g2 := monster(r, "goblin-warrior", 62.6)
	ticks(r, 1)
	combat.damage(h.id, g2, 100, "slashing")
	ticks(r, 50)
	t.eq(rules.kills, [[g2.id, [h.id]]], "rules.on_kill(victim, killers)")
	t.eq(items.kills, [g2.id], "items.on_kill(victim)")
	combat.damage(g2.id, h, 500, "slashing")
	t.eq(rules.dropped, [h.id], "a player at 0 HP: rules.player_dropped")
	t.eq(evs(r, Ev.DOWNED, -1, h.id).size(), 1, "DOWNED")
	t.check(not combat.can_act(h), "downed players cannot act")
	ticks(r, 120)
	t.eq(h.combatant.current_hp, 0, "with rules present, combat does not respawn them")
	# fallback without rules
	var r2 := rig(72)
	var c2: CombatSystem = r2["combat"]
	var h2 := hero(r2, "fighter", 1, 90.5)
	ticks(r2, 1)
	c2.damage(0, h2, 500, "slashing")
	t.eq(evs(r2, Ev.DOWNED, -1, h2.id).size(), 1, "fallback: DOWNED")
	ticks(r2, 80)
	t.eq(h2.combatant.current_hp, 0, "down for 3 s")
	ticks(r2, 15)
	t.check(h2.combatant.current_hp == h2.combatant.stats.max_hp and h2.body.pos == r2["host"].spawn, "then back at the spawn with full HP")
	t.check(r2["host"].drain().size() >= 0 and c2.can_act(h2), "and can act")

func _brain(t: TestLog) -> void:
	var r := rig(81)
	var combat: CombatSystem = r["combat"]
	var h := hero(r)
	h.combatant.stats.max_hp = 500
	h.combatant.stats.current_hp = 500
	var g := monster(r, "goblin-warrior", 75.5, -1, CombatBrain.new())
	var x0 := g.body.pos.x
	ticks(r, 60)
	t.check(g.body.pos.x < x0 - 5.0, "the reference brain walks toward the player")
	var sw := evs(r, Ev.SWING, g.id)
	t.check(not sw.is_empty() and is_equal_approx(sw[0]["windup"], 0.5), "and swings with a 0.5 s wind-up")
	ticks(r, 120)
	t.check(rolls_against(r, h.id) >= 2, "repeatedly (%d rolls in 6 s)" % rolls_against(r, h.id))
	t.check(combat.in_combat(h) and combat.in_combat(g), "both are in combat")
