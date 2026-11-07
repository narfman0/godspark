## The world map (M): the world as a long strip seen side-on, drawn from what the client is
## told, never from tiles: the surface line and the depth bands (META), the places the player
## knows (stood at, or named in a rumour or a quest: those drawn faint, "heard of"), roads and
## deep roads along their route paths between known places (ATLAS), the pinned quest's mark,
## rumour pins, you and the other players in view, and travelling parties only while you can
## see them. Hover a place for its card: name, people, faction and your standing there, its
## state, the last news you heard of it, the work that points at it. Drag to pan, wheel to
## zoom, Home to find yourself. Redraws on change and twice a second for moving things.
## The land itself is common knowledge: the biomes' colours along the ground with their
## regions' names, ranges and rivers with theirs, and the crossings (MapLogic.land_labels and
## crossings), hover one for its name.
class_name WorldMapScreen
extends UiScreen

const MAP_RECT := Rect2(20, 62, 880, 520)
const CARD_X := 916.0
const BANDS := {"sky": Color(0.75, 0.85, 0.95, 0.35), "surface": Color(0.55, 0.7, 0.4, 0.18), "caves": Color(0.45, 0.35, 0.25, 0.22),
	"deeps": Color(0.3, 0.22, 0.35, 0.28), "nadir": Color(0.45, 0.15, 0.12, 0.3)}
const ROUTE_STYLE := {"road": [Color("8a5a2b"), 3.0], "deep_road": [Color("6a4a8a"), 2.5]}
const BIOME_TINT := {"meadow": Color("8cc152"), "forest": Color("2f7d3a"), "mountain": Color("9a9aa2"), "desert": Color("e5c77f"),
	"swamp": Color("5a6b3a")}
const RIVER := Color("3f7fb0")
## Underground regions, drawn once seen (M6).
const REGION_TINT := {"underdark": Color("55556a"), "fungal": Color("a070d8"), "crystal": Color("8fd0ff"), "deep_lake": Color("3f7fd0"),
	"magma": Color("e0602a")}
## Where a land label may go, px down from its place, when something is in the way.
const LABEL_STEPS := {"region": [0.0, -16.0, -32.0], "range": [0.0, -16.0, -32.0], "river": [0.0, 16.0, 32.0, -36.0]}

var dc: DealsClient
var lc: LifeClient
var canvas: Control
var card: VBoxContainer
var zoom := 0.4
var origin := Vector2.ZERO
var hover := -1
var _sites_px := {}
var _drag := false
var _drag_from := Vector2.ZERO
var _fit := 0.4
var _t := 0.0
var _placed := false

func _init() -> void:
	title = "The world, as you know it"
	hint = "Drag: pan   Wheel: zoom   Home: find yourself   Hover a place: what you know of it   Esc or M: close"
	panel_size = Vector2(1200, 630)

func build() -> void:
	canvas = Control.new()
	canvas.position = MAP_RECT.position
	canvas.size = MAP_RECT.size
	canvas.clip_contents = true
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.draw.connect(_draw_map)
	canvas.gui_input.connect(_map_input)
	canvas.mouse_exited.connect(func() -> void:
		hover = -1
		_card())
	panel.add_child(canvas)
	card = VBoxContainer.new()
	card.position = Vector2(CARD_X, 62)
	card.custom_minimum_size = Vector2(panel_size.x - CARD_X - 20, 0)
	card.size = Vector2(panel_size.x - CARD_X - 20, MAP_RECT.size.y)
	card.add_theme_constant_override("separation", 4)
	panel.add_child(card)

func attach() -> void:
	dc = gu.cw.system(HostSystem.DEALS) as DealsClient
	lc = gu.cw.system(HostSystem.LIFE) as LifeClient
	if dc != null:
		dc.atlas_changed.connect(func(_f: Array) -> void: _changed())
		dc.rumour_heard.connect(func(_r: Array) -> void: _changed())
		dc.rumours_reset.connect(_changed)
		dc.quests_changed.connect(func(_q: Array) -> void: _changed())

