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
## Non-solid tiles: torches are posts with a glowing head, walkways planks, stairs treads
## with risers and a stringer, ladders rails and rungs, ropes a cord with a knot at the anchor,
## water a sheet behind the actors.
##
## Vertex data: COLOR is the tile colour (linear), UV2 = (tile or wall id, kind) with kind
## 0 block, 1 emissive, 2 wall, and UV is a world-space tile coordinate on the face's plane:
## enough for a texture array to replace the colours later. Per-tile colour variation is a
## hash in the shader, so it does not stop faces from merging.
##
## Soft mode (snapshot(..., true), what WorldView uses) draws natural ground as terrain, not
## blocks, and changes nothing the core sees: an open corner of a natural tile is cut (CUT tiles
## along each side) and an air cell in an inner corner gets the matching fillet, so a stair of
## single steps reads as one slope through the middle of each tread, where a body stands.
## Those faces are kind 3 (kind 4 for natural walls, 5 water), which the terrain shader colours
## from the blended material map: material_bytes(snap), one texel per tile, so no face shows a
## tile. Roofs cut too; other built things stay square, and plaster, timber and paving (SMOOTH)
## only lose their per-tile colour.
class_name ChunkMesher
extends RefCounted

const N := K.CHUNK
const PAD := K.CHUNK + 2
const FRONT := 0.5
const BACK := -0.5
const BEVEL := 0.2
const WALL_Z := -0.5
const KIND_BLOCK := 0.0
const KIND_EMIT := 1.0
const KIND_WALL := 2.0
const KIND_SOFT := 3.0
const KIND_SOFT_WALL := 4.0
const KIND_WATER := 5.0
## How far along each side an open corner is cut, and a fillet reaches, in tiles. At a half the cut
## of one step and the fillet below it lie on one line.
const CUT := 0.5
const ROOT2 := 1.4142135
## What is ground and not building: tile and wall names.
const NATURAL := ["dirt", "grass", "stone", "bedrock", "rubble", "copper_ore", "iron_ore", "silver_ore", "slate",
	"forest_floor", "loam", "mossy_stone", "scree", "gravel", "granite", "snow", "sand", "hardpan", "sandstone",
	"mire", "mud", "bog_stone", "forest_track", "pass_road", "desert_track", "causeway", "green_lane",
	"river_bed", "ford_stones"]
## Built tiles that take the map's colour and grain but keep their corners; roofs (the first two
## lines) are natural here too, for the cut: a stepped roof reads as a pitched one.
const ROOFS := ["thatch", "shingles", "leaf_roof"]
const SMOOTH := ["plaster", "timber", "logs", "planks", "elf_wood", "road", "dark_stone", "dressed_stone", "cobblestone", "canvas"]
## Walls with no courses to show: they take the ground's shading too.
const NATURAL_WALLS := ["dirt_wall", "stone_wall", "slate_wall", "loam_wall", "mossy_wall", "gravel_wall", "granite_wall",
	"hardpan_wall", "sandstone_wall", "mud_wall", "bog_wall", "plaster_wall", "wood_wall", "elf_wall", "canvas_wall"]
const STICK := Color("#6b4a2b")

static var _soft := PackedByteArray()        ## per tile id: 1 natural
static var _soft_wall := PackedByteArray()   ## per wall id: 1 natural

static func _ensure_soft() -> void:
	if not _soft.is_empty():
		return
	var s := PackedByteArray()
	s.resize(TileDefs.names.size())
	for n: String in NATURAL + ROOFS:
		s[TileDefs.id(n)] = 1
	for n: String in SMOOTH:
		s[TileDefs.id(n)] = 2
	var ws := PackedByteArray()
	ws.resize(TileDefs.wall_colors.size())
	for n: String in NATURAL_WALLS:
		var i := TileDefs.wall_id(n)
		if i > 0 and i < ws.size():
			ws[i] = 1
	_soft_wall = ws
	_soft = s

