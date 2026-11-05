## The heads-up display, drawn in ink on a few custom-drawn Controls (no per-frame node churn):
##   top left    vitals plate: sigil, name, level and class level, hit points (+ a pale tail
##               for recent loss), XP toward the next level with what it gives, Hit Point
##               Dice, spell slots by level as pips; a badge for pending choices; conditions
##   top right   the world clock (sun or moon over a little horizon, day and time) and coin
##   bottom      action / bonus / reaction timers, the 10-slot hotbar, the four quick spells
##   right       toasts;  top centre: the level-up banner;  above the hotbar: context prompts
## Everything reads GameUi's client systems; nothing here changes game state except the hotbar
## selection (items.select_hotbar).
class_name Hud
extends Control

const SLOT := 46.0
const GAP := 4.0
const QSLOT := 42.0
const TOAST_MAX := 5

var gu: GameUi
var vitals: Control
var clock: Control
var bar: Control
var prompt_box: Control
var toasts: VBoxContainer
var banner_box: Control
var downed_box: Control
## Entities the own player has damaged (for kills in the deed tally, and nameplates).
var hurt_by_me := {}
## SRD condition names on the own player (CONDITION events).
var conditions := {}

var _hp_ghost := 0.0
var _hp_ghost_t := 0.0
var _last := {}
var _clock_t := 0.0
var _action_max := 0.6
var _banner_t := -1.0
var _banner_title := ""
var _banner_line := ""
var _sel_name_t := 0.0
var _sel_seen := -1
var _xp_acc := 0
var _xp_src := ""
var _xp_t := -1.0
var _dimmed := false
## Prompt: {text, sub, progress (-1 none), color}
var prompt := {}
## Downed overlay state, set by GameUi's rest/downed logic: {} hidden.
var downed := {}
var _night_t := -1.0
var _night_h := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	vitals = _canvas("vitals", _draw_vitals)
	clock = _canvas("clock", _draw_clock)
	bar = _canvas("bar", _draw_bar)
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.gui_input.connect(_bar_input)
	bar.tooltip_text = " "
	prompt_box = _canvas("prompt", _draw_prompt)
	prompt_box.z_index = 20
	banner_box = _canvas("banner", _draw_banner)
	downed_box = _canvas("downed", _draw_downed)
	toasts = VBoxContainer.new()
	toasts.name = "toasts"
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.add_theme_constant_override("separation", 6)
	toasts.z_index = 20      # over screens too
	add_child(toasts)
	resized.connect(_layout)
	_layout()

func _canvas(n: String, fn: Callable) -> Control:
	var c := Control.new()
	c.name = n
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(fn.bind(c))
	add_child(c)
	return c

func _layout() -> void:
	var s := size
	vitals.position = Vector2(12, 12)
	vitals.size = Vector2(350, 190)
	clock.size = Vector2(220, 74)
	clock.position = Vector2(s.x - clock.size.x - 12, 12)
	var w := 3 * 34.0 + 12 + 10 * SLOT + 9 * GAP + 16 + 4 * QSLOT + 3 * GAP
	bar.size = Vector2(w, SLOT + 22)
	bar.position = Vector2((s.x - w) * 0.5, s.y - bar.size.y - 8)
	prompt_box.size = Vector2(520, 70)
	prompt_box.position = Vector2((s.x - 520) * 0.5, bar.position.y - 84)
	banner_box.size = Vector2(620, 110)
	banner_box.position = Vector2((s.x - 620) * 0.5, 70)
	downed_box.size = s
	downed_box.position = Vector2.ZERO
	toasts.position = Vector2(s.x - 332, 100)
	toasts.size = Vector2(320, 300)

func attach() -> void:
	if gu.items != null:
		gu.items.inventory_changed.connect(func(_i: Array) -> void: bar.queue_redraw())
		gu.items.constellation_changed.connect(vitals.queue_redraw)
	if gu.rules != null:
		gu.rules.sheet_changed.connect(func(_s: Dictionary) -> void: vitals.queue_redraw())
	if gu.combat != null:
		gu.combat.spells_changed.connect(func(_s: Array) -> void: bar.queue_redraw())
		gu.combat.cooldowns_changed.connect(func(_s: Dictionary) -> void:
			bar.queue_redraw()
			vitals.queue_redraw())
	_hp_ghost = float(gu.cw.hp)

func set_dimmed(d: bool) -> void:
	_dimmed = d
	bar.modulate.a = 0.55 if d else 1.0
	vitals.visible = not d
	clock.visible = not d
	banner_box.visible = not d
	toasts.position.y = 4.0 if d else 100.0

