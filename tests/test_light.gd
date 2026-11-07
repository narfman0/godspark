extends RefCounted

const Cat := LightEngine.Category

func run(t: TestLog) -> void:
	_torch_anchor(t)
	_walls_and_corners(t)
	_sun_and_caves(t)
	_sky_shaft(t)
	_incremental(t)
	_carried(t)
	_region_bytes_check(t)
	_own_light(t)
	_view_lights(t)
	_far_jump(t)

## A long teleport on a client: the chunks left behind are dropped and the new ones arrive, then the
## frames relight what is on screen. What is on screen comes first and what was left behind costs
## next to nothing, however slow the frames (budget 0: one unit of work a frame).
func _far_jump(t: TestLog) -> void:
	var src := WorldGen.generate_named("dev", 4)
	var w := TileWorld.new(src.width, src.height, 4, true)
	var light := LightEngine.new(w)
	light.deferred = true
	var copy := func(cx: int, cy: int) -> void:
		var from: Chunk = src.chunk_at(cx, cy)
		var c := w.ensure_chunk(cx, cy)
		c.fg = from.fg
		c.bg = from.bg
		c.liquid = from.liquid
		w.chunk_changed.emit(cx, cy)
	var around := func(at: Vector2i, r: int) -> Array:
		var out: Array = []
		for cy in range(at.y - r, at.y + r + 1):
			for cx in range(at.x - r, at.x + r + 1):
				if cx >= 0 and cy >= 0 and cx < w.chunks_x and cy < w.chunks_y:
					out.append(Vector2i(cx, cy))
		return out
	var view := func(at: Vector2i) -> Rect2i:
		return Rect2i(at * K.CHUNK - Vector2i(48, 32), Vector2i(128, 96))
	# standing in the first town, everything arrived and lit
	var town: Dictionary = (src.meta["sites"] as Array).filter(func(s: Dictionary) -> bool: return s["kind"] == "settlement")[1]
	var deep: Dictionary = (src.meta["sites"] as Array).filter(func(s: Dictionary) -> bool: return s["kind"] == "settlement" and s["band"] != "surface")[0]
	var a := Vector2i(int(town["x"]) >> 5, int(town["y"]) >> 5)
	var b := Vector2i(int(deep["x"]) >> 5, int(deep["y"]) >> 5)
	var old: Array = around.call(a, 3)
	for c: Vector2i in old:
		copy.call(c.x, c.y)
	var guard := 0
	while not light.process(1000000, view.call(a)) and guard < 1000:
		guard += 1
	# the jump: what was left behind goes first, as the host drops it
	for c: Vector2i in old:
		w.unload_chunk(c.x, c.y)
	var new_chunks: Array = around.call(b, 3)
	for c: Vector2i in new_chunks:
		copy.call(c.x, c.y)
	var want: Rect2i = view.call(b)
	# what the view would draw this frame (region_bytes computes nothing, level_at would)
	var truth := LightEngine.new(src)
	truth.ensure_region(want)
	var true_blk := truth.region_bytes(want, false)
	var true_sky := truth.region_bytes(want, true)
	var wrong := func() -> int:
		var blk := light.region_bytes(want, false)
		var sky := light.region_bytes(want, true)
		var bad := 0
		for i in range(0, blk.size(), 11):
			if absi(blk[i] - true_blk[i]) > 2 or absi(sky[i] - true_sky[i]) > 2:
				bad += 1
		return bad
	var frames := 0
	var done := false
	while not done and frames < 1000:
		done = light.process(0, want)
		frames += 1
		if wrong.call() == 0:
			break
	var on_screen := ((want.end.x - 1 >> 5) - (want.position.x >> 5) + 1) * ((want.end.y - 1 >> 5) - (want.position.y >> 5) + 1)
	print("  far jump: %d frames to light %d chunks on screen (%d left behind, %d arrived)" % [frames, on_screen, old.size(), new_chunks.size()])
	t.check(frames <= on_screen + new_chunks.size(), "what is on screen is lit in about one frame a chunk (%d frames, %d on screen)" % [frames, on_screen])
	t.eq(wrong.call(), 0, "and it is the same light a whole world gives")
	var more := 0
	while not light.process(0, want) and more < 200:
		more += 1
	t.check(light.backlog() == 0, "and what was left behind is forgotten in %d more frames" % more)
	t.eq(wrong.call(), 0, "changing nothing on screen")

