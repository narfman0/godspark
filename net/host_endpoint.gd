## The host side of the protocol: turns peer messages into WorldHost calls and WorldHost's
## state and events into per-peer messages, filtered by each player's interest area. No
## nodes and no sockets: it talks to a NetTransport, so tests drive it over a LoopbackHub.
##
## Per tick: read packets, tick the WorldHost, route its events (tile deltas to peers holding
## the chunk, corrections and edit results to their owner), recompute interest (queue new
## chunks nearest first, UNLOAD ones past radius + 1), stream queued chunks within a byte
## budget, flush deltas, and every `snapshot_every` ticks send entity adds/removes and
## snapshots.
class_name HostEndpoint
extends RefCounted

signal player_joined(peer: int, name: String)
signal player_left(peer: int, name: String, reason: int)
## A client asked for a consistency check; `line` is what the host computed.
signal checked(peer: int, line: String)

enum PeerPhase { HANDSHAKE, PLAYING, CLOSING }

var host: WorldHost
var transport: NetTransport
var radius := Interest.DEFAULT_RADIUS
var max_players := 4
## Host ticks per snapshot: 2 at 30 Hz = 15 Hz.
var snapshot_every := 2
## Chunk stream budget per tick: bytes over all peers, and chunks per peer.
var chunk_bytes_per_tick := 96 * 1024
var chunks_per_peer_tick := 16
var handshake_timeout := 5.0
## Host ticks between CLOCK messages (clients run the clock locally in between).
var clock_every := 10 * K.TICK_HZ
## Host time, seconds (ticks / TICK_HZ).
var time := 0.0
var peers := {}           ## peer id -> PeerState
## Message type -> [count, bytes], everything sent.
var sent_by_type := {}
var tick_usec := PackedInt32Array()
var log_fn := Callable()
var _blob_cache := {}     ## Vector2i -> PackedByteArray
var _meta_msg := PackedByteArray()
var _round_robin := 0
## (peer, system id) pairs already logged for a SYS to an unknown system.
var _unknown_sys := {}

func _init(h: WorldHost, t: NetTransport) -> void:
	host = h
	transport = t
	host.world.chunk_changed.connect(_on_chunk_changed)
	_meta()   # built now (a world with no meta.surface scans one): never inside a tick

func _on_chunk_changed(cx: int, cy: int) -> void:
	_blob_cache.erase(Vector2i(cx, cy))

func tick() -> void:
	var t0 := Time.get_ticks_usec()
	_pump()
	host.tick()
	time += 1.0 / K.TICK_HZ
	_route(host.drain())
	for p: PeerState in peers.values():
		if p.phase == PeerPhase.PLAYING:
			_update_interest(p)
	_stream_chunks()
	for p: PeerState in peers.values():
		_flush_deltas(p)
	if host.tick_count % snapshot_every == 0:
		for p: PeerState in peers.values():
			if p.phase == PeerPhase.PLAYING:
				_snapshot(p)
	if host.clock_jumped or host.tick_count % clock_every == 0:
		host.clock_jumped = false
		var msg := Protocol.clock(host.clock.ticks)
		for p: PeerState in peers.values():
			if p.phase == PeerPhase.PLAYING:
				_send(p.id, msg)
	_timeouts()
	tick_usec.append(Time.get_ticks_usec() - t0)

## Tell everyone and close (host shutting down).
func shutdown() -> void:
	for id: int in peers.keys():
		_send(id, Protocol.kick(Protocol.Why.SHUTDOWN, "host closed"))
		transport.disconnect_peer(id)
		_drop_peer(id, Protocol.Why.SHUTDOWN)

func playing_count() -> int:
	var n := 0
	for p: PeerState in peers.values():
		if p.phase == PeerPhase.PLAYING:
			n += 1
	return n

# --- input --------------------------------------------------------------------------

