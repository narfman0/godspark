## Determinism and save/restore: same seed gives the same chronicle; a restored sim stepped
## alongside the original stays identical, including through a JSON round trip.
extends RefCounted

func _js(d: Dictionary) -> String:
	return JSON.stringify(d, "", true, true)

## First path where two JSON-like values differ, or "" if equal (for readable failures).
static func diff(a: Variant, b: Variant, path := "") -> String:
	if typeof(a) != typeof(b):
		return "%s: %s (%s) vs %s (%s)" % [path, a, type_string(typeof(a)), b, type_string(typeof(b))]
	if a is Dictionary:
		var ka: Array = a.keys(); ka.sort()
		var kb: Array = b.keys(); kb.sort()
		if ka != kb:
			return "%s: keys %s vs %s" % [path, ka, kb]
		for k in ka:
			var r := diff(a[k], b[k], "%s.%s" % [path, k])
			if r != "":
				return r
		return ""
	if a is Array:
		if a.size() != b.size():
			return "%s: size %d vs %d" % [path, a.size(), b.size()]
		for i in a.size():
			var r := diff(a[i], b[i], "%s[%d]" % [path, i])
			if r != "":
				return r
		return ""
	return "" if a == b else "%s: %s vs %s" % [path, a, b]

## Largest relative float difference between two same-shaped values; -1 if shapes differ.
static func _float_drift(a: Variant, b: Variant) -> float:
	if typeof(a) != typeof(b):
		return -1.0
	if a is float:
		return absf(a - b) / maxf(absf(b), 1.0)
	var m := 0.0
	if a is Dictionary:
		if a.size() != b.size():
			return -1.0
		for k in a:
			if not b.has(k):
				return -1.0
			var r := _float_drift(a[k], b[k])
			if r < 0.0:
				return -1.0
			m = maxf(m, r)
	elif a is Array:
		if a.size() != b.size():
			return -1.0
		for i in a.size():
			var r := _float_drift(a[i], b[i])
			if r < 0.0:
				return -1.0
			m = maxf(m, r)
	elif a != b:
		return -1.0
	return m

func _same(t: TestLog, a: Dictionary, b: Dictionary, msg: String) -> void:
	var d := diff(a, b)
	t.check(d == "", "%s (%s)" % [msg, d])

func run(t: TestLog) -> void:
	var a := WorldSim.synthetic(16, 42)
	var b := WorldSim.synthetic(16, 42)
	a.step(WorldSim.YEAR_H * 25)
	b.step(WorldSim.YEAR_H * 25)
	t.check(a.chronicle.size() > 20, "25 years make a history (%d events)" % a.chronicle.size())
	_same(t, a.to_dict(), b.to_dict(), "same seed, same state after 25 years")
	t.check(_js(a.to_dict()) != _js(WorldSim.synthetic(16, 43).to_dict()), "different seed, different world")
	# Direct round trip.
	var d := a.to_dict()
	_same(t, WorldSim.from_dict(d).to_dict(), d, "to_dict -> from_dict -> to_dict is exact")
	# Binary round trip (exact), then step both.
	var c := WorldSim.from_dict(bytes_to_var(var_to_bytes(d)))
	_same(t, c.to_dict(), d, "var_to_bytes round trip is exact")
	# JSON (sorted keys): same structure and types; Godot's JSON may drop the last bit of a float.
	var j := WorldSim.from_dict(JSON.parse_string(_js(d))).to_dict()
	var drift := _float_drift(j, d)
	t.check(drift >= 0.0 and drift < 1e-9, "JSON round trip keeps structure, types and values (max relative drift %g)" % drift)
	a.step(WorldSim.YEAR_H * 15 + 37)
	c.step(WorldSim.YEAR_H * 15 + 37)
	_same(t, c.to_dict(), a.to_dict(), "restored sim stays identical after 15 more years")
	t.eq(c.chronicle.size(), a.chronicle.size(), "same chronicle length")
	# Odd step sizes give the same result as whole years.
	var e := WorldSim.synthetic(12, 9)
	var f := WorldSim.synthetic(12, 9)
	e.step(WorldSim.YEAR_H * 3)
	for i in WorldSim.YEAR_H * 3 / 7:
		f.step(7)
	f.step(WorldSim.YEAR_H * 3 - (WorldSim.YEAR_H * 3 / 7) * 7)
	_same(t, f.to_dict(), e.to_dict(), "stepping in 7-hour slices equals stepping by years")
	# Every event describes itself.
	var unknown := 0
	for ev in a.chronicle:
		var line := a.describe(ev)
		if not line.begins_with("Year ") or line.contains("{"):
			unknown += 1
	t.eq(unknown, 0, "every chronicle event has a readable line")
