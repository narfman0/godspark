## A walker from the surface down to the nadir floor and back (M6 track deep, item 3): the real
## PlayerController on the world's own tiles, never digging, along a path the monsters' planner
## finds over the whole world (one search there, one back), followed a leg of LEG nodes at a
## time with local plans, as CrossingBot follows its line. One body, so its time is the time
## on screen. Used by tools/crossing.gd (descent mode) and tests/test_descent.gd.
##   var r := DescentBot.descent(world)
##   r = {ok, why, down: leg, back: leg, from: Vector2, to: Vector2, ways: {kind: n}, bands: [..],
##        regions: [..], digs, tiles_changed, seconds}
##   leg = {ok, why, seconds, ticks, nodes, bands: [band...], regions: [{biome, name}], ways: [kind...],
##          crossings: {shore_path, lava_bridge, rope, ladder, deep_road: ticks}, deepest, retries,
##          rewinds, banned}
## The follower is not perfect in every cave: a leg it fails is planned again round the node it
## could not reach, and a fall into a pocket with no way out puts the body back where it last
## gained ground (retries and rewinds are reported; a walk with many of them is a world to look at).
class_name DescentBot
extends RefCounted

## Path nodes a leg asks of the local planner (well inside MonsterNav.WINDOW).
const LEG := 24
const LEG_TICKS := 1500
const IDLE_LEGS := 6
## A leg the follower fails is planned again from where the body is, this many times running.
const RETRIES := 6
## Times a walk may go back to where it last stood having gained ground, after a fall into a
## place the planner has no way out of (it reports them).
const REWINDS := 6
## Expansions a local plan may make.
const LOCAL_CAP := 60000
## Expansions the whole-world search may make.
const CAP := 60000000
## Print each leg (tools).
static var trace := false

## Where a walk down starts: the spawn settlement (the first surface settlement, as the
## passages stage takes it), standing on its street.
static func spawn(world: TileWorld) -> Vector2:
	for s: Dictionary in world.meta.get("sites", []):
		if s["kind"] == "settlement" and String(s["band"]) in ["surface", "sky"]:
			return Vector2(float(s["x"]) + 0.5, float(s["y"]))
	return Vector2.INF

## The nadir floor (meta.descent.nadir), or the portal's chamber where a world has no magma.
static func nadir(world: TileWorld) -> Vector2:
	var nf: Array = world.meta.get("descent", {}).get("nadir", [])
	if nf.size() == 2:
		return Vector2(float(nf[0]) + 0.5, float(nf[1]))
	for s: Dictionary in world.meta.get("sites", []):
		if s["kind"] == "portal":
			return Vector2(float(s["x"]) + 0.5, float(s["y"]))
	return Vector2.INF

## Down from the spawn to the nadir floor and back up again.
static func descent(world: TileWorld, from := Vector2.INF) -> Dictionary:
	var a := spawn(world) if from == Vector2.INF else from
	var b := nadir(world)
	var hash0 := world.content_hash()
	var st := NavMaps.stats("medium")
	var f := NavFollow.new()
	var r := {"ok": false, "why": "", "from": a, "to": b, "digs": 0, "tiles_changed": false}
	if a == Vector2.INF or b == Vector2.INF:
		r["why"] = "no spawn or no nadir floor"
		return r
	var body := st.make_body()
	body.pos = a
	TileCollision.depenetrate(world, body)
	TileCollision.update_contacts(world, body)
	r["down"] = walk(world, st, body, f, b)
	r["back"] = walk(world, st, body, f, a) if r["down"]["ok"] else {"ok": false, "why": "never got down"}
	r["digs"] = f.dug
	r["tiles_changed"] = world.content_hash() != hash0
	r["seconds"] = float(r["down"].get("seconds", 0.0)) + float(r["back"].get("seconds", 0.0))
	var ways := {}
	for leg: Dictionary in [r["down"], r["back"]]:
		for k: String in leg.get("ways", []):
			ways[k] = int(ways.get(k, 0)) + 1
	r["ways"] = ways
	r["ok"] = r["down"]["ok"] and r["back"]["ok"] and f.dug == 0 and not r["tiles_changed"]
	r["why"] = String(r["down"].get("why", "")) if not r["down"]["ok"] else String(r["back"].get("why", ""))
	return r

