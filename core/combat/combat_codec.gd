## Byte layouts of the combat system's SYS messages (HostSystem.COMBAT). Little-endian;
## `str` is u8 length + UTF-8 (at most 255 bytes). Decoders return {} for a malformed or
## truncated payload, or trailing bytes.
##
## Client -> host
##   ATTACK  f32 aim.x, f32 aim.y, f32 clock, u8 flags (bit0 throw)                    13 B
##   CAST    str slug, u8 slot level, f32 aim.x, f32 aim.y, f32 clock                   14 + slug
##   CANCEL  (empty)
##   (`clock` is the client's estimate of host time, ClientWorld.clock, or -1: the host
##   reads the round trip from it and leads the attacker's body by its velocity times the
##   one-way delay, so a running player swings from where it is, not where it was)
## Host -> client
##   EVENTS  u32 tick, u8 n, n x event                    (send_sys_near, one per chunk per tick)
##     event: u8 kind, u32 src, u32 dst, then by kind:
##       SWING      u8 mode, u8 swings, u16 windup ms, u16 total ms, f32 aim.x, f32 aim.y, str what
##       HIT, CRIT, MISS   u8 d20, s16 total, u8 ac
##       SAVE       u8 dc, u8 saved, str what
##       DAMAGE     u16 amount, u8 dtype (SRD.DamageType), u16 hp after
##       HEAL       u16 amount, u16 hp after
##       CONDITION  u8 condition (SRD.Condition), u8 on
##       DOWNED, DEATH, CANCEL   (nothing)
##       XP         u32 amount        (reserved for the rules track)
##       EFFECT     u8 on, str what   (an ActiveEffects id: "bless-bonus_die", "mastery-sap")
##       PROJECTILE u32 pid, u8 pkind, f32 x, f32 y, f32 vx, f32 vy, f32 gravity
##       IMPACT     u32 pid, f32 x, f32 y
##       PUSH       f32 dx, f32 dy    (the owner of dst sweeps its own body by this much)
##   STATUS  u16 action ms, u16 bonus ms, u16 reaction ms, u8 move mult (/255), u8 flags
##           (bit0 no jump, bit1 no actions, bit2 downed, bit3 concentrating), u32 fear src,
##           9 x (u8 slots left, u8 slots max), str concentration slug           (to the owner)
##   SPELLS  u8 n, n x (str slug, str name, u8 level, u8 flags)                    (to the owner)
##           flags: bit0 attack or save (damage), bit1 bonus action, bit2 reaction,
##           bit3 concentration, bit4 healing, bit5 area, bit6 supported
class_name CombatCodec
extends RefCounted

enum Msg { ATTACK = 1, CAST = 2, CANCEL = 3, EVENTS = 16, STATUS = 17, SPELLS = 18 }
enum Ev { SWING = 1, HIT, MISS, CRIT, SAVE, DAMAGE, HEAL, CONDITION, DOWNED, DEATH, XP, EFFECT,
		PROJECTILE, IMPACT, PUSH, CANCEL }
## SWING modes.
enum Mode { MELEE, RANGED, THROW, CAST, AREA, SAVE_ACTION }
## Projectile kinds (PROJECTILE pkind).
const PKINDS: PackedStringArray = ["arrow", "bolt", "thrown", "spell", "dart"]

const SPELL_DAMAGE := 1
const SPELL_BONUS := 2
const SPELL_REACTION := 4
const SPELL_CONCENTRATION := 8
const SPELL_HEAL := 16
const SPELL_AREA := 32
const SPELL_SUPPORTED := 64

const ST_NO_JUMP := 1
const ST_NO_ACTIONS := 2
const ST_DOWNED := 4
const ST_CONCENTRATING := 8

# --- writing ----------------------------------------------------------------------------

