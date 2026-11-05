## SYS layouts of the monsters system (HostSystem.MONSTERS), host -> client only.
##   INFO (kind 1): u8 n, n x (u32 id, u8 rank, str slug, str people, u16 scale x 100,
##                  u8 flags (1 neutral, 2 lair, 4 leader), u8 k, k x str affix id)
##   GONE (kind 2): u8 n, n x u32 id
## str = u8 length + UTF-8 bytes (at most 255).
class_name MonstersCodec
extends RefCounted

enum Msg { INFO = 1, GONE = 2 }
const RANKS := ["minion", "standard", "elite", "champion", "boss"]
const F_NEUTRAL := 1
const F_LAIR := 2
const F_LEADER := 4

## infos: [{id, rank, slug, people, scale, flags, affixes: [id]}]
static func write_info(infos: Array) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u8(mini(infos.size(), 255))
	for i in mini(infos.size(), 255):
		var d: Dictionary = infos[i]
		b.put_u32(int(d["id"]))
		b.put_u8(maxi(0, RANKS.find(String(d.get("rank", "standard")))))
		_s(b, String(d.get("slug", "")))
		_s(b, String(d.get("people", "")))
		b.put_u16(clampi(roundi(float(d.get("scale", 1.0)) * 100.0), 0, 65535))
		b.put_u8(int(d.get("flags", 0)))
		var af: Array = d.get("affixes", [])
		b.put_u8(mini(af.size(), 255))
		for a in af:
			_s(b, String(a))
	return b.data_array

static func read_info(data: PackedByteArray) -> Array:
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var out: Array = []
	if b.get_size() < 1:
		return out
	var n := b.get_u8()
	for i in n:
		if b.get_available_bytes() < 4 + 1:
			return out
		var d := {"id": b.get_u32(), "rank": RANKS[mini(b.get_u8(), RANKS.size() - 1)]}
		d["slug"] = _rs(b)
		d["people"] = _rs(b)
		if b.get_available_bytes() < 4:
			return out
		d["scale"] = b.get_u16() / 100.0
		d["flags"] = b.get_u8()
		var k := b.get_u8()
		var af: Array = []
		for j in k:
			af.append(_rs(b))
		d["affixes"] = af
		out.append(d)
	return out

static func write_gone(ids: Array) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u8(mini(ids.size(), 255))
	for i in mini(ids.size(), 255):
		b.put_u32(int(ids[i]))
	return b.data_array

static func read_gone(data: PackedByteArray) -> Array:
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var out: Array = []
	if b.get_size() < 1:
		return out
	var n := b.get_u8()
	for i in n:
		if b.get_available_bytes() < 4:
			break
		out.append(b.get_u32())
	return out

static func _s(b: StreamPeerBuffer, s: String) -> void:
	var u := s.to_utf8_buffer()
	if u.size() > 255:
		u = u.slice(0, 255)
	b.put_u8(u.size())
	b.put_data(u)

static func _rs(b: StreamPeerBuffer) -> String:
	if b.get_available_bytes() < 1:
		return ""
	var n := b.get_u8()
	if b.get_available_bytes() < n:
		return ""
	var r: Array = b.get_data(n)
	return (r[1] as PackedByteArray).get_string_from_utf8()
