## The interface root (windowed clients only; ViewPresenter makes it, headless runs never
## load it). A CanvasLayer holding one scaled Control (`root`, sized in a virtual 1280x720 so
## everything scales with the window), the HUD, and a stack of screens. It reads the client
## systems (rules, items, combat; monsters when present) and calls their request methods;
## it owns no rules.
##
## Screens do not stop the world: the game runs behind them, the movement keys still work,
## and every mouse click while a screen is open is taken by the interface (LocalInput asks
## screen_open() / mouse_over_ui()).
class_name GameUi
extends CanvasLayer

signal screen_changed(name: String, open: bool)

var cw: ClientWorld
var presenter: Node
var rules: RulesClient
var items: ItemsClient
var combat: CombatClient
var monsters: Object
var quick := QuickSlots.new()
var prompts := ContextPrompts.new()
## Talk, trade, work and standing (DealsUi: the dialogue panel, toasts); null without Deals.
var deals_ui: DealsUi
## Marks, the talk prompt and plates over people (with Life).
var marks: PeopleMarks
var root: Control
var hud: Hud
## Screens by name (built on first open): inventory, character, constellation, choices, spells.
var screens := {}
var stack: Array[String] = []
var catcher: Control
var ui_scale := 1.0
## Drops seen (id -> item), so a pickup can say what it was.
var drop_items := {}
## Deeds counted on this client since joining (only until the host's DEEDS arrive).
var tally := {}
## Frame cost of the interface, microseconds (for the tour's report).
var frame_usec := PackedInt32Array()
## Screen factories: name -> Callable() -> Control (filled by the screen scripts' owners).
var factories := {}
var _text_focus := false
var _hp_seen := Vector2i(-1, -1)

func _ready() -> void:
	layer = 10
	root = Control.new()
	root.name = "ui_root"
	root.theme = UiTheme.theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	catcher = Control.new()
	catcher.name = "catcher"
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.visible = false
	catcher.gui_input.connect(_catcher_input)
	root.add_child(catcher)
	hud = Hud.new()
	hud.gu = self
	root.add_child(hud)
	get_viewport().size_changed.connect(_fit)
	get_viewport().gui_focus_changed.connect(func(c: Control) -> void: _text_focus = c is LineEdit or c is TextEdit)
	_fit()
	register_screens()

func _fit() -> void:
	var vs := get_viewport().get_visible_rect().size
	ui_scale = UiTheme.scale_for(vs)
	root.scale = Vector2(ui_scale, ui_scale)
	root.size = vs / ui_scale
	root.position = Vector2.ZERO
	catcher.size = root.size
	for c in root.get_children():
		if c is Control and c != catcher:
			(c as Control).size = root.size
	if deals_ui != null:
		deals_ui.layout(root.size)

## Virtual size the interface lays itself out in.
func vsize() -> Vector2:
	return root.size

func attach(client: ClientWorld, pres: Node) -> void:
	cw = client
	presenter = pres
	rules = cw.system(HostSystem.RULES) as RulesClient
	items = cw.system(HostSystem.ITEMS) as ItemsClient
	combat = cw.system(HostSystem.COMBAT) as CombatClient
	monsters = cw.system(HostSystem.MONSTERS)
	quick.on_change = func(slugs: Array) -> void:
		if rules != null:
			rules.set_prefs({"quick": slugs})
	if items != null:
		items.drop_added.connect(func(id: int, _p: Vector2, it: Dictionary) -> void: drop_items[id] = it)
		items.drop_removed.connect(_on_drop_removed)
		items.note.connect(_on_item_note)
	if rules != null:
		rules.leveled.connect(_on_leveled)
		rules.notice.connect(func(t: String) -> void: toast(t))
		rules.xp_gained.connect(func(n: int, src: String) -> void: hud.xp_toast(n, src))
		rules.prefs_arrived.connect(func(p: Dictionary) -> void: quick.load_prefs(p))
		quick.load_prefs(rules.prefs)
	if combat != null:
		combat.event.connect(_on_combat_event)
		# the host said no: why, briefly (out of range, no slot, busy, you are down ...)
		combat.refused.connect(func(_intent: int, why: String) -> void: toast(UiCopy.refusal(why), 1.6, UiTheme.BLOOD_DARK))
	cw.edit_result.connect(_on_edit_result)
	cw.world.tile_changed.connect(_on_tile_changed)
	hud.attach()
	prompts.attach(self)
	if cw.system(HostSystem.DEALS) != null:
		deals_ui = DealsUi.new()
		deals_ui.attach(self)
		marks = PeopleMarks.new()
		marks.gu = self
		root.add_child(marks)
		root.move_child(marks, 0)
		marks.size = root.size
	for s: Control in screens.values():
		if s.has_method("attach"):
			s.call("attach")