## SRD torch: bright to 20 ft (8 tiles), dim another 20 ft (to 16 tiles), dark beyond.
func _torch_anchor(t: TestLog) -> void:
	var world := TileWorld.new(128, 128)
	var light := LightEngine.new(world)
	light.sun = 0.0
	world.set_fg(64, 64, TileDefs.id("torch"))
	t.eq(light.level_at(64, 64), LightEngine.TORCH, "torch tile holds TORCH")
	for d in [1, 4, 8]:
		t.eq(light.category_at(64 + d, 64), Cat.BRIGHT, "torch: bright at %d tiles right" % d)
		t.eq(light.category_at(64, 64 - d), Cat.BRIGHT, "torch: bright at %d tiles down" % d)
	for d in [9, 12, 16]:
		t.eq(light.category_at(64 - d, 64), Cat.DIM, "torch: dim at %d tiles left" % d)
		t.eq(light.category_at(64, 64 + d), Cat.DIM, "torch: dim at %d tiles up" % d)
	for d in [17, 20]:
		t.eq(light.category_at(64 + d, 64), Cat.DARK, "torch: dark at %d tiles" % d)
	t.eq(light.category_at(69, 69), Cat.BRIGHT, "torch: bright at (5, 5), 7.1 tiles")
	t.eq(light.category_at(70, 70), Cat.DIM, "torch: dim at (6, 6), 8.5 tiles")
	t.eq(light.category_at(75, 75), Cat.DIM, "torch: dim at (11, 11), 15.6 tiles")
	t.eq(light.category_at(76, 76), Cat.DARK, "torch: dark at (12, 12), 17 tiles")
	t.eq(LightEngine.strength_for_ft(40.0), LightEngine.TORCH, "a 40 ft light is a torch")
	world.set_fg(64, 64, TileDefs.AIR)
	t.eq(light.category_at(66, 64), Cat.DARK, "removing the torch darkens")

func _walls_and_corners(t: TestLog) -> void:
	var world := TileWorld.new(128, 128)
	var stone := TileDefs.id("stone")
	for y in 128:
		world.set_fg(70, y, stone, true)        # a full-height wall right of the torch
	for y in range(60, 69):
		world.set_fg(58, y, stone, true)        # a short wall left of it
	for y in range(63, 66):
		for x in range(60, 63):
			if x != 61 or y != 64:
				world.set_fg(x, y, stone, true)  # a sealed one-tile pocket at (61, 64)
	world.set_fg(64, 64, TileDefs.id("torch"), true)
	var light := LightEngine.new(world)
	t.check(light.level_at(62, 64) > 0 and light.level_at(60, 64) > 0, "the pocket's rock is lit")
	t.eq(light.level_at(61, 64), 0, "light seeping through rock never comes out into a sealed pocket")
	light.sun = 0.0
	t.check(light.level_at(70, 64) > 0, "an opaque wall face is lit")
	t.eq(light.level_at(71, 64), 0, "no light through an unbroken opaque wall")
	var behind := light.level_at(56, 64)
	var open := light.level_at(64, 64 - 8)
	t.check(behind > 0, "light bends around the end of a wall (got %d)" % behind)
	t.check(behind < open, "and loses more than in the open (%d < %d)" % [behind, open])
	# An inner corner: rock below and right of an open cell, and rock in the diagonal between
	# them. The diagonal shows a face to the room, so it takes the glow like its neighbours.
	for y in range(40, 50):
		for x in range(40, 56):
			world.set_fg(x, y, stone, true)
	for y in range(44, 48):
		for x in range(42, 48):
			world.set_fg(x, y, TileDefs.AIR, true)
	world.set_fg(44, 45, TileDefs.id("torch"), true)
	var diag := light.level_at(48, 43)
	t.check(diag > 0, "rock tucked in an inner corner is lit (got %d)" % diag)
	t.check(diag <= light.level_at(48, 44) and diag <= light.level_at(47, 43), "but no brighter than the walls beside it")
	t.eq(light.level_at(49, 42), 0, "and passes none of it on")

