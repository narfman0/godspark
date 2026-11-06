## The quest log (J). Left: work on offer here (while talking to someone who offers it), work
## under way, and what is done, failed, lapsed or beaten. Right: the chosen quest: who gave it
## and where, the reason in their words, the job, live progress, time left in game days, the
## reward, and Accept / Hand in / Abandon (with what abandoning costs) / Pin to the HUD.
## Reads DealsClient (quests, conversation offers, atlas names); every action is a DealsClient
## request (hand-in goes through the open conversation, as the host wants it).
class_name QuestLogScreen
extends UiScreen

const LIST_W := 360.0

var dc: DealsClient
var list_box: VBoxContainer
var detail: VBoxContainer
var chosen := ""
var _abandon_armed := ""

func _init() -> void:
	title = "Work"
	hint = "Click a line to read it   Pin: show it on the HUD with a pointer   Esc: close"
	panel_size = Vector2(1100, 580)

func build() -> void:
	var sc := ScrollContainer.new()
	sc.position = Vector2(20, 66)
	sc.size = Vector2(LIST_W, panel_size.y - 104)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(sc)
	list_box = VBoxContainer.new()
	list_box.custom_minimum_size.x = LIST_W - 16
	list_box.add_theme_constant_override("separation", 3)
	sc.add_child(list_box)
	var rule := Control.new()
	rule.position = Vector2(LIST_W + 32, 66)
	rule.size = Vector2(3, panel_size.y - 104)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.draw.connect(func() -> void: rule.draw_line(Vector2(1, 0), Vector2(1, rule.size.y), UiTheme.INK_FADED, 2.0))
	panel.add_child(rule)
	var dsc := ScrollContainer.new()
	dsc.position = Vector2(LIST_W + 50, 62)
	dsc.size = Vector2(panel_size.x - LIST_W - 74, panel_size.y - 100)
	dsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(dsc)
	detail = VBoxContainer.new()
	detail.custom_minimum_size.x = dsc.size.x - 16
	detail.add_theme_constant_override("separation", 6)
	dsc.add_child(detail)

func attach() -> void:
	dc = gu.cw.system(HostSystem.DEALS) as DealsClient
	if dc == null:
		return
	dc.quests_changed.connect(func(_q: Array) -> void: refresh())
	dc.talk_changed.connect(func(_c: Dictionary) -> void: refresh())

## Offers in the open conversation, then the log.
func entries() -> Array:
	var out: Array = []
	if dc == null:
		return out
	for q: Dictionary in dc.conversation.get("offers", []):
		if not gu.cw.player_name in (q.get("players", []) as Array):
			var c := q.duplicate()
			c["state"] = "offered"
			out.append(c)
	out.append_array(dc.quests)
	return out

func refresh() -> void:
	if not visible or dc == null:
		return
	for ch in list_box.get_children():
		list_box.remove_child(ch)
		ch.queue_free()
	var all := entries()
	var by := {"offered": [], "active": [], "ended": []}
	for q: Dictionary in all:
		(by[DealsLogic.section_of(q)] as Array).append(q)
	if chosen == "" or all.filter(func(q: Dictionary) -> bool: return String(q["id"]) == chosen).is_empty():
		chosen = String(all[0]["id"]) if not all.is_empty() else ""
		for k: String in ["active", "offered", "ended"]:
			if not (by[k] as Array).is_empty():
				chosen = String(by[k][0]["id"])
				break
	for k: String in ["offered", "active", "ended"]:
		var qs: Array = by[k]
		if qs.is_empty() and k != "active":
			continue
		list_box.add_child(UiTheme.label({"offered": "On offer here", "active": "Under way", "ended": "Done and gone"}[k], UiTheme.HEADING, UiTheme.INK, true))
		if qs.is_empty():
			list_box.add_child(UiTheme.label("Nothing yet. Ask around: \"Any work?\"", UiTheme.SMALL, UiTheme.INK_SOFT))
		for q: Dictionary in qs:
			list_box.add_child(_line(q))
	_detail(all.filter(func(q: Dictionary) -> bool: return String(q["id"]) == chosen))

func _line(q: Dictionary) -> Control:
	var id := String(q["id"])
	var pinned := gu.deals_ui != null and gu.deals_ui.pinned == id
	var b := UiTheme.button(("* " if pinned else "") + String(q.get("title", "")), UiTheme.SMALL + 1)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.custom_minimum_size = Vector2(LIST_W - 20, 34)
	var st := String(q.get("state", ""))
	if id == chosen:
		b.add_theme_stylebox_override("normal", UiTheme.button_box(UiTheme.PARCHMENT.lightened(0.2), UiTheme.INK))
	if st in ["failed", "lapsed", "abandoned", "beaten"]:
		b.add_theme_color_override("font_color", UiTheme.INK_SOFT)
	elif st == "ready":
		b.add_theme_color_override("font_color", UiTheme.MOSS.darkened(0.45))
	b.tooltip_text = DealsLogic.state_word(q)
	b.pressed.connect(func() -> void:
		chosen = id
		_abandon_armed = ""
		refresh())
	return b