# --- per frame (cheap: redraws only what changed) ----------------------------------------

func tick(delta: float) -> void:
	var cw := gu.cw
	var hp := Vector2i(cw.hp, cw.max_hp)
	if hp != _last.get("hp", Vector2i(-9, -9)):
		if hp.x > _hp_ghost or _last.get("hp", Vector2i(-9, -9)).x < 0:
			_hp_ghost = hp.x
		_hp_ghost_t = 0.6
		_last["hp"] = hp
		vitals.queue_redraw()
	if _hp_ghost > hp.x:
		_hp_ghost_t -= delta
		if _hp_ghost_t <= 0.0:
			_hp_ghost = maxf(float(hp.x), _hp_ghost - delta * maxf(8.0, hp.y * 0.6))
		vitals.queue_redraw()
	_clock_t -= delta
	if _clock_t <= 0.0:
		_clock_t = 1.0
		clock.queue_redraw()
	var cc := gu.combat
	if cc != null:
		var a := float(cc.status.get("action", 0.0))
		if a > _action_max or a <= 0.0:
			_action_max = maxf(0.3, a)
		var busy := a > 0.0 or float(cc.status.get("bonus", 0.0)) > 0.0 or float(cc.status.get("reaction", 0.0)) > 0.0 or cc.busy_s > 0.0
		if busy or bool(_last.get("busy", false)):
			bar.queue_redraw()
		_last["busy"] = busy
	if gu.items != null and gu.items.selected() != _sel_seen:
		_sel_seen = gu.items.selected()
		_sel_name_t = 2.0
		bar.queue_redraw()
	if _sel_name_t > 0.0:
		_sel_name_t -= delta
		bar.queue_redraw()
	if _banner_t >= 0.0:
		_banner_t += delta
		banner_box.queue_redraw()
		if _banner_t > 4.5:
			_banner_t = -1.0
	if _xp_t >= 0.0:
		_xp_t += delta
		if _xp_t > 1.2:
			toast("+%d XP%s" % [_xp_acc, "  (%s)" % _xp_src if _xp_src != "" else ""], 2.2, UiTheme.GOLD.darkened(0.45))
			_xp_t = -1.0
			_xp_acc = 0
	for c in toasts.get_children():
		var left := float(c.get_meta("left", 0.0)) - delta
		c.set_meta("left", left)
		c.modulate.a = clampf(left / 0.5, 0.0, 1.0)
		if left <= 0.0:
			c.queue_free()
	if _night_t >= 0.0:
		_night_t += delta
		if _night_t > 3.2:
			_night_t = -1.0
	if not downed.is_empty() or downed_box.visible or _night_t >= 0.0:
		downed_box.visible = not downed.is_empty() or _night_t >= 0.0
		downed_box.queue_redraw()
	prompt_box.visible = not prompt.is_empty() and not _dimmed
	if prompt_box.visible:
		prompt_box.queue_redraw()

# --- toasts, banner, xp ------------------------------------------------------------------------

func toast(text: String, secs := 3.5, color := UiTheme.INK) -> void:
	# the same words again: count them instead of stacking copies
	if toasts.get_child_count() > 0:
		var last := toasts.get_child(toasts.get_child_count() - 1)
		if String(last.get_meta("text", "")) == text and float(last.get_meta("left", 0.0)) > 0.3:
			var n := int(last.get_meta("n", 1)) + 1
			last.set_meta("n", n)
			last.set_meta("left", secs)
			(last.get_child(0) as Label).text = "%s  (x%d)" % [text, n]
			return
	var p := PanelContainer.new()
	p.set_meta("text", text)
	var box := UiTheme.panel_box(UiTheme.PARCHMENT, color if color != UiTheme.INK else UiTheme.INK, 2, 4)
	box.set_content_margin_all(6)
	box.content_margin_left = 10
	p.add_theme_stylebox_override("panel", box)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiTheme.label(text, UiTheme.SMALL, color if color.v < 0.6 else UiTheme.INK)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 296
	p.add_child(l)
	p.set_meta("left", secs)
	toasts.add_child(p)
	while toasts.get_child_count() > TOAST_MAX:
		var old := toasts.get_child(0)
		toasts.remove_child(old)
		old.queue_free()

func xp_toast(n: int, src: String) -> void:
	_xp_acc += n
	_xp_src = src if _xp_t < 0.0 or src == _xp_src else ""
	_xp_t = 0.0

func banner(title: String, line: String) -> void:
	_banner_title = title
	_banner_line = line
	_banner_t = 0.0
	banner_box.queue_redraw()

