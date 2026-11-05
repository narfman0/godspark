## Wire format of the rules system (HostSystem.RULES): SYS message kinds and their byte
## layouts, both directions. Little-endian; str = u16 byte length + UTF-8 (cut at STR_MAX
## bytes). Decoders never trust their input: a short or malformed payload decodes to {}.
##
## Host -> client
##   CHAR    the owner's full sheet (on join and whenever it changes), see encode_sheet
##   CHOICE  one pending choice with its options, sent before the CHAR that lists its key:
##           str key, str kind, str label, u8 count, u16 n, n x (str id, str name,
##           u8 level (255: none), u8 modelled)
##   LEVEL   u8 level, u8 reward (LevelTrack.Reward), one per level gained
##   DOWNED  u32 entity id, u8 state (Down), u8 successes, u8 failures: to the owner and the
##           players near it, on every change; and to a joining player for each downed player
##   REST    u8 event (RestEv), u16 healed, u8 dice spent, str reason, u8 n, n x str (players
##           still up, BED_WAIT)
##   GAIN    u32 xp, str source (a monster's name, "debug")
##   NOTE    str text (a refusal or a notice for the owner, e.g. "answer refused: ...")
## Client -> host
##   ANSWER     str key, u8 n, n x str      answer a pending choice
##   KNACK      str knack id                pick one of an open Knack offer
##   REST_SHORT, REST_LONG, STAND, RESPAWN  no payload
##   REVIVE     u32 target entity id (0: let go)
##   DEBUG      u8 op (Debug), s32 n        only when the host runs with `cheats`
class_name RulesCodec
extends RefCounted

enum K {
	CHAR = 1, CHOICE = 2, LEVEL = 3, DOWNED = 4, REST = 5, GAIN = 6, NOTE = 7,
	ANSWER = 64, KNACK = 65, REST_SHORT = 66, REST_LONG = 67, STAND = 68, REVIVE = 69,
	RESPAWN = 70, DEBUG = 71,
}
## Downed state of a player.
enum Down { UP, DOWNED, STABLE, DEAD }
## REST events.
enum RestEv { SHORT_START, SHORT_DONE, SHORT_STOP, BED_WAIT, BED_DONE, BED_STOP }
## Resting state in the sheet.
enum Resting { NONE, SHORT, BED }
## DEBUG ops (cheats only).
enum Debug { XP, LEVEL, AUTO, HURT, DIE, HEAL }

const STR_MAX := 1024
const VERSION := 1

# --- primitives ---------------------------------------------------------------------

class Writer extends RefCounted:
	var b := PackedByteArray()

	func u8(v: int) -> Writer:
		b.append(clampi(v, 0, 255))
		return self

	func u16(v: int) -> Writer:
		var i := b.size()
		b.resize(i + 2)
		b.encode_u16(i, clampi(v, 0, 0xffff))
		return self

	func u32(v: int) -> Writer:
		var i := b.size()
		b.resize(i + 4)
		b.encode_u32(i, clampi(v, 0, 0xffffffff))
		return self

	func s32(v: int) -> Writer:
		var i := b.size()
		b.resize(i + 4)
		b.encode_s32(i, clampi(v, -0x80000000, 0x7fffffff))
		return self

	func s(text: String) -> Writer:
		var u := text.to_utf8_buffer()
		if u.size() > STR_MAX:
			u = u.slice(0, STR_MAX)
		u16(u.size())
		b.append_array(u)
		return self

class Reader extends RefCounted:
	var b: PackedByteArray
	var i := 0
	var ok := true

	func _init(data: PackedByteArray) -> void:
		b = data

	func _need(n: int) -> bool:
		if not ok or i + n > b.size():
			ok = false
			return false
		return true

	func u8() -> int:
		if not _need(1):
			return 0
		i += 1
		return b[i - 1]

	func u16() -> int:
		if not _need(2):
			return 0
		i += 2
		return b.decode_u16(i - 2)

	func u32() -> int:
		if not _need(4):
			return 0
		i += 4
		return b.decode_u32(i - 4)

	func s32() -> int:
		if not _need(4):
			return 0
		i += 4
		return b.decode_s32(i - 4)

	func s() -> String:
		var n := u16()
		if n > STR_MAX or not _need(n):
			ok = false
			return ""
		i += n
		return b.slice(i - n, i).get_string_from_utf8()

	## True when everything was read and nothing is left over.
	func done() -> bool:
		return ok and i == b.size()

# --- the sheet ----------------------------------------------------------------------

