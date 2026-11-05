## The client side of the protocol over a NetTransport: handshake, then decodes host
## messages into ClientWorld calls, steps the own player at 60 Hz and sends its state
## (every `state_every` steps) and edit requests. No nodes; NetSession calls frame().
class_name ClientEndpoint
extends RefCounted

signal welcomed(cw: ClientWorld)
signal rejected(reason: int, text: String)
## The link is gone (kicked, host closed, timed out or we left). reason: Protocol.Why.
signal disconnected(reason: int, text: String)
## Answer to request_check: did our digest over the host's chunk list match?
signal check_result(tag: String, match_hash: bool, line: String)

enum Phase { CONNECTING, HELLO_SENT, PLAYING, CLOSED }

var transport: NetTransport
var player_name: String
var phase := Phase.CONNECTING
var cw: ClientWorld
## 60 Hz steps per STATE message: 2 = 30 Hz.
var state_every := 2
var connect_timeout := 10.0
var time := 0.0
## Seconds from start to WELCOME, and to the whole initial interest area being present.
var welcome_at := -1.0
var area_at := -1.0
var received_by_type := {}
var _acc := 0.0
var _started := false
var _last_check_line := ""

func _init(t: NetTransport, name_: String) -> void:
	transport = t
	player_name = name_

## Advance by one frame: read messages, step the own player as many 60 Hz steps as fit,
## send state and edits. `input` is this frame's intent (jump_pressed fires on the first
## step only). Returns the number of steps taken.
func frame(dt: float, input: PlayerInput) -> int:
	time += dt
	_pump()
	if phase == Phase.CONNECTING or phase == Phase.HELLO_SENT:
		if time > connect_timeout:
			_close(Protocol.Why.TIMEOUT, "no answer from host")
		return 0
	if phase != Phase.PLAYING:
		return 0
	cw.advance(dt)
	var step_dt := 1.0 / MoveStats.step_hz()
	_acc = minf(_acc + dt, step_dt * 8)   # a long hitch does not turn into a burst
	var steps := 0
	var pressed := input.jump_pressed
	while _acc >= step_dt - 1e-9:
		_acc -= step_dt
		input.jump_pressed = pressed and steps == 0
		for r in cw.step(input):
			_send(Protocol.edit(r["req"], r["op"], r["x"], r["y"], r["tile"]))
		if cw.seq % state_every == 0:
			var s := cw.make_state()
			_send(Protocol.state(s["epoch"], s["seq"], s["pos"], s["vel"], s["flags"]))
		steps += 1
	input.jump_pressed = pressed
	if area_at < 0.0 and cw.area_ready():
		area_at = time
	return steps

## Ask the host for a digest over the chunks it believes we hold.
func request_check(tag: String) -> void:
	_send(Protocol.check_req(tag))

## Leave cleanly: BYE goes out, then the link closes.
func leave(reason := Protocol.Why.LEAVING) -> void:
	if phase == Phase.CLOSED:
		return
	if phase == Phase.PLAYING or phase == Phase.HELLO_SENT:
		_send(Protocol.bye(reason))
	transport.close()
	_close(reason, "left")

func _close(reason: int, text: String) -> void:
	if phase == Phase.CLOSED:
		return
	phase = Phase.CLOSED
	disconnected.emit(reason, text)

func _pump() -> void:
	for ev: Array in transport.poll():
		match ev[0]:
			NetTransport.CONNECT:
				if phase == Phase.CONNECTING:
					_send(Protocol.hello(player_name))
					phase = Phase.HELLO_SENT
			NetTransport.DISCONNECT:
				_close(Protocol.Why.TIMEOUT, "connection lost")
			NetTransport.PACKET:
				if phase != Phase.CLOSED:
					_handle(ev[2])

func _handle(bytes: PackedByteArray) -> void:
	var m := Protocol.decode(bytes)
	if m.is_empty():
		return
	var type: int = m["type"]
	var row: Array = received_by_type.get(type, [0, 0])
	row[0] += 1
	row[1] += bytes.size()
	received_by_type[type] = row
	match type:
		Protocol.T.WELCOME:
			cw = ClientWorld.new()
			cw.setup(m["width"], m["height"], m["seed"], m["id"], player_name, m["pos"], m["epoch"], m["radius"])
			phase = Phase.PLAYING
			welcome_at = time
			welcomed.emit(cw)
		Protocol.T.REJECT:
			rejected.emit(m["reason"], m["text"])
			transport.close()
			_close(m["reason"], m["text"])
		Protocol.T.KICK:
			transport.close()
			_close(m["reason"], m["text"])
		_:
			if cw == null:
				return
			match type:
				Protocol.T.CHUNK:
					cw.apply_chunk(m["cx"], m["cy"], m["blob"])
				Protocol.T.UNLOAD:
					for c: Vector2i in m["coords"]:
						cw.drop_chunk(c.x, c.y)
				Protocol.T.TILES:
					var d: PackedInt32Array = m["deltas"]
					for i in range(0, d.size(), 4):
						cw.apply_tile(d[i], d[i + 1], d[i + 2], d[i + 3])
				Protocol.T.ENT_ADD:
					cw.add_remote(m["id"], m["kind"], m["name"], m["size"], m["pos"], m["flags"])
				Protocol.T.ENT_REMOVE:
					cw.remove_remote(m["id"])
				Protocol.T.SNAPSHOT:
					cw.apply_snapshot(m["tick"], m["entries"])
				Protocol.T.CORRECT:
					cw.apply_correction(m["epoch"], m["pos"], m["vel"])
				Protocol.T.RESULT:
					cw.apply_edit_result(m["req"], m["reason"], Vector2i(m["x"], m["y"]), m["tile"])
				Protocol.T.CHECK:
					_on_check(m)

func _on_check(m: Dictionary) -> void:
	var coords: Array = m["coords"]
	var held := {}
	for c: Vector2i in coords:
		held[c] = true
	var same_set := held.size() == cw.loaded.size()
	if same_set:
		for c: Vector2i in cw.loaded:
			if not held.has(c):
				same_set = false
				break
	var mine := ChunkHash.raw(cw.world, coords)
	var theirs: PackedByteArray = m["digest"]
	var ok := same_set and mine == theirs
	var hp: Vector2 = m["pos"]
	_last_check_line = "NETCHECK client name=%s tag=%s chunks=%d hash=%s pos=%.3f,%.3f host_hash=%s host_pos=%.3f,%.3f same_set=%s" % [
			player_name, m["tag"], coords.size(), mine.hex_encode(), cw.body.pos.x, cw.body.pos.y,
			theirs.hex_encode(), hp.x, hp.y, same_set]
	check_result.emit(m["tag"], ok, _last_check_line)

func _send(msg: PackedByteArray) -> void:
	transport.send(NetTransport.SERVER, msg, not Protocol.unreliable(msg[0]))
