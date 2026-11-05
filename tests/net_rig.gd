## Test helper (not a test): a host and N clients over a LoopbackHub, driven by simulated
## time. Frames run at 60 Hz; the host ticks at K.TICK_HZ.
extends RefCounted

var hub := LoopbackHub.new()
var host: WorldHost
var ep: HostEndpoint
var clients: Array[ClientEndpoint] = []
var inputs: Array[PlayerInput] = []
var ids: Array[int] = []
var frame_dt := 1.0 / 60.0
var _acc := 0.0
var _next := 2

func _init(world: TileWorld, latency := 0.0) -> void:
	hub.latency = latency
	host = WorldHost.new(world)
	ep = HostEndpoint.new(host, hub.transport(NetTransport.SERVER))

func add_client(name: String) -> ClientEndpoint:
	var id := _next
	_next += 1
	var c := ClientEndpoint.new(hub.transport(id), name)
	hub.join(id)
	clients.append(c)
	inputs.append(PlayerInput.new())
	ids.append(id)
	return c

## Disconnect client i abruptly (no BYE).
func cut(i: int) -> void:
	hub.part(ids[i])

func frame() -> void:
	hub.advance(frame_dt)
	for i in clients.size():
		clients[i].frame(frame_dt, inputs[i])
		inputs[i].jump_pressed = false
	_acc += frame_dt
	while _acc >= 1.0 / K.TICK_HZ - 1e-9:
		_acc -= 1.0 / K.TICK_HZ
		ep.tick()

func run(seconds: float) -> void:
	for i in roundi(seconds / frame_dt):
		frame()

## Run until cond() is true or `limit` seconds pass. Returns seconds taken, or -1.
func until(cond: Callable, limit: float) -> float:
	var t := 0.0
	while t < limit:
		if cond.call():
			return t
		frame()
		t += frame_dt
	return t if cond.call() else -1.0

func cw(i: int) -> ClientWorld:
	return clients[i].cw

func host_entity(i: int) -> HostEntity:
	var p: HostEndpoint.PeerState = ep.peers.get(ids[i])
	return host.entity(p.entity_id) if p != null else null

## Host-side digest over the chunks the host believes client i holds.
func host_hash_for(i: int) -> String:
	var p: HostEndpoint.PeerState = ep.peers[ids[i]]
	return ChunkHash.of(host.world, p.sent.keys())

func in_sync(i: int) -> bool:
	var p: HostEndpoint.PeerState = ep.peers.get(ids[i])
	if p == null or cw(i) == null or p.sent.size() != cw(i).loaded.size():
		return false
	return host_hash_for(i) == cw(i).loaded_hash()
