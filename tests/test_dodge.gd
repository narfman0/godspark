## The dodge roll: timing and cooldown on the body, the hurt box's shape, the same clock on
## client and host over the loopback, melee contacts in and out of the tuck, wind-ups
## cancelled, committed swings not, and the rule that it is the box that dodges: arrows pass
## over it, areas still catch it, and nothing is under the blow of a creature too big to miss.
extends RefCounted

const Rig := preload("res://tests/net_rig.gd")
const Combat := preload("res://tests/test_combat.gd")
const Ev := CombatCodec.Ev
const STEP := 1.0 / 60.0

func run(t: TestLog) -> void:
	_numbers(t)
	_timing(t)
	_cooldown(t)
	_limits(t)
	_hurt_shape(t)
	_contacts(t)
	_too_big(t)
	_projectile_and_area(t)
	_cancels_windup(t)
	_committed(t)
	_host_refuses(t)
	_input_bytes(t)
	_client_and_host(t)

static func body(world: TileWorld) -> Body:
	var b := MoveStats.player().make_body()
	b.pos = Vector2(60.5, Combat.GROUND)
	TileCollision.update_contacts(world, b)
	return b

## Steps a standing body through a roll pressed on the first step, returning its x per step.
static func roll_track(world: TileWorld, steps: int) -> PackedFloat64Array:
	var b := body(world)
	var stats := MoveStats.player()
	var out := PackedFloat64Array()
	for i in steps:
		var inp := PlayerInput.new()
		inp.roll = i == 0
		PlayerController.step(world, b, inp, stats, STEP)
		out.append(b.pos.x)
	return out

func _numbers(t: TestLog) -> void:
	var d := CombatTempo.section("dodge")
	t.check(not d.is_empty(), "data/combat.json has a dodge section")
	t.eq(float(d["distance_tiles"]), 2.0, "about two tiles")
	t.eq(float(d["duration_s"]), 0.4, "over about 0.4 s")
	t.eq(float(d["cooldown_s"]), 1.0, "with about a second's cooldown")
	t.check(float(d["hurt_from_s"]) > 0.0 and float(d["hurt_to_s"]) < float(d["duration_s"]), "the tuck is the roll's middle")

func _timing(t: TestLog) -> void:
	var w := Combat.flat_world()
	var b := body(w)
	var stats := MoveStats.player()
	var x0 := b.pos.x
	var inp := PlayerInput.new()
	inp.roll = true
	PlayerController.step(w, b, inp, stats, STEP)
	t.check(b.roll_t >= 0.0, "pressed: rolling")
	t.eq(b.roll_dir, 1, "the way it faces")
	var steps := 1
	var idle := PlayerInput.new()
	while b.roll_t >= 0.0 and steps < 200:
		PlayerController.step(w, b, idle, stats, STEP)
		steps += 1
	t.eq(steps, 25, "0.4 s at 60 Hz: 24 steps of roll and the one that ends it")
	t.check(absf(b.pos.x - x0 - 2.0) < 0.15, "about two tiles from a standstill (%.3f)" % (b.pos.x - x0))
	t.eq(roll_track(w, 40), roll_track(w, 40), "the same input moves the same way, every time")
	# from a run it is not a brake
	var run := body(w)
	var go := PlayerInput.new()
	go.move_x = 1.0
	for i in 40:
		PlayerController.step(w, run, go, stats, STEP)
	var speed := run.vel.x
	go.roll = true
	PlayerController.step(w, run, go, stats, STEP)
	t.check(run.roll_t >= 0.0 and is_equal_approx(run.vel.x, speed), "a roll from a run keeps the run's speed (%.1f)" % run.vel.x)
	t.eq(stats.run_speed, 13.0, "and the run itself is untouched by this track")
	# a left press rolls left
	var left := body(w)
	var back := PlayerInput.new()
	back.move_x = -1.0
	back.roll = true
	PlayerController.step(w, left, back, stats, STEP)
	t.eq(left.roll_dir, -1, "the facing direction, set by what is held")
	# off a ledge it falls
	var w2 := Combat.flat_world()
	for x in range(61, 90):     # the left edge leaves tile 60 at x 61.75, within the two tiles
		for y in range(Combat.GROUND - 6, Combat.GROUND):
			w2.set_fg(x, y, TileDefs.AIR, true)
	var edge := body(w2)
	var e := PlayerInput.new()
	e.roll = true
	PlayerController.step(w2, edge, e, stats, STEP)
	for i in 30:
		PlayerController.step(w2, edge, idle, stats, STEP)
	t.check(edge.pos.y < Combat.GROUND - 0.1, "rolled off a ledge, gravity takes it (y %.2f)" % edge.pos.y)

