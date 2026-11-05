## The character sheet's numbers, computed on the host from the live combatant (after gear,
## Knacks, answered choices and effects), for the owner's sheet (RulesCodec SUMMARY). The
## client shows these and never works them out itself.
##   SheetSummary.of(e.combatant, e.character, host.srd, profs) -> {abilities: [{key, name,
##     score, mod, save, save_prof}], pb, skills: [{name, bonus, prof, expert}], ac,
##     ac_parts: [[label, value]], attacks: [{name, to_hit, damage, per_action}], features,
##     resist: [String], profs: {tools, languages}, speed_ft, temp_hp}
class_name SheetSummary
extends RefCounted

const ABILITY_KEYS := ["str", "dex", "con", "int", "wis", "cha"]
const ABILITY_NAMES := ["Strength", "Dexterity", "Constitution", "Intelligence", "Wisdom", "Charisma"]

static func of(c: Combatant, ch: Character, srd: SRDContent, profs := {}) -> Dictionary:
	if c == null or ch == null:
		return {}
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
	out["ac_parts"] = ac_parts(ch.equipment, c, srd)
	var atk: Array = []
	var w := c.weapon
	if w != null:
		var dm := (w.attack_bonus(c.stats, false) if w.fixed_damage_bonus == WeaponData.NO_FIXED else w.fixed_damage_bonus) + c.bonus_damage
		atk.append({"name": w.weapon_name, "to_hit": c.attack_modifier(),
			"damage": "%dd%d%s %s" % [w.die_count, w.die_sides, "%+d" % dm if dm != 0 else "", String(SRD.DamageType.find_key(w.damage_type)).to_lower()],
			"per_action": c.kit.attacks_per_action() if c.kit != null else 1})
	else:
		atk.append({"name": "Unarmed Strike", "to_hit": c.attack_modifier(),
			"damage": "%d bludgeoning" % maxi(1, 1 + c.stats.ability_modifier(SRD.Ability.STRENGTH)), "per_action": 1})
	out["attacks"] = atk
	out["features"] = c.kit.feature_names() if c.kit != null else []
	var res: Array = []
	for dt_name: String in SRD.DamageType.keys():
		var dt: int = SRD.DamageType[dt_name]
		if c.stats.has_immunity(dt as SRD.DamageType):
			res.append("immune to " + dt_name.to_lower())
		elif c.stats.has_resistance(dt as SRD.DamageType):
			res.append(dt_name.to_lower())
	out["resist"] = res
	out["profs"] = {"tools": profs.get("tools", []), "languages": profs.get("languages", [])}
	out["speed_ft"] = c.speed
	out["temp_hp"] = c.stats.temp_hp
	return out

## What makes up AC: [[label, value]] (value 0 with "(unbonded: asleep)" for a sleeping item).
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
	var known := 0
	for p: Array in parts:
		known += int(p[1])
	if known != c.armor_class:
		parts.append(["Features and effects", c.armor_class - known])     # Defense, Shield, Mage Armor ...
	return parts
