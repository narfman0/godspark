## Trading with a shop or a smith (opens when the conversation's shop opens; Esc goes back to
## the talk). Left: their goods with stock and the price YOU pay (DealsClient.shop listings,
## modifiers applied by the host). Right: your pack, what they would pay for each thing.
## Click buys or sells the amount set by the nudge (- n +); Shift-click the whole stack.
## Under the goods: why prices are what they are (plenty, scarcity, your standing, your Bond,
## patronage), the town's purse (a poor town pays little), and why the shelves are thin when
## they are. A smith's rack shows full item tooltips compared with what you wear. Services (a
## bed, healing) are plain buttons. Every action is a DealsClient request.
class_name ShopScreen
extends UiScreen

const ROW_H := 50.0
const COL_W := 500.0

var dc: DealsClient
var goods_box: VBoxContainer
var pack_box: VBoxContainer
var goods_title: Label
var pack_title: Label
var mood_l: Label
var purse_l: Label
var thin_l: Label
var qty_l: Label
var services: HBoxContainer
var tip: TooltipPanel
var qty := 1
var _hover_item := {}

func _init() -> void:
	title = "Trade"
	hint = "Click: buy or sell the amount set below   Shift-click: the whole stack   Hover: look closer   Esc: back to the talk"
	panel_size = Vector2(1120, 600)

func build() -> void:
	dc = gu.cw.system(HostSystem.DEALS) as DealsClient if gu.cw != null else null
	goods_title = UiTheme.label("Their goods", UiTheme.HEADING, UiTheme.INK, true)
	goods_title.position = Vector2(26, 62)
	panel.add_child(goods_title)
	pack_title = UiTheme.label("Your pack", UiTheme.HEADING, UiTheme.INK, true)
	pack_title.position = Vector2(26 + COL_W + 50, 62)
	panel.add_child(pack_title)
	goods_box = _column(Vector2(24, 96))
	pack_box = _column(Vector2(24 + COL_W + 48, 96))
	var y := 96.0 + 300.0 + 8.0
	mood_l = _line(Vector2(26, y), COL_W, UiTheme.SMALL, UiTheme.INK)
	thin_l = _line(Vector2(26, y + 44), COL_W, UiTheme.SMALL, UiTheme.BLOOD_DARK)
	purse_l = _line(Vector2(26 + COL_W + 50, y), COL_W, UiTheme.SMALL, UiTheme.INK)
	var nudge := HBoxContainer.new()
	nudge.position = Vector2(26 + COL_W + 50, y + 46)
	nudge.add_child(UiTheme.label("Amount per click:", UiTheme.SMALL, UiTheme.INK_SOFT))
	var minus := UiTheme.button("-", UiTheme.BODY)
	minus.custom_minimum_size = Vector2(30, 0)
	minus.pressed.connect(func() -> void: _nudge(-1))
	nudge.add_child(minus)
	qty_l = UiTheme.label("1", UiTheme.HEADING, UiTheme.INK, true)
	qty_l.custom_minimum_size = Vector2(40, 0)
	qty_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nudge.add_child(qty_l)
	var plus := UiTheme.button("+", UiTheme.BODY)
	plus.custom_minimum_size = Vector2(30, 0)
	plus.pressed.connect(func() -> void: _nudge(1))
	nudge.add_child(plus)
	for n: int in [5, 10]:
		var b := UiTheme.button("x%d" % n, UiTheme.SMALL)
		b.pressed.connect(func() -> void: _set_qty(n))
		nudge.add_child(b)
	panel.add_child(nudge)
	services = HBoxContainer.new()
	services.position = Vector2(26, panel_size.y - 70)
	panel.add_child(services)
	tip = TooltipPanel.new()
	add_child(tip)

func _column(at: Vector2) -> VBoxContainer:
	var bg := Panel.new()
	bg.position = at
	bg.size = Vector2(COL_W, 300)
	bg.add_theme_stylebox_override("panel", UiTheme.slot_box(UiTheme.PARCH_SHADE.lightened(0.15), UiTheme.INK_SOFT, 2))
	bg.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(bg)
	var sc := ScrollContainer.new()
	sc.position = at + Vector2(4, 4)
	sc.size = Vector2(COL_W - 8, 292)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(sc)
	var v := VBoxContainer.new()
	v.custom_minimum_size.x = COL_W - 22
	v.add_theme_constant_override("separation", 3)
	sc.add_child(v)
	return v

