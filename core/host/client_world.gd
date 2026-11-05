## A client's mirror of the host's world, testable without sockets: a partial TileWorld
## filled as chunks arrive, remote entities with interpolation buffers, and its own player,
## moved locally at 60 Hz (the client owns its movement) and snapped back by host
## corrections. The net layer decodes messages into the apply_* calls and encodes what
## step() and make_state() return; a presenter (WorldView later) listens to the signals.
##
##   var cw := ClientWorld.new()
##   cw.setup(w, h, seed, my_id, "ann", spawn, 0, Interest.DEFAULT_RADIUS)
##   cw.apply_chunk(cx, cy, blob)          # emits world.chunk_changed and chunk_arrived
##   var edits := cw.step(input)           # one 60 Hz step; returns edit requests
##   cw.advance(frame_dt); cw.present()    # interpolate remotes, emit actor_moved
class_name ClientWorld
extends RefCounted

signal actor_added(id: int, look: Dictionary)
signal actor_moved(id: int, pos: Vector2, facing: int, state: String)
signal actor_removed(id: int)
signal chunk_arrived(cx: int, cy: int)
signal chunk_dropped(cx: int, cy: int)
## reason: WorldHost.Reason (0 = OK). tile: the cell's foreground id on the host now.
signal edit_result(req: int, reason: int, at: Vector2i, tile: int)
signal corrected(pos: Vector2)
## The host's world meta arrived (biomes, bands, sites, surface): world.meta is set.
signal meta_arrived(meta: Dictionary)
## New lines of world history from the host.
signal chronicle_lines(lines: PackedStringArray)

## Edit request ops (wire values).
enum Op { DIG_START, DIG_STOP, PLACE }

## Remote entities are drawn this far (s) behind the newest snapshot.
const INTERP_DELAY := 0.1
## How far past the newest sample a remote may be extrapolated (s).
const MAX_EXTRAPOLATE := 0.1
## Tiles around the own body (plus one step of travel) whose chunks must be present to move.
const FREEZE_MARGIN := 3.0
## Samples kept per remote entity.
const MAX_SAMPLES := 32
## A predicted edit with no RESULT after this long (s, client time) is rolled back to the
## host's value. The channel is reliable, so this only fires on a lost connection.
const PREDICT_TIMEOUT := 3.0
## Host corrections of the own player are blended in the view over about this long (s);
## jumps longer than CORRECT_SNAP tiles are not blended.
const CORRECT_BLEND := 0.05
const CORRECT_SNAP := 8.0

var world: TileWorld
var my_id := 0
var player_name := ""
var body: Body
var stats: MoveStats
## Correction epoch: STATE messages carry it; the host ignores older ones.
var epoch := 0
## 60 Hz step counter, advanced every step (frozen or not).
var seq := 0
var radius := Interest.DEFAULT_RADIUS
## True while the chunks around the own body have not all arrived: the body does not move.
var frozen := true
## Vector2i -> true: chunks that have arrived and not been unloaded.
var loaded := {}
## id -> RemoteEntity
var remotes := {}
## Estimate of host time (s), advanced locally, pulled toward each snapshot's tick.
var clock := 0.0
var corrections := 0
var place_tile := 4
var _clock_synced := false
var _req := 0
var _digging := false
var _dig_at := Vector2i.ZERO
var _dig_req := 0
var _place_prev := false
var _place_at := Vector2i.ZERO
## Local dig progress (prediction) on _dig_at.
var _dig_prog := TileEdit.DigProgress.new()
## req of a dig predicted complete whose RESULT has not arrived; 0 = none. While set, no
## DIG_START or DIG_STOP goes out, so the host's dig of that tile is never abandoned.
var _dig_await := 0
## Predicted cells: Vector2i -> {auth: host's fg value as last seen in the stream, reqs: [req]}
var _pending := {}
## req -> {cell: Vector2i, t: client time when predicted}
var _pending_reqs := {}
var _time := 0.0
## The host's game clock (WorldClock ticks, fractional), run locally between CLOCK messages.
var clock_ticks := float(WorldClock.START_HOUR * WorldClock.TICKS_PER_HOUR)
## View-only offset of the own player after a correction (decays to zero).
var view_offset := Vector2.ZERO
## Edits predicted and rolled back (host refused or timed out).
var predicted := 0
var rolled_back := 0

