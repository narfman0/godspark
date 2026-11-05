## RulesSystem: short rests at a campfire, long rests in beds (the night passes for everyone
## or waits), downed and death saves on the timer, revive, healing up, death and respawn at
## the bed, a shrine or the spawn, and persistence through save and load.
extends RefCounted

const Down := RulesCodec.Down

func run(t: TestLog) -> void:
	_short(t)
	_long(t)
	_long_sim(t)
	_downed(t)
	_respawn(t)
	_persist(t)

static func rig(w := 256, h := 128) -> Array:
	var host := WorldHost.new(TileWorld.make_test(w, h))
	var rules := RulesSystem.new()
	host.add_system(rules)
	return [host, rules]

static func secs(host: WorldHost, s: float) -> void:
	for i in roundi(s * K.TICK_HZ):
		host.tick()

## Feet cell of a player, plus dx.
static func cell(e: HostEntity, dx := 0) -> Vector2i:
	return Vector2i(floori(e.body.pos.x) + dx, floori(e.body.pos.y))

static func rest_events(host: WorldHost, id: int) -> Array:
	var out := []
	for ev: Dictionary in host.outbox:
		if ev["type"] == WorldHost.Ev.SYS and ev["sys"] == HostSystem.RULES and ev["kind"] == RulesCodec.K.REST and ev["to"] == id:
			out.append(RulesCodec.decode_rest(ev["data"]))
	return out

func _short(t: TestLog) -> void:
	var r := rig()
	var host: WorldHost = r[0]
	var rules: RulesSystem = r[1]
	var ann := host.add_player("ann", 2, {"class": "fighter"})
	rules.award_xp(ann.id, LevelTrack.xp_for_level(12))
	host.tick()
	var s := ann.combatant.stats
	t.check(rules.start_short_rest(ann).contains("campfire"), "no campfire, no short rest")
	var fire := cell(ann, 5)
	host.world.set_fg(fire.x, fire.y, TileDefs.id("campfire"))
	t.check(rules.start_short_rest(ann) != "", "a campfire 5 tiles from the feet is too far")
	host.world.set_fg(fire.x, fire.y, TileDefs.AIR)
	fire = cell(ann, 2)
	host.world.set_fg(fire.x, fire.y, TileDefs.id("campfire"))
	var gob := host.add_srd_monster("goblin-warrior", ann.body.pos + Vector2(6, 0))
	t.eq(rules.start_short_rest(ann), "enemies nearby", "a living monster nearby forbids rest")
	host.remove_entity(gob.id)
	s.current_hp -= 20
	var dice := s.hit_dice_remaining
	host.drain()
	t.eq(rules.start_short_rest(ann), "", "rest at the campfire")
	secs(host, 4.0)
	t.eq(s.current_hp, s.max_hp - 20, "nothing yet after 4 s")
	secs(host, 1.1)
	var evs := rest_events(host, ann.id)
	t.check(s.current_hp > s.max_hp - 20, "5 s later: healed (%d/%d)" % [s.current_hp, s.max_hp])
	t.check(s.hit_dice_remaining < dice and s.hit_dice_remaining >= dice - 4, "spent Hit Point Dice (%d -> %d)" % [dice, s.hit_dice_remaining])
	t.check(evs.size() == 2 and evs[1]["event"] == RulesCodec.RestEv.SHORT_DONE and evs[1]["healed"] > 0, "SHORT_START then SHORT_DONE with what it healed")
	t.eq(ann.character.deeds.get("rest", 0), 1, "a rest deed")
	# a short rest restores short-rest features
	ann.combatant.kit.spend("action_surge")
	ann.combatant.kit.spend("second_wind")
	rules.start_short_rest(ann)
	secs(host, 5.1)
	t.eq(ann.combatant.kit.uses_left("action_surge"), 1, "Action Surge back")
	# interrupted by damage
	s.current_hp = 5
	host.drain()
	rules.start_short_rest(ann)
	secs(host, 2.0)
	s.current_hp -= 1
	secs(host, 4.0)
	t.eq(s.current_hp, 4, "damage interrupts it: no healing")
	var ev2 := rest_events(host, ann.id)
	t.check(ev2[-1]["event"] == RulesCodec.RestEv.SHORT_STOP and ev2[-1]["reason"] == "hurt", "SHORT_STOP: hurt")
	# interrupted by moving away
	rules.start_short_rest(ann)
	host.tick()
	host.submit_state(ann.id, ann.epoch, 1000, ann.body.pos + Vector2(1, 0), Vector2.ZERO, HostEntity.F_FLOOR)
	secs(host, 5.0)
	t.eq(s.current_hp, 4, "moving interrupts it")
	t.eq(rules.sheet(ann)["resting"], RulesCodec.Resting.NONE, "and the sheet says so")

