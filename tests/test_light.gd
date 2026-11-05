extends RefCounted

const Cat := LightEngine.Category

func run(t: TestLog) -> void:
	_torch_anchor(t)
	_walls_and_corners(t)
	_sun_and_caves(t)
	_incremental(t)
	_carried(t)

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
	world.set_fg(64, 64, TileDefs.id("torch"), true)
	var light := LightEngine.new(world)
	light.sun = 0.0
	t.check(light.level_at(70, 64) > 0, "an opaque wall face is lit")
	t.eq(light.level_at(71, 64), 0, "no light through an unbroken opaque wall")
	var behind := light.level_at(56, 64)
	var open := light.level_at(64, 64 - 8)
	t.check(behind > 0, "light bends around the end of a wall (got %d)" % behind)
	t.check(behind < open, "and loses more than in the open (%d < %d)" % [behind, open])

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
	t.eq(light.level_at(mid, g - 7), 0, "rock between the cave and the surface is dark")
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