func _cooldown(t: TestLog) -> void:
	var w := Combat.flat_world()
	var b := body(w)
	var stats := MoveStats.player()
	var press := PlayerInput.new()
	press.roll = true
	PlayerController.step(w, b, press, stats, STEP)
	var first := 0
	var starts := 0
	for i in 180:
		var was := b.roll_t
		PlayerController.step(w, b, press, stats, STEP)    # held down: it rolls as often as it may
		if b.roll_t >= 0.0 and was < 0.0:
			starts += 1
			if first == 0:
				first = i + 1
	t.eq(first, roundi(Dodge.cooldown() * 60.0), "the next roll starts a cooldown after the last began")
	t.eq(starts, 3, "three more in three seconds, and no more")

func _limits(t: TestLog) -> void:
	var w := Combat.flat_world()
	var stats := MoveStats.player()
	var press := PlayerInput.new()
	press.roll = true
	var air := body(w)
	air.pos.y += 8.0
	air.coyote = 0.0
	PlayerController.step(w, air, press, stats, STEP)
	t.check(air.roll_t < 0.0, "no roll in mid-air")
	var ladder := body(w)
	ladder.climbing = true
	t.check(not Dodge.can_start(ladder), "none on a ladder")
	var swim := body(w)
	swim.swimming = true
	t.check(not Dodge.can_start(swim), "none in the water")

func _hurt_shape(t: TestLog) -> void:
	var r := Rect2(60.0, 20.0, 1.5, 2.5)
	var mid := Dodge.duration() * 0.5
	t.eq(Dodge.hurt_rect(r, 0.0), r, "the first frames are the whole body")
	t.eq(Dodge.hurt_rect(r, Dodge.duration() - STEP), r, "and the last")
	var tuck := Dodge.hurt_rect(r, mid)
	t.check(tuck.size.x < r.size.x and tuck.size.y < r.size.y * 0.5, "the middle is a low tuck (%s)" % tuck)
	t.eq(tuck.position.y, r.position.y, "at the feet")
	t.check(is_equal_approx(tuck.get_center().x, r.get_center().x), "under the middle of the body")
	t.eq(Dodge.hurt_rect(r, mid), Dodge.hurt_rect(r, mid), "the same every time: pure of everything but t")
	t.check(Dodge.tucked(float(Dodge.conf()["hurt_from_s"])) and not Dodge.tucked(float(Dodge.conf()["hurt_to_s"])), "from hurt_from_s up to hurt_to_s")

## A goblin wound up on the hero; the hero rolls `lead` s before the blow. Returns the rolls
## against the hero and the WHIFF events naming it.
static func blow(lead: float, slug := "goblin-warrior", att_x := 58.0) -> Array:
	var r := Combat.rig(11)
	var combat: CombatSystem = r["combat"]
	var h := Combat.hero(r, "fighter", 1, 60.5)
	var g := Combat.monster(r, slug, att_x, 500)
	Combat.ticks(r, 1)
	var hurt := h.combatant
	hurt.stats.max_hp = 500
	hurt.stats.current_hp = 500
	combat.record = true
	t_attack(r, g, h)
	var windup := CombatTempo.weapon_tempo("monster")["windup"] as float
	var tick_s := 1.0 / K.TICK_HZ
	var to_roll := roundi((windup - lead) / tick_s) - 1
	if to_roll > 0:
		Combat.ticks(r, to_roll)
	if lead >= 0.0:
		combat.now = r["host"].tick_count / float(K.TICK_HZ)
		combat.start_roll(h)
	Combat.ticks(r, 30)
	return [Combat.rolls_against(r, h.id), Combat.evs(r, Ev.WHIFF, g.id, h.id).size()]

static func t_attack(r: Dictionary, g: HostEntity, h: HostEntity) -> void:
	r["combat"].now = r["host"].tick_count / float(K.TICK_HZ)
	assert(r["combat"].start_attack(g, -1, Combat.center(h)))

func _contacts(t: TestLog) -> void:
	var mid := Dodge.duration() * 0.5
	var res := blow(mid)
	t.eq(res[0], 0, "a contact in the roll's middle rolls no attack")
	t.check(res[1] >= 1, "the host says the blow passed over (WHIFF names the hero)")
	var early := blow(-1.0)
	t.check(early[0] >= 1, "with no roll the same blow rolls (%d)" % early[0])
	t.eq(early[1], 0, "and passes over nobody")
	var late := blow(float(Dodge.conf()["hurt_from_s"]) * 0.25)
	t.check(late[0] >= 1, "in the roll's first frames the blow still lands")
	var after := blow(Dodge.duration() - 0.03)
	t.check(after[0] >= 1, "and in its last frames (the tuck is over)")