func _sun_and_caves(t: TestLog) -> void:
	var world := TileWorld.make_test()
	var light := LightEngine.new(world)
	var g := world.height / 2
	var mid := world.width / 2
	t.eq(light.level_at(10, g), LightEngine.SUN, "open sky above the ground is full sun")
	t.eq(light.level_at(10, world.height - 1), LightEngine.SUN, "top row is full sun")
	t.eq(light.category_at(mid + 12, g - 5), Cat.BRIGHT, "sun falls to the bottom of the pit")
	t.eq(light.level_at(10, g - 20), 0, "deep rock is dark")
	t.eq(light.category_at(mid + 3, g - 10), Cat.BRIGHT, "the cave pocket is lit by its torch")
	t.eq(light.level_at(mid, g - 1), LightEngine.SUN - LightEngine.STEP, "the first tile of rock under the sun takes its glow")
	t.eq(light.level_at(mid, g - 2), maxi(0, LightEngine.SUN - LightEngine.STEP - LightEngine.SOLID_STEP),
		"sunlight seeps into rock at SOLID_STEP per tile")
	t.eq(light.level_at(mid, g - 2), 0, "and SOLID_STEP stops it there: rock takes one tile of glow")
	light.sun = 0.0
	t.eq(light.category_at(10, g), Cat.DARK, "night: the open sky is dark")
	t.eq(light.category_at(mid - 2, g - 13), Cat.BRIGHT, "night: the cave torch still burns")
	light.sun = 0.5
	t.eq(light.level_at(10, g), roundi(LightEngine.SUN * 0.5), "sun scales sunlight")
	# Covered cell under a roof, no wall: only spread light.
	var w2 := TileWorld.new(64, 64)
	for x in range(5, 61):
		w2.set_fg(x, 30, TileDefs.id("stone"), true)
	var l2 := LightEngine.new(w2)
	t.eq(l2.level_at(32, 29), 0, "deep under a wide roof, no sun")
	t.eq(l2.category_at(7, 29), Cat.BRIGHT, "near the roof's edge, spread sun")
	t.eq(l2.level_at(32, 31), LightEngine.SUN, "on the roof, full sun")

## Incremental edits must match a fresh engine on the same world.
func _incremental(t: TestLog) -> void:
	var world := TileWorld.make_test()
	var light := LightEngine.new(world)
	var all := Rect2i(0, 0, world.width, world.height)
	light.ensure_region(all)
	var g := world.height / 2
	var mid := world.width / 2
	var changes: Array[Rect2i] = []
	light.light_changed.connect(func(r: Rect2i) -> void: changes.append(r))
	# Dig a shaft from the surface into the cave pocket.
	for y in range(g - 9, g):
		world.set_fg(mid - 6, y, TileDefs.AIR)
	t.check(not changes.is_empty(), "edits emit light_changed")
	t.check(light.level_at(mid - 6, g - 11) >= LightEngine.SUN - LightEngine.STEP * 2,
		"digging a hole to the sky lets the sun into the cave")
	# Cap the shaft again halfway, put a block in the open, remove the cave torch.
	world.set_fg(mid - 6, g - 3, TileDefs.id("stone"))
	world.set_fg(20, g + 2, TileDefs.id("stone"))
	world.set_fg(mid - 2, g - 14, TileDefs.AIR)
	world.set_fg(mid + 2, g - 12, TileDefs.id("torch"))
	world.set_fg(mid + 12, g - 1, TileDefs.id("dirt"))   # bridge over the pit
	light.add_light(7, mid - 7.5, g - 10.5, LightEngine.TORCH)
	light.move_light(7, mid - 5.2, g - 12.1)
	light.add_light(8, 40.0, g + 4.0, LightEngine.strength_for_ft(60.0))
	light.remove_light(8)
	t.eq(_diff(light, all, world), 0, "incremental updates equal a fresh recompute")
	t.check(light.level_at(mid + 12, g - 2) < LightEngine.SUN, "a placed block shades the pit")

