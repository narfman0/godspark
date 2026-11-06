## The monster brains: one state machine with an archetype that changes how it closes, hits
## and backs off (data/ecology/brains.json). Shared: senses through combat's sight (light,
## Darkvision, blindsight) plus hearing a fight nearby; idle / wander / chase / attack / flee /
## return; packmates alert each other and spread out (flankers aim for the far side); a leash
## to the home point; fleeing at low HP for creatures that would; neutral creatures stay
## neutral until attacked or cornered, and a Bond (rules.bond) keeps a creature friendly.
## Readable telegraphs: it stands still through combat's wind-up and recovery.
##
## Archetypes: bruiser (close and hit), skirmisher (hit and retreat), archer and caster (keep
## a distance band, ranged attacks), heavy (slow, breath or area actions when ready), swarm
## (rush), lurker (waits still until prey comes close), flier (swoops from above), ambusher
## (waits in water).
##
## Movement: straight steering when the target is near and in line, else a NavPath from the
## monsters system's budgeted planner (sys.request_plan), followed by NavFollow.
class_name MonsterBrain
extends RefCounted

enum State { IDLE, WANDER, LURK, CHASE, FLEE, RETURN }

const PATH := "res://data/ecology/brains.json"
static var _cfg := {}

var archetype := "bruiser"
var state := State.IDLE
var home := Vector2.ZERO
var hostility := "hostile"
var flees := false
var bond_key := ""
## Same non-empty id: one pack (alerts, spacing, Tethered).
var pack_id := 0
var slot := 0
var target_id := 0
var provoked := {}            # entity id -> true: attacked by them
var rank := "standard"
var slug := ""
## The monsters system's record for this monster (rank, affixes...), set by the system.
var rec: Variant = null
## Planning.
var follow := NavFollow.new()
var plan_pending := false
var plan_goal := Vector2.INF
var plan_at := -100.0
var plan_fail := 0
## Counters for tests and reports.
var attacks := 0
var plans := 0

var _t := 0.0
var _sense_at := -1.0
var _was_busy := false
var _backoff_until := -1.0
var _state_t := 0.0
var _wander_at := 0.0
var _wander_to := Vector2.INF
var _corner_t := 0.0
## No running away again before this: it runs as fast as its pursuer, so a second flight, and
## every one after it, would never end.
var _stand_until := -1.0
var _lost_t := 0.0
var _last := PlayerInput.new()
var _think_at := 0.0
var _calm_next := 0.0
var _line_at := -1.0
var _line_goal := Vector2.INF
var _line_ok := false

static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _cfg

func arch() -> Dictionary:
	return cfg()["archetypes"].get(archetype, cfg()["archetypes"]["bruiser"])

func _num(k: String, d: float) -> float:
	return float(cfg().get(k, d))

func _init(kind := "bruiser", home_pos := Vector2.ZERO) -> void:
	archetype = kind
	home = home_pos
	if kind in ["lurker", "ambusher"]:
		state = State.LURK

