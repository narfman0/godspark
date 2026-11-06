## Standing and patrons (P): every faction you know of (one you have standing with, a patron,
## or one that holds a place you know), with its name, people and towns, your standing as a
## bar from -100 to 100 with the patron tiers and the guards' lines marked, what moved it
## lately, how its guards take you (friendly, wary, hostile), and your patronage: tier, gifts
## given, what it brings. Reads LifeClient (factions, standing), DealsClient (patrons, atlas)
## and DealsUi (recent reasons heard this session).
class_name StandingScreen
extends UiScreen

var box: VBoxContainer

func _init() -> void:
	title = "Standing"
	hint = "Patrons: tiers at 25, 50 and 75. Guards turn friendly at 30 and hostile at -40.   Esc: close"
	panel_size = Vector2(1000, 590)

func build() -> void:
	var sc := ScrollContainer.new()
	sc.position = Vector2(20, 64)
	sc.size = Vector2(panel_size.x - 40, panel_size.y - 100)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(sc)
	box = VBoxContainer.new()
	box.custom_minimum_size.x = sc.size.x - 16
	box.add_theme_constant_override("separation", 8)
	sc.add_child(box)

func attach() -> void:
	var lc := gu.cw.system(HostSystem.LIFE) as LifeClient
	if lc != null:
		lc.factions_changed.connect(refresh)
	var dc := gu.cw.system(HostSystem.DEALS) as DealsClient
	if dc != null:
		dc.patron_changed.connect(func(_p: Dictionary) -> void: refresh())

## Faction ids to show, most standing first.
func shown() -> Array:
	var lc := gu.cw.system(HostSystem.LIFE) as LifeClient
	var dc := gu.cw.system(HostSystem.DEALS) as DealsClient
	if lc == null:
		return []
	var known := MapLogic.discovered(dc.seen, dc.rumours, dc.quests) if dc != null else {}
	var out: Array = []
	for f: String in lc.factions:
		var keep := lc.standing(f) != 0 or (dc != null and dc.patrons.has(f))
		if not keep and dc != null:
			for sid: int in known:
				if String(dc.sites.get(sid, {}).get("faction", "")) == f:
					keep = true
					break
		if keep:
			out.append(f)
	out.sort_custom(func(a: String, b: String) -> bool: return lc.standing(a) > lc.standing(b))
	return out

func refresh() -> void:
	if not visible:
		return
	for ch in box.get_children():
		box.remove_child(ch)
		ch.queue_free()
	var fs := shown()
	if fs.is_empty():
		box.add_child(UiTheme.label("Nobody knows you yet. Give them time.", UiTheme.BODY, UiTheme.INK_SOFT))
		return
	for f: String in fs:
		box.add_child(_card(f))

