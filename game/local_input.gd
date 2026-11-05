## Fills a PlayerInput from the keyboard and mouse each frame (input actions in
## project.godot): move_left/move_right (A/D, arrows), jump (Space), move_up/move_down
## (W/S, arrows), dig (left mouse), place (right mouse), tile_1..tile_4 pick the block.
## The target tile comes from the presenter's screen picking. Combat (CombatClient): attack
## (F, held repeats) aims at the mouse; cast_1..cast_4 (Q, E, R, T) cast the character's
## first four castable attack/save spells at the lowest slot level (the Interface track's
## hotbar replaces this). Conditions (speed 0, prone, fear) filter the movement here.
class_name LocalInput
extends Node

const PLACEABLE := ["wood", "platform", "torch", "ladder"]

var presenter: Presenter
var input := PlayerInput.new()
var place_tile := 0

func _ready() -> void:
	place_tile = TileDefs.id(PLACEABLE[0])

func read() -> PlayerInput:
	input.move_x = Input.get_axis("move_left", "move_right")
	input.jump = Input.is_action_pressed("jump")
	input.jump_pressed = Input.is_action_just_pressed("jump")
	input.up = Input.is_action_pressed("move_up")
	input.down = Input.is_action_pressed("move_down")
	input.dig = Input.is_action_pressed("dig")
	input.place = Input.is_action_pressed("place") and not input.dig
	for i in PLACEABLE.size():
		if Input.is_action_just_pressed("tile_%d" % (i + 1)):
			place_tile = TileDefs.id(PLACEABLE[i])
	input.place_tile = place_tile
	if presenter != null and (input.dig or input.place):
		input.target = presenter.tile_at_screen(get_viewport().get_mouse_position())
	_combat()
	return input

func _combat() -> void:
	if presenter == null or presenter.cw == null:
		return
	var cc := presenter.cw.system(HostSystem.COMBAT) as CombatClient
	if cc == null:
		return
	var aim := Vector2(presenter.tile_at_screen(get_viewport().get_mouse_position())) + Vector2(0.5, 0.5)
	if Input.is_action_pressed("attack"):
		cc.attack(aim)
	for i in 4:
		if Input.is_action_just_pressed("cast_%d" % (i + 1)):
			var s := cc.spell_slot(i)
			if not s.is_empty():
				cc.cast(String(s["slug"]), int(s["level"]), aim)
	input = cc.filter_input(input)