func think(host: WorldHost, e: HostEntity, dt: float) -> PlayerInput:
	_t += dt
	_state_t += dt
	var combat := host.system(HostSystem.COMBAT) as CombatSystem
	var inp := PlayerInput.new()
	if combat == null:
		return inp
	if not combat.can_act(e):
		follow.path = null
		return combat.filter_input(e, inp)
	var foe: HostEntity = host.entity(target_id) if target_id != 0 else null
	if foe != null and (not _foe_kind(host, foe) or combat.actor(foe) == null or not combat._targetable(combat.actor(foe))):
		foe = null
		target_id = 0
	# with Life a foe can stop being one (a grudge runs out, standing changes)
	if foe != null and not provoked.has(foe.id) and host.system(HostSystem.LIFE) != null \
			and not bool(host.system(HostSystem.LIFE).call("hostile", e, foe)):
		foe = null
		target_id = 0
	# far from every player: think slowly, stand still
	if _t < _think_at:
		return combat.filter_input(e, _hold(_last))
	# calm monsters (idle, wandering, lurking) think at 10 Hz; anything that engages them
	# (provoke, a packmate's alert) changes the state at once
	if state in [State.IDLE, State.WANDER, State.LURK]:
		if _t < _calm_next:
			return combat.filter_input(e, _hold(_last))
		_calm_next = _t + 0.1
	var near := _nearest_player_dist(host, e)
	if near > _num("far_tiles", 56.0) and state != State.RETURN and state != State.FLEE:
		_think_at = _t + _num("far_think_s", 0.5)
		_last = PlayerInput.new()
		return _last
	# senses
	if _t >= _sense_at:
		_sense_at = _t + (_num("sense_s", 0.3) if state == State.CHASE else _num("calm_sense_s", 0.5))
		var seen := _sense(host, combat, e)
		if seen != null and (foe == null or seen.id != foe.id and _d(e, seen) + 3.0 < _d(e, foe)):
			if foe == null:
				_alert_pack(host, e, seen)
			foe = seen
			target_id = seen.id
		if foe != null and state in [State.IDLE, State.WANDER, State.LURK]:
			if state != State.LURK or _d(e, foe) <= float(arch().get("trigger", 6.0)) or provoked.has(foe.id):
				_enter(State.CHASE)
	# busy in an attack: stand still facing the target (the telegraph)
	if combat.busy(e):
		_was_busy = true
		if foe != null:
			e.body.facing = 1 if foe.body.pos.x >= e.body.pos.x else -1
		return combat.filter_input(e, inp)
	if _was_busy:
		_was_busy = false
		_backoff_until = _t + float(arch().get("backoff", 0.4))
	# flee at low HP
	if flees and e.combatant != null and state != State.FLEE and _t >= _stand_until \
			and e.combatant.current_hp <= e.combatant.stats.max_hp * _num("flee_hp", 0.25) and foe != null:
		_enter(State.FLEE)
	match state:
		State.LURK:
			_last = inp
		State.IDLE, State.WANDER:
			inp = _wander(host, e, dt)
		State.RETURN:
			if e.body.pos.distance_to(home) <= _num("home_tiles", 6.0):
				_enter(State.IDLE if archetype not in ["lurker", "ambusher"] else State.LURK)
				follow.path = null
			else:
				inp = _go(host, e, home, dt, 1.0, Vector2i(2, 2))
		State.FLEE:
			if foe == null or _state_t > _num("flee_s", 6.0):
				_stand_until = _t + _num("flee_again_s", 45.0)
				_enter(State.RETURN)
				target_id = 0
			else:
				var away := e.body.pos + Vector2(signf(e.body.pos.x - foe.body.pos.x) * 12.0, 0.0)
				inp = _go(host, e, away, dt, 1.0, Vector2i(3, 6))
		State.CHASE:
			if foe == null:
				_lost_t += dt
				if _lost_t > 3.0:
					_enter(State.RETURN)
				else:
					inp = _hold(_last)
			else:
				_lost_t = 0.0
				if e.body.pos.distance_to(home) > _num("leash_tiles", 48.0):
					_enter(State.RETURN)
					target_id = 0
				else:
					inp = _fight(host, combat, e, foe, dt)
	_last = inp
	return combat.filter_input(e, inp)

# --- fighting ----------------------------------------------------------------------------------