## The planner's path from the body to goal over the whole world, then the real controller along it.
static func walk(world: TileWorld, st: MoveStats, b: Body, f: NavFollow, goal: Vector2) -> Dictionary:
	var prof := MonsterNav.profile(st, 0.0)
	var leg := {"ok": false, "why": "", "seconds": 0.0, "ticks": 0, "nodes": 0, "bands": [], "regions": [], "ways": [],
		"crossings": {}, "deepest": b.pos.y, "plan_ms": 0}
	var t0 := Time.get_ticks_msec()
	var s := _whole(world, prof, b.pos, goal)
	var whole := s.result()
	leg["plan_ms"] = Time.get_ticks_msec() - t0
	if whole == null:
		leg["why"] = "no plan from %s to %s (%d expanded)" % [b.pos, goal, s.expanded]
		return leg
	leg["nodes"] = whole.nodes.size()
	var w := {"leg": leg, "ticks": 0, "ways": world.meta.get("descent", {}).get("ways", []), "inside": {}}
	var at := 0
	var idle := 0
	var fails := 0
	var banned := {}
	var failed_at := {}                     # failing edge (or node) -> times
	var good := b.duplicate_body()          # where the body last stood having gained ground
	var gn := MonsterNav.node_of(prof, goal)
	while true:
		var here := MonsterNav.node_of(prof, b.pos)
		if absi(here.x - gn.x) <= 3 and absi(here.y - gn.y) <= 1 and (b.on_floor or b.on_stairs):
			leg["ok"] = true
			break
		at = _progress(whole, here, at)
		var path: NavPath = null
		var tries: Array = [LEG, LEG / 2, LEG * 2, 6, LEG * 3]
		if fails > 0:
			tries = [LEG * (1 + fails), LEG / (1 + fails), LEG * 4, 3]   # a leg that failed: aim elsewhere along the way
		for k: int in tries:
			var j := mini(at + int(k), whole.nodes.size() - 1)
			path = _local(world, prof, b, whole.nodes[j], banned)
			if path != null:
				break
		var why := ""
		if path == null:
			why = "no local plan from %s (path node %d of %d)" % [b.pos, at, whole.nodes.size()]
		else:
			f.set_path(path)
			if trace:
				print("    leg from %s at node %d of %d: %d nodes to %s, edges %s" % [b.pos, at, whole.nodes.size(), path.nodes.size(), path.nodes[-1],
					Array(path.how).map(func(h: int) -> int: return h & 15 if h >= 0 else -1)])
			why = _leg(world, b, f, st, w)
			if why == "" and int(w["ticks"]) > 400000:
				leg["why"] = "out of time at %s" % b.pos
				break
		if why != "":
			# the follower failed a leg (an edge it could not make, a fall off the way). The first
			# time at an edge: the whole way again from here. Again at that edge: round it (and the
			# edge that led there) if the planner has a way round; else back to where the body last
			# stood having gained ground, at rest (a rewind), and try again.
			fails += 1
			leg["retries"] = int(leg.get("retries", 0)) + 1
			if int(leg["retries"]) > RETRIES * 4:
				leg["why"] = "%s at %s, too many legs failed" % [why, b.pos]
				break
			var edges: Array = []
			if path != null and f.path != null and f.i < f.path.size():
				for k in [f.i, f.i - 1]:
					if k > 0:
						var a: Vector2i = f.path.nodes[k - 1]
						var z: Vector2i = f.path.nodes[k]
						edges.append(Vector4i(a.x, a.y, z.x, z.y))
			var key: Variant = edges[0] if not edges.is_empty() else MonsterNav.node_of(prof, b.pos)
			failed_at[key] = int(failed_at.get(key, 0)) + 1
			var again: NavPath = null
			if int(failed_at[key]) >= 2 and not edges.is_empty():
				for e: Vector4i in edges:
					banned[e] = true
				again = _whole(world, prof, b.pos, goal, banned).result()
				if trace:
					print("    banned %s: %s" % [edges, "a way round" if again != null else "no way round"])
				if again == null:
					for e: Vector4i in edges:
						banned.erase(e)
			if again == null and int(failed_at[key]) >= 2:
				_restore(b, good)
				b.vel = Vector2.ZERO
				leg["rewinds"] = int(leg.get("rewinds", 0)) + 1
				if int(leg["rewinds"]) > REWINDS:
					leg["why"] = "%s, rewound too often" % why
					break
			if again == null:
				again = _whole(world, prof, b.pos, goal, banned).result()
			if again == null:
				leg["why"] = "%s, and no way from %s" % [why, b.pos]
				break
			whole = again
			at = 0
			continue
		var now := _progress(whole, MonsterNav.node_of(prof, b.pos), at)
		if now <= at:
			idle += 1
			if idle >= IDLE_LEGS:
				leg["why"] = "no way gained from %s" % b.pos
				break
		else:
			idle = 0
			fails = 0
			if b.on_floor:
				good = b.duplicate_body()
	leg["banned"] = banned.size()
	leg["ticks"] = w["ticks"]
	leg["seconds"] = float(w["ticks"]) / K.TICK_HZ
	return leg

