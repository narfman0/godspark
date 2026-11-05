## Pending choices (U, or the HUD badge): SRD class-level choices (ability score improvements
## and feats, spells and cantrips, fighting styles, subclasses...), Knack offers as three
## inked cards with the deed that earned each, and the Epic Boon at 100. Counts are checked
## (ChoiceLogic.validate) before `answer` goes to the host; "Later" leaves it pending.
class_name ChoicesScreen
extends UiScreen

var list: VBoxContainer
var body: Control
var current := ""
var picked: Array = []
var details: Array = []
var _status: Label

func _init() -> void:
	title = "Choices waiting"
	hint = "Nothing here is urgent: the world keeps turning, and a choice keeps until you make it."
	panel_size = Vector2(1080, 560)

func build() -> void:
	list = VBoxContainer.new()
	list.position = Vector2(24, 70)
	list.size = Vector2(230, 440)
	panel.add_child(list)
	body = Control.new()
	body.position = Vector2(270, 64)
	body.size = Vector2(panel_size.x - 290, 460)
	panel.add_child(body)

func attach() -> void:
	if gu.rules == null:
		return
	gu.rules.sheet_changed.connect(func(_s: Dictionary) -> void: refresh())
	gu.rules.choice_pending.connect(func(_c: Dictionary) -> void: refresh())

func refresh() -> void:
	if not visible or gu.rules == null:
		return
	for c in list.get_children():
		c.queue_free()
	var keys: Array = gu.rules.pending_keys().filter(func(k: String) -> bool: return gu.rules.choices.has(k))
	if not keys.has(current):
		current = keys[0] if not keys.is_empty() else ""
		picked = []
		details = []
	for k: String in keys:
		var ch: Dictionary = gu.rules.choices[k]
		var b := UiTheme.button(String(ch.get("label", k)).replace(" (class level ", ", class level ").replace(" (level ", ", level ").replace(")", "").replace("Ability Score Improvement or Feat", "Improvement or Feat"), UiTheme.SMALL)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(230, 30)
		b.clip_text = true
		if k == current:
			b.add_theme_stylebox_override("normal", UiTheme.button_box(UiTheme.GOLD))
		b.pressed.connect(func() -> void:
			current = k
			picked = []
			details = []
			refresh())
		list.add_child(b)
	_build_body()

func _clear_body() -> void:
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()

func _build_body() -> void:
	_clear_body()
	if current == "":
		var l := UiTheme.label("Nothing waits on you. Go and do something worth a Knack.", UiTheme.HEADING, UiTheme.INK_SOFT)
		l.position = Vector2(20, 40)
		body.add_child(l)
		return
	var ch: Dictionary = gu.rules.choices[current]
	var kind := String(ch.get("kind", ""))
	var head := UiTheme.label(String(ch.get("label", current)), UiTheme.HEADING, UiTheme.INK, true)
	head.position = Vector2(0, 0)
	body.add_child(head)
	if kind == "knack" or (kind == "boon" and (ch.get("options", []) as Array).size() <= 3):
		_cards(ch)
		return
	_options(ch)

## Three inked cards; a click takes the Knack.
func _cards(ch: Dictionary) -> void:
	var opts: Array = ch.get("options", [])
	var sub := UiTheme.label("Your deeds put these on the table. Take one.", UiTheme.SMALL, UiTheme.INK_SOFT)
	sub.position = Vector2(0, 34)
	body.add_child(sub)
	for i in opts.size():
		var o: Dictionary = opts[i]
		var card := KnackCard.new()
		card.position = Vector2(i * 262, 70)
		card.size = Vector2(246, 330)
		card.setup(ch, o, gu.deeds())
		card.picked.connect(func(id: String) -> void:
			if String(ch.get("kind", "")) == "knack":
				gu.rules.pick_knack(id)
			else:
				gu.rules.answer(current, [id])
			gu.toast("Taken: %s." % String(o.get("name", id)), 3.0, UiTheme.GOLD.darkened(0.4)))
		body.add_child(card)

