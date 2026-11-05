## Builds one chunk's terrain mesh. Thread-safe: take a snapshot on the main thread (about
## 20 KB of array copies), build the arrays on a worker, make the ArrayMesh on the main
## thread.
##
##   var snap := ChunkMesher.snapshot(world, cx, cy)        # main thread
##   var arrays := ChunkMesher.build_arrays(snap)           # any thread; [] when empty
##   var mesh := ChunkMesher.to_mesh(arrays)                # main thread
##   ChunkMesher.build(world, cx, cy)                       # the first two in one call
##
## Geometry, in tile units relative to the chunk's bottom-left corner (scaled by K.TILE_M):
## solid tiles are blocks from z = BACK to z = FRONT. Their front faces are greedy-merged
## rectangles. Where a block borders a non-solid cell it gets a 45 degree bevel and a side
## face down to the back plane; bevels meet in mitres at outer corners and get two filler
## triangles at inner corners. Open cells with a background wall get a wall plane at WALL_Z.
## Non-solid tiles (torches) are small posts.
##
## Vertex data: COLOR is the tile colour (linear), UV2 = (tile or wall id, kind) with kind
## 0 block, 1 emissive, 2 wall, and UV is a world-space tile coordinate on the face's plane:
## enough for a texture array to replace the colours later. Per-tile colour variation is a
## hash in the shader, so it does not stop faces from merging.
class_name ChunkMesher
extends RefCounted

const N := K.CHUNK
const PAD := K.CHUNK + 2
const FRONT := 0.5
const BACK := -0.5
const BEVEL := 0.14
const WALL_Z := -0.5
const KIND_BLOCK := 0.0
const KIND_EMIT := 1.0
const KIND_WALL := 2.0

## What a worker needs: copies (packed arrays are shared by reference, so duplicated) of the 3x3 chunks' foreground arrays (or a marker for outside
## the world: 0 air above it, 1 bedrock elsewhere) and this chunk's walls.
static func snapshot(world: TileWorld, cx: int, cy: int) -> Dictionary:
	var fgs: Array = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var x := cx + dx
			var y := cy + dy
			if x < 0 or x >= world.chunks_x or y < 0:
				fgs.append(1)
			elif y >= world.chunks_y:
				fgs.append(0)
			else:
				fgs.append(world.chunk_at(x, y).fg.duplicate())
	return {"cx": cx, "cy": cy, "fgs": fgs, "bg": world.chunk_at(cx, cy).bg.duplicate(),
		"bedrock": TileDefs.id("bedrock")}

static func build(world: TileWorld, cx: int, cy: int) -> Array:
	return build_arrays(snapshot(world, cx, cy))

