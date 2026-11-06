## Every message's byte format, in one place. All little-endian. A message is one packet:
## byte 0 is its type, the rest is its body. decode() returns a Dictionary with "type" and
## the fields named below, or {} for anything malformed (unknown type, truncated, trailing
## garbage where the size is fixed). Strings are u8 length + UTF-8, at most 64 bytes.
##
## Client to host                                             bytes
##   HELLO      u32 magic "GSPK", u16 version, str name,
##              [str class]                                       8 + name (+ 1 + class)
##              class: an SRD class slug for a new character ("" or absent: the host's
##              default). Ignored when the player has a saved character.
##   STATE   *  u16 epoch, u32 seq, f32 x, f32 y,                  20
##              s16 vx*64, s16 vy*64, u8 flags
##   EDIT       u32 req, u8 op, s16 x, s16 y, u16 tile             12
##   BYE        u8 reason                                           2
##   CHECK_REQ  str tag                                             2 + tag
##   SYS        u8 system id, u8 kind, payload (rest, <= MAX_SYS)    3 + payload
##              (both directions; see HostSystem / ClientSystem)
## Host to client
##   WELCOME    u16 version, u32 your_id, u32 width, u32 height,
##              s64 seed, f32 x, f32 y, u16 epoch, u8 tick_hz,
##              u8 snapshot_hz, u8 radius                          36
##   REJECT     u8 reason, str text                                3 + text
##   CHUNK      s16 cx, s16 cy, blob (Chunk.to_bytes, rest)         5 + blob
##   UNLOAD     u16 n, n x (s16 cx, s16 cy)                         3 + 4n
##   TILES      u16 n, n x (u16 x, u16 y, u8 layer, u16 value)      3 + 7n
##   ENT_ADD    u32 id, u8 kind, f32 w, f32 h, f32 x, f32 y,
##              u8 flags, u16 hp, u16 max_hp, str name,
##              str slug, str people, u8 rank, u8 scale*20         32 + strings
##              max_hp 0: the entity has no hit points (no combatant). The rest is the
##              compact look (protocol 7): SRD slug or "player:<class>", people key, rank
##              (index in RANKS), body scale; "" / 0 when it has none.
##   ENT_REMOVE u32 id                                              5
##   SNAPSHOT * u32 tick, u8 n, n x (u32 id, f32 x, f32 y,
##              s16 vx*64, s16 vy*64, u8 flags)                     6 + 17n
##   CORRECT    u16 epoch, f32 x, f32 y, s16 vx*64, s16 vy*64      15
##   RESULT     u32 req, u8 reason, s16 x, s16 y, u16 tile         12
##   CHECK      str tag, u16 n, n x (s16 cx, s16 cy), 32 B sha256,
##              f32 x, f32 y                                       44 + tag + 4n
##   KICK       u8 reason, str text                                3 + text
##   META       u32 raw size, zstd(var_to_bytes({surface: PackedInt32Array of column
##              deltas, biomes, bands, sites}))                     5 + blob
##              Sent once, right after WELCOME and before any chunk.
##   CLOCK      s64 game ticks (WorldClock.ticks)                   9
##              After META, every CLOCK_EVERY host ticks, and at once after a jump.
##   CHRONICLE  u8 history, u8 n, n x (u16 len, UTF-8 text <= 400 B)   3 + lines; history: from
##              before this player arrived (kept, not shown as news)
##              New world-history lines (WorldSim.describe), and a few on join.
##   OBJECTS    s16 cx, s16 cy, u16 n, n x 5 B (Chunk.objects)     7 + 5n
##              A held chunk's whole dressing list, after a change (CHUNK carries it too).
##   VITALS     u8 n, n x (u32 id, u16 hp, u16 max_hp)               2 + 8n
##              Hit points that changed since the peer last heard, for entities it sees
##              and its own; sent on snapshot ticks. ENT_ADD carries the first value.
## (* = unreliable, sequenced; everything else reliable and ordered on one channel, so a
## chunk blob always precedes the tile deltas for that chunk.)
class_name Protocol
extends RefCounted

