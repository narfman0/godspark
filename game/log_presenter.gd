## A presenter with no graphics: logs what a view would show (headless runs, bots).
## Screen picking assumes the own player at the centre and `px_per_tile` pixels per tile.
class_name LogPresenter
extends Presenter

var px_per_tile := 24.0
var quiet := false
var _chunks := 0
var _since := 0.0

func _say(s: String) -> void:
	if not quiet:
		print("[view] ", s)

func world_ready(world: TileWorld, my_id: int) -> void:
	_say("world %dx%d, me = %d" % [world.width, world.height, my_id])

func actor_added(id: int, look: Dictionary) -> void:
	_say("actor + %d %s %s" % [id, look.get("kind", "?"), look.get("name", "")])

func actor_removed(id: int) -> void:
	_say("actor - %d" % id)

func chunk_arrived(_cx: int, _cy: int) -> void:
	_chunks += 1

func edit_result(req: int, reason: int, at: Vector2i, _tile: int) -> void:
	if reason != 0:
		_say("edit %d at %s refused: %s" % [req, at, WorldHost.Reason.find_key(reason)])

func corrected(pos: Vector2) -> void:
	_say("corrected to %s" % pos)

func frame(delta: float) -> void:
	super.frame(delta)
	_since += delta
	if _since >= 5.0 and cw != null:
		_since = 0.0
		_say("at %s, %d chunks held, %d remotes" % [cw.body.pos, cw.loaded.size(), cw.remotes.size()])

func tile_at_screen(screen_pos: Vector2) -> Vector2i:
	if cw == null:
		return Vector2i.ZERO
	var vp := get_viewport().get_visible_rect().size
	var d := (screen_pos - vp * 0.5) / px_per_tile
	var c := cw.body.center() + Vector2(d.x, -d.y)
	return Vector2i(floori(c.x), floori(c.y))
