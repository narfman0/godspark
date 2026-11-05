## In-process message switch for tests and for the listen server's own player. Every message
## is delivered `latency` seconds after it was sent, in order (like ENet reliable on one
## channel: no loss, no reordering). Time only moves when advance() is called. Thread-safe.
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
## Every public call locks: a listen server's host thread and its main-thread client share
## one hub.
var _lock := Mutex.new()

func transport(id: int) -> LoopbackTransport:
	if not _boxes.has(id):
		_boxes[id] = []
	return LoopbackTransport.new(self, id)

## Connect client `id` to the server: both get CONNECT after the latency.
func join(id: int) -> void:
	_lock.lock()
	_links[id] = true
	_push(id, NetTransport.SERVER, NetTransport.CONNECT, PackedByteArray())
	_push(NetTransport.SERVER, id, NetTransport.CONNECT, PackedByteArray())
	_lock.unlock()

## Cut a client's link: both sides get DISCONNECT after anything already in flight.
func part(id: int) -> void:
	_lock.lock()
	if _links.erase(id):
		_push(id, NetTransport.SERVER, NetTransport.DISCONNECT, PackedByteArray())
		_push(NetTransport.SERVER, id, NetTransport.DISCONNECT, PackedByteArray())
	_lock.unlock()

func linked(id: int) -> bool:
	_lock.lock()
	var yes := _links.has(id)
	_lock.unlock()
	return yes

func push(from: int, to: int, kind: int, bytes: PackedByteArray) -> void:
	_lock.lock()
	_push(from, to, kind, bytes)
	_lock.unlock()

func _push(from: int, to: int, kind: int, bytes: PackedByteArray) -> void:
	if not _boxes.has(to):
		_boxes[to] = []
	(_boxes[to] as Array).append([now + latency, from, kind, bytes])

func pop(id: int) -> Array:
	_lock.lock()
	var box: Array = _boxes.get(id, [])
	var out := []
	var n := 0
	while n < box.size() and float(box[n][0]) <= now + 1e-9:
		var m: Array = box[n]
		out.append([m[2], m[1], m[3]])
		n += 1
	if n > 0:
		_boxes[id] = box.slice(n)
	_lock.unlock()
	return out

func advance(dt: float) -> void:
	_lock.lock()
	now += dt
	_lock.unlock()