func setup(width: int, height: int, seed_value: int, id: int, name_: String, pos: Vector2,
		epoch_: int, radius_: int) -> void:
	world = TileWorld.new(width, height, seed_value, true)    # sparse: chunks as they arrive
	my_id = id
	player_name = name_
	stats = MoveStats.player()
	body = stats.make_body()
	body.pos = pos
	epoch = epoch_
	radius = radius_
	actor_added.emit(my_id, {"kind": "player", "size": stats.size, "color": Color(0.85, 0.75, 0.55), "name": player_name, "own": true})

func is_ready() -> bool:
	return world != null

# --- tiles --------------------------------------------------------------------------

## A chunk blob from the host (Chunk.to_bytes). False if it does not decode.
func apply_chunk(cx: int, cy: int, blob: PackedByteArray) -> bool:
	if cx < 0 or cy < 0 or cx >= world.chunks_x or cy >= world.chunks_y:
		return false
	var raw := Chunk.new(cx, cy)
	raw.from_bytes(blob)
	if raw.fg.size() != Chunk.CELLS * 2 or raw.bg.size() != Chunk.CELLS or raw.liquid.size() != Chunk.CELLS:
		return false
	_forget_predictions(cx, cy)        # a whole chunk from the host is the truth
	var c := world.ensure_chunk(cx, cy)
	c.fg = raw.fg
	c.bg = raw.bg
	c.liquid = raw.liquid
	loaded[Vector2i(cx, cy)] = true
	world.chunk_changed.emit(cx, cy)
	chunk_arrived.emit(cx, cy)
	return true

## World meta from the host. Its surface line becomes world.sky_line, so unloaded chunks
## above the ground read as open sky to light (see TileWorld).
func apply_meta(m: Dictionary) -> void:
	world.meta = m
	var surf: Array = m.get("surface", [])
	if surf.size() == world.width:
		world.sky_line = PackedInt32Array(surf)
	meta_arrived.emit(m)

## The host has stopped sending this chunk's changes: forget it.
func drop_chunk(cx: int, cy: int) -> void:
	var at := Vector2i(cx, cy)
	if not loaded.has(at):
		return
	loaded.erase(at)
	_forget_predictions(cx, cy)
	world.unload_chunk(cx, cy)      # frees it and emits chunk_changed
	chunk_dropped.emit(cx, cy)

## One tile delta. Ignored for chunks not held (the host never sends those).
func apply_tile(x: int, y: int, layer: int, value: int) -> void:
	if not world.in_bounds(x, y) or not loaded.has(Vector2i(x >> 5, y >> 5)):
		return
	match layer:
		TileWorld.Layer.FG:
			var p: Dictionary = _pending.get(Vector2i(x, y), {})
			if not p.is_empty():
				p["auth"] = value      # shown when the prediction settles
				return
			world.set_fg(x, y, value)
		TileWorld.Layer.BG:
			world.set_bg(x, y, value)
		TileWorld.Layer.LIQUID:
			world.set_liquid(x, y, value)

func has_chunk(cx: int, cy: int) -> bool:
	return loaded.has(Vector2i(cx, cy))

## Digest over the chunks held (compare with the host's ChunkHash over the same set).
func loaded_hash() -> String:
	return ChunkHash.of(world, loaded.keys())

## True when every chunk within `r` of the own body's chunk has arrived.
func area_ready(r := -1) -> bool:
	if world == null:
		return false
	for c in Interest.around(world, Interest.chunk_of(body.center()), radius if r < 0 else r):
		if not loaded.has(c):
			return false
	return true

# --- own player ---------------------------------------------------------------------

