## RulesSystem: XP and multi-level gains, the reward for every level 1..100 for the four
## classes, pending SRD choices (ask, answer, refuse), Knack offers and deeds.
extends RefCounted

func run(t: TestLog) -> void:
	for f: Callable in [_xp, _choices, _knacks, _deeds, _hundred]:
		var t0 := Time.get_ticks_msec()
		f.call(t)
		print("  %s: %d ms" % [f.get_method(), Time.get_ticks_msec() - t0])

static func rig(w := 256, h := 128) -> Array:
	var host := WorldHost.new(TileWorld.make_test(w, h))
	var rules := RulesSystem.new()
	host.add_system(rules)
	return [host, rules]

func _xp(t: TestLog) -> void:
	var r := rig()
	var host: WorldHost = r[0]
	var rules: RulesSystem = r[1]
	var ann := host.add_player("ann", 2, {"class": "fighter"})
	var bob := host.add_player("bob", 3, {"class": "rogue"})
	var carl := host.add_player("carl", 4)
	carl.body.pos.x += 60.0
	t.check(rules.sheet(ann)["level"] == 1 and ann.combatant != null, "a joining player has a sheet")
	var gob := host.add_srd_monster("goblin-warrior", ann.body.pos + Vector2(3, 0))
	for e: HostEntity in [ann, bob, carl, gob]:     # a surface kill: no depth divisor (data/rules/xp.json)
		e.body.pos.y = host.world.height * 0.7
	var per := host.srd.monster_xp("goblin-warrior")
	t.eq(rules.band_divisor(gob), 1.0, "the surface has no XP divisor")
	rules.on_kill(gob, [ann.id])
	t.eq(ann.character.xp, per, "the killer gets the stat block's XP")
	t.eq(bob.character.xp, per, "a player nearby gets it in full (no split)")
	t.eq(carl.character.xp, 0, "a player far away gets none")
	var gtype := String(host.srd.pack.get_row("monster", "goblin-warrior")["data"]["type"])
	t.eq(ann.character.deeds.get("kill:" + gtype, 0), 1, "a kill deed by creature type (%s)" % gtype)
	gob.set_meta("rank", "elite")
	rules.on_kill(gob, [])
	t.eq(ann.character.xp, per * 3, "an elite is worth double")
	gob.set_meta("xp_mult", 0.25)
	rules.on_kill(gob, [])
	t.eq(ann.character.xp, per * 3 + roundi(per * 0.25), "meta xp_mult overrides the rank")
	# multi-level
	var before_hp := ann.combatant.stats.current_hp
	var before_max := ann.combatant.stats.max_hp
	var before_lvl := ann.character.level
	var levels := rules.award_xp(ann.id, LevelTrack.xp_for_level(7) - ann.character.xp)
	t.eq(ann.character.level, 7, "XP to level 7 at once")
	t.eq(levels, 7 - before_lvl, "several levels gained at once (%d)" % levels)
	t.eq(ann.combatant.stats.max_hp, LevelTrack.max_hp(7, 10, 2), "max HP follows the level track")
	t.eq(ann.combatant.stats.current_hp, before_hp + ann.combatant.stats.max_hp - before_max, "current HP grows with the max")
	t.eq(ann.combatant.stats.level, 2, "class level 2 at level 7")
	t.eq(ann.combatant.stats.hit_dice_remaining, LevelTrack.hit_dice(7), "hit dice grow")
	t.eq(rules.pending(ann).filter(func(p: Dictionary) -> bool: return p["kind"] == "knack").size(), 1, "level 4 opened a Knack offer")
	t.eq(rules.award_xp(ann.id, 0), 0, "no XP, no change")
	rules.award_xp(ann.id, 10 ** 9)
	t.eq(ann.character.level, 100, "the track stops at 100")
	t.check(rules.pending(ann).any(func(p: Dictionary) -> bool: return p["key"] == "boon"), "level 100 opens an Epic Boon pick")

