## Procedural emblems in the house ink: a person's role icon on a faction-coloured disc (the
## dialogue portrait, marks over heads), culture colours for settlements on the map, and the
## marks for work, shops and patrons. Drawn with CanvasItem calls; no textures, no art.
class_name Emblems
extends RefCounted

const FACTION_INKS := [Color("9b3b2a"), Color("2f6f8f"), Color("5d7d2c"), Color("7a4a8c"), Color("a8741e"),
	Color("2e7f73"), Color("8c3d5e"), Color("4b5a7a")]
const CULTURE := {"human": Color("b5523b"), "halfling": Color("6e9a3a"), "dwarf": Color("5f7fa6"), "elf": Color("2f9c7f"),
	"drow": Color("7d4fa8"), "gnome": Color("c49a2c"), "dragonborn": Color("b8432c"), "tiefling": Color("8e2f4f"),
	"goliath": Color("7d8790"), "orc": Color("5a6b2c"), "goblinoid": Color("7a7d2a"), "kobold": Color("a0602a"),
	"gnoll": Color("8a6a3a"), "bandit": Color("6b4a3a")}
## Mark colours over people.
const MARKS := {"shop": UiTheme.GOLD, "smith": Color("9aa3ad"), "work": UiTheme.VERMILION, "turn_in": UiTheme.MOSS,
	"patron": UiTheme.PLUM}

static func faction_color(fid: String) -> Color:
	if fid == "" or fid == "wild":
		return UiTheme.INK_SOFT
	return FACTION_INKS[absi(hash(fid)) % FACTION_INKS.size()]

static func culture_color(culture: String) -> Color:
	return CULTURE.get(culture, UiTheme.INK_SOFT)

## A portrait disc: faction colour, an inked ring, the role's icon in parchment.
static func portrait(ci: CanvasItem, c: Vector2, r: float, role: String, col: Color) -> void:
	ci.draw_circle(c + Vector2(3, 3), r, UiTheme.SHADOW)
	ci.draw_circle(c, r, col)
	ci.draw_circle(c, r * 0.82, col.darkened(0.25))
	ci.draw_arc(c, r, 0, TAU, 48, UiTheme.INK, 3.0, true)
	ci.draw_arc(c, r * 0.82, 0, TAU, 48, UiTheme.PARCHMENT.darkened(0.2), 1.2, true)
	role_icon(ci, c, r * 0.55, role, UiTheme.PARCHMENT)