func _changed() -> void:
	if visible:
		canvas.queue_redraw()
		_card()

func world_size() -> Vector2:
	var w := gu.cw.world
	return Vector2(w.width, w.height)

func refresh() -> void:
	if not visible:
		return
	_fit = MapLogic.fit_zoom(world_size(), MAP_RECT.size)
	if not _placed:
		_placed = true
		zoom = minf(_fit * 2.5, 6.0)
		origin = MapLogic.origin_for(gu.cw.body.center(), world_size(), zoom, MAP_RECT.size)
	canvas.queue_redraw()
	_card()

func _process(dt: float) -> void:
	if not visible:
		return
	_t -= dt
	if _t <= 0.0:
		_t = 0.5
		canvas.queue_redraw()

func find_me() -> void:
	origin = MapLogic.origin_for(gu.cw.body.center(), world_size(), zoom, MAP_RECT.size)
	canvas.queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_HOME:
		find_me()
		get_viewport().set_input_as_handled()

func _map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				zoom_at(mb.position, 1.25 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8)
			canvas.accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = mb.pressed
			_drag_from = mb.position
			canvas.accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag:
			origin += mm.position - _drag_from
			_drag_from = mm.position
			_clamp()
			canvas.queue_redraw()
		var h := MapLogic.pick(_sites_px, mm.position, 12.0)
		if h != hover:
			hover = h
			_card()
			canvas.queue_redraw()

func zoom_at(p: Vector2, k: float) -> void:
	var cell := MapLogic.from_map(p, world_size().y, zoom, origin)
	zoom = clampf(zoom * k, _fit, 6.0)
	origin = p - Vector2(cell.x, world_size().y - cell.y) * zoom
	_clamp()
	canvas.queue_redraw()

func _clamp() -> void:
	var size := world_size() * zoom
	var v := MAP_RECT.size
	origin.x = clampf(origin.x, v.x - size.x, 0.0) if size.x > v.x else (v.x - size.x) * 0.5
	origin.y = clampf(origin.y, v.y - size.y, 0.0) if size.y > v.y else (v.y - size.y) * 0.5

func _p(cell: Vector2) -> Vector2:
	return MapLogic.to_map(cell, world_size().y, zoom, origin)

## What the player knows of now.
func known() -> Dictionary:
	if dc == null:
		return {}
	return MapLogic.discovered(dc.seen, dc.rumours, dc.quests)

# --- drawing ----------------------------------------------------------------------------------------