func _too_big(t: TestLog) -> void:
	var r := Rect2(60.0, 20.0, 1.5, 2.5)
	var tuck := Dodge.hurt_rect(r, Dodge.duration() * 0.5)
	var aim_y := r.get_center().y
	t.check(Dodge.under_blow(tuck, Rect2(56, 20, 2.5, 3.5), aim_y), "a Large swing passes over the tuck")
	t.check(not Dodge.under_blow(tuck, Rect2(52, 20, 7.0, 7.0), aim_y), "a Gargantuan one does not: too big to miss")
	t.check(not Dodge.under_blow(r, Rect2(56, 20, 2.5, 3.5), aim_y), "a standing body is not under anything")
	# the same contact, end to end, from something that big
	var res := blow(Dodge.duration() * 0.5, "ancient-red-dragon", 53.0)
	t.check(res[0] >= 1, "a gargantuan creature's blow still rolls against a rolling hero (%d)" % res[0])

func _projectile_and_area(t: TestLog) -> void:
	# an arrow at chest height passes over the tuck, and over no standing body
	var r := Rect2(60.0, 20.0, 1.5, 2.5)
	var tuck := Dodge.hurt_rect(r, Dodge.duration() * 0.5)
	var a := Vector2(50.0, 21.25)
	var b := Vector2(70.0, 21.25)
	t.check(HitShapes.segment_box(a, b, r) >= 0.0, "a chest-high shot touches a standing body")
	t.eq(HitShapes.segment_box(a, b, tuck), -1.0, "and flies over a tuck")
	var low := Vector2(50.0, 20.2)
	t.check(HitShapes.segment_box(low, Vector2(70.0, 20.2), tuck) >= 0.0, "a shot along the ground does not")
	t.check(HitShapes.in_area(SRD.AoEShape.SPHERE, Vector2(60.75, 22.0), Vector2.RIGHT, 8.0, 0.0, tuck), "an area that reaches the tuck catches it: no rule protects it")

func _cancels_windup(t: TestLog) -> void:
	var r := Combat.rig(3)
	var combat: CombatSystem = r["combat"]
	var h := Combat.hero(r)
	var g := Combat.monster(r, "goblin-warrior", 63.0, 500)
	Combat.ticks(r, 1)
	combat.now = r["host"].tick_count / float(K.TICK_HZ)
	t.check(combat.start_attack(h, -1, Combat.center(g)), "the hero winds up")
	t.check(combat.busy(h), "busy")
	t.eq(combat.start_roll(h), "", "a roll in the wind-up is taken")
	t.eq(Combat.evs(r, Ev.CANCEL, h.id).size(), 1, "CANCEL went out")
	t.check(not combat.busy(h), "the action is not spent")
	t.eq(Combat.evs(r, Ev.ROLL, h.id).size(), 1, "ROLL went out")
	combat.now = r["host"].tick_count / float(K.TICK_HZ)
	t.check(not combat.start_attack(h, -1, Combat.center(g)), "no swing from inside the roll")
	Combat.ticks(r, 20)
	t.eq(Combat.rolls_against(r, g.id), 0, "the swing never landed")
	combat.now = r["host"].tick_count / float(K.TICK_HZ)
	t.check(combat.start_attack(h, -1, Combat.center(g)), "free again once it ends")

func _committed(t: TestLog) -> void:
	var r := Combat.rig(4)
	var combat: CombatSystem = r["combat"]
	var h := Combat.hero(r)
	var g := Combat.monster(r, "goblin-warrior", 63.0, 500)
	Combat.ticks(r, 1)
	combat.now = r["host"].tick_count / float(K.TICK_HZ)
	combat.start_attack(h, -1, Combat.center(g))
	Combat.ticks(r, roundi(float(CombatTempo.weapon_tempo("plain")["windup"]) * K.TICK_HZ) + 1)
	t.check(Combat.rolls_against(r, g.id) >= 1, "the contact has happened")
	combat.now = r["host"].tick_count / float(K.TICK_HZ)
	t.eq(combat.start_roll(h), "swing committed", "a roll cannot start after a swing's contact has begun")
	t.eq(Combat.evs(r, Ev.CANCEL, h.id).size(), 0, "and nothing was cancelled")

