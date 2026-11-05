## Inventory and paper doll (Tab or I). Left: the doll, with head, neck, cloak, armour, hands,
## belt and feet on the body, main and off hand at its sides, and ten ring slots in two rows
## of five under the hands. Middle: the hotbar row and the 40-slot bag. Right: crafting, and
## bonding when a campfire is near.
##
## Mouse: click to pick up and click to put down (or drag and let go); shift-click wears a
## piece of gear (or takes it off); right-click drinks, wears or bonds; click outside the
## panel with something held to drop it. Every action is an ItemsClient request; the host
## answers with the mirror and a note (refusals become toasts).
class_name InventoryScreen
extends UiScreen

const S := 46.0
const G := 4.0
const GRID_POS := Vector2(372, 92)
const DOLL_POS := Vector2(24, 70)
const DOLL_SIZE := Vector2(330, 450)
const DOLL_SLOTS := ["head", "neck", "cloak", "armor", "hands", "belt", "feet", "main_hand", "off_hand"]
const SLOT_LABELS := {"head": "Head", "neck": "Neck", "cloak": "Cloak", "armor": "Armour", "hands": "Hands", "belt": "Belt",
	"feet": "Feet", "main_hand": "Main", "off_hand": "Off"}

var grid: Control
var doll: Control
var side: VBoxContainer
var tip: TooltipPanel
var craft_box: VBoxContainer
var bond_label: Label
## Index on the cursor (-1: none), and where a drag started.
var held := -1
var _press_at := -1
var _press_pos := Vector2.ZERO
var _hover := -1
var _bonding := {}

func _init() -> void:
	title = "Pack and person"
	hint = "Click: pick up / put down   Shift-click: wear or take off   Right-click: use, wear or bond   Click outside: drop"
	panel_size = Vector2(1120, 580)

func build() -> void:
	doll = Control.new()
	doll.position = DOLL_POS
	doll.size = DOLL_SIZE
	doll.mouse_filter = Control.MOUSE_FILTER_STOP
	doll.draw.connect(_draw_doll)
	doll.gui_input.connect(_slot_input.bind(doll))
	doll.mouse_exited.connect(_unhover)
	panel.add_child(doll)
	grid = Control.new()
	grid.position = GRID_POS
	grid.size = Vector2(10 * (S + G), 6 * (S + G) + 40)
	grid.mouse_filter = Control.MOUSE_FILTER_STOP
	grid.draw.connect(_draw_grid)
	grid.gui_input.connect(_slot_input.bind(grid))
	grid.mouse_exited.connect(_unhover)
	panel.add_child(grid)
	side = VBoxContainer.new()
	side.position = Vector2(GRID_POS.x + grid.size.x + 22, 70)
	side.size = Vector2(panel_size.x - side.position.x - 22, 440)
	panel.add_child(side)
	side.add_child(UiTheme.label("Make", UiTheme.HEADING, UiTheme.INK, true))
	craft_box = VBoxContainer.new()
	side.add_child(craft_box)
	var gap := Control.new()
	gap.custom_minimum_size.y = 14
	side.add_child(gap)
	side.add_child(UiTheme.label("Bond", UiTheme.HEADING, UiTheme.INK, true))
	bond_label = UiTheme.label("", UiTheme.SMALL, UiTheme.INK_SOFT)
	bond_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bond_label.custom_minimum_size.x = side.size.x
	side.add_child(bond_label)
	tip = TooltipPanel.new()
	add_child(tip)

func attach() -> void:
	if gu.items == null:
		return
	gu.items.inventory_changed.connect(func(_i: Array) -> void: refresh())
	gu.items.equipment_changed.connect(func(_s: Array) -> void: refresh())
	gu.items.bonding.connect(func(i: int, ms: int) -> void:
		_bonding = {} if ms <= 0 else {"index": i, "ms": ms, "t0": Time.get_ticks_msec()}
		refresh())