func _options(ch: Dictionary) -> void:
	var kind := String(ch.get("kind", ""))
	var n := int(ch.get("count", 1))
	var opts: Array = ch.get("options", [])
	var sc := ScrollContainer.new()
	sc.position = Vector2(0, 40)
	sc.size = Vector2(body.size.x * 0.55, 330)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	sc.add_child(grid)
	var text := RichTextLabel.new()
	text.position = Vector2(body.size.x * 0.58, 40)
	text.size = Vector2(body.size.x * 0.42, 330)
	text.bbcode_enabled = false
	text.add_theme_font_size_override("normal_font_size", UiTheme.SMALL)
	body.add_child(text)
	for o: Dictionary in opts:
		var id := String(o["id"])
		var label := String(o.get("name", id))
		if o.has("level"):
			label += "  (%s)" % ("cantrip" if int(o["level"]) == 0 else "lv %d" % int(o["level"]))
		var b := UiTheme.button(label, UiTheme.SMALL)
		b.custom_minimum_size = Vector2(sc.size.x * 0.5 - 10, 28)
		b.clip_text = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if id in picked:
			b.add_theme_stylebox_override("normal", UiTheme.button_box(UiTheme.GOLD))
			b.add_theme_stylebox_override("hover", UiTheme.button_box(UiTheme.GOLD.lightened(0.2)))
		if not bool(o.get("modelled", true)):
			b.tooltip_text = "Recorded, but not simulated yet."
		b.mouse_entered.connect(func() -> void: text.text = "%s\n\n%s" % [String(o.get("name", id)), ChoiceLogic.option_text(ch, o)])
		b.pressed.connect(func() -> void:
			picked = ChoiceLogic.toggle(picked, id, 1 if kind == "asi" else n)
			if kind == "asi":
				details = []
			text.text = "%s\n\n%s" % [String(o.get("name", id)), ChoiceLogic.option_text(ch, o)]
			_build_body())
		grid.add_child(b)
	if not picked.is_empty():
		text.text = "%s\n\n%s" % [String(picked[-1]).replace("-", " ").capitalize(), ChoiceLogic.option_text(ch, {"id": picked[-1]})]
	var y := 384.0
	if kind == "asi" and not picked.is_empty():
		var need := ChoiceLogic.asi_details(String(picked[0]))
		if not need.is_empty():
			var row := HBoxContainer.new()
			row.position = Vector2(0, y - 8)
			body.add_child(row)
			var pool: Array = ChoiceLogic.ABILITIES if String(need["what"]) == "abilities" else (["str", "dex"] if String(need["what"]) == "str_dex" else
				["athletics", "acrobatics", "stealth", "perception", "insight", "arcana", "history", "medicine", "survival", "persuasion", "deception", "intimidation"])
			for a: String in pool:
				var cnt := details.count(a)
				var b2 := UiTheme.button(a.to_upper() if a.length() == 3 else a.capitalize() + (" x%d" % cnt if cnt > 1 else ""), UiTheme.TINY)
				if cnt > 0:
					b2.add_theme_stylebox_override("normal", UiTheme.button_box(UiTheme.TEAL.lightened(0.3)))
				b2.pressed.connect(func() -> void:
					if String(need["what"]) == "abilities":
						if details.size() >= 2:
							details = []
						details.append(a)
					else:
						details = ChoiceLogic.toggle(details, a, int(need["n"]))
					_build_body())
				row.add_child(b2)
			y += 30
	var ans := ChoiceLogic.answer_for(ch, picked, details)
	var why := ChoiceLogic.validate(ch, ans)
	_status = UiTheme.label(why if why != "" else "Ready.", UiTheme.SMALL, UiTheme.BLOOD_DARK if why != "" else Color("3d6b1f"))
	_status.position = Vector2(0, y + 12)
	body.add_child(_status)
	var ok := UiTheme.button("Choose", UiTheme.BODY)
	ok.position = Vector2(body.size.x - 220, y + 6)
	ok.disabled = why != ""
	ok.pressed.connect(func() -> void:
		gu.rules.answer(current, ans)
		picked = []
		details = [])
	body.add_child(ok)
	var later := UiTheme.button("Later", UiTheme.BODY)
	later.position = Vector2(body.size.x - 110, y + 6)
	later.pressed.connect(func() -> void: gu.close(String(name)))
	body.add_child(later)