func _host_refuses(t: TestLog) -> void:
	var r := Combat.rig(5)
	var combat: CombatSystem = r["combat"]
	var h := Combat.hero(r)
	Combat.ticks(r, 1)
	combat.now = r["host"].tick_count / float(K.TICK_HZ)
	t.eq(combat.start_roll(h), "", "the first roll")
	Combat.ticks(r, 5)
	combat.now = r["host"].tick_count / float(K.TICK_HZ)
	t.eq(combat.start_roll(h), "dodge not ready", "the host keeps the cooldown too")
	Combat.ticks(r, roundi(Dodge.cooldown() * K.TICK_HZ))
	combat.now = r["host"].tick_count / float(K.TICK_HZ)
	t.eq(combat.start_roll(h), "", "and lets the next one go")
	var g := Combat.monster(r, "goblin-warrior", 66.0, 500)
	combat.now = r["host"].tick_count / float(K.TICK_HZ)
	t.eq(combat.start_roll(g), "no body", "creatures do not roll")
	Combat.ticks(r, roundi(Dodge.cooldown() * K.TICK_HZ) + 1)
	combat.now = r["host"].tick_count / float(K.TICK_HZ)
	combat.actor(h).move_mult = 0.5
	t.eq(combat.start_roll(h), "you cannot roll", "a slowed body cannot roll, on the host as on the client")
	combat.actor(h).move_mult = 1.0
	var m := CombatCodec.read_roll(CombatCodec.roll(12.5))
	t.eq(m["clock"], 12.5, "ROLL round trip")
	t.eq(CombatCodec.read_roll(PackedByteArray([1, 2])), {}, "a short ROLL is refused")
	var ev := CombatCodec.read_events(CombatCodec.events(7, [{"kind": Ev.ROLL, "src": 5, "dst": 0, "duration": 0.4},
		{"kind": Ev.WHIFF, "src": 9, "dst": 5}]))
	t.eq(ev["events"].size(), 2, "ROLL and WHIFF events decode")
	t.eq(ev["events"][0]["duration"], 0.4, "with the roll's length")
	t.eq(ev["events"][1]["dst"], 5, "and who rolled under the blow")

func _input_bytes(t: TestLog) -> void:
	var p := PlayerInput.new()
	p.move_x = 1.0
	t.eq(p.to_bytes().size(), 2, "a plain step is still 2 bytes")
	p.roll = true
	var b := p.to_bytes()
	t.eq(b.size(), 3, "a roll is one more")
	var q := PlayerInput.from_bytes(b)
	t.check(q != null and q.roll and q.equals(p), "lossless")
	p.dig = true
	p.target = Vector2i(5, 6)
	var q2 := PlayerInput.from_bytes(p.to_bytes())
	t.check(q2 != null and q2.roll and q2.equals(p), "after a tile intent too")

## Over the loopback at 50 ms each way: the client's body and the host's clock describe the
## same roll, a blow in the middle misses on the host, and no state is corrected.
func _client_and_host(t: TestLog) -> void:
	var rig := Rig.new(Combat.flat_world(), 0.05)
	var combat := CombatSystem.new()
	rig.host.add_system(combat)
	combat.record = true
	var cc := CombatClient.new()
	var c := rig.add_client("ann")
	c.welcomed.connect(func(cw: ClientWorld) -> void: cw.add_system(cc))
	t.check(rig.until(func() -> bool: return c.cw != null and c.cw.area_ready() and not c.cw.frozen, 6.0) >= 0.0, "joined")
	rig.run(1.0)
	var he := rig.host_entity(0)
	var cw := rig.cw(0)
	var corrections := he.corrections
	rig.inputs[0].roll = true
	rig.frame()
	rig.inputs[0].roll = false
	t.check(cw.body.roll_t >= 0.0, "the client rolls at once, predicted")
	t.check(rig.until(func() -> bool: return combat.actor(he).roll_t0 > -1.0, 1.0) >= 0.0, "the host hears of it")
	var a := combat.actor(he)
	combat.now = rig.host.tick_count / float(K.TICK_HZ)
	# the two clocks agree within a tick and a bit of the rig's rounding
	var host_t := combat.now - a.roll_t0
	t.check(absf(host_t - cw.body.roll_t) <= 2.0 / K.TICK_HZ, "the same roll on both sides (host %.3f, client %.3f)" % [host_t, cw.body.roll_t])
	t.eq(Dodge.hurt_rect(he.body.rect(), 0.2).size, Dodge.hurt_rect(cw.body.rect(), 0.2).size, "the same box from the same function")
	rig.run(1.2)
	t.eq(he.corrections, corrections, "the host took every state of the roll")
	t.check(cw.body.pos.distance_to(he.body.pos) < 0.25, "and agrees where it ended")
	# a client that may not roll asks for nothing
	cc.busy_s = 0.5
	cc.windup_s = 0.0
	var press := PlayerInput.new()
	press.roll = true
	t.check(not cc.filter_input(press).roll, "after a contact the client does not roll")
	cc.busy_s = 0.5
	cc.windup_s = 0.1
	var press2 := PlayerInput.new()
	press2.roll = true
	t.check(cc.filter_input(press2).roll, "in a wind-up it does")
	cc.busy_s = 0.0
	cc.windup_s = 0.0
