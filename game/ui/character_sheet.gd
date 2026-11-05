## The character sheet (C): abilities with modifiers and saves, skills, proficiency bonus, AC
## and what makes it up, attacks with to-hit and damage, features from the class kit,
## Knacks, Bonds, deeds, Hit Point Dice, resistances, and movement as the sparks have it.
## Every number is the host's (RulesClient.summary through SheetModel).
class_name CharacterSheet
extends UiScreen

var body: Control
var _m := {}

func _init() -> void:
	title = "Character"
	hint = "C or Esc to close."
	panel_size = Vector2(1140, 590)

func build() -> void:
	body = Control.new()
	body.position = Vector2(20, 60)
	body.size = panel_size - Vector2(40, 90)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.draw.connect(_draw_body)
	panel.add_child(body)

func attach() -> void:
	if gu.rules != null:
		gu.rules.sheet_changed.connect(func(_s: Dictionary) -> void: refresh())
		gu.rules.summary_changed.connect(func(_s: Dictionary) -> void: refresh())
		gu.rules.deeds_changed.connect(func(_d: Dictionary) -> void: refresh())

func refresh() -> void:
	if not visible or gu.rules == null:
		return
	_m = SheetModel.build(gu.rules.summary, gu.cw.stats)
	body.queue_redraw()

func _h(c: Control, p: Vector2, t: String) -> void:
	UiTheme.text(c, p, t, UiTheme.HEADING, UiTheme.INK, true)
	c.draw_line(p + Vector2(0, 5), p + Vector2(UiTheme.text_width(t, UiTheme.HEADING, true), 5), UiTheme.INK_FADED, 1.5)

