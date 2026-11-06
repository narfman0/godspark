## Nameplates with a thin hit point bar, drawn over the world: other players always (name and
## hit points, "down" when downed), monsters while in a fight (hurt, or seen acting in the last
## few seconds), under the cursor, or engaged (what the next swing would land on). Rank changes the frame (elite: a double blue rule,
## champion: gold with a star, boss: vermilion with points; minions have a plain thin one);
## affix names sit under the name. Rank and affixes come from the monsters client's
## monster_info(id, info) signal when that system exists, else from look.rank, else none.
## A pool of CAP custom-drawn Controls. A crowd never makes a tower: plates step up over each
## other at most STACK high; whoever finds no room there gets a short bar over its head with no
## name (BAR_ROWS high), and past that nothing. The one under the cursor, players and ranked
## foes choose first, then the nearest.
class_name Nameplates
extends Control

const CAP := 24
const FIGHT_SECS := 8.0
const W := 180.0
const H := 44.0
## How many name plates high a stack may be.
const STACK := 3
## The compact form: a bar with no name, and how many rows of them.
const BAR_W := 64.0
const BAR_H := 10.0
const BAR_ROWS := 3
const GAP := 2.0

var fx: FxView
var plates: Array[Control] = []
## id -> {rank, affixes: [String]} (monsters client or look)
var info := {}
## id -> msec of the last combat activity seen
var active := {}
var _data: Array = []    # per plate: {id, name, hp, max, rank, affixes, player, downed}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in CAP:
		var c := Control.new()
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.size = Vector2(W, H)
		c.visible = false
		c.draw.connect(_draw_plate.bind(c, i))
		add_child(c)
		plates.append(c)
		_data.append({})

func touch(id: int) -> void:
	active[id] = Time.get_ticks_msec()

func set_info(id: int, d: Dictionary) -> void:
	var cur: Dictionary = info.get(id, {})
	cur.merge(d, true)
	info[id] = cur

func forget(id: int) -> void:
	info.erase(id)
	active.erase(id)

func step(cam: Camera3D, hovered: int, engaged := 0) -> void:
	var cw := fx.cw
	if cam == null or cw == null:
		return
	var now := Time.get_ticks_msec()
	var me := cw.view_pos()
	var cand: Array = []
	var lc := cw.system(HostSystem.LIFE) as LifeClient
	for r: ClientWorld.RemoteEntity in cw.remotes.values():
		var player := r.kind == HostEntity.Kind.PLAYER
		if not player:
			if r.max_hp <= 0 or r.hp <= 0:
				continue
			var fighting := r.hp < r.max_hp or now - int(active.get(r.id, -100000)) < FIGHT_SECS * 1000.0
			# Life's calm people get the interface's name plate on hover (GameUi PeopleMarks)
			if not fighting and r.id != engaged and (r.id != hovered or (lc != null and lc.is_person(r.id))):
				continue
		var first := priority(r.id == hovered or r.id == engaged, player, String(info.get(r.id, {}).get("rank", "")))
		cand.append([first, r.pos.distance_squared_to(me), r])
	cand.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var sc := UiTheme.scale_for(get_viewport().get_visible_rect().size)
	var rules := cw.system(HostSystem.RULES) as RulesClient
	var want: Array = []
	for row: Array in cand.slice(0, CAP):
		var r: ClientWorld.RemoteEntity = row[2]
		var top := Vector3(r.pos.x * K.TILE_M, (r.pos.y + r.size.y) * K.TILE_M + 0.25, 0.0)
		if cam.is_position_behind(top):
			continue
		var sp := cam.unproject_position(top)
		var inf: Dictionary = info.get(r.id, {})
		var affs: Array = inf.get("affixes", [])
		var nm := r.name
		var pre := " ".join(PackedStringArray(affs)) + " "
		if not affs.is_empty() and nm.begins_with(pre):
			nm = nm.substr(pre.length())    # the host's name leads with the affixes: they sit under it here
		var d := {"id": r.id, "name": nm, "hp": r.hp, "max": r.max_hp, "rank": String(inf.get("rank", "")),
			"affixes": affs, "player": r.kind == HostEntity.Kind.PLAYER,
			"downed": rules != null and rules.is_downed(r.id)}
		want.append({"at": sp, "tall": H if affs.is_empty() else 60.0, "d": d})
	var spots := arrange(want, sc)
	for i in CAP:
		var c := plates[i]
		if i >= spots.size() or (spots[i] as Dictionary).is_empty():
			c.visible = false
			continue
		var box: Rect2 = spots[i]["box"]
		var d: Dictionary = want[i]["d"]
		d["bar"] = spots[i]["bar"]
		c.scale = Vector2(sc, sc)
		c.position = Vector2(box.get_center().x - W * 0.5 * sc, box.end.y - H * sc)
		if d != _data[i]:
			_data[i] = d
			c.queue_redraw()
		c.visible = true

## Who chooses a place first (lower is sooner): under the cursor, players, ranked foes, the rest.
static func priority(hovered: bool, player: bool, rank: String) -> int:
	if hovered:
		return 0
	if player:
		return 1
	return 2 if rank in ["boss", "champion", "elite"] else 3

