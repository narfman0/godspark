## A small log of world history at the bottom left of the screen: new chronicle lines appear,
## stay for SHOW seconds and fade out over FADE. The toggle_chronicle action (L) hides it, or
## shows the last few lines again.
class_name ChronicleOverlay
extends CanvasLayer

const SHOW := 12.0
const FADE := 3.0
const MAX_LINES := 4
var width := 700.0

var visible_log := true
var _box: VBoxContainer
var _lines: Array = []    # [{label: Label, age: float}]
var _recent := PackedStringArray()

func _ready() -> void:
	layer = 5
	_box = VBoxContainer.new()
	_box.anchor_top = 1.0
	_box.anchor_bottom = 1.0
	_box.offset_left = 16.0
	_box.offset_right = 16.0 + width
	_box.offset_top = -16.0
	_box.offset_bottom = -16.0
	_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_box.add_theme_constant_override("separation", 2)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)

## Lift the log above the HUD's bottom bar and narrow it (virtual pixels at 1280x720).
func set_margin(bottom: float, w: float) -> void:
	_box.offset_bottom = -bottom
	_box.offset_top = -bottom
	_box.offset_right = 16.0 + w
	width = w
	for l: Dictionary in _lines:
		(l["label"] as Label).custom_minimum_size.x = w

func add_lines(lines: PackedStringArray) -> void:
	for l in lines:
		_recent.append(l)
		if visible_log:
			_add(l)
	if _recent.size() > MAX_LINES:
		_recent = _recent.slice(_recent.size() - MAX_LINES)

func _add(text: String) -> void:
	var lab := Label.new()
	lab.text = text
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.custom_minimum_size.x = width
	lab.add_theme_font_size_override("font_size", 13)
	lab.add_theme_color_override("font_color", Color(0.93, 0.89, 0.78))
	lab.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	lab.add_theme_constant_override("shadow_offset_x", 1)
	lab.add_theme_constant_override("shadow_offset_y", 1)
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(lab)
	_lines.append({"label": lab, "age": 0.0})
	while _lines.size() > MAX_LINES:
		(_lines.pop_front()["label"] as Label).queue_free()

func _process(delta: float) -> void:
	for i in range(_lines.size() - 1, -1, -1):
		var l: Dictionary = _lines[i]
		l["age"] += delta
		var lab: Label = l["label"]
		lab.modulate.a = clampf(1.0 - (float(l["age"]) - SHOW) / FADE, 0.0, 1.0)
		if l["age"] > SHOW + FADE:
			lab.queue_free()
			_lines.remove_at(i)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_chronicle"):
		toggle()

func toggle() -> void:
	visible_log = not visible_log
	for l: Dictionary in _lines:
		(l["label"] as Label).queue_free()
	_lines.clear()
	if visible_log:
		for s in _recent:
			_add(s)
