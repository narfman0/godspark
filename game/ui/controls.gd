## The control scheme in one place: the help overlay (F1 or H) reads it, README "Controls"
## mirrors it (a test checks every key named here appears there). Change keys in project.godot
## [input] and here together.
class_name Controls
extends RefCounted

## [group, [[keys, what], ...]]
const GROUPS := [
	["Moving", [
		["A / D", "walk left and right"],
		["Space", "jump (hold for higher)"],
		["W / S", "climb ladders and ropes; W takes a staircase from its foot"],
		["S (hold)", "drop through a walkway, stairs or a ladder top"],
		["V", "dodge roll"],
		["Shift", "dash (with the Dash spark)"],
	]],
	["Fighting and working", [
		["Left mouse", "use what is selected: attack, place, drink, hang a rope"],
		["Right mouse", "dig (rubble you can place again)"],
		["F", "attack with your weapon, whatever is selected"],
		["Q R T G", "quick spells: hold to aim, let go to cast"],
		["1-9, 0", "hotbar slot (a rope from the hotbar is hung where you click)"],
	]],
	["The world", [
		["E", "talk to the person by you; rest, sleep, kindle, revive"],
		["1-9 / 0", "in a conversation: answer / say farewell"],
		["Esc", "close the top screen, or leave a conversation"],
		["Wheel, = and -", "zoom"],
	]],
	["Screens", [
		["Tab or I", "pack and paper doll"],
		["C / K / B / U", "character / constellation / spells / choices"],
		["M", "the world map"],
		["J", "work: the quest log"],
		["P", "standing and patrons"],
		["L", "the world's history"],
		["F1 or H", "this card"],
	]],
]

## Every key string named (for the README check).
static func keys() -> Array:
	var out: Array = []
	for g: Array in GROUPS:
		for row: Array in g[1]:
			out.append(String(row[0]))
	return out