## Places for plates. want: in order of priority, [{at: the point over the head, tall}] (unscaled
## height). Returns one per want: {box: Rect2 on screen, bar: true for the compact form}, or {}
## for none. Name plates step up over each other at most STACK high; the rest are bars at their
## heads, with the names lifted clear of them.
static func arrange(want: Array, sc: float) -> Array:
	var out: Array = []
	var named: Array[Rect2] = []
	for w: Dictionary in want:
		var tall := float(w["tall"]) * sc
		var lifted: Variant = _lift(_above(w["at"], W * sc, tall), named, (STACK - 1) * (tall + GAP))
		if lifted != null:
			named.append(lifted)
		out.append({"bar": lifted == null})
	var taken: Array[Rect2] = []
	for i in want.size():
		if bool(out[i]["bar"]):
			var lifted: Variant = _lift(_above(want[i]["at"], BAR_W * sc, BAR_H * sc), taken, (BAR_ROWS - 1) * (BAR_H * sc + GAP))
			if lifted == null:
				out[i] = {}
			else:
				taken.append(lifted)
				out[i]["box"] = lifted
	# the names again, over the bars (STACK bounds them already: this rise is only the bars')
	for i in want.size():
		if not (out[i] as Dictionary).is_empty() and not bool(out[i]["bar"]):
			var box: Rect2 = _lift(_above(want[i]["at"], W * sc, float(want[i]["tall"]) * sc), taken, INF)
			taken.append(box)
			out[i]["box"] = box
	return out

## A box of this size centred over a point, its bottom edge there.
static func _above(at: Vector2, w: float, h: float) -> Rect2:
	return Rect2(at.x - w * 0.5, at.y - h, w, h)

## The box moved up until it touches none of `placed`, or null if that takes more than `rise`.
static func _lift(box: Rect2, placed: Array[Rect2], rise: float) -> Variant:
	var y0 := box.position.y
	var moved := true
	while moved:
		moved = false
		for o: Rect2 in placed:
			if o.intersects(box):
				box.position.y = o.position.y - box.size.y - GAP
				moved = true
		if y0 - box.position.y > rise + 0.01:
			return null
	return box

## A name that fits the plate: shortened at a word where it can be, "..." at the end.
static func fit(s: String, size: int, w: float) -> String:
	if UiTheme.text_width(s, size) <= w:
		return s
	var words := s.split(" ")
	while words.size() > 1:
		words.remove_at(words.size() - 1)
		var t := " ".join(words) + "..."
		if UiTheme.text_width(t, size) <= w:
			return t
	var t := s
	while t.length() > 3 and UiTheme.text_width(t + "...", size) > w:
		t = t.substr(0, t.length() - 1)
	return t + "..."

## Frame colour and weight for a rank.
static func rank_style(rank: String) -> Dictionary:
	match rank:
		"elite":
			return {"color": UiTheme.SKY, "width": 2.0, "double": true, "label": "Elite"}
		"champion":
			return {"color": UiTheme.GOLD, "width": 3.0, "double": true, "label": "Champion", "star": true}
		"boss":
			return {"color": UiTheme.VERMILION, "width": 3.0, "double": true, "label": "Boss", "points": true}
		"minion":
			return {"color": UiTheme.INK_SOFT, "width": 1.0, "double": false, "label": ""}
	return {"color": UiTheme.INK, "width": 1.5, "double": false, "label": ""}

func _draw_plate(c: Control, i: int) -> void:
	var d: Dictionary = _data[i]
	if d.is_empty():
		return
	var st := rank_style(String(d["rank"]))
	var frac := float(d["hp"]) / maxf(1.0, float(d["max"]))
	var col := UiTheme.MOSS if bool(d["player"]) else UiTheme.VERMILION
	if bool(d["downed"]):
		col = UiTheme.INK_SOFT
	if bool(d.get("bar", false)):
		var short := Rect2((W - BAR_W) * 0.5, H - BAR_H + 2.0, BAR_W, BAR_H - 4.0)
		c.draw_rect(short, UiTheme.INK_SOFT)
		c.draw_rect(Rect2(short.position, Vector2(short.size.x * clampf(frac, 0, 1), short.size.y)), col)
		c.draw_rect(short, st["color"], false, 1.0)
		return
	var nm := String(d["name"])
	if String(st["label"]) != "":
		nm = "%s %s" % [st["label"], nm]
	var affixes: Array = d["affixes"]
	var bar := Rect2(10, H - 10, W - 20, 7)
	c.draw_rect(Rect2(bar.position + Vector2(1.5, 1.5), bar.size), UiTheme.SHADOW)
	c.draw_rect(bar, UiTheme.INK_SOFT)
	c.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(frac, 0, 1), bar.size.y)), col)
	var bc: Color = st["color"]
	c.draw_rect(bar, bc, false, float(st["width"]))
	if bool(st["double"]):
		c.draw_rect(bar.grow(2.5), bc, false, 1.0)
	if st.has("star"):
		UiTheme.star(c, Vector2(bar.position.x - 6, bar.get_center().y), 7, 2.5, UiTheme.GOLD, 4, UiTheme.INK)
	if st.has("points"):
		for s: int in [-1, 1]:
			var x := bar.get_center().x + s * (bar.size.x * 0.5 + 4)
			c.draw_colored_polygon(PackedVector2Array([Vector2(x, bar.position.y - 3), Vector2(x + s * 7, bar.get_center().y), Vector2(x, bar.end.y + 3)]), UiTheme.VERMILION)
	var fs := UiTheme.SMALL
	var down := "  (down)" if bool(d["downed"]) else ""
	nm = fit(nm, fs, W - 8.0 - UiTheme.text_width(down, fs)) + down
	UiTheme.text(c, Vector2(0, bar.position.y - 4), nm, fs, UiTheme.TEXT_LIGHT if String(d["rank"]) in ["", "minion"] else bc.lightened(0.3),
		false, HORIZONTAL_ALIGNMENT_CENTER, W, 4)
	if not affixes.is_empty():
		UiTheme.text(c, Vector2(0, bar.position.y - 20), fit(", ".join(affixes), UiTheme.TINY, W - 8.0), UiTheme.TINY, UiTheme.STARLIGHT, false, HORIZONTAL_ALIGNMENT_CENTER, W, 3)