## What a worker needs: copies (packed arrays are shared by reference, so duplicated) of the 3x3 chunks' foreground arrays (or a marker for outside
## the world: 0 air above it, 1 bedrock elsewhere) and this chunk's walls.
static func snapshot(world: TileWorld, cx: int, cy: int, soft := false) -> Dictionary:
	if soft:
		_ensure_soft()
	var fgs: Array = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var x := cx + dx
			var y := cy + dy
			if x < 0 or x >= world.chunks_x or y < 0:
				fgs.append(1)
			elif y >= world.chunks_y:
				fgs.append(0)
			elif not world.has_chunk(x, y):
				# Unloaded (sparse client world): open sky above the surface line, else rock.
				fgs.append(0 if world.unloaded_is_sky(x, y) else 1)
			else:
				fgs.append(world.chunk_at(x, y).fg.duplicate())
	var own := world.chunk_at(cx, cy)
	var bg := own.bg.duplicate() if own != null else PackedByteArray()
	if own == null:
		bg.resize(K.CHUNK * K.CHUNK)
	return {"cx": cx, "cy": cy, "fgs": fgs, "bg": bg, "bedrock": TileDefs.id("bedrock"), "soft": soft}

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
	var cut := PackedByteArray()
	if snap.get("soft", false):
		cut = _cuts(ids, sol)
	_fronts(buf, ids, sol, cut)
	_edges(buf, ids, sol, cut)
	if not cut.is_empty():
		_soft_cells(buf, ids, sol, cut, snap["bg"])
		_fillets(buf, ids, sol)
	_walls(buf, ids, sol, snap["bg"], not cut.is_empty())
	_posts(buf, ids, sol, not cut.is_empty())
	return buf.arrays()

## The chunk's light-giving tiles (TileDefs.emit), for the view's lamps: Vector3i(world x,
## world y, tile id) each. Safe on a worker: it reads only the snapshot and TileDefs.
static func emitters(snap: Dictionary) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var own: Variant = (snap["fgs"] as Array)[4]
	if not (own is PackedByteArray):
		return out
	var fg := own as PackedByteArray
	var emit := TileDefs.emit
	var ox: int = int(snap["cx"]) * N
	var oy: int = int(snap["cy"]) * N
	for i in N * N:
		var id := fg.decode_u16(i * 2)
		if id < emit.size() and emit[id] > 0:
			out.append(Vector3i(ox + (i % N), oy + i / N, id))
	return out

## The chunk's material map, row by row: RGBA8, a natural tile's colour with alpha 255, all else
## zero, so filtering blends ground with ground and a shader can tell how near it is to the edge.
## Safe on a worker: it reads only the snapshot and TileDefs. Empty for a chunk with no tiles.
static func material_bytes(snap: Dictionary) -> PackedByteArray:
	var src: Variant = (snap["fgs"] as Array)[4]
	var out := PackedByteArray()
	if not src is PackedByteArray:
		return out
	out.resize(N * N * 4)
	var fg := src as PackedByteArray
	var colors := TileDefs.colors
	for p in N * N:
		var id := fg.decode_u16(p * 2)
		if _soft[id] != 0:
			var c := colors[id]
			out[p * 4] = c.r8
			out[p * 4 + 1] = c.g8
			out[p * 4 + 2] = c.b8
			out[p * 4 + 3] = 255
	return out

## Per padded cell, which of its corners are cut: bit 0 (+x, +y), 1 (-x, +y), 2 (-x, -y), 3 (+x, -y).
static func _cuts(ids: PackedInt32Array, sol: PackedByteArray) -> PackedByteArray:
	var cut := PackedByteArray()
	cut.resize(PAD * PAD)
	for j in range(1, PAD - 1):
		for i in range(1, PAD - 1):
			var c := i + j * PAD
			if sol[c] == 0 or _soft[ids[c]] != 1:
				continue
			var r := sol[c + 1] == 0
			var l := sol[c - 1] == 0
			var u := sol[c + PAD] == 0
			var d := sol[c - PAD] == 0
			cut[c] = (1 if r and u else 0) | (2 if l and u else 0) | (4 if l and d else 0) | (8 if r and d else 0)
	return cut

static func _kind(id: int, cut: PackedByteArray) -> float:
	return KIND_SOFT if not cut.is_empty() and _soft[id] != 0 else KIND_BLOCK

