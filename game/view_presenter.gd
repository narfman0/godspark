## The real presenter: a LightEngine over the client's partial world, a WorldView, and a
## CameraRig following the own player, who carries a torch so caves are playable.
## Chunks arriving from the host emit chunk_changed on the client world, which WorldView and
## LightEngine already listen to.
class_name ViewPresenter
extends Presenter

const OWN_LIGHT := 1
## Light ids of torches carried by other actors (Life's guards at night): base + entity id.
const CARRIED_LIGHT := 1 << 24
## Carried light ids for remote actors: their entity id plus this.
const REMOTE_LIGHT := 1 << 20

var light: LightEngine
var view: WorldView
var rig: CameraRig
var env: Environment
var my_id := 0
var sun := 1.0
var chronicle: ChronicleOverlay
## The interface (HUD and screens): windowed clients only.
var ui: GameUi
## In-world feedback: numbers, nameplates, telegraphs, drops, projectiles.
var fx: FxView
## Carried light strength last set (the Lantern spark and light gear widen it).
var _torch := LightEngine.TORCH
var dressing: DressingView
## Seconds between dressing rebuilds while chunks or objects keep changing.
const DRESS_EVERY := 0.3
var _dress_dirty := false
var _dress_wait := 0.0
var _actors := {}
## id -> true while its carried torch is lit (look.light "torch": lit when the sun is low)
var _carried := {}
## id -> [one-shot state, until msec (-1: held)] from combat events.
var _oneshot := {}

func world_ready(world: TileWorld, id: int) -> void:
	my_id = id
	_clear()
	light = LightEngine.new(world)
	light.deferred = true     # chunk arrivals and cold chunks are spread over frames
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
	dressing = DressingView.new()
	view.add_child(dressing)
	world.objects_changed.connect(func(_cx: int, _cy: int) -> void: _dress_dirty = true)
	_dress_dirty = true
	if rig == null:
		rig = CameraRig.new()
		add_child(rig)
	rig.target = cw.view_pos() + Vector2(0, cw.body.size.y * 0.5)
	rig.snap()
	if chronicle == null:
		chronicle = ChronicleOverlay.new()
		add_child(chronicle)
		chronicle.set_margin(150.0, 460.0)
	chronicle.add_history(cw.chronicle)
	fx = FxView.new()
	view.add_child(fx)
	fx.setup(cw, view)
	if ui == null:
		ui = GameUi.new()
		add_child(ui)
	ui.attach(cw, self)

func _clear() -> void:
	_actors.clear()
	fx = null
	dressing = null
	if view != null:
		view.queue_free()
		view = null
	light = null

func detach() -> void:
	super.detach()
	if ui != null:
		ui.detach()
	_clear()

func actor_added(id: int, look: Dictionary) -> void:
	if view == null:
		return
	if look.get("kind") == "player" and not look.has("slug"):
		look = look.duplicate()
		look["slug"] = "player"  # data/looks.json decides the body; a primitive without art
	view.add_actor(id, look)
	_actors[id] = true
	if fx != null:
		fx.actor_added(id, look)
	if id == my_id:
		light.add_light(OWN_LIGHT, cw.body.pos.x, cw.body.pos.y + 1.8, LightEngine.TORCH)
	elif String(look.get("light", "")) == "torch":
		_carried[id] = false

func actor_moved(id: int, pos: Vector2, facing: int, state: String) -> void:
	if view == null or not _actors.has(id):
		return
	var shot: Array = _oneshot.get(id, [])
	if not shot.is_empty():
		if shot[1] < 0 or Time.get_ticks_msec() < int(shot[1]):
			state = String(shot[0])
		else:
			_oneshot.erase(id)
	view.move_actor(id, pos, facing, state)
	if _carried.has(id):
		var lit := light.sun < 0.5
		if lit and not bool(_carried[id]):
			light.add_light(CARRIED_LIGHT + id, pos.x + 0.6 * facing, pos.y + 1.8, LightEngine.TORCH)
		elif lit:
			light.move_light(CARRIED_LIGHT + id, pos.x + 0.6 * facing, pos.y + 1.8)
		elif bool(_carried[id]):
			light.remove_light(CARRIED_LIGHT + id)
		_carried[id] = lit
	if id == my_id:
		light.move_light(OWN_LIGHT, pos.x + 0.6 * facing, pos.y + 1.8)
		var want := torch_strength()
		if want != _torch:
			_torch = want
			light.add_light(OWN_LIGHT, pos.x + 0.6 * facing, pos.y + 1.8, want)

func chunk_arrived(_cx: int, _cy: int) -> void:
	_dress_dirty = true

func chunk_dropped(_cx: int, _cy: int) -> void:
	_dress_dirty = true

## Every dressing record in the chunks held, for DressingView ({id: name, x, y}).
func _dress() -> void:
	var recs: Array = []
	for c: Vector2i in cw.loaded:
		for r: Dictionary in Dressing.records_in(cw.world, c.x, c.y):
			recs.append({"id": Dressing.name_of(int(r["id"])), "x": r["x"], "y": r["y"]})
	dressing.set_objects(recs)