## One 60 Hz step of the own player. Returns edit requests for the host:
## [{op: Op, req: int, x, y, tile}]. Dig is held (DIG_START when it starts or retargets,
## DIG_STOP on release); place fires on press and on retarget while held. Requests the
## local world already says are impossible are not sent.
func step(input: PlayerInput) -> Array[Dictionary]:
	seq += 1
	var step_dt := 1.0 / MoveStats.step_hz()
	_time += step_dt
	_expire_predictions()
	var reqs: Array[Dictionary] = []
	if _dig_await != 0:
		pass   # a predicted dig waits for the host's word; nothing about digging goes out
	elif input.dig:
		var t := input.target
		if not _digging or t != _dig_at:
			if TileEdit.can_dig(world, body, t.x, t.y) and has_chunk(t.x >> 5, t.y >> 5):
				_req += 1
				_dig_req = _req
				reqs.append({"op": Op.DIG_START, "req": _req, "x": t.x, "y": t.y, "tile": 0})
				_digging = true
				_dig_at = t
				_dig_prog.reset()
			elif _digging:
				reqs.append({"op": Op.DIG_STOP, "req": 0, "x": t.x, "y": t.y, "tile": 0})
				_digging = false
		if _digging:
			if not TileEdit.can_dig(world, body, _dig_at.x, _dig_at.y):
				reqs.append({"op": Op.DIG_STOP, "req": 0, "x": _dig_at.x, "y": _dig_at.y, "tile": 0})
				_digging = false
			elif _dig_prog.update(_dig_at, world.get_fg(_dig_at.x, _dig_at.y), step_dt):
				# Done by our clock: show it now. The host finishes about one trip later.
				_predict(_dig_at, TileDefs.AIR, _dig_req)
				_dig_await = _dig_req
				_digging = false
	elif _digging:
		reqs.append({"op": Op.DIG_STOP, "req": 0, "x": _dig_at.x, "y": _dig_at.y, "tile": 0})
		_digging = false
	if input.place and (not _place_prev or input.target != _place_at):
		var t := input.target
		var tile := input.place_tile if input.place_tile > 0 else place_tile
		_place_at = t
		if has_chunk(t.x >> 5, t.y >> 5) and TileEdit.can_place(world, body, t.x, t.y, tile, [body]):
			_req += 1
			reqs.append({"op": Op.PLACE, "req": _req, "x": t.x, "y": t.y, "tile": tile})
			_predict(t, tile, _req)
	_place_prev = input.place
	frozen = not _body_area_loaded()
	if not frozen:
		PlayerController.step(world, body, input, stats, 1.0 / MoveStats.step_hz())
	return reqs

func _body_area_loaded() -> bool:
	var margin := FREEZE_MARGIN + body.vel.length() / MoveStats.step_hz()
	for c in Interest.chunks_under(world, body.rect(), margin):
		if not loaded.has(c):
			return false
	return true

## What the client sends up: {epoch, seq, pos, vel, flags}.
func make_state() -> Dictionary:
	return {"epoch": epoch, "seq": seq, "pos": body.pos, "vel": body.vel,
			"flags": HostEntity.body_flags(body, _digging)}

## The host refused our movement: go where it says and adopt its epoch. The body snaps; the
## picture blends (view_offset).
func apply_correction(new_epoch: int, pos: Vector2, vel: Vector2) -> void:
	epoch = new_epoch
	var off := body.pos + view_offset - pos
	view_offset = off if off.length() < CORRECT_SNAP else Vector2.ZERO
	body.pos = pos
	body.vel = vel
	body.jumping = false
	body.climbing = false
	body.clinging = false
	body.coyote = 0.0
	body.jump_buffer = 0.0
	body.drop_y = Body.NO_DROP
	TileCollision.update_contacts(world, body)
	corrections += 1
	corrected.emit(pos)

