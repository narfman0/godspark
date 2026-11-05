## Wire layouts of the items system's SYS messages (HostSystem.ITEMS = 3). Little-endian;
## str = u8 length + UTF-8. Every encode has a decode returning the same values ({} or []
## when malformed); tests/test_items_codec.gd round-trips them.
##
## Item record (rec):
##   str base, u16 count, u8 flags (1 material, 2 quality, 4 affixes, 8 magic, 16 tier,
##   32 spark, 64 bonded), then in flag order: str material, str quality, u8 n + n str affix,
##   str magic, u8 tier, str spark id + u8 rank. Counts above 65535 (coin) are clamped.
##
## Host -> client
##   SLOTS   1  u32 coin, u8 selected, u8 n, n x (u8 index, u8 has, rec if has)
##              index: 0-9 hotbar, 10-49 bag, 50-68 Equipment.SLOTS
##   STARS   2  u16 walk, u16 climb, u16 swim, u16 fly (ft), str size, u8 slots, u8 n,
##              n x (str id, u8 rank, u8 x, u8 y)
##   DROPS   3  u16 n, n x (u32 id, f32 x, f32 y, f32 vx, f32 vy, rec)   (add, or update by id)
##   GONE    4  u16 n, n x (u32 id, u32 by)        by: entity that picked it up, 0 = gone
##   MOVED   5  u16 n, n x (u32 id, f32 x, f32 y, f32 vx, f32 vy)
##   NOTE    6  u8 op (a client kind, or 0), u8 ok, str word   (refusals and results for the UI)
##   BONDING 7  u8 slot index, u16 ms left (0 = done or stopped)
## Client -> host
##   MOVE   16  u8 a, u8 b          any two indices (equip = move to an equipment index;
##                                   b = 255: unequip/move to the first free bag slot)
##   USE    17  u8 index
##   DROP   18  u8 index, u16 n
##   SELECT 19  u8 hotbar slot
##   BOND   20  u8 index
##   KINDLE 21  u8 index
##   SWAP   22  u8 star, u8 index
##   CRAFT  23  str recipe, u8 times
class_name ItemsCodec
extends RefCounted

enum K { SLOTS = 1, STARS = 2, DROPS = 3, GONE = 4, MOVED = 5, NOTE = 6, BONDING = 7,
	MOVE = 16, USE = 17, DROP = 18, SELECT = 19, BOND = 20, KINDLE = 21, SWAP = 22, CRAFT = 23 }
const ANY := 255

# --- writer / reader ----------------------------------------------------------------------

static func _w() -> StreamPeerBuffer:
	var b := StreamPeerBuffer.new()
	b.big_endian = false
	return b

static func _r(data: PackedByteArray) -> StreamPeerBuffer:
	var b := StreamPeerBuffer.new()
	b.big_endian = false
	b.data_array = data
	return b

static func _str(b: StreamPeerBuffer, s: String) -> void:
	var u := s.to_utf8_buffer()
	if u.size() > 255:
		u = u.slice(0, 255)
	b.put_u8(u.size())
	b.put_data(u)

## Reads a str; null if short.
static func _rstr(b: StreamPeerBuffer) -> Variant:
	if b.get_available_bytes() < 1:
		return null
	var n := b.get_u8()
	if b.get_available_bytes() < n:
		return null
	var r: Array = b.get_data(n)
	return (r[1] as PackedByteArray).get_string_from_utf8()

static func _need(b: StreamPeerBuffer, n: int) -> bool:
	return b.get_available_bytes() >= n

static func put_rec(b: StreamPeerBuffer, it: Dictionary) -> void:
	_str(b, String(it.get("base", "")))
	b.put_u16(clampi(int(it.get("count", 1)), 0, 0xffff))
	var f := 0
	if it.has("material"): f |= 1
	if it.has("quality"): f |= 2
	if it.has("affixes"): f |= 4
	if it.has("magic"): f |= 8
	if it.has("tier"): f |= 16
	if it.has("spark"): f |= 32
	if bool(it.get("bonded", false)): f |= 64
	b.put_u8(f)
	if f & 1: _str(b, String(it["material"]))
	if f & 2: _str(b, String(it["quality"]))
	if f & 4:
		var a: Array = it["affixes"]
		b.put_u8(mini(a.size(), 255))
		for i in mini(a.size(), 255):
			_str(b, String(a[i]))
	if f & 8: _str(b, String(it["magic"]))
	if f & 16: b.put_u8(clampi(int(it["tier"]), 0, 255))
	if f & 32:
		_str(b, String(it["spark"].get("id", "")))
		b.put_u8(clampi(int(it["spark"].get("rank", 0)), 0, 255))