func chronicle_lines(lines: PackedStringArray) -> void:
	if chronicle != null:
		chronicle.add_lines(lines)

func chronicle_history(lines: PackedStringArray) -> void:
	if chronicle != null:
		chronicle.add_history(lines)

func meta_arrived(_meta: Dictionary) -> void:
	if light != null:
		light.reset()     # anything lit before the sky line was known

## Combat events drive the actors' existing one-shot clips ("attack", "hit", "death"),
## held over the movement state for a moment; an actor without art shows nothing new.
func combat_event(ev: Dictionary) -> void:
	if view == null:
		return
	if fx != null:
		fx.combat_event(ev)
	var now := Time.get_ticks_msec()
	match int(ev.get("kind", 0)):
		CombatCodec.Ev.SWING:
			if _actors.has(int(ev["src"])):
				_oneshot[int(ev["src"])] = ["attack", now + maxi(250, roundi(float(ev.get("total", 0.4)) * 1000.0))]
		CombatCodec.Ev.DAMAGE:
			var d := int(ev["dst"])
			if _actors.has(d) and String(_oneshot.get(d, [""])[0]) != "death":
				_oneshot[d] = ["hit", now + 300]
		CombatCodec.Ev.DEATH, CombatCodec.Ev.DOWNED:
			if _actors.has(int(ev["dst"])):
				_oneshot[int(ev["dst"])] = ["death", -1]
		CombatCodec.Ev.HEAL:
			if String(_oneshot.get(int(ev["dst"]), [""])[0]) == "death":
				_oneshot.erase(int(ev["dst"]))

## Back on their feet (revived, stabilised, healed, respawned): let go of the death pose.
func actor_vitals(id: int, hp: int, max_hp: int) -> void:
	super.actor_vitals(id, hp, max_hp)
	# down at 0 HP however it happened (a combat DOWNED, a rule, a fall): hold the pose
	if hp <= 0 and max_hp > 0 and _actors.has(id) and String(_oneshot.get(id, [""])[0]) != "death":
		_oneshot[id] = ["death", -1]
	if hp > 0 and String(_oneshot.get(id, [""])[0]) == "death":
		_oneshot.erase(id)

func actor_removed(id: int) -> void:
	_oneshot.erase(id)
	if bool(_carried.get(id, false)):
		light.remove_light(CARRIED_LIGHT + id)
	_carried.erase(id)
	if fx != null:
		fx.actor_removed(id)
	if view != null and _actors.erase(id):
		view.remove_actor(id)

func frame(delta: float) -> void:
	super.frame(delta)
	if view == null or cw == null:
		return
	rig.target = cw.view_pos() + Vector2(0, cw.body.size.y * 0.5)
	_dress_wait -= delta
	if _dress_dirty and _dress_wait <= 0.0 and dressing != null:
		_dress_dirty = false
		_dress_wait = DRESS_EVERY
		_dress()
	var s := WorldClock.sun_at(cw.hours())
	if absf(s - light.sun) > 0.002 or (s != light.sun and (s <= WorldClock.MOON or s >= 1.0)):
		light.sun = s
	view.view_half = rig.visible_half_extent()
	view.set_focus(rig.pos)
	env.background_color = WorldView.sky_color(light.sun)

func tile_at_screen(screen_pos: Vector2) -> Vector2i:
	return view.tile_at_screen(screen_pos) if view != null else Vector2i.ZERO

## The own carried light: a torch, widened by the items client's `light` tag (Lantern spark,
## glowing gear): each point of light is one more tile of reach.
func torch_strength() -> int:
	var items := cw.system(HostSystem.ITEMS) as ItemsClient if cw != null else null
	var extra := float(items.tags().get("light", 0.0)) if items != null and items.live else 0.0
	return mini(LightEngine.MAX, LightEngine.TORCH + roundi(extra * LightEngine.STEP))

## Aiming preview of a quick spell (LocalInput, while its key is held); {} clears it.
func aim_preview(spell: Dictionary, aim: Vector2) -> void:
	if fx != null:
		fx.aim_preview(spell, aim)

## Wheel: zoom, or with Ctrl held a hotbar slot (over the hotbar the HUD takes the wheel).
## Zoom keys: = and - (and the keypad's + and -).
func _unhandled_input(event: InputEvent) -> void:
	if rig == null:
		return
	if event.is_action_pressed("zoom_in"):
		rig.zoom *= 1.12
	elif event.is_action_pressed("zoom_out"):
		rig.zoom /= 1.12
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_WHEEL_UP and mb.button_index != MOUSE_BUTTON_WHEEL_DOWN:
		return
	var up := mb.button_index == MOUSE_BUTTON_WHEEL_UP
	if InputLogic.wheel_target(mb.ctrl_pressed, false) == "hotbar":
		var items := cw.system(HostSystem.ITEMS) as ItemsClient if cw != null else null
		if items != null:
			items.select_hotbar(InputLogic.next_hotbar(items.selected(), -1 if up else 1))
	elif up:
		rig.zoom *= 1.12
	else:
		rig.zoom /= 1.12
