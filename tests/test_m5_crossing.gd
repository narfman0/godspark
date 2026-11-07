## The goal's first clause on a world the suite can afford (2048 wide, both climate orders): the real
## controller walks from the cold end to the hot end on the surface, all five biomes in climate
## order, over the pass and the river, with no digging, and leaves the world's tiles as they were.
## tools/crossing.gd is the same walk on medium worlds.
extends RefCounted

const SEEDS := [1, 4]

func run(t: TestLog) -> void:
	var orders := {}
	for sd: int in SEEDS:
		var world := WorldGen.generate_named("dev", sd)
		orders[String(world.meta["climate"]["order"])] = true
		_walks(t, world, sd)
	t.eq(orders.size(), 2, "both climate orders walked (%s)" % [orders.keys()])
	_a_blocked_pass_stops_it(t)
	_faults_are_seen(t)

func _walks(t: TestLog, world: TileWorld, sd: int) -> void:
	var r := CrossingBot.walk(world)
	var label := "dev seed %d" % sd
	t.check(r["ok"], "%s: the walker reached the hot end (%s)" % [label, r["why"]])
	t.eq(CrossingBot.faults(world, r), [], "%s: a whole crossing" % label)
	var strip: Array = world.meta["biomes"]
	var got: Array = (r["entered"] as Array).map(func(e: Dictionary) -> String: return String(e["biome"]))
	var want: Array = strip.map(func(s: Dictionary) -> String: return String(s["biome"]))
	t.eq(got, want, "%s: every biome entered in the strip's order" % label)
	var five: Array = BiomeIds.generated("surface")
	five.sort()
	var seen := got.duplicate()
	seen.sort()
	t.eq(seen, five, "%s: all five biomes" % label)
	for i in range(1, strip.size()):
		t.check(float(strip[i]["temp"]) > float(strip[i - 1]["temp"]), "%s: %s is hotter than %s" % [label, strip[i]["biome"], strip[i - 1]["biome"]])
		t.check(float(r["entered"][i]["t"]) > float(r["entered"][i - 1]["t"]), "%s: entered %s later than %s" % [label, strip[i]["biome"], strip[i - 1]["biome"]])
	var passes := 0
	var rivers := 0
	for c: Dictionary in r["crossed"]:
		if c["kind"] == "pass":
			passes += 1
		elif c["kind"] in ["bridge", "ford"]:
			rivers += 1
	t.check(passes >= 1, "%s: over a pass (%d)" % [label, passes])
	t.check(rivers >= 1, "%s: over a river (%d)" % [label, rivers])
	t.eq(int(r["digs"]), 0, "%s: digs=0" % label)
	t.check(not r["tiles_changed"], "%s: the world's tiles are as they were" % label)
	# on-screen pace: a walker's top speed is a bound on any honest time
	var tiles := int(r["end"]) - int(r["start"])
	t.check(float(r["seconds"]) * NavMaps.stats("medium").run_speed >= tiles, "%s: %d tiles in %.0f s is no faster than a body runs" % [label, tiles, r["seconds"]])

## The walls are a barrier: stop up the pass and the same walker does not get past the range.
func _a_blocked_pass_stops_it(t: TestLog) -> void:
	var world := WorldGen.generate_named("dev", 1)
	var rg: Dictionary = world.meta["barriers"]["ranges"][0]
	var path: Array = rg["pass"]["path"]
	var mid: Array = path[path.size() / 2]
	var stone := TileDefs.id("stone")
	for k in range(-1, 40):
		for dx in 3:
			world.set_fg(int(mid[0]) + dx, int(mid[1]) + k, stone, true)
	var r := CrossingBot.walk(world)
	t.check(not r["ok"], "with its pass stopped the range cannot be crossed on foot (%s)" % r["why"])
	t.check((r["crossed"] as Array).all(func(c: Dictionary) -> bool: return c["kind"] != "pass"), "and no pass is reported")

## The checker itself: each kind of failure is reported.
func _faults_are_seen(t: TestLog) -> void:
	var world := WorldGen.generate(2048, 1024, 1, {"stop_after": "names"})
	var good := {"ok": true, "why": "", "digs": 0, "tiles_changed": false, "below": 0.0, "crossed": [], "entered": []}
	for s: Dictionary in world.meta["biomes"]:
		good["entered"].append({"biome": s["biome"]})
	for span: Dictionary in CrossingBot.spans(world):
		good["crossed"].append({"kind": span["kind"], "name": span["name"], "off": 0.0})
	t.eq(CrossingBot.faults(world, good), [], "a good walk has no faults")
	for bad: Array in [["digs", 3], ["tiles_changed", true], ["below", 40.0], ["entered", []], ["crossed", []], ["ok", false]]:
		var r := good.duplicate()
		r[bad[0]] = bad[1]
		t.check(not CrossingBot.faults(world, r).is_empty(), "a walk with %s = %s has a fault" % bad)
	var off := good.duplicate(true)
	off["crossed"][0]["off"] = 20.0
	t.check(not CrossingBot.faults(world, off).is_empty(), "so has one that went round a crossing's way (say under a range)")
