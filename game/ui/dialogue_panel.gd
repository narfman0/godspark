## Talking to someone: a parchment panel anchored low on the screen (the world stays visible
## and running: it is co-op). Left: the speaker's portrait (role icon on their faction's
## colour), name, role and town, and their line. Under it the options as inked buttons with
## their number keys (1-9; 0 or Esc leaves). Right: what the view brings: rumours as short
## notes with the place named and a "mark on map" box (on by default), work on offer as cards
## with an Accept button, a patron's word. Every choice is a DealsClient request; the host
## answers with the next TALK (or closes it, and DealsUi says why).
class_name DialoguePanel
extends Control

const W := 940.0
const H := 204.0
const LEFT_W := 520.0

var gu: GameUi
var dui: DealsUi
var dc: DealsClient
var bg: Panel
var portrait: Control
var name_l: Label
var sub_l: Label
var line_l: Label
var opts: HFlowContainer
var side: ScrollContainer
var side_box: VBoxContainer
var side_title: Label
var _role := ""
var _faction := ""

func setup(g: GameUi, d: DealsUi) -> void:
	gu = g
	dui = d
	dc = d.dc
	name = "dialogue"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	bg = Panel.new()
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.size = Vector2(W, H)
	add_child(bg)
	portrait = Control.new()
	portrait.position = Vector2(16, 16)
	portrait.size = Vector2(92, 92)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.draw.connect(func() -> void: Emblems.portrait(portrait, Vector2(46, 46), 42, _role, Emblems.faction_color(_faction)))
	bg.add_child(portrait)
	name_l = UiTheme.label("", UiTheme.HEADING + 2, UiTheme.INK, true)
	name_l.position = Vector2(120, 12)
	bg.add_child(name_l)
	sub_l = UiTheme.label("", UiTheme.SMALL, UiTheme.INK_SOFT)
	sub_l.position = Vector2(122, 42)
	bg.add_child(sub_l)
	line_l = UiTheme.label("", UiTheme.BODY, UiTheme.INK)
	line_l.position = Vector2(122, 62)
	line_l.size = Vector2(LEFT_W - 130, 56)
	line_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line_l.max_lines_visible = 3
	bg.add_child(line_l)
	opts = HFlowContainer.new()
	opts.position = Vector2(16, 122)
	opts.size = Vector2(LEFT_W - 10, H - 130)
	opts.add_theme_constant_override("h_separation", 6)
	opts.add_theme_constant_override("v_separation", 6)
	bg.add_child(opts)
	var rule := Control.new()
	rule.position = Vector2(LEFT_W + 14, 14)
	rule.size = Vector2(3, H - 28)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.draw.connect(func() -> void: rule.draw_line(Vector2(1, 0), Vector2(1, rule.size.y), UiTheme.INK_FADED, 2.0))
	bg.add_child(rule)
	side_title = UiTheme.label("", UiTheme.HEADING, UiTheme.INK, true)
	side_title.position = Vector2(LEFT_W + 30, 10)
	bg.add_child(side_title)
	side = ScrollContainer.new()
	side.position = Vector2(LEFT_W + 28, 42)
	side.size = Vector2(W - LEFT_W - 44, H - 54)
	side.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bg.add_child(side)
	side_box = VBoxContainer.new()
	side_box.custom_minimum_size.x = side.size.x - 14
	side_box.add_theme_constant_override("separation", 6)
	side.add_child(side_box)

func layout(vs: Vector2) -> void:
	size = vs
	bg.position = Vector2(floorf((vs.x - W) * 0.5), vs.y - H - 66)

## Show the open conversation (or hide when there is none, or a shop screen covers it).
func refresh() -> void:
	var c := dc.conversation
	visible = not c.is_empty() and not gu.is_open("shop")
	if c.is_empty():
		return
	_role = String(c.get("role", ""))
	_faction = String(c.get("faction", ""))
	portrait.queue_redraw()
	name_l.text = String(c.get("name", ""))
	sub_l.text = dui.speaker_line(c)
	line_l.text = "“%s”" % String(c.get("line", ""))
	for ch in opts.get_children():
		opts.remove_child(ch)
		ch.queue_free()
	var i := 1
	for o: Dictionary in c.get("options", []):
		var id := String(o["id"])
		var b := UiTheme.button("%d  %s" % [i, String(o["label"])] if i <= 9 else String(o["label"]), UiTheme.SMALL + 1)
		if id == "bye":
			b.text = "0  %s" % String(o["label"])
		b.pressed.connect(func() -> void: dui.choose(id))
		opts.add_child(b)
		i += 1
	_side(c)

