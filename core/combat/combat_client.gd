## The client half of combat (HostSystem.COMBAT): sends intents, receives events, status
## and the spell list, keeps a short event log. Main thread; never rolls dice.
##
## For the UI (Interface track):
##   signal event(ev: Dictionary)          # every CombatCodec event, in order (ev.t = host tick)
##   signal cooldowns_changed(status)      # action/bonus/reaction seconds left, slots, limits
##   signal spells_changed(spells)         # [{slug, name, level, flags}] (CombatCodec.SPELL_*)
##   attack(aim: Vector2, throw := false); cast(slug, level, aim); cancel()
##   rolled()                              # the own body started a roll: tells the host
##   target_at(aim) -> {id, reach}         # the creature the next swing or shot would land on
##   spell_slot(i) -> Dictionary           # the i-th castable attack/save spell (hotbar default)
##   filter_input(inp) -> PlayerInput      # own movement limits (speed 0, prone, fear)
##   events_log: Array                      # the last LOG_MAX events
class_name CombatClient
extends ClientSystem

signal event(ev: Dictionary)
signal cooldowns_changed(status: Dictionary)
signal spells_changed(spells: Array)
## The host refused an attack or cast intent (intent: CombatCodec.Msg.ATTACK or CAST).
signal refused(intent: int, reason: String)

const LOG_MAX := 64
## Seconds a sent intent blocks a repeat while its SWING has not come back.
const PENDING_S := 0.35

var cw: ClientWorld
var events_log: Array = []
## Last STATUS, counted down locally (action, bonus, reaction: seconds left).
var status := {}
var spells: Array = []
## Seconds until the own action sequence ends (from SWING events about me).
var busy_s := 0.0
## Seconds until the own swing's first contact (a roll may not start after it).
var windup_s := 0.0
var _pending := 0.0
var sent := 0
## Entity id -> cw.clock when an event last named it.
var _fighting := {}

func sys_id() -> int:
	return HostSystem.COMBAT

func attach(c: ClientWorld) -> void:
	cw = c

func handle(kind: int, data: PackedByteArray) -> void:
	match kind:
		CombatCodec.Msg.EVENTS:
			var m := CombatCodec.read_events(data)
			for ev: Dictionary in m.get("events", []):
				_apply(ev)
		CombatCodec.Msg.STATUS:
			var st := CombatCodec.read_status(data)
			if not st.is_empty():
				status = st
				cooldowns_changed.emit(status)
		CombatCodec.Msg.SPELLS:
			spells = CombatCodec.read_spells(data)
			spells_changed.emit(spells)
		CombatCodec.Msg.REFUSED:
			var m := CombatCodec.read_refused(data)
			if not m.is_empty():
				refused.emit(int(m["intent"]), String(m["reason"]))

func _apply(ev: Dictionary) -> void:
	var me := cw != null and int(ev["dst"]) == cw.my_id
	if int(ev["kind"]) == CombatCodec.Ev.SWING and cw != null and int(ev["src"]) == cw.my_id:
		busy_s = float(ev.get("total", 0.0))
		windup_s = float(ev.get("windup", 0.0))
		_pending = 0.0
	if int(ev["kind"]) == CombatCodec.Ev.CANCEL and cw != null and int(ev["src"]) == cw.my_id:
		busy_s = 0.0
		windup_s = 0.0
		_pending = 0.0
	if me and int(ev["kind"]) == CombatCodec.Ev.PUSH and cw.body != null:
		var v := cw.body.vel
		cw.body.vel = ev["push"]
		TileCollision.move(cw.world, cw.body, 1.0)
		cw.body.vel = Vector2(0.0, minf(v.y, 0.0))
	events_log.append(ev)
	if events_log.size() > LOG_MAX:
		events_log.pop_front()
	for id: int in [int(ev["src"]), int(ev["dst"])]:
		if id != 0:
			_fighting[id] = cw.clock
	if _fighting.size() > 512:
		for id: int in _fighting.keys():
			if not in_fight(id):
				_fighting.erase(id)
	event.emit(ev)

## Is this entity in a fight, as far as this client heard? The host's in_combat (the last blow
## within in_combat_s), with a second's margin for the news to arrive.
func in_fight(id: int) -> bool:
	return _fighting.has(id) and cw.clock - float(_fighting[id]) <= CombatTempo.num("in_combat_s", 5.0) + 1.0

