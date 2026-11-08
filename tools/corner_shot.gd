## A picture of every kind of corner the soft terrain mesher draws, in a torch-lit room cut out
## of rock: a one-tile bump and a one-tile hole in the floor, a notch in the ceiling, a step, a
## pillar, so a corner that comes out black or white is easy to spot. Runs under
## tools/soft_godot.sh (CPU Vulkan).
##   tools/soft_godot.sh -s res://tools/corner_shot.gd -- out=/tmp/x.png [hard=1] [zoom=2] [sky=1]
##     [region=fungal|crystal|deep_lake|magma] [liquid=water|lava] [shadows=low]
##     sky=1: the same shapes open to the sky by day (white corners), else underground by torch.
##     region: the room cut from that region's rock, floor and wall tiles, the world's meta naming
##     the region (its rock glow and fog), not plain stone.
##     liquid: a basin left of the room, its floor a stair of single steps down into water or lava,
##     the camera on it: corners where ground meets a liquid.
extends SceneTree

## Rock, wall and floor tiles of each underground region (docs/tracks/deep.md).
const REGIONS := {"fungal": ["spore_stone", "spore_wall", "mycelium"], "crystal": ["crystal_stone", "crystal_wall", "geode_floor"],
	"deep_lake": ["lake_stone", "lake_wall", "shore_sand"], "magma": ["basalt", "basalt_wall", "ash"]}

func _initialize() -> void:
	var o := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		o[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var size := Vector2i(1280, 720)
	DisplayServer.window_set_size(size)
	root.size = size
	var world := TileWorld.new(128, 128, 1)
	var stone := TileDefs.id("stone")
	var wall := TileDefs.wall_id("stone_wall")
	var floor_tile := stone
	var region := String(o.get("region", ""))
	if REGIONS.has(region):
		stone = TileDefs.id(REGIONS[region][0])
		wall = TileDefs.wall_id(REGIONS[region][1])
		floor_tile = TileDefs.id(REGIONS[region][2])
		world.meta["biomes"] = [{"biome": region, "band": "deeps", "x0": 0, "x1": 127, "y0": 0, "y1": 127, "name": region}]
	var sky := o.has("sky")
	var floor_y := 60
	var top := 128 if sky else 72
	for x in 128:
		for y in top:
			world.set_fg(x, y, stone, true)
			world.set_bg(x, y, wall, true)
	for x in range(44, 84):
		for y in range(floor_y, 72 if not sky else 128):
			world.set_fg(x, y, TileDefs.AIR, true)
	world.set_fg(50, floor_y, stone, true)                   # a one-tile bump
	world.set_fg(56, floor_y - 1, TileDefs.AIR, true)        # a one-tile hole
	for y in range(floor_y, floor_y + 3):                    # a pillar three high
		world.set_fg(72, y, stone, true)
	for i in 3:                                              # a stair of single steps
		for y in range(floor_y, floor_y + 1 + i):
			world.set_fg(76 + i, y, stone, true)
	if not sky:
		world.set_fg(60, 71, TileDefs.AIR, true)             # a notch in the ceiling
		world.set_fg(66, 71, TileDefs.AIR, true)
		world.set_fg(67, 71, TileDefs.AIR, true)
	var x := 63
	var y := floor_y
	var liquid := String(o.get("liquid", ""))
	if liquid in ["water", "lava"]:
		# The basin: open from x 30 to 43, its floor 52 for six columns, then a step a column up to
		# the room's floor; the liquid fills it to the room's floor.
		var fill := TileDefs.id(liquid)
		for bx in range(30, 44):
			var bottom := 52 if bx < 36 else 52 + (bx - 35)
			for by in range(bottom, 72 if not sky else 128):
				world.set_fg(bx, by, fill if by < floor_y else TileDefs.AIR, true)
		x = 44
		y = floor_y
	for fx in 128:                                           # the floor's top row takes the floor tile
		for fy in range(1, 128):
			if world.get_fg(fx, fy) == stone and not world.is_solid(fx, fy + 1) and world.get_fg(fx, fy + 1) == TileDefs.AIR:
				world.set_fg(fx, fy, floor_tile, true)
	var sun := 1.0 if sky else 0.0
	var light := LightEngine.new(world)
	light.sun = sun
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = WorldView.sky_color(sun) if sky else Color.BLACK
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var view := WorldView.new()
	root.add_child(view)
	view.setup(world, light)
	view.hour = 13.0 if sky else 22.0
	view.lights.set_quality(String(o.get("shadows", "low")))
	view.soft = not o.has("hard")
	var rig := CameraRig.new()
	root.add_child(rig)
	rig.zoom = float(o.get("zoom", 2.0))
	var focus := Vector2(x + 0.5, y + 4.0)
	rig.target = focus
	rig.snap()
	await process_frame
	view.view_half = rig.visible_half_extent()
	view.set_focus(focus)
	view.add_actor(1, {"player": "fighter", "name": "Ash", "kind": "hero", "color": Color(0.85, 0.3, 0.25)})
	view.move_actor(1, Vector2(x + 0.5, y), 1, "idle")
	if not sky:
		for tx: int in ([46, 48, 58, 70] if liquid != "" else [48, 58, 70]):
			world.set_fg(tx, y, TileDefs.id("torch"))
	var frames := 0
	while frames < 900:
		await process_frame
		frames += 1
		view.view_half = rig.visible_half_extent()
		view.set_focus(focus)
		if frames > 3 and view.is_idle():
			break
	for i in 3:
		await RenderingServer.frame_post_draw
	var out := String(o.get("out", ""))
	if out != "":
		root.get_texture().get_image().save_png(out)
		print("corner_shot: ", out)
	quit()
