## Invented names from the syllable tables in data/sim/names.json.
class_name SimNames
extends RefCounted

static func make(rng: RandomNumberGenerator, set_name: String, taken: Dictionary) -> String:
	SimData.ensure()
	var t: Dictionary = SimData.names.get(set_name, SimData.names["place"])
	for attempt in 12:
		var s: String = t.start[rng.randi_range(0, t.start.size() - 1)]
		if rng.randf() < float(t.get("mid_chance", 0.0)):
			s += t.mid[rng.randi_range(0, t.mid.size() - 1)]
		var e: String = t.end[rng.randi_range(0, t.end.size() - 1)]
		if s.length() > 0 and e.length() > 0 and s[s.length() - 1] == e[0]:
			e = e.substr(1)
		var n := s + e
		n = n.substr(0, 1).to_upper() + n.substr(1).to_lower()
		if not taken.has(n):
			taken[n] = true
			return n
	var fallback := "%s %d" % [set_name.capitalize(), taken.size()]
	taken[fallback] = true
	return fallback

static var _deep := {}

## The underground style of a people's settlements (data/setting/names.json "deep"): {kind,
## forms}; "_" for a people with none.
static func deep_style(culture: String) -> Dictionary:
	if _deep.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/setting/names.json"))
		_deep = (d as Dictionary).get("deep", {}) if d is Dictionary else {}
		if not _deep.has("_"):
			_deep["_"] = {"kind": "settlement", "forms": ["{n}"]}
	return _deep.get(culture, _deep["_"])

## What a map or a guard calls a settlement below: "the city of Zaerrith", "Kolzul Deephold".
## A surface settlement, or a people with no deep style, is just its name. Picked by a hash of
## the name, so it never moves a generator.
static func title(culture: String, name: String, band := "deeps") -> String:
	if band == "surface" or band == "sky":
		return name
	var st := deep_style(culture)
	var forms: Array = st.get("forms", ["{n}"])
	if forms.is_empty():
		return name
	return String(forms[absi(hash(name)) % forms.size()]).replace("{n}", name)

## What a people calls one of its settlements below ("city", "hold", "warren").
static func kind_word(culture: String) -> String:
	return String(deep_style(culture).get("kind", "settlement"))
