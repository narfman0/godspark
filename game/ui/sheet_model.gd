## The character sheet's numbers, worked out on the client from what it mirrors: the sheet
## (class, levels, scores after gear, knacks), the worn equipment and the sparked MoveStats.
## The host does not send the build's answered choices, so a stand-in Character is made with
## the class defaults and answered by the same auto rules, then dressed in the mirrored gear,
## and its ability scores set to the host's. Saves, skills, AC, attacks and features are read
## off that combatant. Display only: the host's dice decide everything.
class_name SheetModel
extends RefCounted

const ABILITY_KEYS := ["str", "dex", "con", "int", "wis", "cha"]
const ABILITY_NAMES := ["Strength", "Dexterity", "Constitution", "Intelligence", "Wisdom", "Charisma"]

static var _cache_key := ""
static var _cache := {}

## sheet: RulesClient.sheet; eq: Equipment; knacks: [id]; stats: the own MoveStats.
static func build(name: String, sheet: Dictionary, eq: Equipment, stats: MoveStats, srd: SRDContent) -> Dictionary:
	if sheet.is_empty():
		return {}
	var key := "%s|%s|%s|%s" % [name, var_to_str(sheet), var_to_str(eq.worn), var_to_str([stats.run_speed, stats.jump_velocity, stats.air_jumps, stats.dash_speed])] if stats != null else name
	if key == _cache_key:
		return _cache
	var cls := String(sheet.get("class", "fighter"))
	var ch := Character.create(name, cls, [], [], String(sheet.get("species", "")), String(sheet.get("background", "")), srd)
	ch.level = int(sheet.get("level", 1))
	if String(sheet.get("subclass", "")) != "":
		ch.subclass = String(sheet["subclass"])
	ch.auto_choices(srd)
	var c := ch.make_combatant(srd)
	eq.dress(c, ch, srd)
	var scores: Array = sheet.get("scores", [])
	for i in mini(6, scores.size()):
		c.stats.set_ability(i as SRD.Ability, int(scores[i]))
	for k: String in sheet.get("knacks", []):
		var d := Knacks.def(k)
		if String(d.get("kind", "")) == "skill":
			var sk := SRDContent.skill_from(String(d.get("key", "")))
			if sk >= 0:
				c.stats.set_skill_proficiency(sk as SRD.Skill, true)
	var out := {}
	var ab: Array = []
	for i in 6:
		ab.append({"key": ABILITY_KEYS[i], "name": ABILITY_NAMES[i], "score": c.stats.get_ability(i as SRD.Ability),
			"mod": c.stats.ability_modifier(i as SRD.Ability), "save": c.stats.saving_throw_bonus(i as SRD.Ability),
			"save_prof": c.stats.is_save_proficient(i as SRD.Ability)})
	out["abilities"] = ab
	out["pb"] = c.stats.proficiency_bonus()
	var skills: Array = []
	for sk_name: String in SRD.Skill.keys():
		var sk: int = SRD.Skill[sk_name]
		skills.append({"name": sk_name.capitalize(), "bonus": SRDSkills.skill_bonus(c.stats, sk as SRD.Skill),
			"prof": c.stats.is_skill_proficient(sk as SRD.Skill), "expert": c.stats.has_skill_expertise(sk as SRD.Skill)})
	out["skills"] = skills
	out["ac"] = c.armor_class
	out["ac_parts"] = ac_parts(eq, c, srd)
	var atk: Array = []
	var w := c.weapon
	if w != null:
		var dm := (w.attack_bonus(c.stats, false) if w.fixed_damage_bonus == WeaponData.NO_FIXED else w.fixed_damage_bonus) + c.bonus_damage
		atk.append({"name": w.weapon_name, "to_hit": c.attack_modifier(),
			"damage": "%dd%d%s %s" % [w.die_count, w.die_sides, "%+d" % dm if dm != 0 else "", String(SRD.DamageType.find_key(w.damage_type)).to_lower()],
			"per_action": c.kit.attacks_per_action() if c.kit != null else 1})
	else:
		atk.append({"name": "Unarmed Strike", "to_hit": c.attack_modifier(), "damage": "%d bludgeoning" % maxi(1, 1 + c.stats.ability_modifier(SRD.Ability.STRENGTH)), "per_action": 1})
	out["attacks"] = atk
	var feats: Array = []
	if c.kit != null:
		feats = c.kit.feature_names()
	out["features"] = feats
	var res: Array = []
	for dt_name: String in SRD.DamageType.keys():
		var dt: int = SRD.DamageType[dt_name]
		if c.stats.has_immunity(dt as SRD.DamageType):
			res.append("immune to " + dt_name.to_lower())
		elif c.stats.has_resistance(dt as SRD.DamageType):
			res.append(dt_name.to_lower())
	out["resist"] = res
	out["speed_ft"] = c.speed
	out["move"] = move_lines(stats)
	_cache_key = key
	_cache = out
	return out

## What makes up AC: [[label, value]] (value "" for a note).
static func ac_parts(eq: Equipment, c: Combatant, srd: SRDContent) -> Array:
	var parts: Array = []
	var armor := eq.at("armor")
	var dex := c.stats.ability_modifier(SRD.Ability.DEXTERITY)
	if not armor.is_empty() and srd.pack.has_row("armor", String(armor["base"])):
		var a := srd.make_armor(String(armor["base"]))
		parts.append([ItemGen.name(armor), a.base_ac])
		var d := dex if a.max_dex_bonus < 0 else mini(dex, a.max_dex_bonus)
		if d != 0:
			parts.append(["Dexterity", d])
	else:
		parts.append(["Unarmoured", 10])
		if dex != 0:
			parts.append(["Dexterity", dex])
	var shield := eq.at("off_hand")
	if not shield.is_empty() and Items.is_shield(shield):
		parts.append([ItemGen.name(shield), 2])
	for s: String in Equipment.SLOTS:
		var it := eq.at(s)
		if it.is_empty():
			continue
		var b := 0
		for m: Dictionary in Items.mods(it, true):
			b += int(m.get("ac", 0))
		if b != 0:
			parts.append([ItemGen.name(it), b])
		elif Items.needs_bond(it) and not bool(it.get("bonded", false)) and Items.budget_of(it).y != 0:
			parts.append([ItemGen.name(it) + " (unbonded: asleep)", 0])
	return parts

## Movement as changed by sparks, in plain numbers.
static func move_lines(s: MoveStats) -> Array:
	if s == null:
		return []
	var out: Array = ["Run %.1f tiles/s" % s.run_speed, "Jump %.1f tiles/s up" % s.jump_velocity]
	if s.air_jumps > 0:
		out.append("%d air jump%s" % [s.air_jumps, "" if s.air_jumps == 1 else "s"])
	if s.dash_speed > 0.0:
		out.append("Dash %.0f tiles/s, every %.1f s" % [s.dash_speed, s.dash_cooldown])
	if s.glide_fall > 0.0:
		out.append("Glide at %.0f tiles/s" % s.glide_fall)
	if s.climb_speed > 0.0:
		out.append("Climb walls %.0f tiles/s" % s.climb_speed)
	out.append("Swim %.1f tiles/s" % s.swim_speed)
	return out
