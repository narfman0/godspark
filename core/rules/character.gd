## One player's character: identity, the 100-level track, the SRD build, and the state rests
## restore. Owned by the host, saved in the player record (to_dict), mirrored to its owner by
## the rules system. Pure data plus the bridge to the addon (make_combatant).
##
##   var ch := Character.create("ann", "wizard", [], [], "", "", srd)   # level 1, choices answered
##   var r := ch.gain_level()                       # LevelTrack.Reward
##   var c := ch.make_combatant(srd)                # addon Combatant at class_level()
##
## Contract: docs/architecture.md, "M2 contracts / Character".
class_name Character
extends RefCounted

## SRD hit die by class (checked against the addon's classes in tests): lets the record
## compute its own max hit points without building a ClassData.
const HIT_DIE := {"barbarian": 12, "fighter": 10, "paladin": 10, "ranger": 10, "bard": 8,
	"cleric": 8, "druid": 8, "monk": 8, "rogue": 8, "warlock": 8, "sorcerer": 6, "wizard": 6}

## Default builds for the first four classes. scores: STR..CHA (the standard array);
## prefs: SRDProgression.auto_answer preference lists. gear: until the items track supplies it.
const DEFAULTS := {
	"fighter": {"scores": [15, 13, 14, 8, 12, 10], "skills": ["athletics", "perception"],
		"background": "soldier", "prefs": {"asi": ["str", "con", "dex"]},
		"gear": {"weapon": "longsword", "armor": "chain-mail", "shield": true}},
	"rogue": {"scores": [8, 15, 14, 13, 12, 10], "skills": ["stealth", "sleight-of-hand", "acrobatics", "perception"],
		"background": "criminal", "prefs": {"asi": ["dex", "con", "wis"], "expertise": ["stealth", "perception"]},
		"gear": {"weapon": "rapier", "armor": "leather-armor", "shield": false}},
	"wizard": {"scores": [8, 13, 14, 15, 12, 10], "skills": ["arcana", "history"],
		"background": "sage", "prefs": {"asi": ["int", "con", "dex"],
			"cantrips": ["fire-bolt", "ray-of-frost", "shocking-grasp"],
			"spells": ["magic-missile", "shield", "burning-hands", "scorching-ray", "misty-step", "fireball",
				"lightning-bolt", "ice-storm", "cone-of-cold", "chain-lightning"]},
		"gear": {"weapon": "quarterstaff", "armor": "", "shield": false}},
	"cleric": {"scores": [13, 10, 14, 8, 15, 12], "skills": ["insight", "medicine"],
		"background": "acolyte", "prefs": {"asi": ["wis", "con", "str"],
			"cantrips": ["sacred-flame", "guidance", "toll-the-dead"],
			"spells": ["cure-wounds", "guiding-bolt", "bless", "healing-word", "spiritual-weapon",
				"spirit-guardians", "mass-healing-word", "guardian-of-faith", "flame-strike"]},
		"gear": {"weapon": "mace", "armor": "chain-mail", "shield": true}},
}
const FALLBACK_GEAR := {"weapon": "dagger", "armor": "", "shield": false}
const DEFAULT_SCORES := [10, 10, 10, 10, 10, 10]
const DEFAULT_SPECIES := "human"

var name := ""
var class_slug := "fighter"
## "" until chosen; the addon picks the first SRD subclass at class level 3 meanwhile.
var subclass := ""
var species := DEFAULT_SPECIES
var background := ""
## 1..LevelTrack.MAX_LEVEL
var level := 1
var xp := 0
## The addon's SRDProgression build: {class, scores: [STR..CHA], skills, spells?, choices:
## {"<class level>": {<choice id>: [answer...]}}, prefs?}.
var build := {}
## Knack ids taken, and deed counters (tiles dug, kills by type...): the rules track.
var knacks: Array = []
var deeds := {}
## The items track's state, saved here (and only here): kindled sparks, carried items and
## coin, and what is worn. See docs/tracks/items.md.
var sparks := Constellation.new()
var inventory := Inventory.new()
var equipment := Equipment.new()
## State rests restore. hp: current hit points (max comes from the level, max_hp()).
## slots_left: spell slots left per level [l1..l9] ([] = all); uses_left: {resource: n}
## ({} = all). The rules track owns the last two.
var hp := 0
var hit_dice_left := 1
var slots_left: Array = []
var uses_left := {}
## Where death and long rests return you: a Vector2i, or null for none.
var bed: Variant = null
## The bed is a paid room (an inn, Deals): the respawn point holds while the cell is open,
## with no bed tile there.
var bed_inn := false
## Interface preferences kept with the character (clean_prefs): {quick: [4 spell slugs]}.
var prefs := {}

