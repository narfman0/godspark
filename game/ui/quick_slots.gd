## The four quick-spell slots (Q R T G): which prepared spell each holds, and why one cannot
## be cast right now. Assignments are kept per character name in user://ui.cfg. Unassigned
## slots fall back to the combat client's default (the i-th castable spell).
class_name QuickSlots
extends RefCounted

const N := 4
const KEYS := ["Q", "R", "T", "G"]
const CFG := "user://ui.cfg"

var slugs: Array = ["", "", "", ""]
var owner_name := ""

## The spell row ({slug, name, level, flags}) slot i holds, from the mirrored spell list.
func spell_for(i: int, spells: Array) -> Dictionary:
	if i < 0 or i >= N:
		return {}
	var want := String(slugs[i])
	if want != "":
		for s: Dictionary in spells:
			if String(s["slug"]) == want:
				return s
		return {}
	# default: the i-th supported spell not assigned elsewhere
	var ok := spells.filter(func(s: Dictionary) -> bool:
		return int(s["flags"]) & CombatCodec.SPELL_SUPPORTED != 0 and not String(s["slug"]) in slugs)
	var k := 0
	for j in i:
		if String(slugs[j]) == "":
			k += 1
	return ok[k] if k < ok.size() else {}

func assign(i: int, slug: String) -> void:
	if i < 0 or i >= N:
		return
	for j in N:
		if String(slugs[j]) == slug:
			slugs[j] = ""
	slugs[i] = slug
	save()

## Why the spell cannot be cast now ("" if it can), from STATUS and the spell's flags.
static func why_not(spell: Dictionary, status: Dictionary, busy := 0.0) -> String:
	if spell.is_empty():
		return "empty"
	var f := int(spell.get("flags", 0))
	if f & CombatCodec.SPELL_SUPPORTED == 0:
		return "not in play yet"
	var flags := int(status.get("flags", 0))
	if flags & CombatCodec.ST_DOWNED:
		return "you are down"
	if flags & CombatCodec.ST_NO_ACTIONS:
		return "you can't act"
	var lvl := int(spell.get("level", 0))
	if lvl > 0:
		var slots: Array = status.get("slots", [])
		var any := false
		for l in range(lvl - 1, mini(9, slots.size())):
			if int(slots[l][0]) > 0:
				any = true
				break
		if not any:
			return "no slot left"
	if f & CombatCodec.SPELL_REACTION:
		if float(status.get("reaction", 0.0)) > 0.0:
			return "reaction spent"
		return ""
	if f & CombatCodec.SPELL_BONUS and float(status.get("bonus", 0.0)) > 0.0:
		return "bonus action spent"
	if float(status.get("action", 0.0)) > 0.0 or busy > 0.0:
		return "busy"
	return ""

## The timer (seconds left) a spell waits on, for the cooldown sweep.
static func timer_for(spell: Dictionary, status: Dictionary) -> float:
	var f := int(spell.get("flags", 0))
	if f & CombatCodec.SPELL_REACTION:
		return float(status.get("reaction", 0.0))
	if f & CombatCodec.SPELL_BONUS:
		return float(status.get("bonus", 0.0))
	return float(status.get("action", 0.0))

func load_for(name: String) -> void:
	owner_name = name
	var cfg := ConfigFile.new()
	if cfg.load(CFG) == OK:
		var a: Variant = cfg.get_value("quick", name, [])
		if a is Array and (a as Array).size() == N:
			slugs = (a as Array).map(func(x: Variant) -> String: return String(x))

func save() -> void:
	if owner_name == "":
		return
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	cfg.set_value("quick", owner_name, slugs)
	cfg.save(CFG)
