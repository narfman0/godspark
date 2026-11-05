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