func _fight(host: WorldHost, combat: CombatSystem, e: HostEntity, foe: HostEntity, dt: float) -> PlayerInput:
	var inp := PlayerInput.new()
	var dx := foe.body.pos.x - e.body.pos.x
	var dist := HitShapes.gap(e.body.rect(), foe.body.rect())
	var aim := foe.body.rect().get_center()
	if _t < _backoff_until:
		if archetype in ["skirmisher", "flier", "archer", "caster"] or float(arch().get("backoff", 0.0)) > 0.0:
			inp.move_x = -signf(dx) * (1.0 if archetype == "skirmisher" else 0.6)
			if archetype == "flier":
				inp.up = true
			return inp
	var acts := combat.actions_of(e)
	# a ready breath or area action that would reach
	for i in acts.size():
		var act: Dictionary = acts[i]
		if act["kind"] == "save" and e.combatant != null and MonsterSpells.save_action_ready(e.combatant, act["save"]) \
				and e.body.rect().get_center().distance_to(aim) <= K.ft(float(act.get("reach_ft", 5.0))) \
				and combat.start_attack(e, i, aim):
			attacks += 1
			return inp
	var ranged := _ranged_action(acts)
	var keep: Array = arch().get("keep", [])
	if archetype in ["archer", "caster"] and ranged >= 0 and not keep.is_empty():
		if _reaches(host, e, foe, acts, ranged, dist) and dist >= 2.5 and combat.start_attack(e, ranged, aim):
			attacks += 1
			return inp
		if dist < float(keep[0]):
			# too close: melee if it can, else step away
			if _reaches(host, e, foe, acts, _first_attack(acts), dist) and combat.start_attack(e, -1, aim):
				attacks += 1
				return inp
			return _go(host, e, e.body.pos + Vector2(-signf(dx) * 6.0, 0.0), dt, 1.0, Vector2i(2, 3))
		if dist <= float(keep[1]):
			e.body.facing = 1 if dx >= 0.0 else -1
			return inp
	if _reaches(host, e, foe, acts, _first_attack(acts), dist) and combat.start_attack(e, -1, aim):
		attacks += 1
		return inp
	# close in: spread around the target; flankers take the far side
	var goal := foe.body.pos
	if pack_id != 0 and slot > 0:
		var off := float((slot + 1) / 2) * _num("spacing_tiles", 1.6)
		if slot % 2 == 1:
			goal.x += signf(dx) * off             # the far side: a different way round
		else:
			goal.x -= signf(dx) * minf(off, 1.0)  # the near side, not on the leader's tile
	if archetype == "flier" and e.stats.fly_speed > 0.0 and dist > 3.0:
		goal.y += float(arch().get("hover", 4.0))
	return _go(host, e, goal, dt, float(arch().get("speed", 1.0)), Vector2i(1, 2), foe)

## Would action i touch foe now (melee reach, or normal range for ranged), with a line to it?
## The same test as combat.targets_in_reach, for one target (no loop over every creature).
func _reaches(host: WorldHost, e: HostEntity, foe: HostEntity, acts: Array, i: int, gap: float) -> bool:
	var reach := 2.0
	var rng := 0.0
	if i >= 0 and i < acts.size():
		var act: Dictionary = acts[i]
		if act["kind"] == "ranged":
			reach = 0.0
			rng = K.ft(float(act.get("range_ft", 0.0)))
		else:
			reach = K.ft(float(act.get("reach_ft", 5.0)))
	if gap > maxf(reach + HitShapes.EPS, rng):
		return false
	return HitShapes.line_to(host.world, e.body.rect().get_center(), foe.body.rect())

## The action Multiattack starts with, else the default attack (as combat picks it).
func _first_attack(acts: Array) -> int:
	for i in acts.size():
		if acts[i]["kind"] == "melee":
			return i
	return 0 if not acts.is_empty() else -1

func _ranged_action(acts: Array) -> int:
	for i in acts.size():
		if acts[i]["kind"] == "ranged":
			return i
	return -1

# --- movement ---------------------------------------------------------------------------------

## Head for `goal`: straight when it is near and in line, else along a planned path.
func _go(host: WorldHost, e: HostEntity, goal: Vector2, dt: float, speed: float, tol: Vector2i,
		foe: HostEntity = null) -> PlayerInput:
	var b := e.body
	var d := goal - b.pos
	var mid_jump := follow.active() and follow.jump_t >= 0
	var direct: bool = not mid_jump and (b.on_floor or b.swimming) and absf(d.x) <= _num("direct_tiles", 10.0) and absf(d.y) <= 1.5 and e.stats.fly_speed <= 0.0
	if direct:
		# the line check is cached for a moment (it is the costly part)
		if _t >= _line_at or _line_goal.distance_to(goal) > 1.0:
			_line_at = _t + 0.2
			_line_goal = goal
			_line_ok = not TileCollision.raycast(host.world, b.pos + Vector2(0, 1.2), goal + Vector2(0, 1.2))["hit"]
		direct = _line_ok
	if direct and not b.swimming:
		follow.path = null
		var inp := PlayerInput.new()
		inp.move_x = clampf(d.x * 1.5, -1.0, 1.0) * speed if absf(d.x) > 0.3 else 0.0
		if b.on_wall and b.on_floor and inp.move_x != 0.0 and signi(b.wall_dir) == signi(int(signf(inp.move_x))):
			inp.jump = true
			inp.jump_pressed = true
		return inp
	var sys: Variant = host.system(HostSystem.MONSTERS)
	# replan: no path (not more than once a second; after a failed plan, wait replan_s), the
	# goal moved, or the path is old
	var since := _t - plan_at
	var stale := ((follow.path == null or follow.failed or not follow.active()) and since > (_num("replan_s", 2.0) if plan_fail > 0 else 1.0)) \
		or (plan_goal.distance_to(goal) > _num("goal_moved_tiles", 4.0) and since > 0.5) or since > _num("replan_s", 2.0) * 1.5
	if stale and not mid_jump and not plan_pending and sys != null and sys.has_method("request_plan"):
		if follow.failed:
			plan_fail += 1
		sys.request_plan(e, goal, tol)
		plan_pending = true
		plan_goal = goal
		plan_at = _t
	if follow.active():
		var inp := follow.input(host.world, b, dt, _dig_rate(e))
		if inp != null:
			inp.move_x *= speed
			return inp
	# no path (yet): straight at it, jumping at walls
	var inp2 := PlayerInput.new()
	if follow.path == null or follow.failed:
		inp2.move_x = clampf(d.x, -1.0, 1.0) * speed if absf(d.x) > 0.5 else 0.0
		if e.stats.fly_speed > 0.0:
			inp2.up = d.y > 0.5
			inp2.down = d.y < -0.5
		elif b.on_wall and b.on_floor and inp2.move_x != 0.0:
			inp2.jump = true
			inp2.jump_pressed = true
	return inp2

