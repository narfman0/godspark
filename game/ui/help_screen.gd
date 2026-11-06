## The controls card (F1 or H): every key, in four inked groups, from Controls (the one place
## the scheme lives). A night-sky card so it reads apart from the parchment screens.
class_name HelpScreen
extends UiScreen

func _init() -> void:
	title = "How things are done"
	hint = "Screens never pause the world: it is co-op.   Esc, F1 or H: close"
	panel_size = Vector2(1060, 560)

func build() -> void:
	var cols := [Vector2(28, 70), Vector2(546, 70)]
	var i := 0
	for g: Array in Controls.GROUPS:
		var at: Vector2 = cols[0] if i < 2 else cols[1]
		if i == 1:
			at.y = 290
		elif i == 3:
			at.y = 250
		var v := VBoxContainer.new()
		v.position = at
		v.add_theme_constant_override("separation", 3)
		panel.add_child(v)
		v.add_child(UiTheme.label(String(g[0]), UiTheme.HEADING, UiTheme.INK, true))
		for row: Array in g[1]:
			var h := HBoxContainer.new()
			var k := UiTheme.label(String(row[0]), UiTheme.SMALL + 1, UiTheme.INK)
			var key_box := PanelContainer.new()
			var sb := UiTheme.button_box(UiTheme.PARCHMENT)
			sb.content_margin_top = 1
			sb.content_margin_bottom = 1
			key_box.add_theme_stylebox_override("panel", sb)
			key_box.add_child(k)
			var wrap := Control.new()
			wrap.custom_minimum_size = Vector2(150, 30)
			key_box.position = Vector2(0, 1)
			wrap.add_child(key_box)
			h.add_child(wrap)
			var d := UiTheme.label(String(row[1]), UiTheme.SMALL + 1, UiTheme.INK)
			d.custom_minimum_size.x = 330
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			h.add_child(d)
			v.add_child(h)
		i += 1
