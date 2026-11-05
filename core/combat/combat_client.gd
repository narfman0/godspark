## The client half of combat (HostSystem.COMBAT): sends intents, receives events, status
## and the spell list, keeps a short event log. Main thread; never rolls dice.
##
## For the UI (Interface track):
##   signal event(ev: Dictionary)          # every CombatCodec event, in order (ev.t = host tick)
##   signal cooldowns_changed(status)      # action/bonus/reaction seconds left, slots, limits
##   signal spells_changed(spells)         # [{slug, name, level, flags}] (CombatCodec.SPELL_*)
##   attack(aim: Vector2, throw := false); cast(slug, level, aim); cancel()
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
var _pending := 0.0
var sent := 0

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
		_pending = 0.0
	if int(ev["kind"]) == CombatCodec.Ev.CANCEL and cw != null and int(ev["src"]) == cw.my_id:
		busy_s = 0.0
		_pending = 0.0
	if me and int(ev["kind"]) == CombatCodec.Ev.PUSH and cw.body != null:
		var v := cw.body.vel
		cw.body.vel = ev["push"]
		TileCollision.move(cw.world, cw.body, 1.0)
		cw.body.vel = Vector2(0.0, minf(v.y, 0.0))
	events_log.append(ev)
	if events_log.size() > LOG_MAX:
		events_log.pop_front()
	event.emit(ev)

func frame(dt: float) -> void:
	busy_s = maxf(0.0, busy_s - dt)
	_pending = maxf(0.0, _pending - dt)
	for k: String in ["action", "bonus", "reaction"]:
		if status.has(k):
			status[k] = maxf(0.0, float(status[k]) - dt)

## Ready to start an action (nothing running, nothing asked for and unanswered).
func can_attack() -> bool:
	return busy_s <= 0.0 and _pending <= 0.0 and float(status.get("action", 0.0)) <= 0.0 \
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

## The i-th (0-based) supported spell for the default bindings: attack and save spells
## first (the host orders them), then the rest. {} when there is none.
func spell_slot(i: int) -> Dictionary:
	var ok := spells.filter(func(s: Dictionary) -> bool: return int(s["flags"]) & CombatCodec.SPELL_SUPPORTED != 0)
	return ok[i] if i >= 0 and i < ok.size() else {}

## Own movement limits from the host's STATUS (conditions and speed effects).
func filter_input(inp: PlayerInput) -> PlayerInput:
	if status.is_empty() or cw == null:
		return inp
	var fear := Vector2.INF
	var src := int(status.get("fear_src", 0))
	if src != 0 and cw.remotes.has(src):
		fear = (cw.remotes[src] as ClientWorld.RemoteEntity).pos
	return CombatSystem.apply_limits(inp, float(status.get("move_mult", 1.0)),
		int(status.get("flags", 0)) & CombatCodec.ST_NO_JUMP != 0, cw.body.pos, fear)

## A scripted fighter (bots, smoke tests): walk at the nearest live monster this client can
## see and attack it when in reach. Returns the input to use; attacks through attack().
func fight_step(inp: PlayerInput, reach := 3.0) -> PlayerInput:
	if cw == null or cw.body == null:
		return inp
	var best: ClientWorld.RemoteEntity = null
	var bpos := Vector2.ZERO
	var bd := 1e9
	for r: ClientWorld.RemoteEntity in cw.remotes.values():
		if r.kind == HostEntity.Kind.PLAYER or (r.max_hp > 0 and r.hp <= 0):
			continue
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
	if absf(dx) > reach:
		inp.move_x = signf(dx)
	else:
		cw.body.facing = 1 if dx >= 0.0 else -1
		attack(bpos + Vector2(0, best.size.y * 0.5))
	return filter_input(inp)
