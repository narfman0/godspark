## In-process message switch for tests and for the listen server's own player. Every message
## is delivered `latency` seconds after it was sent, in order (like ENet reliable on one
## channel: no loss, no reordering). Time only moves when advance() is called.
##
##   var hub := LoopbackHub.new()
##   var server := hub.transport(NetTransport.SERVER)
##   var client := hub.transport(2)
##   hub.join(2)                      # both sides get CONNECT
##   hub.advance(1.0 / 60.0)
class_name LoopbackHub
extends RefCounted

var latency := 0.0
var now := 0.0
## peer id -> Array of [deliver_at, from, kind, bytes]
var _boxes := {}
var _links := {}

func transport(id: int) -> LoopbackTransport:
	if not _boxes.has(id):
		_boxes[id] = []
	return LoopbackTransport.new(self, id)

## Connect client `id` to the server: both get CONNECT after the latency.
func join(id: int) -> void:
	_links[id] = true
	push(id, NetTransport.SERVER, NetTransport.CONNECT, PackedByteArray())
	push(NetTransport.SERVER, id, NetTransport.CONNECT, PackedByteArray())

## Cut a client's link: both sides get DISCONNECT after anything already in flight.
func part(id: int) -> void:
	if not _links.erase(id):
		return
	push(id, NetTransport.SERVER, NetTransport.DISCONNECT, PackedByteArray())
	push(NetTransport.SERVER, id, NetTransport.DISCONNECT, PackedByteArray())

func linked(id: int) -> bool:
	return _links.has(id)

func push(from: int, to: int, kind: int, bytes: PackedByteArray) -> void:
	if not _boxes.has(to):
		_boxes[to] = []
	(_boxes[to] as Array).append([now + latency, from, kind, bytes])

func pop(id: int) -> Array:
	var box: Array = _boxes.get(id, [])
	var out := []
	var n := 0
	while n < box.size() and float(box[n][0]) <= now + 1e-9:
		var m: Array = box[n]
		out.append([m[2], m[1], m[3]])
		n += 1
	if n > 0:
		_boxes[id] = box.slice(n)
	return out

func advance(dt: float) -> void:
	now += dt
