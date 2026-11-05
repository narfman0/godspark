## The constellation (K, or E at a shrine): the character's kindled sparks as stars on a night
## sky, joined by ink lines in the order kindled, empty slots as faint rings where the next
## stars will go (slots come from level). Hover a star for its name, rank and effect. Loose
## sparks from the pack are listed at the side; near a shrine, pick one and kindle it into an
## empty slot, or click a star to swap it out (ItemsClient.kindle / swap_spark). The drawing
## doubles as the character's sigil, shown at the bottom (the holy symbol to come).
class_name ConstellationScreen
extends UiScreen

const SKY := Vector2(440, 440)

var sky: Control
var side: VBoxContainer
var tip: TooltipPanel
var sigil_rect: TextureRect
var chosen := -1     ## inventory slot of the loose spark picked
var _hover := -1
var _lay := {}
var _dust: Array = []

func _init() -> void:
	title = "Constellation"
	hint = "Sparks never touch your attacks, AC or damage: they change how you move and live."
	panel_size = Vector2(980, 560)
	night = true

func build() -> void:
	sky = Control.new()
	sky.position = Vector2(26, 76)
	sky.size = SKY
	sky.mouse_filter = Control.MOUSE_FILTER_STOP
	sky.draw.connect(_draw_sky)
	sky.gui_input.connect(_sky_input)
	sky.mouse_exited.connect(func() -> void:
		_hover = -1
		tip.hide_tip()
		sky.queue_redraw())
	panel.add_child(sky)
	side = VBoxContainer.new()
	side.position = Vector2(500, 76)
	side.size = Vector2(450, 330)
	panel.add_child(side)
	sigil_rect = TextureRect.new()
	sigil_rect.position = Vector2(500, 420)
	sigil_rect.size = Vector2(96, 96)
	sigil_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sigil_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	panel.add_child(sigil_rect)
	var sl := UiTheme.label("Your sigil. Worshippers will carry it, one day.", UiTheme.SMALL, UiTheme.STARLIGHT.darkened(0.15))
	sl.position = Vector2(608, 456)
	panel.add_child(sl)
	tip = TooltipPanel.new()
	add_child(tip)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for i in 90:
		_dust.append([Vector2(rng.randf() * SKY.x, rng.randf() * SKY.y), rng.randf_range(0.6, 1.6), rng.randf_range(0.15, 0.5)])

func attach() -> void:
	if gu.items != null:
		gu.items.constellation_changed.connect(refresh)
		gu.items.inventory_changed.connect(func(_i: Array) -> void: refresh())

func closed() -> void:
	chosen = -1
	tip.hide_tip()

func refresh() -> void:
	if not visible or gu.items == null:
		return
	var con := gu.items.constellation
	_lay = SigilLayout.layout(gu.cw.player_name, con.kindled, con.slots, SKY)
	sigil_rect.texture = ImageTexture.create_from_image(SigilLayout.image(gu.items.sigil(), 96))
	sky.queue_redraw()
	_fill_side()

func loose_sparks() -> Array:
	var out: Array = []
	for i in Inventory.SIZE:
		if gu.items.item(i).has("spark"):
			out.append(i)
	return out

func _fill_side() -> void:
	for c in side.get_children():
		side.remove_child(c)
		c.queue_free()
	var con := gu.items.constellation
	var shrine := Nearby.has(gu.cw, Nearby.SHRINE, 3)
	side.add_child(UiTheme.label("%d of %d stars kindled" % [con.size(), con.slots], UiTheme.HEADING, UiTheme.STARLIGHT, true))
	var where := UiTheme.label("A shrine is close: the sky is listening." if shrine else "Find a shrine to kindle or swap (sparks travel fine in a pack).",
		UiTheme.SMALL, UiTheme.GOLD if shrine else UiTheme.STARLIGHT.darkened(0.3))
	side.add_child(where)
	var gap := Control.new()
	gap.custom_minimum_size.y = 8
	side.add_child(gap)
	side.add_child(UiTheme.label("Loose sparks", UiTheme.BODY, UiTheme.STARLIGHT, true))
	var loose := loose_sparks()
	if loose.is_empty():
		side.add_child(UiTheme.label("None in your pack. Elites and champions carry them.", UiTheme.SMALL, UiTheme.STARLIGHT.darkened(0.3)))
	for i: int in loose:
		var it := gu.items.item(i)
		var sp: Dictionary = it["spark"]
		var b := UiTheme.button("%s %s   %s" % [Sparks.spark_name(String(sp["id"])), Sparks.rank_name(int(sp["rank"])), ItemText.spark_effect(String(sp["id"]), int(sp["rank"]))], UiTheme.SMALL)
		b.icon = ItemIcons.texture(it)
		b.add_theme_constant_override("icon_max_width", 24)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.custom_minimum_size = Vector2(450, 30)
		if i == chosen:
			b.add_theme_stylebox_override("normal", UiTheme.button_box(UiTheme.GOLD))
		b.pressed.connect(func() -> void:
			chosen = -1 if chosen == i else i
			refresh())
		side.add_child(b)
	if chosen >= 0:
		var row := HBoxContainer.new()
		var k := UiTheme.button("Kindle into an empty slot", UiTheme.BODY)
		k.disabled = not shrine or con.size() >= con.slots
		k.pressed.connect(func() -> void:
			gu.items.kindle(chosen)
			chosen = -1)
		row.add_child(k)
		side.add_child(row)
		side.add_child(UiTheme.label("...or click a star to swap it for this one." if con.size() > 0 else "", UiTheme.SMALL, UiTheme.STARLIGHT.darkened(0.2)))