func refresh() -> void:
	if not visible or gu.items == null:
		return
	grid.queue_redraw()
	doll.queue_redraw()
	_fill_crafts()
	var near := Nearby.has(gu.cw, Nearby.CAMPFIRE)
	var waiting := 0
	for i in Inventory.SIZE + Equipment.SLOTS.size():
		var it := gu.items.item(i)
		if not it.is_empty() and Items.needs_bond(it) and not bool(it.get("bonded", false)):
			waiting += 1
	var t := "A campfire is close: right-click an unbonded treasure to bond it." if near else "Bonding needs a campfire close by."
	if waiting > 0:
		t += "  %d treasure%s waiting (marked with a star)." % [waiting, "" if waiting == 1 else "s"]
	if not _bonding.is_empty():
		t = "Bonding %s... stay by the fire." % ItemGen.name(gu.items.item(int(_bonding["index"])))
	bond_label.text = t

func closed() -> void:
	held = -1
	tip.hide_tip()

func _fill_crafts() -> void:
	for c in craft_box.get_children():
		c.queue_free()
	var rec := Items.recipes()
	for id: String in rec:
		var r: Dictionary = rec[id]
		var ins: Dictionary = r.get("in", {})
		var ok := true
		var need := PackedStringArray()
		for b: String in ins:
			var have := gu.items.inventory.count_base(b)
			if have < int(ins[b]):
				ok = false
			need.append("%d %s" % [int(ins[b]), String(Items.row(b).get("name", b)).to_lower()])
		var out: Dictionary = r.get("out", {})
		var btn := UiTheme.button("%s x%d   (%s)" % [String(Items.row(String(out.get("base", ""))).get("name", id)), int(out.get("count", 1)), ", ".join(need)], UiTheme.SMALL)
		btn.disabled = not ok
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.icon = ItemIcons.texture(out)
		btn.expand_icon = false
		btn.add_theme_constant_override("icon_max_width", 24)
		btn.pressed.connect(func() -> void: gu.items.craft(id))
		craft_box.add_child(btn)

# --- geometry ------------------------------------------------------------------------------

## Grid slot rects (grid coordinates): 0-9 hotbar on top, then 4 rows of the bag.
static func grid_rect(i: int) -> Rect2:
	if i < Inventory.HOTBAR:
		return Rect2(i * (S + G), 22, S, S)
	var j := i - Inventory.HOTBAR
	return Rect2((j % 10) * (S + G), 22 + S + 30 + (j / 10) * (S + G), S, S)

## Paper doll slot rects (doll coordinates), by Equipment slot name.
static func doll_rects() -> Dictionary:
	var cx := DOLL_SIZE.x * 0.5
	var r := {}
	r["head"] = Rect2(cx - S * 0.5, 8, S, S)
	r["neck"] = Rect2(cx + 34, 30, S, S)
	r["cloak"] = Rect2(cx - 34 - S, 30, S, S)
	r["armor"] = Rect2(cx - S * 0.5, 90, S, S)
	r["hands"] = Rect2(cx + 50, 120, S, S)
	r["belt"] = Rect2(cx - S * 0.5, 150, S, S)
	r["feet"] = Rect2(cx - S * 0.5, 232, S, S)
	r["main_hand"] = Rect2(14, 150, S, S)
	r["off_hand"] = Rect2(DOLL_SIZE.x - 14 - S, 150, S, S)
	var rs := 36.0
	for k in 10:
		var kk := k % 5
		var x := 14.0 + (kk % 2) * (rs + 4)
		if k >= 5:
			x = DOLL_SIZE.x - 14.0 - rs - (kk % 2) * (rs + 4)
		r["ring_%d" % (k + 1)] = Rect2(x, 214 + (kk / 2) * (rs + 4), rs, rs)
	return r

func _index_at(c: Control, p: Vector2) -> int:
	if c == grid:
		for i in Inventory.SIZE:
			if grid_rect(i).has_point(p):
				return i
	else:
		var rs := doll_rects()
		for s: String in rs:
			if (rs[s] as Rect2).has_point(p):
				return Equipment.index_of(s)
	return -1

# --- input -----------------------------------------------------------------------------------

