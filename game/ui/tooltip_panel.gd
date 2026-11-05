## The interface's tooltip: a small parchment card of styled lines (ItemText.lines' format),
## kept beside the mouse and inside the screen.
class_name TooltipPanel
extends PanelContainer

const STYLE_COLORS := {"title": UiTheme.INK, "sub": UiTheme.INK_SOFT, "stat": UiTheme.INK, "good": Color("3d6b1f"),
	"bad": UiTheme.BLOOD_DARK, "magic": Color("5a2f78"), "warn": Color("8a5a00"), "flavor": UiTheme.INK_SOFT}
const WIDTH := 300.0

var box: VBoxContainer

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UiTheme.panel_box(UiTheme.PARCHMENT, UiTheme.INK, 2, 4)
	sb.set_content_margin_all(10)
	add_theme_stylebox_override("panel", sb)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	visible = false
	z_index = 50

func show_lines(lines: Array, at: Vector2, title_color := UiTheme.INK) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	for l: Array in lines:
		var st := String(l[1])
		var lab := UiTheme.label(String(l[0]), UiTheme.HEADING if st == "title" else (UiTheme.TINY if st in ["flavor", "sub"] else UiTheme.SMALL),
			title_color if st == "title" else STYLE_COLORS.get(st, UiTheme.INK), st == "title")
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.custom_minimum_size.x = WIDTH
		box.add_child(lab)
	visible = true
	reset_size()
	place(at)

func place(at: Vector2) -> void:
	var lim := get_parent_control().size if get_parent_control() != null else Vector2(1280, 720)
	var p := at + Vector2(18, 12)
	if p.x + size.x > lim.x - 4:
		p.x = at.x - size.x - 12
	if p.y + size.y > lim.y - 4:
		p.y = lim.y - size.y - 4
	position = p.max(Vector2(4, 4))

func hide_tip() -> void:
	visible = false