## A record, or null if malformed.
static func get_rec(b: StreamPeerBuffer) -> Variant:
	var base: Variant = _rstr(b)
	if base == null or not _need(b, 3):
		return null
	var it := {"base": base, "count": b.get_u16()}
	var f := b.get_u8()
	if f & 1:
		var m: Variant = _rstr(b)
		if m == null: return null
		it["material"] = m
	if f & 2:
		var q: Variant = _rstr(b)
		if q == null: return null
		it["quality"] = q
	if f & 4:
		if not _need(b, 1): return null
		var n := b.get_u8()
		var a: Array = []
		for i in n:
			var s: Variant = _rstr(b)
			if s == null: return null
			a.append(s)
		it["affixes"] = a
	if f & 8:
		var mg: Variant = _rstr(b)
		if mg == null: return null
		it["magic"] = mg
	if f & 16:
		if not _need(b, 1): return null
		it["tier"] = b.get_u8()
	if f & 32:
		var sid: Variant = _rstr(b)
		if sid == null or not _need(b, 1): return null
		it["spark"] = {"id": sid, "rank": b.get_u8()}
	if f & 64:
		it["bonded"] = true
	return it

# --- host -> client -----------------------------------------------------------------------

## entries: [[index, rec or {}]]
static func slots(coin: int, selected: int, entries: Array) -> PackedByteArray:
	var b := _w()
	b.put_u32(clampi(coin, 0, 0xffffffff))
	b.put_u8(selected)
	b.put_u8(entries.size())
	for e: Array in entries:
		b.put_u8(int(e[0]))
		var rec: Dictionary = e[1]
		b.put_u8(0 if rec.is_empty() else 1)
		if not rec.is_empty():
			put_rec(b, rec)
	return b.data_array

## {coin, selected, entries: [[index, rec]]}
static func read_slots(data: PackedByteArray) -> Dictionary:
	var b := _r(data)
	if not _need(b, 6):
		return {}
	var out := {"coin": b.get_u32(), "selected": b.get_u8(), "entries": []}
	var n := b.get_u8()
	for i in n:
		if not _need(b, 2):
			return {}
		var idx := b.get_u8()
		var has := b.get_u8()
		var rec: Variant = {}
		if has:
			rec = get_rec(b)
			if rec == null:
				return {}
		out["entries"].append([idx, rec])
	return out

## speeds: {walk, climb, swim, fly}; stars: [{id, rank, at: [x, y]}]
static func stars(speeds: Dictionary, size_name: String, n_slots: int, kindled: Array) -> PackedByteArray:
	var b := _w()
	for k: String in ["walk", "climb", "swim", "fly"]:
		b.put_u16(clampi(int(speeds.get(k, 0)), 0, 0xffff))
	_str(b, size_name)
	b.put_u8(clampi(n_slots, 0, 255))
	b.put_u8(mini(kindled.size(), 255))
	for k: Dictionary in kindled:
		_str(b, String(k["id"]))
		b.put_u8(int(k["rank"]))
		var at: Array = k.get("at", [0, 0])
		b.put_u8(int(at[0]))
		b.put_u8(int(at[1]))
	return b.data_array

## {speeds, size, slots, kindled}
static func read_stars(data: PackedByteArray) -> Dictionary:
	var b := _r(data)
	if not _need(b, 8):
		return {}
	var sp := {"walk": b.get_u16(), "climb": b.get_u16(), "swim": b.get_u16(), "fly": b.get_u16()}
	var size: Variant = _rstr(b)
	if size == null or not _need(b, 2):
		return {}
	var out := {"speeds": sp, "size": size, "slots": b.get_u8(), "kindled": []}
	var n := b.get_u8()
	for i in n:
		var id: Variant = _rstr(b)
		if id == null or not _need(b, 3):
			return {}
		out["kindled"].append({"id": id, "rank": b.get_u8(), "at": [b.get_u8(), b.get_u8()]})
	return out