## A new level-1 character. Empty scores, skills, species or background take the class
## default (DEFAULTS; other SRD classes get flat 10s and no skills). With `srd`, the class
## level 1 choices (cantrips, spells, masteries...) are answered now (auto_choices).
static func create(char_name: String, class_slug_in: String, scores: Array = [], skills: Array = [],
		species_in := "", background_in := "", srd: SRDContent = null) -> Character:
	var ch := Character.new()
	var d: Dictionary = DEFAULTS.get(class_slug_in, {})
	ch.name = char_name
	ch.sparks.salt = char_name
	ch.class_slug = class_slug_in
	ch.species = species_in if species_in != "" else DEFAULT_SPECIES
	ch.background = background_in if background_in != "" else String(d.get("background", ""))
	ch.build = {
		"class": class_slug_in,
		"scores": (scores if not scores.is_empty() else d.get("scores", DEFAULT_SCORES)).duplicate(),
		"skills": (skills if not skills.is_empty() else d.get("skills", [])).duplicate(),
		"choices": {},
	}
	ch.level = 1
	if srd != null:
		ch.auto_choices(srd)
	ch.hp = ch.max_hp()
	ch.hit_dice_left = ch.hit_dice_max()
	return ch

## The class level the SRD sees (LevelTrack.class_level).
func class_level() -> int:
	return LevelTrack.class_level(level)

func hit_die() -> int:
	return int(HIT_DIE.get(class_slug, 8))

## The build resolved at the current class level: {scores, options, spells, feats}.
func resolved() -> Dictionary:
	return SRDProgression.resolve(null, build, class_level())

func con_mod() -> int:
	var s: Array = resolved()["scores"]
	return floori((int(s[2]) - 10) / 2.0)

func max_hp() -> int:
	return LevelTrack.max_hp(level, hit_die(), con_mod())

func hit_dice_max() -> int:
	return LevelTrack.hit_dice(level)

func spark_slots() -> int:
	return LevelTrack.spark_slots(level)

## Answer every unanswered SRD choice for class levels 1..class_level() with
## SRDProgression.auto_answer and the class's preference lists. Returns how many it answered.
func auto_choices(srd: SRDContent) -> int:
	var n := 0
	var old_max := max_hp()
	var prefs: Dictionary = build.get("prefs", DEFAULTS.get(class_slug, {}).get("prefs", {}))
	var choices: Dictionary = build.get("choices", {})
	build["choices"] = choices
	for cl in range(1, class_level() + 1):
		var key := str(cl)
		var answers: Dictionary = choices.get(key, {})
		choices[key] = answers    # answers land in the build at once, for later levels' choices()
		var scores: Array = SRDProgression.resolve(srd, build, cl - 1)["scores"]
		for ch: Dictionary in SRDProgression.choices(srd, build, cl):
			if not answers.has(ch["id"]):
				answers[ch["id"]] = SRDProgression.auto_answer(ch, prefs, scores)
				n += 1
		if answers.is_empty():
			choices.erase(key)
	_max_changed(old_max)
	return n

## Record the answer to one SRD choice (choice id from pending_choices) at a class level.
## Current hit points follow a changed maximum (an ASI to Constitution).
func answer_choice(class_lvl: int, choice_id: String, answer: Array) -> void:
	var old_max := max_hp()
	var choices: Dictionary = build.get("choices", {})
	build["choices"] = choices
	var answers: Dictionary = choices.get(str(class_lvl), {})
	answers[choice_id] = answer.duplicate()
	choices[str(class_lvl)] = answers
	_max_changed(old_max)

func _max_changed(old_max: int) -> void:
	hp = maxi(0, hp + max_hp() - old_max)      # the max with gear (rebuilt next) bounds it

## Choices the SRD asks for at class levels 1..class_level() that the build has not answered:
## [{class_level, choice}] (choice as SRDProgression.choices gives it).
func pending_choices(srd: SRDContent) -> Array:
	var out := []
	var choices: Dictionary = build.get("choices", {})
	for cl in range(1, class_level() + 1):
		var answers: Dictionary = choices.get(str(cl), {})
		for ch: Dictionary in SRDProgression.choices(srd, build, cl):
			if not answers.has(ch["id"]):
				out.append({"class_level": cl, "choice": ch})
	return out

## One level up (to at most LevelTrack.MAX_LEVEL). Applies what needs no choice: hit points
## grow with the max (current hit points rise by the same amount) and new Hit Point Dice are
## added. Spark slots follow the level (spark_slots()). Knacks and the SRD's class-level
## choices are left to the rules track (pending_choices). Returns the level's reward.
func gain_level() -> LevelTrack.Reward:
	if level >= LevelTrack.MAX_LEVEL:
		return LevelTrack.reward(level)
	var old_max := max_hp()
	var old_dice := hit_dice_max()
	level += 1
	hp = maxi(0, hp + max_hp() - old_max)      # the max with gear (rebuilt next) bounds it
	hit_dice_left = clampi(hit_dice_left + hit_dice_max() - old_dice, 0, hit_dice_max())
	return LevelTrack.reward(level)