## Put the body back as a copy of it was.
static func _restore(b: Body, from: Body) -> void:
	for p: Dictionary in from.get_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			b.set(p["name"], from.get(p["name"]))

## The planner's whole way from the body to goal: in a window around the two first, then over the
## whole world if that window does not hold one.
static func _whole(world: TileWorld, prof: NavProfile, from: Vector2, goal: Vector2, banned := {}) -> NavSearch:
	var s := MonsterNav.start(world, prof, from, goal, Vector2i(1, 1), false, CAP, reach(world, from, goal))
	s.banned = banned
	while not s.step(1000000):
		pass
	if s.result() == null:
		s = MonsterNav.start(world, prof, from, goal, Vector2i(1, 1), false, CAP, Vector2i(world.width, world.height))
		s.banned = banned
		while not s.step(1000000):
			pass
	return s

## A local plan from the body (or a hair beside it, where the body's own node is not one a
## search starts from) to a node of the whole way.
static func _local(world: TileWorld, prof: NavProfile, b: Body, n: Vector2i, banned: Dictionary) -> NavPath:
	for o: Vector2 in [Vector2.ZERO, Vector2(0.45, 0.0), Vector2(-0.45, 0.0), Vector2(0.0, 1.0), Vector2(1.0, 0.0), Vector2(-1.0, 0.0)]:
		var s := MonsterNav.start(world, prof, b.pos + o, MonsterNav.node_pos(prof, n), Vector2i(1, 1), false, LOCAL_CAP, Vector2i(96, 96))
		s.banned = banned
		while not s.step(100000):
			pass
		var p := s.result()
		if p != null:
			return p
	return null

## The window of a whole-way search: the way between, a quarter of the world's width to either
## side and an eighth of its height above and below (a whole medium world is 1.3 GB of search).
static func reach(world: TileWorld, a: Vector2, b: Vector2) -> Vector2i:
	return Vector2i(mini(world.width, int(absf(a.x - b.x)) + world.width / 4), mini(world.height, int(absf(a.y - b.y)) + world.height / 8))

## The furthest node of the whole path at or near the body's node, from `at` on (a little way
## back too, for a leg that overshot and came back).
static func _progress(whole: NavPath, here: Vector2i, at: int) -> int:
	var best := at
	var bd := 1 << 30
	for i in range(maxi(0, at - 8), mini(whole.nodes.size(), at + LEG * 4)):
		var n: Vector2i = whole.nodes[i]
		var d := absi(n.x - here.x) + absi(n.y - here.y)
		if d < bd or (d == bd and i > best):
			bd = d
			best = i
	return best if bd <= 4 else at