const MAGIC := 0x4B505347    # "GSPK"
const VERSION := 11  # 9: biome tiles 21-33, 112-116 and walls 10-17; 10: river tiles 117-119; 11: the dodge roll and richer SWING and STATUS (an older peer cannot read them)
## ENT_ADD rank byte: index into this list.
const RANKS := ["standard", "minion", "elite", "champion", "boss"]
const MAX_STR := 64
const VEL_SCALE := 64.0

enum T {
	HELLO = 1, STATE = 2, EDIT = 3, BYE = 4, CHECK_REQ = 5,
	WELCOME = 16, REJECT = 17, CHUNK = 18, UNLOAD = 19, TILES = 20, ENT_ADD = 21,
	ENT_REMOVE = 22, SNAPSHOT = 23, CORRECT = 24, RESULT = 25, CHECK = 26, KICK = 27,
	META = 28, CLOCK = 29, CHRONICLE = 30, OBJECTS = 31, SYS = 32, VITALS = 33,
}
## Largest SYS payload in bytes.
const MAX_SYS := 32768
## Largest decompressed META body accepted.
const MAX_META := 8 * 1024 * 1024
## The world.meta keys a client gets.
const META_KEYS := ["biomes", "bands", "sites"]

## REJECT / KICK / BYE reasons.
enum Why { NONE, VERSION, FULL, NAME_TAKEN, BAD_NAME, TIMEOUT, MALFORMED, SHUTDOWN, LEAVING, FINAL }

static func unreliable(type: int) -> bool:
	return type == T.STATE or type == T.SNAPSHOT

static func type_name(type: int) -> String:
	var k: Variant = T.find_key(type)
	return String(k) if k != null else "?%d" % type

# --- encoding -----------------------------------------------------------------------

static func hello(name: String, char_class := "") -> PackedByteArray:
	var w := Writer.new(T.HELLO)
	w.u32(MAGIC)
	w.u16(VERSION)
	w.str8(name)
	w.str8(char_class)
	return w.b

## A system message (either direction). Empty if the payload is over MAX_SYS.
static func sys(sys_id: int, kind: int, data: PackedByteArray) -> PackedByteArray:
	if data.size() > MAX_SYS:
		return PackedByteArray()
	var w := Writer.new(T.SYS)
	w.u8(sys_id)
	w.u8(kind)
	w.b.append_array(data)
	return w.b

## entries: [{id, hp, max_hp}], at most 255.
static func vitals(entries: Array) -> PackedByteArray:
	var w := Writer.new(T.VITALS)
	var n := mini(entries.size(), 255)
	w.u8(n)
	for i in n:
		var e: Dictionary = entries[i]
		w.u32(int(e["id"]))
		w.u16(clampi(int(e["hp"]), 0, 0xffff))
		w.u16(clampi(int(e["max_hp"]), 0, 0xffff))
	return w.b

static func state(epoch: int, seq: int, pos: Vector2, vel: Vector2, flags: int) -> PackedByteArray:
	var w := Writer.new(T.STATE)
	w.u16(epoch)
	w.u32(seq)
	w.vec(pos)
	w.vel(vel)
	w.u8(flags)
	return w.b

static func edit(req: int, op: int, x: int, y: int, tile: int) -> PackedByteArray:
	var w := Writer.new(T.EDIT)
	w.u32(req)
	w.u8(op)
	w.s16(x)
	w.s16(y)
	w.u16(tile)
	return w.b

static func bye(reason: int) -> PackedByteArray:
	var w := Writer.new(T.BYE)
	w.u8(reason)
	return w.b

static func check_req(tag: String) -> PackedByteArray:
	var w := Writer.new(T.CHECK_REQ)
	w.str8(tag)
	return w.b

static func welcome(id: int, width: int, height: int, seed_value: int, pos: Vector2, epoch: int,
		tick_hz: int, snapshot_hz: int, radius: int) -> PackedByteArray:
	var w := Writer.new(T.WELCOME)
	w.u16(VERSION)
	w.u32(id)
	w.u32(width)
	w.u32(height)
	w.s64(seed_value)
	w.vec(pos)
	w.u16(epoch)
	w.u8(tick_hz)
	w.u8(snapshot_hz)
	w.u8(radius)
	return w.b