func _hundred(t: TestLog) -> void:
	for cls: String in ["fighter", "rogue", "wizard", "cleric"]:
		var r := rig()
		var host: WorldHost = r[0]
		var rules: RulesSystem = r[1]
		var e := host.add_player("p", 2, {"class": cls})
		var ok := true
		var hp_ok := true
		var slots_ok := true
		var knacks := 0
		for lvl in range(2, 101):
			rules.award_xp(e.id, LevelTrack.xp_for_level(lvl) - e.character.xp)
			knacks += 1 if LevelTrack.reward(lvl) == LevelTrack.Reward.KNACK else 0
			rules.auto_answer(e)
			ok = ok and e.character.level == lvl and e.combatant.stats.level == LevelTrack.class_level(lvl)
			var con := e.combatant.stats.ability_modifier(SRD.Ability.CONSTITUTION)
			hp_ok = hp_ok and e.combatant.stats.max_hp == LevelTrack.max_hp(lvl, Character.HIT_DIE[cls], con)
			slots_ok = slots_ok and rules.sheet(e)["spark_slots"] == LevelTrack.spark_slots(lvl)
		t.check(ok, "%s: every level 2..100 lands with the right class level" % cls)
		t.check(hp_ok, "%s: max HP equals LevelTrack at every level" % cls)
		t.check(slots_ok, "%s: spark slots follow the level" % cls)
		t.eq(e.character.knacks.size(), LevelTrack.knacks(100), "%s: 20 Knacks by level 100" % cls)
		t.eq(rules.pending(e), [], "%s: nothing pending after auto answers" % cls)
		t.check(rules.sheet(e)["boon"] != "", "%s: an Epic Boon taken" % cls)
		t.eq(e.character.subclass, host.srd.subclass_slugs(cls)[0], "%s: the SRD subclass at class level 3" % cls)

func _choices(t: TestLog) -> void:
	var r := rig()
	var host: WorldHost = r[0]
	var rules: RulesSystem = r[1]
	var e := host.add_player("fay", 2, {"class": "fighter"})
	rules.award_xp(e.id, LevelTrack.xp_for_level(15) - e.character.xp)   # class level 4: ASI
	var asi := {}
	for p: Dictionary in rules.pending(e):
		if p["key"] == "4:asi":
			asi = p
	t.check(not asi.is_empty(), "class level 4 asks for an ASI or feat (4:asi)")
	var str_before := e.combatant.stats.get_ability(SRD.Ability.STRENGTH)
	t.eq(str_before, 15, "withheld: no ASI applied while it is pending")
	t.check(rules.answer(e, "4:asi", ["ability-score-improvement", "str"]) != "", "one ability is refused")
	t.check(rules.answer(e, "4:asi", ["ability-score-improvement", "str", "luck"]) != "", "a made-up ability is refused")
	t.check(rules.answer(e, "4:asi", ["boon-of-fate"]) != "", "a feat not on offer is refused")
	t.check(rules.answer(e, "9:asi", ["ability-score-improvement", "str", "str"]) != "", "a choice not pending is refused")
	t.check(rules.answer(e, "knack:99", ["skill-athletics"]) != "", "a knack offer that does not exist is refused")
	var hp_before := e.combatant.stats.max_hp
	t.eq(rules.answer(e, "4:asi", ["ability-score-improvement", "str", "con"]), "", "a good answer is taken")
	t.eq(e.combatant.stats.get_ability(SRD.Ability.STRENGTH), 16, "STR +1 on the rebuilt combatant")
	t.eq(e.combatant.stats.max_hp, hp_before, "CON 14 -> 15 keeps the +2 modifier: same max HP")
	t.eq(e.combatant.stats.get_ability(SRD.Ability.CONSTITUTION), 15, "CON +1")
	t.check(not rules.pending(e).any(func(p: Dictionary) -> bool: return p["key"] == "4:asi"), "no longer pending")
	t.eq(rules.answer(e, "4:asi", ["ability-score-improvement", "str", "con"]) != "", true, "answering twice is refused")
	# a pick-kind choice: weapon mastery
	var wm := {}
	for p: Dictionary in rules.pending(e):
		if p["kind"] == "pick":
			wm = p
	if not wm.is_empty():
		var opts: Array = wm["options"]
		var twice := []
		for i in int(wm["count"]):
			twice.append(opts[0]["id"])
		if int(wm["count"]) > 1:
			t.check(rules.answer(e, wm["key"], twice) != "", "the same option twice is refused")
		t.check(rules.answer(e, wm["key"], ["no-such"]) != "", "a wrong count or option is refused")
	# the wizard's spells
	var w := host.add_player("wiz", 3, {"class": "wizard"})
	rules.award_xp(w.id, LevelTrack.xp_for_level(5) - w.character.xp)
	var sp := {}
	for p: Dictionary in rules.pending(w):
		if p["kind"] == "spell":
			sp = p
	t.check(not sp.is_empty(), "a wizard's class level 2 asks for spells")
	var picks := (sp["options"] as Array).slice(0, int(sp["count"])).map(func(o: Dictionary) -> String: return o["id"])
	var known: int = w.character.resolved()["spells"].size()
	t.eq(rules.answer(w, sp["key"], picks), "", "spells answered")
	t.eq(w.character.resolved()["spells"].size(), known + picks.size(), "and known")