static func _leg(world: TileWorld, b: Body, f: NavFollow, st: MoveStats, w: Dictionary) -> String:
	var dt := 1.0 / K.TICK_HZ
	var steps := maxi(1, MoveStats.step_hz() / K.TICK_HZ)
	var sdt := 1.0 / MoveStats.step_hz()
	for k in LEG_TICKS:
		var inp := f.input(world, b, dt, 2.0)
		if inp == null:
			if f.failed:
				return f.why
			inp = PlayerInput.new()
			if b.on_floor or b.on_stairs or b.climbing or b.swimming:
				return ""                 # the path is walked: at rest on something, or hanging on a rope
		for i in steps:
			PlayerController.step(world, b, inp, st, sdt)
			inp.jump_pressed = false
		w["ticks"] = int(w["ticks"]) + 1
		_note(world, b, w)
		if trace and k % 60 == 0 and k > 0:
			print("      t%d %s climbing %s floor %s input x %.2f up %s down %s jump %s node %d" % [k, b.pos, b.climbing, b.on_floor, inp.move_x, inp.up, inp.down, inp.jump, f.i])
	return "out of ticks on a leg"

## Bands, regions and ways the body reaches this tick, and what it stands on.
static func _note(world: TileWorld, b: Body, w: Dictionary) -> void:
	var leg: Dictionary = w["leg"]
	var x := floori(b.pos.x)
	var y := floori(b.pos.y)
	leg["deepest"] = minf(float(leg["deepest"]), b.pos.y)
	var band := _band(world, b.pos.y)
	var bands: Array = leg["bands"]
	if bands.is_empty() or bands[-1] != band:
		bands.append(band)
	var r := BiomeIds.region_at(world.meta, b.pos.x, b.pos.y)
	if not r.is_empty():
		var regs: Array = leg["regions"]
		var tag := "%s (%s)" % [r.get("name", ""), r["biome"]]
		if regs.is_empty() or regs[-1] != tag:
			regs.append(tag)
	var ways: Array = w["ways"]
	var inside: Dictionary = w["inside"]
	for i in ways.size():
		var wy: Dictionary = ways[i]
		var on := x >= int(wy["x0"]) and x <= int(wy["x1"]) and y >= int(wy["y0"]) and y <= int(wy["y1"])
		if on and not inside.has(i):
			inside[i] = true
			(leg["ways"] as Array).append(String(wy["kind"]))
		elif not on:
			inside.erase(i)
	var cr: Dictionary = leg["crossings"]
	var under := world.get_fg(x, y - 1)
	var kind := ""
	if b.climbing:
		kind = "rope" if TileDefs.rope[world.get_fg(x, y + 1)] != 0 or TileDefs.rope[world.get_fg(x, y)] != 0 else "ladder"
	elif b.swimming:
		kind = "swim"
	elif under == TileDefs.id("lava_bridge"):
		kind = "lava_bridge"
	elif under == TileDefs.id("cobblestone") and world.get_bg(x, y) == TileDefs.wall_id("cobble_wall") and band in ["deeps", "nadir"]:
		kind = "deep_road" if r.get("biome", "") != "deep_lake" else "shore_path"
	if kind != "":
		cr[kind] = int(cr.get(kind, 0)) + 1

static func _band(world: TileWorld, y: float) -> String:
	var bands: Dictionary = world.meta.get("bands", {})
	for k: String in bands:
		if y >= float(bands[k][0]) and y < float(bands[k][1]) + 1.0:
			return k
	return "nadir"

## What is wrong with a finished descent, as a list. Empty is a whole descent and climb back.
static func faults(world: TileWorld, r: Dictionary) -> Array:
	var out: Array = []
	if not r["down"].get("ok", false):
		out.append("down: %s" % r["down"].get("why", ""))
	if not r["back"].get("ok", false):
		out.append("back: %s" % r["back"].get("why", ""))
	if not "nadir" in (r["down"].get("bands", []) as Array):
		out.append("never reached the nadir")
	if int(r["digs"]) != 0:
		out.append("%d digs" % r["digs"])
	if r["tiles_changed"]:
		out.append("the world's tiles changed")
	return out