func combat_event(ev: Dictionary) -> void:
	var me := gu.cw.my_id
	match int(ev["kind"]):
		CombatCodec.Ev.DAMAGE:
			if int(ev["src"]) == me:
				hurt_by_me[int(ev["dst"])] = Time.get_ticks_msec()
		CombatCodec.Ev.CONDITION:
			if int(ev["dst"]) == me:
				var n := String(SRD.Condition.find_key(int(ev.get("cond", 0)))).capitalize()
				if bool(ev.get("on", false)):
					conditions[n] = true
				else:
					conditions.erase(n)
				vitals.queue_redraw()

# --- drawing -----------------------------------------------------------------------------------

func _draw_vitals(c: Control) -> void:
	var cw := gu.cw
	var sh: Dictionary = gu.rules.sheet if gu.rules != null else {}
	var r := Rect2(0, 0, 340, 120)
	UiTheme.ink_rect(c, r, UiTheme.PARCHMENT, UiTheme.INK, 3.0)
	# the sigil disc
	var sc := Vector2(48, 56)
	c.draw_circle(sc + Vector2(2, 2), 36, UiTheme.SHADOW)
	c.draw_circle(sc, 36, UiTheme.NIGHT)
	c.draw_arc(sc, 36, 0, TAU, 40, UiTheme.INK, 3.0, true)
	c.draw_arc(sc, 32, 0, TAU, 40, UiTheme.STARLIGHT.darkened(0.4), 1.0, true)
	if gu.items != null:
		SigilLayout.draw_small(c, gu.items.sigil(), sc, 26.0, gu.items.constellation.slots)
	var level := int(sh.get("level", 1))
	var lx := 96.0
	UiTheme.text(c, Vector2(lx, 26), cw.player_name.capitalize(), UiTheme.HEADING, UiTheme.INK, true)
	var lvl_txt := "Lv %d" % level
	UiTheme.text(c, Vector2(r.end.x - 12 - UiTheme.text_width(lvl_txt, UiTheme.HEADING, true), 26), lvl_txt, UiTheme.HEADING, UiTheme.VERMILION.darkened(0.2), true)
	var cls := String(sh.get("class", "")).capitalize()
	var sub := "%s %d" % [cls, int(sh.get("class_level", 1))] if cls != "" else "..."
	if level < LevelTrack.MAX_LEVEL:
		sub += "   next: " + UiCopy.reward_short(LevelTrack.reward(level + 1))
	UiTheme.text(c, Vector2(lx, 44), sub, UiTheme.TINY, UiTheme.INK_SOFT)
	# hit points
	var hp := maxi(cw.hp, 0)
	var mx := maxi(cw.max_hp, 1)
	var hb := Rect2(lx, 52, r.end.x - lx - 12, 22)
	UiTheme.ink_bar(c, hb, float(hp) / mx, UiTheme.VERMILION, UiTheme.BLOOD_DARK.darkened(0.3), _hp_ghost / mx)
	var hp_txt := "%d / %d" % [hp, cw.max_hp] if cw.max_hp > 0 else "-"
	UiTheme.text(c, Vector2(hb.position.x, hb.position.y + 17), hp_txt, UiTheme.BODY, UiTheme.TEXT_LIGHT, false, HORIZONTAL_ALIGNMENT_CENTER, hb.size.x, 4)
	# experience
	var x0 := int(sh.get("xp_level", 0))
	var x1 := int(sh.get("xp_next", 1))
	var xf := clampf(float(int(sh.get("xp", 0)) - x0) / maxf(1.0, x1 - x0), 0.0, 1.0)
	var xb := Rect2(lx, 80, hb.size.x, 9)
	UiTheme.ink_bar(c, xb, xf, UiTheme.GOLD, UiTheme.INK_SOFT)
	if level < LevelTrack.MAX_LEVEL:
		_reward_mark(c, Vector2(xb.end.x, xb.position.y + 4.5), LevelTrack.reward(level + 1))
	# hit dice and spell slots
	var y := 106.0
	UiTheme.text(c, Vector2(lx, y + 5), "HD", UiTheme.TINY, UiTheme.INK_SOFT)
	var hd := int(sh.get("hit_dice", 0))
	var hdm := int(sh.get("hit_dice_max", 0))
	var px := lx + 22
	for i in mini(hdm, 10):
		_die_pip(c, Vector2(px, y), i < hd)
		px += 11
	if hdm > 10:
		UiTheme.text(c, Vector2(px, y + 5), "%d/%d" % [hd, hdm], UiTheme.TINY, UiTheme.INK_SOFT)
		px += 30
	var slots: Array = gu.combat.status.get("slots", sh.get("slots", [])) if gu.combat != null and not gu.combat.status.is_empty() else sh.get("slots", [])
	px += 10
	for l in mini(9, slots.size()):
		var mxs := int(slots[l][1])
		if mxs <= 0:
			continue
		if px > r.end.x - 30:
			break
		UiTheme.text(c, Vector2(px, y + 5), _roman(l + 1), UiTheme.TINY, UiTheme.TEAL.darkened(0.3))
		px += UiTheme.text_width(_roman(l + 1), UiTheme.TINY) + 3
		for k in mxs:
			UiTheme.pip(c, Vector2(px + 3, y), 3.5, UiTheme.TEAL, k < int(slots[l][0]))
			px += 9
		px += 6
	# pending choices badge
	var by := r.end.y + 8
	var pend: Array = sh.get("pending", [])
	if not pend.is_empty():
		var t := "%d choice%s waiting  [U]" % [pend.size(), "" if pend.size() == 1 else "s"]
		var w := UiTheme.text_width(t, UiTheme.SMALL) + 34
		UiTheme.ink_rect(c, Rect2(0, by, w, 24), UiTheme.GOLD, UiTheme.INK, 2.0)
		UiTheme.star(c, Vector2(13, by + 12), 8, 3, UiTheme.PARCHMENT, 4, UiTheme.INK)
		UiTheme.text(c, Vector2(26, by + 18), t, UiTheme.SMALL, UiTheme.INK)
		by += 32
	# conditions and concentration
	var tags: Array = conditions.keys()
	var conc := String(gu.combat.status.get("concentration", "")) if gu.combat != null else ""
	if conc != "":
		tags.append("Concentrating: " + conc.replace("-", " ").capitalize())
	var tx := 0.0
	for t: String in tags:
		var w2 := UiTheme.text_width(t, UiTheme.TINY) + 14
		if tx + w2 > 340:
			tx = 0.0
			by += 24
		UiTheme.ink_rect(c, Rect2(tx, by, w2, 20), UiTheme.PLUM.lightened(0.55) if t.begins_with("Conc") else UiTheme.VERMILION.lightened(0.55), UiTheme.INK, 1.5, false)
		UiTheme.text(c, Vector2(tx + 7, by + 15), t, UiTheme.TINY, UiTheme.INK)
		tx += w2 + 6