## Keep the part of a polygon where (p - o).dot(n) >= 0.
static func _clip(poly: PackedVector2Array, o: Vector2, n: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var count := poly.size()
	for i in count:
		var a := poly[i]
		var b := poly[(i + 1) % count]
		var da := (a - o).dot(n)
		var db := (b - o).dot(n)
		if da >= 0.0:
			out.append(a)
		if (da >= 0.0) != (db >= 0.0):
			out.append(a.lerp(b, da / (da - db)))
	return out

static func _fan(buf: MeshBuf, poly: PackedVector2Array, col: Color, id: int, kind: float) -> void:
	for i in range(1, poly.size() - 1):
		buf.tri(Vector3(poly[0].x, poly[0].y, FRONT), Vector3(poly[i].x, poly[i].y, FRONT),
			Vector3(poly[i + 1].x, poly[i + 1].y, FRONT), Vector3(0, 0, 1), col, id, kind)

## The sloped face between two points of the outline: its bevel from the front polygon's edge,
## and its side down to the back. out is the outward normal in the plane.
static func _slope(buf: MeshBuf, poly: PackedVector2Array, o1: Vector2, o2: Vector2, line_at: Vector2, out: Vector2,
		col: Color, id: int, kind: float) -> void:
	var i1 := Vector2.INF
	var i2 := Vector2.INF
	for p in poly:
		if absf((p - line_at).dot(out)) > 0.002:
			continue
		if i1 == Vector2.INF or p.distance_squared_to(o1) < i1.distance_squared_to(o1):
			i1 = p
		if i2 == Vector2.INF or p.distance_squared_to(o2) < i2.distance_squared_to(o2):
			i2 = p
	var z := FRONT - BEVEL
	if i1 != Vector2.INF:
		var nb := Vector3(out.x, out.y, 1.0).normalized()
		buf.quad(Vector3(o1.x, o1.y, z), Vector3(o2.x, o2.y, z), Vector3(i2.x, i2.y, FRONT), Vector3(i1.x, i1.y, FRONT), nb, col, id, kind)
	buf.quad(Vector3(o1.x, o1.y, z), Vector3(o2.x, o2.y, z), Vector3(o2.x, o2.y, BACK), Vector3(o1.x, o1.y, BACK), Vector3(out.x, out.y, 0), col, id, kind)

## Natural cells with a cut corner: a front polygon, a slope for each cut, and behind the cut-away
## the wall the open cells beside it show. Walls stand only behind open cells, so without it the
## camera, level with one column only, saw through the cut to the backdrop: a black or white
## notch at every outer corner underground. By day on the surface the cells beside it show the
## sky and so does the cut: nothing is drawn.
static func _soft_cells(buf: MeshBuf, ids: PackedInt32Array, sol: PackedByteArray, cut: PackedByteArray, bg: PackedByteArray) -> void:
	var colors := TileDefs.colors
	var wall_colors := TileDefs.wall_colors
	const CORNERS: Array[Vector2i] = [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1), Vector2i(1, -1)]
	for ly in N:
		for lx in N:
			var c := lx + 1 + (ly + 1) * PAD
			var m := cut[c]
			if m == 0:
				continue
			var id := ids[c]
			var col := colors[id].srgb_to_linear()
			var o := Vector2(lx, ly)
			var poly := PackedVector2Array([o, o + Vector2(1, 0), o + Vector2(1, 1), o + Vector2(0, 1)])
			if sol[c + 1] == 0:
				poly = _clip(poly, o + Vector2(1 - BEVEL, 0), Vector2(-1, 0))
			if sol[c - 1] == 0:
				poly = _clip(poly, o + Vector2(BEVEL, 0), Vector2(1, 0))
			if sol[c + PAD] == 0:
				poly = _clip(poly, o + Vector2(0, 1 - BEVEL), Vector2(0, -1))
			if sol[c - PAD] == 0:
				poly = _clip(poly, o + Vector2(0, BEVEL), Vector2(0, 1))
			for k in 4:
				if m & (1 << k):
					var s := CORNERS[k]
					var out := Vector2(s).normalized()
					var corner := o + Vector2(0.5, 0.5) + Vector2(s) * 0.5
					var o1 := corner - Vector2(s.x, 0) * CUT
					poly = _clip(poly, o1 - out * BEVEL, -out)
			if poly.size() >= 3:
				_fan(buf, poly, col, id, KIND_SOFT)
			for k in 4:
				if m & (1 << k):
					var s := CORNERS[k]
					var out := Vector2(s).normalized()
					var corner := o + Vector2(0.5, 0.5) + Vector2(s) * 0.5
					var o1 := corner - Vector2(s.x, 0) * CUT
					var o2 := corner - Vector2(0, s.y) * CUT
					_slope(buf, poly, o1, o2, o1 - out * BEVEL, out, col, id, KIND_SOFT)
					var w := 0
					for n: Vector2i in [Vector2i(lx + s.x, ly), Vector2i(lx, ly + s.y)]:
						if n.x >= 0 and n.x < N and n.y >= 0 and n.y < N and bg[n.x + n.y * N] != 0:
							w = bg[n.x + n.y * N]
							break
					if w != 0:
						buf.tri(Vector3(o1.x, o1.y, WALL_Z), Vector3(corner.x, corner.y, WALL_Z), Vector3(o2.x, o2.y, WALL_Z),
							Vector3(0, 0, 1), wall_colors[w].srgb_to_linear(), w, KIND_SOFT_WALL if _soft_wall[w] != 0 else KIND_WALL)