func _pump() -> void:
	for ev: Array in transport.poll():
		var id: int = ev[1]
		match ev[0]:
			NetTransport.CONNECT:
				var p := PeerState.new()
				p.id = id
				p.since = time
				peers[id] = p
			NetTransport.DISCONNECT:
				_drop_peer(id, Protocol.Why.TIMEOUT)
			NetTransport.PACKET:
				_handle(id, ev[2])

func _handle(id: int, bytes: PackedByteArray) -> void:
	var p: PeerState = peers.get(id)
	if p == null or p.phase == PeerPhase.CLOSING:
		return
	var m := Protocol.decode(bytes)
	if m.is_empty():
		p.malformed += 1
		return
	var type: int = m["type"]
	if p.phase == PeerPhase.HANDSHAKE:
		if type == Protocol.T.HELLO:
			_hello(p, m)
		return
	var e := host.entity(p.entity_id)
	match type:
		Protocol.T.STATE:
			host.submit_state(p.entity_id, m["epoch"], m["seq"], m["pos"], m["vel"], m["flags"])
		Protocol.T.EDIT:
			match int(m["op"]):
				ClientWorld.Op.DIG_START:
					host.request_dig(p.entity_id, m["req"], m["x"], m["y"])
				ClientWorld.Op.DIG_STOP:
					host.stop_dig(p.entity_id)
				ClientWorld.Op.PLACE:
					host.request_place(p.entity_id, m["req"], m["x"], m["y"], m["tile"])
		Protocol.T.SYS:
			if not host.receive_sys(p.entity_id, m["sys"], m["kind"], m["data"]):
				var k := Vector2i(id, int(m["sys"]))
				if not _unknown_sys.has(k):
					_unknown_sys[k] = true
					_log("ignored SYS for unknown system %d (kind %d) from peer %d (%s)" % [m["sys"], m["kind"], id, p.name])
		Protocol.T.BYE:
			p.phase = PeerPhase.CLOSING
			_drop_peer(id, m["reason"])
			transport.disconnect_peer(id)
		Protocol.T.CHECK_REQ:
			# Everything the host has changed so far goes out before the answer, so the
			# client, on reading it, holds exactly what this digest covers.
			_route(host.drain())
			_flush_deltas(p)
			var coords: Array[Vector2i] = []
			coords.assign(p.sent.keys())
			Interest.sort_by_distance(coords, Vector2i.ZERO)
			var digest := ChunkHash.raw(host.world, coords)
			var pos: Vector2 = e.body.pos if e != null else Vector2.ZERO
			_send(id, Protocol.check(m["tag"], coords, digest, pos))
			var line := "NETCHECK host name=%s tag=%s chunks=%d hash=%s pos=%.3f,%.3f" % [
					p.name, m["tag"], coords.size(), digest.hex_encode(), pos.x, pos.y]
			checked.emit(id, line)
			_log(line)

func _hello(p: PeerState, m: Dictionary) -> void:
	var name := String(m["name"]).strip_edges()
	var why := Protocol.Why.NONE
	var text := ""
	if int(m["magic"]) != Protocol.MAGIC or int(m["version"]) != Protocol.VERSION:
		why = Protocol.Why.VERSION
		text = "host speaks protocol %d" % Protocol.VERSION
	elif name.is_empty():
		why = Protocol.Why.BAD_NAME
		text = "empty name"
	elif host.player_named(name) != null:
		why = Protocol.Why.NAME_TAKEN
		text = "%s is already playing" % name
	elif playing_count() >= max_players:
		why = Protocol.Why.FULL
		text = "host is full (%d)" % max_players
	if why != Protocol.Why.NONE:
		_send(p.id, Protocol.reject(why, text))
		p.phase = PeerPhase.CLOSING
		transport.disconnect_peer(p.id)
		_log("reject peer %d (%s): %s" % [p.id, name, text])
		return
	var e := host.add_player(name, p.id, {"class": String(m.get("class", ""))})
	p.entity_id = e.id
	p.name = name
	p.phase = PeerPhase.PLAYING
	p.since = time
	_send(p.id, Protocol.welcome(e.id, host.world.width, host.world.height, host.world.world_seed,
			e.body.pos, e.epoch, K.TICK_HZ, K.TICK_HZ / snapshot_every, radius))
	_send(p.id, _meta())
	_send(p.id, Protocol.clock(host.clock.ticks))
	p.arrived_h = host.sim_now()
	var recent := host.recent_chronicle()
	if not recent.is_empty():
		_send(p.id, Protocol.chronicle(recent, true))
	_update_interest(p)
	_log("join peer %d as %s (entity %d) at %s" % [p.id, name, e.id, e.body.pos])
	player_joined.emit(p.id, name)

