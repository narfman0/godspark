extends RefCounted

func run(t: TestLog) -> void:
	var world := TileWorld.make_test()
	t.eq(Places.place(world, 3), {}, "a world without places has none")
	t.eq(Places.route_path(world, 0), [], "nor routes")
	world.meta = {
		"sites": [{"id": 3, "kind": "settlement", "x": 40, "y": 64}, {"id": 4, "kind": "settlement", "x": 90, "y": 64}],
		"routes": [{"id": 0, "a": 3, "b": 4, "kind": "road", "length": 50},
			{"id": 1, "a": 3, "b": 4, "kind": "road", "length": 52, "path": [[40, 64], [60, 66], [90, 64]]}],
		"places": {"3": {"site": 3, "rect": [30, 64, 20, 8], "culture": "human", "tier": "village",
			"buildings": [{"kind": "smithy", "rect": [32, 64, 6, 5], "door": [34, 64], "anchors": {"smith": [[35, 64]]}},
				{"kind": "home", "rect": [40, 64, 5, 5], "door": [42, 64], "anchors": {"townsfolk": [[41, 64], [43, 64]]}}]}},
	}
	t.eq(Places.place(world, 3)["tier"], "village", "a place by site id")
	t.eq(Places.buildings(world, 3, "smithy").size(), 1, "buildings by kind")
	t.eq(Places.anchors(world, 3, "smith"), [Vector2i(35, 64)], "anchors for a role")
	t.eq(Places.anchors(world, 3, "townsfolk").size(), 2, "several anchors")
	t.eq(Places.anchors(world, 3, "priest"), [Vector2i(40, 64)], "no anchor falls back to the site")
	t.eq(Places.anchors(world, 4, "guard"), [Vector2i(90, 64)], "a site with no place falls back too")
	t.eq(Places.route_path(world, 0), [Vector2i(40, 64), Vector2i(90, 64)], "a route without a path is its two sites")
	t.eq(Places.route_path(world, 1).size(), 3, "a stored path")
	t.eq(Places.route_point(world, 1, 0.5), Vector2i(60, 66), "a point along it")
	t.eq(Places.route_point(world, 1, 1.0), Vector2i(90, 64), "its end")
