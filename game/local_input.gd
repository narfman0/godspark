## Fills a PlayerInput from the keyboard and mouse each frame (input actions in
## project.godot; the whole scheme is in README "Controls"):
##   move A/D (arrows), climb W/S, jump Space, dash Shift (with the Dash spark; a double tap
##   works too), dig: RIGHT mouse (held), primary: LEFT mouse uses the selected hotbar item
##   toward the cursor (a weapon or empty slot attacks and keeps attacking while held, a
##   placeable places, a potion is drunk), F attacks with the wielded weapon whatever is
##   selected, 1-0 pick a hotbar slot, Q R T G: hold to aim a quick spell, release to cast.
## Mouse buttons reach the world only through _unhandled_input, so a click the interface
## takes (any screen, the hotbar, a button) never digs or attacks; with a screen open the
## interface takes every click. The interface (presenter.ui, a GameUi, windowed clients
## only) is used by duck typing so headless runs never load it.
## Conditions (speed 0, prone, fear) filter the movement here (CombatClient.filter_input).
class_name LocalInput
extends Node

const PLACEABLE := ["wood", "platform", "torch", "ladder"]

var presenter: Presenter
var input := PlayerInput.new()
var place_tile := 0
var _lmb := false
var _rmb := false
var _lmb_edge := false
## Quick spell being aimed (0-3), -1 none.
var _aiming := -1

func _ready() -> void:
	place_tile = TileDefs.id(PLACEABLE[0])

func _ui() -> Object:
	return presenter.get("ui") if presenter != null else null

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	var ui := _ui()
	var allowed := true
	if ui != null:
		allowed = InputLogic.world_click_allowed(bool(ui.call("screen_open")), bool(ui.call("mouse_over_ui")))
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed and allowed:
			_lmb = true
			_lmb_edge = true
		elif not mb.pressed:
			_lmb = false
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		_rmb = mb.pressed and allowed

## Forget held buttons (a screen opened over the world).
func release_mouse() -> void:
	_lmb = false
	_rmb = false
	_lmb_edge = false

func read() -> PlayerInput:
	var ui := _ui()
	var keys_ok := InputLogic.movement_allowed(ui != null and bool(ui.call("text_focus")))
	if ui != null and bool(ui.call("screen_open")):
		release_mouse()
	input.move_x = Input.get_axis("move_left", "move_right") if keys_ok else 0.0
	input.jump = keys_ok and Input.is_action_pressed("jump")
	input.jump_pressed = keys_ok and Input.is_action_just_pressed("jump")
	input.up = keys_ok and Input.is_action_pressed("move_up")
	input.down = keys_ok and Input.is_action_pressed("move_down")
	input.dash = keys_ok and Input.is_action_just_pressed("dash") and (ui == null or not bool(ui.call("screen_open")))
	input.dig = _rmb
	input.place = false
	var cw := presenter.cw if presenter != null else null
	var items: ClientSystem = cw.system(HostSystem.ITEMS) if cw != null else null
	var live := items != null and bool(items.get("live"))
	for i in Inventory.HOTBAR:
		if keys_ok and Input.is_action_just_pressed("hotbar_%d" % (i + 1)):
			if items != null:
				items.call("select_hotbar", InputLogic.hotbar_index(i + 1))
			if i < PLACEABLE.size():
				place_tile = TileDefs.id(PLACEABLE[i])     # without the items system: fixed blocks
	var item: Dictionary = items.call("item", int(items.call("selected"))) if live else {}
	var act := InputLogic.primary_action(item) if live else "place"
	if live:
		place_tile = int(items.call("selected_tile"))
	input.place_tile = place_tile
	var mouse_tile := presenter.tile_at_screen(get_viewport().get_mouse_position()) if presenter != null else Vector2i.ZERO
	match act:
		"place":
			input.place = _lmb and not input.dig
		"use":
			if _lmb_edge and items != null:
				items.call("use", int(items.call("selected")))
	if input.dig or input.place:
		input.target = mouse_tile
	_combat(act == "attack" and _lmb, Vector2(mouse_tile) + Vector2(0.5, 0.5), keys_ok)
	_lmb_edge = false
	return input

func _combat(primary_attack: bool, aim: Vector2, keys_ok: bool) -> void:
	if presenter == null or presenter.cw == null:
		return
	var cc := presenter.cw.system(HostSystem.COMBAT) as CombatClient
	if cc == null:
		return
	if primary_attack or (keys_ok and Input.is_action_pressed("attack")):
		cc.attack(aim)
	var ui := _ui()
	for i in 4:
		var act := "cast_%d" % (i + 1)
		if keys_ok and Input.is_action_just_pressed(act) and _aiming < 0:
			_aiming = i
		if _aiming == i:
			var s: Dictionary = ui.call("quick_spell", i) if ui != null else cc.spell_slot(i)
			if Input.is_action_pressed(act) and keys_ok:
				if presenter.has_method("aim_preview"):
					presenter.call("aim_preview", s, aim)
			else:
				_aiming = -1
				if presenter.has_method("aim_preview"):
					presenter.call("aim_preview", {}, aim)
				if not s.is_empty():
					var ok := cc.cast(String(s["slug"]), int(s["level"]), aim)
					if ui != null:
						ui.call("cast_sent", i, ok)
	input = cc.filter_input(input)