## Air in an inner corner of natural ground: a wedge that carries the slope on.
static func _fillets(buf: MeshBuf, ids: PackedInt32Array, sol: PackedByteArray) -> void:
	var colors := TileDefs.colors
	for ly in N:
		for lx in N:
			var c := lx + 1 + (ly + 1) * PAD
			if ids[c] != 0:
				continue
			for sy: int in [-1, 1]:
				var b := c + sy * PAD
				if sol[b] == 0 or _soft[ids[b]] != 1:
					continue
				for sx: int in [-1, 1]:
					var a := c + sx
					if sol[a] == 0 or _soft[ids[a]] != 1 or sol[b + sx] == 0:
						continue
					var s := Vector2(sx, sy)
					var corner := Vector2(lx, ly) + Vector2(0.5, 0.5) + s * 0.5
					var o1 := corner - Vector2(s.x, 0) * CUT
					var o2 := corner - Vector2(0, s.y) * CUT
					var into := s.normalized()        # toward the corner, into the ground
					var far := corner - s
					var near := corner + s * BEVEL
					var poly := PackedVector2Array([near, Vector2(far.x, near.y), far, Vector2(near.x, far.y)])
					poly = _clip(poly, o1 + into * BEVEL, into)
					var id := ids[b]
					var col := colors[id].srgb_to_linear()
					if poly.size() >= 3:
						_fan(buf, poly, col, id, KIND_SOFT)
					_slope(buf, poly, o1, o2, o1 + into * BEVEL, -into, col, id, KIND_SOFT)

## Greedy front faces: horizontal runs of one id with the same top/bottom exposure, then
## stacked runs with the same span merged upward.
static func _fronts(buf: MeshBuf, ids: PackedInt32Array, sol: PackedByteArray, cut := PackedByteArray()) -> void:
	var cuts := not cut.is_empty()
	var rects: Array[PackedFloat32Array] = []   # [x0, x1, y0, y1, id]
	var open := {}
	for ly in N:
		var next := {}
		var row := (ly + 1) * PAD
		var lx := 0
		while lx < N:
			var c := lx + 1 + row
			if sol[c] == 0 or (cuts and cut[c] != 0):
				lx += 1
				continue
			var id := ids[c]
			var eu := sol[c + PAD] == 0
			var ed := sol[c - PAD] == 0
			var x0 := lx
			while lx + 1 < N:
				var n := lx + 2 + row
				if sol[n] == 0 or ids[n] != id or (sol[n + PAD] == 0) != eu or (sol[n - PAD] == 0) != ed or (cuts and cut[n] != 0):
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
			Vector3(r[0], r[3], FRONT), nz, col, int(r[4]), _kind(int(r[4]), cut))

## Bevels, side faces and inner-corner fillers, for each of the four directions. Where a cell's
## corner is cut its run stops short of the corner, and _soft_cells draws the slope.
static func _edges(buf: MeshBuf, ids: PackedInt32Array, sol: PackedByteArray, cut := PackedByteArray()) -> void:
	var cuts := not cut.is_empty()
	var past := BEVEL * (ROOT2 - 1.0)   # how much further the front's edge stops than the outline
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
				var kind := _kind(id, cut)
				var cs := CUT if cuts and se and _soft[id] == 1 else 0.0
				var ce := CUT if cuts and ee and _soft[id] == 1 else 0.0
				var f0 := start + Vector2(s) * (cs + past if cs > 0.0 else (BEVEL if se else 0.0)) + fe
				var f1 := end - Vector2(s) * (ce + past if ce > 0.0 else (BEVEL if ee else 0.0)) + fe
				var k0 := start + Vector2(s) * cs + ke
				var k1 := end - Vector2(s) * ce + ke
				if (k1 - k0).dot(Vector2(s)) > 0.001:
					if (f1 - f0).dot(Vector2(s)) < 0.0:
						f0 = (f0 + f1) * 0.5
						f1 = f0
					buf.quad(Vector3(f0.x, f0.y, FRONT), Vector3(f1.x, f1.y, FRONT), Vector3(k1.x, k1.y, FRONT - BEVEL),
						Vector3(k0.x, k0.y, FRONT - BEVEL), nb, col, id, kind)
					buf.quad(Vector3(k0.x, k0.y, FRONT - BEVEL), Vector3(k1.x, k1.y, FRONT - BEVEL),
						Vector3(k1.x, k1.y, BACK), Vector3(k0.x, k0.y, BACK), e3, col, id, kind)
				# Inner corners: the neighbour along s is solid and so is the cell beyond it in e.
				if not se and sol[c0 - so + eo] != 0:
					buf.tri(Vector3(k0.x, k0.y, FRONT), Vector3(k0.x - e.x * BEVEL, k0.y - e.y * BEVEL, FRONT),
						Vector3(k0.x, k0.y, FRONT - BEVEL), Vector3(s.x, s.y, 0), col, id, kind)
				if not ee and sol[c + so + eo] != 0:
					buf.tri(Vector3(k1.x, k1.y, FRONT), Vector3(k1.x - e.x * BEVEL, k1.y - e.y * BEVEL, FRONT),
						Vector3(k1.x, k1.y, FRONT - BEVEL), Vector3(-s.x, -s.y, 0), col, id, kind)
				t += 1