func _slot_input(event: InputEvent, c: Control) -> void:
	var items := gu.items
	if items == null:
		return
	if event is InputEventMouseMotion:
		var i := _index_at(c, (event as InputEventMouseMotion).position)
		if i != _hover:
			_hover = i
			grid.queue_redraw()
			doll.queue_redraw()
		_update_tip(i, c.position + panel.position + (event as InputEventMouseMotion).position)
		if held >= 0:
			grid.queue_redraw()
			doll.queue_redraw()
		return
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	var i := _index_at(c, mb.position)
	if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		if i < 0:
			return
		if mb.shift_pressed:
			quick_equip(i)
		elif held < 0:
			if not items.item(i).is_empty():
				held = i
				_press_at = i
				_press_pos = mb.global_position
		else:
			put_down(i)
		refresh()
	elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
		# a drag: let go over another slot
		if held >= 0 and held == _press_at and i >= 0 and i != held and mb.global_position.distance_to(_press_pos) > 6.0:
			put_down(i)
			refresh()
		_press_at = -1
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and i >= 0:
		use_or_bond(i)

## What a click does with the held item over slot i (the decision, for tests too).
static func click_plan(held_index: int, target: int, target_empty: bool) -> String:
	if held_index < 0:
		return "pick" if not target_empty else "none"
	if target == held_index:
		return "cancel"
	return "move"

func put_down(i: int) -> void:
	match click_plan(held, i, gu.items.item(i).is_empty()):
		"move":
			gu.items.move(held, i)
	held = -1

func quick_equip(i: int) -> void:
	var it := gu.items.item(i)
	if it.is_empty():
		return
	if i >= Equipment.FIRST:
		gu.items.unequip(i)
	elif Items.slot_kind(it) != "":
		gu.items.use(i)
	held = -1

func use_or_bond(i: int) -> void:
	var it := gu.items.item(i)
	if it.is_empty():
		return
	if Items.needs_bond(it) and not bool(it.get("bonded", false)):
		gu.items.bond(i)
	elif i < Inventory.SIZE and (not Items.use_of(it).is_empty() or Items.slot_kind(it) != ""):
		gu.items.use(i)
	elif i >= Equipment.FIRST:
		gu.items.unequip(i)

## A click outside the panel (GameUi's catcher): drop what is held.
func click_outside(event: InputEventMouseButton) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if panel.get_global_rect().has_point(event.global_position):
		return
	if held >= 0:
		var it := gu.items.item(held)
		gu.items.drop(held, maxi(1, Items.count(it)))
		gu.toast("Dropped %s." % ItemGen.name(it), 2.0)
		held = -1
		refresh()
	else:
		gu.close(String(name))

func _unhover() -> void:
	_hover = -1
	tip.hide_tip()
	grid.queue_redraw()
	doll.queue_redraw()

func _update_tip(i: int, at: Vector2) -> void:
	if i < 0 or gu.items.item(i).is_empty() or held >= 0:
		tip.hide_tip()
		return
	var it := gu.items.item(i)
	var ctx := {"class": String(gu.rules.sheet.get("class", "")) if gu.rules != null else ""}
	if i < Inventory.SIZE:
		var sk := Items.slot_kind(it)
		if sk != "" and sk != "ring":
			ctx["worn"] = gu.items.equipment.at(sk)
	tip.show_lines(ItemText.lines(it, ctx), at, ItemIcons.rarity_color(it).darkened(0.2))

# --- drawing ----------------------------------------------------------------------------------

func _draw_grid() -> void:
	var items := gu.items
	if items == null:
		return
	UiTheme.text(grid, Vector2(0, 16), "Hotbar  (1-0)", UiTheme.SMALL, UiTheme.INK_SOFT, true)
	UiTheme.text(grid, Vector2(0, 22 + S + 24), "Pack", UiTheme.SMALL, UiTheme.INK_SOFT, true)
	var coin := "%d gp" % items.coin()
	UiTheme.text(grid, Vector2(grid.size.x - UiTheme.text_width(coin, UiTheme.BODY) - 6, 22 + S + 24), coin, UiTheme.BODY, UiTheme.GOLD.darkened(0.45))
	for i in Inventory.SIZE:
		var r := grid_rect(i)
		var it := items.item(i) if i != held else {}
		Hud.draw_slot(grid, r, it, i == items.selected() and i < Inventory.HOTBAR, i == _hover)
		if i == held:
			grid.draw_rect(r.grow(-2), Color(UiTheme.INK, 0.15))
		if not _bonding.is_empty() and int(_bonding["index"]) == i:
			_bond_ring(grid, r)
	_draw_held(grid)