func _star_at(p: Vector2) -> int:
	var stars: Array = _lay.get("stars", [])
	for i in stars.size():
		if (stars[i] as Vector2).distance_to(p) < 14.0:
			return i
	return -1

func _sky_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var i := _star_at((event as InputEventMouseMotion).position)
		if i != _hover:
			_hover = i
			sky.queue_redraw()
		if i >= 0:
			var k: Dictionary = gu.items.constellation.kindled[i]
			var id := String(k["id"])
			tip.show_lines([["%s %s" % [Sparks.spark_name(id), Sparks.rank_name(int(k["rank"]))], "title"],
				[String(Sparks.row(id).get("group", "")).capitalize() + " spark, star %d" % (i + 1), "sub"],
				[String(Sparks.row(id).get("text", "")), "magic"], [ItemText.spark_effect(id, int(k["rank"])), "good"]],
				sky.position + panel.position + (event as InputEventMouseMotion).position)
		else:
			tip.hide_tip()
	elif event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var i := _star_at((event as InputEventMouseButton).position)
		if i >= 0 and chosen >= 0:
			gu.items.swap_spark(i, chosen)
			chosen = -1

func _draw_sky() -> void:
	var r := Rect2(Vector2.ZERO, SKY)
	sky.draw_rect(r, UiTheme.NIGHT_DEEP)
	for d: Array in _dust:
		sky.draw_circle(d[0], d[1], Color(UiTheme.STARLIGHT, d[2]))
	var stars: Array = _lay.get("stars", [])
	var ghosts: Array = _lay.get("ghosts", [])
	for g: Vector2 in ghosts:
		sky.draw_arc(g, 6.0, 0, TAU, 16, Color(UiTheme.STARLIGHT, 0.22), 1.2, true)
	for l: Array in _lay.get("lines", []):
		var a: Vector2 = stars[l[0]]
		var b: Vector2 = stars[l[1]]
		sky.draw_line(a, b, Color(UiTheme.STARLIGHT, 0.18), 6.0, true)
		sky.draw_line(a, b, Color(UiTheme.STARLIGHT, 0.85), 2.0, true)
	var kindled: Array = gu.items.constellation.kindled if gu.items != null else []
	for i in stars.size():
		var rank := int(kindled[i]["rank"]) if i < kindled.size() else 0
		var g := String(Sparks.row(String(kindled[i]["id"])).get("group", "motion")) if i < kindled.size() else "motion"
		var col: Color = ItemIcons.SPARK_GROUP_COLORS.get(g, UiTheme.GOLD)
		var size := 9.0 + rank * 3.0 + (3.0 if i == _hover else 0.0)
		sky.draw_circle(stars[i], size * 1.4, Color(col, 0.18))
		UiTheme.star(sky, stars[i], size, size * 0.32, col, 4, UiTheme.INK)
		sky.draw_circle(stars[i], 2.2, Color(1, 1, 0.95))
	sky.draw_rect(r, UiTheme.STARLIGHT.darkened(0.4), false, 2.0)
	if stars.is_empty():
		UiTheme.text(sky, Vector2(0, SKY.y * 0.5), "No stars yet. Kindle a spark at a shrine.", UiTheme.BODY, Color(UiTheme.STARLIGHT, 0.6), false, HORIZONTAL_ALIGNMENT_CENTER, SKY.x)
