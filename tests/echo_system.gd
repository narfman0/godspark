## Test helper (not a test): a tiny system pair proving the plumbing. The client PINGs; the
## host counts pings per player (saved in the player record) and in total (saved with the
## world) and answers PONG to that player only; SHOUT goes back to every player, NEAR to the
## players whose interest covers the sender.
extends RefCounted

const ID := 200
enum K { PING, PONG, SHOUT, NEAR }

class Host extends HostSystem:
	var host: WorldHost
	var total := 0
	var pings := {}           ## entity id -> count
	var ticks := 0
	var added: Array[int] = []
	var removed: Array[int] = []

	func sys_id() -> int:
		return 200

	func attach(h: WorldHost) -> void:
		host = h

	func tick(_h: WorldHost) -> void:
		ticks += 1

	func entity_added(_h: WorldHost, e: HostEntity) -> void:
		added.append(e.id)

	func entity_removed(_h: WorldHost, e: HostEntity) -> void:
		removed.append(e.id)
		pings.erase(e.id)

	func handle(h: WorldHost, e: HostEntity, kind: int, data: PackedByteArray) -> void:
		match kind:
			0:   # PING
				pings[e.id] = int(pings.get(e.id, 0)) + 1
				total += 1
				h.send_sys(200, 1, pong(pings[e.id], total, data), e.id)
			2:   # SHOUT
				h.send_sys(200, 2, data)
			3:   # NEAR
				h.send_sys_near(200, 3, data, e.body.pos)

	func save_player(e: HostEntity) -> Dictionary:
		return {"pings": pings.get(e.id, 0)}

	func load_player(e: HostEntity, d: Dictionary) -> void:
		pings[e.id] = int(d.get("pings", 0))

	func save_world() -> Dictionary:
		return {"total": total}

	func load_world(d: Dictionary) -> void:
		total = int(d.get("total", 0))

	## PONG payload: u16 this player's pings, u32 total pings, then the PING's bytes.
	static func pong(mine: int, all: int, echo: PackedByteArray) -> PackedByteArray:
		var b := PackedByteArray()
		b.resize(6)
		b.encode_u16(0, mine)
		b.encode_u32(2, all)
		b.append_array(echo)
		return b

class Client extends ClientSystem:
	var cw: ClientWorld
	## [kind, data] in arrival order.
	var got: Array = []
	var frames := 0

	func sys_id() -> int:
		return 200

	func attach(c: ClientWorld) -> void:
		cw = c

	func handle(kind: int, data: PackedByteArray) -> void:
		got.append([kind, data])

	func frame(_dt: float) -> void:
		frames += 1

	func kinds(kind: int) -> Array:
		return got.filter(func(g: Array) -> bool: return g[0] == kind)

	## The last PONG: [mine, total, echo].
	func last_pong() -> Array:
		var p := kinds(1)
		if p.is_empty():
			return []
		var d: PackedByteArray = p[-1][1]
		return [d.decode_u16(0), d.decode_u32(2), d.slice(6)]
