## The swings and contacts drawn over the world: a crescent through the arc a blow really covers
## and a mark on whatever it met. Two fixed pools of quads, nothing allocated per frame; numbers
## and colours in data/combat.json "feel". FxView feeds it from combat events.
class_name SwingFx
extends Node3D

const SLASH := preload("res://view/fx/slash.gdshader")
const IMPACT := preload("res://view/fx/impact.gdshader")
const SLASHES := 12
const IMPACTS := 16
enum Mark { HIT, CRIT, MISS }

var quads: Array[MeshInstance3D] = []
## Per quad: {src, wait, t, dur, hold, box, reach}; dur < 0: free.
var live: Array = []
var marks: Array[MeshInstance3D] = []
var mark_live: Array = []
## src -> the last slash's index (what a HIT, MISS or WHIFF restyles).
var last := {}
var _next_mark := 0
var _phase := 0.0

static func feel() -> Dictionary:
	return CombatTempo.section("feel")

static func color(key: String) -> Color:
	return Color.from_string(String(feel().get("colors", {}).get(key, "")), Color.WHITE)

func _ready() -> void:
	for i in SLASHES:
		quads.append(_quad(SLASH))
		live.append({"dur": -1.0, "src": 0})
	for i in IMPACTS:
		marks.append(_quad(IMPACT))
		mark_live.append({"dur": -1.0})

func _quad(shader: Shader) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = shader
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi

## One sweep `wait` seconds from now. box: half the attacker's box; reach: tiles past it.
func slash(src: int, wait: float, dir: Vector2, reach: float, half: float, box: Vector2, side: float, width: float, tint: Color) -> void:
	var best := 0
	for i in SLASHES:
		if float(live[i]["dur"]) < 0.0:
			best = i
			break
	var extent := reach + maxf(box.x, box.y) + 0.8
	live[best] = {"src": src, "wait": wait, "t": 0.0, "dur": float(feel().get("slash_s", 0.16)), "hold": 0.0, "box": box}
	var mi := quads[best]
	mi.scale = Vector3(extent * 2.0 * K.TILE_M, extent * 2.0 * K.TILE_M, 1.0)
	var m := mi.material_override as ShaderMaterial
	m.set_shader_parameter("size", reach)
	m.set_shader_parameter("box", box)
	m.set_shader_parameter("extent", extent)
	m.set_shader_parameter("dir", dir)
	m.set_shader_parameter("half_deg", half)
	m.set_shader_parameter("side", side)
	m.set_shader_parameter("width", width)
	m.set_shader_parameter("color", tint)
	m.set_shader_parameter("progress", 0.0)
	m.set_shader_parameter("fade", 1.0)
	last[src] = best

## What the blow met recolours the sweep it belongs to.
func result(src: int, tint: Color, width := -1.0) -> void:
	var i := int(last.get(src, -1))
	if i < 0 or float(live[i]["dur"]) < 0.0 or int(live[i]["src"]) != src:
		return
	var m := quads[i].material_override as ShaderMaterial
	m.set_shader_parameter("color", tint)
	if width >= 0.0:
		m.set_shader_parameter("width", width)

## The attacker's slashes stop for the hit-stop.
func hold(src: int, s: float) -> void:
	for l: Dictionary in live:
		if int(l["src"]) == src and float(l["dur"]) >= 0.0:
			l["hold"] = maxf(float(l["hold"]), s)

func cancel(src: int) -> void:
	for i in SLASHES:
		if int(live[i]["src"]) == src and float(live[i]["wait"]) > 0.0:
			live[i]["dur"] = -1.0
			quads[i].visible = false

## A mark at `pos` (tiles): HIT, CRIT or MISS.
func mark(pos: Vector2, kind: int) -> void:
	var f := feel()
	var key: String = ["hit", "crit", "miss"][kind]
	var i := _next_mark
	_next_mark = (_next_mark + 1) % IMPACTS
	var size := float(f.get("impact_tiles", {}).get(key, 1.5)) * K.TILE_M
	var mi := marks[i]
	mi.position = Vector3(pos.x * K.TILE_M, pos.y * K.TILE_M, (ChunkMesher.FRONT + 0.03) * K.TILE_M)
	mi.scale = Vector3(size * 2.0, size * 2.0, 1.0)
	mi.visible = true
	_phase += 2.4
	var m := mi.material_override as ShaderMaterial
	m.set_shader_parameter("kind", kind)
	m.set_shader_parameter("color", color(key))
	m.set_shader_parameter("rays", 12.0 if kind == Mark.CRIT else 7.0)
	m.set_shader_parameter("phase", _phase)
	m.set_shader_parameter("progress", 0.0)
	mark_live[i] = {"t": 0.0, "dur": float(f.get("impact_s", {}).get(key, 0.25))}

func step(dt: float, fx: FxView) -> void:
	for i in SLASHES:
		var l: Dictionary = live[i]
		if float(l["dur"]) < 0.0:
			continue
		if float(l["wait"]) > 0.0:
			l["wait"] = float(l["wait"]) - dt
			if float(l["wait"]) > 0.0:
				continue
		if float(l["hold"]) > 0.0:
			l["hold"] = float(l["hold"]) - dt
		else:
			l["t"] = float(l["t"]) + dt
		var k := float(l["t"]) / float(l["dur"])
		if k > 1.5:
			l["dur"] = -1.0
			quads[i].visible = false
			continue
		var c := fx.actor_center(int(l["src"]))
		if c == Vector2.INF:
			l["dur"] = -1.0
			quads[i].visible = false
			continue
		var mi := quads[i]
		mi.position = Vector3(c.x * K.TILE_M, c.y * K.TILE_M, (ChunkMesher.FRONT + 0.03) * K.TILE_M)
		mi.visible = true
		var m := mi.material_override as ShaderMaterial
		m.set_shader_parameter("progress", clampf(k, 0.0, 1.0))
		m.set_shader_parameter("fade", clampf(1.5 - k * 1.0, 0.0, 1.0) * clampf(3.0 - k * 2.0, 0.0, 1.0))
	for i in IMPACTS:
		var l: Dictionary = mark_live[i]
		if float(l["dur"]) < 0.0:
			continue
		l["t"] = float(l["t"]) + dt
		var k := float(l["t"]) / float(l["dur"])
		if k >= 1.0:
			l["dur"] = -1.0
			marks[i].visible = false
			continue
		(marks[i].material_override as ShaderMaterial).set_shader_parameter("progress", k)

## Slashes and marks showing or waiting (the tour and tests read it).
func active_count() -> int:
	var n := 0
	for l: Dictionary in live + mark_live:
		if float(l["dur"]) >= 0.0:
			n += 1
	return n
