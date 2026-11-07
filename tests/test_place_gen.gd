## Settlements laid out at worldgen (stage "places", PlaceBuilder): they match the sim, lots
## never overlap, anchors stand on floors, the street is open end to end, a Medium walker
## (the real controller) walks the street, climbs to every upper floor and comes back out,
## and places survive save and load. Old worlds without places still load and run.
extends RefCounted

func run(t: TestLog) -> void:
	_templates(t)
	var world := WorldGen.generate_named("dev", 5)
	var took := int(WorldGen.last_timings.get("places", 999))
	if took >= 150:           # other processes run beside this one (tools/test.sh): a second sample
		WorldGen.generate_named("dev", 5)
		took = mini(took, int(WorldGen.last_timings.get("places", 999)))
	t.check(took < 150, "the places stage is quick (%d ms)" % took)
	_matches_sim(t, world)
	_layout(t, world)
	_walks(t, world)
	_spawn(t, world)
	_save(t, world)
	_old_world(t)

func _templates(t: TestLog) -> void:
	PlaceStyles.ensure()
	for kind in ["home", "smithy", "store", "tavern", "hall", "shrine", "market", "gate"]:
		t.check(not PlaceStyles.templates_of(kind).is_empty(), "a template for " + kind)
	for n in ["home", "home_tall", "smithy", "store", "store_tall", "tavern", "hall", "shrine", "square", "market", "gate"]:
		var tp := PlaceStyles.template(n)
		var cs: PackedByteArray = tp["cells"]
		var w := int(tp["w"])
		# the feet row and the three rows above are open at both ends (the street runs through)
		var open_ends := true
		for dy in 4:
			for dx in [0, w - 1]:
				if TileDefs.solid[PlaceBuilder._legend(char(cs[dx + dy * w]), PlaceStyles.style("human")["ids"], 0)[0]] != 0:
					open_ends = false
		t.check(open_ends, "%s: doorways 4 rows tall at both ends" % n)
	for c in ["human", "halfling", "dwarf", "elf", "drow", "goblinoid", "bandit", "gnome", "kobold"]:
		t.check(not PlaceStyles.style(c).is_empty(), "a style for " + c)
	t.eq(PlaceStyles.style_name("bandit"), "raider", "bandits build camps")
	t.eq(PlaceStyles.style_name("nobody"), "human", "unknown cultures fall back")

func _matches_sim(t: TestLog, world: TileWorld) -> void:
	var sim := WorldSim.from_meta(world.meta, world.world_seed)
	var n := 0
	for sid: int in sim.settlements:
		var p := Places.place(world, sid)
		var s: SimSettlement = sim.settlements[sid]
		if p.is_empty():
			continue
		n += 1
		t.eq([p["culture"], p["tier"]], [s.culture, s.tier], "site %d: the place has the sim's culture and tier" % sid)
		t.check(not p["buildings"].is_empty(), "site %d: a settled place has buildings" % sid)
	t.check(n >= 4, "most settlements are laid out (%d)" % n)
	for k: String in Places.all(world):
		if not sim.settlements.has(int(k)):
			t.eq(Places.place(world, int(k))["buildings"], [], "an unsettled site is laid out but empty")

func _layout(t: TestLog, world: TileWorld) -> void:
	var kinds := {}
	for k: String in Places.all(world):
		var p: Dictionary = Places.all(world)[k]
		var x0 := int(p["street"][0])
		var x1 := int(p["street"][1])
		var y := int(p["street"][2])
		var rects: Array[Rect2i] = []
		var ok_overlap := true
		for i in (p["lots"] as Array).size():
			var r := PlaceBuilder.lot_rect(p, i)
			for o: Rect2i in rects:
				if o.intersects(r):
					ok_overlap = false
			rects.append(r)
			if r.position.x < x0 - 3 or r.end.x > x1 + 4:
				ok_overlap = false
		t.check(ok_overlap, "site %s: lots do not overlap and stay on the street" % k)
		var open := true
		for x in range(x0, x1 + 1):
			if not world.is_solid(x, y - 1):
				open = false
			for dy in 4:
				if world.is_solid(x, y + dy):
					open = false
		t.check(open, "site %s: the street is floored and 4 rows clear end to end" % k)
		var anchors_ok := true
		for b: Dictionary in p["buildings"]:
			kinds[b["kind"]] = true
			for role: String in b["anchors"]:
				for c: Array in b["anchors"][role]:
					var cx := int(c[0])
					var cy := int(c[1])
					var floor_ok := world.is_solid(cx, cy - 1) or TileDefs.platform[world.get_fg(cx, cy - 1)] != 0 \
							or TileDefs.ladder[world.get_fg(cx, cy - 1)] != 0
					if world.is_solid(cx, cy) or world.is_solid(cx, cy + 1) or world.is_solid(cx, cy + 2) or not floor_ok:
						anchors_ok = false
			var d: Array = b["door"]
			if world.is_solid(int(d[0]), int(d[1])) or int(d[1]) != y:
				anchors_ok = false
		t.check(anchors_ok, "site %s: anchors and doors are open feet cells with a floor" % k)
	# every dressing record in the world (building pieces, signposts) stands where it holds
	var bad := []
	var pieces := 0
	for cy in world.chunks_y:
		for cx in world.chunks_x:
			for r: Dictionary in Dressing.records_in(world, cx, cy):
				if String(Dressing.def(r["id"]).get("where", {}).get("band", "")) == "place":
					pieces += 1
				if not Dressing.holds(world, r["id"], r["x"], r["y"]):
					bad.append([Dressing.name_of(r["id"]), r["x"], r["y"]])
	t.check(pieces > 20, "places are dressed (%d pieces)" % pieces)
	t.check(bad.is_empty(), "every dressing record holds where it stands %s" % [bad.slice(0, 5)])
	for kind in ["home", "shrine", "smithy", "market"]:
		t.check(kinds.has(kind), "some place has a " + kind)