func frame(dt: float) -> void:
	busy_s = maxf(0.0, busy_s - dt)
	windup_s = maxf(0.0, windup_s - dt)
	_pending = maxf(0.0, _pending - dt)
	for k: String in ["action", "bonus", "reaction"]:
		if status.has(k):
			status[k] = maxf(0.0, float(status[k]) - dt)

## Ready to start an action (nothing running, nothing asked for and unanswered, not rolling).
func can_attack() -> bool:
	return (cw == null or cw.body == null or cw.body.roll_t < 0.0) and busy_s <= 0.0 and _pending <= 0.0 and float(status.get("action", 0.0)) <= 0.0 \
		and int(status.get("flags", 0)) & (CombatCodec.ST_NO_ACTIONS | CombatCodec.ST_DOWNED) == 0

## The client's estimate of host time (-1 until a snapshot has synced it).
func _clock() -> float:
	return cw.clock if cw != null and bool(cw.get("_clock_synced")) else -1.0

## Attack toward `aim` (tile units). Rate-limited locally; the host decides.
func attack(aim: Vector2, throw := false) -> bool:
	if cw == null or not can_attack():
		return false
	_pending = PENDING_S
	sent += 1
	cw.send_sys(sys_id(), CombatCodec.Msg.ATTACK, CombatCodec.attack(aim, _clock(), throw))
	return true

func cast(slug: String, level: int, aim: Vector2) -> bool:
	if cw == null:
		return false
	var reaction := false
	for s: Dictionary in spells:
		if s["slug"] == slug:
			reaction = int(s["flags"]) & CombatCodec.SPELL_REACTION != 0
	if not reaction and not can_attack():
		return false
	if not reaction:
		_pending = PENDING_S
	sent += 1
	cw.send_sys(sys_id(), CombatCodec.Msg.CAST, CombatCodec.cast(slug, level, aim, _clock()))
	return true

func cancel() -> void:
	if cw != null:
		cw.send_sys(sys_id(), CombatCodec.Msg.CANCEL, PackedByteArray())

## May the own player start a roll? Not once a swing's contact has begun, not while it cannot
## act or is slowed, and a Frightened creature cannot roll toward what it fears.
func can_roll(inp: PlayerInput) -> bool:
	if cw == null or cw.body == null or (busy_s > 0.0 and windup_s <= 0.0):
		return false
	if int(status.get("flags", 0)) & (CombatCodec.ST_NO_ACTIONS | CombatCodec.ST_DOWNED) != 0:
		return false
	if float(status.get("move_mult", 1.0)) < 1.0:
		return false
	var src := int(status.get("fear_src", 0))
	if src != 0 and cw.remotes.has(src):
		var dir := signf(inp.move_x) if inp.move_x != 0.0 else float(cw.body.facing)
		if dir == signf((cw.remotes[src] as ClientWorld.RemoteEntity).pos.x - cw.body.pos.x):
			return false
	return true

## The body rolled (predicted): the host gets the same clock and tests hits on the same tuck.
func rolled() -> void:
	if cw != null:
		cw.send_sys(sys_id(), CombatCodec.Msg.ROLL, CombatCodec.roll(_clock()))

## The i-th (0-based) supported spell for the default bindings: attack and save spells
## first (the host orders them), then the rest. {} when there is none.
func spell_slot(i: int) -> Dictionary:
	var ok := spells.filter(func(s: Dictionary) -> bool: return int(s["flags"]) & CombatCodec.SPELL_SUPPORTED != 0)
	return ok[i] if i >= 0 and i < ok.size() else {}

## Own movement limits from the host's STATUS (conditions and speed effects).
func filter_input(inp: PlayerInput) -> PlayerInput:
	if inp.roll and not can_roll(inp):
		inp.roll = false
	if status.is_empty() or cw == null:
		return inp
	var fear := Vector2.INF
	var src := int(status.get("fear_src", 0))
	if src != 0 and cw.remotes.has(src):
		fear = (cw.remotes[src] as ClientWorld.RemoteEntity).pos
	return CombatSystem.apply_limits(inp, float(status.get("move_mult", 1.0)),
		int(status.get("flags", 0)) & CombatCodec.ST_NO_JUMP != 0, cw.body.pos, fear)