class W:
	var b := PackedByteArray()
	func u8(v: int) -> W:
		b.append(clampi(v, 0, 255))
		return self
	func u16(v: int) -> W:
		var i := b.size()
		b.resize(i + 2)
		b.encode_u16(i, clampi(v, 0, 0xffff))
		return self
	func s16(v: int) -> W:
		var i := b.size()
		b.resize(i + 2)
		b.encode_s16(i, clampi(v, -32768, 32767))
		return self
	func u32(v: int) -> W:
		var i := b.size()
		b.resize(i + 4)
		b.encode_u32(i, v & 0xffffffff)
		return self
	func f32(v: float) -> W:
		var i := b.size()
		b.resize(i + 4)
		b.encode_float(i, v)
		return self
	func text(s: String) -> W:
		var u := s.to_utf8_buffer()
		if u.size() > 255:
			u = u.slice(0, 255)
		b.append(u.size())
		b.append_array(u)
		return self

class R:
	var b: PackedByteArray
	var i := 0
	var ok := true
	func _init(bytes: PackedByteArray) -> void:
		b = bytes
	func _need(n: int) -> bool:
		if i + n > b.size():
			ok = false
		return ok
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
	func s16() -> int:
		if not _need(2):
			return 0
		i += 2
		return b.decode_s16(i - 2)
	func u32() -> int:
		if not _need(4):
			return 0
		i += 4
		return b.decode_u32(i - 4)
	func f32() -> float:
		if not _need(4):
			return 0.0
		i += 4
		return b.decode_float(i - 4)
	func text() -> String:
		var n := u8()
		if not _need(n):
			return ""
		i += n
		return b.slice(i - n, i).get_string_from_utf8()
	func done() -> bool:
		return ok and i == b.size()

# --- client -> host -----------------------------------------------------------------------

static func attack(aim: Vector2, clock: float, throw := false) -> PackedByteArray:
	return W.new().f32(aim.x).f32(aim.y).f32(clock).u8(1 if throw else 0).b

static func read_attack(data: PackedByteArray) -> Dictionary:
	var r := R.new(data)
	var out := {"aim": Vector2(r.f32(), r.f32()), "clock": r.f32(), "throw": r.u8() & 1 != 0}
	return out if r.done() and _finite(out["aim"]) and is_finite(out["clock"]) else {}

static func cast(slug: String, level: int, aim: Vector2, clock: float) -> PackedByteArray:
	return W.new().text(slug).u8(level).f32(aim.x).f32(aim.y).f32(clock).b

static func read_cast(data: PackedByteArray) -> Dictionary:
	var r := R.new(data)
	var out := {"slug": r.text(), "level": r.u8(), "aim": Vector2(r.f32(), r.f32()), "clock": r.f32()}
	return out if r.done() and _finite(out["aim"]) and is_finite(out["clock"]) else {}

static func _finite(v: Vector2) -> bool:
	return is_finite(v.x) and is_finite(v.y)

# --- events -------------------------------------------------------------------------------

## One EVENTS payload. Each event is a Dictionary with kind, src, dst and its kind's fields
## (see the header): mode, swings, windup, total (seconds), aim, what, d20, total_roll, ac,
## dc, saved, amount, dtype, hp, cond, on, pid, pkind, pos, vel, gravity, push.
static func events(tick: int, evs: Array) -> PackedByteArray:
	var w := W.new().u32(tick).u8(evs.size())
	for ev: Dictionary in evs:
		_event(w, ev)
	return w.b