func _carried(t: TestLog) -> void:
	var world := TileWorld.make_test()
	var light := LightEngine.new(world)
	light.sun = 0.0
	var g := world.height / 2
	t.eq(light.category_at(30, g + 3), Cat.DARK, "night surface before the light")
	light.add_light(1, 30.5, g + 3.2, LightEngine.TORCH)
	t.eq(light.level_at(30, g + 3), LightEngine.TORCH, "carried light at its tile")
	t.eq(light.category_at(36, g + 3), Cat.BRIGHT, "and lights 6 tiles away")
	t.eq(light.category_at(100, g + 3), Cat.DARK, "far away stays dark")
	light.move_light(1, 100.0, g + 3.0)
	t.eq(light.level_at(100, g + 3), LightEngine.TORCH, "carried light moved with its bearer")
	t.eq(light.category_at(30, g + 3), Cat.DARK, "and left its old spot dark")
	light.move_light(1, 30.0, g + 3.0)
	light.remove_light(1)
	t.eq(light.category_at(30, g + 3), Cat.DARK, "removing it darkens")
	var all := Rect2i(0, 0, world.width, world.height)
	light.ensure_region(all)
	t.eq(_diff(light, all, world), 0, "after carried lights, still equal to a fresh recompute")

func _diff(light: LightEngine, r: Rect2i, world: TileWorld) -> int:
	var fresh := LightEngine.new(world)
	for id: int in light._lights:
		var l: Vector3i = light._lights[id]
		fresh._lights[id] = l
	fresh.ensure_region(r)
	var bad := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if light.block_at(x, y) != fresh.block_at(x, y) or light.sky_at(x, y) != fresh.sky_at(x, y):
				if bad < 5:
					print("    differs at %d,%d: %d/%d vs %d/%d" % [x, y, light.block_at(x, y), light.sky_at(x, y), fresh.block_at(x, y), fresh.sky_at(x, y)])
				bad += 1
	return bad

func _region_bytes_check(t: TestLog) -> void:
	var world := TileWorld.make_test(64, 64)
	var light := LightEngine.new(world)
	var r := Rect2i(-3, 20, 70, 50)
	light.ensure_region(r)
	var sky := light.region_bytes(r, true)
	var blk := light.region_bytes(r, false)
	t.eq(sky.size(), r.size.x * r.size.y, "region_bytes size")
	var bad := 0
	for j in r.size.y:
		for i in r.size.x:
			var x := r.position.x + i
			var y := r.position.y + j
			if sky[i + j * r.size.x] != light.sky_at(x, y) or blk[i + j * r.size.x] != light.block_at(x, y):
				bad += 1
	t.eq(bad, 0, "region_bytes matches sky_at / block_at, padding included")

## The player lights nothing unless a light is held, worn or on (view/light_sources.gd).
func _own_light(t: TestLog) -> void:
	t.check(LightSources.own({}, {}, {}, []).is_empty(), "no source: no own light")
	t.check(LightSources.own({"base": "longsword", "count": 1}, {"main_hand": {"base": "longsword", "count": 1}}, {}, []).is_empty(),
		"a sword in hand gives no light")
	var held := LightSources.own({"base": "tile:torch", "count": 10}, {}, {}, [])
	t.eq(int(held.get("level", 0)), LightEngine.TORCH, "a torch selected in the hotbar is a torch")
	t.eq(float(held.get("radius", 0.0)), 16.0, "and reaches 16 tiles")
	t.eq(int(LightSources.own({}, {"off_hand": {"base": "tile:torch", "count": 1}}, {}, []).get("level", 0)), LightEngine.TORCH,
		"a torch in the off hand lights")
	t.eq(int(LightSources.own({}, {}, {}, ["light"]).get("level", 0)), LightEngine.strength_for_ft(40.0),
		"the Light effect lights 20 ft bright, 20 dim")
	t.eq(int(LightSources.own({}, {}, {}, ["concentration:light"]).get("level", 0)), LightEngine.strength_for_ft(40.0),
		"a concentration effect's name is the spell's")
	var glow := LightSources.own({}, {}, {"light": 6}, [])
	t.eq(int(glow.get("level", 0)), LightEngine.DIM_MIN + 6 * LightEngine.STEP, "a Lantern spark alone glows 6 tiles")
	t.eq(LightEngine.category_of(int(glow["level"])), Cat.DIM, "and its glow is dim")
	t.eq(int(LightSources.own({"base": "tile:torch", "count": 1}, {}, {"light": 6}, []).get("level", 0)),
		LightEngine.TORCH + 6 * LightEngine.STEP, "with a torch held, the spark widens it")
	t.eq(int(LightSources.own({"base": "tile:torch", "count": 1}, {}, {}, ["light"]).get("level", 0)), LightEngine.TORCH,
		"two lights: the stronger")
	# The real items mirror: the light follows the selected slot and the off hand.
	var items := ItemsClient.new()
	items.inventory.put(3, Items.make("tile:torch", 10))
	items.inventory.selected = Inventory.ATTACK_SLOT
	t.check(LightSources.of_items(items, []).is_empty(), "items: the attack slot selected, no light")
	items.select_hotbar(3)
	t.eq(int(LightSources.of_items(items, []).get("level", 0)), LightEngine.TORCH, "items: the torch slot selected, a torch")
	items.select_hotbar(4)
	t.check(LightSources.of_items(items, []).is_empty(), "items: another slot, the torch is put away")
	items.equipment.worn["off_hand"] = Items.make("tile:torch", 1)
	t.eq(int(LightSources.of_items(items, []).get("level", 0)), LightEngine.TORCH, "items: a torch worn in the off hand lights")
	items.equipment.worn.erase("off_hand")
	t.check(LightSources.of_items(items, ["light"]).size() > 0, "items: the Light effect on, a light")
	t.check(LightSources.of_items(null, []).is_empty(), "no items mirror, no light")

