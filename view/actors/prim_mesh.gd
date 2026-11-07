## Props built from primitives, for what has no model or whose model is not fetched: a dressing.json
## row's "prim" is a list of parts, so the look below needs no art (AGENTS.md: the game runs with
## none). Units are the row's own: DressingView.placement scales the top to fit_h.
##
##   "prim": {"parts": [
##     {"lathe": [[radius, y, "#colour", glow], ...], "at": [x, z], "sides": 7, "lean": [dx, dz],
##      "rough": 0.1, "seed": 3, "squash": 1.0},
##     {"box": [x0, y0, z0, x1, y1, z1], "color": "#colour", "glow": 0.0}]}
##
## A lathe is rings up a stem (bottom to top; a ring's radius may be 0): flat faces, colour and glow
## blend up it. lean moves the top that far, the rings in between in proportion. rough knocks each
## ring's corners in or out by that share, seeded, so a stem is not a machined column. glow (0-2)
## is light of its own: a cap's gills read in a cave nothing else lights (view/shaders/prim.gdshader).
##
##   PrimMesh.build(row["prim"])   # {parts: [{mesh, xform}], top: float} or {} with no parts
class_name PrimMesh
extends RefCounted

const SHADER := preload("res://view/shaders/prim.gdshader")
## COLOR.a holds glow / GLOW_MAX: a vertex's colour is eight bits.
const GLOW_MAX := 2.0

static var _mat: ShaderMaterial

static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = SHADER
	return _mat

static func build(prim: Variant) -> Dictionary:
	if not (prim is Dictionary) or (prim as Dictionary).get("parts", []).is_empty():
		return {}
	var b := Buf.new()
	for p: Dictionary in prim["parts"]:
		if p.has("lathe"):
			_lathe(b, p)
		elif p.has("box"):
			_box(b, p)
	if b.v.is_empty():
		return {}
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = b.v
	arrays[Mesh.ARRAY_NORMAL] = b.n
	arrays[Mesh.ARRAY_COLOR] = b.c
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material())
	return {"parts": [{"mesh": mesh, "xform": Transform3D.IDENTITY}], "top": b.top}

static func _lathe(b: Buf, p: Dictionary) -> void:
	var rings: Array = p["lathe"]
	var sides := int(p.get("sides", 7))
	var at: Array = p.get("at", [0.0, 0.0])
	var lean: Array = p.get("lean", [0.0, 0.0])
	var rough := float(p.get("rough", 0.0))
	var sd := int(p.get("seed", 1))
	var squash := float(p.get("squash", 1.0))
	var y0 := float(rings[0][1])
	var y1 := float(rings[-1][1])
	var span := maxf(absf(y1 - y0), 0.001)
	var pts: Array = []       # per ring: its corners
	for j in rings.size():
		var ring: Array = rings[j]
		var k := absf(float(ring[1]) - y0) / span
		var cx := float(at[0]) + float(lean[0]) * k
		var cz := float(at[1]) + float(lean[1]) * k
		var row := PackedVector3Array()
		for i in sides:
			var a := TAU * (float(i) + 0.5 * (j % 2)) / sides
			var r := float(ring[0])
			if rough > 0.0:
				var h := hash(Vector3i(i, j, sd))
				r *= 1.0 + rough * (float(h & 0xff) / 127.5 - 1.0)
			row.append(Vector3(cx + cos(a) * r, float(ring[1]), cz + sin(a) * r * squash))
		pts.append(row)
	for j in rings.size() - 1:
		var c0 := _colour(rings[j][2], float(rings[j][3]) if (rings[j] as Array).size() > 3 else 0.0)
		var c1 := _colour(rings[j + 1][2], float(rings[j + 1][3]) if (rings[j + 1] as Array).size() > 3 else 0.0)
		var low: PackedVector3Array = pts[j]
		var up: PackedVector3Array = pts[j + 1]
		for i in sides:
			var n2 := (i + 1) % sides
			var mid := (low[i] + low[n2] + up[i] + up[n2]) * 0.25
			var out := mid - Vector3(float(at[0]) + float(lean[0]) * absf(mid.y - y0) / span, mid.y, float(at[1]) + float(lean[1]) * absf(mid.y - y0) / span)
			b.tri(low[i], low[n2], up[n2], c0, c0, c1, out)
			b.tri(low[i], up[n2], up[i], c0, c1, c1, out)

static func _box(b: Buf, p: Dictionary) -> void:
	var q: Array = p["box"]
	var lo := Vector3(float(q[0]), float(q[1]), float(q[2]))
	var hi := Vector3(float(q[3]), float(q[4]), float(q[5]))
	var c := _colour(String(p.get("color", "#808080")), float(p.get("glow", 0.0)))
	var faces := [
		[Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3.BACK],
		[Vector3(hi.x, lo.y, lo.z), Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3.FORWARD],
		[Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z), Vector3.UP],
		[Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3.DOWN],
		[Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, hi.y, lo.z), Vector3.LEFT],
		[Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3.RIGHT]]
	for f: Array in faces:
		b.tri(f[0], f[1], f[2], c, c, c, f[4])
		b.tri(f[0], f[2], f[3], c, c, c, f[4])

## Linear colour, glow in alpha.
static func _colour(hex: Variant, glow: float) -> Color:
	var c := Color.from_string(String(hex), Color.MAGENTA).srgb_to_linear()
	c.a = clampf(glow / GLOW_MAX, 0.0, 1.0)
	return c

class Buf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var top := 0.0

	## A flat triangle, wound for the normal nearest `out` (Godot's front faces are clockwise).
	func tri(a: Vector3, b: Vector3, d: Vector3, ca: Color, cb: Color, cd: Color, out: Vector3) -> void:
		var nrm := (b - a).cross(d - a)
		if nrm.length_squared() < 1e-10:
			return
		nrm = nrm.normalized()
		if nrm.dot(out) > 0.0:
			v.append_array([a, d, b])
			c.append_array([ca, cd, cb])
		else:
			v.append_array([a, b, d])
			c.append_array([ca, cb, cd])
			nrm = -nrm
		n.append_array([nrm, nrm, nrm])
		top = maxf(top, maxf(a.y, maxf(b.y, d.y)))