func _line(at: Vector2, w: float, sz: int, col: Color) -> Label:
	var l := UiTheme.label("", sz, col)
	l.position = at
	l.size = Vector2(w, 40)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(l)
	return l

func attach() -> void:
	dc = gu.cw.system(HostSystem.DEALS) as DealsClient
	if dc == null:
		return
	dc.shop_changed.connect(func(_s: Dictionary) -> void: refresh())
	dc.talk_changed.connect(func(_c: Dictionary) -> void: refresh())
	if gu.items != null:
		gu.items.inventory_changed.connect(func(_i: Array) -> void: refresh())

func closed() -> void:
	tip.hide_tip()
	if gu.deals_ui != null:
		gu.deals_ui.dialogue.refresh()

## Coin changes float off the pack's purse while trading (the HUD's purse is under the screen).
func _process(_dt: float) -> void:
	if visible and gu != null and gu.hud != null and not gu.hud._coin_fx.is_empty():
		pack_title.text = "Your pack  (%d coin)" % (gu.items.coin() if gu.items != null else 0)
		panel.queue_redraw()

func _draw_frame() -> void:
	super._draw_frame()
	if gu == null or gu.hud == null:
		return
	var k := 0
	for cf: Dictionary in gu.hud._coin_fx:
		var ft := float(cf["t"])
		var d := int(cf["d"])
		var a := clampf((1.6 - ft) / 0.5, 0.0, 1.0)
		var txt := ("+%d coin" % d) if d > 0 else ("%d coin" % d)
		var x := pack_title.position.x + UiTheme.text_width(pack_title.text, UiTheme.HEADING, true) + 16
		UiTheme.text(panel, Vector2(x, pack_title.position.y + 22 - ft * 14 - k * 20), txt, UiTheme.HEADING,
			Color(UiTheme.GOLD.darkened(0.25) if d > 0 else UiTheme.VERMILION, a), false)
		k += 1

func _nudge(d: int) -> void:
	_set_qty(qty + d)

func _set_qty(n: int) -> void:
	qty = clampi(n, 1, 99)
	if qty_l != null:
		qty_l.text = str(qty)

func refresh() -> void:
	if not visible or dc == null:
		return
	var s := dc.shop
	if s.is_empty():
		return
	var smith := String(s.get("kind", "")) == "smith"
	var town := String(s.get("town", ""))
	title = ("The smith's rack, %s" if smith else "The shelves of %s") % town
	panel.queue_redraw()
	var site: Dictionary = dc.sites.get(int(s.get("site", -1)), {})
	var fac := String(site.get("faction", dc.conversation.get("faction", "")))
	var lc := gu.cw.system(HostSystem.LIFE) as LifeClient
	var standing := lc.standing(fac) if lc != null else 0
	var bonds: Dictionary = gu.rules.sheet.get("bonds", {}) if gu.rules != null else {}
	var bonded := int(bonds.get("people:" + String(site.get("culture", "")), 0)) >= 1
	var pt := int(dc.patrons.get(fac, {}).get("tier", 0)) if not bool(dc.patrons.get(fac, {}).get("suspended", false)) else 0
	var mods := DealsLogic.price_mods(standing, bonded, pt)
	var ls: Array = s.get("listings", [])
	goods_title.text = "%s  (%d)" % ["On the rack" if smith else "Their goods", ls.size()]
	_clear(goods_box)
	if ls.is_empty():
		goods_box.add_child(_empty_note("Sold out. Come back another day." if not smith else "Nothing on the rack today."))
	for l: Dictionary in ls:
		goods_box.add_child(_row(l["item"], int(l["n"]), int(l["price"]), true, String(l["id"]), -1))
	_clear(pack_box)
	var sells: Dictionary = s.get("sell", {})
	var keys: Array = sells.keys()
	keys.sort()
	for slot: int in keys:
		var it := gu.items.item(slot) if gu.items != null else {}
		if it.is_empty():
			continue
		pack_box.add_child(_row(it, Items.count(it), int(sells[slot]), false, "", slot))
	if keys.is_empty():
		pack_box.add_child(_empty_note("Nothing they want. Ore, goods and gear sell; rubble does not."))
	pack_title.text = "Your pack  (%d coin)" % (gu.items.coin() if gu.items != null else 0)
	mood_l.text = DealsLogic.price_mood(ls, mods, "smith" if smith else "store")
	thin_l.text = DealsLogic.thin_line(ls, site, "smith" if smith else "store")
	purse_l.text = DealsLogic.purse_line(int(s.get("wealth", 0)), int(site.get("pop", 0)))
	_services()