func _long(t: TestLog) -> void:
	var r := rig()
	var host: WorldHost = r[0]
	var rules: RulesSystem = r[1]
	var ann := host.add_player("ann", 2, {"class": "wizard"})
	var bob := host.add_player("bob", 3)
	bob.body.pos.x -= 8.0
	host.tick()
	t.check(rules.start_long_rest(ann).contains("bed"), "no bed, no long rest")
	var b1 := cell(ann, 1)
	var b2 := cell(bob, -2)
	host.world.set_fg(b1.x, b1.y, TileDefs.id("bed"))
	host.world.set_fg(b2.x, b2.y, TileDefs.id("bed"))
	ann.combatant.stats.current_hp = 1
	ann.combatant.stats.hit_dice_remaining = 0
	ann.combatant.energy_slots.use_slot(1)
	var day := host.clock.day()
	host.drain()
	t.eq(rules.start_long_rest(ann), "", "ann lies down")
	secs(host, 1.0)
	var evs := rest_events(host, ann.id)
	t.check(not evs.is_empty() and evs[-1]["event"] == RulesCodec.RestEv.BED_WAIT and evs[-1]["names"] == ["bob"], "ann waits and is told who is up (%s)" % [evs])
	t.eq(host.clock.day(), day, "the night has not passed")
	t.eq(ann.combatant.stats.current_hp, 1, "and she has not rested")
	t.eq(rules.start_long_rest(bob), "", "bob lies down")
	host.tick()
	t.eq(host.clock.day(), day + 1, "the night passed")
	t.check(absf(host.clock.hour_of_day() - RulesSystem.WAKE_HOUR) < 0.05, "it is morning (%s)" % WorldClock.describe(host.clock.hours()))
	t.eq(ann.combatant.stats.current_hp, ann.combatant.stats.max_hp, "full HP")
	t.eq(ann.combatant.stats.hit_dice_remaining, ann.character.hit_dice_max(), "all Hit Point Dice")
	t.eq(ann.combatant.energy_slots.slots_remaining_at(1), ann.combatant.energy_slots.slots_max_at(1), "slots back")
	t.eq(ann.character.bed, b1, "the bed is ann's respawn point")
	t.eq(bob.character.bed, b2, "and bob's his")
	t.eq(ann.character.deeds.get("sleep", 0), 1, "a night slept")
	t.check(host.clock_jumped, "the clock jump is flagged for the clients")
	t.eq(rules.start_long_rest(ann), "you slept less than a day ago", "once per day")
	host.sleep(15.0)
	t.eq(rules.start_long_rest(ann), "", "a day after the last one began, again")
	rules.stand(ann)
	# solo
	var r2 := rig()
	var h2: WorldHost = r2[0]
	var solo := h2.add_player("solo", 2)
	h2.tick()
	var bc := cell(solo, 1)
	h2.world.set_fg(bc.x, bc.y, TileDefs.id("bed"))
	(r2[1] as RulesSystem).start_long_rest(solo)
	var d0 := h2.clock.day()
	h2.tick()
	t.eq(h2.clock.day(), d0 + 1, "a lone player sleeps through the night")
	# leaving the bed
	var r3 := rig()
	var h3: WorldHost = r3[0]
	var p := h3.add_player("p", 2)
	var q := h3.add_player("q", 3)
	h3.tick()
	var c3 := cell(p, 1)
	h3.world.set_fg(c3.x, c3.y, TileDefs.id("bed"))
	(r3[1] as RulesSystem).start_long_rest(p)
	h3.tick()
	h3.world.set_fg(c3.x, c3.y, TileDefs.AIR)
	h3.tick()
	t.eq((r3[1] as RulesSystem).sheet(p)["resting"], RulesCodec.Resting.NONE, "a bed dug out from under you wakes you")
	t.eq(q.name, "q", "q stayed up")