static func reject(reason: int, text: String) -> PackedByteArray:
	return _reason_text(T.REJECT, reason, text)

static func kick(reason: int, text: String) -> PackedByteArray:
	return _reason_text(T.KICK, reason, text)

static func _reason_text(type: int, reason: int, text: String) -> PackedByteArray:
	var w := Writer.new(type)
	w.u8(reason)
	w.str8(text)
	return w.b

static func chunk(cx: int, cy: int, blob: PackedByteArray) -> PackedByteArray:
	var w := Writer.new(T.CHUNK)
	w.s16(cx)
	w.s16(cy)
	w.b.append_array(blob)
	return w.b

static func unload(coords: Array) -> PackedByteArray:
	var w := Writer.new(T.UNLOAD)
	w.u16(coords.size())
	for c: Vector2i in coords:
		w.s16(c.x)
		w.s16(c.y)
	return w.b

## deltas: flat PackedInt32Array of (x, y, layer, value) quadruples.
static func tiles(deltas: PackedInt32Array) -> PackedByteArray:
	var n := deltas.size() / 4
	var b := PackedByteArray()
	b.resize(3 + 7 * n)
	b[0] = T.TILES
	b.encode_u16(1, n)
	var o := 3
	for i in n:
		b.encode_u16(o, deltas[i * 4])
		b.encode_u16(o + 2, deltas[i * 4 + 1])
		b[o + 4] = deltas[i * 4 + 2]
		b.encode_u16(o + 5, deltas[i * 4 + 3])
		o += 7
	return b

## hp, max_hp: max_hp 0 for an entity without hit points.
## look: the entity's look; only slug, people, rank and scale travel (compact_look).
static func ent_add(id: int, kind: int, size: Vector2, pos: Vector2, flags: int, name: String,
		hp := 0, max_hp := 0, look := {}) -> PackedByteArray:
	var w := Writer.new(T.ENT_ADD)
	w.u32(id)
	w.u8(kind)
	w.vec(size)
	w.vec(pos)
	w.u8(flags)
	w.u16(clampi(hp, 0, 0xffff))
	w.u16(clampi(max_hp, 0, 0xffff))
	w.str8(name)
	w.str8(String(look.get("slug", "")))
	w.str8(String(look.get("people", "")))
	w.u8(maxi(0, RANKS.find(String(look.get("rank", "standard")))))
	w.u8(clampi(roundi(float(look.get("scale", 0.0)) * 20.0), 0, 255))
	return w.b

## What of a look ENT_ADD carries, as decode gives it back: {slug?, people?, rank?, scale?}
## (keys only when set; rank only when not standard).
static func compact_look(look: Dictionary) -> Dictionary:
	var out := {}
	if String(look.get("slug", "")) != "":
		out["slug"] = String(look["slug"]).left(MAX_STR)
	if String(look.get("people", "")) != "":
		out["people"] = String(look["people"]).left(MAX_STR)
	var r := RANKS.find(String(look.get("rank", "standard")))
	if r > 0:
		out["rank"] = RANKS[r]
	var sc := clampi(roundi(float(look.get("scale", 0.0)) * 20.0), 0, 255)
	if sc > 0:
		out["scale"] = sc / 20.0
	return out

static func ent_remove(id: int) -> PackedByteArray:
	var w := Writer.new(T.ENT_REMOVE)
	w.u32(id)
	return w.b