## The creature the next swing or shot would land on, from where the own body stands now:
## {id, reach: true} the host's own choice of what the blow touches (melee: the arc and the
## reach of the wielded weapon, foes first, nearest box, nearest the aim; a shot: the first
## foe on the line to the aim), {id, reach: false} a foe under the aim but out of reach, or
## {} for nobody. Life's calm people are left out until a fight names them.
func target_at(aim: Vector2) -> Dictionary:
	if cw == null or cw.body == null or cw.world == null:
		return {}
	var rect := cw.body.rect()
	var center := rect.get_center()
	var dir := HitShapes.aim_dir(center, aim, cw.body.facing)
	var range_t := K.ft(float(status.get("range_ft", 0)))
	var reach := K.ft(float(status.get("reach_ft", 5)))
	var half := float(CombatTempo.section("melee").get("arc_half_angle_deg", 70.0))
	var life := cw.system(HostSystem.LIFE)
	var best := {}
	var best_row := [false, 0.0, 0.0]
	var under := 0
	var end := center + dir * range_t
	var best_t := 2.0
	for r: ClientWorld.RemoteEntity in cw.remotes.values():
		if r.kind == HostEntity.Kind.PLAYER or (r.max_hp > 0 and r.hp <= 0):
			continue
		if life != null and life.has_method("is_person") and bool(life.call("is_person", r.id)) and not in_fight(r.id):
			continue
		var box := Rect2(r.pos - Vector2(r.size.x * 0.5, 0.0), r.size)
		if box.grow(0.5).has_point(aim):
			under = r.id
		if range_t > 0.0:
			var t := HitShapes.segment_box(center, end, box)
			if t >= 0.0 and t < best_t and HitShapes.line_to(cw.world, center, box):
				best_t = t
				best = {"id": r.id, "reach": true}
		else:
			var gap := HitShapes.gap(rect, box)
			if gap > reach or not HitShapes.in_arc(rect, dir, reach, half, box) or not HitShapes.line_to(cw.world, center, box):
				continue
			var d := box.get_center().distance_to(aim)
			if best.is_empty() or HitShapes.nearer_touch(true, gap, d, true, best_row[1], best_row[2]):
				best = {"id": r.id, "reach": true}
				best_row = [true, gap, d]
	if best.is_empty() and under != 0:
		return {"id": under, "reach": false}
	return best

## A scripted fighter (bots, smoke tests): walk at the nearest live monster this client can
## see and attack it when in reach. Returns the input to use; attacks through attack().
## `pick` (optional, RemoteEntity -> bool) chooses which remotes count as foes; by default
## every remote that is not a player or one of Life's people.
func fight_step(inp: PlayerInput, reach := 3.0, pick := Callable()) -> PlayerInput:
	if cw == null or cw.body == null:
		return inp
	var best: ClientWorld.RemoteEntity = null
	var bpos := Vector2.ZERO
	var bd := 1e9
	var life := cw.system(HostSystem.LIFE)
	for r: ClientWorld.RemoteEntity in cw.remotes.values():
		if r.kind == HostEntity.Kind.PLAYER or (r.max_hp > 0 and r.hp <= 0):
			continue
		if pick.is_valid():
			if not bool(pick.call(r)):
				continue
		elif life != null and life.has_method("is_person") and bool(life.call("is_person", r.id)):
			continue      # Life's townsfolk, guards and travellers are not monsters to hunt
		var p: Vector2 = cw.sample_remote(r.id).get("pos", r.pos)    # as drawn (interpolated)
		var d := p.distance_to(cw.body.pos)
		if d < bd:
			bd = d
			best = r
			bpos = p
	inp.move_x = 0.0
	if best == null:
		return inp
	var dx := bpos.x - cw.body.pos.x
	# close until the boxes are in reach, height included: on a slope or stair a target 3 tiles
	# across is 3 tiles up as well (M2's scripted fighters stopped there and swung at the air)
	var them := Rect2(bpos - Vector2(best.size.x * 0.5, 0.0), best.size)
	var near := HitShapes.gap(cw.body.rect(), them) <= minf(reach, 1.9)
	if absf(dx) > reach or not near:
		inp.move_x = signf(dx)
	if near:
		cw.body.facing = 1 if dx >= 0.0 else -1
		attack(them.get_center())
	return filter_input(inp)
