## Several server-side transports as one: a listen server takes ENet peers and its own
## player's loopback at once. Peer ids must not collide (ENet never hands out 1, which the
## loopback hub uses for the server; the local player gets LOCAL_PEER).
class_name MultiTransport
extends NetTransport

var parts: Array[NetTransport] = []
var _owner := {}   # peer -> NetTransport

func add(t: NetTransport) -> void:
	parts.append(t)

func poll() -> Array:
	var out := []
	for t in parts:
		for ev: Array in t.poll():
			if ev[0] == CONNECT:
				_owner[ev[1]] = t
			out.append(ev)
			if ev[0] == PACKET:
				_count_in((ev[2] as PackedByteArray).size())
	return out

func send(peer: int, bytes: PackedByteArray, reliable: bool) -> void:
	var t: NetTransport = _owner.get(peer)
	if t != null:
		_count_out(bytes.size())
		t.send(peer, bytes, reliable)

func disconnect_peer(peer: int) -> void:
	var t: NetTransport = _owner.get(peer)
	if t != null:
		t.disconnect_peer(peer)

func close() -> void:
	for t in parts:
		t.close()
