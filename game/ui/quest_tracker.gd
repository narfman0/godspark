## The pinned quest on the HUD (top right, under the clock): its title, the job, live
## progress and time left, and a pointer with the distance to where it leads (the target site,
## or the travelling party or lair when the host says where it is). Redrawn a few times a
## second, not every frame.
class_name QuestTracker
extends Control

const W := 300.0
const H := 86.0

var gu: GameUi
var _t := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(W, H)
	name = "quest_tracker"

## The pinned quest, or {}.
func quest() -> Dictionary:
	var dui := gu.deals_ui
	if dui == null or dui.pinned == "":
		return {}
	for q: Dictionary in dui.dc.quests:
		if String(q.get("id", "")) == dui.pinned and String(q.get("state", "")) in ["active", "ready"]:
			return q
	return {}

func tick(dt: float) -> void:
	_t -= dt
	if _t <= 0.0:
		_t = 0.25
		visible = not quest().is_empty()
		queue_redraw()

func _draw() -> void:
	var q := quest()
	if q.is_empty():
		return
	var r := Rect2(Vector2.ZERO, size)
	UiTheme.ink_rect(self, r, UiTheme.PARCHMENT, UiTheme.MOSS.darkened(0.3) if String(q.get("state", "")) == "ready" else UiTheme.INK, 2.0)
	var tw := W - 86
	UiTheme.text(self, Vector2(10, 20), String(q.get("title", "")), UiTheme.SMALL + 1, UiTheme.INK, true, HORIZONTAL_ALIGNMENT_LEFT, tw)
	var ready := String(q.get("state", "")) == "ready"
	var line := "Done: go back and be paid." if ready else DealsLogic.progress_text(q)
	UiTheme.text(self, Vector2(10, 40), line, UiTheme.SMALL, UiTheme.MOSS.darkened(0.45) if ready else UiTheme.INK, false, HORIZONTAL_ALIGNMENT_LEFT, tw)
	UiTheme.ink_bar(self, Rect2(10, 48, tw - 4, 7), DealsLogic.progress_frac(q), UiTheme.MOSS if ready else UiTheme.GOLD, UiTheme.PARCH_SHADE)
	var tl := DealsLogic.time_left(int(q.get("due", 0)), gu.deals_ui.dc.sim_hour())
	UiTheme.text(self, Vector2(10, 74), DealsLogic.cap(tl) if tl != "" else "", UiTheme.TINY, UiTheme.INK_SOFT)
	# the pointer
	var tgt := MapLogic.quest_target(q, gu.cw.world.meta)
	if ready:
		tgt = MapLogic.site_xy(gu.cw.world.meta, int(q.get("site", -1)))
	var c := Vector2(W - 40, 34)
	draw_circle(c + Vector2(2, 2), 22, UiTheme.SHADOW)
	draw_circle(c, 22, UiTheme.PARCH_SHADE)
	draw_arc(c, 22, 0, TAU, 32, UiTheme.INK, 2.0, true)
	if tgt == Vector2.INF:
		UiTheme.text(self, c + Vector2(-20, 6), "?", UiTheme.HEADING, UiTheme.INK_SOFT, true, HORIZONTAL_ALIGNMENT_CENTER, 40)
		return
	var b := DealsLogic.bearing(gu.cw.body.center(), tgt)
	if ready and MapLogic.at_site(gu.cw.world.meta, int(q.get("site", -1)), gu.cw.body.center()):
		b["text"] = "here"
	if String(b["text"]) == "here":
		UiTheme.star(self, c, 12, 5, UiTheme.GOLD, 4, UiTheme.INK)
		UiTheme.text(self, Vector2(W - 76, 74), "here", UiTheme.TINY, UiTheme.INK, false, HORIZONTAL_ALIGNMENT_CENTER, 72)
		return
	var a := float(b["angle"])
	var d := Vector2(cos(a), sin(a))
	var n := Vector2(-d.y, d.x)
	var tip := c + d * 17
	draw_colored_polygon(PackedVector2Array([tip, c - d * 8 + n * 9, c - d * 3, c - d * 8 - n * 9]), UiTheme.VERMILION)
	draw_polyline(PackedVector2Array([tip, c - d * 8 + n * 9, c - d * 3, c - d * 8 - n * 9, tip]), UiTheme.INK, 1.5, true)
	UiTheme.text(self, Vector2(W - 86, 74), "%d tiles" % roundi(float(b["dist"])), UiTheme.TINY, UiTheme.INK, false, HORIZONTAL_ALIGNMENT_CENTER, 92)
