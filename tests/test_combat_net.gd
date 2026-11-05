## Combat on the wire: codec round trips and malformed input; two clients over loopback
## (50 ms) fighting a monster see the same events and the same final hit points; the aim
## error client-owned movement causes at 50 ms, with and without the lag offset.
extends RefCounted

const Rig := preload("res://tests/net_rig.gd")
const Ev := CombatCodec.Ev

func run(t: TestLog) -> void:
	_codec(t)
	_loopback(t)
	_aim_lag(t)

func _codec(t: TestLog) -> void:
	var a := CombatCodec.read_attack(CombatCodec.attack(Vector2(10.5, -3.25), 12.5, true))
	t.eq([a["aim"], a["clock"], a["throw"]], [Vector2(10.5, -3.25), 12.5, true], "ATTACK round trip")
	t.eq(CombatCodec.attack(Vector2.ZERO, 0.0).size(), 13, "ATTACK is 13 bytes")
	var c := CombatCodec.read_cast(CombatCodec.cast("magic-missile", 2, Vector2(1, 2), 3.0))
	t.eq([c["slug"], c["level"], c["aim"], c["clock"]], ["magic-missile", 2, Vector2(1, 2), 3.0], "CAST round trip")
	t.eq(CombatCodec.read_attack(PackedByteArray([1, 2, 3])), {}, "a short ATTACK is refused")
	var nan := CombatCodec.attack(Vector2(NAN, 0), 0.0)
	t.eq(CombatCodec.read_attack(nan), {}, "a NaN aim is refused")
	var evs := [
		{"kind": Ev.SWING, "src": 5, "dst": 0, "mode": CombatCodec.Mode.MELEE, "swings": 2, "windup": 0.15, "total": 0.5, "aim": Vector2(3.5, 21.25), "what": "Longsword"},
		{"kind": Ev.HIT, "src": 5, "dst": 9, "d20": 14, "total_roll": 19, "ac": 15},
		{"kind": Ev.MISS, "src": 5, "dst": 9, "d20": 1, "total_roll": 6, "ac": 15},
		{"kind": Ev.CRIT, "src": 5, "dst": 9, "d20": 20, "total_roll": 25, "ac": 15},
		{"kind": Ev.SAVE, "src": 5, "dst": 9, "dc": 13, "saved": true, "what": "fireball"},
		{"kind": Ev.DAMAGE, "src": 5, "dst": 9, "amount": 23, "dtype": SRD.DamageType.FIRE, "hp": 7},
		{"kind": Ev.HEAL, "src": 3, "dst": 5, "amount": 9, "hp": 12},
		{"kind": Ev.CONDITION, "src": 0, "dst": 9, "cond": SRD.Condition.PRONE, "on": true},
		{"kind": Ev.DOWNED, "src": 9, "dst": 5},
		{"kind": Ev.DEATH, "src": 5, "dst": 9},
		{"kind": Ev.XP, "src": 9, "dst": 5, "amount": 50},
		{"kind": Ev.EFFECT, "src": 3, "dst": 5, "on": false, "what": "bless-bonus_die"},
		{"kind": Ev.PROJECTILE, "src": 5, "dst": 0, "pid": 77, "pkind": 1, "pos": Vector2(1.5, 2.5), "vel": Vector2(40, 3.5), "gravity": 22.0},
		{"kind": Ev.IMPACT, "src": 5, "dst": 9, "pid": 77, "pos": Vector2(20.25, 21.5)},
		{"kind": Ev.PUSH, "src": 0, "dst": 9, "push": Vector2(4, 0)},
		{"kind": Ev.CANCEL, "src": 5, "dst": 0},
	]
	var m := CombatCodec.read_events(CombatCodec.events(1234, evs))
	t.eq(m.get("tick"), 1234, "EVENTS tick")
	var back: Array = m.get("events", [])
	t.eq(back.size(), evs.size(), "every event kind decodes")
	for i in mini(back.size(), evs.size()):
		var want: Dictionary = evs[i].duplicate()
		want["t"] = 1234
		var got: Dictionary = back[i]
		var same := true
		for k: String in want:
			var a1: Variant = want[k]
			var b1: Variant = got.get(k)
			if a1 is float:
				same = same and absf(float(a1) - float(b1)) < 1e-3
			else:
				same = same and a1 == b1
		t.check(same and got.size() == want.size(), "round trip: %s" % CombatCodec.describe(want))
	var raw := CombatCodec.events(1, evs)
	t.eq(CombatCodec.read_events(raw.slice(0, raw.size() - 1)), {}, "a truncated EVENTS is refused")
	var extra := raw.duplicate()
	extra.append(0)
	t.eq(CombatCodec.read_events(extra), {}, "trailing bytes are refused")
	var bad := CombatCodec.events(1, [{"kind": 99, "src": 1, "dst": 2}])
	t.eq(CombatCodec.read_events(bad), {}, "an unknown event kind is refused")
	var st := {"action": 0.25, "bonus": 1.5, "reaction": 0.0, "move_mult": 0.5, "flags": CombatCodec.ST_NO_JUMP, "fear_src": 42,
		"slots": [[2, 4], [1, 3], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0]], "concentration": "bless"}
	var st2 := CombatCodec.read_status(CombatCodec.status(st))
	t.check(absf(st2["move_mult"] - 0.5) < 0.01 and st2["slots"] == st["slots"] and st2["concentration"] == "bless"
		and st2["fear_src"] == 42 and is_equal_approx(st2["bonus"], 1.5), "STATUS round trip")
	var sp := [{"slug": "fire-bolt", "name": "Fire Bolt", "level": 0, "flags": 65}, {"slug": "shield", "name": "Shield", "level": 1, "flags": 68}]
	t.eq(CombatCodec.read_spells(CombatCodec.spells(sp)), sp, "SPELLS round trip")
	# every truncation of a valid payload is refused, never a crash
	var full := CombatCodec.events(7, evs)
	var refused := 0
	for n in full.size():
		if CombatCodec.read_events(full.slice(0, n)).is_empty():
			refused += 1
	t.eq(refused, full.size(), "every truncated EVENTS payload is refused")

