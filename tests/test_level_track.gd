## LevelTrack: the 100-level map, reward rhythm, counts, XP and hit points against the SRD.
extends RefCounted

const R := LevelTrack.Reward

func run(t: TestLog) -> void:
	# class levels
	var cl := {1: 1, 4: 1, 5: 2, 9: 2, 10: 3, 24: 5, 50: 11, 94: 19, 95: 20, 99: 20, 100: 20}
	for lvl: int in cl:
		t.eq(LevelTrack.class_level(lvl), cl[lvl], "class level at %d" % lvl)
	for c in range(2, 21):
		t.eq(LevelTrack.class_level(5 * (c - 1)), c, "class level %d starts at level %d" % [c, 5 * (c - 1)])
	# rhythm
	t.eq([LevelTrack.reward(1), LevelTrack.reward(2), LevelTrack.reward(3), LevelTrack.reward(4), LevelTrack.reward(5)],
			[R.SPARK_SLOT, R.VIGOR, R.SPARK_SLOT, R.KNACK, R.CLASS_LEVEL], "the beat of a band")
	t.eq([LevelTrack.reward(96), LevelTrack.reward(97), LevelTrack.reward(98), LevelTrack.reward(99), LevelTrack.reward(100)],
			[R.SPARK_SLOT, R.VIGOR, R.SPARK_SLOT, R.KNACK, R.EPIC_BOON], "the last band ends in the Epic Boon")
	# counts agree with walking the rhythm
	var tally := {}
	var ok := true
	for lvl in range(1, 101):
		var r := LevelTrack.reward(lvl)
		tally[r] = int(tally.get(r, 0)) + 1
		ok = ok and LevelTrack.spark_slots(lvl) == int(tally.get(R.SPARK_SLOT, 0)) \
				and LevelTrack.vigor_steps(lvl) == int(tally.get(R.VIGOR, 0)) \
				and LevelTrack.knacks(lvl) == int(tally.get(R.KNACK, 0)) \
				and LevelTrack.count(lvl, R.CLASS_LEVEL) == int(tally.get(R.CLASS_LEVEL, 0))
	t.check(ok, "closed-form counts match the rhythm at every level")
	t.eq([LevelTrack.spark_slots(100), LevelTrack.vigor_steps(100), LevelTrack.knacks(100)], [40, 20, 20],
			"40 spark slots, 20 Vigor, 20 Knacks at 100")
	t.eq(LevelTrack.count(100, R.CLASS_LEVEL), 19, "19 class levels after the first")
	t.eq(LevelTrack.spark_slots(1), 1, "level 1 brings the first spark slot")

	# XP
	var th := SRDExperience.XP_THRESHOLDS
	t.eq(LevelTrack.xp_for_level(1), 0, "level 1 needs nothing")
	var anchors := true
	for c in range(2, 21):
		anchors = anchors and LevelTrack.xp_for_level(5 * (c - 1)) == roundi(th[c - 1] * LevelTrack.XP_SCALE)
	t.check(anchors, "each class level needs the SRD's XP (times XP_SCALE)")
	t.eq(LevelTrack.xp_for_level(7), roundi((300 + 600 * 2 / 5.0) * LevelTrack.XP_SCALE), "between: the gap in fifths")
	t.eq(LevelTrack.xp_for_level(3), roundi(150 * LevelTrack.XP_SCALE), "the first band: the gap in quarters")
	t.eq(LevelTrack.xp_for_level(100), roundi(405000 * LevelTrack.XP_SCALE), "level 100: one more of the last SRD gap")
	var mono := true
	for lvl in range(2, 101):
		mono = mono and LevelTrack.xp_for_level(lvl) > LevelTrack.xp_for_level(lvl - 1)
	t.check(mono, "XP strictly increases")
	var xp5 := LevelTrack.xp_for_level(5)
	t.eq([LevelTrack.level_for_xp(0), LevelTrack.level_for_xp(xp5 - 1), LevelTrack.level_for_xp(xp5), LevelTrack.level_for_xp(10 ** 9)],
			[1, 4, 5, 100], "level_for_xp inverts it")

	# hit points
	for c in [["fighter", 10, 2], ["wizard", 6, 1], ["rogue", 8, 0], ["barbarian", 12, -1], ["wizard", 6, -3]]:
		var hd: int = c[1]
		var con: int = c[2]
		var exact := true
		for k in range(1, 21):
			var lvl := 1 if k == 1 else 5 * (k - 1)
			var srd := LevelTrack.srd_hp(k, hd, con)
			exact = exact and LevelTrack.max_hp(lvl, hd, con) - LevelTrack.vigor_steps(lvl) * LevelTrack.vigor_hp(hd) == srd
		t.check(exact, "%s d%d CON %+d: SRD fixed total at every class level before Vigor" % c)
		var nondec := true
		for lvl in range(2, 101):
			nondec = nondec and LevelTrack.max_hp(lvl, hd, con) >= LevelTrack.max_hp(lvl - 1, hd, con)
		t.check(nondec, "%s d%d CON %+d: never decreases" % c)
	# fighter d10 CON +2: level 1 = 12, each class level +8
	t.eq(LevelTrack.max_hp(1, 10, 2), 12, "level 1 fighter: 10 + 2")
	t.eq(LevelTrack.max_hp(2, 10, 2), 12 + 2 + 5, "level 2: a quarter of the next gain (2) and Vigor (5)")
	t.eq(LevelTrack.max_hp(5, 10, 2), 20 + 5, "level 5 = SRD class level 2 (20) plus one Vigor")
	t.eq(LevelTrack.max_hp(95, 10, 2), 12 + 19 * 8 + 19 * 5, "level 95 = SRD class level 20 plus 19 Vigor")
	t.eq(LevelTrack.max_hp(100, 10, 2), 12 + 20 * 8 + 20 * 5, "level 100: one more gain past 20, 20 Vigor")
	t.eq(LevelTrack.vigor_hp(6), 3, "Vigor on a d6: 3")
	t.eq(LevelTrack.vigor_hp(10), 5, "on a d10: 5")
	t.eq(LevelTrack.max_hp(7, 6, 0) - LevelTrack.max_hp(6, 6, 0), 3 + (4 * 2 / 5 - 4 * 1 / 5), "a Vigor level adds half a die on top of the fifth")
	t.eq([LevelTrack.hit_dice(1), LevelTrack.hit_dice(2), LevelTrack.hit_dice(100)], [1, 2, 40], "Hit Point Dice: class levels plus Vigor")
