## The spell list (B, or click a quick slot): the prepared spells the combat client mirrors
## (SPELLS), the slots left by level (STATUS), and the four quick slots Q R T G. Assign a spell
## with its Q/R/T/G buttons. A spell that cannot be cast now is greyed with the reason (no
## slot, busy, bonus action spent, not in play yet). Hold the key in play to aim (areas show
## their shape), let go to cast.
class_name SpellScreen
extends UiScreen

var rows: VBoxContainer
var info: RichTextLabel
var slots_line: Control

func _init() -> void:
	title = "Spells"
	hint = "Hold Q, R, T or G in play to aim; let go to cast. Areas show where they will land."
	panel_size = Vector2(980, 540)

func build() -> void:
	slots_line = Control.new()
	slots_line.position = Vector2(26, 64)
	slots_line.size = Vector2(600, 30)
	slots_line.draw.connect(_draw_slots)
	panel.add_child(slots_line)
	var sc := ScrollContainer.new()
	sc.position = Vector2(24, 100)
	sc.size = Vector2(600, 400)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(sc)
	rows = VBoxContainer.new()
	rows.custom_minimum_size.x = 585
	sc.add_child(rows)
	info = RichTextLabel.new()
	info.position = Vector2(646, 100)
	info.size = Vector2(310, 400)
	info.add_theme_font_size_override("normal_font_size", UiTheme.SMALL)
	panel.add_child(info)

func attach() -> void:
	if gu.combat != null:
		gu.combat.spells_changed.connect(func(_s: Array) -> void: refresh())
		gu.combat.cooldowns_changed.connect(func(_s: Dictionary) -> void:
			if visible:
				slots_line.queue_redraw())

func refresh() -> void:
	if not visible:
		return
	slots_line.queue_redraw()
	for c in rows.get_children():
		rows.remove_child(c)
		c.queue_free()
	var cc := gu.combat
	var spells: Array = cc.spells if cc != null else []
	if spells.is_empty():
		var l := UiTheme.label("No spells prepared. Steel, then: it never runs out of slots.", UiTheme.BODY, UiTheme.INK_SOFT)
		rows.add_child(l)
		info.text = ""
		return
	for s: Dictionary in spells:
		rows.add_child(_row(s))

static func tags_of(flags: int) -> String:
	var t := PackedStringArray()
	if flags & CombatCodec.SPELL_DAMAGE:
		t.append("harm")
	if flags & CombatCodec.SPELL_HEAL:
		t.append("heal")
	if flags & CombatCodec.SPELL_AREA:
		t.append("area")
	if flags & CombatCodec.SPELL_BONUS:
		t.append("bonus action")
	if flags & CombatCodec.SPELL_REACTION:
		t.append("reaction")
	if flags & CombatCodec.SPELL_CONCENTRATION:
		t.append("concentration")
	return ", ".join(t)

func _row(s: Dictionary) -> Control:
	var row := HBoxContainer.new()
	var why := QuickSlots.why_not(s, gu.combat.status, gu.combat.busy_s)
	var lvl := int(s["level"])
	var nm := UiTheme.button("%s  ·  %s" % [String(s["name"]), "cantrip" if lvl == 0 else "level %d" % lvl], UiTheme.SMALL)
	nm.alignment = HORIZONTAL_ALIGNMENT_LEFT
	nm.custom_minimum_size = Vector2(300, 30)
	nm.clip_text = true
	if why != "" and why != "busy":
		nm.add_theme_color_override("font_color", UiTheme.INK_FADED)
	nm.pressed.connect(func() -> void: _show(s, why))
	nm.mouse_entered.connect(func() -> void: _show(s, why))
	row.add_child(nm)
	var tag := UiTheme.label(tags_of(int(s["flags"])) if why == "" or why == "busy" else why, UiTheme.TINY,
		UiTheme.INK_SOFT if why == "" or why == "busy" else UiTheme.BLOOD_DARK)
	tag.custom_minimum_size.x = 120
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(tag)
	for i in QuickSlots.N:
		var b := UiTheme.button(QuickSlots.KEYS[i], UiTheme.SMALL)
		b.custom_minimum_size = Vector2(32, 28)
		if String(gu.quick_spell(i).get("slug", "")) == String(s["slug"]):
			b.add_theme_stylebox_override("normal", UiTheme.button_box(UiTheme.TEAL.lightened(0.25)))
		b.tooltip_text = "Put %s on %s" % [String(s["name"]), QuickSlots.KEYS[i]]
		b.pressed.connect(func() -> void:
			gu.quick.assign(i, String(s["slug"]))
			gu.hud.bar.queue_redraw()
			refresh())
		row.add_child(b)
	return row

func _show(s: Dictionary, why: String) -> void:
	var slug := String(s["slug"])
	var t := ChoiceLogic.option_text({"kind": "spell"}, {"id": slug})
	info.text = "%s\n%s\n\n%s%s" % [String(s["name"]), tags_of(int(s["flags"])), t if t.length() < 700 else t.substr(0, 700) + "...",
		"\n\nNot now: " + why if why != "" else ""]

func _draw_slots() -> void:
	var st: Dictionary = gu.combat.status if gu.combat != null else {}
	var slots: Array = st.get("slots", [])
	var x := 0.0
	UiTheme.text(slots_line, Vector2(x, 20), "Slots:", UiTheme.BODY, UiTheme.INK)
	x += 56
	var any := false
	for l in mini(9, slots.size()):
		var mx := int(slots[l][1])
		if mx <= 0:
			continue
		any = true
		UiTheme.text(slots_line, Vector2(x, 20), "Lv %d" % (l + 1), UiTheme.SMALL, UiTheme.TEAL.darkened(0.35))
		x += 38
		for k in mx:
			UiTheme.pip(slots_line, Vector2(x + 6, 14), 6, UiTheme.TEAL, k < int(slots[l][0]))
			x += 16
		x += 14
	if not any:
		UiTheme.text(slots_line, Vector2(x, 20), "none (cantrips and steel only)", UiTheme.SMALL, UiTheme.INK_SOFT)