static func _roman(n: int) -> String:
	return ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX"][clampi(n, 0, 9)]

func _die_pip(c: Control, p: Vector2, full: bool) -> void:
	var pts := PackedVector2Array([p + Vector2(0, -5), p + Vector2(4.5, -1), p + Vector2(2.8, 4.5), p + Vector2(-2.8, 4.5), p + Vector2(-4.5, -1)])
	if full:
		c.draw_colored_polygon(pts, UiTheme.VERMILION.lightened(0.15))
	pts.append(pts[0])
	c.draw_polyline(pts, UiTheme.INK if full else UiTheme.INK_FADED, 1.3, true)

## The little mark at the end of the XP bar: what the next level gives.
func _reward_mark(c: Control, p: Vector2, rw: int) -> void:
	match rw:
		LevelTrack.Reward.SPARK_SLOT:
			UiTheme.star(c, p, 9, 3.5, UiTheme.STARLIGHT, 4, UiTheme.INK)
		LevelTrack.Reward.VIGOR:
			c.draw_circle(p, 7, UiTheme.VERMILION)
			c.draw_arc(p, 7, 0, TAU, 16, UiTheme.INK, 1.5, true)
			c.draw_line(p - Vector2(4, 0), p + Vector2(4, 0), UiTheme.PARCHMENT, 2)
			c.draw_line(p - Vector2(0, 4), p + Vector2(0, 4), UiTheme.PARCHMENT, 2)
		LevelTrack.Reward.KNACK:
			UiTheme.ink_rect(c, Rect2(p - Vector2(6, 8), Vector2(12, 16)), UiTheme.PARCHMENT, UiTheme.INK, 1.5, false)
			c.draw_line(p + Vector2(-3, -3), p + Vector2(3, -3), UiTheme.INK, 1)
			c.draw_line(p + Vector2(-3, 1), p + Vector2(3, 1), UiTheme.INK, 1)
		_:
			UiTheme.star(c, p, 10, 5, UiTheme.GOLD, 5, UiTheme.INK)