func _services() -> void:
	_clear(services)
	var back := UiTheme.button("Back to the talk", UiTheme.SMALL)
	back.pressed.connect(func() -> void: gu.close("shop"))
	services.add_child(back)
	for o: Dictionary in dc.conversation.get("options", []):
		var id := String(o["id"])
		if id == "bed" or id == "heal":
			var b := UiTheme.button(String(o["label"]), UiTheme.SMALL)
			b.pressed.connect(func() -> void: dc.service(id))
			services.add_child(b)

func _clear(c: Control) -> void:
	for ch in c.get_children():
		c.remove_child(ch)
		ch.queue_free()

func _empty_note(t: String) -> Label:
	var l := UiTheme.label(t, UiTheme.SMALL, UiTheme.INK_SOFT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(COL_W - 40, 40)
	return l

## A row: icon, name, how many, the price each; click to trade.
func _row(it: Dictionary, n: int, price: int, buying: bool, lid: String, slot: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(COL_W - 24, ROW_H)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var coin := gu.items.coin() if gu.items != null else 0
	var afford := not buying or coin >= price
	c.draw.connect(func() -> void:
		var r := Rect2(Vector2.ZERO, c.size)
		var hov := c.get_global_rect().has_point(c.get_global_mouse_position())
		c.draw_rect(r, UiTheme.PARCHMENT if hov else Color(UiTheme.PARCHMENT, 0.55))
		c.draw_rect(r, UiTheme.INK_SOFT if hov else UiTheme.INK_FADED, false, 1.5)
		Hud.draw_slot(c, Rect2(4, 3, 44, 44), it)
		var nm := ItemGen.name(it)
		UiTheme.text(c, Vector2(58, 22), nm, UiTheme.BODY, ItemIcons.rarity_color(it).darkened(0.35) if ItemIcons.rarity(it) != "" else UiTheme.INK, false,
			HORIZONTAL_ALIGNMENT_LEFT, c.size.x - 200)
		var sub := ("%d in stock" % n) if buying else ("you have %d" % n)
		UiTheme.text(c, Vector2(58, 41), sub, UiTheme.TINY, UiTheme.INK_SOFT)
		var pt := "%d" % price
		var pw := UiTheme.text_width(pt, UiTheme.HEADING)
		var px := c.size.x - 16 - pw
		UiTheme.text(c, Vector2(px, 31), pt, UiTheme.HEADING, UiTheme.INK if afford else UiTheme.BLOOD_DARK)
		c.draw_circle(Vector2(px - 12, 24), 7, ItemIcons.BRASS)
		c.draw_arc(Vector2(px - 12, 24), 7, 0, TAU, 14, UiTheme.INK, 1.5, true)
		UiTheme.text(c, Vector2(px - 70, 44), "each" if buying else "they pay", UiTheme.TINY, UiTheme.INK_SOFT, false, HORIZONTAL_ALIGNMENT_RIGHT, 50))
	c.mouse_entered.connect(func() -> void:
		c.queue_redraw()
		_tip(it, c))
	c.mouse_exited.connect(func() -> void:
		c.queue_redraw()
		tip.hide_tip())
	c.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var all := (ev as InputEventMouseButton).shift_pressed
			var k := n if all else mini(qty, n)
			if buying:
				if all and price > 0:
					k = mini(n, coin / price)
				dc.buy(lid, maxi(1, k))
			else:
				dc.sell(slot, maxi(1, k))
			c.accept_event()
		elif ev is InputEventMouseMotion:
			tip.place(get_local_mouse_position()))
	return c

func _tip(it: Dictionary, c: Control) -> void:
	var ctx := {"class": String(gu.rules.sheet.get("class", "")) if gu.rules != null else ""}
	var sk := Items.slot_kind(it)
	if sk != "" and sk != "ring" and gu.items != null:
		ctx["worn"] = gu.items.equipment.at(sk)
	tip.show_lines(ItemText.lines(it, ctx), get_global_transform().affine_inverse() * (c.get_global_transform() * Vector2(c.size.x, 0)), ItemIcons.rarity_color(it).darkened(0.2))