func _loopback(t: TestLog) -> void:
	var world := TileWorld.make_test(1024, 128)
	var rig := Rig.new(world, 0.05)
	var combat := CombatSystem.new()
	rig.host.add_system(combat)
	rig.host.rng.seed = 99
	var seen: Array = [[], []]
	var ccs: Array = []
	for i in 2:
		var c := rig.add_client("p%d" % i)
		var cc := CombatClient.new()
		ccs.append(cc)
		var log: Array = seen[i]
		cc.event.connect(func(ev: Dictionary) -> void: log.append(CombatCodec.describe(ev)))
		c.welcomed.connect(func(cw: ClientWorld) -> void: cw.add_system(cc))
	var ready := rig.until(func() -> bool:
		return rig.clients.all(func(c: ClientEndpoint) -> bool: return c.cw != null and c.cw.area_ready()), 6.0)
	t.check(ready >= 0.0, "two clients joined")
	var sp := rig.host.spawn
	var gob := rig.host.add_srd_monster("goblin-warrior", sp + Vector2(-8, 0), CombatBrain.new())
	gob.combatant.stats.max_hp = 40
	gob.combatant.stats.current_hp = 40
	for i in 2:
		var he := rig.host_entity(i)
		he.combatant.stats.max_hp = 200
		he.combatant.stats.current_hp = 200
	var gid := gob.id
	var took := rig.until(func() -> bool:
		for i in 2:
			rig.inputs[i] = (ccs[i] as CombatClient).fight_step(PlayerInput.new())
		return not rig.host.entities.has(gid), 40.0)
	t.check(took >= 0.0, "the two players killed the goblin (%.1f s)" % took)
	rig.run(1.0)
	t.check(seen[0].size() > 10, "events arrived (%d)" % seen[0].size())
	t.eq(seen[0], seen[1], "both clients saw the same events in the same order")
	t.check(seen[0].any(func(s: String) -> bool: return s.begins_with("DEATH")), "including the DEATH")
	t.check(seen[0].any(func(s: String) -> bool: return s.begins_with("SWING %d>" % gid)), "and the goblin's swings")
	var h0 := rig.host_entity(0).combatant.current_hp
	var h1 := rig.host_entity(1).combatant.current_hp
	t.eq([rig.cw(0).hp, rig.cw(1).hp], [h0, h1], "each client's own hit points match the host")
	t.eq([rig.cw(0).vitals_of(rig.host_entity(1).id).x, rig.cw(1).vitals_of(rig.host_entity(0).id).x], [h1, h0], "and each sees the other's")
	t.check(not (ccs[0] as CombatClient).status.is_empty() and (ccs[0] as CombatClient).spells.size() == 0, "STATUS arrived; a fighter has no spells")
	t.check((ccs[0] as CombatClient).sent > 0 and combat.counts["swings"] > 2, "intents went up (%d) and swings ran" % (ccs[0] as CombatClient).sent)

## A player running right at full speed attacks: how far is the host's copy of its body
## from where the client was when it pressed, and at the contact frame?
func _aim_lag(t: TestLog) -> void:
	var world := TileWorld.make_test(1024, 128)
	var rig := Rig.new(world, 0.05)
	var combat := CombatSystem.new()
	rig.host.add_system(combat)
	var cc := CombatClient.new()
	var c := rig.add_client("runner")
	c.welcomed.connect(func(cw: ClientWorld) -> void: cw.add_system(cc))
	rig.until(func() -> bool: return c.cw != null and c.cw.area_ready(), 6.0)
	rig.host.add_srd_monster("goblin-warrior", rig.host.spawn + Vector2(40, 0))   # something to snapshot (syncs the clock)
	rig.run(0.5)
	rig.inputs[0].move_x = -1.0     # left: open ground (the test world's pit is to the right)
	rig.run(1.0)
	var e := rig.host_entity(0)
	var raw := e.body.pos.distance_to(rig.cw(0).body.pos)
	cc.attack(rig.cw(0).body.pos + Vector2(-3, 1))
	var lag := -1.0
	var at_contact := -1.0
	var comp := -1.0
	var t0 := -1.0
	for i in 60:
		rig.frame()
		var a := combat.actor(e)
		if lag < 0.0 and not a.seq.is_empty():
			lag = a.lead
			t0 = float(a.seq["t0"])
		if t0 >= 0.0 and at_contact < 0.0 and combat.now >= t0 + 0.2 - 1e-6:
			at_contact = e.body.pos.distance_to(rig.cw(0).body.pos)
			comp = combat._rect(a).position.distance_to(rig.cw(0).body.rect().position)
	print("  AIM running at %.1f t/s, 50 ms one way: host copy behind by %.2f tiles; estimated lead %.3f s; at the contact frame %.2f tiles uncompensated, %.2f led" % [
		e.stats.run_speed, raw, lag, at_contact, comp])
	t.check(raw > 0.5 and at_contact > 0.5, "at 50 ms the host's copy trails a running player (%.2f tiles)" % at_contact)
	t.check(lag > 0.03 and lag < 0.12, "the lead estimate is about the one-way delay (%.3f s)" % lag)
	t.check(comp >= 0.0 and comp < at_contact * 0.5, "leading by velocity brings the swing origin to the player (%.2f < %.2f)" % [comp, at_contact])