func _draw_body() -> void:
	if _m.is_empty():
		UiTheme.text(body, Vector2(0, 40), "No sheet yet.", UiTheme.BODY, UiTheme.INK_SOFT)
		return
	var c := body
	var sh: Dictionary = gu.rules.sheet
	UiTheme.text(c, Vector2(250, 0), "%s · level %d · %s %d%s" % [gu.cw.player_name.capitalize(), int(sh["level"]), String(sh["class"]).capitalize(),
		int(sh["class_level"]), (" (%s)" % String(sh["subclass"]).replace("-", " ").capitalize()) if String(sh.get("subclass", "")) != "" else ""],
		UiTheme.BODY, UiTheme.INK_SOFT)
	# abilities: six inked boxes
	var y := 24.0
	for i in 6:
		var a: Dictionary = _m["abilities"][i]
		var r := Rect2(0, y, 220, 58)
		UiTheme.ink_rect(c, r, UiTheme.PARCHMENT.lightened(0.06), UiTheme.INK, 2.0)
		UiTheme.text(c, r.position + Vector2(10, 22), String(a["name"]), UiTheme.SMALL, UiTheme.INK_SOFT, true)
		UiTheme.text(c, r.position + Vector2(10, 48), "%d" % int(a["score"]), UiTheme.HEADING, UiTheme.INK)
		var mod := "%+d" % int(a["mod"])
		c.draw_circle(r.position + Vector2(66, 41), 13, UiTheme.PARCH_SHADE)
		c.draw_arc(r.position + Vector2(66, 41), 13, 0, TAU, 24, UiTheme.INK, 2.0, true)
		UiTheme.text(c, r.position + Vector2(50, 47), mod, UiTheme.SMALL, UiTheme.INK, true, HORIZONTAL_ALIGNMENT_CENTER, 32)
		UiTheme.pip(c, r.position + Vector2(130, 36), 5, UiTheme.TEAL, bool(a["save_prof"]))
		UiTheme.text(c, r.position + Vector2(142, 42), "save %+d" % int(a["save"]), UiTheme.SMALL, UiTheme.INK)
		y += 64
	UiTheme.text(c, Vector2(0, y + 18), "Proficiency bonus %+d" % int(_m["pb"]), UiTheme.BODY, UiTheme.INK)
	UiTheme.text(c, Vector2(0, y + 40), "Hit points %d / %d   ·   Hit Point Dice %d / %d" % [maxi(0, gu.cw.hp), gu.cw.max_hp, int(sh["hit_dice"]), int(sh["hit_dice_max"])], UiTheme.SMALL, UiTheme.INK)
	# skills
	var x := 250.0
	_h(c, Vector2(x, 44), "Skills")
	var sy := 70.0
	var skills: Array = _m["skills"]
	for i in skills.size():
		var s: Dictionary = skills[i]
		var col := x + (i % 2) * 175
		var row := sy + (i / 2) * 22
		UiTheme.pip(c, Vector2(col + 5, row - 5), 4.5, UiTheme.GOLD if bool(s["expert"]) else UiTheme.TEAL, bool(s["prof"]))
		UiTheme.text(c, Vector2(col + 16, row), "%+d  %s" % [int(s["bonus"]), String(s["name"])], UiTheme.SMALL, UiTheme.INK if bool(s["prof"]) else UiTheme.INK_SOFT)
	# armour class and attacks
	var ay := sy + 9 * 22 + 26
	_h(c, Vector2(x, ay), "Armour Class %d" % int(_m["ac"]))
	var py := ay + 24
	for p: Array in _m["ac_parts"]:
		UiTheme.text(c, Vector2(x + 10, py), "%s  %s" % [("%+d" % int(p[1])) if p[1] != 10 or p[0] != "Unarmoured" else "10", String(p[0])], UiTheme.SMALL, UiTheme.INK)
		py += 19
	py += 12
	_h(c, Vector2(x, py), "Attacks")
	py += 24
	for a: Dictionary in _m["attacks"]:
		var per := int(a.get("per_action", 1))
		UiTheme.text(c, Vector2(x + 10, py), "%s  %+d to hit, %s%s" % [String(a["name"]), int(a["to_hit"]), String(a["damage"]), "  (x%d per action)" % per if per > 1 else ""], UiTheme.SMALL, UiTheme.INK)
		py += 19
	# features, knacks, bonds, deeds, resistances, movement
	x = 630.0
	_h(c, Vector2(x, 44), "Features")
	var fy := 68.0
	var feats: Array = _m["features"]
	var line := ""
	for f: Variant in feats:
		var t := String(f) if line == "" else line + ", " + String(f)
		if UiTheme.text_width(t, UiTheme.SMALL) > 460:
			UiTheme.text(c, Vector2(x, fy), line + ",", UiTheme.SMALL, UiTheme.INK)
			fy += 19
			line = String(f)
		else:
			line = t
	if line != "":
		UiTheme.text(c, Vector2(x, fy), line, UiTheme.SMALL, UiTheme.INK)
		fy += 19
	fy += 12
	_h(c, Vector2(x, fy), "Knacks and Bonds")
	fy += 22
	var kn: Array = sh.get("knacks", [])
	var kt := ", ".join(kn.map(func(k: String) -> String: return String(Knacks.def(k).get("name", k))))
	UiTheme.text(c, Vector2(x, fy), kt if kt != "" else "None yet: they come every fifth level, from what you do.", UiTheme.SMALL, UiTheme.INK if kt != "" else UiTheme.INK_SOFT)
	fy += 19
	var bonds: Dictionary = sh.get("bonds", {})
	if not bonds.is_empty():
		UiTheme.text(c, Vector2(x, fy), "Bonds: " + ", ".join(bonds.keys().map(func(b: String) -> String: return b.split(":")[-1].replace("_", " ").capitalize())), UiTheme.SMALL, UiTheme.INK)
		fy += 19
	fy += 12
	_h(c, Vector2(x, fy), "Deeds")
	fy += 22
	var deeds := gu.deeds()
	var dk: Array = deeds.keys().filter(func(k: String) -> bool: return not k.contains(":") or k.begins_with("dig:") or k.begins_with("kill:"))
	dk.sort_custom(func(a: String, b: String) -> bool: return int(deeds[a]) > int(deeds[b]))
	if dk.is_empty():
		UiTheme.text(c, Vector2(x, fy), "Nothing yet. The world is watching, mildly.", UiTheme.SMALL, UiTheme.INK_SOFT)
		fy += 19
	for k: String in dk.slice(0, 5):
		UiTheme.text(c, Vector2(x, fy), UiCopy.deed(k, int(deeds[k])) + ".", UiTheme.SMALL, UiTheme.INK)
		fy += 19
	fy += 12
	_h(c, Vector2(x, fy), "Resistances and movement")
	fy += 22
	var res: Array = _m["resist"]
	UiTheme.text(c, Vector2(x, fy), "Resist: " + (", ".join(res) if not res.is_empty() else "nothing in particular"), UiTheme.SMALL, UiTheme.INK)
	fy += 19
	var langs: Array = _m.get("profs", {}).get("languages", [])
	var tools: Array = _m.get("profs", {}).get("tools", [])
	UiTheme.text(c, Vector2(x, fy), "Speed %d ft.%s%s" % [int(_m["speed_ft"]),
		("  Tools: " + ", ".join(tools)) if not tools.is_empty() else "", ("  Languages: " + ", ".join(langs)) if not langs.is_empty() else ""],
		UiTheme.SMALL, UiTheme.INK)
	var mv: Array = _m["move"]
	for i in range(0, mv.size(), 2):
		fy += 19
		UiTheme.text(c, Vector2(x, fy), ".  ".join(mv.slice(i, i + 2)) + ".", UiTheme.SMALL, UiTheme.INK)