## entries: [{id, pos, vel, flags}], at most 255.
static func snapshot(tick: int, entries: Array) -> PackedByteArray:
	var n := mini(entries.size(), 255)
	var b := PackedByteArray()
	b.resize(6 + 17 * n)
	b[0] = T.SNAPSHOT
	b.encode_u32(1, tick & 0xffffffff)
	b[5] = n
	var o := 6
	for i in n:
		var e: Dictionary = entries[i]
		var p: Vector2 = e["pos"]
		var v: Vector2 = e["vel"]
		b.encode_u32(o, int(e["id"]))
		b.encode_float(o + 4, p.x)
		b.encode_float(o + 8, p.y)
		b.encode_s16(o + 12, _vq(v.x))
		b.encode_s16(o + 14, _vq(v.y))
		b[o + 16] = int(e["flags"]) & 0xff
		o += 17
	return b

static func correct(epoch: int, pos: Vector2, vel: Vector2) -> PackedByteArray:
	var w := Writer.new(T.CORRECT)
	w.u16(epoch)
	w.vec(pos)
	w.vel(vel)
	return w.b

static func result(req: int, reason: int, x: int, y: int, tile: int) -> PackedByteArray:
	var w := Writer.new(T.RESULT)
	w.u32(req)
	w.u8(reason)
	w.s16(x)
	w.s16(y)
	w.u16(tile)
	return w.b

static func check(tag: String, coords: Array, digest: PackedByteArray, pos: Vector2) -> PackedByteArray:
	var w := Writer.new(T.CHECK)
	w.str8(tag)
	w.u16(coords.size())
	for c: Vector2i in coords:
		w.s16(c.x)
		w.s16(c.y)
	var d := digest.duplicate()
	d.resize(32)
	w.b.append_array(d)
	w.vec(pos)
	return w.b

## The parts of world.meta a client needs. surface: the highest solid tile per column
## (sent as deltas so it compresses to a few hundred bytes).
static func meta(m: Dictionary) -> PackedByteArray:
	var d := {}
	for k: String in META_KEYS:
		if m.has(k):
			d[k] = m[k]
	var surf: Array = m.get("surface", [])
	var deltas := PackedInt32Array()
	deltas.resize(surf.size())
	var prev := 0
	for i in surf.size():
		deltas[i] = int(surf[i]) - prev
		prev = int(surf[i])
	d["surface"] = deltas
	var raw := var_to_bytes(d)
	var w := Writer.new(T.META)
	w.u32(raw.size())
	w.b.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD))
	return w.b

