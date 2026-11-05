## Combat timing from data/combat.json: how long a weapon's Attack action takes, where its
## contact frames fall (Extra Attack and Multiattack as combos), cast tempos, and spell
## durations from the table (a round is 2 s, a minute 20 s, ...). Pure functions.
##
##   var cls := CombatTempo.weapon_class(srd, c.weapon, two_handed, false)   # "light", "heavy"...
##   var tl := CombatTempo.timeline(CombatTempo.weapon_tempo(cls), 2)
##   # {windup: 0.15, contacts: [0.15, 0.37], total: 0.5}
##   CombatTempo.duration_s("Concentration, up to 1 minute")   # 20.0; -1 = instantaneous
class_name CombatTempo
extends RefCounted

const PATH := "res://data/combat.json"

static var _data := {}

static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _data

## A section of data/combat.json (a Dictionary), {} when missing.
static func section(key: String) -> Dictionary:
	var v: Variant = data().get(key, {})
	return v if v is Dictionary else {}

static func num(key: String, default := 0.0) -> float:
	return float(data().get(key, default))

## Tempo class of a weapon (see data/combat.json weapon_tempo). w null = Unarmed Strike.
## Monster natural weapons (no pack slug) are "monster". throw: a Thrown melee weapon thrown.
static func weapon_class(srd: SRDContent, w: WeaponData, two_handed := false, throw := false) -> String:
	if w == null:
		return "unarmed"
	if is_natural(srd, w):
		return "monster"
	var props := weapon_props(srd, w)
	if throw:
		return "thrown"
	if w.is_ranged():
		if "thrown" in props and not "ammunition" in props:
			return "thrown"
		if "loading" in props:
			return "loading"
		if "heavy" in props:
			return "heavy_bow"
		return "bow"
	if "heavy" in props or "two_handed" in props:
		return "heavy"
	if "versatile" in props and two_handed:
		return "versatile_two"
	if "light" in props:
		return "light"
	return "plain"

## A stat-block attack (no SRD weapon row behind it).
static func is_natural(srd: SRDContent, w: WeaponData) -> bool:
	return w != null and (w.slug == "" or srd == null or not srd.pack.has_row("weapon", w.slug))

## The pack's property words for a weapon ("light", "heavy", "reach"...): the addon's bitmask
## has no Heavy, so the row is read. [] for monster weapons.
static func weapon_props(srd: SRDContent, w: WeaponData) -> Array:
	if w == null or w.slug == "" or srd == null:
		return []
	var row := srd.pack.get_row("weapon", w.slug)
	return row.get("data", {}).get("properties", []) if not row.is_empty() else []

## {windup, recovery, sweep} for a tempo class (falls back to "plain").
static func weapon_tempo(cls: String) -> Dictionary:
	var t := section("weapon_tempo")
	var row: Variant = t.get(cls, t.get("plain"))
	return row

## Where the contact frames of an n-swing sequence fall. The first comes after the wind-up;
## the others follow `gap` apart, taken out of the recovery so the whole action keeps its
## time (so n swings cost what one does, and damage scales with n as in the SRD).
##   {windup, gap, contacts: [s...], total}
static func timeline(tempo: Dictionary, n := 1) -> Dictionary:
	var w := float(tempo.get("windup", 0.2))
	var r := float(tempo.get("recovery", 0.4))
	var combo := section("combo")
	var gap := 0.0
	if n > 1:
		gap = minf(float(combo.get("gap_max", 0.22)), maxf(0.0, r - float(combo.get("recovery_min", 0.08))) / (n - 1))
	var contacts: Array[float] = []
	for i in maxi(1, n):
		contacts.append(w + gap * i)
	return {"windup": w, "gap": gap, "contacts": contacts, "total": w + r}

## Cast tempo for an SRD casting time ("action", "bonus_action", "reaction"): {windup, recovery}.
static func cast_tempo(casting_time: String) -> Dictionary:
	var c := section("cast")
	var row: Variant = c.get(casting_time, c.get("action"))
	return row

## Real seconds for a spell duration text from the SRD ("Concentration, up to 1 minute",
## "1 round", "8 hours"). -1: instantaneous or not timed ("Until dispelled").
static func duration_s(text: String) -> float:
	var d := section("durations_s")
	var m := RegEx.create_from_string("(\\d+) (round|minute|hour|day)s?").search(text.to_lower())
	if m == null:
		return -1.0
	var n := int(m.get_string(1))
	var unit := m.get_string(2)
	var key := "%d %s%s" % [n, unit, "" if n == 1 else "s"]
	var rows: Dictionary = d.get("rows", {})
	if rows.has(key):
		return float(rows[key])
	var per: Dictionary = d.get("per_unit", {})
	return minf(n * float(per.get(unit, 2.0)), float(d.get("cap", 1200.0)))

## SRD reach of a weapon in feet: 10 with Reach, the stat block's reach for monster weapons.
static func reach_ft(srd: SRDContent, w: WeaponData) -> float:
	if w == null:
		return 5.0
	if is_natural(srd, w):
		return float(maxi(5, w.range_normal)) if not w.is_ranged() else 5.0
	return 10.0 if "reach" in weapon_props(srd, w) else 5.0

## [normal, long] range in feet for a ranged or thrown weapon; [0, 0] for melee-only.
static func range_ft(srd: SRDContent, w: WeaponData) -> Vector2:
	if w == null:
		return Vector2.ZERO
	if w.is_ranged():
		return Vector2(w.range_normal, w.range_long)
	if srd != null and w.slug != "":
		var r: Variant = srd.pack.get_row("weapon", w.slug).get("data", {}).get("range")
		if r is Array and (r as Array).size() == 2:
			return Vector2(float(r[0]), float(r[1]))
	return Vector2.ZERO

## Which projectile a ranged weapon looses: "arrow", "bolt", "thrown".
static func projectile_kind(srd: SRDContent, w: WeaponData, throw: bool) -> String:
	if throw or w == null:
		return "thrown"
	var props := weapon_props(srd, w)
	if "thrown" in props and not "ammunition" in props:
		return "thrown"
	if "loading" in props:
		return "bolt"
	return "arrow"
