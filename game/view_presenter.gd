## The real presenter: a LightEngine over the client's partial world, a WorldView, and a
## CameraRig following the own player, who carries a torch so caves are playable.
## Chunks arriving from the host emit chunk_changed on the client world, which WorldView and
## LightEngine already listen to.
class_name ViewPresenter
extends Presenter

const OWN_LIGHT := 1
## Carried light ids for remote actors: their entity id plus this.
const REMOTE_LIGHT := 1 << 20

var light: LightEngine
var view: WorldView
var rig: CameraRig
var env: Environment
var my_id := 0
var sun := 1.0
var chronicle: ChronicleOverlay
var _actors := {}

func world_ready(world: TileWorld, id: int) -> void:
	my_id = id
	_clear()
	light = LightEngine.new(world)
	light.sun = sun
	if env == null:
		env = Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		var we := WorldEnvironment.new()
		we.environment = env
		add_child(we)
	view = WorldView.new()
	add_child(view)
	view.setup(world, light)
	if rig == null:
		rig = CameraRig.new()
		add_child(rig)
	rig.target = cw.view_pos() + Vector2(0, cw.body.size.y * 0.5)
	rig.snap()
	if chronicle == null:
		chronicle = ChronicleOverlay.new()
		add_child(chronicle)

func _clear() -> void:
	_actors.clear()
	if view != null:
		view.queue_free()
		view = null
	light = null

func detach() -> void:
	super.detach()
	_clear()

func actor_added(id: int, look: Dictionary) -> void:
	if view == null:
		return
	if look.get("kind") == "player" and not look.has("slug"):
		look = look.duplicate()
		look["slug"] = "player"  # data/looks.json decides the body; a primitive without art
	view.add_actor(id, look)
	_actors[id] = true
	if id == my_id:
		light.add_light(OWN_LIGHT, cw.body.pos.x, cw.body.pos.y + 1.8, LightEngine.TORCH)

func actor_moved(id: int, pos: Vector2, facing: int, state: String) -> void:
	if view == null or not _actors.has(id):
		return
	view.move_actor(id, pos, facing, state)
	if id == my_id:
		light.move_light(OWN_LIGHT, pos.x + 0.6 * facing, pos.y + 1.8)

func chronicle_lines(lines: PackedStringArray) -> void:
	if chronicle != null:
		chronicle.add_lines(lines)

func meta_arrived(_meta: Dictionary) -> void:
	if light != null:
		light.reset()     # anything lit before the sky line was known

func actor_removed(id: int) -> void:
	if view != null and _actors.erase(id):
		view.remove_actor(id)

func frame(delta: float) -> void:
	super.frame(delta)
	if view == null or cw == null:
		return
	rig.target = cw.view_pos() + Vector2(0, cw.body.size.y * 0.5)
	var s := WorldClock.sun_at(cw.hours())
	if absf(s - light.sun) > 0.002 or (s != light.sun and (s <= WorldClock.MOON or s >= 1.0)):
		light.sun = s
	view.view_half = rig.visible_half_extent()
	view.set_focus(rig.pos)
	env.background_color = WorldView.sky_color(light.sun)

func tile_at_screen(screen_pos: Vector2) -> Vector2i:
	return view.tile_at_screen(screen_pos) if view != null else Vector2i.ZERO

func _unhandled_input(event: InputEvent) -> void:
	if rig == null or not (event is InputEventMouseButton) or not event.pressed:
		return
	match (event as InputEventMouseButton).button_index:
		MOUSE_BUTTON_WHEEL_UP:
			rig.zoom *= 1.12
		MOUSE_BUTTON_WHEEL_DOWN:
			rig.zoom /= 1.12