## META for joining clients, built once (a world without meta.surface, like the test world,
## gets one scanned from its tiles).
func _meta() -> PackedByteArray:
	if _meta_msg.is_empty():
		var m := host.world.meta.duplicate()
		if not m.has("surface"):
			m["surface"] = Array(host.world.scan_surface())
		_meta_msg = Protocol.meta(m)
	return _meta_msg

func _drop_peer(id: int, reason: int) -> void:
	var p: PeerState = peers.get(id)
	if p == null:
		return
	peers.erase(id)
	if p.entity_id != 0:
		host.remove_entity(p.entity_id)
		_route(host.drain())
		_log("leave peer %d (%s) reason %d" % [id, p.name, reason])
		player_left.emit(id, p.name, reason)

func _timeouts() -> void:
	for p: PeerState in peers.values():
		if p.phase == PeerPhase.HANDSHAKE and time - p.since > handshake_timeout:
			_send(p.id, Protocol.kick(Protocol.Why.TIMEOUT, "no hello"))
			p.phase = PeerPhase.CLOSING
			transport.disconnect_peer(p.id)

# --- output -------------------------------------------------------------------------

func _route(events: Array[Dictionary]) -> void:
	for ev in events:
		match int(ev["type"]):
			WorldHost.Ev.TILE:
				var c := Vector2i(int(ev["x"]) >> 5, int(ev["y"]) >> 5)
				_blob_cache.erase(c)
				for p: PeerState in peers.values():
					if p.sent.has(c):
						p.deltas.append_array(PackedInt32Array([ev["x"], ev["y"], ev["layer"], ev["value"]]))
			WorldHost.Ev.LEAVE:
				for p: PeerState in peers.values():
					p.vitals.erase(int(ev["id"]))
					if p.visible.erase(int(ev["id"])):
						_send(p.id, Protocol.ent_remove(ev["id"]))
			WorldHost.Ev.CORRECT:
				if peers.has(int(ev["owner"])):
					_send(ev["owner"], Protocol.correct(ev["epoch"], ev["pos"], ev["vel"]))
					_log("correct entity %d (%s) to %s" % [ev["id"], WorldHost.StateCheck.find_key(ev["why"]), ev["pos"]])
			WorldHost.Ev.OBJECTS:
				var oc := Vector2i(int(ev["cx"]), int(ev["cy"]))
				_blob_cache.erase(oc)
				var msg := Protocol.objects(oc.x, oc.y, host.world.chunk_at(oc.x, oc.y).objects)
				for p: PeerState in peers.values():
					if p.sent.has(oc):
						_flush_deltas(p)      # the tile change lands before the object goes
						_send(p.id, msg)
			WorldHost.Ev.CHRONICLE:
				for p: PeerState in peers.values():
					if p.phase == PeerPhase.PLAYING:
						_send_chronicle(p, ev["lines"], ev["t"])
			WorldHost.Ev.SYS:
				var msg := Protocol.sys(ev["sys"], ev["kind"], ev["data"])
				if msg.is_empty():
					continue
				for p: PeerState in _sys_targets(ev):
					_flush_deltas(p)       # tile changes queued before it land first
					_send(p.id, msg)
			WorldHost.Ev.EDIT_RESULT:
				if peers.has(int(ev["owner"])):
					_flush_deltas(peers[ev["owner"]])     # the tile change lands before its result
					_send(ev["owner"], Protocol.result(ev["req"], ev["reason"], ev["x"], ev["y"], ev["tile"]))