## The planner answered (path may be null: unreachable).
func on_plan(path: NavPath) -> void:
	plan_pending = false
	plans += 1
	if path == null:
		plan_fail += 1
		follow.path = null
		if plan_fail >= 3 and state == State.CHASE:
			# lose interest
			_enter(State.RETURN)
			target_id = 0
			plan_fail = 0
		return
	follow.set_path(path)
	plan_fail = 0

func _dig_rate(e: HostEntity) -> float:
	return maxf(e.stats.burrow_speed / 8.0, 1.5)

func _wander(host: WorldHost, e: HostEntity, dt: float) -> PlayerInput:
	if archetype in ["lurker", "ambusher"]:
		return PlayerInput.new()
	if _t >= _wander_at:
		var w: Array = cfg().get("wander_s", [3.0, 8.0])
		var r := _rng(e)
		_wander_at = _t + r.randf_range(float(w[0]), float(w[1]))
		var span := _num("wander_tiles", 10.0)
		_wander_to = home + Vector2(r.randf_range(-span, span), 0.0)
		_enter(State.WANDER)
	if state == State.WANDER and _wander_to != Vector2.INF:
		if absf(_wander_to.x - e.body.pos.x) < 1.0:
			_enter(State.IDLE)
			return PlayerInput.new()
		var inp := PlayerInput.new()
		inp.move_x = signf(_wander_to.x - e.body.pos.x) * 0.4
		var ahead := Vector2(e.body.pos.x + signf(inp.move_x) * (e.body.size.x * 0.5 + 0.6), e.body.pos.y)
		# do not wander off ledges or into walls
		if e.stats.fly_speed <= 0.0 and (not host.world.is_solid(floori(ahead.x), floori(ahead.y) - 1) \
				or (e.body.on_wall and signi(e.body.wall_dir) == signi(int(signf(inp.move_x))))):
			_enter(State.IDLE)
			_wander_to = Vector2.INF
			return PlayerInput.new()
		return inp
	return PlayerInput.new()

## Deterministic per-monster randomness that does not touch the rules dice.
func _rng(e: HostEntity) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([e.id, int(_t * 10.0)])
	return r

# --- senses -----------------------------------------------------------------------------------

## The nearest player it notices and is hostile to: seen (sight, light, Darkvision,
## blindsight) or heard fighting nearby. Neutral creatures notice only who provoked them.
func _sense(host: WorldHost, combat: CombatSystem, e: HostEntity) -> HostEntity:
	var best: HostEntity = null
	var bd := INF
	var sight := _num("sight_tiles", 30.0)
	var hear := _num("hear_tiles", 20.0)
	var life := host.system(HostSystem.LIFE)
	for p: HostEntity in host.entities.values():
		if p == e or (life == null and not p.is_player()):
			continue
		var d := _d(e, p)
		if d > maxf(sight, hear) or d >= bd:
			continue
		var pa := combat.actor(p)
		if pa == null or not combat._targetable(pa) or not is_foe(host, e, p, d):
			continue
		var noticed := provoked.has(p.id)
		if not noticed and d <= hear and combat.in_combat(p):
			noticed = true
		if not noticed and d <= sight and combat.sight.can_see(e, p):
			noticed = true
		if noticed:
			best = p
			bd = d
	return best