func _knacks(t: TestLog) -> void:
	t.check(Knacks.all().size() >= 30, "at least 30 knacks (%d)" % Knacks.all().size())
	var kinds := {}
	for k: Dictionary in Knacks.all():
		kinds[k["kind"]] = true
		for c: String in k["deeds"]:
			t.check(float(k["deeds"][c]) > 0.0, "deed weights are positive")
			break
	t.eq(kinds.keys().size(), 4, "skills, tools, languages and bonds")
	var cultures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sim/cultures.json"))
	var all_bonded := true
	for c: String in cultures:
		if not c.begins_with("_"):
			all_bonded = all_bonded and Knacks.exists("bond-people-" + c)
	t.check(all_bonded, "a Bond for every people in cultures.json")
	t.eq(Knacks.beast_kind("dire-wolf"), "wolf", "beast kinds from slugs")
	var a := Knacks.offer([], {"dig": 400, "dig:stone": 400}, 77, [])
	t.eq(a, Knacks.offer([], {"dig": 400, "dig:stone": 400}, 77, []), "offers are deterministic")
	t.eq(a.size(), 3, "three offers")
	t.check(a[0] != a[1] and a[1] != a[2] and a[0] != a[2], "three different knacks")
	t.check(not "skill-athletics" in Knacks.offer([], {}, 5, ["athletics"], 80), "a skill already held is never offered")
	var held := Knacks.all().map(func(k: Dictionary) -> String: return k["id"]).slice(0, Knacks.all().size() - 2)
	var last := Knacks.offer(held, {}, 1, [])
	t.eq(last.size(), 2, "only what is not held, even if fewer than three")
	# weighting: a band of swimming makes Navigator's Tools far more likely
	var hits := 0
	var base := 0
	for s in 200:
		if "tool-navigators-tools" in Knacks.offer([], {"swim": 600}, s, []):
			hits += 1
		if "tool-navigators-tools" in Knacks.offer([], {}, s, []):
			base += 1
	t.check(hits > base * 3, "deeds weight the offer (navigator's tools %d/200 after swimming, %d/200 without)" % [hits, base])
	# through the system: no repeats across 20 offers, bonds recorded
	var r := rig()
	var host: WorldHost = r[0]
	var rules: RulesSystem = r[1]
	var e := host.add_player("kit", 2)
	for i in 30:
		Knacks.add_deed(e.character.deeds, "trade:dwarf", 1)
	rules.award_xp(e.id, LevelTrack.xp_for_level(4))
	var offer: Array = rules.pending(e).filter(func(p: Dictionary) -> bool: return p["kind"] == "knack")
	t.eq(offer.size(), 1, "a Knack offer at level 4")
	var ids: Array = offer[0]["options"].map(func(o: Dictionary) -> String: return o["id"])
	var r2 := rig()
	var e2: HostEntity = (r2[0] as WorldHost).add_player("kit", 2)
	for i in 30:
		Knacks.add_deed(e2.character.deeds, "trade:dwarf", 1)
	(r2[1] as RulesSystem).award_xp(e2.id, LevelTrack.xp_for_level(4))
	t.eq((r2[1] as RulesSystem).pending(e2).filter(func(p: Dictionary) -> bool: return p["kind"] == "knack")[0]["options"].map(func(o: Dictionary) -> String: return o["id"]),
			ids, "the same character and deeds get the same offer on another host")
	t.check(rules.pick_knack(e, "skill-nonsense") != "", "a knack not offered is refused")
	var bond_pick := "bond-people-dwarf" if "bond-people-dwarf" in ids else String(ids[0])
	t.eq(rules.pick_knack(e, bond_pick), "", "picked " + bond_pick)
	if bond_pick == "bond-people-dwarf":
		t.eq(rules.bond(e.id, "people:dwarf"), 1, "a Bond is recorded with strength 1")
	t.eq(rules.bond(e.id, "people:elf"), 0, "no bond, 0")
	rules.award_xp(e.id, LevelTrack.xp_for_level(100))
	rules.auto_answer(e)
	var seen := {}
	var dup := false
	for k: String in e.character.knacks:
		dup = dup or seen.has(k)
		seen[k] = true
	t.check(not dup and e.character.knacks.size() == 20, "20 knacks, none twice")
	# a skill knack is applied to the combatant
	var r3 := rig()
	var h3: WorldHost = r3[0]
	var e3 := h3.add_player("sk", 2, {"class": "fighter"})
	(r3[1] as RulesSystem).award_xp(e3.id, LevelTrack.xp_for_level(4))
	var p3: Dictionary = (r3[1] as RulesSystem).pending(e3).filter(func(p: Dictionary) -> bool: return p["kind"] == "knack")[0]
	e3.character.knacks.append("skill-stealth")
	(r3[1] as RulesSystem).refresh(e3)
	t.check(e3.combatant.stats.is_skill_proficient(SRD.Skill.STEALTH), "a skill Knack makes the combatant proficient")
	t.check(p3["options"].size() == 3, "fighter offer has three")
	t.check("stealth" in (r3[1] as RulesSystem).proficiencies(e3.id)["skills"], "proficiencies() lists it")