static func _event(w: W, ev: Dictionary) -> void:
	var k := int(ev["kind"])
	w.u8(k).u32(int(ev.get("src", 0))).u32(int(ev.get("dst", 0)))
	match k:
		Ev.SWING:
			var aim: Vector2 = ev.get("aim", Vector2.ZERO)
			w.u8(int(ev.get("mode", 0))).u8(int(ev.get("swings", 1))).u16(roundi(float(ev.get("windup", 0.0)) * 1000.0)) \
				.u16(roundi(float(ev.get("total", 0.0)) * 1000.0)).f32(aim.x).f32(aim.y).text(String(ev.get("what", "")))
		Ev.HIT, Ev.MISS, Ev.CRIT:
			w.u8(int(ev.get("d20", 0))).s16(int(ev.get("total_roll", 0))).u8(int(ev.get("ac", 0)))
		Ev.SAVE:
			w.u8(int(ev.get("dc", 0))).u8(1 if ev.get("saved", false) else 0).text(String(ev.get("what", "")))
		Ev.DAMAGE:
			w.u16(int(ev.get("amount", 0))).u8(int(ev.get("dtype", 0))).u16(int(ev.get("hp", 0)))
		Ev.HEAL:
			w.u16(int(ev.get("amount", 0))).u16(int(ev.get("hp", 0)))
		Ev.CONDITION:
			w.u8(int(ev.get("cond", 0))).u8(1 if ev.get("on", false) else 0)
		Ev.XP:
			w.u32(int(ev.get("amount", 0)))
		Ev.EFFECT:
			w.u8(1 if ev.get("on", false) else 0).text(String(ev.get("what", "")))
		Ev.PROJECTILE:
			var p: Vector2 = ev.get("pos", Vector2.ZERO)
			var v: Vector2 = ev.get("vel", Vector2.ZERO)
			w.u32(int(ev.get("pid", 0))).u8(int(ev.get("pkind", 0))).f32(p.x).f32(p.y).f32(v.x).f32(v.y) \
				.f32(float(ev.get("gravity", 0.0)))
		Ev.IMPACT:
			var p2: Vector2 = ev.get("pos", Vector2.ZERO)
			w.u32(int(ev.get("pid", 0))).f32(p2.x).f32(p2.y)
		Ev.PUSH:
			var d: Vector2 = ev.get("push", Vector2.ZERO)
			w.f32(d.x).f32(d.y)

## {tick, events: [Dictionary]} or {} when malformed.
static func read_events(data: PackedByteArray) -> Dictionary:
	var r := R.new(data)
	var tick := r.u32()
	var n := r.u8()
	var out: Array = []
	for i in n:
		var ev := {"kind": r.u8(), "src": r.u32(), "dst": r.u32()}
		match int(ev["kind"]):
			Ev.SWING:
				ev["mode"] = r.u8()
				ev["swings"] = r.u8()
				ev["windup"] = r.u16() / 1000.0
				ev["total"] = r.u16() / 1000.0
				ev["aim"] = Vector2(r.f32(), r.f32())
				ev["what"] = r.text()
			Ev.HIT, Ev.MISS, Ev.CRIT:
				ev["d20"] = r.u8()
				ev["total_roll"] = r.s16()
				ev["ac"] = r.u8()
			Ev.SAVE:
				ev["dc"] = r.u8()
				ev["saved"] = r.u8() != 0
				ev["what"] = r.text()
			Ev.DAMAGE:
				ev["amount"] = r.u16()
				ev["dtype"] = r.u8()
				ev["hp"] = r.u16()
			Ev.HEAL:
				ev["amount"] = r.u16()
				ev["hp"] = r.u16()
			Ev.CONDITION:
				ev["cond"] = r.u8()
				ev["on"] = r.u8() != 0
			Ev.XP:
				ev["amount"] = r.u32()
			Ev.EFFECT:
				ev["on"] = r.u8() != 0
				ev["what"] = r.text()
			Ev.PROJECTILE:
				ev["pid"] = r.u32()
				ev["pkind"] = r.u8()
				ev["pos"] = Vector2(r.f32(), r.f32())
				ev["vel"] = Vector2(r.f32(), r.f32())
				ev["gravity"] = r.f32()
			Ev.IMPACT:
				ev["pid"] = r.u32()
				ev["pos"] = Vector2(r.f32(), r.f32())
			Ev.PUSH:
				ev["push"] = Vector2(r.f32(), r.f32())
			Ev.DOWNED, Ev.DEATH, Ev.CANCEL:
				pass
			_:
				return {}
		ev["t"] = tick
		out.append(ev)
	return {"tick": tick, "events": out} if r.done() else {}

# --- status and spells ----------------------------------------------------------------------