## New lines for one peer: what happened before it arrived (a sim still catching up) is history
## to it, not news.
func _send_chronicle(p: PeerState, lines: PackedStringArray, hours: PackedInt32Array) -> void:
	var old := PackedStringArray()
	var news := PackedStringArray()
	for i in lines.size():
		if hours[i] < p.arrived_h:
			old.append(lines[i])
		else:
			news.append(lines[i])
	for i in range(0, old.size(), 32):
		_send(p.id, Protocol.chronicle(old.slice(i, i + 32), true))
	for i in range(0, news.size(), 32):
		_send(p.id, Protocol.chronicle(news.slice(i, i + 32)))

## Who a SYS event goes to: one player's peer, every playing peer, or those whose interest
## area (radius, in chunks) covers `near`.
func _sys_targets(ev: Dictionary) -> Array:
	var out := []
	var to := int(ev["to"])
	if to != WorldHost.ALL:
		var e := host.entity(to)
		var p: PeerState = peers.get(e.owner) if e != null and e.is_player() else null
		if p != null and p.phase == PeerPhase.PLAYING and p.entity_id == to:
			out.append(p)
		return out
	var near: Variant = ev.get("near")
	var c := Interest.chunk_of(near) if near is Vector2 else Vector2i.ZERO
	for p: PeerState in peers.values():
		if p.phase != PeerPhase.PLAYING:
			continue
		if near is Vector2 and (not p.interest_set or Interest.dist(c, p.center) > radius):
			continue
		out.append(p)
	return out

func _update_interest(p: PeerState) -> void:
	var e := host.entity(p.entity_id)
	if e == null:
		return
	var center := Interest.chunk_of(e.body.center())
	if center == p.center and p.interest_set:
		return
	p.center = center
	p.interest_set = true
	var gone: Array[Vector2i] = []
	for c: Vector2i in p.sent:
		if Interest.dist(c, center) > radius + 1:
			gone.append(c)
	for c in gone:
		p.sent.erase(c)
	if not gone.is_empty():
		_send(p.id, Protocol.unload(gone))
	var queue: Array[Vector2i] = []
	for c in p.queue:
		if Interest.dist(c, center) <= radius + 1:
			queue.append(c)
	var queued := {}
	for c in queue:
		queued[c] = true
	for c in Interest.around(host.world, center, radius):
		if not p.sent.has(c) and not queued.has(c):
			queue.append(c)
	Interest.sort_by_distance(queue, center)
	p.queue = queue

func _stream_chunks() -> void:
	var budget := chunk_bytes_per_tick
	var list: Array = peers.values()
	if list.is_empty():
		return
	_round_robin = (_round_robin + 1) % list.size()
	for k in list.size():
		var p: PeerState = list[(k + _round_robin) % list.size()]
		if p.phase != PeerPhase.PLAYING:
			continue
		var n := 0
		while not p.queue.is_empty() and n < chunks_per_peer_tick and budget > 0:
			var c: Vector2i = p.queue.pop_front()
			var blob: PackedByteArray = _blob_cache.get(c, PackedByteArray())
			if blob.is_empty():
				blob = host.world.chunk_at(c.x, c.y).to_bytes()
				_blob_cache[c] = blob
			var msg := Protocol.chunk(c.x, c.y, blob)
			_send(p.id, msg)
			p.sent[c] = true
			p.chunks_sent += 1
			budget -= msg.size()
			n += 1

func _flush_deltas(p: PeerState) -> void:
	var d := p.deltas
	if d.is_empty():
		return
	p.deltas = PackedInt32Array()
	var per := 4 * 4096
	for i in range(0, d.size(), per):
		_send(p.id, Protocol.tiles(d.slice(i, i + per)))