## drops: [{id, pos, vel, item}]
static func drops(list: Array) -> PackedByteArray:
	var b := _w()
	b.put_u16(list.size())
	for d: Dictionary in list:
		b.put_u32(int(d["id"]))
		b.put_float(d["pos"].x)
		b.put_float(d["pos"].y)
		b.put_float(d["vel"].x)
		b.put_float(d["vel"].y)
		put_rec(b, d["item"])
	return b.data_array

static func read_drops(data: PackedByteArray) -> Array:
	var b := _r(data)
	if not _need(b, 2):
		return []
	var n := b.get_u16()
	var out: Array = []
	for i in n:
		if not _need(b, 20):
			return []
		var d := {"id": b.get_u32(), "pos": Vector2(b.get_float(), b.get_float()), "vel": Vector2(b.get_float(), b.get_float())}
		var rec: Variant = get_rec(b)
		if rec == null:
			return []
		d["item"] = rec
		out.append(d)
	return out

## gone: [[id, by]]
static func gone(list: Array) -> PackedByteArray:
	var b := _w()
	b.put_u16(list.size())
	for g: Array in list:
		b.put_u32(int(g[0]))
		b.put_u32(int(g[1]))
	return b.data_array

static func read_gone(data: PackedByteArray) -> Array:
	var b := _r(data)
	if not _need(b, 2):
		return []
	var n := b.get_u16()
	if not _need(b, n * 8):
		return []
	var out: Array = []
	for i in n:
		out.append([b.get_u32(), b.get_u32()])
	return out

## moved: [{id, pos, vel}]
static func moved(list: Array) -> PackedByteArray:
	var b := _w()
	b.put_u16(list.size())
	for d: Dictionary in list:
		b.put_u32(int(d["id"]))
		b.put_float(d["pos"].x)
		b.put_float(d["pos"].y)
		b.put_float(d["vel"].x)
		b.put_float(d["vel"].y)
	return b.data_array

static func read_moved(data: PackedByteArray) -> Array:
	var b := _r(data)
	if not _need(b, 2):
		return []
	var n := b.get_u16()
	if not _need(b, n * 20):
		return []
	var out: Array = []
	for i in n:
		out.append({"id": b.get_u32(), "pos": Vector2(b.get_float(), b.get_float()), "vel": Vector2(b.get_float(), b.get_float())})
	return out

static func note(op: int, ok: bool, word: String) -> PackedByteArray:
	var b := _w()
	b.put_u8(op)
	b.put_u8(1 if ok else 0)
	_str(b, word)
	return b.data_array

static func read_note(data: PackedByteArray) -> Dictionary:
	var b := _r(data)
	if not _need(b, 2):
		return {}
	var op := b.get_u8()
	var ok := b.get_u8() != 0
	var w: Variant = _rstr(b)
	return {} if w == null else {"op": op, "ok": ok, "word": w}

static func bonding(index: int, ms_left: int) -> PackedByteArray:
	return bytes([index, ms_left & 0xff, (ms_left >> 8) & 0xff])

static func read_bonding(data: PackedByteArray) -> Dictionary:
	if data.size() < 3:
		return {}
	return {"index": data[0], "ms": data.decode_u16(1)}

# --- client -> host -----------------------------------------------------------------------

static func bytes(vals: Array) -> PackedByteArray:
	var out := PackedByteArray()
	for v: int in vals:
		out.append(v & 0xff)
	return out

static func drop_req(index: int, n: int) -> PackedByteArray:
	var b := _w()
	b.put_u8(index)
	b.put_u16(clampi(n, 0, 0xffff))
	return b.data_array

static func read_drop_req(data: PackedByteArray) -> Dictionary:
	if data.size() < 3:
		return {}
	return {"index": data[0], "n": data.decode_u16(1)}

static func craft(recipe: String, times: int) -> PackedByteArray:
	var b := _w()
	_str(b, recipe)
	b.put_u8(clampi(times, 1, 255))
	return b.data_array

static func read_craft(data: PackedByteArray) -> Dictionary:
	var b := _r(data)
	var r: Variant = _rstr(b)
	if r == null or not _need(b, 1):
		return {}
	return {"recipe": r, "times": b.get_u8()}