func detach() -> void:
	cw = null
	rules = null
	items = null
	combat = null

# --- what LocalInput asks -------------------------------------------------------------------

func screen_open() -> bool:
	return not stack.is_empty()

func mouse_over_ui() -> bool:
	var c := get_viewport().gui_get_hovered_control()
	return c != null and c.mouse_filter == Control.MOUSE_FILTER_STOP and root.is_ancestor_of(c)

func text_focus() -> bool:
	return _text_focus

## Do the number keys belong to the interface now (a conversation's options), not the hotbar?
func number_keys_taken() -> bool:
	return deals_ui != null and deals_ui.talking() and deals_ui.dialogue.visible

func quick_spell(i: int) -> Dictionary:
	return quick.spell_for(i, combat.spells if combat != null else [])

func cast_sent(i: int, ok: bool) -> void:
	if not ok:
		var why := QuickSlots.why_not(quick_spell(i), combat.status if combat != null else {}, combat.busy_s if combat != null else 0.0)
		toast("%s: %s" % [String(quick_spell(i).get("name", QuickSlots.KEYS[i])), why if why != "" else "not now"], 1.6)

# --- screens ---------------------------------------------------------------------------------

## Fill `factories`; screens are made the first time they open.
func register_screens() -> void:
	factories["inventory"] = func() -> Control: return InventoryScreen.new()
	factories["choices"] = func() -> Control: return ChoicesScreen.new()
	factories["constellation"] = func() -> Control: return ConstellationScreen.new()
	factories["spells"] = func() -> Control: return SpellScreen.new()
	factories["character"] = func() -> Control: return CharacterSheet.new()
	factories["shop"] = func() -> Control: return ShopScreen.new()
	factories["quests"] = func() -> Control: return QuestLogScreen.new()
	factories["map"] = func() -> Control: return WorldMapScreen.new()

func screen(name: String) -> Control:
	if screens.has(name):
		return screens[name]
	if not factories.has(name):
		return null
	var s: Control = (factories[name] as Callable).call()
	s.name = name
	s.visible = false
	root.add_child(s)
	s.size = root.size
	screens[name] = s
	if s.has_method("setup"):
		s.call("setup", self)
	if cw != null and s.has_method("attach"):
		s.call("attach")
	return s

func open(name: String) -> void:
	if name == "map" and deals_ui != null:
		deals_ui.fresh_marks = 0
	var s := screen(name)
	if s == null:
		return
	if name in stack:
		stack.erase(name)
	stack.append(name)
	s.visible = true
	s.move_to_front()
	if s.has_method("refresh"):
		s.call("refresh")
	_layout_stack()
	screen_changed.emit(name, true)

func close(name: String) -> void:
	if not name in stack:
		return
	stack.erase(name)
	var s: Control = screens.get(name)
	if s != null:
		s.visible = false
		if s.has_method("closed"):
			s.call("closed")
	_layout_stack()
	screen_changed.emit(name, false)

func toggle(name: String) -> void:
	if name in stack and stack[-1] == name:
		close(name)
	else:
		open(name)

func close_top() -> bool:
	if stack.is_empty():
		return false
	close(stack[-1])
	return true

func is_open(name: String) -> bool:
	return name in stack

func _layout_stack() -> void:
	catcher.visible = not stack.is_empty()
	if not stack.is_empty():
		catcher.move_to_front()
		(screens[stack[-1]] as Control).move_to_front()
	hud.set_dimmed(not stack.is_empty())

func _catcher_input(event: InputEvent) -> void:
	# A click outside every screen: the inventory drops what it holds; nothing reaches the world.
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var inv: Control = screens.get("inventory")
		if inv != null and inv.visible and inv.has_method("click_outside"):
			inv.call("click_outside", event)