func _long_sim(t: TestLog) -> void:
	var world := WorldGen.generate_named("dev", 3)
	var host := WorldHost.new(world)
	var rules := RulesSystem.new()
	host.add_system(rules)
	var e := host.add_player("sim", 2)
	host.tick()
	var c := cell(e, 1)
	host.world.set_fg(c.x, c.y, TileDefs.AIR)
	host.world.set_fg(c.x, c.y, TileDefs.id("bed"))
	for m: HostEntity in host.entities.values():
		if m.kind == HostEntity.Kind.MONSTER:
			host.remove_entity(m.id)
	var sim_t := host.sim.t
	t.eq(rules.start_long_rest(e), "", "a bed on a generated world")
	host.tick()
	t.check(host.sim_behind() > 0, "the night passed and the sim is behind (%d h)" % host.sim_behind())
	var n := 0
	while host.sim_behind() > 0 and n < 2000:
		host.tick()
		n += 1
	t.eq(host.sim_behind(), 0, "the sim catches up through the normal budget (%d ticks)" % n)
	t.check(host.sim.t > sim_t + 15, "the sim stepped through the night (%d -> %d)" % [sim_t, host.sim.t])

func _downed(t: TestLog) -> void:
	var r := rig()
	var host: WorldHost = r[0]
	var rules: RulesSystem = r[1]
	var ann := host.add_player("ann", 2)
	var bob := host.add_player("bob", 3)
	host.tick()
	# three successes: stable, then up at 1 HP
	rules.test_d20 = [12, 15, 10]
	ann.combatant.stats.current_hp = 0
	host.tick()
	t.check(rules.is_downed(ann), "0 HP: downed")
	t.check(ann.combatant.conditions.has(SRD.Condition.UNCONSCIOUS), "and Unconscious")
	secs(host, 3.9)
	t.eq(ann.combatant.death_saves.successes, 0, "no save before 4 s")
	secs(host, 0.2)
	t.eq(ann.combatant.death_saves.successes, 1, "one save at 4 s")
	secs(host, 8.0)
	t.eq(rules.sheet(ann)["state"], Down.STABLE, "three successes: stable")
	t.eq(ann.combatant.stats.current_hp, 0, "still at 0")
	secs(host, RulesSystem.STABLE_SECONDS + 0.1)
	t.check(not rules.is_downed(ann) and ann.combatant.stats.current_hp == 1, "up at 1 HP after a short delay")
	# a natural 20
	rules.test_d20 = [20]
	rules.player_dropped(ann)
	secs(host, 4.1)
	t.check(not rules.is_downed(ann) and ann.combatant.stats.current_hp == 1, "a natural 20: up with 1 HP")
	# failures, damage while down, death
	rules.test_d20 = [5]
	ann.combatant.stats.current_hp = 0
	rules.player_dropped(ann)
	secs(host, 4.1)
	t.eq(ann.combatant.death_saves.failures, 1, "a failed save")
	rules.player_dropped(ann)
	t.eq(ann.combatant.death_saves.failures, 2, "damage while down is a failure")
	rules.player_dropped(ann, true)
	t.check(rules.is_dead(ann), "a critical hit while down: two more, dead")
	# heal gets you up
	var r2 := rig()
	var h2: WorldHost = r2[0]
	var rs2: RulesSystem = r2[1]
	var cat := h2.add_player("cat", 2)
	h2.tick()
	cat.combatant.stats.current_hp = 0
	rs2.player_dropped(cat)
	t.eq(cat.combatant.stats.heal(5), 0, "the addon's heal does nothing at 0 HP")
	t.eq(rs2.heal(cat, 5), 5, "the rules system's heal does")
	t.check(not rs2.is_downed(cat) and cat.combatant.stats.current_hp == 5, "healing gets a downed player up")
	rs2.player_dropped(cat)
	cat.combatant.stats.current_hp = 3      # something wrote HP directly (a potion)
	h2.tick()
	t.check(not rs2.is_downed(cat), "any healing gets them up")
	# held in place; digs refused
	rs2.player_dropped(cat)
	var at := cat.body.pos
	var ep := cat.epoch
	h2.submit_state(cat.id, cat.epoch, 500, at + Vector2(1.0, 0), Vector2.ZERO, HostEntity.F_FLOOR)
	h2.tick()
	t.eq(cat.body.pos, at, "a downed body's client cannot move it")
	t.check(cat.epoch != ep, "the host corrected it (epoch %d -> %d)" % [ep, cat.epoch])
	var corr := h2.outbox.filter(func(ev: Dictionary) -> bool: return ev["type"] == WorldHost.Ev.CORRECT and ev["id"] == cat.id)
	t.check(not corr.is_empty() and corr[-1]["epoch"] == cat.epoch, "with a CORRECT to its owner")
	# revive
	rules.respawn(ann)
	ann.combatant.stats.current_hp = 0
	host.tick()
	t.check(rules.is_downed(ann), "ann down again")
	bob.body.pos = ann.body.pos + Vector2(10, 0)
	t.eq(rules.revive(bob, ann.id), "out of reach", "revive needs reach")
	bob.body.pos = ann.body.pos + Vector2(1.5, 0)
	t.eq(rules.revive(bob, bob.id), "no one to revive", "not yourself")
	rules.test_d20 = [10, 10]
	t.eq(rules.revive(bob, ann.id), "", "bob holds revive")
	secs(host, 1.5)
	t.check(rules.is_downed(ann), "not yet at 1.5 s")
	secs(host, 0.6)
	t.check(not rules.is_downed(ann) and ann.combatant.stats.current_hp == 1, "up at 1 HP after 2 s")
	t.eq(bob.character.deeds.get("revive", 0), 1, "a revive deed for bob")
	ann.combatant.stats.current_hp = 0
	host.tick()
	rules.revive(bob, ann.id)
	secs(host, 1.0)
	rules.revive(bob, 0)
	secs(host, 1.5)
	t.check(rules.is_downed(ann), "letting go stops the revive")