func _draw_clock(c: Control) -> void:
	var r := Rect2(Vector2.ZERO, Vector2(c.size.x, 48))
	UiTheme.ink_rect(c, r, UiTheme.PARCHMENT, UiTheme.INK, 3.0)
	var hours := gu.cw.hours()
	var h := fposmod(hours, 24.0)
	var sun := WorldClock.sun_at(hours)
	# the dial: a window of sky with the sun or moon riding over a hill
	var dial := Rect2(8, 7, 58, 34)
	c.draw_rect(dial, WorldView.sky_color(sun).lerp(UiTheme.NIGHT, 0.2))
	var day := h >= 5.0 and h < 19.5
	var f := (h - 5.0) / 14.5 if day else fposmod(h - 19.5, 24.0) / 9.5
	var body_p := Vector2(dial.position.x + 6 + f * (dial.size.x - 12), dial.end.y - 6 - sin(f * PI) * (dial.size.y - 14))
	if day:
		c.draw_circle(body_p, 7, UiTheme.GOLD)
		c.draw_arc(body_p, 7, 0, TAU, 16, UiTheme.INK, 1.5, true)
	else:
		c.draw_circle(body_p, 6, UiTheme.STARLIGHT)
		c.draw_circle(body_p + Vector2(3, -2), 5, WorldView.sky_color(sun).lerp(UiTheme.NIGHT, 0.2))
	var hill := PackedVector2Array([Vector2(dial.position.x, dial.end.y), Vector2(dial.position.x, dial.end.y - 6),
		Vector2(dial.position.x + 20, dial.end.y - 10), Vector2(dial.position.x + 40, dial.end.y - 5), Vector2(dial.end.x, dial.end.y - 8), dial.end])
	c.draw_colored_polygon(hill, UiTheme.MOSS.darkened(0.3))
	c.draw_rect(dial, UiTheme.INK, false, 2.0)
	UiTheme.text(c, Vector2(76, 31), UiCopy.clock(hours), UiTheme.HEADING, UiTheme.INK, true)
	# coin
	if gu.items != null:
		var cy := 66.0
		var t := "%d" % gu.items.coin()
		var w := UiTheme.text_width(t, UiTheme.BODY)
		var x := c.size.x - w - 8
		UiTheme.text(c, Vector2(x, cy + 6), t, UiTheme.BODY, UiTheme.TEXT_LIGHT, false, HORIZONTAL_ALIGNMENT_LEFT, -1, 4)
		c.draw_circle(Vector2(x - 12, cy), 8, ItemIcons.BRASS)
		c.draw_arc(Vector2(x - 12, cy), 8, 0, TAU, 16, UiTheme.INK, 2.0, true)
		c.draw_arc(Vector2(x - 12, cy), 4.5, 0, TAU, 12, UiTheme.INK_SOFT, 1.0, true)

## Rects of the bar's parts, in bar coordinates.
func hotbar_rect(i: int) -> Rect2:
	return Rect2(3 * 34.0 + 12 + i * (SLOT + GAP), 18, SLOT, SLOT)

func quick_rect(i: int) -> Rect2:
	var x0 := 3 * 34.0 + 12 + 10 * SLOT + 9 * GAP + 16
	return Rect2(x0 + i * (QSLOT + GAP), 18 + (SLOT - QSLOT), QSLOT, QSLOT)

