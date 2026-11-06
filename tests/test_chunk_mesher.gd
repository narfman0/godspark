extends RefCounted

func run(t: TestLog) -> void:
	var stone := TileDefs.id("stone")
	var T := K.TILE_M

	var empty := TileWorld.new(64, 64)
	t.eq(ChunkMesher.build(empty, 0, 0), [], "an empty chunk builds nothing")

	var test := TileWorld.make_test()
	var deep := ChunkMesher.build(test, 0, 0)
	t.eq(_verts(deep), 4, "a buried all-stone chunk is one merged front quad")

	# traversal pieces: each draws something of its own (a box is 16 vertices), and a rope's
	# anchor cell (no rope above) carries a knot
	var counts := {}
	for n: String in ["platform", "ladder", "stairs_r", "stairs_l", "rope"]:
		var wt := TileWorld.new(64, 64)
		wt.set_fg(5, 5, TileDefs.id(n), true)
		counts[n] = _verts(ChunkMesher.build(wt, 0, 0))
	t.check(counts["stairs_r"] == 36 and counts["stairs_l"] == 36 and counts["platform"] == 48 and counts["ladder"] == 64 and counts["rope"] == 32,
			"walkways, stairs, ladders and ropes have their own shapes (%s)" % counts)
	var rp := TileWorld.new(64, 64)
	rp.set_fg(5, 5, TileDefs.id("rope"), true)
	rp.set_fg(5, 4, TileDefs.id("rope"), true)
	t.eq(_verts(ChunkMesher.build(rp, 0, 0)), counts["rope"] + 16, "a two-cell rope: one knot, at the anchor")

	var one := TileWorld.new(64, 64)
	one.set_fg(5, 5, stone, true)
	t.eq(_verts(ChunkMesher.build(one, 0, 0)), 4 + 4 * 4 + 4 * 4, "a lone block: front, 4 bevels, 4 sides")

	var two := TileWorld.new(64, 64)
	two.set_fg(5, 5, stone, true)
	two.set_fg(6, 5, stone, true)
	var a2 := ChunkMesher.build(two, 0, 0)
	t.eq(_verts(a2), 4 + 4 * 4 + 4 * 4, "two blocks side by side merge into one block's worth")
	var inner := 0
	var nv: PackedVector3Array = a2[Mesh.ARRAY_NORMAL]
	var pv: PackedVector3Array = a2[Mesh.ARRAY_VERTEX]
	for i in pv.size():
		if absf(nv[i].x) > 0.9 and is_equal_approx(pv[i].x, 6 * T):
			inner += 1
	t.eq(inner, 0, "no faces between two solid tiles")

	# An L of three blocks has one inner corner: two filler triangles.
	var ell := TileWorld.new(64, 64)
	ell.set_fg(5, 5, stone, true)
	ell.set_fg(6, 5, stone, true)
	ell.set_fg(5, 6, stone, true)
	var al := ChunkMesher.build(ell, 0, 0)
	var idx: PackedInt32Array = al[Mesh.ARRAY_INDEX]
	t.eq(idx.size() % 3, 0, "whole triangles")
	var bad := 0
	for i in idx:
		if i < 0 or i >= _verts(al):
			bad += 1
	t.eq(bad, 0, "indices in range")
	# fronts: (5,5) and (6,5) differ in top exposure, (5,6) in right inset: 3 quads.
	# Edges: 6 runs, a bevel and a side each. One inner corner: 2 triangles.
	t.eq(_verts(al), 3 * 4 + 6 * 8 + 2 * 3, "an L: 3 fronts, 6 edge runs, one inner corner")

	# Winding: every triangle faces along its normal under Godot's clockwise rule.
	var wrong := 0
	for k in range(0, idx.size(), 3):
		var p0: Vector3 = pv_of(al, idx[k])
		var p1: Vector3 = pv_of(al, idx[k + 1])
		var p2: Vector3 = pv_of(al, idx[k + 2])
		var nn: Vector3 = (al[Mesh.ARRAY_NORMAL] as PackedVector3Array)[idx[k]]
		if (p1 - p0).cross(p2 - p0).dot(nn) >= 0.0:
			wrong += 1
	t.eq(wrong, 0, "triangle winding matches normals")

	# The surface chunk of the test world: walls behind the pit and the cave, a torch post.
	var g := test.height / 2
	var mid := test.width / 2
	var surf := ChunkMesher.build(test, (mid - 2) / K.CHUNK, (g - 14) / K.CHUNK)
	var kinds := {}
	for f: Vector2 in (surf[Mesh.ARRAY_TEX_UV2] as PackedVector2Array):
		kinds[int(f.y)] = true
	t.check(kinds.has(1) and kinds.has(2), "cave chunk has emissive (torch) and wall vertices")
	t.check(_verts(surf) < 3000, "cave chunk vertex count is sane (%d)" % _verts(surf))

	# Snapshots are copies: editing the world after the snapshot does not change the build.
	var snap := ChunkMesher.snapshot(two, 0, 0)
	two.set_fg(20, 20, stone)
	t.eq(_verts(ChunkMesher.build_arrays(snap)), 36, "a snapshot is isolated from later edits")

func pv_of(a: Array, i: int) -> Vector3:
	return (a[Mesh.ARRAY_VERTEX] as PackedVector3Array)[i]

func _verts(a: Array) -> int:
	return 0 if a.is_empty() else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