## A small icon for a role, centred at c, about 2s wide.
static func role_icon(ci: CanvasItem, c: Vector2, s: float, role: String, col: Color) -> void:
	var w := maxf(1.5, s * 0.14)
	match role:
		"merchant":     # a balance
			ci.draw_line(c + Vector2(0, -s * 0.8), c + Vector2(0, s * 0.7), col, w)
			ci.draw_line(c + Vector2(-s * 0.8, -s * 0.5), c + Vector2(s * 0.8, -s * 0.5), col, w)
			for sx: float in [-0.8, 0.8]:
				var p := c + Vector2(s * sx, -s * 0.5)
				ci.draw_line(p, p + Vector2(-s * 0.3, s * 0.6), col, w * 0.6)
				ci.draw_line(p, p + Vector2(s * 0.3, s * 0.6), col, w * 0.6)
				ci.draw_arc(p + Vector2(0, s * 0.6), s * 0.32, 0, PI, 10, col, w)
			ci.draw_line(c + Vector2(-s * 0.4, s * 0.7), c + Vector2(s * 0.4, s * 0.7), col, w)
		"smith":        # a hammer over an anvil
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.9, s * 0.2), c + Vector2(s * 0.9, s * 0.2),
				c + Vector2(s * 0.5, s * 0.5), c + Vector2(s * 0.3, s * 0.85), c + Vector2(-s * 0.3, s * 0.85), c + Vector2(-s * 0.5, s * 0.5)]), col)
			ci.draw_line(c + Vector2(-s * 0.5, -s * 0.9), c + Vector2(s * 0.2, 0.0), col, w)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.85, -s * 0.6), c + Vector2(-s * 0.55, -s * 1.0),
				c + Vector2(-s * 0.15, -s * 0.7), c + Vector2(-s * 0.45, -s * 0.3)]), col)
		"keeper":       # a tankard
			ci.draw_rect(Rect2(c + Vector2(-s * 0.55, -s * 0.6), Vector2(s * 0.9, s * 1.4)), col)
			ci.draw_arc(c + Vector2(s * 0.4, s * 0.1), s * 0.35, -PI * 0.5, PI * 0.5, 10, col, w)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.65, -s * 0.8), Vector2(s * 1.1, s * 0.3)), col.lightened(0.3))
		"priest":       # a sun
			ci.draw_circle(c, s * 0.38, col)
			for i in 8:
				var a := TAU * i / 8.0
				ci.draw_line(c + Vector2(cos(a), sin(a)) * s * 0.55, c + Vector2(cos(a), sin(a)) * s * 0.95, col, w)
		"guard", "escort", "raider":   # a shield
			var pts := PackedVector2Array([c + Vector2(-s * 0.75, -s * 0.8), c + Vector2(s * 0.75, -s * 0.8), c + Vector2(s * 0.7, s * 0.1),
				c + Vector2(0, s * 0.95), c + Vector2(-s * 0.7, s * 0.1)])
			ci.draw_colored_polygon(pts, col)
			ci.draw_line(c + Vector2(0, -s * 0.7), c + Vector2(0, s * 0.75), col.darkened(0.45), w)
			ci.draw_line(c + Vector2(-s * 0.6, -s * 0.25), c + Vector2(s * 0.6, -s * 0.25), col.darkened(0.45), w)
		"drover", "wagon":   # a wheel
			ci.draw_arc(c, s * 0.8, 0, TAU, 20, col, w * 1.3)
			for i in 4:
				var a := PI * i / 4.0
				ci.draw_line(c - Vector2(cos(a), sin(a)) * s * 0.8, c + Vector2(cos(a), sin(a)) * s * 0.8, col, w * 0.7)
		_:              # a head and shoulders
			ci.draw_circle(c + Vector2(0, -s * 0.35), s * 0.4, col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.8, s * 0.95), c + Vector2(-s * 0.6, s * 0.25),
				c + Vector2(0, s * 0.1), c + Vector2(s * 0.6, s * 0.25), c + Vector2(s * 0.8, s * 0.95)]), col)

## A mark over a person's head: a small inked tag. kind: shop, smith, work, turn_in, patron.
static func mark(ci: CanvasItem, c: Vector2, kind: String, s := 11.0) -> void:
	var col: Color = MARKS.get(kind, UiTheme.INK_SOFT)
	match kind:
		"work":       # an exclamation on a vermilion diamond
			var d := PackedVector2Array([c + Vector2(0, -s * 1.2), c + Vector2(s, 0), c + Vector2(0, s * 1.2), c + Vector2(-s, 0)])
			_poly(ci, d, col)
			ci.draw_line(c + Vector2(0, -s * 0.6), c + Vector2(0, s * 0.25), UiTheme.PARCHMENT, 2.5)
			ci.draw_circle(c + Vector2(0, s * 0.6), 1.6, UiTheme.PARCHMENT)
		"turn_in":    # a tick on a green disc
			ci.draw_circle(c + Vector2(2, 2), s, UiTheme.SHADOW)
			ci.draw_circle(c, s, col)
			ci.draw_arc(c, s, 0, TAU, 20, UiTheme.INK, 2.0, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-s * 0.5, 0), c + Vector2(-s * 0.1, s * 0.45), c + Vector2(s * 0.55, -s * 0.45)]), UiTheme.PARCHMENT, 2.5, true)
		"patron":     # a plum star
			UiTheme.star(ci, c, s * 1.2, s * 0.5, col, 5, UiTheme.INK)
		"shop":       # a gold coin
			ci.draw_circle(c + Vector2(2, 2), s * 0.9, UiTheme.SHADOW)
			ci.draw_circle(c, s * 0.9, col)
			ci.draw_arc(c, s * 0.9, 0, TAU, 20, UiTheme.INK, 2.0, true)
			ci.draw_arc(c, s * 0.5, 0, TAU, 14, UiTheme.INK_SOFT, 1.2, true)
		"smith":      # an anvil
			ci.draw_circle(c + Vector2(2, 2), s, UiTheme.SHADOW)
			ci.draw_circle(c, s, UiTheme.PARCHMENT)
			ci.draw_arc(c, s, 0, TAU, 20, UiTheme.INK, 2.0, true)
			role_icon(ci, c + Vector2(0, 1), s * 0.6, "smith", UiTheme.INK)