func _unhandled_input(event: InputEvent) -> void:
	if _text_focus:
		return
	if deals_ui != null and deals_ui.input(event):
		get_viewport().set_input_as_handled()
		return
	for pair: Array in [["inventory", "inventory"], ["character", "character"], ["constellation", "constellation"],
			["spellbook", "spells"], ["levelup", "choices"], ["quest_log", "quests"], ["world_map", "map"], ["standing", "standing"],
			["help", "help"]]:
		if event.is_action_pressed(pair[0]):
			toggle(pair[1])
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ui_cancel") and close_top():
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and deals_ui != null and deals_ui.talking():
		deals_ui.dc.leave()
		get_viewport().set_input_as_handled()

# --- toasts and events ------------------------------------------------------------------------

func toast(text: String, secs := 3.5, color := UiTheme.INK) -> void:
	if hud != null:
		hud.toast(text, secs, color)

func _on_drop_removed(id: int, by: int) -> void:
	var it: Dictionary = drop_items.get(id, {})
	drop_items.erase(id)
	if cw != null and by == cw.my_id and not it.is_empty():
		var n := Items.count(it)
		var nm := ItemGen.name(it)
		toast("Picked up %s%s" % [nm, " x%d" % n if n > 1 else ""], 2.5, ItemIcons.rarity_color(it))

func _on_item_note(op: int, ok: bool, word: String) -> void:
	if ok:
		if op == ItemsCodec.K.KINDLE:
			toast("The star takes. Your constellation grows.", 3.0, UiTheme.PLUM)
		elif op == ItemsCodec.K.BOND:
			toast("Bonded. It knows you now.", 3.0, UiTheme.PLUM)
		return
	toast(UiCopy.item_refusal(word), 3.0, UiTheme.BLOOD_DARK)

func _on_leveled(level: int, reward: int) -> void:
	hud.banner("Level %d" % level, UiCopy.reward_line(reward, LevelTrack.class_level(level)))

func _on_combat_event(ev: Dictionary) -> void:
	if cw == null:
		return
	if int(ev["kind"]) == CombatCodec.Ev.SWING and int(ev["src"]) == cw.my_id:
		hud._hint_fading = true      # they found the attack: let the controls hint go
	if int(ev["kind"]) == CombatCodec.Ev.DEATH and int(ev["dst"]) != cw.my_id:
		var r: ClientWorld.RemoteEntity = cw.remotes.get(int(ev["dst"]))
		if r != null and r.kind != HostEntity.Kind.PLAYER and hud.hurt_by_me.has(r.id):
			_count("kill", 1)
			_count("kill:" + r.name.to_lower(), 1)
	hud.combat_event(ev)

func _on_edit_result(_req: int, reason: int, _at: Vector2i, tile: int) -> void:
	if reason == 0 and tile != 0:
		_count("place", 1)

func _on_tile_changed(x: int, y: int, layer_: int, old: int, now: int) -> void:
	if layer_ != TileWorld.Layer.FG or now != TileDefs.AIR or old == TileDefs.AIR or cw == null:
		return
	if Vector2(x + 0.5, y + 0.5).distance_to(cw.body.center()) <= 8.0 and Input.is_action_pressed("dig"):
		_count("dig", 1)
		if old < TileDefs.names.size():
			_count("dig:" + TileDefs.names[old], 1)

func _count(counter: String, n: int) -> void:
	tally[counter] = int(tally.get(counter, 0)) + n

## Deeds to show: the host's when it sends them (sheet.deeds), else this session's tally.
func deeds() -> Dictionary:
	if rules != null and rules.sheet.has("deeds"):
		return rules.sheet["deeds"]
	return tally

func _process(_delta: float) -> void:
	if cw == null:
		return
	var t0 := Time.get_ticks_usec()
	var vs := get_viewport().get_visible_rect().size
	if not is_equal_approx(root.size.x * ui_scale, vs.x) or not is_equal_approx(root.size.y * ui_scale, vs.y):
		_fit()
	prompts.tick(_delta)
	hud.tick(_delta)
	if marks != null:
		marks.step()
	frame_usec.append(Time.get_ticks_usec() - t0)
	if frame_usec.size() > 4000:
		frame_usec = frame_usec.slice(2000)
