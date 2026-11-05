## The interface's words: short, readable first, a little wry. One place so the voice stays
## the same and is easy to change.
class_name UiCopy
extends RefCounted

## ItemsClient refusal words (docs/tracks/items.md) as sentences.
const ITEM_REFUSALS := {
	"full": "Your pack is full. Something has to go.",
	"bad_index": "That slot doesn't exist.",
	"empty": "Nothing there.",
	"no_move": "That won't budge.",
	"bad_slot": "That doesn't go there.",
	"not_wearable": "You can't wear that. You tried.",
	"stack": "One at a time on the body, please.",
	"two_handed": "Both hands are busy with the big one.",
	"off_hand_busy": "Your off hand is already holding something.",
	"not_light": "Two weapons only if both are light.",
	"occupied": "Something is already there.",
	"full_hp": "You're already in one piece.",
	"not_usable": "You turn it over. Nothing happens.",
	"no_body": "You need a body for that.",
	"no_bond_needed": "It works fine without a bond.",
	"bonded": "Already bonded to you.",
	"class": "It refuses you: wrong calling.",
	"no_campfire": "Bonding needs a campfire close by.",
	"interrupted": "The bond slipped. Stay by the fire.",
	"not_a_spark": "That's not a spark.",
	"no_shrine": "Kindling needs a shrine within a few steps.",
	"unknown": "Nobody knows what that is.",
	"duplicate": "You already carry that star.",
	"no_star": "There's no star there.",
	"missing": "You lack the makings.",
}

static func item_refusal(word: String) -> String:
	return ITEM_REFUSALS.get(word, word.capitalize())

## What a level of the 100-level track gives, short (for the XP bar marker).
static func reward_short(r: int) -> String:
	match r:
		LevelTrack.Reward.SPARK_SLOT:
			return "spark slot"
		LevelTrack.Reward.VIGOR:
			return "Vigor"
		LevelTrack.Reward.KNACK:
			return "Knack"
		LevelTrack.Reward.CLASS_LEVEL:
			return "class level"
		LevelTrack.Reward.EPIC_BOON:
			return "Epic Boon"
	return ""

## The level-up banner's second line.
static func reward_line(r: int, class_level := 0) -> String:
	match r:
		LevelTrack.Reward.SPARK_SLOT:
			return "A new star waits to be kindled in your constellation."
		LevelTrack.Reward.VIGOR:
			return "Vigor: more hit points, and one more Hit Point Die."
		LevelTrack.Reward.KNACK:
			return "A Knack: pick one of three. Your deeds chose them."
		LevelTrack.Reward.CLASS_LEVEL:
			return "Class level %d! New features and choices await." % class_level if class_level > 0 else "A class level! New features and choices await."
		LevelTrack.Reward.EPIC_BOON:
			return "Level 100. Past mortal. Choose an Epic Boon."
	return ""

static func clock(hours: float) -> String:
	var day := int(floor(hours / 24.0))
	var h := fposmod(hours, 24.0)
	return "Day %d  %02d:%02d" % [day + 1, int(h), int(fmod(h, 1.0) * 60.0)]

## Deed counters (core/rules/knacks.gd) as a past-tense phrase with a count.
static func deed(counter: String, n: int) -> String:
	var parts := counter.split(":")
	var head := parts[0]
	var what := parts[1].replace("_", " ").replace("-", " ") if parts.size() > 1 else ""
	match head:
		"dig":
			return "You dug %d %s" % [n, what if what != "" else "tiles"]
		"place":
			return "You placed %d %s" % [n, what if what != "" else "blocks"]
		"run":
			return "You ran %d tiles" % n
		"climb":
			return "You climbed %d tiles" % n
		"fall":
			return "You fell %d tiles, all told" % n
		"swim":
			return "You swam %d tiles" % n
		"underground":
			return "You spent %d minutes underground" % maxi(1, n / 60)
		"sleep":
			return "You slept %d nights" % n
		"rest":
			return "You rested by the fire %d times" % n
		"kill":
			return "You felled %d %s" % [n, what if what != "" else "foes"]
		"beast":
			return "You met %d %s" % [n, what]
		"trade":
			return "You traded %d times" % n
		"craft":
			return "You crafted %d things" % n
		"kindle":
			return "You kindled %d sparks" % n
		"revive":
			return "You hauled %d allies back up" % n
		"downed":
			return "You hit the dirt %d times" % n
	return "%s: %d" % [counter, n]

## A deed with no count yet: what earns it.
static func deed_hint(counter: String) -> String:
	var parts := counter.split(":")
	var what := parts[1].replace("_", " ").replace("-", " ") if parts.size() > 1 else ""
	match parts[0]:
		"dig":
			return "for digging " + (what if what != "" else "")
		"place":
			return "for building"
		"run":
			return "for all that running"
		"climb":
			return "for climbing"
		"fall":
			return "for falling, mostly on purpose"
		"swim":
			return "for swimming"
		"underground":
			return "for time spent below"
		"kill":
			return "for felling " + (what if what != "" else "foes")
		"beast":
			return "for time among " + what
		"trade":
			return "for trading"
		"sleep", "rest":
			return "for resting well"
		"revive":
			return "for picking friends up"
		"downed":
			return "for getting knocked down"
	return "for your deeds"