func _draw_map() -> void:
	var c := canvas
	var meta: Dictionary = gu.cw.world.meta
	var wh := world_size().y
	c.draw_rect(Rect2(Vector2.ZERO, c.size), UiTheme.PARCHMENT.lightened(0.05))
	# depth bands
	var bands: Dictionary = meta.get("bands", {})
	for b: String in bands:
		var yr: Array = bands[b]
		var top := _p(Vector2(0, float(yr[1]) + 1)).y
		var bot := _p(Vector2(0, float(yr[0]))).y
		c.draw_rect(Rect2(origin.x, top, world_size().x * zoom, bot - top), BANDS.get(b, Color(0, 0, 0, 0.05)))
		if bot - top > 18:
			UiTheme.text(c, Vector2(6, clampf(top + 16, 14, c.size.y - 4)), b.capitalize(), UiTheme.TINY, Color(UiTheme.INK_SOFT, 0.8), true)
	# the ground: under the surface line
	var surf: Array = meta.get("surface", [])
	if not surf.is_empty():
		var line := MapLogic.surface_line(surf, wh, zoom, origin, maxi(1, roundi(3.0 / zoom)))
		var poly := line.duplicate()
		poly.append(_p(Vector2(surf.size() - 1, 0)))
		poly.append(_p(Vector2(0, 0)))
		c.draw_colored_polygon(poly, Color(UiTheme.PARCH_DEEP, 0.28))
		c.draw_polyline(line, UiTheme.INK_SOFT, 1.6, true)
	var kn := known()
	_draw_land(c, meta, _place_boxes(meta, kn))
	# roads between known places
	if dc != null:
		for r: Dictionary in MapLogic.known_routes(dc.routes, kn):
			var st: Array = ROUTE_STYLE.get(String(r["kind"]), [UiTheme.INK_SOFT, 2.0])
			var pl := MapLogic.polyline(r["path"], wh, zoom, origin, 3.0)
			if pl.size() >= 2:
				c.draw_polyline(pl, Color(UiTheme.INK, 0.5), float(st[1]) + 2.0, true)
				c.draw_polyline(pl, st[0], float(st[1]), true)
	# places
	_sites_px.clear()
	for s: Dictionary in meta.get("sites", []):
		var sid := int(s["id"])
		if not kn.has(sid):
			continue
		var p := _p(Vector2(float(s["x"]), float(s["y"])))
		_sites_px[sid] = p
		var faint := String(kn[sid]) == "heard"
		var a: Dictionary = dc.sites.get(sid, {}) if dc != null else {}
		var kind := String(s["kind"])
		if sid == hover:
			c.draw_circle(p + Vector2(0, -6), 16, Color(UiTheme.GOLD, 0.35))
		if kind == "settlement" and not bool(a.get("ruin", false)) and a.has("tier"):
			Emblems.settlement(c, p, String(a.get("culture", "")), MapLogic.tier_n(String(a.get("tier", ""))), faint)
		elif kind == "lair":
			Emblems.lair(c, p, bool(a.get("apex", false)), faint)
		elif kind == "portal":
			Emblems.portal(c, p, faint)
		else:
			Emblems.ruin(c, p, faint)
		var nm := _place_name(s, a, faint)
		if nm != "":
			var w := UiTheme.text_width(nm, UiTheme.TINY)
			UiTheme.text(c, p + Vector2(-w * 0.5, 14), nm, UiTheme.TINY, Color(UiTheme.INK, 0.55 if faint else 1.0), false,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 0)
	# rumour pins (the marked ones)
	if dc != null and gu.deals_ui != null:
		var pinned_at := {}
		for r: Dictionary in dc.map_marks():
			var sid := int(r["site"])
			if gu.deals_ui.is_marked(int(r["id"])) and _sites_px.has(sid) and not pinned_at.has(sid):
				pinned_at[sid] = true
				var p: Vector2 = _sites_px[sid] + Vector2(10, -18)
				c.draw_line(p, p + Vector2(-6, 10), UiTheme.INK, 1.5)
				UiTheme.ink_rect(c, Rect2(p - Vector2(5, 7), Vector2(10, 8)), UiTheme.PARCHMENT, UiTheme.INK, 1.2, false)
	# parties you can see (Life's people in view, grouped by party)
	if lc != null:
		var parties := {}
		for id: int in lc.people:
			var pp: Dictionary = lc.people[id]
			var r: ClientWorld.RemoteEntity = gu.cw.remotes.get(id)
			if String(pp.get("kind", "")) != "party" or r == null:
				continue
			var pid := int(pp.get("of", -1))
			if not parties.has(pid):
				parties[pid] = {"sum": Vector2.ZERO, "n": 0, "kind": String(pp.get("party", ""))}
			parties[pid]["sum"] += r.pos
			parties[pid]["n"] += 1
		for pid: int in parties:
			var d: Dictionary = parties[pid]
			var p := _p(d["sum"] / float(d["n"]))
			var hostile := String(d["kind"]) in ["raid", "army", "pack"]
			c.draw_circle(p + Vector2(1, 1), 6, UiTheme.SHADOW)
			c.draw_circle(p, 6, UiTheme.VERMILION if hostile else UiTheme.GOLD)
			c.draw_arc(p, 6, 0, TAU, 14, UiTheme.INK, 1.5, true)
			Emblems.role_icon(c, p, 4.0, "raider" if hostile else "wagon", UiTheme.INK)
	# the pinned quest
	if gu.deals_ui != null and gu.deals_ui.pinned != "" and dc != null:
		for q: Dictionary in dc.quests:
			if String(q["id"]) == gu.deals_ui.pinned:
				var tgt := MapLogic.quest_target(q, meta) if String(q.get("state", "")) != "ready" else MapLogic.site_xy(meta, int(q.get("site", -1)))
				if tgt != Vector2.INF:
					var tp := _p(tgt)
					c.draw_dashed_line(_p(gu.cw.body.center()), tp, Color(UiTheme.VERMILION, 0.7), 1.5, 6.0)
					c.draw_line(tp + Vector2(-7, -7), tp + Vector2(7, 7), UiTheme.VERMILION, 3.5)
					c.draw_line(tp + Vector2(-7, 7), tp + Vector2(7, -7), UiTheme.VERMILION, 3.5)
	# other players in view, then you
	for r: ClientWorld.RemoteEntity in gu.cw.remotes.values():
		if r.kind == HostEntity.Kind.PLAYER:
			var p := _p(r.pos)
			c.draw_circle(p, 5, UiTheme.SKY)
			c.draw_arc(p, 5, 0, TAU, 12, UiTheme.INK, 1.5, true)
			UiTheme.text(c, p + Vector2(8, 4), r.name.capitalize(), UiTheme.TINY, UiTheme.INK)
	var me := _p(gu.cw.body.center())
	UiTheme.star(c, me, 10, 4, UiTheme.VERMILION, 4, UiTheme.INK, PI / 4.0)
	UiTheme.text(c, me + Vector2(10, -8), "you", UiTheme.TINY, UiTheme.BLOOD_DARK)
	c.draw_rect(Rect2(Vector2.ZERO, c.size), UiTheme.INK, false, 2.0)
	# legend
	UiTheme.text(c, Vector2(c.size.x - 290, c.size.y - 8), "faint: heard of     X: pinned work     pin: a rumour", UiTheme.TINY, UiTheme.INK_SOFT)

