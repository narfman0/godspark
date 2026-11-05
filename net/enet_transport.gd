## NetTransport over Godot's ENetMultiplayerPeer, used raw: it is not installed as the
## SceneTree's multiplayer peer (no RPCs), we poll it and read packets ourselves.
## Reliable messages go reliable-ordered, the rest unreliable-ordered; ENet keeps the two
## modes on separate internal channels, so snapshots never wait behind chunk streams.
##
##   var t := EnetTransport.new(); t.listen(24650, 4)        # host
##   var t := EnetTransport.new(); t.connect_to("127.0.0.1", 24650)
class_name EnetTransport
extends NetTransport

## Peer timeouts (ms): ENet drops a peer that has not acknowledged anything for this long.
const TIMEOUT_MIN_MS := 2000
const TIMEOUT_MAX_MS := 5000

var peer: ENetMultiplayerPeer
var is_server := false
var _events := []
var _connected := false
var _closed := false

func listen(port: int, max_clients: int, bind := "*") -> Error:
	peer = ENetMultiplayerPeer.new()
	peer.set_bind_ip(bind)
	var err := peer.create_server(port, max_clients)
	if err != OK:
		peer = null
		return err
	is_server = true
	_hook()
	return OK

func connect_to(address: String, port: int) -> Error:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		peer = null
		return err
	_hook()
	return OK

func _hook() -> void:
	peer.peer_connected.connect(_on_connected)
	peer.peer_disconnected.connect(_on_disconnected)

func _on_connected(id: int) -> void:
	var p := peer.get_peer(id)
	if p != null:
		p.set_timeout(32, TIMEOUT_MIN_MS, TIMEOUT_MAX_MS)
	if not is_server:
		_connected = true
	_events.append([CONNECT, id, PackedByteArray()])

func _on_disconnected(id: int) -> void:
	_events.append([DISCONNECT, id, PackedByteArray()])
	if not is_server:
		_closed = true

func poll() -> Array:
	if peer == null:
		var none := _events
		_events = []
		return none
	peer.poll()
	while peer.get_available_packet_count() > 0:
		var from := peer.get_packet_peer()
		var b := peer.get_packet()
		_count_in(b.size())
		_events.append([PACKET, from, b])
	# A client that never got through reports one DISCONNECT for the server.
	if not is_server and not _closed and peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		_closed = true
		_events.append([DISCONNECT, SERVER, PackedByteArray()])
	var out := _events
	_events = []
	return out

func send(to: int, bytes: PackedByteArray, reliable: bool) -> void:
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	peer.set_target_peer(to)
	peer.transfer_channel = 0
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	if peer.put_packet(bytes) == OK:
		_count_out(bytes.size())

## Graceful: queued packets go out first, then the peer is told.
func disconnect_peer(id: int) -> void:
	if peer == null:
		return
	if is_server:
		var p := peer.get_peer(id)
		if p != null:
			p.peer_disconnect_later()
	else:
		close()

## Flushes what is queued, then closes.
func close() -> void:
	if peer == null:
		return
	if not is_server:
		var p := peer.get_peer(SERVER)
		if p != null:
			p.peer_disconnect_later()
		for i in 20:
			peer.poll()
			if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
				break
			OS.delay_msec(5)
	else:
		peer.host.flush()
	peer.close()
	peer = null
	_closed = true
