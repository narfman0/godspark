## Where NavFollow fails: plans paths on generated worlds and walks each with the real body
## (PlayerController) and NavFollow, without replanning, and logs every failure: the edge
## kind it was on, the nodes, the reason, and (pics=N) an ASCII picture of the first N.
##   godot --headless -s res://tools/nav_probe.gd -- [seeds=3,5,7] [pairs=24] [mode=pairs|sites|both]
##                                                   [size=large|medium] [pics=6] [replan=0]
## pairs: cave pairs ~40 tiles apart on 1024x512 worlds (as tests/test_monster_nav.gd _caves),
##   planned with a 64-tile window. sites: dev worlds, paths from the spawn settlement to every
##   site from one flood (as tools/cave_nav.gd mode=sites).
## replan=N: let the walk replan up to N times from where it is (as the brains do), to compare.
extends SceneTree

const TEST := preload("res://tests/test_monster_nav.gd")

var pics := 0
var shown := 0
var by_edge := {}
var by_why := {}
var replan := 0
var trace := 0

func _initialize() -> void:
	var opts := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() > 1 else ""
	var seeds := String(opts.get("seeds", "3,5,7")).split(",")
	pics = int(opts.get("pics", "4"))
	replan = int(opts.get("replan", "0"))
	trace = int(opts.get("trace", "0"))
	var size := String(opts.get("size", "medium"))
	var mode := String(opts.get("mode", "pairs"))
	var st := NavMaps.stats(size, {"walk": 30} if size != "large" else {"walk": 30, "climb": 30})
	var ok := 0
	var n := 0
	if mode in ["pairs", "both"]:
		for s in seeds:
			var r := _pairs(int(s), st, int(opts.get("pairs", "24")))
			ok += r[0]
			n += r[1]
			print("seed %s pairs: followed %d of %d planned" % [s, r[0], r[1]])
	if mode in ["sites", "both"]:
		for s in seeds:
			var r := _sites(int(s), st, String(opts.get("world", "dev")))
			ok += r[0]
			n += r[1]
			print("seed %s sites: followed %d of %d paths" % [s, r[0], r[1]])
	print("NAVPROBE %s: followed %d of %d planned paths (%.0f%%)" % [size, ok, n, 100.0 * ok / maxi(1, n)])
	print("  failures by edge: ", _named(by_edge))
	print("  failures by reason: ", by_why)
	quit()

func _named(d: Dictionary) -> Dictionary:
	var out := {}
	for k: int in d:
		out[MonsterNav.EDGE_NAMES[k] if k >= 0 else "end"] = d[k]
	return out

func _pairs(world_seed: int, st: MoveStats, pairs: int) -> Array:
	var world := WorldGen.generate(1024, 512, world_seed)
	var band: Array = world.meta.get("bands", {}).get("caves", [100, 200])
	var r := RandomNumberGenerator.new()
	r.seed = 5
	var prof := MonsterNav.profile(st)
	var ok := 0
	var planned := 0
	var n := 0
	var tries := 0
	while n < pairs and tries < 5000:
		tries += 1
		var a := TEST._spot(world, st, r, int(band[0]), int(band[1]))
		if a == Vector2.INF:
			continue
		var cands := TEST._connected_spots(world, st, a)
		if cands.is_empty():
			continue
		var b: Vector2 = cands[r.randi_range(0, cands.size() - 1)]
		n += 1
		var s := MonsterNav.start(world, prof, a, b, Vector2i(1, 1), false)
		while not s.step(100000):
			pass
		var path := s.result()
		if path == null:
			continue
		planned += 1
		if _walk(world, st, prof, path, a, b, "seed %d pair %d" % [world_seed, n]):
			ok += 1
	return [ok, planned]

func _sites(world_seed: int, st: MoveStats, size: String) -> Array:
	var world := WorldGen.generate_named(size, world_seed)
	var prof := MonsterNav.profile(st)
	var spawn := Vector2.INF
	var spawn_id := -1
	for site: Dictionary in world.meta["sites"]:
		if site["kind"] == "settlement" and site["band"] in ["surface", "sky"]:
			spawn = Vector2(float(site["x"]) + 0.5, float(site["y"]))
			spawn_id = int(site["id"])
			break
	var radius := Vector2i(world.width, world.height)
	var flood := MonsterNav.start(world, prof, spawn, Vector2(-5000, -5000), Vector2i.ZERO, false, 20000000, radius)
	while not flood.step(1000000):
		pass
	var ok := 0
	var n := 0
	for site: Dictionary in world.meta["sites"]:
		if int(site["id"]) == spawn_id:
			continue
		var goal := Vector2(float(site["x"]) + 0.5, float(site["y"]))
		var g := MonsterNav.node_of(prof, goal)
		var path: NavPath = null
		for o: Vector2i in [Vector2i.ZERO, Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(1, 1)]:
			path = flood.path_to(g + o)
			if path != null:
				break
		if path == null:
			continue
		n += 1
		if _walk(world, st, prof, path, spawn, MonsterNav.node_pos(prof, path.end_node()), "seed %d %s %d" % [world_seed, site["kind"], site["id"]]):
			ok += 1
	return [ok, n]

