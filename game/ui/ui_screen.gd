## Base of the interface's screens: a parchment panel centred in the virtual 1280x720 space,
## with an inked title, a close button and a footer hint. The world keeps running behind it.
class_name UiScreen
extends Control

var gu: GameUi
var panel: Panel
var title := ""
var hint := ""
var panel_size := Vector2(1000, 560)
var night := false

func setup(g: GameUi) -> void:
	gu = g
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	if night:
		panel.add_theme_stylebox_override("panel", UiTheme.night_box())
	panel.size = panel_size
	add_child(panel)
	panel.draw.connect(_draw_frame)
	var close := UiTheme.button("x", UiTheme.BODY)
	close.size = Vector2(30, 28)
	close.position = Vector2(panel_size.x - 38, 8)
	close.pressed.connect(func() -> void: gu.close(String(name)))
	panel.add_child(close)
	resized.connect(_center)
	build()
	_center()

func _center() -> void:
	if panel != null:
		panel.position = ((size - panel_size) * 0.5).floor()

## Fill the panel (override).
func build() -> void:
	pass

func _draw_frame() -> void:
	var col := UiTheme.STARLIGHT if night else UiTheme.INK
	UiTheme.text(panel, Vector2(24, 40), title, UiTheme.TITLE, col, true)
	panel.draw_line(Vector2(22, 50), Vector2(22 + UiTheme.text_width(title, UiTheme.TITLE, true) + 30, 50), col, 2.0, true)
	if hint != "":
		UiTheme.text(panel, Vector2(24, panel_size.y - 14), hint, UiTheme.TINY, Color(col, 0.7))
