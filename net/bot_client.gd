## A scripted client for smoke tests: joins, waits for its area, walks, jumps, digs `digs`
## tiles, places `places` blocks, checks its partial world against the host, leaves,
## rejoins (expecting to come back where it left), checks again and says a final BYE.
## Prints one "BOT ..." line per milestone and the client NETCHECK lines.
##
##   var bot := BotClient.new(); bot.address = "127.0.0.1"; bot.port = 24650
##   bot.bot_name = "bot1"; bot.finished.connect(...); add_child(bot)
class_name BotClient
extends Node

signal finished(ok: bool)

var address := "127.0.0.1"
var port := NetSession.DEFAULT_PORT
var bot_name := "bot"
var digs := 3
var places := 3
var rejoin := true
## Walking direction: +1 right, -1 left.
var dir := 1
## Seconds to wait before connecting (to join late, after others have edited).
var delay := 0.0

var session: NetSession
var input := PlayerInput.new()
var errors := PackedStringArray()
var dug := 0
var placed := 0
var refused := 0
var phase := "wait"
var _t := 0.0
var _target := Vector2i(-1, -1)
var _target_t := 0.0
var _tried := {}
var _left_at := Vector2.ZERO
var _check_line := ""
var _check_ok := false
var _check_tag := ""
var _done := false
var _wood := 0

func _ready() -> void:
	_wood = TileDefs.id("wood")

func _say(s: String) -> void:
	print("BOT %s %s" % [bot_name, s])

func _fail(why: String) -> void:
	errors.append("%s: %s" % [phase, why])
	_say("FAIL %s: %s" % [phase, why])
	_finish()

func _finish() -> void:
	if _done:
		return
	_done = true
	_say("done ok=%s dug=%d placed=%d refused=%d corrections=%d" % [errors.is_empty(), dug, placed, refused,
			cw().corrections if cw() != null else -1])
	if session != null and session.client_ep != null and session.client_ep.phase != ClientEndpoint.Phase.CLOSED:
		session.leave(Protocol.Why.FINAL if errors.is_empty() else Protocol.Why.LEAVING)
	finished.emit(errors.is_empty())

func _connect() -> void:
	session = NetSession.new()
	session.input_source = func() -> PlayerInput: return input
	add_child(session)
	session.client_closed.connect(_on_closed)
	var err := session.start_client(address, port, bot_name)
	if err != OK:
		_fail("connect error %d" % err)
		return
	session.client_ep.check_result.connect(_on_check)

func _on_closed(reason: int, text: String) -> void:
	if phase != "leave" and not _done:
		_fail("disconnected (%s: %s)" % [Protocol.Why.find_key(reason), text])

func _on_check(tag: String, ok: bool, line: String) -> void:
	print(line)
	_check_tag = tag
	_check_ok = ok
	_check_line = line

func cw() -> ClientWorld:
	return session.client_world() if session != null else null

func _go(p: String) -> void:
	phase = p
	_t = 0.0
	input = PlayerInput.new()
	if session != null:
		session.input_source = func() -> PlayerInput: return input