## CHAR. sheet: {level, xp, xp_level, xp_next, class, subclass, species, background,
## class_level, scores: [6], hp, max_hp, hit_dice, hit_dice_max, slots: [[left, max] x 9],
## uses: {name: [left, max]}, spark_slots, knacks: [id], bonds: {key: strength}, boon,
## pending: [{key, kind, label, count}], state (Down), successes, failures, resting (Resting),
## rest_ready: bool, bed: Vector2i or null}
## Layout: u8 VERSION, u8 level, u32 xp, u32 xp_level, u32 xp_next, str class, str subclass,
## str species, str background, u8 class_level, 6 x u8 scores, u16 hp, u16 max_hp, u8 hit_dice,
## u8 hit_dice_max, 9 x (u8 left, u8 max), u8 n uses x (str, u8, u8), u8 spark_slots,
## u8 n knacks x str, u8 n bonds x (str, u8), str boon, u8 n pending x (str key, str kind,
## str label, u8 count), u8 state, u8 successes, u8 failures, u8 resting, u8 rest_ready,
## u8 has_bed, s32 bed x, s32 bed y.
static func encode_sheet(s: Dictionary) -> PackedByteArray:
	var w := Writer.new()
	w.u8(VERSION).u8(s["level"]).u32(s["xp"]).u32(s["xp_level"]).u32(s["xp_next"])
	w.s(s["class"]).s(s["subclass"]).s(s["species"]).s(s["background"]).u8(s["class_level"])
	for i in 6:
		w.u8(int(s["scores"][i]))
	w.u16(s["hp"]).u16(s["max_hp"]).u8(s["hit_dice"]).u8(s["hit_dice_max"])
	var slots: Array = s["slots"]
	for i in 9:
		var p: Array = slots[i] if i < slots.size() else [0, 0]
		w.u8(int(p[0])).u8(int(p[1]))
	var uses: Dictionary = s["uses"]
	w.u8(uses.size())
	for k: String in uses:
		w.s(k).u8(int(uses[k][0])).u8(int(uses[k][1]))
	w.u8(s["spark_slots"])
	var knacks: Array = s["knacks"]
	w.u8(knacks.size())
	for k: String in knacks:
		w.s(k)
	var bonds: Dictionary = s["bonds"]
	w.u8(bonds.size())
	for k: String in bonds:
		w.s(k).u8(int(bonds[k]))
	w.s(s["boon"])
	var pending: Array = s["pending"]
	w.u8(pending.size())
	for p: Dictionary in pending.slice(0, 255):
		w.s(p["key"]).s(p["kind"]).s(p["label"]).u8(p["count"])
	w.u8(s["state"]).u8(s["successes"]).u8(s["failures"]).u8(s["resting"]).u8(1 if s["rest_ready"] else 0)
	var bed: Variant = s.get("bed")
	w.u8(1 if bed is Vector2i else 0)
	w.s32(bed.x if bed is Vector2i else 0).s32(bed.y if bed is Vector2i else 0)
	return w.b

static func decode_sheet(data: PackedByteArray) -> Dictionary:
	var r := Reader.new(data)
	if r.u8() != VERSION:
		return {}
	var s := {"level": r.u8(), "xp": r.u32(), "xp_level": r.u32(), "xp_next": r.u32(),
		"class": r.s(), "subclass": r.s(), "species": r.s(), "background": r.s(),
		"class_level": r.u8()}
	var scores := []
	for i in 6:
		scores.append(r.u8())
	s["scores"] = scores
	s["hp"] = r.u16()
	s["max_hp"] = r.u16()
	s["hit_dice"] = r.u8()
	s["hit_dice_max"] = r.u8()
	var slots := []
	for i in 9:
		slots.append([r.u8(), r.u8()])
	s["slots"] = slots
	var uses := {}
	for i in r.u8():
		var k := r.s()
		uses[k] = [r.u8(), r.u8()]
	s["uses"] = uses
	s["spark_slots"] = r.u8()
	var knacks := []
	for i in r.u8():
		knacks.append(r.s())
	s["knacks"] = knacks
	var bonds := {}
	for i in r.u8():
		var k := r.s()
		bonds[k] = r.u8()
	s["bonds"] = bonds
	s["boon"] = r.s()
	var pending := []
	for i in r.u8():
		pending.append({"key": r.s(), "kind": r.s(), "label": r.s(), "count": r.u8()})
	s["pending"] = pending
	s["state"] = r.u8()
	s["successes"] = r.u8()
	s["failures"] = r.u8()
	s["resting"] = r.u8()
	s["rest_ready"] = r.u8() != 0
	var has_bed := r.u8() != 0
	var bed := Vector2i(r.s32(), r.s32())
	s["bed"] = bed if has_bed else null
	return s if r.done() else {}