func _detail(sel: Array) -> void:
	for ch in detail.get_children():
		detail.remove_child(ch)
		ch.queue_free()
	if sel.is_empty():
		detail.add_child(_wrap("No work. The world has plenty of it: talk to keepers, guards, merchants and priests.", UiTheme.BODY, UiTheme.INK_SOFT))
		return
	var q: Dictionary = sel[0]
	var id := String(q["id"])
	var st := String(q.get("state", ""))
	detail.add_child(UiTheme.label(String(q.get("title", "")), UiTheme.TITLE - 4, UiTheme.INK, true))
	var town := dc.site_name(int(q.get("site", -1)))
	var giver := DealsLogic.role_word(String(q.get("giver", "")))
	var who := "From the %s of %s" % [giver, town] if giver != "" and town != "" else ("From %s" % town if town != "" else "")
	var fac := gu.deals_ui.faction_name(String(q.get("faction", ""))) if gu.deals_ui != null else ""
	if fac != "":
		who += ", " + fac
	detail.add_child(_wrap("%s.  %s." % [who, DealsLogic.state_word(q)], UiTheme.SMALL, UiTheme.INK_SOFT))
	detail.add_child(_wrap("“%s”" % String(q.get("why", "")), UiTheme.BODY, UiTheme.INK))
	detail.add_child(_wrap(String(q.get("goal", "")), UiTheme.BODY, UiTheme.INK))
	if st in ["active", "ready", "offered"]:
		var bar := Control.new()
		bar.custom_minimum_size = Vector2(detail.custom_minimum_size.x, 30)
		var frac := DealsLogic.progress_frac(q)
		var ptxt := DealsLogic.progress_text(q)
		bar.draw.connect(func() -> void:
			UiTheme.ink_bar(bar, Rect2(0, 6, 300, 16), frac, UiTheme.MOSS if st == "ready" else UiTheme.GOLD, UiTheme.PARCH_SHADE)
			UiTheme.text(bar, Vector2(316, 21), ptxt, UiTheme.SMALL, UiTheme.INK))
		detail.add_child(bar)
		var tl := DealsLogic.time_left(int(q.get("due", 0)), dc.sim_hour())
		var where := ""
		var tgt := MapLogic.quest_target(q, gu.cw.world.meta)
		if tgt != Vector2.INF:
			where = "  Way: %s." % String(DealsLogic.bearing(gu.cw.body.center(), tgt)["text"])
			if q.has("target_site") and dc.site_name(int(q["target_site"])) != "":
				where = "  Way to %s: %s." % [dc.site_name(int(q["target_site"])), String(DealsLogic.bearing(gu.cw.body.center(), tgt)["text"])]
		detail.add_child(_wrap("%s.%s" % [DealsLogic.cap(tl) if tl != "" else "No hurry", where], UiTheme.SMALL, UiTheme.INK_SOFT))
	if q.has("reward"):
		detail.add_child(_wrap("Reward: %s." % DealsLogic.reward_text(q["reward"]), UiTheme.BODY, UiTheme.GOLD.darkened(0.5)))
	elif int(q.get("paid", 0)) > 0:
		detail.add_child(_wrap("Paid %d coin." % int(q["paid"]), UiTheme.BODY, UiTheme.GOLD.darkened(0.5)))
	var players: Array = q.get("players", [])
	if players.size() > 1:
		detail.add_child(_wrap("With: %s." % ", ".join(PackedStringArray(players)), UiTheme.SMALL, UiTheme.INK_SOFT))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	detail.add_child(row)
	match st:
		"offered":
			var a := UiTheme.button("Accept", UiTheme.BODY)
			a.pressed.connect(func() -> void: dc.accept(id))
			row.add_child(a)
		"active", "ready":
			var pin := UiTheme.button("Unpin" if gu.deals_ui.pinned == id else "Pin to the HUD", UiTheme.BODY)
			pin.pressed.connect(func() -> void:
				gu.deals_ui.pinned = "" if gu.deals_ui.pinned == id else id
				refresh())
			row.add_child(pin)
			if _can_hand_in(id):
				var h := UiTheme.button("Hand it in", UiTheme.BODY)
				h.pressed.connect(func() -> void: gu.deals_ui.choose("turn_in:" + id))
				row.add_child(h)
			var ab := UiTheme.button("Abandon" if _abandon_armed != id else "Really abandon", UiTheme.BODY)
			ab.pressed.connect(func() -> void:
				if _abandon_armed == id:
					dc.abandon(id)
					_abandon_armed = ""
				else:
					_abandon_armed = id
				refresh())
			row.add_child(ab)
			if _abandon_armed == id:
				detail.add_child(_wrap(DealsLogic.abandon_text(q), UiTheme.SMALL, UiTheme.BLOOD_DARK))

func _can_hand_in(id: String) -> bool:
	for o: Dictionary in dc.conversation.get("options", []):
		if String(o["id"]) == "turn_in:" + id:
			return true
	return false

func _wrap(s: String, sz: int, col: Color) -> Label:
	var l := UiTheme.label(s, sz, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = detail.custom_minimum_size.x - 4
	return l