func apply_edit_result(req: int, reason: int, at: Vector2i, tile: int) -> void:
	if req == _dig_req and _digging:
		_digging = false    # done or refused: a held button will ask again when it can
		_dig_prog.reset()
	if req == _dig_await:
		_dig_await = 0
	var pr: Dictionary = _pending_reqs.get(req, {})
	if not pr.is_empty():
		var cell: Vector2i = pr["cell"]
		if cell == at:
			_pending[cell]["auth"] = tile   # the host's value as of this point in the stream
		if reason != 0:
			rolled_back += 1
		_settle(req)
	edit_result.emit(req, reason, at, tile)

## Where the view should draw the own player: the body plus the fading correction offset.
func view_pos() -> Vector2:
	return body.pos + view_offset

## Number of edits shown but not yet confirmed.
func pending_count() -> int:
	return _pending_reqs.size()

# --- prediction ---------------------------------------------------------------------

func _predict(cell: Vector2i, value: int, req: int) -> void:
	var p: Dictionary = _pending.get(cell, {})
	if p.is_empty():
		p = {"auth": world.get_fg(cell.x, cell.y), "reqs": []}
		_pending[cell] = p
	(p["reqs"] as Array).append(req)
	_pending_reqs[req] = {"cell": cell, "t": _time}
	predicted += 1
	world.set_fg(cell.x, cell.y, value)

## Drop one prediction; when none is left on its cell, show the host's value.
func _settle(req: int) -> void:
	var pr: Dictionary = _pending_reqs.get(req, {})
	if pr.is_empty():
		return
	_pending_reqs.erase(req)
	var cell: Vector2i = pr["cell"]
	var p: Dictionary = _pending.get(cell, {})
	if p.is_empty():
		return
	(p["reqs"] as Array).erase(req)
	if (p["reqs"] as Array).is_empty():
		_pending.erase(cell)
		world.set_fg(cell.x, cell.y, int(p["auth"]))

func _expire_predictions() -> void:
	if _pending_reqs.is_empty():
		return
	for req: int in _pending_reqs.keys():
		if _time - float(_pending_reqs[req]["t"]) > PREDICT_TIMEOUT:
			rolled_back += 1
			if req == _dig_await:
				_dig_await = 0
			_settle(req)

func _forget_predictions(cx: int, cy: int) -> void:
	if _pending.is_empty():
		return
	for cell: Vector2i in _pending.keys():
		if cell.x >> 5 == cx and cell.y >> 5 == cy:
			for req: int in _pending[cell]["reqs"]:
				_pending_reqs.erase(req)
				if req == _dig_await:
					_dig_await = 0
			_pending.erase(cell)

# --- remote entities ----------------------------------------------------------------

func add_remote(id: int, kind: int, name_: String, size: Vector2, pos: Vector2, flags: int) -> void:
	if id == my_id:
		return
	var r: RemoteEntity = remotes.get(id)
	var fresh := r == null
	if fresh:
		r = RemoteEntity.new()
		r.id = id
		remotes[id] = r
	r.kind = kind
	r.name = name_
	r.size = size
	r.samples.clear()
	r.samples.append([clock, pos, Vector2.ZERO, flags])
	r.placeholder = true
	r.pos = pos
	r.flags = flags
	if fresh:
		actor_added.emit(id, {"kind": "player" if kind == HostEntity.Kind.PLAYER else "monster",
				"size": size, "color": Color(0.45, 0.6, 0.9) if kind == HostEntity.Kind.PLAYER else Color(0.6, 0.2, 0.2),
				"name": name_})

func remove_remote(id: int) -> void:
	if remotes.erase(id):
		actor_removed.emit(id)

