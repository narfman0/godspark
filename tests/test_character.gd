## Character: creation with default builds, levels 1 / 24 / 50 / 100 for the four first
## classes, hit points from the level track, the combatant's class level, round trips.
extends RefCounted

const CLASSES := ["fighter", "rogue", "wizard", "cleric"]

func run(t: TestLog) -> void:
	var srd := WorldHost.shared_srd()
	t.check(srd != null, "shared SRD content (built in %d ms)" % (WorldHost.srd_build_usec / 1000))
	for cls: String in Character.HIT_DIE:
		t.eq(Character.HIT_DIE[cls], srd.make_class(cls).hit_die, "%s hit die matches the SRD" % cls)

	for cls: String in CLASSES:
		var ch := Character.create("ann", cls, [], [], "", "", srd)
		t.eq([ch.level, ch.class_level(), ch.hp, ch.max_hp()], [1, 1, ch.max_hp(), LevelTrack.max_hp(1, ch.hit_die(), ch.con_mod())],
				"%s: level 1, full hit points" % cls)
		t.check(ch.pending_choices(srd).is_empty(), "%s: class level 1 choices answered at creation" % cls)
		var t0 := Time.get_ticks_usec()
		var c := ch.make_combatant(srd)
		var us := Time.get_ticks_usec() - t0
		t.check(c != null and c.kit != null and c.kit.level == 1 and c.weapon != null,
				"%s: level-1 combatant with a weapon (%d us)" % [cls, us])
		for target in [24, 50, 100]:
			var rewards := {}
			while ch.level < target:
				var r := ch.gain_level()
				rewards[r] = int(rewards.get(r, 0)) + 1
			var answered := ch.auto_choices(srd)
			t0 = Time.get_ticks_usec()
			c = ch.make_combatant(srd)
			us = Time.get_ticks_usec() - t0
			var ok := c != null and c.kit != null
			t.check(ok, "%s level %d builds (%d choices auto-answered, combatant in %d us)" % [cls, target, answered, us])
			if not ok:
				continue
			var want := LevelTrack.max_hp(target, ch.hit_die(), c.stats.ability_modifier(SRD.Ability.CONSTITUTION))
			t.eq([c.kit.level, c.stats.level], [ch.class_level(), ch.class_level()], "%s %d: combatant at class level %d" % [cls, target, ch.class_level()])
			t.eq([c.stats.max_hp, ch.max_hp(), c.stats.current_hp], [want, want, want], "%s %d: hit points from the level track, full" % [cls, target])
			t.check(ch.pending_choices(srd).is_empty(), "%s %d: nothing left to choose" % [cls, target])
		t.eq(ch.spark_slots(), 40, "%s at 100: 40 spark slots" % cls)
		t.eq(ch.hit_dice_left, ch.hit_dice_max(), "%s: hit dice kept full while levelling" % cls)
		t.eq(ch.gain_level(), LevelTrack.Reward.EPIC_BOON, "%s: no level past 100" % cls)
		t.eq(ch.level, 100, "%s: stays 100" % cls)

	# a wizard's spells and a fighter's ASI come from the build
	var wiz := Character.create("w", "wizard", [], [], "", "", srd)
	while wiz.level < 24:
		wiz.gain_level()
	wiz.auto_choices(srd)
	t.check("fireball" in wiz.resolved()["spells"], "a level-24 wizard has Fireball by default")
	var f := Character.create("f", "fighter", [], [], "", "", srd)
	while f.level < 15:
		f.gain_level()
	f.auto_choices(srd)
	t.check(int(f.resolved()["scores"][0]) > 15, "a fighter's ASI raised Strength (%s)" % [f.resolved()["scores"]])

	# hit points follow levels and carry over
	var r := Character.create("r", "rogue", [], [], "", "", srd)
	r.hp = 3
	var before := r.max_hp()
	t.eq(r.gain_level(), LevelTrack.Reward.VIGOR, "level 2 is Vigor")
	t.eq(r.hp, 3 + r.max_hp() - before, "current hit points rise with the max")
	var rc := r.make_combatant(srd)
	t.eq(rc.stats.current_hp, r.hp, "the combatant starts at the record's hit points")
	rc.stats.current_hp = 1
	r.capture(rc)
	t.eq(r.hp, 1, "capture copies play back")
	t.eq(r.move_stats(rc).walk, 30.0, "move stats from the combatant's speed")
	t.eq(r.move_stats(rc).size_name, "medium", "Medium")

	# round trip, through JSON too
	var w := Character.create("Wen", "cleric", [], ["insight", "religion"], "dwarf", "", srd)
	for i in 11:
		w.gain_level()
	w.auto_choices(srd)
	w.xp = 12345
	w.knacks = ["bond:dwarf"]
	w.deeds = {"dug": 40, "kills:undead": 3}
	w.bed = Vector2i(12, -4)
	w.uses_left = {"channel_divinity": 1}
	var d := w.to_dict()
	t.eq(Character.from_dict(d).to_dict(), d, "dict round trip is exact")
	var j: Variant = JSON.parse_string(JSON.stringify(d))
	t.eq(Character.from_dict(j).to_dict(), d, "and through JSON")
	t.eq(Character.from_dict(j).make_combatant(srd).stats.max_hp, w.make_combatant(srd).stats.max_hp, "the reloaded character builds the same")
	t.eq(Character.from_dict({"name": "x"}), null, "not a character: null")
	var none := Character.create("n", "wizard")
	t.eq(Character.from_dict(none.to_dict()).bed, null, "no bed stays none")
	t.eq(none.build["scores"], Character.DEFAULTS["wizard"]["scores"], "default scores")
	t.eq([none.species, none.background], ["human", "sage"], "default species and background")