# --- other host messages ------------------------------------------------------------

## CHOICE. c: {key, kind, label, count, options: [{id, name, level?, modelled?}]}
static func encode_choice(c: Dictionary) -> PackedByteArray:
	var w := Writer.new()
	w.s(c["key"]).s(c["kind"]).s(c["label"]).u8(c["count"])
	var opts: Array = c["options"]
	w.u16(opts.size())
	for o: Dictionary in opts.slice(0, 0xffff):
		w.s(String(o["id"])).s(String(o.get("name", o["id"])))
		w.u8(int(o["level"]) if o.has("level") else 255).u8(1 if o.get("modelled", true) else 0)
	return w.b

static func decode_choice(data: PackedByteArray) -> Dictionary:
	var r := Reader.new(data)
	var c := {"key": r.s(), "kind": r.s(), "label": r.s(), "count": r.u8()}
	var opts := []
	for i in r.u16():
		var o := {"id": r.s(), "name": r.s()}
		var lvl := r.u8()
		if lvl != 255:
			o["level"] = lvl
		o["modelled"] = r.u8() != 0
		opts.append(o)
		if not r.ok:
			break
	c["options"] = opts
	return c if r.done() else {}

static func encode_level(level: int, reward: int) -> PackedByteArray:
	return Writer.new().u8(level).u8(reward).b

static func decode_level(data: PackedByteArray) -> Dictionary:
	var r := Reader.new(data)
	var d := {"level": r.u8(), "reward": r.u8()}
	return d if r.done() else {}

static func encode_downed(id: int, state: int, successes: int, failures: int) -> PackedByteArray:
	return Writer.new().u32(id).u8(state).u8(successes).u8(failures).b

static func decode_downed(data: PackedByteArray) -> Dictionary:
	var r := Reader.new(data)
	var d := {"id": r.u32(), "state": r.u8(), "successes": r.u8(), "failures": r.u8()}
	return d if r.done() else {}

static func encode_rest(event: int, healed := 0, dice := 0, reason := "", names: Array = []) -> PackedByteArray:
	var w := Writer.new().u8(event).u16(healed).u8(dice).s(reason)
	w.u8(mini(names.size(), 255))
	for n: String in names.slice(0, 255):
		w.s(n)
	return w.b

static func decode_rest(data: PackedByteArray) -> Dictionary:
	var r := Reader.new(data)
	var d := {"event": r.u8(), "healed": r.u16(), "dice": r.u8(), "reason": r.s()}
	var names := []
	for i in r.u8():
		names.append(r.s())
	d["names"] = names
	return d if r.done() else {}

static func encode_gain(xp: int, source: String) -> PackedByteArray:
	return Writer.new().u32(xp).s(source).b

static func decode_gain(data: PackedByteArray) -> Dictionary:
	var r := Reader.new(data)
	var d := {"xp": r.u32(), "source": r.s()}
	return d if r.done() else {}

static func encode_str(s: String) -> PackedByteArray:
	return Writer.new().s(s).b

## NOTE and KNACK: one string ("" and false-y on a bad payload: check ok).
static func decode_str(data: PackedByteArray) -> Dictionary:
	var r := Reader.new(data)
	var s := r.s()
	return {"text": s} if r.done() else {}

# --- client messages ----------------------------------------------------------------

static func encode_answer(key: String, answer: Array) -> PackedByteArray:
	var w := Writer.new().s(key)
	w.u8(mini(answer.size(), 255))
	for a: Variant in answer.slice(0, 255):
		w.s(String(a))
	return w.b

static func decode_answer(data: PackedByteArray) -> Dictionary:
	var r := Reader.new(data)
	var d := {"key": r.s()}
	var a := []
	for i in r.u8():
		a.append(r.s())
	d["answer"] = a
	return d if r.done() else {}

static func encode_id(id: int) -> PackedByteArray:
	return Writer.new().u32(id).b

static func decode_id(data: PackedByteArray) -> int:
	var r := Reader.new(data)
	var id := r.u32()
	return id if r.done() else -1

static func encode_debug(op: int, n: int) -> PackedByteArray:
	return Writer.new().u8(op).s32(n).b

static func decode_debug(data: PackedByteArray) -> Dictionary:
	var r := Reader.new(data)
	var d := {"op": r.u8(), "n": r.s32()}
	return d if r.done() else {}