func _draw_bar(c: Control) -> void:
	var cc := gu.combat
	var st: Dictionary = cc.status if cc != null else {}
	# timers: action, bonus, reaction
	var names := ["A", "B", "R"]
	var keys := ["action", "bonus", "reaction"]
	var cols := [UiTheme.VERMILION, UiTheme.GOLD, UiTheme.SKY]
	for i in 3:
		var p := Vector2(16 + i * 34.0, 18 + SLOT * 0.5)
		var left := float(st.get(keys[i], 0.0))
		var mx := _action_max if i == 0 else float(K.ROUND_SECONDS)
		c.draw_circle(p + Vector2(1.5, 1.5), 14, UiTheme.SHADOW)
		c.draw_circle(p, 14, cols[i] if left <= 0.0 else UiTheme.PARCH_SHADE)
		UiTheme.sweep(c, p, 14, clampf(left / mx, 0.0, 1.0), UiTheme.INK_FADED)
		c.draw_arc(p, 14, 0, TAU, 24, UiTheme.INK, 2.0, true)
		UiTheme.text(c, p + Vector2(-14, 6), names[i], UiTheme.SMALL, UiTheme.INK, true, HORIZONTAL_ALIGNMENT_CENTER, 28)
	# the hotbar
	var hb: Array = gu.items.hotbar() if gu.items != null else []
	var sel := gu.items.selected() if gu.items != null else 0
	for i in 10:
		var r := hotbar_rect(i)
		var it: Dictionary = hb[i] if i < hb.size() else {}
		_slot(c, r, it, i == sel)
		UiTheme.text(c, r.position + Vector2(4, 13), str((i + 1) % 10), UiTheme.TINY, UiTheme.INK_SOFT)
	# the selected item's name, briefly, above its slot
	if _sel_name_t > 0.0 and sel < hb.size() and not (hb[sel] as Dictionary).is_empty():
		var nm := ItemGen.name(hb[sel])
		var w := UiTheme.text_width(nm, UiTheme.SMALL) + 16
		var cx := hotbar_rect(sel).get_center().x
		var a := clampf(_sel_name_t / 0.4, 0.0, 1.0)
		var rr := Rect2(clampf(cx - w * 0.5, 0, c.size.x - w), -6, w, 20)
		c.draw_rect(rr, Color(UiTheme.PARCHMENT, a))
		c.draw_rect(rr, Color(UiTheme.INK, a), false, 1.5)
		UiTheme.text(c, rr.position + Vector2(8, 15), nm, UiTheme.SMALL, Color(UiTheme.INK, a))
	# quick spells
	for i in QuickSlots.N:
		var r := quick_rect(i)
		var s := gu.quick_spell(i)
		var why := QuickSlots.why_not(s, st, cc.busy_s if cc != null else 0.0)
		c.draw_rect(Rect2(r.position + Vector2(2, 2), r.size), UiTheme.SHADOW)
		c.draw_rect(r, UiTheme.NIGHT if not s.is_empty() else UiTheme.PARCH_SHADE)
		if not s.is_empty():
			var f := int(s["flags"])
			var col := UiTheme.MOSS if f & CombatCodec.SPELL_HEAL else (UiTheme.VERMILION if f & CombatCodec.SPELL_DAMAGE else UiTheme.TEAL)
			if why != "" and why != "busy" and not why.ends_with("spent"):
				col = col.lerp(UiTheme.INK_SOFT, 0.7)
			c.draw_circle(r.get_center() + Vector2(0, -3), 13, col)
			c.draw_arc(r.get_center() + Vector2(0, -3), 13, 0, TAU, 20, UiTheme.STARLIGHT, 1.5, true)
			UiTheme.text(c, Vector2(r.position.x, r.get_center().y + 2), _abbrev(String(s["name"])), UiTheme.TINY, UiTheme.TEXT_LIGHT, false, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 3)
			var lvl := int(s["level"])
			if lvl > 0:
				UiTheme.text(c, r.end - Vector2(12, 3), str(lvl), UiTheme.TINY, UiTheme.STARLIGHT)
			var t := QuickSlots.timer_for(s, st)
			var mx := _action_max if f & (CombatCodec.SPELL_BONUS | CombatCodec.SPELL_REACTION) == 0 else float(K.ROUND_SECONDS)
			UiTheme.sweep(c, r.get_center(), r.size.x * 0.7, clampf(t / mx, 0.0, 1.0), Color(0, 0, 0, 0.5))
		c.draw_rect(r, UiTheme.INK, false, 2.0)
		UiTheme.ink_rect(c, Rect2(r.position + Vector2(-4, -8), Vector2(16, 16)), UiTheme.PARCHMENT, UiTheme.INK, 1.5, false)
		UiTheme.text(c, r.position + Vector2(-4, 5), QuickSlots.KEYS[i], UiTheme.TINY, UiTheme.INK, true, HORIZONTAL_ALIGNMENT_CENTER, 16)

static func _abbrev(n: String) -> String:
	var words := n.split(" ", false)
	if words.size() >= 2:
		return (words[0].substr(0, 1) + words[1].substr(0, 1)).to_upper()
	return n.substr(0, 3)

## One inventory-style slot with its item (shared look with the inventory screen).
static func draw_slot(c: CanvasItem, r: Rect2, it: Dictionary, selected := false, hover := false) -> void:
	if selected:
		c.draw_rect(Rect2(r.position + Vector2(3, 3), r.size), UiTheme.SHADOW)
	var bg := UiTheme.PARCHMENT if selected else (UiTheme.PARCH_SHADE.lightened(0.1) if hover else UiTheme.PARCH_SHADE)
	c.draw_rect(r, bg)
	if not it.is_empty():
		var rc := ItemIcons.rarity_color(it)
		if ItemIcons.rarity(it) != "":
			c.draw_rect(r.grow(-3), Color(rc, 0.22))
		c.draw_texture_rect(ItemIcons.texture(it), r.grow(-4), false)
		var n := Items.count(it)
		if n > 1:
			var t := str(n) if n < 10000 else "%dk" % (n / 1000)
			UiTheme.text(c, Vector2(r.position.x, r.end.y - 3), t, UiTheme.SMALL, UiTheme.TEXT_LIGHT, false, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 3, 4)
		if Items.needs_bond(it) and not bool(it.get("bonded", false)):
			UiTheme.star(c, r.position + Vector2(r.size.x - 7, 8), 5, 2, UiTheme.PLUM, 4, UiTheme.INK)
	c.draw_rect(r, UiTheme.GOLD.darkened(0.2) if selected else UiTheme.INK_SOFT, false, 3.0 if selected else 2.0)
	if selected:
		c.draw_rect(r.grow(2), UiTheme.INK, false, 1.5)