func _side(c: Dictionary) -> void:
	for ch in side_box.get_children():
		side_box.remove_child(ch)
		ch.queue_free()
	var view := String(c.get("view", "main"))
	match view:
		"rumours":
			var rs: Array = c.get("rumours", [])
			side_title.text = "What they've heard" if not rs.is_empty() else "No news"
			var fresh := {}
			for r: Dictionary in c.get("new", []):
				fresh[int(r["id"])] = true
			for r: Dictionary in rs:
				side_box.add_child(_rumour_card(r, fresh.has(int(r["id"]))))
		"quests":
			var offers: Array = c.get("offers", [])
			side_title.text = "Work on offer" if not offers.is_empty() else "No work today"
			for q: Dictionary in offers:
				side_box.add_child(_offer_card(q))
		"patron":
			side_title.text = "Patronage"
			side_box.add_child(_text(dui.patron_summary(_faction), UiTheme.SMALL))
		_:
			var mine: Array = dc.quests_in("active").filter(func(q: Dictionary) -> bool: return int(q.get("site", -1)) == int(c.get("site", -2)))
			side_title.text = "Your work here" if not mine.is_empty() else "%s" % dui.town_line(int(c.get("site", -1)))
			for q: Dictionary in mine:
				side_box.add_child(_text("%s: %s (%s)" % [q.get("title", ""), DealsLogic.progress_text(q), DealsLogic.state_word(q).to_lower()], UiTheme.SMALL))
			if mine.is_empty():
				var st := dui.town_state(int(c.get("site", -1)))
				if st != "":
					side_box.add_child(_text(st, UiTheme.SMALL, UiTheme.INK_SOFT))

func _text(s: String, sz := UiTheme.SMALL, col := UiTheme.INK) -> Label:
	var l := UiTheme.label(s, sz, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = side_box.custom_minimum_size.x - 4
	return l

func _card() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UiTheme.panel_box(UiTheme.PARCH_SHADE.lightened(0.25), UiTheme.INK_SOFT, 1, 3)
	sb.set_content_margin_all(6)
	sb.shadow_size = 0
	p.add_theme_stylebox_override("panel", sb)
	return p

## A rumour as a note: what happened, where, and "mark on map".
func _rumour_card(r: Dictionary, fresh: bool) -> Control:
	var p := _card()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	p.add_child(v)
	var parts := DealsLogic.rumour_parts(String(r.get("text", "")))
	var when := UiTheme.label(("New.  " if fresh else "") + parts[0], UiTheme.TINY, UiTheme.VERMILION.darkened(0.3) if fresh else UiTheme.INK_SOFT)
	v.add_child(when)
	var t := _text(parts[1], UiTheme.SMALL)
	t.custom_minimum_size.x = side_box.custom_minimum_size.x - 20
	v.add_child(t)
	var sid := int(r.get("site", -1))
	if sid >= 0:
		var h := HBoxContainer.new()
		var where := "%s, %s %s" % [dui.site_label(sid), String(r.get("dist", "")), String(r.get("dir", ""))]
		h.add_child(UiTheme.label(where.strip_edges(), UiTheme.TINY, UiTheme.INK_SOFT))
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(sp)
		var cb := CheckBox.new()
		cb.text = "mark on map"
		cb.add_theme_font_size_override("font_size", UiTheme.TINY)
		cb.add_theme_color_override("font_color", UiTheme.INK)
		cb.add_theme_color_override("font_hover_color", UiTheme.INK)
		cb.add_theme_color_override("font_pressed_color", UiTheme.INK)
		cb.focus_mode = Control.FOCUS_NONE
		cb.button_pressed = dui.is_marked(int(r.get("id", -1)))
		cb.toggled.connect(func(on: bool) -> void: dui.set_marked(int(r.get("id", -1)), on))
		h.add_child(cb)
		v.add_child(h)
	return p

## Work on offer: title, why (their words), the job, time, reward, Accept.
func _offer_card(q: Dictionary) -> Control:
	var p := _card()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	p.add_child(v)
	var w := side_box.custom_minimum_size.x - 20
	var title := UiTheme.label(String(q.get("title", "")), UiTheme.BODY, UiTheme.INK, true)
	v.add_child(title)
	var why := _text("“%s”" % String(q.get("why", "")), UiTheme.SMALL, UiTheme.INK_SOFT)
	why.custom_minimum_size.x = w
	v.add_child(why)
	var goal := _text(String(q.get("goal", "")), UiTheme.SMALL)
	goal.custom_minimum_size.x = w
	v.add_child(goal)
	var tl := DealsLogic.time_left(int(q.get("due", 0)), dc.sim_hour())
	v.add_child(_text("Reward: %s.  %s" % [DealsLogic.reward_text(q.get("reward", {})), tl.capitalize() if tl != "" else ""], UiTheme.TINY, UiTheme.GOLD.darkened(0.5)))
	var mine := gu.cw.player_name in (q.get("players", []) as Array)
	var b := UiTheme.button("Taken" if mine else ("Accept" if String(q.get("state", "")) == "offered" else "Join them"), UiTheme.SMALL)
	b.disabled = mine
	b.pressed.connect(func() -> void: dc.accept(String(q["id"])))
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(b)
	return p
