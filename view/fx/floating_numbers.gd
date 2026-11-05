## Floating combat numbers over the world: damage, healing, misses, crits and saves, from
## combat events. A fixed pool of Labels (NumberPool, at most CAP live: a horde replaces the
## oldest instead of flooding the screen), projected from the world each frame.
class_name FloatingNumbers
extends Control

const CAP := 40
const RISE := 1.6       ## tiles over a number's life

var fx: FxView
var pool := NumberPool.new(CAP)
var labels: Array[Label] = []
## Per slot: world anchor (tiles), colour, base size.
var anchors: Array = []
var _scale := 1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in CAP:
		var l := Label.new()
		l.visible = false
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_override("font", UiTheme.body_font())
		UiTheme.world_label(l, 22)
		add_child(l)
		labels.append(l)
		anchors.append({"pos": Vector2.ZERO, "size": 22})

## Show `text` above `pos` (tiles) for target entity `target`.
func spawn(target: int, pos: Vector2, text: String, color: Color, size := 22) -> void:
	var s := pool.acquire(target)
	var i := int(s["index"])
	var l := labels[i]
	l.text = text
	l.add_theme_color_override("font_color", color)
	var fs := roundi(size * _scale)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_constant_override("outline_size", maxi(4, roundi(6 * _scale)))
	var jitter := (float(hash(pool.now) & 0xff) / 255.0 - 0.5) * 0.8
	anchors[i] = {"pos": pos + Vector2(jitter, 0.55 * int(s["row"])), "size": fs}
	l.visible = true
	l.reset_size()

func step(dt: float, cam: Camera3D) -> void:
	_scale = UiTheme.scale_for(get_viewport().get_visible_rect().size)
	for i in pool.step(dt):
		labels[i].visible = false
	if cam == null:
		return
	for i in CAP:
		var sl: Dictionary = pool.slots[i]
		var age := float(sl["age"])
		if age < 0.0:
			continue
		var l := labels[i]
		var a: Dictionary = anchors[i]
		var k := age / NumberPool.LIFE
		var w: Vector2 = a["pos"] + Vector2(0, RISE * (1.0 - pow(1.0 - k, 2.0)))
		var p3 := Vector3(w.x * K.TILE_M, w.y * K.TILE_M, 0.3)
		if cam.is_position_behind(p3):
			l.visible = false
			continue
		var sp := cam.unproject_position(p3)
		l.position = sp - l.size * 0.5
		var pop := 1.0 + 0.35 * maxf(0.0, 1.0 - age / 0.12)
		l.scale = Vector2(pop, pop)
		l.pivot_offset = l.size * 0.5
		l.modulate.a = clampf((NumberPool.LIFE - age) / 0.35, 0.0, 1.0)