func _slot(c: Control, r: Rect2, it: Dictionary, selected: bool) -> void:
	Hud.draw_slot(c, r, it, selected)

func _bar_input(event: InputEvent) -> void:
	if gu.items == null:
		return
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			gu.items.select_hotbar(InputLogic.next_hotbar(gu.items.selected(), -1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1))
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			for i in 10:
				if hotbar_rect(i).has_point(mb.position):
					gu.items.select_hotbar(i)
			for i in QuickSlots.N:
				if quick_rect(i).has_point(mb.position):
					gu.open("spells")
			accept_event()

func _draw_prompt(c: Control) -> void:
	if prompt.is_empty():
		return
	var t := String(prompt.get("text", ""))
	var s := String(prompt.get("sub", ""))
	var w := maxf(UiTheme.text_width(t, UiTheme.BODY), UiTheme.text_width(s, UiTheme.SMALL)) + 34
	var prog := float(prompt.get("progress", -1.0))
	if prog >= 0.0:
		w += 40
	var h := 50.0 if s != "" else 34.0
	var r := Rect2((c.size.x - w) * 0.5, c.size.y - h, w, h)
	UiTheme.ink_rect(c, r, UiTheme.PARCHMENT, prompt.get("color", UiTheme.INK), 2.5)
	var tx := r.position.x + 14
	if prog >= 0.0:
		var p := Vector2(tx + 14, r.get_center().y)
		c.draw_circle(p, 13, UiTheme.PARCH_SHADE)
		c.draw_arc(p, 11, -PI * 0.5, -PI * 0.5 + TAU * clampf(prog, 0.0, 1.0), 32, UiTheme.MOSS.darkened(0.1), 5.0, true)
		c.draw_arc(p, 13, 0, TAU, 24, UiTheme.INK, 1.5, true)
		tx += 38
	UiTheme.text(c, Vector2(tx, r.position.y + 23), t, UiTheme.BODY, UiTheme.INK)
	if s != "":
		UiTheme.text(c, Vector2(tx, r.position.y + 41), s, UiTheme.SMALL, UiTheme.INK_SOFT)

func _draw_banner(c: Control) -> void:
	if _banner_t < 0.0:
		return
	var a := clampf(_banner_t / 0.25, 0.0, 1.0) * clampf((4.5 - _banner_t) / 0.6, 0.0, 1.0)
	var drop := (1.0 - clampf(_banner_t / 0.25, 0.0, 1.0)) * -30.0
	c.modulate.a = a
	var r := Rect2(0, drop, c.size.x, 92)
	# a ribbon: parchment with notched ends
	var notch := 22.0
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), Vector2(r.end.x - notch, r.get_center().y),
		Vector2(r.end.x, r.end.y), Vector2(r.position.x, r.end.y), Vector2(r.position.x + notch, r.get_center().y)])
	var sh := PackedVector2Array()
	for p in pts:
		sh.append(p + Vector2(4, 4))
	c.draw_colored_polygon(sh, UiTheme.SHADOW)
	c.draw_colored_polygon(pts, UiTheme.PARCHMENT)
	var outline := pts.duplicate()
	outline.append(pts[0])
	c.draw_polyline(outline, UiTheme.INK, 3.0, true)
	UiTheme.star(c, Vector2(r.position.x + 56, r.get_center().y), 16, 6, UiTheme.GOLD, 4, UiTheme.INK, _banner_t)
	UiTheme.star(c, Vector2(r.end.x - 56, r.get_center().y), 16, 6, UiTheme.GOLD, 4, UiTheme.INK, -_banner_t)
	UiTheme.text(c, Vector2(0, r.position.y + 46), _banner_title, UiTheme.TITLE + 8, UiTheme.VERMILION.darkened(0.15), true, HORIZONTAL_ALIGNMENT_CENTER, c.size.x)
	UiTheme.text(c, Vector2(0, r.position.y + 74), _banner_line, UiTheme.BODY, UiTheme.INK, false, HORIZONTAL_ALIGNMENT_CENTER, c.size.x)

