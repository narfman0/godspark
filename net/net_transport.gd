## Moves byte messages between peers. HostEndpoint and ClientEndpoint only talk to this,
## so the same code runs over ENet (EnetTransport), in-process queues (LoopbackTransport,
## for tests and the listen server's own player) or both at once (MultiTransport).
##
## poll() returns events since the last call, in order: [kind, peer, bytes].
## A client's only peer is SERVER (1).
class_name NetTransport
extends RefCounted

enum { CONNECT, DISCONNECT, PACKET }

const SERVER := 1

## Bytes and messages sent, for measurements.
var bytes_out := 0
var packets_out := 0
var bytes_in := 0
var packets_in := 0

func poll() -> Array:
	return []

func send(_peer: int, _bytes: PackedByteArray, _reliable: bool) -> void:
	pass

func disconnect_peer(_peer: int) -> void:
	pass

func close() -> void:
	pass

func _count_out(n: int) -> void:
	bytes_out += n
	packets_out += 1

func _count_in(n: int) -> void:
	bytes_in += n
	packets_in += 1
