## Wind-up telegraphs from SWING events and the quick-spell aiming preview: an SRD shape (arc,
## cone, line, circle, square) drawn flat on the front plane, filling up over the wind-up.
## Monsters' in vermilion, other players' areas in teal, the own aim in pale gold. A melee arc
## is the shape the host tests: the swinger's box grown by the weapon's reach, within
## data/combat.json melee.arc_half_angle_deg of the aim. A pool of quads with the telegraph
## shader; nothing is allocated per frame.
class_name Telegraphs
extends Node3D

const SHADER := preload("res://view/fx/telegraph.gdshader")
const CAP := 16
enum Shape { ARC, CONE, LINE, CIRCLE, SQUARE }
const MONSTER_COLOR := Color(0.85, 0.27, 0.17, 0.7)     # thin enough to see the swinger through in a dark cave
const ALLY_COLOR := Color(0.18, 0.61, 0.58, 0.85)
const AIM_COLOR := Color(0.96, 0.85, 0.45, 0.9)
## The own swing: the same gold, lighter (it shows at every swing).
const SWING_COLOR := Color(0.96, 0.85, 0.45, 0.55)
## Melee reach from a monster's edge, tiles (SRD 5 ft).
const MELEE_REACH := 2.0

var quads: Array[MeshInstance3D] = []
## Per quad: {t, dur, src}
var live: Array = []
var preview: MeshInstance3D
## The next swing's arc, while a foe is near (its own quad: it stands through a spell's preview).
var arc: MeshInstance3D

func _ready() -> void:
	for i in CAP + 2:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		mi.mesh = q
		var m := ShaderMaterial.new()
		m.shader = SHADER
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		if i == CAP:
			preview = mi
		elif i == CAP + 1:
			arc = mi
		else:
			quads.append(mi)
			live.append({"t": 0.0, "dur": -1.0, "src": 0})

## A shape as data: {shape, origin, dir, size, width, half, box}. Pure (tests read it). box: half
## a swinger's box; an arc's edge runs at (size - box.x) from that box, not from its centre.
static func describe(shape: int, origin: Vector2, dir: Vector2, size: float, width := 2.0, half := 70.0, box := Vector2.ZERO) -> Dictionary:
	return {"shape": shape, "origin": origin, "dir": dir.normalized() if dir.length() > 0.001 else Vector2.RIGHT,
		"size": maxf(0.3, size), "width": width, "half": half, "box": box}

static func arc_half() -> float:
	return float(CombatTempo.section("melee").get("arc_half_angle_deg", 70.0))

## The shape a SWING event telegraphs, from the swinger's box (pos = feet, size in tiles).
## Spells: their SRD area (`area` from the spell: {shape: SRD.AoEShape, size_ft, range_ft}).
static func for_swing(ev: Dictionary, pos: Vector2, size: Vector2, area := {}) -> Dictionary:
	var c := pos + Vector2(0, size.y * 0.5)
	var aim: Vector2 = ev.get("aim", c + Vector2.RIGHT)
	var dir := aim - c
	match int(ev.get("mode", 0)):
		CombatCodec.Mode.MELEE:
			return describe(Shape.ARC, c, dir, size.x * 0.5 + K.ft(float(ev.get("reach_ft", 5.0))), 2.0, arc_half(), size * 0.5)
		CombatCodec.Mode.RANGED, CombatCodec.Mode.THROW:
			return describe(Shape.LINE, c, dir, minf(dir.length(), 40.0), 0.5)
		CombatCodec.Mode.SAVE_ACTION:
			return describe(Shape.CONE, c, dir, 6.0 + size.x)
	if not area.is_empty():
		return area_shape(area, c, aim)
	return describe(Shape.CIRCLE, aim, dir, 1.0)

