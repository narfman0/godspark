## RulesCodec: every message kind round-trips, and short or padded payloads decode to {}.
extends RefCounted

func run(t: TestLog) -> void:
	_mirrors(t)
	var s := {"level": 24, "xp": 123456, "xp_level": 120000, "xp_next": 130000, "class": "wizard",
		"subclass": "evoker", "species": "human", "background": "sage", "class_level": 5,
		"scores": [8, 13, 14, 16, 12, 10], "hp": 31, "max_hp": 40, "hit_dice": 7, "hit_dice_max": 9,
		"slots": [[4, 4], [2, 3], [1, 2], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0]],
		"uses": {"arcane_recovery": [1, 1]}, "spark_slots": 10, "knacks": ["skill-athletics", "lang-dwarvish"],
		"bonds": {"people:dwarf": 2}, "boon": "", "pending": [{"key": "4:asi", "kind": "asi", "label": "ASI (class level 4)", "count": 1}],
		"state": RulesCodec.Down.STABLE, "successes": 3, "failures": 1, "resting": RulesCodec.Resting.BED,
		"rest_ready": true, "bed": Vector2i(-12, 340)}
	var b := RulesCodec.encode_sheet(s)
	t.eq(RulesCodec.decode_sheet(b), s, "CHAR round-trips")
	var s2 := s.duplicate(true)
	s2["bed"] = null
	t.eq(RulesCodec.decode_sheet(RulesCodec.encode_sheet(s2)), s2, "CHAR without a bed")
	t.eq(RulesCodec.decode_sheet(b.slice(0, b.size() - 1)), {}, "a short CHAR is refused")
	var padded := b.duplicate()
	padded.append(0)
	t.eq(RulesCodec.decode_sheet(padded), {}, "a padded CHAR is refused")
	t.eq(RulesCodec.decode_sheet(PackedByteArray()), {}, "an empty CHAR is refused")
	t.check(b.size() < 300, "a level-24 sheet is small (%d bytes)" % b.size())

	var c := {"key": "5:spells", "kind": "spell", "label": "New Prepared Spells", "count": 2,
		"options": [{"id": "fireball", "name": "Fireball", "level": 3, "modelled": true},
			{"id": "fly", "name": "Fly", "level": 3, "modelled": false}, {"id": "x", "name": "X", "modelled": true}]}
	t.eq(RulesCodec.decode_choice(RulesCodec.encode_choice(c)), c, "CHOICE round-trips")
	var cb := RulesCodec.encode_choice(c)
	t.eq(RulesCodec.decode_choice(cb.slice(0, cb.size() - 3)), {}, "a short CHOICE is refused")
	t.eq(RulesCodec.decode_level(RulesCodec.encode_level(100, LevelTrack.Reward.EPIC_BOON)),
			{"level": 100, "reward": LevelTrack.Reward.EPIC_BOON}, "LEVEL round-trips")
	t.eq(RulesCodec.decode_downed(RulesCodec.encode_downed(70000, 1, 2, 1)),
			{"id": 70000, "state": 1, "successes": 2, "failures": 1}, "DOWNED round-trips")
	t.eq(RulesCodec.decode_downed(PackedByteArray([1, 2])), {}, "a short DOWNED is refused")
	t.eq(RulesCodec.decode_rest(RulesCodec.encode_rest(RulesCodec.RestEv.BED_WAIT, 0, 0, "", ["bob", "carl"])),
			{"event": RulesCodec.RestEv.BED_WAIT, "healed": 0, "dice": 0, "reason": "", "names": ["bob", "carl"]}, "REST round-trips")
	t.eq(RulesCodec.decode_rest(RulesCodec.encode_rest(RulesCodec.RestEv.SHORT_DONE, 17, 2, "é")),
			{"event": RulesCodec.RestEv.SHORT_DONE, "healed": 17, "dice": 2, "reason": "é", "names": []}, "REST with UTF-8")
	t.eq(RulesCodec.decode_gain(RulesCodec.encode_gain(450, "Goblin")), {"xp": 450, "source": "Goblin"}, "GAIN round-trips")
	t.eq(RulesCodec.decode_str(RulesCodec.encode_str("hello")), {"text": "hello"}, "NOTE / KNACK round-trip")
	t.eq(RulesCodec.decode_answer(RulesCodec.encode_answer("4:asi", ["ability-score-improvement", "str", "str"])),
			{"key": "4:asi", "answer": ["ability-score-improvement", "str", "str"]}, "ANSWER round-trips")
	t.eq(RulesCodec.decode_answer(PackedByteArray([9, 0, 1])), {}, "a bad ANSWER is refused")
	t.eq(RulesCodec.decode_id(RulesCodec.encode_id(12)), 12, "REVIVE round-trips")
	t.eq(RulesCodec.decode_id(PackedByteArray([1])), -1, "a short REVIVE is refused")
	t.eq(RulesCodec.decode_debug(RulesCodec.encode_debug(RulesCodec.Debug.HURT, -5)),
			{"op": RulesCodec.Debug.HURT, "n": -5}, "DEBUG round-trips")
	var long := "x".repeat(5000)
	t.eq(String(RulesCodec.decode_str(RulesCodec.encode_str(long))["text"]).length(), RulesCodec.STR_MAX, "long strings are cut")

## Integration mirrors: DEEDS, SUMMARY, PREFS (and their refusals of bad input).
func _mirrors(t: TestLog) -> void:
	var deeds := {"kill": 16, "kill:fey": 8, "dig:stone": 412, "run": 90000}
	t.eq(RulesCodec.decode_deeds(RulesCodec.encode_deeds(deeds)).get("deeds"), deeds, "DEEDS round trip")
	var d := RulesCodec.encode_deeds(deeds)
	t.eq(RulesCodec.decode_deeds(d.slice(0, d.size() - 1)), {}, "a truncated DEEDS is refused")
	var summ := {"ac": 18, "attacks": [{"name": "Longsword", "to_hit": 5, "damage": "1d8+3 slashing", "per_action": 1}],
		"skills": [{"name": "Athletics", "bonus": 5, "prof": true, "expert": false}], "resist": ["fire"]}
	var back := RulesCodec.decode_json(RulesCodec.encode_json(summ))
	t.eq([int(back["ac"]), String(back["attacks"][0]["damage"]), back["resist"]], [18, "1d8+3 slashing", ["fire"]], "SUMMARY round trip")
	var raw := RulesCodec.encode_json(summ)
	t.eq(RulesCodec.decode_json(raw.slice(0, raw.size() - 2)), {}, "a truncated SUMMARY is refused")
	t.eq(RulesCodec.decode_json(PackedByteArray([3, 0, 0, 0, 0x5b, 0x31, 0x5d])), {}, "a JSON array is not a summary")
	t.eq(RulesCodec.encode_json({"x": "y".repeat(RulesCodec.PREFS_MAX)}, RulesCodec.PREFS_MAX).size(), 0, "oversize prefs are not encoded")
	t.eq(Character.clean_prefs({"quick": ["a", 3, "c"], "evil": 1}), {"quick": ["a", "", "c", ""]}, "prefs are cleaned to known shapes")
