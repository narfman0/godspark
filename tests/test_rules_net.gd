## The rules system over a loopback link with two clients: sheets mirrored to their owners,
## levels and a Knack picked from the client, a short rest, a long rest that waits for the
## second player, a downed player who cannot move and is revived by the other's client.
extends RefCounted

const Rig := preload("res://tests/net_rig.gd")
const Down := RulesCodec.Down

func run(t: TestLog) -> void:
	var world := TileWorld.make_test(512, 128)
	var rig := Rig.new(world, 0.03)
	var rules := RulesSystem.new()
	rig.host.add_system(rules)
	var rc: Array[RulesClient] = []
	for n in ["ann", "bob"]:
		var c := rig.add_client(n)
		var r := RulesClient.new()
		rc.append(r)
		c.welcomed.connect(func(cw: ClientWorld) -> void: cw.add_system(r))
	var ready := rig.until(func() -> bool:
		return rig.clients.all(func(c: ClientEndpoint) -> bool: return c.cw != null and c.cw.area_ready()), 6.0)
	t.check(ready >= 0.0, "two clients joined")
	rig.run(0.3)
	var ann := rig.host_entity(0)
	var bob := rig.host_entity(1)
	t.eq(rc[0].level(), 1, "ann has her sheet")
	t.eq(rc[0].sheet["class"], "fighter", "with her class")
	t.eq(rc[0].sheet["max_hp"], ann.combatant.stats.max_hp, "and her hit points")

	# levels and a Knack, answered from the client
	var levels := []
	rc[0].leveled.connect(func(l: int, rw: int) -> void: levels.append([l, rw]))
	var asked := []
	rc[0].choice_pending.connect(func(c: Dictionary) -> void: asked.append(c["key"]))
	var gains := []
	rc[0].xp_gained.connect(func(n: int, _s: String) -> void: gains.append(n))
	rules.award_xp(ann.id, LevelTrack.xp_for_level(4), "test")
	rig.run(0.3)
	t.eq(levels, [[2, LevelTrack.Reward.VIGOR], [3, LevelTrack.Reward.SPARK_SLOT], [4, LevelTrack.Reward.KNACK]], "leveled(level, reward) per level")
	t.eq(gains, [LevelTrack.xp_for_level(4)], "xp_gained")
	t.eq(rc[0].level(), 4, "the sheet follows")
	t.eq(asked, ["knack:4"], "the Knack offer arrives as a pending choice")
	var offer: Dictionary = rc[0].choices.get("knack:4", {})
	t.eq((offer.get("options", []) as Array).size(), 3, "with three options")
	t.eq(rc[1].level(), 1, "bob's sheet is his own")
	rc[0].answer("4:asi", ["ability-score-improvement", "str", "str"])
	rig.run(0.3)
	t.check(rc[0].notices.size() > 0 and rc[0].notices[-1].begins_with("answer refused"), "a bad answer comes back as a notice")
	var pick: String = offer["options"][1]["id"]
	rc[0].pick_knack(pick)
	rig.run(0.3)
	t.eq(rc[0].sheet["knacks"], [pick], "the Knack is taken")
	t.eq(rc[0].pending_keys(), [], "nothing pending")
	t.check(not rc[0].choices.has("knack:4"), "the client forgot the answered choice")

	# a short rest
	var at := Vector2i(floori(ann.body.pos.x) + 2, floori(ann.body.pos.y))
	rig.host.world.set_fg(at.x, at.y, TileDefs.id("campfire"))
	ann.combatant.stats.current_hp -= 6
	rig.run(0.3)
	var hp0 := rig.cw(0).hp
	var rests := []
	rc[0].rest_event.connect(func(ev: Dictionary) -> void: rests.append(ev))
	rc[0].rest_short()
	rig.run(5.6)
	t.check(not rests.is_empty() and rests[-1]["event"] == RulesCodec.RestEv.SHORT_DONE, "the short rest finished (%s)" % [rests])
	t.check(rig.cw(0).hp > hp0, "and healed (VITALS %d -> %d)" % [hp0, rig.cw(0).hp])

	# a long rest: ann waits for bob
	var b1 := Vector2i(floori(ann.body.pos.x) - 1, floori(ann.body.pos.y))
	var b2 := Vector2i(floori(bob.body.pos.x) + 1, floori(bob.body.pos.y))
	rig.host.world.set_fg(b1.x, b1.y, TileDefs.id("bed"))
	rig.host.world.set_fg(b2.x, b2.y, TileDefs.id("bed"))
	rig.run(0.2)
	var day := rig.host.clock.day()
	rests.clear()
	rc[0].rest_long()
	rig.run(1.0)
	t.check(not rests.is_empty() and rests[-1]["event"] == RulesCodec.RestEv.BED_WAIT and rests[-1]["names"] == ["bob"], "ann is told bob is still up (%s)" % [rests])
	t.eq(rc[0].sheet["resting"], RulesCodec.Resting.BED, "her sheet says she is in bed")
	t.eq(rig.host.clock.day(), day, "no night yet")
	rc[1].rest_long()
	rig.run(1.0)
	t.eq(rig.host.clock.day(), day + 1, "both in bed: the night passed")
	t.check(absf(fposmod(rig.cw(0).hours(), 24.0) - RulesSystem.WAKE_HOUR) < 0.2, "ann's client clock says morning (%s)" % WorldClock.describe(rig.cw(0).hours()))
	t.eq(rests[-1]["event"], RulesCodec.RestEv.BED_DONE, "BED_DONE")
	t.check(rc[0].sheet["bed"] != null and not rc[0].sheet["rest_ready"], "a bed to wake at, and no second rest today")

	# downed: frozen, seen by bob, revived by bob's client
	var downs := []
	rc[1].downed_changed.connect(func(id: int, st: int, _s: int, _f: int) -> void: downs.append([id, st]))
	rules.test_d20 = [10, 10, 10]
	ann.combatant.stats.current_hp = 0
	rig.run(0.4)
	t.check(rules.is_downed(ann), "ann is down")
	t.eq(rc[0].state_of(ann.id), Down.DOWNED, "she knows")
	t.check(downs.has([ann.id, Down.DOWNED]), "bob sees her go down")
	t.eq(rig.cw(0).stats.run_speed, 0.0, "her client's movement is frozen")
	var x0 := rig.cw(0).body.pos.x
	rig.inputs[0].move_x = 1.0
	rig.run(0.6)
	rig.inputs[0].move_x = 0.0
	t.check(absf(rig.cw(0).body.pos.x - x0) < 0.05, "her body does not move on her client")
	t.check(absf(ann.body.pos.x - x0) < 0.35, "nor on the host")
	bob.body.pos = ann.body.pos + Vector2(1.0, 0)      # the host's word; bob's client follows on its next state
	rig.cw(1).body.pos = bob.body.pos
	rc[1].revive(ann.id)
	rig.run(2.4)
	t.check(not rules.is_downed(ann), "bob's revive got her up")
	t.eq(rc[0].state_of(ann.id), Down.UP, "her client knows")
	t.check(rig.cw(0).stats.run_speed > 0.0, "and can move again")
	t.check(rc[0].notices[-1].contains("bob"), "she is told who did it (%s)" % rc[0].notices[-1])
	t.check(downs[-1] == [ann.id, Down.UP], "bob saw her get up")
	# death and respawn at her bed
	rc[0].debug(RulesCodec.Debug.DIE)
	rig.run(0.3)
	t.check(rc[0].notices[-1] == "cheats are off", "DEBUG needs cheats")
	rules.cheats = true
	rc[0].debug(RulesCodec.Debug.DIE)
	rig.run(0.3)
	t.eq(rc[0].state_of(ann.id), Down.DEAD, "dead")
	var corr0 := rig.cw(0).corrections
	rc[0].respawn()
	rig.run(0.5)
	t.eq(rc[0].state_of(ann.id), Down.UP, "respawned")
	t.check(rig.cw(0).corrections > corr0, "her client was moved by a correction")
	t.check(rig.cw(0).body.pos.distance_to(Vector2(b1.x + 0.5, b1.y)) < 0.3, "to her bed (%s)" % rig.cw(0).body.pos)
	t.eq(rig.cw(0).hp, ann.combatant.stats.max_hp, "with full hit points")
	rig.run(0.5)
	t.check(ann.body.pos.distance_to(rig.cw(0).body.pos) < 0.3, "the host and her client agree where she is")
	rc[0].debug(RulesCodec.Debug.LEVEL, 24)
	rc[0].debug(RulesCodec.Debug.AUTO)
	rig.run(0.5)
	t.eq([rc[0].level(), rc[0].sheet["class_level"], rc[0].pending_keys()], [24, 5, []], "debug level 24 and auto answers")