## Players only without Life; with Life any creature can be a foe.
static func _foe_kind(host: WorldHost, foe: HostEntity) -> bool:
	return foe.is_player() or host.system(HostSystem.LIFE) != null

## Would it fight `p` now? Without Life: a player it is hostile to (hostile_to). With Life:
## provoked, or Life's stance says HOSTILE (players must also pass hostile_to: neutral
## creatures, Bonds).
func is_foe(host: WorldHost, e: HostEntity, p: HostEntity, d := -1.0) -> bool:
	var life := host.system(HostSystem.LIFE)
	if life == null:
		return p.is_player() and hostile_to(host, e, p, d)
	if provoked.has(p.id):
		return true
	if p.is_player() and not hostile_to(host, e, p, d):
		return false
	return bool(life.call("hostile", e, p))

## Is it hostile to this player now? Provoked: always. Neutral: only when cornered (a player
## stays very close for a while). A Bond of strength 1+ with its kind or people: friendly.
func hostile_to(host: WorldHost, e: HostEntity, p: HostEntity, d := -1.0) -> bool:
	if provoked.has(p.id):
		return true
	if bond_key != "":
		var rules := host.system(HostSystem.RULES)
		if rules != null and rules.has_method("bond") and int(rules.call("bond", p.id, bond_key)) >= 1:
			return false
	if hostility == "neutral":
		if d < 0.0:
			d = _d(e, p)
		if d <= _num("corner_tiles", 2.5):
			_corner_t += _num("sense_s", 0.3)
			if _corner_t >= _num("corner_s", 2.5):
				provoked[p.id] = true
				return true
		else:
			_corner_t = maxf(0.0, _corner_t - 0.1)
		return false
	return true

## Attacked (by the monsters system from combat's damage hook).
func provoke(host: WorldHost, e: HostEntity, src: int) -> void:
	var p := host.entity(src)
	if p == null or p == e or (not p.is_player() and host.system(HostSystem.LIFE) == null):
		return
	provoked[src] = true
	if target_id == 0 or state in [State.IDLE, State.WANDER, State.LURK, State.RETURN]:
		target_id = src
		if state != State.FLEE:
			_enter(State.CHASE)
		_alert_pack(host, e, p)

func _alert_pack(host: WorldHost, e: HostEntity, foe: HostEntity) -> void:
	if pack_id == 0:
		return
	var r := _num("pack_alert_tiles", 28.0)
	for m: HostEntity in host.entities.values():
		if m == e or m.brain == null or not (m.brain is MonsterBrain):
			continue
		var mb: MonsterBrain = m.brain
		if mb.pack_id != pack_id or m.body.pos.distance_to(e.body.pos) > r:
			continue
		mb.alerted_by(foe)

## A packmate saw (or was hit by) foe.
func alerted_by(foe: HostEntity) -> void:
	if hostility == "neutral" and not provoked.has(foe.id):
		provoked[foe.id] = true      # the herd defends itself
	if target_id == 0 or state in [State.IDLE, State.WANDER, State.LURK]:
		target_id = foe.id
		if state != State.FLEE:
			_enter(State.CHASE)

func _enter(s: State) -> void:
	if state != s:
		state = s
		_state_t = 0.0

static func _d(a: HostEntity, b: HostEntity) -> float:
	return a.body.pos.distance_to(b.body.pos)

func _nearest_player_dist(host: WorldHost, e: HostEntity) -> float:
	var best := INF
	for p: HostEntity in host.entities.values():
		if p.is_player():
			best = minf(best, p.body.pos.distance_to(e.body.pos))
	return best

## Keep moving the same way, without a fresh jump press.
static func _hold(last: PlayerInput) -> PlayerInput:
	var inp := PlayerInput.new()
	inp.move_x = last.move_x
	inp.up = last.up
	inp.down = last.down
	return inp