## The name a known place shows at this zoom, "" for none.
func _place_name(s: Dictionary, a: Dictionary, faint: bool) -> String:
	if zoom >= _fit * 1.6 or int(s["id"]) == hover or not faint and String(s["kind"]) == "settlement":
		return String(a.get("name", ""))
	return ""

## The screen boxes of the known places' emblems and names: drawn over the land, so the land's
## own names keep off them.
func _place_boxes(meta: Dictionary, kn: Dictionary) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for s: Dictionary in meta.get("sites", []):
		var sid := int(s["id"])
		if not kn.has(sid):
			continue
		var p := _p(Vector2(float(s["x"]), float(s["y"])))
		out.append(Rect2(p - Vector2(11, 18), Vector2(22, 22)))
		var a: Dictionary = dc.sites.get(sid, {}) if dc != null else {}
		var nm := _place_name(s, a, String(kn[sid]) == "heard")
		if nm != "":
			var w := UiTheme.text_width(nm, UiTheme.TINY)
			out.append(Rect2(p + Vector2(-w * 0.5, 2), Vector2(w, 14)))
	return out

## The land's own marks: a band of each biome's colour under the ground line, rivers, crossings,
## and the names, which take the size of what they name. taken: the boxes they keep off.
func _draw_land(c: Control, meta: Dictionary, taken: Array[Rect2]) -> void:
	var surf: Array = meta.get("surface", [])
	var kn := known()
	var labels := MapLogic.land_labels(meta).filter(func(l: Dictionary) -> bool:
		return not l.has("band") or kn.get(MapLogic.region_key(int(l["i"])), "") == "seen")
	for l: Dictionary in labels:
		if l.has("band"):
			# an underground region the player has been in: its span tinted at its depth
			var col: Color = REGION_TINT.get(String(l.get("biome", "")), UiTheme.INK_SOFT)
			var a := _p(Vector2(float(l["x0"]), float(l["y1"])))
			var b := _p(Vector2(float(l["x1"]) + 1.0, float(l["y0"])))
			c.draw_rect(Rect2(a, b - a), Color(col, 0.22))
			c.draw_rect(Rect2(a, b - a), Color(col, 0.6), false, 1.5)
		elif l["kind"] == "region" and not surf.is_empty():
			var col: Color = BIOME_TINT.get(String(l.get("biome", "")), UiTheme.INK_SOFT)
			var line := PackedVector2Array()
			var step := maxi(1, roundi(6.0 / zoom))
			for x in range(int(l["x0"]), mini(int(l["x1"]), surf.size() - 1), step):
				line.append(_p(Vector2(x, float(surf[x]) - 6.0 / zoom)))
			if line.size() >= 2:
				c.draw_polyline(line, Color(col, 0.75), 7.0, true)
		elif l["kind"] == "river":
			var a := _p(Vector2(float(l["x0"]), float(l["y"])))
			var b := _p(Vector2(float(l["x1"]), float(l["y"])))
			c.draw_line(a, b, RIVER, maxf(3.0, 8.0 * zoom))
	for x: Dictionary in MapLogic.crossings(meta):
		var p := _p(Vector2(float(x["x"]), float(x["y"])))
		match String(x["kind"]):
			"pass":
				c.draw_polyline(PackedVector2Array([p + Vector2(-6, 4), p + Vector2(0, -4), p + Vector2(6, 4)]), UiTheme.INK, 2.5, true)
			"under":
				c.draw_arc(p, 6.0, PI, TAU, 10, UiTheme.INK, 2.0, true)
			"bridge":
				c.draw_line(p + Vector2(-7, -2), p + Vector2(7, -2), UiTheme.INK, 3.0)
			_:
				for k: int in [-5, 0, 5]:
					c.draw_circle(p + Vector2(k, -1), 1.6, UiTheme.INK)
	for x: Dictionary in MapLogic.crossings(meta):
		if zoom >= _fit * 1.6 and String(x["kind"]) in ["pass", "bridge", "ford"]:
			var p := _p(Vector2(float(x["x"]), float(x["y"])))
			if p.x >= 0.0 and p.x <= c.size.x:
				_label(c, String(x["kind"]).capitalize(), p + Vector2(0, -8), UiTheme.TINY, UiTheme.INK_SOFT)
	var shown: Array = taken.duplicate()
	for kind: String in ["region", "range", "river"]:
		for l: Dictionary in labels:
			if l["kind"] != kind:
				continue
			var name_ := String(l["name"]).trim_prefix("the ")
			if _p(Vector2(float(l["x1"]), 0.0)).x < 0.0 or _p(Vector2(float(l["x0"]), 0.0)).x > c.size.x:
				continue                 # none of it is on the map at this zoom
			var at := _p(Vector2(float(l["x"]), float(l["y"])))
			var size := UiTheme.BODY if kind != "river" else UiTheme.SMALL
			var col: Color = UiTheme.INK if kind == "region" else (UiTheme.INK_SOFT if kind == "range" else RIVER.darkened(0.35))
			var y := at.y - (34.0 if kind == "region" and not l.has("band") else (12.0 if kind != "river" else -18.0))
			var w := UiTheme.text_width(name_, size)
			var box := Rect2(MapLogic.fit_x(at.x, w, c.size.x), y - 14.0, w, 16.0)
			var dy := MapLogic.free_row(box, shown, LABEL_STEPS[kind])
			if is_nan(dy):
				continue
			shown.append(Rect2(box.position + Vector2(0.0, dy), box.size))
			_label(c, name_, Vector2(at.x, y + dy), size, col)