func _bond_ring(c: Control, r: Rect2) -> void:
	var left := float(_bonding["ms"]) - (Time.get_ticks_msec() - int(_bonding["t0"]))
	var f := 1.0 - clampf(left / maxf(1.0, float(_bonding["ms"])), 0.0, 1.0)
	c.draw_arc(r.get_center(), r.size.x * 0.45, -PI * 0.5, -PI * 0.5 + TAU * f, 24, UiTheme.PLUM, 4.0, true)
	c.queue_redraw()

func _draw_held(c: Control) -> void:
	if held < 0 or not c.get_global_rect().has_point(c.get_global_mouse_position()):
		return
	var it := gu.items.item(held)
	var p := c.get_local_mouse_position()
	c.draw_texture_rect(ItemIcons.texture(it), Rect2(p - Vector2(20, 20), Vector2(40, 40)), false, Color(1, 1, 1, 0.9))

func _draw_doll() -> void:
	var items := gu.items
	if items == null:
		return
	var cx := DOLL_SIZE.x * 0.5
	# the figure: an inked silhouette with outstretched hands
	var ink := Color(UiTheme.INK, 0.55)
	var fill := Color(UiTheme.PARCH_DEEP, 0.35)
	doll.draw_circle(Vector2(cx, 54), 26, fill)
	doll.draw_arc(Vector2(cx, 54), 26, 0, TAU, 32, ink, 2.0, true)
	var torso := PackedVector2Array([Vector2(cx - 44, 92), Vector2(cx + 44, 92), Vector2(cx + 34, 200), Vector2(cx - 34, 200)])
	doll.draw_colored_polygon(torso, fill)
	torso.append(torso[0])
	doll.draw_polyline(torso, ink, 2.0, true)
	doll.draw_line(Vector2(cx - 44, 96), Vector2(60, 172), ink, 6.0, true)
	doll.draw_line(Vector2(cx + 44, 96), Vector2(DOLL_SIZE.x - 60, 172), ink, 6.0, true)
	doll.draw_line(Vector2(cx - 20, 200), Vector2(cx - 26, 262), ink, 7.0, true)
	doll.draw_line(Vector2(cx + 20, 200), Vector2(cx + 26, 262), ink, 7.0, true)
	UiTheme.text(doll, Vector2(0, 300), "ten fingers, ten rings", UiTheme.TINY, UiTheme.INK_SOFT, false, HORIZONTAL_ALIGNMENT_CENTER, DOLL_SIZE.x)
	var rs := doll_rects()
	for s: String in rs:
		var r: Rect2 = rs[s]
		var idx := Equipment.index_of(s)
		var it := items.item(idx) if idx != held else {}
		Hud.draw_slot(doll, r, it, false, idx == _hover)
		if it.is_empty():
			var lab := String(SLOT_LABELS.get(s, "Ring"))
			UiTheme.text(doll, Vector2(r.position.x, r.get_center().y + 5), lab, UiTheme.TINY if not s.begins_with("ring") else 11, Color(UiTheme.INK, 0.4), false, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		if not _bonding.is_empty() and int(_bonding["index"]) == idx:
			_bond_ring(doll, r)
	# what the gear adds up to
	var y := 350.0
	var tags := ItemText.tag_words(items.equipment.tags())
	var hit := 0
	var ac := 0
	for it2: Dictionary in items.equipment.worn.values():
		var b := Items.budget_of(it2)
		hit += b.x
		ac += b.y
	UiTheme.text(doll, Vector2(8, y), "From gear: %+d to hit, %+d AC" % [hit, ac], UiTheme.SMALL, UiTheme.INK)
	for t: String in tags.slice(0, 5):
		y += 18
		UiTheme.text(doll, Vector2(8, y), t, UiTheme.TINY, Color("3d6b1f"))
	_draw_held(doll)
