## Pure decisions behind the control scheme (README "Controls"), kept apart so tests can
## check them without a window:
##   - the selected hotbar item decides what the left mouse button does
##   - a click over an interface screen or widget never reaches the world
##   - the mouse wheel zooms, except with Ctrl held or over the hotbar, where it picks a slot
class_name InputLogic
extends RefCounted

## What the left mouse button does with this hotbar item: "place" (a placeable tile),
## "use" (a consumable such as a potion), else "attack" (weapons, empty slots and anything
## else swing the wielded main-hand weapon, or fists).
static func primary_action(item: Dictionary) -> String:
	if item.is_empty():
		return "attack"
	if Items.tile_of(item) > 0:
		return "place"
	if not Items.use_of(item).is_empty() and Items.slot_kind(item) == "":
		return "use"
	return "attack"

## May a mouse click act on the world (dig, place, attack)?
static func world_click_allowed(screen_open: bool, over_ui: bool) -> bool:
	return not screen_open and not over_ui

## What a wheel notch does: "hotbar" or "zoom".
static func wheel_target(ctrl: bool, over_hotbar: bool) -> String:
	return "hotbar" if ctrl or over_hotbar else "zoom"

## The hotbar slot after one wheel notch (dir +1 = next), wrapping over 10 slots.
static func next_hotbar(selected: int, dir: int) -> int:
	return posmod(selected + dir, Inventory.HOTBAR)

## May the keyboard move the character? Only a focused text field takes the keys away.
static func movement_allowed(text_focus: bool) -> bool:
	return not text_focus

## Hotbar slot for a hotbar_N action (keys 1-9 then 0): N - 1.
static func hotbar_index(n: int) -> int:
	return clampi(n - 1, 0, Inventory.HOTBAR - 1)