func _deeds(t: TestLog) -> void:
	var r := rig()
	var host: WorldHost = r[0]
	var rules: RulesSystem = r[1]
	var e := host.add_player("dee", 2)
	host.tick()
	var x := floori(e.body.pos.x) + 2
	var y := floori(e.body.pos.y) - 1
	t.eq(host.request_dig(e.id, 1, x, y), WorldHost.Reason.OK, "dig a grass tile")
	for i in 40:
		host.tick()
	t.eq(e.character.deeds.get("dig:grass", 0), 1, "a dig deed by tile kind")
	t.eq(e.character.deeds.get("dig", 0), 1, "and the aggregate")
	t.eq(host.request_place(e.id, 2, x, y, TileDefs.id("wood")), WorldHost.Reason.OK, "place wood")
	host.tick()
	t.eq(e.character.deeds.get("place:wood", 0), 1, "a place deed")
	# running: the client reports states along the ground
	var seq := 0
	for i in 18:
		seq += 2
		host.submit_state(e.id, e.epoch, seq, e.body.pos + Vector2(0.5, 0), Vector2(9, 0), HostEntity.F_FLOOR)
		host.tick()
	t.eq(e.character.deeds.get("run", 0), 9, "tiles run (9)")
	# underground: in the cave pocket of the test world
	var w := host.world
	e.body.pos = Vector2(w.width / 2.0 - 4.0, w.height / 2.0 - 14.0)
	rules.tick(host)
	for i in K.TICK_HZ * 3:
		rules.tick(host)
	t.eq(e.character.deeds.get("underground:caves", 0), 3, "seconds underground by band")
	rules.add_deed(e.id, "trade:dwarf", 2)
	t.eq([e.character.deeds.get("trade:dwarf"), e.character.deeds.get("trade")], [2, 2], "add_deed for later systems")
