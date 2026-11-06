## Growth and ruin (PlaceKeeper): a sim that grows a town, founds a hamlet on an empty site
## and abandons a settlement changes the tiles, the dressing and meta.places; changes wait
## while a player can see the place; everything survives save and load.
extends RefCounted

func run(t: TestLog) -> void:
	var world := WorldGen.generate_named("dev", 2)
	var host := WorldHost.new(world)
	var town := -1
	var empty := -1
	for k: String in Places.all(world):
		var p: Dictionary = Places.all(world)[k]
		var surface: bool = int(p["street"][2]) > world.height / 2
		if surface and p["tier"] == "" and empty < 0:
			empty = int(k)
		elif surface and p["tier"] in ["village", "town"] and town < 0:
			town = int(k)
	t.check(town >= 0 and empty >= 0, "a settled place and an empty laid-out site (%d, %d)" % [town, empty])
	if town < 0 or empty < 0:
		return
	var sim := host.sim
	var before: int = Places.buildings(world, town).size()
	host.drain()

	# Growth, first while a player stands in the town: it waits.
	sim.settlements[town].tier = "city"
	var p := host.add_player("watcher", 1)
	var st: Array = Places.place(world, town)["street"]
	host.teleport(p, Vector2(int(st[0]) + 4.5, int(st[2])))
	_ticks(host, 2)
	t.check(host.places_keeper.waiting.has(town), "a change waits while a player can see the place")
	t.eq(Places.buildings(world, town).size(), before, "nothing popped in under the player's eyes")
	host.teleport(p, Vector2(int(st[1]) + 300.5, world.height - 2))   # far away (it falls, never mind)
	_ticks(host, 2)
	t.eq(Places.place(world, town)["tier"], "city", "the town became a city once out of view")
	var after: int = Places.buildings(world, town).size()
	t.check(after > before, "more buildings stand (%d -> %d)" % [before, after])
	var ev := host.drain()
	var tiles := 0
	var objs := 0
	for e: Dictionary in ev:
		if e["type"] == WorldHost.Ev.TILE:
			tiles += 1
		elif e["type"] == WorldHost.Ev.OBJECTS:
			objs += 1
	t.check(tiles > 50, "clients hear of it as tile changes (%d, objects %d)" % [tiles, objs])
	t.check(_built_tiles_ok(world, town), "every built lot's walls stand in the tiles")

	# Founding on the empty site.
	var fid: int = sim.factions.keys()[0]
	sim._new_settlement(empty, "halfling", fid, 60)
	_ticks(host, 2)
	var fp := Places.place(world, empty)
	t.eq([fp["tier"], fp["style"]], ["hamlet", "halfling"], "a founding stamps a hamlet in the founder's style")
	t.check(Places.buildings(world, empty, "home").size() >= 3, "with its homes")
	t.check(_built_tiles_ok(world, empty), "standing in the tiles")
	var dressed := 0
	for e: Dictionary in host.drain():
		if e["type"] == WorldHost.Ev.OBJECTS:
			dressed += 1
	t.check(dressed > 0, "and furnished (OBJECTS sent for %d chunks)" % dressed)

	# Abandonment.
	sim.settlements.erase(town)
	sim.ruins[town] = true
	_ticks(host, 2)
	var rp := Places.place(world, town)
	t.eq(rp["tier"], "", "an abandoned place has no tier")
	var ruined := true
	for b: Dictionary in rp["buildings"]:
		if b["kind"] != "ruin":
			ruined = false
	t.check(ruined and not rp["buildings"].is_empty(), "every building is a ruin")
	var roofless := true
	for b: Dictionary in rp["buildings"]:
		var r: Array = b["rect"]
		for x in range(int(r[0]), int(r[0]) + int(r[2])):
			for y in range(int(r[1]) + 2, int(r[1]) + int(r[3])):
				if world.is_solid(x, y):
					roofless = false
	t.check(roofless, "ruins have lost walls, floors and roofs")
	var open := true
	for x in range(int(rp["street"][0]), int(rp["street"][1]) + 1):
		for dy in range(1, 4):
			if world.is_solid(x, int(rp["street"][2]) + dy):
				open = false
	t.check(open, "the street through the ruins stays open (rubble is one tile high)")

	# Persistence.
	var dir := "user://test_place_keeper"
	t.eq(WorldSave.save(world, dir), OK, "the world saves")
	var back := WorldSave.load(dir)
	t.check(back != null and back.meta["places"] == world.meta["places"], "places survive save and load")
	t.check(back != null and back.content_hash() == world.content_hash(), "and so do the changed tiles and dressing")
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)

func _ticks(host: WorldHost, seconds: int) -> void:
	for i in seconds * K.TICK_HZ:
		host.tick()

## Each built lot's side-wall lintel and ceiling are solid where the template says so.
func _built_tiles_ok(world: TileWorld, sid: int) -> bool:
	var place := Places.place(world, sid)
	for i in (place["lots"] as Array).size():
		var lot: Dictionary = place["lots"][i]
		if lot["state"] != "built":
			continue
		var tp := PlaceStyles.template(PlaceBuilder.shown(place, i))
		var cs: PackedByteArray = tp["cells"]
		var w := int(tp["w"])
		for dy in int(tp["h"]):
			for dx in w:
				var ch := char(cs[dx + dy * w])
				var solid := world.is_solid(int(lot["x"]) + dx, int(place["street"][2]) + dy)
				if (ch in ["#", "=", "+"]) != solid:
					return false
	return true