static func _decode_meta(r: Reader) -> Variant:
	var n := r.u32()
	var blob := r.rest()
	if not r.ok or n <= 0 or n > MAX_META or blob.is_empty():
		return null
	var raw := blob.decompress(n, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != n:
		return null
	var d: Variant = bytes_to_var(raw)
	if not d is Dictionary or not (d as Dictionary).get("surface") is PackedInt32Array:
		return null
	var out := {}
	for k: String in META_KEYS:
		if d.has(k):
			out[k] = d[k]
	var deltas: PackedInt32Array = d["surface"]
	var surf: Array = []
	surf.resize(deltas.size())
	var acc := 0
	for i in deltas.size():
		acc += deltas[i]
		surf[i] = acc
	out["surface"] = surf
	return out

const MAX_LINE := 400

static func objects(cx: int, cy: int, records: PackedByteArray) -> PackedByteArray:
	var w := Writer.new(T.OBJECTS)
	w.s16(cx)
	w.s16(cy)
	w.u16(records.size() / Chunk.OBJ_BYTES)
	w.b.append_array(records.slice(0, records.size() / Chunk.OBJ_BYTES * Chunk.OBJ_BYTES))
	return w.b

static func chronicle(lines: PackedStringArray, history := false) -> PackedByteArray:
	var w := Writer.new(T.CHRONICLE)
	w.u8(1 if history else 0)
	var n := mini(lines.size(), 255)
	w.u8(n)
	for i in n:
		var u := lines[i].to_utf8_buffer()
		if u.size() > MAX_LINE:
			u = u.slice(0, MAX_LINE)
		w.u16(u.size())
		w.b.append_array(u)
	return w.b

static func clock(ticks: int) -> PackedByteArray:
	var w := Writer.new(T.CLOCK)
	w.s64(ticks)
	return w.b

static func _vq(v: float) -> int:
	return clampi(roundi(v * VEL_SCALE), -32768, 32767)

# --- decoding -----------------------------------------------------------------------

static func decode(b: PackedByteArray) -> Dictionary:
	if b.is_empty():
		return {}
	var r := Reader.new(b)
	var type := r.u8()
	var m := {"type": type}
	match type:
		T.HELLO:
			m["magic"] = r.u32()
			m["version"] = r.u16()
			m["name"] = r.str8()
			m["class"] = r.str8() if r.ok and not r.at_end() else ""   # absent before version 6
		T.STATE:
			m["epoch"] = r.u16()
			m["seq"] = r.u32()
			m["pos"] = r.vec()
			m["vel"] = r.vel()
			m["flags"] = r.u8()
		T.EDIT:
			m["req"] = r.u32()
			m["op"] = r.u8()
			m["x"] = r.s16()
			m["y"] = r.s16()
			m["tile"] = r.u16()
		T.BYE:
			m["reason"] = r.u8()
		T.CHECK_REQ:
			m["tag"] = r.str8()
		T.WELCOME:
			m["version"] = r.u16()
			m["id"] = r.u32()
			m["width"] = r.u32()
			m["height"] = r.u32()
			m["seed"] = r.s64()
			m["pos"] = r.vec()
			m["epoch"] = r.u16()
			m["tick_hz"] = r.u8()
			m["snapshot_hz"] = r.u8()
			m["radius"] = r.u8()
		T.REJECT, T.KICK:
			m["reason"] = r.u8()
			m["text"] = r.str8()
		T.CHUNK:
			m["cx"] = r.s16()
			m["cy"] = r.s16()
			m["blob"] = r.rest()
		T.UNLOAD:
			var n := r.u16()
			var list: Array[Vector2i] = []
			for i in n:
				list.append(Vector2i(r.s16(), r.s16()))
			m["coords"] = list
		T.TILES:
			var n := r.u16()
			var d := PackedInt32Array()
			for i in n:
				d.append(r.u16())
				d.append(r.u16())
				d.append(r.u8())
				d.append(r.u16())
			m["deltas"] = d
		T.ENT_ADD:
			m["id"] = r.u32()
			m["kind"] = r.u8()
			m["size"] = r.vec()
			m["pos"] = r.vec()
			m["flags"] = r.u8()
			m["hp"] = r.u16()
			m["max_hp"] = r.u16()
			m["name"] = r.str8()
			var look := {}
			var slug := r.str8()
			var people := r.str8()
			var rank := r.u8()
			var scale := r.u8()
			if slug != "":
				look["slug"] = slug
			if people != "":
				look["people"] = people
			if rank > 0 and rank < RANKS.size():
				look["rank"] = RANKS[rank]
			if scale > 0:
				look["scale"] = scale / 20.0
			m["look"] = look
		T.ENT_REMOVE:
			m["id"] = r.u32()
		T.SNAPSHOT:
			m["tick"] = r.u32()
			var n := r.u8()
			var list := []
			for i in n:
				list.append({"id": r.u32(), "pos": r.vec(), "vel": r.vel(), "flags": r.u8()})
			m["entries"] = list
		T.CORRECT:
			m["epoch"] = r.u16()
			m["pos"] = r.vec()
			m["vel"] = r.vel()
		T.RESULT:
			m["req"] = r.u32()
			m["reason"] = r.u8()
			m["x"] = r.s16()
			m["y"] = r.s16()
			m["tile"] = r.u16()
		T.META:
			var d: Variant = _decode_meta(r)
			if d == null:
				return {}
			m["meta"] = d
		T.CLOCK:
			m["ticks"] = r.s64()
		T.OBJECTS:
			m["cx"] = r.s16()
			m["cy"] = r.s16()
			var n := r.u16()
			m["records"] = r.bytes(n * Chunk.OBJ_BYTES)
		T.CHRONICLE:
			m["history"] = r.u8() != 0
			var n := r.u8()
			var lines := PackedStringArray()
			for i in n:
				var k := r.u16()
				if k > MAX_LINE:
					return {}
				lines.append(r.bytes(k).get_string_from_utf8())
			m["lines"] = lines
		T.SYS:
			m["sys"] = r.u8()
			m["kind"] = r.u8()
			m["data"] = r.rest()
			if (m["data"] as PackedByteArray).size() > MAX_SYS:
				return {}
		T.VITALS:
			var n := r.u8()
			var list := []
			for i in n:
				list.append({"id": r.u32(), "hp": r.u16(), "max_hp": r.u16()})
			m["entries"] = list
		T.CHECK:
			m["tag"] = r.str8()
			var n := r.u16()
			var list: Array[Vector2i] = []
			for i in n:
				list.append(Vector2i(r.s16(), r.s16()))
			m["coords"] = list
			m["digest"] = r.bytes(32)
			m["pos"] = r.vec()
		_:
			return {}
	if not r.ok or (type != T.CHUNK and type != T.META and not r.at_end()):
		return {}
	return m

## Builds a message into `b`.
class Writer extends RefCounted:
	var b := PackedByteArray()

	func _init(type: int) -> void:
		b.append(type)

	func u8(v: int) -> void:
		b.append(v & 0xff)

	func u16(v: int) -> void:
		var o := b.size()
		b.resize(o + 2)
		b.encode_u16(o, v & 0xffff)

	func s16(v: int) -> void:
		var o := b.size()
		b.resize(o + 2)
		b.encode_s16(o, clampi(v, -32768, 32767))

	func u32(v: int) -> void:
		var o := b.size()
		b.resize(o + 4)
		b.encode_u32(o, v & 0xffffffff)

	func s64(v: int) -> void:
		var o := b.size()
		b.resize(o + 8)
		b.encode_s64(o, v)

	func f32(v: float) -> void:
		var o := b.size()
		b.resize(o + 4)
		b.encode_float(o, v)

	func vec(v: Vector2) -> void:
		f32(v.x)
		f32(v.y)

	func vel(v: Vector2) -> void:
		s16(Protocol._vq(v.x))
		s16(Protocol._vq(v.y))

	func str8(s: String) -> void:
		var u := s.to_utf8_buffer()
		if u.size() > Protocol.MAX_STR:
			u = u.slice(0, Protocol.MAX_STR)
		u8(u.size())
		b.append_array(u)

## Bounds-checked reads: past the end, `ok` goes false and reads return zeros.
class Reader extends RefCounted:
	var b: PackedByteArray
	var o := 0
	var ok := true

	func _init(bytes: PackedByteArray) -> void:
		b = bytes

	func _has(n: int) -> bool:
		if o + n > b.size():
			ok = false
			return false
		return true

	func at_end() -> bool:
		return o == b.size()

	func u8() -> int:
		if not _has(1):
			return 0
		o += 1
		return b[o - 1]

	func u16() -> int:
		if not _has(2):
			return 0
		o += 2
		return b.decode_u16(o - 2)

	func s16() -> int:
		if not _has(2):
			return 0
		o += 2
		return b.decode_s16(o - 2)

	func u32() -> int:
		if not _has(4):
			return 0
		o += 4
		return b.decode_u32(o - 4)

	func s64() -> int:
		if not _has(8):
			return 0
		o += 8
		return b.decode_s64(o - 8)

	func f32() -> float:
		if not _has(4):
			return 0.0
		o += 4
		return b.decode_float(o - 4)

	func vec() -> Vector2:
		var x := f32()
		return Vector2(x, f32())

	func vel() -> Vector2:
		var x := s16() / Protocol.VEL_SCALE
		return Vector2(x, s16() / Protocol.VEL_SCALE)

	func str8() -> String:
		var n := u8()
		if not _has(n):
			return ""
		o += n
		return b.slice(o - n, o).get_string_from_utf8()

	func bytes(n: int) -> PackedByteArray:
		if not _has(n):
			return PackedByteArray()
		o += n
		return b.slice(o - n, o)

	func rest() -> PackedByteArray:
		var out := b.slice(o)
		o = b.size()
		return out