## Background wall plane behind open cells, greedy-merged per wall id.
static func _walls(buf: MeshBuf, _ids: PackedInt32Array, sol: PackedByteArray, bg: PackedByteArray, soft := false) -> void:
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
			Vector3(r[0], r[3], WALL_Z), nz, colors[r[4]].srgb_to_linear(), r[4], KIND_SOFT_WALL if soft and _soft_wall[r[4]] != 0 else KIND_WALL)

## Non-solid, non-air tiles: a small post standing on the cell's floor.
static func _posts(buf: MeshBuf, ids: PackedInt32Array, sol: PackedByteArray, soft := false) -> void:
	var colors := TileDefs.colors
	var wk := KIND_WATER if soft else KIND_BLOCK
	var emit := TileDefs.emit
	var water := TileDefs.id("water")
	for ly in N:
		for lx in N:
			var c := lx + 1 + (ly + 1) * PAD
			var id := ids[c]
			if id == 0 or sol[c] != 0:
				continue
			var col := colors[id].srgb_to_linear()
			if id == water:
				# A sheet behind the actors, with a lighter skin along the top.
				buf.box(Vector3(lx, ly, -0.42), Vector3(lx + 1, ly + 1, -0.3), col, id, wk)
				if ids[c + PAD] != water:
					buf.box(Vector3(lx, ly + 0.86, -0.3), Vector3(lx + 1, ly + 1, 0.42), col.lightened(0.35), id, wk)
			elif TileDefs.burn[id] != 0:
				# Lava: a glowing sheet behind the actors, a brighter crust along the top.
				buf.box(Vector3(lx, ly, -0.42), Vector3(lx + 1, ly + 1, -0.3), col, id, KIND_EMIT)
				if TileDefs.burn[ids[c + PAD]] == 0:
					buf.box(Vector3(lx, ly + 0.8, -0.3), Vector3(lx + 1, ly + 1, 0.42), col.lightened(0.3), id, KIND_EMIT)
			elif emit[id] > 0 and TileDefs.shape[id] != "":
				_glow(buf, lx, ly, TileDefs.shape[id], col, id, sol[c - PAD] == 0 and sol[c + PAD] != 0)
			elif emit[id] > 0:
				# A stick with a glowing head.
				buf.box(Vector3(lx + 0.44, ly, -0.06), Vector3(lx + 0.56, ly + 0.5, 0.06), STICK.srgb_to_linear(), id, KIND_BLOCK)
				buf.box(Vector3(lx + 0.36, ly + 0.5, -0.12), Vector3(lx + 0.64, ly + 0.82, 0.12), col, id, KIND_EMIT)
			elif TileDefs.stairs[id] != 0:
				_stair(buf, lx, ly, TileDefs.stairs[id] == 1, col, id)
			elif TileDefs.platform[id] != 0:
				# A plank walkway the full depth of the row, on two thin bearers.
				buf.box(Vector3(lx, ly + 0.78, -0.45), Vector3(lx + 1, ly + 1.0, 0.45), col, id, KIND_BLOCK)
				var dark := col.darkened(0.35)
				buf.box(Vector3(lx + 0.05, ly + 0.66, -0.4), Vector3(lx + 0.95, ly + 0.78, -0.3), dark, id, KIND_BLOCK)
				buf.box(Vector3(lx + 0.05, ly + 0.66, 0.3), Vector3(lx + 0.95, ly + 0.78, 0.4), dark, id, KIND_BLOCK)
			elif TileDefs.rope[id] != 0:
				# A hanging cord behind the actors, with a knot where it is anchored.
				buf.box(Vector3(lx + 0.45, ly, -0.3), Vector3(lx + 0.55, ly + 1.0, -0.2), col, id, KIND_BLOCK)
				if TileDefs.rope[ids[c + PAD]] == 0:
					buf.box(Vector3(lx + 0.34, ly + 0.62, -0.36), Vector3(lx + 0.66, ly + 0.96, -0.14), col.darkened(0.2), id, KIND_BLOCK)
			elif TileDefs.ladder[id] != 0:
				# Two rails and two rungs, behind the actors.
				var dark := col.darkened(0.25)
				buf.box(Vector3(lx + 0.12, ly, -0.34), Vector3(lx + 0.24, ly + 1.0, -0.22), dark, id, KIND_BLOCK)
				buf.box(Vector3(lx + 0.76, ly, -0.34), Vector3(lx + 0.88, ly + 1.0, -0.22), dark, id, KIND_BLOCK)
				buf.box(Vector3(lx + 0.24, ly + 0.2, -0.32), Vector3(lx + 0.76, ly + 0.3, -0.24), col, id, KIND_BLOCK)
				buf.box(Vector3(lx + 0.24, ly + 0.7, -0.32), Vector3(lx + 0.76, ly + 0.8, -0.24), col, id, KIND_BLOCK)
			else:
				buf.box(Vector3(lx + 0.4, ly, -0.1), Vector3(lx + 0.6, ly + 0.6, 0.1), col, id, KIND_BLOCK)