## The real controller: street end to end, and up to each upper floor and back to the street.
func _walks(t: TestLog, world: TileWorld) -> void:
	var st := NavMaps.stats("medium")
	var uppers := 0
	var up_ok := 0
	for k: String in Places.all(world):
		var p: Dictionary = Places.all(world)[k]
		if p["buildings"].is_empty():
			continue
		var y := int(p["street"][2])
		var a := Vector2(int(p["street"][0]) + 1.5, y)
		var b := Vector2(int(p["street"][1]) - 1.5, y)
		var r := walk(world, st, a, b)
		t.check(r["reached"], "site %s: a Medium walker crosses the street end to end (%s at %s)" % [k, r["why"], r["pos"]])
		var back := walk(world, st, b, a)
		t.check(back["reached"], "site %s: and back (%s at %s)" % [k, back["why"], back["pos"]])
		for bld: Dictionary in p["buildings"]:
			for c: Array in bld["anchors"].get("townsfolk", []) + bld["anchors"].get("guard", []):
				if int(c[1]) <= y:
					continue
				uppers += 1
				var door := Vector2(int(bld["door"][0]) + 0.75, y)
				var top := Vector2(int(c[0]) + 0.5, int(c[1]))
				var go := NavMaps.run({"world": world, "start": door, "goal": top}, st, 900)
				var out := NavMaps.run({"world": world, "start": top, "goal": door}, st, 900) if go["reached"] else go
				if go["reached"] and out["reached"]:
					up_ok += 1
				else:
					t.check(false, "site %s %s: up to %s and out (%s / %s)" % [k, bld["kind"], c, go["why"], out["why"]])
	t.check(uppers > 0, "the world has upper floors to climb to (%d)" % uppers)
	t.eq(up_ok, uppers, "every upper floor is reached from the door and left again")

## NavMaps.run in legs of at most LEG columns (the planner's window is 64): the body carries
## on from where each leg ended. Waypoints are on the start's row.
const LEG := 40
static func walk(world: TileWorld, st: MoveStats, a: Vector2, b: Vector2, ticks_per_leg := 900) -> Dictionary:
	var pos := a
	var r := {"reached": false, "why": "", "pos": a}
	while true:
		var d := b.x - pos.x
		var goal := b if absf(d) <= LEG else Vector2(floorf(pos.x + signf(d) * LEG) + 0.5, a.y)
		r = NavMaps.run({"world": world, "start": pos, "goal": goal}, st, ticks_per_leg)
		if not r["reached"]:
			return r
		pos = r["pos"]
		if goal == b:
			return r
	return r

## New players start on the square of the first settled surface place.
func _spawn(t: TestLog, world: TileWorld) -> void:
	var at: Vector2 = load("res://game/main.gd").spawn_for(world, Vector2.ZERO)
	var sid := Places.street_at(world, floori(at.x))
	t.check(sid.x >= 0 and int(at.y) == sid.y and Places.place(world, sid.x)["tier"] != "", "the spawn is on a settled place's street (%s)" % at)
	t.check(not world.is_solid(floori(at.x), int(at.y)) and world.is_solid(floori(at.x), int(at.y) - 1), "standing on the ground")

func _save(t: TestLog, world: TileWorld) -> void:
	var dir := "user://test_place_gen"
	t.eq(WorldSave.save(world, dir), OK, "saves")
	var back := WorldSave.load(dir)
	t.check(back != null and back.meta.get("places") == world.meta["places"], "places round-trip through save and load")
	t.check(back != null and back.content_hash() == world.content_hash(), "with their tiles and dressing")
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)

func _old_world(t: TestLog) -> void:
	var world := WorldGen.generate(512, 256, 7)
	world.meta.erase("places")
	t.eq(Places.all(world), {}, "an old world has no places")
	var host := WorldHost.new(world)
	host.add_player("old", 1)
	for i in 30:
		host.tick()
	t.check(host.sim != null and host.tick_count == 30, "an old world without places still loads and runs")