func _snapshot(p: PeerState) -> void:
	var entries := []
	var vit := []
	for e: HostEntity in host.entities.values():
		var hv := e.vitals()
		if e.id == p.entity_id:
			_vitals_changed(p, e.id, hv, vit)
			continue
		var d := Interest.dist(Interest.chunk_of(e.body.center()), p.center)
		if not p.visible.has(e.id):
			if d > radius:
				continue
			p.visible[e.id] = true
			_send(p.id, Protocol.ent_add(e.id, e.kind, e.body.size, e.body.pos, e.flags, e.name, maxi(0, hv.x), maxi(0, hv.y), _look_of(e)))
			p.vitals[e.id] = hv
		elif d > radius + 1:
			p.visible.erase(e.id)
			p.vitals.erase(e.id)
			_send(p.id, Protocol.ent_remove(e.id))
			continue
		else:
			_vitals_changed(p, e.id, hv, vit)
		entries.append({"id": e.id, "pos": e.body.pos, "vel": e.body.vel, "flags": e.flags})
	if not vit.is_empty():
		for i in range(0, vit.size(), 255):
			_send(p.id, Protocol.vitals(vit.slice(i, i + 255)))
	if not entries.is_empty():
		var msg := Protocol.snapshot(host.tick_count, entries)
		_send(p.id, msg)
		p.snapshot_bytes += msg.size()

func _vitals_changed(p: PeerState, id: int, hv: Vector2i, out: Array) -> void:
	if hv == HostEntity.NO_VITALS or p.vitals.get(id, HostEntity.NO_VITALS) == hv:
		return
	p.vitals[id] = hv
	out.append({"id": id, "hp": hv.x, "max_hp": hv.y})

func _send(peer: int, msg: PackedByteArray) -> void:
	var type := int(msg[0])
	transport.send(peer, msg, not Protocol.unreliable(type))
	var row: Array = sent_by_type.get(type, [0, 0])
	row[0] += 1
	row[1] += msg.size()
	sent_by_type[type] = row
	var p: PeerState = peers.get(peer)
	if p != null:
		p.bytes_out += msg.size()

func _log(s: String) -> void:
	if log_fn.is_valid():
		log_fn.call(s)

## Human-readable traffic summary.
func traffic_report() -> String:
	var lines := PackedStringArray()
	for type: int in sent_by_type:
		var row: Array = sent_by_type[type]
		lines.append("  %-10s %6d msgs %9d bytes (avg %.1f)" % [Protocol.type_name(type), row[0], row[1], float(row[1]) / maxi(1, row[0])])
	return "\n".join(lines)

## What the host knows about one connection.
class PeerState extends RefCounted:
	var id := 0
	var phase := 0
	var name := ""
	var entity_id := 0
	var since := 0.0
	## The sim hour it joined at: chronicle entries from before are history to it.
	var arrived_h := 0
	var center := Vector2i.ZERO
	var interest_set := false
	## Chunks the peer holds (sent and not unloaded): Vector2i -> true.
	var sent := {}
	## Chunks still to send, nearest first.
	var queue: Array[Vector2i] = []
	## Entity ids the peer has been told about.
	var visible := {}
	## Hit points the peer last heard: entity id -> Vector2i(hp, max).
	var vitals := {}
	## Pending tile deltas, flat (x, y, layer, value).
	var deltas := PackedInt32Array()
	var bytes_out := 0
	var snapshot_bytes := 0
	var chunks_sent := 0
	var malformed := 0

## The entity's look as it goes out: what it holds comes from combat, which knows what it swings.
func _look_of(e: HostEntity) -> Dictionary:
	var cs: HostSystem = host.system(HostSystem.COMBAT)
	if cs == null:
		return e.look
	var look := e.look.duplicate()
	look["wield"] = cs.call("shown_wield", e)
	return look