## A light that grows in a cell (TileDefs.shape): cap, a pale stem under a glowing cap; crystal,
## three glowing shards; moss, a glowing carpet. hung: it grows down from the cell's ceiling.
static func _glow(buf: MeshBuf, lx: int, ly: int, kind: String, col: Color, id: int, hung: bool) -> void:
	var y0 := float(ly)
	var up := 1.0
	if hung:
		y0 = ly + 1.0
		up = -1.0
	var at := func(h0: float, h1: float) -> Array:
		var a := y0 + up * h0
		var b := y0 + up * h1
		return [minf(a, b), maxf(a, b)]
	match kind:
		"cap":
			var stem: Array = at.call(0.0, 0.45)
			buf.box(Vector3(lx + 0.44, stem[0], -0.06), Vector3(lx + 0.56, stem[1], 0.06), Color("#d8d0e0").srgb_to_linear(), id, KIND_BLOCK)
			var cap: Array = at.call(0.4, 0.62)
			buf.box(Vector3(lx + 0.22, cap[0], -0.2), Vector3(lx + 0.78, cap[1], 0.2), col, id, KIND_EMIT)
		"crystal":
			for k in 3:
				var cx := lx + 0.25 + k * 0.25
				var tall := [0.55, 0.85, 0.45][k] as float
				var sh: Array = at.call(0.0, tall)
				buf.box(Vector3(cx - 0.07, sh[0], -0.08 + k * 0.05), Vector3(cx + 0.07, sh[1], 0.06 + k * 0.05), col, id, KIND_EMIT)
		_:
			var mat: Array = at.call(0.0, 0.12)
			buf.box(Vector3(lx, mat[0], -0.4), Vector3(lx + 1, mat[1], 0.4), col, id, KIND_EMIT)

## One stair cell: a tread the full depth at the top of the cell, a riser down its low side,
## and a diagonal stringer at the back from this tread's low corner to the next one's.
static func _stair(buf: MeshBuf, lx: int, ly: int, rises_right: bool, col: Color, id: int) -> void:
	var dark := col.darkened(0.3)
	buf.box(Vector3(lx, ly + 0.8, -0.45), Vector3(lx + 1, ly + 1.0, 0.45), col, id, KIND_BLOCK)
	var rx: float = lx if rises_right else lx + 0.85
	buf.box(Vector3(rx, ly + 0.25, -0.42), Vector3(rx + 0.15, ly + 0.8, 0.42), dark, id, KIND_BLOCK)
	var nz := Vector3(0, 0, 1)
	var a := Vector3(lx, ly - 0.05 if rises_right else ly + 0.75, -0.44)
	var b := Vector3(lx + 1, ly + 0.75 if rises_right else ly - 0.05, -0.44)
	buf.quad(a, b, b + Vector3(0, 0.3, 0), a + Vector3(0, 0.3, 0), nz, dark, id, KIND_BLOCK)

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