static func to_mesh(arrays: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if not arrays.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Surface arrays (Mesh.ARRAY_MAX long) for one chunk, or [] if it has nothing to draw.
static func build_arrays(snap: Dictionary) -> Array:
	var fgs: Array = snap["fgs"]
	var bedrock: int = snap["bedrock"]
	var ids := PackedInt32Array()
	ids.resize(PAD * PAD)
	var sol := PackedByteArray()
	sol.resize(PAD * PAD)
	var solid := TileDefs.solid
	for j in PAD:
		var ly := j - 1
		var dy := -1 if ly < 0 else (1 if ly >= N else 0)
		var sy := ly - dy * N
		for i in PAD:
			var lx := i - 1
			var dx := -1 if lx < 0 else (1 if lx >= N else 0)
			var src: Variant = fgs[(dx + 1) + (dy + 1) * 3]
			var id: int
			if src is PackedByteArray:
				id = (src as PackedByteArray).decode_u16(((lx - dx * N) + sy * N) * 2)
			else:
				id = bedrock if src == 1 else 0
			ids[i + j * PAD] = id
			sol[i + j * PAD] = solid[id]
	var buf := MeshBuf.new(Vector2(snap["cx"] * N, snap["cy"] * N))
	_fronts(buf, ids, sol)
	_edges(buf, ids, sol)
	_walls(buf, ids, sol, snap["bg"])
	_posts(buf, ids, sol)
	return buf.arrays()

## Greedy front faces: horizontal runs of one id with the same top/bottom exposure, then
## stacked runs with the same span merged upward.
static func _fronts(buf: MeshBuf, ids: PackedInt32Array, sol: PackedByteArray) -> void:
	var rects: Array[PackedFloat32Array] = []   # [x0, x1, y0, y1, id]
	var open := {}
	for ly in N:
		var next := {}
		var row := (ly + 1) * PAD
		var lx := 0
		while lx < N:
			var c := lx + 1 + row
			if sol[c] == 0:
				lx += 1
				continue
			var id := ids[c]
			var eu := sol[c + PAD] == 0
			var ed := sol[c - PAD] == 0
			var x0 := lx
			while lx + 1 < N:
				var n := lx + 2 + row
				if sol[n] == 0 or ids[n] != id or (sol[n + PAD] == 0) != eu or (sol[n - PAD] == 0) != ed:
					break
				lx += 1
			var il := sol[x0 + row] == 0
			var ir := sol[lx + 2 + row] == 0
			var key := x0 | (lx << 5) | (int(il) << 10) | (int(ir) << 11) | (id << 12)
			var top := ly + 1 - (BEVEL if eu else 0.0)
			if not ed and open.has(key):
				var r: PackedFloat32Array = rects[open[key]]
				r[3] = top
				rects[open[key]] = r
				if not eu:
					next[key] = open[key]
			else:
				rects.append(PackedFloat32Array([x0 + (BEVEL if il else 0.0), lx + 1 - (BEVEL if ir else 0.0),
					ly + (BEVEL if ed else 0.0), top, id]))
				if not eu:
					next[key] = rects.size() - 1
			lx += 1
		open = next
	var colors := TileDefs.colors
	var nz := Vector3(0, 0, 1)
	for r in rects:
		var col := colors[int(r[4])].srgb_to_linear()
		buf.quad(Vector3(r[0], r[2], FRONT), Vector3(r[1], r[2], FRONT), Vector3(r[1], r[3], FRONT),
			Vector3(r[0], r[3], FRONT), nz, col, int(r[4]), KIND_BLOCK)

## Bevels, side faces and inner-corner fillers, for each of the four directions.
static func _edges(buf: MeshBuf, ids: PackedInt32Array, sol: PackedByteArray) -> void:
	var colors := TileDefs.colors
	for e: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var s := Vector2i(1, 0) if e.x == 0 else Vector2i(0, 1)
		var eo := e.x + e.y * PAD
		var so := s.x + s.y * PAD
		var e3 := Vector3(e.x, e.y, 0)
		var nb := Vector3(e.x, e.y, 1).normalized()
		var fe := Vector2(e) * (0.5 - BEVEL)
		var ke := Vector2(e) * 0.5
		for line in N:
			var t := 0
			while t < N:
				var cell := Vector2i(t, line) if e.x == 0 else Vector2i(line, t)
				var c := cell.x + 1 + (cell.y + 1) * PAD
				if sol[c] == 0 or sol[c + eo] != 0:
					t += 1
					continue
				var id := ids[c]
				var t0 := t
				var c0 := c
				while t + 1 < N and sol[c + so] != 0 and ids[c + so] == id and sol[c + so + eo] == 0:
					t += 1
					c += so
				var col := colors[id].srgb_to_linear()
				var start := Vector2(cell) + Vector2(0.5, 0.5) - Vector2(s) * 0.5
				var end := start + Vector2(s) * (t - t0 + 1)
				var se := sol[c0 - so] == 0
				var ee := sol[c + so] == 0
				var f0 := start + Vector2(s) * (BEVEL if se else 0.0) + fe
				var f1 := end - Vector2(s) * (BEVEL if ee else 0.0) + fe
				var k0 := start + ke
				var k1 := end + ke
				buf.quad(Vector3(f0.x, f0.y, FRONT), Vector3(f1.x, f1.y, FRONT), Vector3(k1.x, k1.y, FRONT - BEVEL),
					Vector3(k0.x, k0.y, FRONT - BEVEL), nb, col, id, KIND_BLOCK)
				buf.quad(Vector3(k0.x, k0.y, FRONT - BEVEL), Vector3(k1.x, k1.y, FRONT - BEVEL),
					Vector3(k1.x, k1.y, BACK), Vector3(k0.x, k0.y, BACK), e3, col, id, KIND_BLOCK)
				# Inner corners: the neighbour along s is solid and so is the cell beyond it in e.
				if not se and sol[c0 - so + eo] != 0:
					buf.tri(Vector3(k0.x, k0.y, FRONT), Vector3(k0.x - e.x * BEVEL, k0.y - e.y * BEVEL, FRONT),
						Vector3(k0.x, k0.y, FRONT - BEVEL), Vector3(s.x, s.y, 0), col, id, KIND_BLOCK)
				if not ee and sol[c + so + eo] != 0:
					buf.tri(Vector3(k1.x, k1.y, FRONT), Vector3(k1.x - e.x * BEVEL, k1.y - e.y * BEVEL, FRONT),
						Vector3(k1.x, k1.y, FRONT - BEVEL), Vector3(-s.x, -s.y, 0), col, id, KIND_BLOCK)
				t += 1

## Background wall plane behind open cells, greedy-merged per wall id.
static func _walls(buf: MeshBuf, _ids: PackedInt32Array, sol: PackedByteArray, bg: PackedByteArray) -> void:
	var rects: Array[PackedInt32Array] = []   # [x0, x1, y0, y1, wall]
	var open := {}
	for ly in N:
		var next := {}
		var lx := 0
		while lx < N:
			var w := bg[lx + ly * N]
			if w == 0 or sol[lx + 1 + (ly + 1) * PAD] != 0:
				lx += 1
				continue
			var x0 := lx
			while lx + 1 < N and bg[lx + 1 + ly * N] == w and sol[lx + 2 + (ly + 1) * PAD] == 0:
				lx += 1
			var key := x0 | (lx << 5) | (w << 10)
			if open.has(key):
				var r: PackedInt32Array = rects[open[key]]
				r[3] = ly + 1
				rects[open[key]] = r
				next[key] = open[key]
			else:
				rects.append(PackedInt32Array([x0, lx + 1, ly, ly + 1, w]))
				next[key] = rects.size() - 1
			lx += 1
		open = next
	var colors := TileDefs.wall_colors
	var nz := Vector3(0, 0, 1)
	for r in rects:
		buf.quad(Vector3(r[0], r[2], WALL_Z), Vector3(r[1], r[2], WALL_Z), Vector3(r[1], r[3], WALL_Z),
			Vector3(r[0], r[3], WALL_Z), nz, colors[r[4]].srgb_to_linear(), r[4], KIND_WALL)

## Non-solid, non-air tiles: a small post standing on the cell's floor.
static func _posts(buf: MeshBuf, ids: PackedInt32Array, sol: PackedByteArray) -> void:
	var colors := TileDefs.colors
	var emit := TileDefs.emit
	for ly in N:
		for lx in N:
			var c := lx + 1 + (ly + 1) * PAD
			var id := ids[c]
			if id == 0 or sol[c] != 0:
				continue
			var col := colors[id].srgb_to_linear()
			var kind := KIND_EMIT if emit[id] > 0 else KIND_BLOCK
			var a := Vector3(lx + 0.4, ly, -0.1)
			var b := Vector3(lx + 0.6, ly + 0.6, 0.1)
			buf.box(a, b, col, id, kind)

## Growing vertex arrays. Quads take four corners in order around the face and fix the
## winding to match the normal (Godot's front faces are clockwise).
class MeshBuf:
	var origin: Vector2
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()

	func _init(o: Vector2) -> void:
		origin = o

	func _uv(p: Vector3, nrm: Vector3) -> Vector2:
		var ax := absf(nrm.x)
		var ay := absf(nrm.y)
		if ax > ay and ax > absf(nrm.z):
			return Vector2(p.z, p.y + origin.y)
		if ay > absf(nrm.z):
			return Vector2(p.x + origin.x, p.z)
		return Vector2(p.x + origin.x, p.y + origin.y)

	func _vert(p: Vector3, nrm: Vector3, col: Color, f: Vector2) -> void:
		v.append(p * K.TILE_M)
		n.append(nrm)
		c.append(col)
		uv.append(_uv(p, nrm))
		uv2.append(f)

	func quad(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, nrm: Vector3, col: Color, id: int, kind: float) -> void:
		var base := v.size()
		var f := Vector2(id, kind)
		if (b - a).cross(cc - a).dot(nrm) > 0.0:
			var t := b
			b = d
			d = t
		_vert(a, nrm, col, f)
		_vert(b, nrm, col, f)
		_vert(cc, nrm, col, f)
		_vert(d, nrm, col, f)
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])

	func tri(a: Vector3, b: Vector3, cc: Vector3, nrm: Vector3, col: Color, id: int, kind: float) -> void:
		var base := v.size()
		var f := Vector2(id, kind)
		if (b - a).cross(cc - a).dot(nrm) > 0.0:
			var t := b
			b = cc
			cc = t
		_vert(a, nrm, col, f)
		_vert(b, nrm, col, f)
		_vert(cc, nrm, col, f)
		idx.append_array([base, base + 1, base + 2])

	func box(a: Vector3, b: Vector3, col: Color, id: int, kind: float) -> void:
		quad(Vector3(a.x, a.y, b.z), Vector3(b.x, a.y, b.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z), Vector3(0, 0, 1), col, id, kind)
		quad(Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, a.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z), Vector3(0, 1, 0), col, id, kind)
		quad(Vector3(a.x, a.y, a.z), Vector3(a.x, b.y, a.z), Vector3(a.x, b.y, b.z), Vector3(a.x, a.y, b.z), Vector3(-1, 0, 0), col, id, kind)
		quad(Vector3(b.x, a.y, a.z), Vector3(b.x, b.y, a.z), Vector3(b.x, b.y, b.z), Vector3(b.x, a.y, b.z), Vector3(1, 0, 0), col, id, kind)

	func arrays() -> Array:
		if v.is_empty():
			return []
		var out: Array = []
		out.resize(Mesh.ARRAY_MAX)
		out[Mesh.ARRAY_VERTEX] = v
		out[Mesh.ARRAY_NORMAL] = n
		out[Mesh.ARRAY_COLOR] = c
		out[Mesh.ARRAY_TEX_UV] = uv
		out[Mesh.ARRAY_TEX_UV2] = uv2
		out[Mesh.ARRAY_INDEX] = idx
		return out
