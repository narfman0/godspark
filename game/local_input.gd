## Fills a PlayerInput from the keyboard and mouse each frame (input actions in
## project.godot): move_left/move_right (A/D, arrows), jump (Space), move_up/move_down
## (W/S, arrows), dig (left mouse), place (right mouse), tile_1..tile_4 pick the block.
## The target tile comes from the presenter's screen picking.
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
	# With the items system the keys pick hotbar slots 1-4 and you place what is selected.
	var items: ClientSystem = presenter.cw.system(HostSystem.ITEMS) if presenter != null and presenter.cw != null else null
	for i in PLACEABLE.size():
		if Input.is_action_just_pressed("tile_%d" % (i + 1)):
			place_tile = TileDefs.id(PLACEABLE[i])
			if items != null and items.has_method("select_hotbar"):
				items.call("select_hotbar", i)
	if items != null and bool(items.get("live")):
		place_tile = int(items.call("selected_tile"))
	input.place_tile = place_tile
	if presenter != null and (input.dig or input.place):
		input.target = presenter.tile_at_screen(get_viewport().get_mouse_position())
	return input