## Walk the path; on a failure log the edge it was on. True when the body arrived.
func _walk(world: TileWorld, st: MoveStats, prof: NavProfile, path: NavPath, from: Vector2, to: Vector2, label: String) -> bool:
	var b := st.make_body()
	b.pos = from
	TileCollision.depenetrate(world, b)
	TileCollision.update_contacts(world, b)
	var f := NavFollow.new()
	f.set_path(path)
	var dt := 1.0 / K.TICK_HZ
	var steps := maxi(1, MoveStats.step_hz() / K.TICK_HZ)
	var sdt := 1.0 / MoveStats.step_hz()
	var replans := 0
	var limit := path.size() * 30 + 600
	var t := 0
	var ring: Array = []
	while t < limit:
		t += 1
		var inp := f.input(world, b, dt)
		if inp != null and trace > 0:
			ring.append("      t%d i%d %s mx %.2f up %s dn %s j %s jp %s | pos %.3f,%.3f vel %.2f,%.2f fl %s cl %s jt %d" % [t, f.i,
				MonsterNav.EDGE_NAMES[f.path.how[mini(f.i, f.path.size() - 1)] & 15], inp.move_x, inp.up, inp.down, inp.jump,
				inp.jump_pressed, b.pos.x, b.pos.y, b.vel.x, b.vel.y, b.on_floor, b.climbing, f.jump_t])
			if ring.size() > trace:
				ring.pop_front()
		if inp == null:
			if f.failed and replans < replan:
				replans += 1
				var s2 := MonsterNav.start(world, prof, b.pos, to, Vector2i(1, 1), false, 400000, Vector2i(200, 200))
				while not s2.step(100000):
					pass
				var p2 := s2.result()
				if p2 != null:
					f.set_path(p2)
					continue
			break
		for i in steps:
			PlayerController.step(world, b, inp, st, sdt)
			inp.jump_pressed = false
	var reached := absf(b.pos.x - to.x) <= 2.0 and absf(b.pos.y - to.y) <= 1.6
	if reached:
		return true
	var k := mini(f.i, f.path.size() - 1)
	var edge := f.path.how[k] & 15 if k > 0 else -1
	var why := f.why if f.failed else ("timeout" if t >= limit else "ended away")
	by_edge[edge] = int(by_edge.get(edge, 0)) + 1
	var wk := why.split(" ")[0]
	by_why[wk] = int(by_why.get(wk, 0)) + 1
	var prev: Vector2i = f.path.nodes[k - 1] if k > 0 else f.path.nodes[0]
	var extra := ""
	if edge == MonsterNav.Edge.JUMP:
		var j: Dictionary = prof.jumps[f.path.how[k] >> 4]
		extra = " jump dl %d dy %d hold %d delay %d" % [j["dl"], j["dy"], j["hold"], j["delay"]]
	print("  FAIL %s: %s at node %d/%d %s -> %s%s; body %s vel %s floor %s climb %s; %s" % [label,
		MonsterNav.EDGE_NAMES[edge] if edge >= 0 else "-", k, f.path.size(), prev, f.path.nodes[k], extra,
		b.pos, b.vel, b.on_floor, b.climbing, why])
	if shown < pics:
		shown += 1
		_picture(world, f.path, k, b)
		for l: String in ring:
			print(l)
	return false

func _picture(world: TileWorld, path: NavPath, k: int, b: Body) -> void:
	var c: Vector2i = path.nodes[k]
	var marks := {}
	for i in range(maxi(0, k - 12), mini(path.size(), k + 12)):
		marks[path.nodes[i]] = "T" if i == k else ("o" if i < k else "+")
	var bx0 := floori(b.left())
	var bx1 := ceili(b.right()) - 1
	var by0 := floori(b.pos.y)
	var by1 := ceili(b.top()) - 1
	for y in range(c.y + 10, c.y - 9, -1):
		var line := "    %4d " % y
		for x in range(c.x - 20, c.x + 21):
			var ch := "."
			var id := world.get_fg(x, y)
			if TileDefs.solid[id] != 0:
				ch = "#"
			elif TileDefs.stairs[id] != 0:
				ch = "/" if id == TileDefs.id("stairs_r") else "\\"
			elif TileDefs.platform[id] != 0:
				ch = "="
			elif TileDefs.rope[id] != 0:
				ch = "|"
			elif TileDefs.ladder[id] != 0:
				ch = "H"
			if marks.has(Vector2i(x, y)):
				ch = marks[Vector2i(x, y)]
			if x >= bx0 and x <= bx1 and y >= by0 and y <= by1:
				ch = "B" if ch == "." else ch.to_lower() if ch != "#" else "X"
			line += ch
		print(line)
	print("    path near: ", _desc(path, k))

func _desc(path: NavPath, k: int) -> String:
	var parts := PackedStringArray()
	for i in range(maxi(1, k - 4), mini(path.size(), k + 4)):
		parts.append("%s%s>%d,%d" % ["*" if i == k else "", MonsterNav.EDGE_NAMES[path.how[i] & 15], path.nodes[i].x, path.nodes[i].y])
	return " ".join(parts)