## The clock jumped `hours` forward (everyone slept, or a debug key): fade through the night.
func night(hours: float) -> void:
	_night_t = 0.0
	_night_h = hours

func _draw_downed(c: Control) -> void:
	if _night_t >= 0.0:
		var a := clampf(minf(_night_t / 0.5, (3.2 - _night_t) / 0.8), 0.0, 1.0)
		c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(UiTheme.NIGHT_DEEP, 0.85 * a))
		for i in 40:
			var hsh := hash(i * 7919)
			var p := Vector2(float(hsh & 0xfff) / 4095.0 * c.size.x, float((hsh >> 12) & 0xfff) / 4095.0 * c.size.y * 0.7)
			UiTheme.star(c, p, 3.0 + (hsh % 3), 1.0, Color(UiTheme.STARLIGHT, a * 0.8), 4, Color(0, 0, 0, 0))
		UiTheme.text(c, Vector2(0, c.size.y * 0.45), "The night passes...", UiTheme.TITLE + 6, Color(UiTheme.STARLIGHT, a), true, HORIZONTAL_ALIGNMENT_CENTER, c.size.x)
		UiTheme.text(c, Vector2(0, c.size.y * 0.45 + 36), "%d hours, give or take a dream." % roundi(_night_h), UiTheme.BODY, Color(UiTheme.STARLIGHT.darkened(0.2), a), false, HORIZONTAL_ALIGNMENT_CENTER, c.size.x)
	if downed.is_empty():
		return
	var s := c.size
	var dead := bool(downed.get("dead", false))
	# a dark ink vignette
	for i in 6:
		var k := float(i) / 6.0
		var m := 60.0 * (1.0 - k) + 4.0
		c.draw_rect(Rect2(0, 0, s.x, m), Color(UiTheme.BLOOD_DARK.darkened(0.6), 0.12))
		c.draw_rect(Rect2(0, s.y - m, s.x, m), Color(UiTheme.BLOOD_DARK.darkened(0.6), 0.12))
		c.draw_rect(Rect2(0, 0, m * 1.4, s.y), Color(UiTheme.BLOOD_DARK.darkened(0.6), 0.12))
		c.draw_rect(Rect2(s.x - m * 1.4, 0, m * 1.4, s.y), Color(UiTheme.BLOOD_DARK.darkened(0.6), 0.12))
	var w := 420.0
	var r := Rect2((s.x - w) * 0.5, s.y * 0.30, w, 132)
	UiTheme.ink_rect(c, r, UiTheme.PARCHMENT, UiTheme.INK, 3.0)
	UiTheme.text(c, Vector2(r.position.x, r.position.y + 38), String(downed.get("title", "")), UiTheme.TITLE, UiTheme.BLOOD_DARK, true, HORIZONTAL_ALIGNMENT_CENTER, w)
	UiTheme.text(c, Vector2(r.position.x, r.position.y + 62), String(downed.get("line", "")), UiTheme.SMALL, UiTheme.INK_SOFT, false, HORIZONTAL_ALIGNMENT_CENTER, w)
	if not dead:
		var succ := int(downed.get("successes", 0))
		var fail := int(downed.get("failures", 0))
		var y := r.position.y + 90
		UiTheme.text(c, Vector2(r.position.x + 40, y + 5), "saved", UiTheme.SMALL, UiTheme.MOSS.darkened(0.3))
		for i in 3:
			UiTheme.pip(c, Vector2(r.position.x + 100 + i * 20, y), 7, UiTheme.MOSS, i < succ)
		UiTheme.text(c, Vector2(r.position.x + 230, y + 5), "failed", UiTheme.SMALL, UiTheme.BLOOD_DARK)
		for i in 3:
			UiTheme.pip(c, Vector2(r.position.x + 292 + i * 20, y), 7, UiTheme.VERMILION, i < fail)
		var next := float(downed.get("next", -1.0))
		if next >= 0.0:
			UiTheme.ink_bar(c, Rect2(r.position.x + 40, y + 18, w - 80, 7), 1.0 - clampf(next / 4.0, 0.0, 1.0), UiTheme.INK_SOFT, UiTheme.PARCH_SHADE)
	else:
		UiTheme.text(c, Vector2(r.position.x, r.position.y + 100), String(downed.get("sub", "")), UiTheme.BODY, UiTheme.INK, false, HORIZONTAL_ALIGNMENT_CENTER, w)