func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	input.jump_pressed = false
	match phase:
		"wait":
			if _t >= delay:
				_connect()
				_go("join")
		"join", "rejoin":
			var c := cw()
			if c != null and c.area_ready():
				var ep := session.client_ep
				var objs := 0
				for k: Vector2i in c.loaded:
					objs += c.world.chunk_at(k.x, k.y).object_count()
				_say("%s area_ms=%d welcome_ms=%d chunks=%d pos=%.2f,%.2f objects=%d clock=%s chronicle=%d" % [phase,
						roundi(ep.area_at * 1000.0), roundi(ep.welcome_at * 1000.0), c.loaded.size(), c.body.pos.x,
						c.body.pos.y, objs, WorldClock.describe(c.hours()), c.chronicle.size()])
				if phase == "rejoin":
					if c.body.pos.distance_to(_left_at) > 0.6:
						_fail("came back at %s, left at %s" % [c.body.pos, _left_at])
						return
					_go("settle_final")
				else:
					_go("walk")
			elif _t > 15.0:
				_fail("no area after 15 s")
		"walk":
			input.move_x = dir
			if _t > 1.0:
				_go("jump")
				input.jump = true
				input.jump_pressed = true
		"jump":
			input.jump = _t < 0.25
			if _t > 0.5 and cw().body.on_floor:
				_go("dig")
			elif _t > 4.0:
				_fail("never landed")
		"dig":
			_dig_step()
		"place":
			_place_step()
		"settle_pre", "settle_final":
			if cw().body.on_floor and absf(cw().body.vel.x) < 0.01 and _t > 0.6:
				var tag := "pre" if phase == "settle_pre" else "final"
				_check_tag = ""
				session.client_ep.request_check(tag)
				_go("check_" + tag)
			elif _t > 5.0:
				_fail("never settled")
		"check_pre", "check_final":
			if _check_tag != "":
				if not _check_ok:
					_fail("check %s mismatch" % _check_tag)
					return
				if phase == "check_final":
					_finish()
				elif rejoin:
					_left_at = cw().body.pos
					_go("leave")
					session.leave()
				else:
					_go("settle_final")
			elif _t > 5.0:
				_fail("no check answer")
		"leave":
			if _t > 0.8:
				session.queue_free()
				session = null
				_connect()
				_go("rejoin")

func _dig_step() -> void:
	var c := cw()
	if dug >= digs:
		_go("place")
		return
	if _t > 30.0:
		_fail("dug only %d of %d" % [dug, digs])
		return
	if _target.x >= 0:
		_target_t += get_process_delta_time()
		if c.world.get_fg(_target.x, _target.y) == TileDefs.AIR:
			dug += 1
			_target = Vector2i(-1, -1)
		elif _target_t > 4.0:
			refused += 1
			_target = Vector2i(-1, -1)
	if _target.x < 0:
		_target = _pick(func(x: int, y: int) -> bool:
			return TileEdit.can_dig(c.world, c.body, x, y), [2, 3, 4, -2, -3], [-1, -2, -3])
		_target_t = 0.0
	input.dig = _target.x >= 0
	input.target = _target

func _place_step() -> void:
	var c := cw()
	if placed >= places:
		input.place = false
		_target = Vector2i(-1, -1)
		_go("settle_pre")
		return
	if _t > 20.0:
		_fail("placed only %d of %d" % [placed, places])
		return
	if _target.x >= 0:
		_target_t += get_process_delta_time()
		if c.world.get_fg(_target.x, _target.y) == _wood:
			placed += 1
			_target = Vector2i(-1, -1)
		elif _target_t > 2.0:
			refused += 1
			_target = Vector2i(-1, -1)
	if _target.x < 0:
		_target = _pick(func(x: int, y: int) -> bool:
			var others := [c.body]
			for r: ClientWorld.RemoteEntity in c.remotes.values():
				var b := Body.new()
				b.size = r.size
				b.pos = r.pos
				others.append(b)
			return TileEdit.can_place(c.world, c.body, x, y, _wood, others), [-2, -3, -4, 2, 3, 4], [0, 1, 2])
		_target_t = 0.0
	input.place = _target.x >= 0
	input.place_tile = _wood
	input.target = _target

## First untried cell (relative to the feet, x offsets times `dir`) that passes ok(x, y).
func _pick(ok: Callable, dxs: Array, dys: Array) -> Vector2i:
	var c := cw()
	var fx := floori(c.body.pos.x)
	var fy := roundi(c.body.pos.y)
	for dy: int in dys:
		for dx: int in dxs:
			var at := Vector2i(fx + dx * dir, fy + dy)
			if not _tried.has(at) and ok.call(at.x, at.y):
				_tried[at] = true
				return at
	return Vector2i(-1, -1)
