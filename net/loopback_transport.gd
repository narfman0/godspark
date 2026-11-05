## One endpoint on a LoopbackHub. See LoopbackHub.
class_name LoopbackTransport
extends NetTransport

var hub: LoopbackHub
var id: int

func _init(h: LoopbackHub, my_id: int) -> void:
	hub = h
	id = my_id

func poll() -> Array:
	var out := hub.pop(id)
	for ev: Array in out:
		if ev[0] == PACKET:
			_count_in((ev[2] as PackedByteArray).size())
	return out

func send(peer: int, bytes: PackedByteArray, _reliable: bool) -> void:
	var link := peer if id == SERVER else id
	if not hub.linked(link):
		return
	_count_out(bytes.size())
	hub.push(id, peer, PACKET, bytes)

func disconnect_peer(peer: int) -> void:
	hub.part(peer if id == SERVER else id)

func close() -> void:
	if id != SERVER:
		hub.part(id)
