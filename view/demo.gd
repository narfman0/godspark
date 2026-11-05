## Fly a camera over a world to watch meshing and light update live.
##   WASD / arrows: move    wheel: zoom    left click: dig    right click: place stone
##   T: cycle time of day (noon, dusk, night)    L: drop / pick up the walker's torch
## opts (set before adding to the tree, e.g. by tools/shot.gd): x, y, zoom, sun, gen=seed.
extends Node3D

const SUNS := [1.0, 0.35, 0.0]

var opts := {}
var world: TileWorld
var light: LightEngine
var view: WorldView
var rig: CameraRig
var env: Environment
var focus := Vector2.ZERO
var _sun_i := 0
var _walker_x := 0.0
var _walker_dir := 1
var _walk := true

func _ready() -> void:
	world = _make_world()
	light = LightEngine.new(world)
	light.sun = float(opts.get("sun", 1.0))
	_sun_i = SUNS.find(light.sun)
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	view = WorldView.new()
	add_child(view)
	view.setup(world, light)
	rig = CameraRig.new()
	add_child(rig)
	var ground := _ground_y(world.width / 2)
	focus = Vector2(float(opts.get("x", world.width / 2)), float(opts.get("y", ground - 2)))
	rig.zoom = float(opts.get("zoom", 1.0))
	rig.target = focus
	rig.snap()
	_walker_x = world.width / 2 - 30.0
	_walk = not opts.has("still")
	view.add_actor(1, {"kind": "hero", "size": Vector2(1.5, 2.5), "color": Color(0.85, 0.3, 0.25)})
	view.add_actor(2, {"kind": "goblin", "size": Vector2(1.2, 1.8), "color": Color(0.35, 0.7, 0.3)})
	_place_walker()
	var mid := world.width / 2
	view.move_actor(2, Vector2(mid - 4.5, _ground_y(mid - 4) if opts.has("gen") else world.height / 2 - 14), 1)
	_update_view()

func _make_world() -> TileWorld:
	if opts.has("gen"):
		# Track A's generator, when it exists. Not a dependency: resolved by name at runtime.
		for c: Dictionary in ProjectSettings.get_global_class_list():
			if c["class"] == "WorldGen":
				var gen: Script = load(c["path"])
				return gen.call("generate", 1024, 512, int(opts["gen"]))
		push_warning("demo: no WorldGen class, using the test world")
	return TileWorld.make_test()

func _ground_y(x: int) -> int:
	var y := world.height - 1
	while y > 0 and not world.is_solid(x, y):
		y -= 1
	return y + 1

func _place_walker() -> void:
	var gy := _ground_y(int(_walker_x))
	var p := Vector2(_walker_x, gy)
	view.move_actor(1, p, _walker_dir)
	if not light.has_light(1):
		light.add_light(1, p.x + 0.7 * _walker_dir, p.y + 1.8, LightEngine.TORCH)
	else:
		light.move_light(1, p.x + 0.7 * _walker_dir, p.y + 1.8)

func _process(delta: float) -> void:
	var move := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_down", "ui_up"))
	if Input.is_physical_key_pressed(KEY_A):
		move.x -= 1
	if Input.is_physical_key_pressed(KEY_D):
		move.x += 1
	if Input.is_physical_key_pressed(KEY_W):
		move.y += 1
	if Input.is_physical_key_pressed(KEY_S):
		move.y -= 1
	focus += move.limit_length(1.0) * 40.0 / rig.zoom * delta
	focus = focus.clamp(Vector2.ZERO, Vector2(world.width, world.height))
	rig.target = focus
	if _walk:
		_walker_x += _walker_dir * 4.0 * delta
		var mid := world.width / 2
		if _walker_x > mid - 18 or _walker_x < mid - 44:
			_walker_dir = -_walker_dir
		_place_walker()
	# Ease the sun toward the selected time of day.
	var want: float = SUNS[maxi(_sun_i, 0)]
	if absf(light.sun - want) > 0.002:
		light.sun = move_toward(light.sun, want, delta * 0.6)
	_update_view()

func _update_view() -> void:
	view.view_half = rig.visible_half_extent()
	view.set_focus(rig.pos)
	env.background_color = WorldView.sky_color(light.sun)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				rig.zoom *= 1.12
			MOUSE_BUTTON_WHEEL_DOWN:
				rig.zoom /= 1.12
			MOUSE_BUTTON_LEFT:
				var tl := view.tile_at_screen(mb.position)
				if world.get_fg(tl.x, tl.y) != TileDefs.id("bedrock"):
					world.set_fg(tl.x, tl.y, TileDefs.AIR)
			MOUSE_BUTTON_RIGHT:
				var tr := view.tile_at_screen(mb.position)
				if world.get_fg(tr.x, tr.y) == TileDefs.AIR:
					world.set_fg(tr.x, tr.y, TileDefs.id("stone"))
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).physical_keycode:
			KEY_T:
				_sun_i = (_sun_i + 1) % SUNS.size()
			KEY_L:
				_walk = not _walk
				if not _walk:
					light.remove_light(1)
				else:
					_place_walker()
