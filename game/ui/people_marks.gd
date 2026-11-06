## The living world over people's heads, drawn on one interface canvas (no per-person nodes):
##   - a small mark over people who sell (coin), smith (anvil), have work on offer (vermilion
##     diamond), work of yours to hand in (green tick), or are your patron's (plum star)
##   - the talk prompt over the nearest person E would talk to ("E: talk to Dunton, merchant")
##   - a name plate (name, role) over a person under the mouse
##   - a party plate over a caravan, raid or patrol the client can see ("Caravan of the Tarnby
##     League, bound for Marstead"): only parties whose people are in view (no omniscience)
## Reads LifeClient (people), DealsClient (quests, atlas work, patrons) and DealsUi.target.
class_name PeopleMarks
extends Control

const NEAR := 48.0

var gu: GameUi
var _items: Array = []     # [{p: screen pos, mark, prompt, plate}]
var _parties: Array = []   # [{p, text, hostile}]
var _had := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	name = "people_marks"

func step() -> void:
	var dui := gu.deals_ui
	if dui == null or dui.lc == null or gu.cw == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_items.clear()
	_parties.clear()
	var cw := gu.cw
	var lc := dui.lc
	var dc := dui.dc
	var me := cw.view_pos()
	var hovered := _hovered()
	var sc := gu.ui_scale
	var parties := {}
	for id: int in lc.people:
		var r: ClientWorld.RemoteEntity = cw.remotes.get(id)
		if r == null or r.hp <= 0 and r.max_hp > 0:
			continue
		if r.pos.distance_to(me) > NEAR:
			continue
		var top := Vector3(r.pos.x * K.TILE_M, (r.pos.y + r.size.y) * K.TILE_M + 0.2, 0.0)
		if cam.is_position_behind(top):
			continue
		var sp := cam.unproject_position(top) / sc
		var p: Dictionary = lc.people[id]
		var it := {"p": sp, "mark": DealsLogic.role_mark(p, dc.quests, dc.sites.get(int(p.get("of", -1)), {}), dc.patrons)}
		if id == dui.target:
			it["prompt"] = DealsLogic.talk_prompt(p)
		elif id == hovered:
			it["plate"] = DealsLogic.person_label(p)
		if String(p.get("kind", "")) == "party":
			var pid := int(p.get("of", -1))
			var cur: Dictionary = parties.get(pid, {})
			if cur.is_empty() or sp.y < float(cur["y"]) - 0.1 or (absf(sp.y - float(cur["y"])) < 6.0 and String(p.get("role", "")) == "wagon"):
				parties[pid] = {"y": sp.y, "p": sp, "info": p}
		if it.has("prompt") or it.has("plate") or String(it["mark"]) != "":
			_items.append(it)
	for pid: int in parties:
		var info: Dictionary = parties[pid]["info"]
		var kind := String(info.get("party", ""))
		var f := dui.faction_name(String(info.get("faction", "")))
		var text := DealsLogic.party_plate(kind, f, dc.site_name(int(info.get("dest", -1))), dc.site_name(int(info.get("home", -1))))
		_parties.append({"p": parties[pid]["p"] + Vector2(0, -34), "text": text, "hostile": kind in ["raid", "army", "pack"]})
	if not _items.is_empty() or not _parties.is_empty() or _had:
		queue_redraw()
	_had = not _items.is_empty() or not _parties.is_empty()

## The person under the mouse (0: none).
func _hovered() -> int:
	if gu.presenter == null or not gu.presenter.has_method("tile_at_screen"):
		return 0
	var t: Vector2i = gu.presenter.call("tile_at_screen", get_viewport().get_mouse_position())
	var p := Vector2(t) + Vector2(0.5, 0.5)
	var lc := gu.deals_ui.lc
	for id: int in lc.people:
		var r: ClientWorld.RemoteEntity = gu.cw.remotes.get(id)
		if r != null and Rect2(r.pos - Vector2(r.size.x * 0.5, 0), r.size).grow(0.4).has_point(p):
			return id
	return 0

func _draw() -> void:
	for pt: Dictionary in _parties:
		_tag(pt["p"], String(pt["text"]), UiTheme.BLOOD_DARK if bool(pt["hostile"]) else UiTheme.INK, UiTheme.SMALL, true)
	for it: Dictionary in _items:
		var p: Vector2 = it["p"]
		var y := p.y - 12.0
		if String(it["mark"]) != "":
			Emblems.mark(self, Vector2(p.x, y), String(it["mark"]), 9.0)
			y -= 20.0
		if it.has("prompt"):
			_tag(Vector2(p.x, y), String(it["prompt"]), UiTheme.INK, UiTheme.BODY, false, true)
		elif it.has("plate"):
			_tag(Vector2(p.x, y), String(it["plate"]), UiTheme.INK, UiTheme.SMALL)

## A parchment tag centred over `at` (its bottom edge at at.y).
func _tag(at: Vector2, text: String, border: Color, fs: int, display := false, key := false) -> void:
	var w := UiTheme.text_width(text, fs, display) + 18
	var h := fs + 12.0
	var r := Rect2(clampf(at.x - w * 0.5, 4, size.x - w - 4), at.y - h, w, h)
	UiTheme.ink_rect(self, r, UiTheme.PARCHMENT, border, 2.0 if key else 1.5)
	if key:
		draw_rect(r.grow(-3), Color(UiTheme.GOLD, 0.18))
	UiTheme.text(self, Vector2(r.position.x, r.end.y - 7), text, fs, UiTheme.INK if border == UiTheme.INK else border, display,
		HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
