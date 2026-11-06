## Plates in a crowd (Nameplates.arrange): a raid's plates used to stack into a tower to the top
## of the screen. And Nameplates.fit: a long name is shortened at a word.
extends RefCounted

func run(t: TestLog) -> void:
	_tower(t)
	_spread(t)
	_order(t)
	_tall(t)
	_fit(t)

func _crowd(n: int, step := 6.0, tall := 44.0) -> Array:
	var out: Array = []
	for i in n:
		out.append({"at": Vector2(600.0 + i * step, 300.0), "tall": tall})
	return out

func _counts(spots: Array) -> Dictionary:
	var c := {"named": 0, "bars": 0, "none": 0, "top": INF}
	for s: Dictionary in spots:
		if s.is_empty():
			c["none"] += 1
			continue
		c["bars" if s["bar"] else "named"] += 1
		c["top"] = minf(c["top"], (s["box"] as Rect2).position.y)
	return c

func _overlaps(spots: Array) -> int:
	var n := 0
	for i in spots.size():
		for j in range(i + 1, spots.size()):
			if not (spots[i] as Dictionary).is_empty() and not (spots[j] as Dictionary).is_empty() \
					and (spots[i]["box"] as Rect2).intersects(spots[j]["box"]):
				n += 1
	return n

## The picture that started it: a dozen raiders within a few tiles of each other.
func _tower(t: TestLog) -> void:
	var spots := Nameplates.arrange(_crowd(12), 1.0)
	var c := _counts(spots)
	t.eq(c["named"], Nameplates.STACK, "a crowd: names for the first few only")
	t.check(int(c["bars"]) >= 1, "the rest as bars (%d, %d with nothing)" % [c["bars"], c["none"]])
	var most := Nameplates.STACK * (Nameplates.H + Nameplates.GAP) + Nameplates.BAR_ROWS * (Nameplates.BAR_H + Nameplates.GAP)
	t.check(300.0 - float(c["top"]) <= most, "the stack is capped: %.0f px above the heads, at most %.0f" % [300.0 - float(c["top"]), most])
	t.check(float(c["top"]) > 100.0, "nowhere near the top of the screen (%.0f)" % c["top"])
	t.eq(_overlaps(spots), 0, "nothing drawn on top of anything")
	t.check(not bool(spots[0]["bar"]) and not bool(spots[1]["bar"]), "the first in line keep their names")
	var big := _counts(Nameplates.arrange(_crowd(12), 2.0))
	t.check(300.0 - float(big["top"]) <= most * 2.0, "scaled with the interface (%.0f px at 2x)" % [300.0 - float(big["top"])])

## Room to spare: everyone keeps a name, however many.
func _spread(t: TestLog) -> void:
	var spots := Nameplates.arrange(_crowd(6, 200.0), 1.0)
	var c := _counts(spots)
	t.eq(c["named"], 6, "spread out, all six keep their names")
	t.eq(c["top"], 300.0 - Nameplates.H, "and sit at their heads")

func _order(t: TestLog) -> void:
	t.check(Nameplates.priority(true, false, "") < Nameplates.priority(false, true, ""), "under the cursor comes first")
	t.check(Nameplates.priority(false, true, "") < Nameplates.priority(false, false, "boss"), "then players")
	t.check(Nameplates.priority(false, false, "elite") < Nameplates.priority(false, false, ""), "then ranked foes")
	t.eq(Nameplates.priority(false, false, "minion"), Nameplates.priority(false, false, ""), "a minion is nobody special")

## Plates with affixes are taller: still capped.
func _tall(t: TestLog) -> void:
	var c := _counts(Nameplates.arrange(_crowd(10, 6.0, 60.0), 1.0))
	t.eq(c["named"], Nameplates.STACK, "tall plates: the same number of names")
	t.check(300.0 - float(c["top"]) <= Nameplates.STACK * 62.0 + Nameplates.BAR_ROWS * (Nameplates.BAR_H + Nameplates.GAP), "and capped")

func _fit(t: TestLog) -> void:
	var fs := UiTheme.SMALL
	var w := Nameplates.W - 8.0
	t.eq(Nameplates.fit("Durgarth, raider", fs, w), "Durgarth, raider", "a short name is left alone")
	var long := "Wexbridge, guard of the Far Marches of Tarniholm and the Hazadek Hold"
	var cut := Nameplates.fit(long, fs, w)
	t.check(cut.ends_with("...") and cut.length() < long.length(), "a long name is shortened (%s)" % cut)
	t.check(UiTheme.text_width(cut, fs) <= w, "and fits (%.0f of %.0f)" % [UiTheme.text_width(cut, fs), w])
	t.check(long.begins_with(cut.trim_suffix("...")) and long[cut.length() - 3] == " ", "at a word")
	var word := "Rhindaunmorgathulkazanthrimdurelkharosvenn".repeat(2)
	var one := Nameplates.fit(word, fs, w)
	t.check(one.ends_with("...") and UiTheme.text_width(one, fs) <= w and word.begins_with(one.trim_suffix("...")), "one endless word is cut in the middle (%s)" % one)
	t.eq(Nameplates.fit("", fs, w), "", "no name, no dots")
