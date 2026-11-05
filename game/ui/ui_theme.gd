## The interface's look in one place: colours, fonts, StyleBoxes, a Theme, and a few ink
## drawing helpers every widget shares. Change the look here.
##
## The look: hand-inked. Dark ink outlines with a hard offset "print" shadow, parchment
## panels, night-sky panels for the stars, bold flat accents (vermilion hit points, gold
## experience and coin, teal spell slots, plum magic).
##
## Fonts are fetched by tools/fetch_fonts.sh into assets/fonts/ (git-ignored, OFL); with
## none present the engine's default font is used. Nothing here runs on dedicated servers or
## bots: only the windowed presenter builds the interface.
##
##   var theme := UiTheme.theme()            # set on the UI root Control
##   UiTheme.label("Hello", UiTheme.BODY, UiTheme.INK)
##   UiTheme.ink_rect(self, rect, UiTheme.PARCHMENT)   # inside _draw()
class_name UiTheme
extends RefCounted

# --- colours ------------------------------------------------------------------------------
const INK := Color("1b1612")
const INK_SOFT := Color("4a3c30")
const INK_FADED := Color(0.106, 0.086, 0.071, 0.35)
const PARCHMENT := Color("efe2c2")
const PARCH_SHADE := Color("dccaa0")
const PARCH_DEEP := Color("b99d6b")
const NIGHT := Color("161c38")
const NIGHT_DEEP := Color("0b0f22")
const STARLIGHT := Color("f6e9b8")
const VERMILION := Color("d9452b")
const BLOOD_DARK := Color("6e1a12")
const GOLD := Color("e8b13a")
const TEAL := Color("2f9c95")
const SKY := Color("5b8fd9")
const MOSS := Color("6ea33c")
const PLUM := Color("8e4fb3")
const SHADOW := Color(0.06, 0.04, 0.03, 0.55)
const TEXT_LIGHT := Color("f7eedb")

## Rarity accents (SRD rarities; "spark" for sparks, "fine" for ordinary gear with affixes).
const RARITY := {
	"": INK_SOFT, "common": INK_SOFT, "fine": Color("3f7f8a"), "uncommon": MOSS, "rare": SKY,
	"very rare": PLUM, "legendary": Color("e07b1f"), "artifact": VERMILION, "spark": Color("ffd75e"),
}

# --- sizes (virtual 1280x720 pixels; the UI root scales with the window) -------------------
const BASE_SIZE := Vector2(1280, 720)
const TITLE := 30
const HEADING := 22
const BODY := 18
const SMALL := 15
const TINY := 13
const BORDER := 3
const PRINT_OFFSET := Vector2(3, 3)

const FONT_DIR := "res://assets/fonts/"
const DISPLAY_FILE := "IMFellEnglishSC.ttf"
const BODY_FILE := "PatrickHand.ttf"

static var _theme: Theme
static var _display: Font
static var _body: Font
static var _fonts_loaded := false

## UI scale for a window size: 1.0 at 1280x720, 1.5 at 1920x1080, never below 0.75.
static func scale_for(window: Vector2) -> float:
	return clampf(minf(window.x / BASE_SIZE.x, window.y / BASE_SIZE.y), 0.75, 3.0)

static func _load_fonts() -> void:
	if _fonts_loaded:
		return
	_fonts_loaded = true
	_display = _font_file(DISPLAY_FILE)
	_body = _font_file(BODY_FILE)
	var fallback := ThemeDB.fallback_font
	if _body == null:
		_body = fallback
	elif fallback != null:
		_body.fallbacks = [fallback]
	if _display == null:
		_display = _body
	elif _body != null:
		_display.fallbacks = [_body]

static func _font_file(file: String) -> FontFile:
	var path := FONT_DIR + file
	if not FileAccess.file_exists(path):
		return null
	var f := FontFile.new()
	if f.load_dynamic_font(path) != OK:
		return null
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.hinting = TextServer.HINTING_LIGHT
	return f

## Titles, banners, card names.
static func display_font() -> Font:
	_load_fonts()
	return _display

## Everything else.
static func body_font() -> Font:
	_load_fonts()
	return _body

static func has_fetched_fonts() -> bool:
	return FileAccess.file_exists(FONT_DIR + BODY_FILE)

# --- style boxes -------------------------------------------------------------------------

