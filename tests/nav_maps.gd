## Hand-built maps and a real-body runner for the navigation tests and tools.
##   var m := NavMaps.build(["#....G", "#S..##", "######"])   # top row first
##   var r := NavMaps.run(m, NavMaps.stats("medium"), 600)
class_name NavMaps
extends RefCounted

const OX := 8
const OY := 8

## Build a world from ASCII rows (top first). '#' stone, 'd' dirt, '=' platform, '/' and '\\' stairs rising right and left, 'H' ladder,
## '~' water, 'L' lava, 'S' start feet cell, 'G' goal feet cell, anything else air. Everything below the
## art is stone. Returns {world, start: Vector2 (feet), goal: Vector2 (feet)}.
static func build(rows: Array, w := 96, h := 96) -> Dictionary:
	var world := TileWorld.new(w, h, 7)
	var stone := TileDefs.id("stone")
	var dirt := TileDefs.id("dirt")
	var plat := TileDefs.id("platform")
	var ladder := TileDefs.id("ladder")
	for x in w:
		for y in OY:
			world.set_fg(x, y, stone, true)
	var start := Vector2.ZERO
	var goal := Vector2.ZERO
	var n := rows.size()
	var wide := 0
	for line: String in rows:
		wide = maxi(wide, line.length())
	# rock to either side of the art, up to its top row
	for x in w:
		if x >= OX and x < OX + wide:
			continue
		for y in range(OY, OY + n):
			world.set_fg(x, y, stone, true)
	for r in n:
		var line: String = rows[r]
		var y := OY + (n - 1 - r)
		for c in line.length():
			var x := OX + c
			match line[c]:
				"#": world.set_fg(x, y, stone, true)
				"d": world.set_fg(x, y, dirt, true)
				"=": world.set_fg(x, y, plat, true)
				"H": world.set_fg(x, y, ladder, true)
				"/": world.set_fg(x, y, TileDefs.id("stairs_r"), true)
				"\\": world.set_fg(x, y, TileDefs.id("stairs_l"), true)
				"~": world.set_liquid(x, y, 15, true)
				"L": world.set_fg(x, y, TileDefs.id("lava"), true)
				"S": start = Vector2(x + 0.5, y)
				"G": goal = Vector2(x + 0.5, y)
	return {"world": world, "start": start, "goal": goal}

static func stats(size: String, speeds := {"walk": 30}) -> MoveStats:
	return MoveStats.from_srd(speeds, size)

## Plan (synchronously) and walk a real body along the path with PlayerController, as the
## host does (one input per tick, step_hz / TICK_HZ steps per tick). Returns
## {planned: bool, reached: bool, path: NavPath, ticks, pos, why, usec, expanded}.
static func run(m: Dictionary, st: MoveStats, max_ticks := 900, dig := 0.0, start_override := Vector2.INF) -> Dictionary:
	var world: TileWorld = m["world"]
	var b := st.make_body()
	b.pos = m["start"] if start_override == Vector2.INF else start_override
	TileCollision.depenetrate(world, b)
	TileCollision.update_contacts(world, b)
	var prof := MonsterNav.profile(st, dig)
	var goal: Vector2 = m["goal"]
	var s := MonsterNav.start(world, prof, b.pos, goal, Vector2i(1, 1), false)
	while not s.step(100000):
		pass
	var path := s.result()
	var out := {"planned": path != null, "reached": false, "path": path, "ticks": 0, "pos": b.pos, "why": "",
		"usec": s.usec, "expanded": s.expanded, "dug": 0}
	if path == null:
		return out
	var f := NavFollow.new()
	f.set_path(path)
	var dt := 1.0 / K.TICK_HZ
	var steps := maxi(1, MoveStats.step_hz() / K.TICK_HZ)
	var sdt := 1.0 / MoveStats.step_hz()
	var replans := 0
	for t in max_ticks:
		var inp := f.input(world, b, dt, maxf(st.burrow_speed / 8.0, 2.0))
		if inp == null:
			if f.failed and replans < 3:
				replans += 1
				var s2 := MonsterNav.start(world, prof, b.pos, goal, Vector2i(1, 1), false)
				while not s2.step(100000):
					pass
				var p2 := s2.result()
				if p2 != null:
					f.set_path(p2)
					continue
			if f.failed:
				out["why"] = f.why
			break
		for i in steps:
			PlayerController.step(world, b, inp, st, sdt)
			inp.jump_pressed = false
		out["ticks"] = t + 1
	out["pos"] = b.pos
	out["dug"] = f.dug
	out["replans"] = replans
	out["reached"] = absf(b.pos.x - goal.x) <= 2.0 and absf(b.pos.y - goal.y) <= 1.6
	return out
