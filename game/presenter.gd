## What the playing client shows. attach() hooks a ClientWorld's signals to the virtual
## methods below; frame() is called once per rendered frame. Implementations:
## LogPresenter (prints; headless) and ViewPresenter (WorldView, LightEngine, CameraRig).
class_name Presenter
extends Node

var cw: ClientWorld

func attach(client: ClientWorld) -> void:
	cw = client
	cw.actor_added.connect(actor_added)
	cw.actor_moved.connect(actor_moved)
	cw.actor_removed.connect(actor_removed)
	cw.chunk_arrived.connect(chunk_arrived)
	cw.chunk_dropped.connect(chunk_dropped)
	cw.world.tile_changed.connect(tile_changed)
	cw.edit_result.connect(edit_result)
	cw.corrected.connect(corrected)
	cw.meta_arrived.connect(meta_arrived)
	cw.chronicle_lines.connect(chronicle_lines)
	cw.chronicle_history.connect(chronicle_history)
	cw.vitals_changed.connect(actor_vitals)
	var combat := cw.system(HostSystem.COMBAT)
	if combat != null and combat.has_signal("event"):
		combat.connect("event", combat_event)
	world_ready(cw.world, cw.my_id)
	# the own player was announced in setup(), before we were listening
	actor_added(cw.my_id, {"kind": "player", "size": cw.stats.size, "color": Color(0.85, 0.75, 0.55), "name": cw.player_name, "own": true})

## Forget the current client (it left); a new one may attach later.
func detach() -> void:
	if cw == null:
		return
	for sig: Array in [[cw.actor_added, actor_added], [cw.actor_moved, actor_moved], [cw.actor_removed, actor_removed],
			[cw.chunk_arrived, chunk_arrived], [cw.chunk_dropped, chunk_dropped], [cw.world.tile_changed, tile_changed],
			[cw.edit_result, edit_result], [cw.corrected, corrected], [cw.meta_arrived, meta_arrived],
			[cw.chronicle_lines, chronicle_lines], [cw.chronicle_history, chronicle_history],
			[cw.vitals_changed, actor_vitals]]:
		if (sig[0] as Signal).is_connected(sig[1]):
			(sig[0] as Signal).disconnect(sig[1])
	var combat := cw.system(HostSystem.COMBAT)
	if combat != null and combat.has_signal("event") and combat.is_connected("event", combat_event):
		combat.disconnect("event", combat_event)
	cw = null

## Per frame: interpolate and move actors.
func frame(_delta: float) -> void:
	if cw != null:
		cw.present()

## Tile under a screen position (mouse), for dig and place targets.
func tile_at_screen(_screen_pos: Vector2) -> Vector2i:
	return Vector2i.ZERO

func world_ready(_world: TileWorld, _my_id: int) -> void:
	pass

func actor_added(_id: int, _look: Dictionary) -> void:
	pass

func actor_moved(_id: int, _pos: Vector2, _facing: int, _state: String) -> void:
	pass

func actor_removed(_id: int) -> void:
	pass

func chunk_arrived(_cx: int, _cy: int) -> void:
	pass

func chunk_dropped(_cx: int, _cy: int) -> void:
	pass

func tile_changed(_x: int, _y: int, _layer: int, _old: int, _now: int) -> void:
	pass

func edit_result(_req: int, _reason: int, _at: Vector2i, _tile: int) -> void:
	pass

func corrected(_pos: Vector2) -> void:
	pass

func meta_arrived(_meta: Dictionary) -> void:
	pass

func chronicle_lines(_lines: PackedStringArray) -> void:
	pass

## What happened before this player arrived. Optional.
func chronicle_history(_lines: PackedStringArray) -> void:
	pass

## An actor's hit points (the own player too: id == cw.my_id). Optional.
func actor_vitals(_id: int, _hp: int, _max_hp: int) -> void:
	pass

## A combat event (CombatCodec.Ev: SWING, HIT, DAMAGE, DEATH...; see CombatClient). Optional.
func combat_event(_ev: Dictionary) -> void:
	pass