## Text centred on at, kept inside the map.
func _label(c: Control, s: String, at: Vector2, size: int, col: Color) -> void:
	var x := MapLogic.fit_x(at.x, UiTheme.text_width(s, size), c.size.x)
	UiTheme.text(c, Vector2(x, at.y), s, size, col, false, HORIZONTAL_ALIGNMENT_LEFT, -1, 0)

# --- the card -----------------------------------------------------------------------------------------

func _card() -> void:
	for ch in card.get_children():
		card.remove_child(ch)
		ch.queue_free()
	if dc == null:
		return
	var w := card.custom_minimum_size.x
	if hover < 0:
		card.add_child(UiTheme.label("Places you know", UiTheme.HEADING, UiTheme.INK, true))
		var kn := known()
		var seen_n := kn.values().count("seen")
		card.add_child(_wrap("%d visited, %d heard of. Talk to people to hear of more; walk the roads to see them." % [seen_n, kn.size() - seen_n], w))
		if gu.deals_ui != null and gu.deals_ui.pinned != "":
			for q: Dictionary in dc.quests:
				if String(q["id"]) == gu.deals_ui.pinned:
					card.add_child(UiTheme.label("Pinned", UiTheme.HEADING, UiTheme.INK, true))
					card.add_child(_wrap("%s: %s" % [q.get("title", ""), DealsLogic.progress_text(q)], w))
		return
	var a: Dictionary = dc.sites.get(hover, {})
	var kn2 := known()
	var nm := String(a.get("name", ""))
	var kind := String(a.get("kind", ""))
	if nm == "":
		nm = {"lair": "A lair", "portal": "The portal", "ruin": "A ruin"}.get(kind, "A ruin" if bool(a.get("ruin", false)) else "A place")
	card.add_child(_wrap(nm, w, UiTheme.HEADING + 2, UiTheme.INK, true))
	if String(kn2.get(hover, "")) == "heard":
		card.add_child(_wrap("Heard of, never seen.", w, UiTheme.SMALL, UiTheme.INK_SOFT))
	if kind == "settlement" and a.has("tier") and not bool(a.get("ruin", false)):
		card.add_child(_wrap(DealsLogic.cap(DealsLogic.place_line(a)) + ".", w))
		var f := String(a.get("faction", ""))
		var fname := gu.deals_ui.faction_name(f) if gu.deals_ui != null else ""
		var v := lc.standing(f) if lc != null else 0
		card.add_child(_wrap("%s. Your standing %d: %s; their guards are %s." % [fname, v, DealsLogic.standing_word(v).to_lower(),
			DealsLogic.guards_word(v)], w))
		var sl := DealsLogic.state_line(a)
		card.add_child(_wrap("%s. %s" % [sl[0], sl[1]], w, UiTheme.SMALL, UiTheme.INK_SOFT))
	elif kind == "lair":
		card.add_child(_wrap("Something lives there%s." % (", and it is hungry for more than mice" if bool(a.get("apex", false)) else ""), w))
	elif bool(a.get("ruin", false)) or kind == "ruin":
		card.add_child(_wrap("Fallen stones. Someone lived here once.", w))
	var news := ""
	for r: Dictionary in dc.rumours:
		if int(r.get("site", -1)) == hover:
			news = String(r.get("text", ""))
	if news != "":
		card.add_child(UiTheme.label("Last you heard", UiTheme.BODY, UiTheme.INK, true))
		card.add_child(_wrap(news, w, UiTheme.SMALL))
	var work: Array = []
	for q: Dictionary in dc.quests:
		if String(q.get("state", "")) in ["active", "ready"] and (int(q.get("target_site", -1)) == hover or int(q.get("site", -1)) == hover):
			work.append(String(q.get("title", "")))
	if not work.is_empty():
		card.add_child(UiTheme.label("Your work", UiTheme.BODY, UiTheme.INK, true))
		card.add_child(_wrap(", ".join(PackedStringArray(work)), w, UiTheme.SMALL))
	var xy := MapLogic.site_xy(gu.cw.world.meta, hover)
	if xy != Vector2.INF:
		card.add_child(_wrap("From here: %s." % String(DealsLogic.bearing(gu.cw.body.center(), xy)["text"]), w, UiTheme.SMALL, UiTheme.INK_SOFT))

func _wrap(s: String, w: float, sz := UiTheme.SMALL, col := UiTheme.INK, display := false) -> Label:
	var l := UiTheme.label(s, sz, col, display)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = w
	return l