## Sunlight is a shaft: full down the open column, falling off fast sideways under cover.
func _sky_shaft(t: TestLog) -> void:
	var cov := LightEngine.sky_covered_step()
	t.check(cov >= 2 * LightEngine.STEP, "covered sky falls off faster than open light (%d)" % cov)
	var w := TileWorld.new(96, 64)
	var stone := TileDefs.id("stone")
	for x in 96:
		w.set_fg(x, 0, stone, true)            # a floor
	for x in range(10, 90):
		if x != 50:
			w.set_fg(x, 20, stone, true)       # a roof with one hole at x = 50
	var l := LightEngine.new(w)
	t.eq(l.level_at(5, 10), LightEngine.SUN, "open air beside the roof is full sun")
	t.eq(l.level_at(50, 1), LightEngine.SUN, "down the hole's open column, full sun to the floor")
	t.eq(l.level_at(50, 19), LightEngine.SUN, "and just under the roof")
	t.eq(l.level_at(51, 1), LightEngine.SUN - LightEngine.STEP, "one tile beside the shaft: the first step costs STEP")
	t.eq(l.level_at(52, 1), LightEngine.SUN - LightEngine.STEP - cov, "two tiles: then sky_covered_step a tile")
	t.eq(l.level_at(49, 1), l.level_at(51, 1), "the same both sides")
	t.eq(l.category_at(53, 1), Cat.BRIGHT, "three tiles beside it is still Bright")
	t.eq(l.category_at(57, 1), Cat.DARK, "seven tiles beside it is Darkness (a torch would still reach)")
	t.eq(l.category_at(11, 10), Cat.BRIGHT, "a tile in under the roof's edge is Bright")
	t.eq(l.category_at(17, 10), Cat.DARK, "seven tiles in, Darkness")
	t.eq(l.level_at(30, 10), 0, "deep under the roof, nothing")
	# A torch under the same roof keeps its SRD reach: the covered falloff is the sky's alone.
	w.set_fg(30, 1, TileDefs.id("torch"), true)
	var l2 := LightEngine.new(w)
	t.eq(l2.category_at(38, 1), Cat.BRIGHT, "a torch under cover: bright at 8 tiles")
	t.eq(l2.category_at(46, 1), Cat.DIM, "dim at 16")
	t.eq(l2.category_at(30, 17), Cat.DIM, "dim at 16 up")
	# Edits keep the shaft exact: close the hole, open another, compare with a fresh engine.
	l2.ensure_region(Rect2i(0, 0, 96, 64))
	w.set_fg(50, 20, stone)
	w.set_fg(70, 20, TileDefs.AIR)
	t.eq(l2.level_at(70, 1), LightEngine.SUN, "a new hole: its shaft")
	t.eq(l2.level_at(50, 1), 0, "the closed hole goes dark")
	t.eq(_diff(l2, Rect2i(0, 0, 96, 64), w), 0, "covered sky: incremental edits equal a fresh recompute")