## The addon Combatant at class_level(): the build's resolved scores and options, the class's
## default weapon and armour (until the items track supplies gear), max hit points from the
## level track and current hit points from this record. No spark touches it.
func make_combatant(srd: SRDContent) -> Combatant:
	var cl := class_level()
	var r := SRDProgression.resolve(srd, build, cl)
	var gear: Dictionary = DEFAULTS.get(class_slug, {}).get("gear", FALLBACK_GEAR)
	var c := srd.make_character(name, class_slug, cl, r["scores"], String(gear["weapon"]),
			String(gear["armor"]), bool(gear["shield"]), build.get("skills", []), subclass, r["options"])
	if c == null:
		return null
	c.stats.max_hp = LevelTrack.max_hp(level, c.stats.hit_die, c.stats.ability_modifier(SRD.Ability.CONSTITUTION))
	# Not capped at the gear-less max: gear that raises Constitution is put on next (Rules'
	# refresh or Equipment.dress), and that caps it at the max with gear.
	c.stats.current_hp = maxi(0, hp)
	c.stats.hit_dice_remaining = clampi(hit_dice_left, 0, hit_dice_max())
	return c

## Copy what play changes on the combatant back into the record (before saving): hit points
## (bounded by the combatant's max, which gear CON may raise above max_hp()), Hit Point Dice,
## spell slots and limited uses left.
func capture(c: Combatant) -> void:
	if c == null:
		return
	hp = maxi(0, c.stats.current_hp)
	hit_dice_left = clampi(c.stats.hit_dice_remaining, 0, hit_dice_max())
	if c.energy_slots != null:
		slots_left = []
		for i in 9:
			slots_left.append(c.energy_slots.slots_remaining[i])
	if c.kit != null:
		uses_left = {}
		for k: String in c.kit.resources:
			uses_left[k] = int(c.kit.resources[k]["current"])

## Movement from the combatant's speed, Medium size. Sparks and gear change it later.
func move_stats(c: Combatant = null) -> MoveStats:
	return MoveStats.from_srd({"walk": c.speed if c != null else 30}, "medium")

# --- saving -----------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"format": 1, "name": name, "class": class_slug, "subclass": subclass, "species": species,
		"background": background, "level": level, "xp": xp, "build": build.duplicate(true),
		"knacks": knacks.duplicate(), "deeds": deeds.duplicate(true), "sparks": sparks.to_dict(),
		"inventory": inventory.to_dict(), "equipment": equipment.to_dict(),
		"hp": hp, "hit_dice_left": hit_dice_left, "slots_left": slots_left.duplicate(),
		"uses_left": uses_left.duplicate(true), "bed": [bed.x, bed.y] if bed is Vector2i else null,
		"prefs": prefs.duplicate(true),
	}.merged({"bed_inn": true} if bed_inn and bed is Vector2i else {})

## Inverse of to_dict, also after a trip through JSON (numbers come back as floats: the
## known integer fields are made ints again). Null if `d` is not a character.
static func from_dict(d: Dictionary) -> Character:
	if not d.has("class") or not d.has("level"):
		return null
	var ch := Character.new()
	ch.name = String(d.get("name", ""))
	ch.class_slug = String(d["class"])
	ch.subclass = String(d.get("subclass", ""))
	ch.species = String(d.get("species", DEFAULT_SPECIES))
	ch.background = String(d.get("background", ""))
	ch.level = LevelTrack.clamp_level(int(d["level"]))
	ch.xp = int(d.get("xp", 0))
	ch.build = _ints(d.get("build", {}))
	ch.knacks = Array(d.get("knacks", [])).duplicate()
	ch.deeds = _ints(d.get("deeds", {}))
	ch.sparks = Constellation.from_dict(d.get("sparks", {}))
	ch.sparks.salt = ch.name
	ch.inventory = Inventory.from_dict(d.get("inventory", {}))
	ch.equipment = Equipment.from_dict(d.get("equipment", {}))
	ch.hp = int(d.get("hp", 0))
	ch.hit_dice_left = int(d.get("hit_dice_left", 0))
	ch.slots_left = _ints(d.get("slots_left", []))
	ch.uses_left = _ints(d.get("uses_left", {}))
	var b: Variant = d.get("bed")
	ch.bed = Vector2i(int(b[0]), int(b[1])) if b is Array and (b as Array).size() == 2 else null
	ch.bed_inn = bool(d.get("bed_inn", false)) and ch.bed is Vector2i
	ch.prefs = clean_prefs(d.get("prefs", {}))
	return ch

## Only known preference keys and shapes survive: quick = 4 short strings.
static func clean_prefs(d: Variant) -> Dictionary:
	var out := {}
	if d is Dictionary and (d as Dictionary).get("quick") is Array:
		var q: Array = []
		for s: Variant in (d["quick"] as Array).slice(0, 4):
			q.append(String(s).left(64) if s is String else "")
		while q.size() < 4:
			q.append("")
		out["quick"] = q
	return out

## Whole-number floats (from JSON) back to ints, recursively. Build data has no real floats.
static func _ints(v: Variant) -> Variant:
	if v is float and is_finite(v) and float(int(v)) == v:
		return int(v)
	if v is Array:
		var a: Array = []
		for x: Variant in v:
			a.append(_ints(x))
		return a
	if v is Dictionary:
		var o := {}
		for k: Variant in v:
			o[k] = _ints(v[k])
		return o
	return v