## st: {action, bonus, reaction (seconds left), move_mult (0..1), flags, fear_src,
## slots: [[left, max] x 9], concentration}
static func status(st: Dictionary) -> PackedByteArray:
	var w := W.new().u16(roundi(float(st.get("action", 0.0)) * 1000.0)).u16(roundi(float(st.get("bonus", 0.0)) * 1000.0)) \
		.u16(roundi(float(st.get("reaction", 0.0)) * 1000.0)).u8(roundi(clampf(float(st.get("move_mult", 1.0)), 0.0, 1.0) * 255.0)) \
		.u8(int(st.get("flags", 0))).u32(int(st.get("fear_src", 0)))
	var slots: Array = st.get("slots", [])
	for i in 9:
		var s: Array = slots[i] if i < slots.size() else [0, 0]
		w.u8(int(s[0])).u8(int(s[1]))
	return w.text(String(st.get("concentration", ""))).b

static func read_status(data: PackedByteArray) -> Dictionary:
	var r := R.new(data)
	var st := {"action": r.u16() / 1000.0, "bonus": r.u16() / 1000.0, "reaction": r.u16() / 1000.0,
		"move_mult": r.u8() / 255.0, "flags": r.u8(), "fear_src": r.u32()}
	var slots := []
	for i in 9:
		slots.append([r.u8(), r.u8()])
	st["slots"] = slots
	st["concentration"] = r.text()
	return st if r.done() else {}

## spells: [{slug, name, level, flags}]
static func spells(list: Array) -> PackedByteArray:
	var w := W.new().u8(mini(list.size(), 255))
	for i in mini(list.size(), 255):
		var s: Dictionary = list[i]
		w.text(String(s["slug"])).text(String(s.get("name", ""))).u8(int(s.get("level", 0))).u8(int(s.get("flags", 0)))
	return w.b

static func read_spells(data: PackedByteArray) -> Array:
	var r := R.new(data)
	var n := r.u8()
	var out := []
	for i in n:
		out.append({"slug": r.text(), "name": r.text(), "level": r.u8(), "flags": r.u8()})
	return out if r.done() else []

## One readable line for an event (logs, tests).
static func describe(ev: Dictionary) -> String:
	var k := int(ev.get("kind", 0))
	var head := "%s %d>%d" % [String(Ev.find_key(k)) if Ev.find_key(k) != null else "?", int(ev.get("src", 0)), int(ev.get("dst", 0))]
	match k:
		Ev.SWING:
			return "%s %s x%d windup %.2f total %.2f %s" % [head, String(Mode.find_key(int(ev.get("mode", 0)))).to_lower(),
				int(ev.get("swings", 1)), float(ev.get("windup", 0.0)), float(ev.get("total", 0.0)), ev.get("what", "")]
		Ev.HIT, Ev.MISS, Ev.CRIT:
			return "%s d20=%d total=%d ac=%d" % [head, int(ev.get("d20", 0)), int(ev.get("total_roll", 0)), int(ev.get("ac", 0))]
		Ev.SAVE:
			return "%s %s dc=%d %s" % [head, ev.get("what", ""), int(ev.get("dc", 0)), "saved" if ev.get("saved", false) else "failed"]
		Ev.DAMAGE:
			return "%s %d %s hp=%d" % [head, int(ev.get("amount", 0)), String(SRD.DamageType.find_key(int(ev.get("dtype", 0)))).to_lower(), int(ev.get("hp", 0))]
		Ev.HEAL:
			return "%s +%d hp=%d" % [head, int(ev.get("amount", 0)), int(ev.get("hp", 0))]
		Ev.CONDITION:
			return "%s %s %s" % [head, String(SRD.Condition.find_key(int(ev.get("cond", 0)))).to_lower(), "on" if ev.get("on", false) else "off"]
		Ev.EFFECT:
			return "%s %s %s" % [head, ev.get("what", ""), "on" if ev.get("on", false) else "off"]
		Ev.PROJECTILE:
			return "%s #%d %s" % [head, int(ev.get("pid", 0)), PKINDS[int(ev.get("pkind", 0))] if int(ev.get("pkind", 0)) < PKINDS.size() else "?"]
		Ev.IMPACT:
			return "%s #%d at %.1f,%.1f" % [head, int(ev.get("pid", 0)), Vector2(ev.get("pos", Vector2.ZERO)).x, Vector2(ev.get("pos", Vector2.ZERO)).y]
		Ev.PUSH:
			return "%s by %s" % [head, ev.get("push", Vector2.ZERO)]
	return head