func _card(f: String) -> Control:
	var lc := gu.cw.system(HostSystem.LIFE) as LifeClient
	var dc := gu.cw.system(HostSystem.DEALS) as DealsClient
	var info: Dictionary = lc.factions.get(f, {})
	var v := lc.standing(f)
	var p: Dictionary = dc.patrons.get(f, {}) if dc != null else {}
	var towns: Array = []
	if dc != null:
		var known := MapLogic.discovered(dc.seen, dc.rumours, dc.quests)
		for sid: int in dc.sites:
			var s: Dictionary = dc.sites[sid]
			if String(s.get("faction", "")) == f and known.has(sid) and String(s.get("name", "")) != "":
				towns.append(String(s["name"]))
	var hist: Array = gu.deals_ui.history.get(f, []) if gu.deals_ui != null else []
	var c := Control.new()
	c.custom_minimum_size = Vector2(box.custom_minimum_size.x, 112)
	var name_ := DealsLogic.cap(String(info.get("name", "Faction " + f)))
	var culture := String(info.get("culture", ""))
	var col := Emblems.faction_color(f)
	var tier := 0 if bool(p.get("suspended", false)) else int(p.get("tier", DealsLogic.tier_of(v)))
	c.draw.connect(func() -> void:
		var w := c.size.x
		UiTheme.ink_rect(c, Rect2(0, 0, w, c.size.y - 4), UiTheme.PARCH_SHADE.lightened(0.2), UiTheme.INK_SOFT, 1.5)
		Emblems.portrait(c, Vector2(42, 46), 30, "guard", col)
		UiTheme.text(c, Vector2(84, 28), name_, UiTheme.HEADING, UiTheme.INK, true)
		var sub := culture.capitalize() + ("" if bool(info.get("alive", true)) else " (fallen)")
		if not towns.is_empty():
			sub += ".  Towns you know: " + ", ".join(PackedStringArray(towns.slice(0, 4)))
		UiTheme.text(c, Vector2(84, 48), sub, UiTheme.SMALL, UiTheme.INK_SOFT, false, HORIZONTAL_ALIGNMENT_LEFT, w - 400)
		# the bar: -100 .. 100
		var bar := Rect2(84, 60, w - 430, 16)
		var frac := (v + 100) / 200.0
		var fill := UiTheme.VERMILION if v <= DealsLogic.HOSTILE_AT else (UiTheme.MOSS if v >= DealsLogic.FRIENDLY_AT else UiTheme.GOLD)
		c.draw_rect(Rect2(bar.position + Vector2(2, 2), bar.size), UiTheme.SHADOW)
		c.draw_rect(bar, UiTheme.PARCHMENT)
		var mid := bar.position.x + bar.size.x * 0.5
		var x := bar.position.x + bar.size.x * frac
		c.draw_rect(Rect2(minf(mid, x), bar.position.y, absf(x - mid), bar.size.y), fill)
		for m: int in [DealsLogic.HOSTILE_AT, 0, DealsLogic.FRIENDLY_AT]:
			var mx := bar.position.x + bar.size.x * (m + 100) / 200.0
			c.draw_line(Vector2(mx, bar.position.y - 3), Vector2(mx, bar.end.y + 3), UiTheme.INK_SOFT, 1.0)
		for i in DealsLogic.TIERS.size():
			var tx := bar.position.x + bar.size.x * (int(DealsLogic.TIERS[i]) + 100) / 200.0
			UiTheme.star(c, Vector2(tx, bar.position.y - 2), 6, 2.5, UiTheme.PLUM if tier > i else UiTheme.PARCH_SHADE, 4, UiTheme.INK)
		c.draw_rect(bar, UiTheme.INK, false, 2.0)
		UiTheme.text(c, Vector2(84, 96), "%+d  %s.  Guards: %s." % [v, DealsLogic.standing_word(v), DealsLogic.guards_word(v)], UiTheme.SMALL,
			UiTheme.BLOOD_DARK if v <= DealsLogic.HOSTILE_AT else UiTheme.INK)
		# right column: patronage and what moved it
		var rx := w - 330
		var pt := "Patron, tier %d. Gifts given: %d." % [tier, int(p.get("given", 0))] if tier > 0 else \
			("Patronage suspended." if bool(p.get("suspended", false)) else "Not your patron (yet: %d to go)." % maxi(0, int(DealsLogic.TIERS[0]) - v))
		UiTheme.text(c, Vector2(rx, 28), pt, UiTheme.SMALL, UiTheme.PLUM.darkened(0.3) if tier > 0 else UiTheme.INK_SOFT, false, HORIZONTAL_ALIGNMENT_LEFT, 320)
		if tier > 0:
			UiTheme.text(c, Vector2(rx, 48), "%d%% off, a free bed%s" % [5 * tier, ", patron work" if tier >= 2 else ""], UiTheme.TINY, UiTheme.INK_SOFT)
		var y := 68.0
		for hrec: Array in hist.slice(maxi(0, hist.size() - 2)):
			UiTheme.text(c, Vector2(rx, y), "%+d  %s" % [int(hrec[0]), String(hrec[1]).replace("_", " ")], UiTheme.TINY, UiTheme.INK, false, HORIZONTAL_ALIGNMENT_LEFT, 320)
			y += 16)
	return c
