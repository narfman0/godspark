## A stat block's actions as things the combat machine can swing: every attack action as its
## own WeaponData (the addon only builds the first), save actions (breath weapons...) through
## MonsterSpells, and Multiattack parsed into a list of attack actions.
##
##   var m := MonsterMoves.of(srd, "brown-bear")
##   # {actions: [{name, kind: "melee"|"ranged"|"save", weapon?, riders?, save?, reach_ft, range_ft}],
##   #  multi: [action index...] (empty: none), default: index, unsupported: [names]}
class_name MonsterMoves
extends RefCounted

static var _cache := {}
const _NUM := {"one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6}
## Actions that are not attacks and that the machine does not need (or reports elsewhere).
const _SKIP := ["Multiattack", "Spellcasting"]

static func of(srd: SRDContent, slug: String) -> Dictionary:
	if _cache.has(slug):
		return _cache[slug]
	var row := srd.pack.get_row("monster", slug)
	var out := parse(row.get("data", {}).get("actions", []))
	_cache[slug] = out
	return out

static func parse(actions: Array) -> Dictionary:
	var out := {"actions": [], "multi": [], "default": -1, "unsupported": []}
	var saves := MonsterSpells.parse_save_actions(actions)
	var multi_text := ""
	for a: Dictionary in actions:
		var name := String(a.get("name", ""))
		if name == "Multiattack":
			multi_text = String(a.get("text", ""))
			continue
		if name in _SKIP:
			continue
		var atk: Variant = a.get("attack")
		if atk is Dictionary and not (atk as Dictionary).get("damage", []).is_empty():
			out["actions"].append(_attack(a))
			continue
		var sv := {}
		for f: Dictionary in saves:
			if f["key"] == name:
				sv = f
		if not sv.is_empty():
			out["actions"].append({"name": String(sv["name"]), "kind": "save", "save": sv,
				"reach_ft": float(sv.get("area_size", 0)) if int(sv.get("area_size", 0)) > 0 else float(sv.get("range", 5)),
				"range_ft": float(sv.get("range", 5))})
			continue
		out["unsupported"].append(name)
	var acts: Array = out["actions"]
	for i in acts.size():
		if acts[i]["kind"] == "melee":
			out["default"] = i
			break
	if out["default"] < 0:
		for i in acts.size():
			if acts[i]["kind"] == "ranged":
				out["default"] = i
				break
	if multi_text != "":
		out["multi"] = _multi(multi_text, acts, int(out["default"]))
	return out

static func _attack(a: Dictionary) -> Dictionary:
	var atk: Dictionary = a["attack"]
	var w := WeaponData.new()
	w.weapon_name = String(a["name"])
	var dice := SRDContent.parse_dice(String(atk["damage"][0]["dice"]))
	w.die_count = dice.count
	w.die_sides = dice.sides
	w.damage_type = SRDContent.damage_type_from(String(atk["damage"][0]["type"]))
	w.fixed_attack_bonus = int(atk.get("bonus", 0))
	w.fixed_damage_bonus = dice.bonus
	var ranged := String(atk.get("kind", "melee")) == "ranged" and atk.has("range")
	if ranged:
		w.range_normal = int(atk["range"][0])
		w.range_long = int(atk["range"][1])
	else:
		w.range_normal = int(atk.get("reach", 5))
		w.range_long = w.range_normal
	var riders := []
	var r := MonsterActions.parse_hit_rider(a)
	if not r.is_empty():
		riders.append(r)
	for part: Dictionary in (atk["damage"] as Array).slice(1):
		if r.is_empty() or String(part.get("dice", "")) != String(r.get("dice", "")):
			var rd := {"name": String(a["name"]), "dice": String(part["dice"]), "type": String(part["type"])}
			if "had advantage" in String(a.get("text", "")).to_lower():
				rd["condition"] = "advantage"     # "plus 2 (1d4) Slashing damage if the attack roll had Advantage"
			riders.append(rd)
	return {"name": String(a["name"]), "kind": "ranged" if ranged else "melee", "weapon": w, "riders": riders,
		"reach_ft": float(w.range_normal) if not ranged else 5.0,
		"range_ft": float(w.range_normal) if ranged else 0.0, "range_long_ft": float(w.range_long) if ranged else 0.0}

## "makes one Bite attack and one Claw attack" -> [bite, claw]; "two Rend attacks";
## "two attacks, using Scimitar or Shortbow" -> two of the default. Only the first
## alternative ("... or ...") is read.
static func _multi(text: String, acts: Array, default_i: int) -> Array:
	var low := text.to_lower().replace("’", "'")
	var first := low.get_slice(" or ", 0) if " or " in low and low.find(" or ") < low.find(".") else low
	var re := RegEx.create_from_string("\\b(one|two|three|four|five|six)\\s+(?:([a-z][a-z' -]*?)\\s+)?attacks?\\b")
	var out := []
	for m in re.search_all(first):
		var n: int = _NUM[m.get_string(1)]
		var nm := m.get_string(2).strip_edges()
		var idx := -1
		for i in acts.size():
			var an := String(acts[i]["name"]).to_lower()
			if nm != "" and (an == nm or nm.ends_with(an) or an.begins_with(nm)):
				idx = i
				break
		if idx < 0 and acts.size() > 0 and default_i >= 0:
			idx = default_i
		if idx >= 0 and acts[idx]["kind"] != "save":
			for k in n:
				out.append(idx)
	return out