## A parchment panel: ink border and a hard offset print shadow.
static func panel_box(bg := PARCHMENT, border := INK, width := BORDER, radius := 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.shadow_color = SHADOW
	s.shadow_size = 0
	s.shadow_offset = PRINT_OFFSET
	s.shadow_size = 1
	s.set_content_margin_all(10)
	s.anti_aliasing = true
	return s

static func night_box() -> StyleBoxFlat:
	var s := panel_box(NIGHT, STARLIGHT.darkened(0.25), 2, 8)
	return s

static func slot_box(bg := PARCH_SHADE, border := INK_SOFT, width := 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(4)
	s.set_content_margin_all(2)
	s.anti_aliasing = true
	return s

static func button_box(bg: Color, border := INK, pressed := false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(5)
	s.shadow_color = SHADOW
	s.shadow_offset = Vector2.ZERO if pressed else Vector2(2, 2)
	s.shadow_size = 0 if pressed else 1
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 3
	s.content_margin_bottom = 4
	s.anti_aliasing = true
	return s

## The Theme every interface Control inherits (from the UI root).
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = BODY
	t.set_color("font_color", "Label", INK)
	t.set_stylebox("panel", "Panel", panel_box())
	t.set_stylebox("panel", "PanelContainer", panel_box())
	t.set_stylebox("normal", "Button", button_box(PARCH_SHADE))
	t.set_stylebox("hover", "Button", button_box(PARCHMENT.lightened(0.15)))
	t.set_stylebox("pressed", "Button", button_box(PARCH_DEEP, INK, true))
	t.set_stylebox("disabled", "Button", button_box(PARCH_SHADE.darkened(0.12), INK_FADED))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", INK_FADED)
	t.set_font_size("font_size", "Button", BODY)
	var tip := panel_box(PARCHMENT, INK, 2, 4)
	tip.set_content_margin_all(8)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", INK)
	t.set_font_size("normal_font_size", "RichTextLabel", BODY)
	t.set_color("default_color", "RichTextLabel", INK)
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	var sb_grab := StyleBoxFlat.new()
	sb_grab.bg_color = INK_SOFT
	sb_grab.set_corner_radius_all(3)
	t.set_stylebox("grabber", "VScrollBar", sb_grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", sb_grab)
	t.set_stylebox("grabber_pressed", "VScrollBar", sb_grab)
	var sb_track := StyleBoxFlat.new()
	sb_track.bg_color = PARCH_SHADE
	sb_track.set_corner_radius_all(3)
	sb_track.content_margin_left = 6
	t.set_stylebox("scroll", "VScrollBar", sb_track)
	t.set_constant("separation", "VBoxContainer", 4)
	t.set_constant("separation", "HBoxContainer", 6)
	_theme = t
	return t

# --- labels ------------------------------------------------------------------------------

static func label(text: String, size := BODY, color := INK, display := false) -> Label:
	var l := Label.new()
	l.text = text
	style_label(l, size, color, display)
	return l

static func style_label(l: Label, size := BODY, color := INK, display := false) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if display:
		l.add_theme_font_override("font", display_font())
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE

## A label readable over the game world: light text with an ink outline.
static func world_label(l: Label, size := BODY, color := TEXT_LIGHT, outline := 5) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE

static func button(text: String, size := BODY) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_NONE
	return b

# --- ink drawing (call inside a CanvasItem's _draw) -----------------------------------------

## A filled rectangle with an ink outline and the offset print shadow.
static func ink_rect(ci: CanvasItem, r: Rect2, fill: Color, border := INK, width := 2.0, shadow := true) -> void:
	if shadow:
		ci.draw_rect(Rect2(r.position + PRINT_OFFSET * 0.7, r.size), SHADOW)
	ci.draw_rect(r, fill)
	ci.draw_rect(r, border, false, width)

## A horizontal bar: `frac` filled with `fill` over a dark trough, ink outline. `ghost` (>= frac)
## draws a paler tail (recent loss).
static func ink_bar(ci: CanvasItem, r: Rect2, frac: float, fill: Color, trough := INK_SOFT, ghost := -1.0) -> void:
	ci.draw_rect(Rect2(r.position + PRINT_OFFSET * 0.6, r.size), SHADOW)
	ci.draw_rect(r, trough)
	if ghost > frac:
		ci.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(ghost, 0.0, 1.0), r.size.y)), fill.lightened(0.45))
	var w := r.size.x * clampf(frac, 0.0, 1.0)
	if w > 0.0:
		ci.draw_rect(Rect2(r.position, Vector2(w, r.size.y)), fill)
		ci.draw_rect(Rect2(r.position, Vector2(w, maxf(1.0, r.size.y * 0.28))), fill.lightened(0.25))
	ci.draw_rect(r, INK, false, 2.0)

## A round pip: filled or an empty ring.
static func pip(ci: CanvasItem, c: Vector2, radius: float, color: Color, filled: bool) -> void:
	if filled:
		ci.draw_circle(c + Vector2(1, 1), radius, SHADOW)
		ci.draw_circle(c, radius, color)
		ci.draw_arc(c, radius, 0, TAU, 16, INK, 1.5, true)
	else:
		ci.draw_arc(c, radius - 0.5, 0, TAU, 16, INK_SOFT, 1.5, true)

## A pointed star (points >= 4) centred at c.
static func star(ci: CanvasItem, c: Vector2, outer: float, inner: float, color: Color, points := 4, outline := INK, rot := 0.0) -> void:
	var pts := PackedVector2Array()
	for i in points * 2:
		var a := rot - PI * 0.5 + PI * i / points
		var r := outer if i % 2 == 0 else inner
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	ci.draw_colored_polygon(pts, color)
	if outline.a > 0.0:
		pts.append(pts[0])
		ci.draw_polyline(pts, outline, 1.5, true)

## A pie (a cooldown sweep): the part of a circle still waiting, `frac` of a turn from the top.
static func sweep(ci: CanvasItem, c: Vector2, radius: float, frac: float, color: Color) -> void:
	if frac <= 0.0:
		return
	var pts := PackedVector2Array([c])
	var n := maxi(3, ceili(24 * frac))
	for i in n + 1:
		var a := -PI * 0.5 + TAU * frac * i / n
		pts.append(c + Vector2(cos(a), sin(a)) * radius)
	ci.draw_colored_polygon(pts, color)

## Text drawn directly (for custom-drawn widgets).
static func text(ci: CanvasItem, pos: Vector2, s: String, size := BODY, color := INK, display := false,
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, outline := 0) -> void:
	var f := display_font() if display else body_font()
	if outline > 0:
		ci.draw_string_outline(f, pos, s, align, width, size, outline, INK)
	ci.draw_string(f, pos, s, align, width, size, color)

static func text_width(s: String, size := BODY, display := false) -> float:
	var f := display_font() if display else body_font()
	return f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
