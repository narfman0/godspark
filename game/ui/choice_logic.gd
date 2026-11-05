## Pure helpers behind the level-up screens: picking options against a choice's count,
## validation before `answer` is sent (the host's own rules, RulesSystem.validate, plus the
## friendlier words here), option text from the SRD content, and the deed line of a Knack.
class_name ChoiceLogic
extends RefCounted

const ABILITIES := ["str", "dex", "con", "int", "wis", "cha"]

## Toggle `id` in `picked` for a choice of `count`: remove if there, add if room, else replace
## the most recent pick.
static func toggle(picked: Array, id: String, count: int) -> Array:
	var out := picked.duplicate()
	if id in out:
		out.erase(id)
	elif out.size() < count:
		out.append(id)
	elif not out.is_empty():
		out[-1] = id
	return out

## What details an ASI-kind feat needs after its id: {what: abilities|str_dex|skills, n}.
static func asi_details(feat: String) -> Dictionary:
	match feat:
		"ability-score-improvement":
			return {"what": "abilities", "n": 2, "min": 2}
		"grappler":
			return {"what": "str_dex", "n": 1, "min": 1}
		"skilled":
			return {"what": "skills", "n": 3, "min": 1}
	return {}

## The answer to send: for "asi" [feat, details...], else the picks.
static func answer_for(choice: Dictionary, picked: Array, details: Array = []) -> Array:
	if String(choice.get("kind", "")) == "asi":
		return ([picked[0]] if not picked.is_empty() else []) + details
	return picked.duplicate()

## "" if the answer can be sent, else why not (in plain words).
static func validate(choice: Dictionary, ans: Array) -> String:
	if ans.is_empty():
		return "Pick %s." % ("one" if int(choice.get("count", 1)) == 1 else str(int(choice.get("count", 1))))
	var kind := String(choice.get("kind", ""))
	if kind == "asi":
		var need := asi_details(String(ans[0]))
		var rest := ans.slice(1)
		if not need.is_empty() and rest.size() < int(need["min"]):
			match String(need["what"]):
				"abilities":
					return "Choose two abilities to raise (the same one twice for +2)."
				"str_dex":
					return "Choose Strength or Dexterity."
				"skills":
					return "Choose up to three skills."
	else:
		var n := int(choice.get("count", 1))
		var seen := {}
		for a: Variant in ans:
			if seen.has(a):
				return "%s is picked twice." % String(a)
			seen[a] = true
		if ans.size() != n:
			return "Pick %d (%d so far)." % [n, ans.size()]
	var why := RulesSystem.validate(choice, ans)
	return "" if why == "" else why.left(1).to_upper() + why.substr(1) + "."

## Rules text for an option of a choice ({id, name, level?}).
static func option_text(choice: Dictionary, opt: Dictionary) -> String:
	var id := String(opt.get("id", ""))
	var kind := String(choice.get("kind", ""))
	if kind == "knack":
		return String(Knacks.def(id).get("text", ""))
	var pack := ItemText.srd().pack
	for k: String in (["spell"] if kind == "spell" else ["feat", "class_option", "subclass", "spell", "feature"]):
		if pack.has_row(k, id):
			var row := pack.get_row(k, id)
			var d: Dictionary = row.get("data", {})
			var t := String(d.get("text", d.get("description", "")))
			if k == "spell":
				var lvl := int(d.get("level", 0))
				t = "%s. %s" % ["Cantrip" if lvl == 0 else "Level %d %s" % [lvl, String(d.get("school", ""))], t]
			return t.replace("\n", " ")
	return ""

## The best deed behind a Knack offer: {counter, n} from the deed counts (n 0: none counted).
static func knack_deed(knack_id: String, deeds: Dictionary) -> Dictionary:
	var w: Dictionary = Knacks.def(knack_id).get("deeds", {})
	var best := ""
	var best_score := -1.0
	for c: String in w:
		var score := float(w[c]) * (1.0 + float(deeds.get(c, 0)))
		if score > best_score:
			best_score = score
			best = c
	return {"counter": best, "n": int(deeds.get(best, 0))}

## "You dug 412 stone: Stonecutter's Tools", or the hint when nothing was counted.
static func knack_line(knack_id: String, deeds: Dictionary) -> String:
	var d := knack_deed(knack_id, deeds)
	var nm := String(Knacks.def(knack_id).get("name", knack_id))
	if String(d["counter"]) == "":
		return "Offered for the road so far: %s" % nm
	if int(d["n"]) > 0:
		return "%s: %s" % [UiCopy.deed(String(d["counter"]), int(d["n"])), nm]
	return "%s, %s" % [nm, UiCopy.deed_hint(String(d["counter"]))]
