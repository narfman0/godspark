## The descent is a journey (M6 track deep, item 3): on a 2048-wide world a walker goes from the
## spawn down to the nadir floor and back up on foot, the real controller, never digging
## (DescentBot, as tools/crossing.gd descent does on medium worlds); every surface biome has a
## way in; the world has three kinds of way at least; sinkholes are built to be climbed.
extends RefCounted

func run(t: TestLog) -> void:
	var w := WorldGen.generate_named("dev", 2)
	_ways(t, w)
	_sinkholes(t, w)
	var r := DescentBot.descent(w)
	t.eq(DescentBot.faults(w, r), [], "dev seed 2: down to the nadir floor and back (%s)" % r.get("why", ""))
	t.eq(int(r["digs"]), 0, "digs=0")
	t.check(not r["tiles_changed"], "and the world's tiles are as they were")
	var bands: Array = r["down"].get("bands", [])
	for b: String in ["surface", "caves", "deeps", "nadir"]:
		t.check(b in bands, "the way down passes through the %s (%s)" % [b, " > ".join(bands)])
	t.check(not (r["down"].get("regions", []) as Array).is_empty(), "and through named regions (%s)" % [r["down"].get("regions", [])])
	t.check(not (r.get("ways", {}) as Dictionary).is_empty(), "it went in by a way from the surface (%s)" % [r.get("ways", {})])
	t.check(String(r["back"].get("bands", [""])[-1]) == "surface", "and came back up to the surface")
	print("  descent dev 2: %.0f s down, %.0f s back on screen; ways %s; regions %s" % [float(r["down"].get("seconds", 0.0)),
		float(r["back"].get("seconds", 0.0)), r.get("ways", {}), r["down"].get("regions", [])])

## Every surface biome has a way in, and the world has three kinds of way or more.
func _ways(t: TestLog, w: TileWorld) -> void:
	var ways: Array = w.meta["descent"]["ways"]
	var kinds := {}
	for wy: Dictionary in ways:
		kinds[wy["kind"]] = true
	t.check(kinds.size() >= 3, "three kinds of way in at least (%s)" % [kinds.keys()])
	for seg: Dictionary in BiomeIds.strip(w.meta):
		var n := 0
		for wy: Dictionary in ways:
			var mid := (int(wy["x0"]) + int(wy["x1"])) / 2
			if mid >= int(seg["x0"]) and mid <= int(seg["x1"]):
				n += 1
		t.check(n > 0, "the %s has a way in (%d)" % [seg["biome"], n])

## A sinkhole: a deck the road walks, a rope from it to the chamber floor, room to climb.
func _sinkholes(t: TestLog, w: TileWorld) -> void:
	var sk: Array = w.meta["descent"]["sinkholes"]
	t.check(sk.size() >= 2, "dev seed 2 has sinkholes (%d)" % sk.size())
	var st := NavMaps.stats("medium")
	for s: Dictionary in sk:
		var rc := int(s["rope"])
		var top := int(s["top"])
		var bottom := int(s["bottom"])
		var broken := 0
		for y in range(bottom, top):
			if TileDefs.rope[w.get_fg(rc, y)] == 0:
				broken += 1
		t.eq(broken, 0, "sinkhole at %d: one rope from the deck to the chamber floor" % rc)
		t.check(w.is_solid(rc - 1, bottom - 1) or w.is_solid(rc, bottom - 1), "and a floor at its foot")
		var walls := 0
		for y in range(bottom, top - 1):
			if w.is_solid(rc - 1, y) or w.is_solid(rc, y):
				walls += 1
		t.eq(walls, 0, "a climber's box is clear the whole way (%d rows)" % (top - bottom))
		for x in range(int(s["x0"]), int(s["x1"]) + 1):
			var g := w.get_fg(x, top - 1)
			t.check(w.is_solid(x, top - 1) or TileDefs.platform[g] != 0 or TileDefs.rope[g] != 0, "the deck holds a body at %d" % x)
		var leg := NavMaps.run({"world": w, "start": Vector2(rc, top), "goal": Vector2(rc, maxi(bottom, top - 40))}, st, 1200)
		t.check(leg["reached"], "sinkhole at %d: the real controller climbs down the rope (%s)" % [rc, leg["why"]])
		var up := NavMaps.run({"world": w, "start": Vector2(rc, bottom), "goal": Vector2(rc, mini(top, bottom + 40))}, st, 1200)
		t.check(up["reached"], "and up it from the chamber (%s)" % up["why"])