static func _poly(ci: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	var sh := PackedVector2Array()
	for p in pts:
		sh.append(p + Vector2(2, 2))
	ci.draw_colored_polygon(sh, UiTheme.SHADOW)
	ci.draw_colored_polygon(pts, col)
	var o := pts.duplicate()
	o.append(pts[0])
	ci.draw_polyline(o, UiTheme.INK, 2.0, true)

## A settlement on the map: a culture-coloured house, bigger by tier (hamlet 0 .. city 3).
static func settlement(ci: CanvasItem, c: Vector2, culture: String, tier: int, faint := false) -> void:
	var col := culture_color(culture)
	var a := 0.45 if faint else 1.0
	var s := 6.0 + tier * 2.0
	var n := 1 + mini(tier, 2)
	for i in n:
		var x := c.x + (i - (n - 1) * 0.5) * s * 1.1
		var base := c.y
		var hh := s * (1.0 if i == n / 2 else 0.75)
		var pts := PackedVector2Array([Vector2(x - s * 0.5, base), Vector2(x - s * 0.5, base - hh), Vector2(x, base - hh - s * 0.6),
			Vector2(x + s * 0.5, base - hh), Vector2(x + s * 0.5, base)])
		ci.draw_colored_polygon(pts, Color(col, a))
		var o := pts.duplicate()
		o.append(pts[0])
		ci.draw_polyline(o, Color(UiTheme.INK, a), 1.5, true)
	if tier >= 3:
		UiTheme.star(ci, c + Vector2(0, -s * 2.4), 4, 1.6, Color(UiTheme.GOLD, a), 4, Color(UiTheme.INK, a))

## A lair on the map: a fanged cave mouth (vermilion when apex).
static func lair(ci: CanvasItem, c: Vector2, apex: bool, faint := false) -> void:
	var a := 0.45 if faint else 1.0
	var col := UiTheme.VERMILION if apex else UiTheme.BLOOD_DARK.lightened(0.2)
	ci.draw_arc(c, 7, PI, TAU, 12, Color(UiTheme.INK, a), 6.0, true)
	ci.draw_arc(c, 7, PI, TAU, 12, Color(col, a), 3.0, true)
	for dx: float in [-3.0, 0.0, 3.0]:
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(dx - 1.5, -3), c + Vector2(dx + 1.5, -3), c + Vector2(dx, 1)]), Color(UiTheme.PARCHMENT, a))

## A ruin: two broken columns.
static func ruin(ci: CanvasItem, c: Vector2, faint := false) -> void:
	var a := 0.45 if faint else 1.0
	for i in 2:
		var x := c.x - 4 + i * 8
		var h := 10.0 - i * 4.0
		ci.draw_rect(Rect2(x - 2, c.y - h, 4, h), Color(UiTheme.PARCH_DEEP, a))
		ci.draw_rect(Rect2(x - 2, c.y - h, 4, h), Color(UiTheme.INK, a), false, 1.2)
	ci.draw_line(c + Vector2(-8, 0), c + Vector2(8, 0), Color(UiTheme.INK, a), 1.5)

## The portal: a plum ring.
static func portal(ci: CanvasItem, c: Vector2, faint := false) -> void:
	var a := 0.45 if faint else 1.0
	ci.draw_arc(c, 8, 0, TAU, 24, Color(UiTheme.INK, a), 5.0, true)
	ci.draw_arc(c, 8, 0, TAU, 24, Color(UiTheme.PLUM.lightened(0.2), a), 3.0, true)
	UiTheme.star(ci, c, 4, 1.5, Color(UiTheme.STARLIGHT, a), 4, Color(0, 0, 0, 0))