## entries: [{id, pos, vel, flags}] at host tick `tick`. Unknown ids are ignored (an
## ENTITY_ADD on the reliable channel may still be on its way).
func apply_snapshot(tick: int, entries: Array) -> void:
	var t := float(tick) / K.TICK_HZ
	if not _clock_synced or absf(clock - t) > 0.5:
		clock = t
		_clock_synced = true
	else:
		clock += (t - clock) * 0.1
	for en: Dictionary in entries:
		var r: RemoteEntity = remotes.get(int(en["id"]))
		if r == null:
			continue
		if r.placeholder:
			r.samples.clear()        # the sample add_remote made, on the local clock
			r.placeholder = false
		elif not r.samples.is_empty() and float(r.samples[-1][0]) >= t:
			continue                 # duplicate or out of order
		r.samples.append([t, en["pos"], en["vel"], int(en["flags"])])
		if r.samples.size() > MAX_SAMPLES:
			r.samples.pop_front()

## Most recent chronicle lines kept (oldest first).
const CHRONICLE_KEEP := 50
var chronicle := PackedStringArray()

func apply_chronicle(lines: PackedStringArray) -> void:
	chronicle.append_array(lines)
	if chronicle.size() > CHRONICLE_KEEP:
		chronicle = chronicle.slice(chronicle.size() - CHRONICLE_KEEP)
	chronicle_lines.emit(lines)

## The host's game clock arrived (join, periodically, after a jump).
func apply_clock(ticks: int) -> void:
	clock_ticks = float(ticks)

## Game hours (WorldClock time) as this client sees it.
func hours() -> float:
	return clock_ticks / WorldClock.TICKS_PER_HOUR

## Advance local time by a frame (also the game clock and the correction offset).
func advance(frame_dt: float) -> void:
	clock += frame_dt
	clock_ticks += frame_dt * K.TICK_HZ
	if view_offset != Vector2.ZERO:
		view_offset *= exp(-frame_dt / CORRECT_BLEND)
		if view_offset.length() < 0.01:
			view_offset = Vector2.ZERO

## Interpolated state of a remote at the render time: {pos, vel, flags}.
func sample_remote(id: int) -> Dictionary:
	var r: RemoteEntity = remotes.get(id)
	if r == null:
		return {}
	var rt := clock - INTERP_DELAY
	var s := r.samples
	if s.is_empty():
		return {"pos": r.pos, "vel": Vector2.ZERO, "flags": r.flags}
	if rt <= float(s[0][0]) or s.size() == 1:
		var only: Array = s[0] if rt <= float(s[0][0]) else s[-1]
		return {"pos": only[1], "vel": only[2], "flags": only[3]}
	for i in range(s.size() - 1, 0, -1):
		var a: Array = s[i - 1]
		var b: Array = s[i]
		if rt >= float(a[0]) and rt <= float(b[0]):
			var span := float(b[0]) - float(a[0])
			var f := 0.0 if span <= 0.0 else (rt - float(a[0])) / span
			return {"pos": (a[1] as Vector2).lerp(b[1], f), "vel": (a[2] as Vector2).lerp(b[2], f), "flags": b[3]}
	var last: Array = s[-1]
	var ahead := minf(rt - float(last[0]), MAX_EXTRAPOLATE)
	return {"pos": (last[1] as Vector2) + (last[2] as Vector2) * ahead, "vel": last[2], "flags": last[3]}

## Emit actor_moved for the own player and every remote, interpolated.
func present() -> void:
	if world == null:
		return
	actor_moved.emit(my_id, view_pos(), body.facing, HostEntity.state_name(HostEntity.body_flags(body, _digging), body.vel))
	for id: int in remotes:
		var st := sample_remote(id)
		var r: RemoteEntity = remotes[id]
		r.pos = st["pos"]
		r.flags = st["flags"]
		actor_moved.emit(id, r.pos, 1 if r.flags & HostEntity.F_RIGHT else -1, HostEntity.state_name(r.flags, st["vel"]))

## Interpolation buffer and identity of an entity someone else moves.
class RemoteEntity extends RefCounted:
	var id := 0
	var kind := 0
	var name := ""
	var size := Vector2.ONE
	## [[host_time: float, pos: Vector2, vel: Vector2, flags: int], ...] oldest first.
	var samples: Array = []
	## True while the only sample is the one add_remote made.
	var placeholder := false
	var pos := Vector2.ZERO
	var flags := 0