## The view's lights: the lamp pool takes the nearest sources, the sun follows the clock.
func _view_lights(t: TestLog) -> void:
	var cands := [{"key": "a", "pos": Vector2(10, 0)}, {"key": "b", "pos": Vector2(2, 0)},
		{"key": "c", "pos": Vector2(-5, 0)}, {"key": "d", "pos": Vector2(0, 30)}]
	var p := WorldLights.pick(cands, Vector2.ZERO, 2)
	t.eq(p.size(), 2, "pick: n of them")
	t.eq(String(p[0]["key"]) + String(p[1]["key"]), "bc", "pick: the nearest, nearest first")
	t.eq(String(WorldLights.pick(cands, Vector2(0, 28), 1)[0]["key"]), "d", "pick: nearest to where the camera is")
	t.eq(WorldLights.pick(cands, Vector2.ZERO, 24).size(), 4, "pick: fewer sources than lamps, all of them")
	# Emitters from a chunk's mesh build, carried lights from the presenter, into the pool.
	var world := TileWorld.new(96, 64)
	var torch := TileDefs.id("torch")
	for x: int in [4, 20, 40, 60, 90]:
		world.set_fg(x, 10, torch, true)
	var em := ChunkMesher.emitters(ChunkMesher.snapshot(world, 0, 0))
	t.eq(em.size(), 2, "a chunk lists its light-giving tiles")
	t.eq(em[0], Vector3i(4, 10, torch), "with their world tile and id")
	var view := WorldView.new()
	for cx in 3:
		view.emitters[Vector2i(cx, 0)] = ChunkMesher.emitters(ChunkMesher.snapshot(world, cx, 0))
	view.focus = Vector2(45, 10)
	view.view_half = Vector2(40, 24)
	view.carry(7, Vector2(47, 11), LightSources.row("tile:torch"))
	var lights := WorldLights.new()
	view.add_child(lights)
	lights.setup(view)
	lights.max_lights = 3
	lights._lamps()
	var keys: Array = lights.lit.map(func(c: Dictionary) -> String: return String(c["key"]))
	t.eq(keys, ["c7", "t40,10", "t60,10"], "the pool lights the nearest three: the carried torch, then the tiles")
	var shown := 0
	for o: OmniLight3D in lights._pool:
		shown += 1 if o.visible else 0
	t.eq(shown, 3, "three lamps on")
	view.focus = Vector2(5, 10)
	lights._lamps()
	t.eq(String(lights.lit[0]["key"]), "t4,10", "the camera moves: the pool follows it")
	t.eq(lights._pool.size(), 3, "and reuses its lamps")
	view.carry(7, Vector2.ZERO, {})
	t.check(not view.carried.has(7), "a light put out leaves the view")
	view.free()
	# The sun's angle and colour follow the clock.
	var noon := WorldLights.sun_dir(12.25)
	var morning := WorldLights.sun_dir(8.0)
	var evening := WorldLights.sun_dir(16.5)
	t.check(noon.y > morning.y and noon.y > evening.y, "the sun is highest at noon")
	t.check(morning.x > 0.3 and evening.x < -0.3, "it rises on one side and sets on the other")
	t.check(noon.z > 0.2 and morning.z > 0.2 and evening.z > 0.2, "always a little in front of the play plane")
	t.check(WorldLights.is_day(12.0) and not WorldLights.is_day(23.0), "day is the sun, night the moon")
	var midnight := WorldLights.sun_dir(0.25)
	t.check(midnight.y > WorldLights.sun_dir(21.0).y, "the moon climbs through the night too")
	var lnoon := WorldLights.sun_light(12.25)
	var lnight := WorldLights.sun_light(0.25)
	t.check(float(lnoon["energy"]) > 3.0 * float(lnight["energy"]) and float(lnight["energy"]) > 0.0, "moonlight is faint, not none")
	t.check((lnight["color"] as Color).b > (lnight["color"] as Color).r, "and blue")
	t.check((WorldLights.sun_light(7.0)["color"] as Color).b < (lnoon["color"] as Color).b, "the low sun is warmer than noon")
	t.check(float(WorldLights.sun_light(18.5)["energy"]) < 0.01, "at the hand-over nothing shines, so no shadow jumps")
	t.check(midnight.y < noon.y - 0.2, "the moon rides lower than the noon sun: long shadows")
	t.check(WorldView.night_visual() <= 0.12 and WorldView.night_visual() > WorldClock.MOON,
		"night draws the sky field near the rules' moon, a little over it (%.2f)" % WorldView.night_visual())