func _respawn(t: TestLog) -> void:
	var r := rig()
	var host: WorldHost = r[0]
	var rules: RulesSystem = r[1]
	var ann := host.add_player("ann", 2, {"class": "cleric"})
	rules.award_xp(ann.id, LevelTrack.xp_for_level(20))
	host.tick()
	var bed := cell(ann, -30)
	host.world.set_fg(bed.x, bed.y, TileDefs.id("bed"))
	ann.character.bed = bed
	t.eq(rules.respawn(ann), false, "no respawn while alive")
	ann.combatant.energy_slots.use_slot(1)
	ann.combatant.stats.hit_dice_remaining = 0
	rules.debug(ann, RulesCodec.Debug.DIE, 0)
	t.check(rules.is_dead(ann), "dead")
	var ep := ann.epoch
	t.check(rules.respawn(ann), "respawn")
	t.eq(ann.body.pos, Vector2(bed.x + 0.5, bed.y), "at the bed")
	t.check(ann.epoch != ep, "a clean teleport (epoch bumped)")
	t.eq(ann.combatant.stats.current_hp, ann.combatant.stats.max_hp, "full HP")
	t.eq(ann.combatant.stats.hit_dice_remaining, ann.character.hit_dice_max(), "all Hit Point Dice")
	t.eq(ann.combatant.energy_slots.slots_remaining_at(1), ann.combatant.energy_slots.slots_max_at(1), "slots back")
	t.eq(ann.character.level, 20, "nothing lost")
	# no bed: the nearest shrine
	host.world.set_fg(bed.x, bed.y, TileDefs.AIR)
	var near := cell(ann, 20)
	var far := cell(ann, -60)
	host.world.set_fg(near.x, near.y, TileDefs.id("shrine"))
	host.world.set_fg(far.x, far.y, TileDefs.id("shrine"))
	rules.debug(ann, RulesCodec.Debug.DIE, 0)
	rules.respawn(ann)
	t.eq(ann.body.pos, Vector2(near.x + 0.5, near.y), "bed gone: the nearest shrine")
	# nothing: the spawn, and on its own after the delay
	host.world.set_fg(near.x, near.y, TileDefs.AIR)
	host.world.set_fg(far.x, far.y, TileDefs.AIR)
	rules.debug(ann, RulesCodec.Debug.DIE, 0)
	secs(host, RulesSystem.RESPAWN_SECONDS - 1.0)
	t.check(rules.is_dead(ann), "still dead before the delay")
	secs(host, 1.1)
	t.check(not rules.is_dead(ann), "respawned after the delay")
	t.check(ann.body.pos.distance_to(host.spawn) < 0.6, "at the world spawn (%s vs %s)" % [ann.body.pos, host.spawn])