## An SRD area as a telegraph: self-origin shapes start at the caster, others at the aim
## clamped to range (as the host does, minus the wall check).
static func area_shape(area: Dictionary, caster: Vector2, aim: Vector2) -> Dictionary:
	var dir := aim - caster
	var size := K.ft(float(area.get("size_ft", 5)))
	var rng := K.ft(maxf(float(area.get("range_ft", 0)), 5.0))
	var origin := caster
	if float(area.get("range_ft", 0)) > 0.0:
		origin = aim if aim.distance_to(caster) <= rng else caster + dir.normalized() * rng
	match int(area.get("shape", SRD.AoEShape.SPHERE)):
		SRD.AoEShape.CONE:
			return describe(Shape.CONE, origin, dir, size)
		SRD.AoEShape.LINE:
			return describe(Shape.LINE, origin, dir, size, 2.0)
		SRD.AoEShape.CUBE:
			return describe(Shape.SQUARE, origin, dir, size)
	return describe(Shape.CIRCLE, origin, dir, size)

## follow: the shape stays on `src` (the own swing, on a body that keeps running).
func show_shape(d: Dictionary, dur: float, color: Color, src := 0, follow := false) -> void:
	var best := 0
	var bt := -1.0
	for i in CAP:
		var l: Dictionary = live[i]
		if float(l["dur"]) < 0.0:
			best = i
			break
		if int(l["src"]) == src and src != 0:
			best = i
			break
		if float(l["t"]) > bt:
			bt = float(l["t"])
			best = i
	live[best] = {"t": 0.0, "dur": maxf(0.1, dur), "src": src, "follow": follow}
	_apply(quads[best], d, color, 0.0)

func set_preview(d: Dictionary) -> void:
	if d.is_empty():
		preview.visible = false
		return
	_apply(preview, d, AIM_COLOR, 1.0)

func _apply(mi: MeshInstance3D, d: Dictionary, color: Color, progress: float) -> void:
	var extent := float(d["size"]) + 0.6
	if int(d["shape"]) == Shape.LINE or int(d["shape"]) == Shape.SQUARE:
		extent = float(d["size"]) + float(d["width"]) + 0.6
	var o: Vector2 = d["origin"]
	mi.position = Vector3(o.x * K.TILE_M, o.y * K.TILE_M, (ChunkMesher.FRONT + 0.02) * K.TILE_M)
	mi.scale = Vector3(extent * 2.0 * K.TILE_M, extent * 2.0 * K.TILE_M, 1.0)
	var m := mi.material_override as ShaderMaterial
	m.set_shader_parameter("shape", int(d["shape"]))
	m.set_shader_parameter("size", float(d["size"]))
	m.set_shader_parameter("extent", extent)
	m.set_shader_parameter("dir", d["dir"])
	m.set_shader_parameter("width", float(d["width"]))
	m.set_shader_parameter("half_deg", float(d["half"]))
	m.set_shader_parameter("box", d.get("box", Vector2.ZERO))
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("progress", progress)
	mi.visible = true

func cancel_from(src: int) -> void:
	for i in CAP:
		if int(live[i]["src"]) == src:
			live[i]["dur"] = -1.0
			quads[i].visible = false

## The swing that follows `src` stands at this centre now (tiles).
func move_from(src: int, origin: Vector2) -> void:
	for i in CAP:
		if int(live[i]["src"]) == src and bool(live[i].get("follow", false)) and float(live[i]["dur"]) >= 0.0:
			quads[i].position = Vector3(origin.x * K.TILE_M, origin.y * K.TILE_M, quads[i].position.z)

## The faint arc of the next swing, over the aim; {} clears it.
func set_reach_arc(d: Dictionary, color: Color) -> void:
	if d.is_empty():
		arc.visible = false
		return
	_apply(arc, d, color, 0.0)

func step(dt: float) -> void:
	for i in CAP:
		var l: Dictionary = live[i]
		if float(l["dur"]) < 0.0:
			continue
		l["t"] = float(l["t"]) + dt
		var k := float(l["t"]) / float(l["dur"])
		if k > 1.15:
			l["dur"] = -1.0
			quads[i].visible = false
			continue
		(quads[i].material_override as ShaderMaterial).set_shader_parameter("progress", clampf(k, 0.0, 1.0))

func active_count() -> int:
	var n := 0
	for l: Dictionary in live:
		if float(l["dur"]) >= 0.0:
			n += 1
	return n
