## One inked card of a Knack (or Epic Boon) offer: what it is, what it does, and the deed that
## put it on the table. Click to take it.
class_name KnackCard
extends Control

signal picked(id: String)

const KIND_COLORS := {"skill": UiTheme.TEAL, "tool": UiTheme.GOLD, "language": UiTheme.SKY, "bond": UiTheme.VERMILION, "boon": UiTheme.PLUM}

var id := ""
var nm := ""
var kind := ""
var text := ""
var deed := ""
var _hover := false

func setup(choice: Dictionary, opt: Dictionary, deeds: Dictionary) -> void:
	id = String(opt.get("id", ""))
	nm = String(opt.get("name", id))
	if String(choice.get("kind", "")) == "knack":
		var d := Knacks.def(id)
		kind = String(d.get("kind", "knack"))
		text = String(d.get("text", ""))
		deed = ChoiceLogic.knack_line(id, deeds)
	else:
		kind = "boon"
		text = ChoiceLogic.option_text(choice, opt)
		deed = "Past mortal, the road bends upward."
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func() -> void:
		_hover = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = false
		queue_redraw())

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		picked.emit(id)
		accept_event()

func _draw() -> void:
	var lift := -6.0 if _hover else 0.0
	var r := Rect2(Vector2(0, lift), size)
	var col: Color = KIND_COLORS.get(kind, UiTheme.INK_SOFT)
	draw_rect(Rect2(r.position + Vector2(5, 6), r.size), UiTheme.SHADOW)
	draw_rect(r, UiTheme.PARCHMENT.lightened(0.05))
	draw_rect(r.grow(-7), col.lightened(0.55), false, 2.0)
	draw_rect(r, UiTheme.INK, false, 3.0)
	# the corner seal
	draw_circle(r.position + Vector2(r.size.x * 0.5, 50), 30, col)
	draw_arc(r.position + Vector2(r.size.x * 0.5, 50), 30, 0, TAU, 32, UiTheme.INK, 2.5, true)
	UiTheme.star(self, r.position + Vector2(r.size.x * 0.5, 50), 18, 6, UiTheme.PARCHMENT, 4 if kind != "bond" else 6, UiTheme.INK)
	var w := r.size.x - 28
	UiTheme.text(self, r.position + Vector2(14, 112), nm, UiTheme.HEADING, UiTheme.INK, true, HORIZONTAL_ALIGNMENT_CENTER, w)
	UiTheme.text(self, r.position + Vector2(14, 134), kind.capitalize(), UiTheme.SMALL, col.darkened(0.3), false, HORIZONTAL_ALIGNMENT_CENTER, w)
	draw_line(r.position + Vector2(40, 144), r.position + Vector2(r.size.x - 40, 144), UiTheme.INK_FADED, 1.5)
	_wrap(text, r.position + Vector2(14, 168), w, UiTheme.SMALL, UiTheme.INK, 6)
	# the deed line: wrapped inside its box (it used to run off the card: "for time among bird")
	var lh := UiTheme.TINY + 3
	draw_rect(Rect2(r.position + Vector2(10, r.size.y - 14 - lh * 4 - 8), Vector2(r.size.x - 20, lh * 4 + 8)), Color(col, 0.16))
	_wrap(deed, r.position + Vector2(18, r.size.y - 14 - lh * 4 + UiTheme.TINY), w - 8, UiTheme.TINY, UiTheme.INK_SOFT, 4)
	if _hover:
		UiTheme.text(self, r.position + Vector2(0, r.size.y + 22), "click to take it", UiTheme.SMALL, UiTheme.INK_SOFT, false, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)

## Word-wrapped text drawn in at most max_lines lines.
func _wrap(s: String, at: Vector2, w: float, fs: int, col: Color, max_lines: int) -> void:
	var words := s.replace("\n", " ").split(" ", false)
	var line := ""
	var y := at.y
	var n := 0
	for word in words:
		var t := word if line == "" else line + " " + word
		if UiTheme.text_width(t, fs) > w and line != "":
			n += 1
			if n >= max_lines:
				UiTheme.text(self, Vector2(at.x, y), line + "...", fs, col)
				return
			UiTheme.text(self, Vector2(at.x, y), line, fs, col)
			y += fs + 3
			line = word
		else:
			line = t
	if line != "":
		UiTheme.text(self, Vector2(at.x, y), line, fs, col)