func _persist(t: TestLog) -> void:
	var r := rig()
	var host: WorldHost = r[0]
	var rules: RulesSystem = r[1]
	var ann := host.add_player("ann", 2, {"class": "wizard"})
	host.tick()
	Knacks.add_deed(ann.character.deeds, "dig:stone", 41)
	rules.award_xp(ann.id, LevelTrack.xp_for_level(24) + 5)     # pending choices and a knack offer
	var b := cell(ann, 1)
	host.world.set_fg(b.x, b.y, TileDefs.id("bed"))
	rules.start_long_rest(ann)
	host.tick()      # solo: sleeps
	rules.answer(ann, "knack:4", [rules.pending(ann).filter(func(p: Dictionary) -> bool: return p["kind"] == "knack")[0]["options"][0]["id"]])
	ann.combatant.energy_slots.use_slot(1)
	ann.combatant.energy_slots.use_slot(2)
	ann.combatant.kit.spend("arcane_recovery")
	ann.combatant.stats.current_hp = 0
	rules.test_d20 = [3]
	host.tick()
	secs(host, 4.1)
	var before := rules.sheet(ann)
	var pend_before := rules.pending(ann).map(func(p: Dictionary) -> String: return p["key"])
	var deeds := ann.character.deeds.duplicate()
	t.check(pend_before.size() >= 2, "things are pending (%s)" % [pend_before])
	t.eq(before["state"], Down.DOWNED, "ann is down with a failure")
	# through JSON, the way the record is stored
	host.remove_entity(ann.id)
	var rec: Dictionary = JSON.parse_string(JSON.stringify(host.records["ann"]))
	var r2 := rig()
	var h2: WorldHost = r2[0]
	var rs2: RulesSystem = r2[1]
	h2.records["ann"] = rec
	var back := h2.add_player("ann", 9)
	var after := rs2.sheet(back)
	t.eq(after, before, "the whole sheet survives save, quit and rejoin")
	t.eq(rs2.pending(back).map(func(p: Dictionary) -> String: return p["key"]), pend_before, "pending choices too")
	t.eq(back.character.deeds, deeds, "deeds")
	t.eq(typeof(back.character.deeds["dig"]), TYPE_INT, "deeds come back as ints")
	t.eq(back.character.bed, b, "the bed")
	t.check(rs2.is_downed(back), "still downed")
	t.eq(back.combatant.death_saves.failures, 1, "with the failure")
	t.check(not rs2.long_rest_ready(back), "the once-a-day rest clock")
	var k: Dictionary = rs2.pending(back).filter(func(p: Dictionary) -> bool: return p["kind"] == "knack")[0] \
			if rs2.pending(back).any(func(p: Dictionary) -> bool: return p["kind"] == "knack") else {}
	if not k.is_empty():
		t.eq(rs2.answer(back, k["key"], [k["options"][0]["id"]]), "", "a restored knack offer can be answered")
