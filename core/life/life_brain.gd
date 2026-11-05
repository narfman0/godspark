## The brain of Life's people: a MonsterBrain (senses, nav, fighting, fleeing) with a post that
## Life moves through the day (work anchor, the square at dusk, the home door at night; a
## party's point on its route). Fighters (guards, escorts, raiders, patrols) fight what Life's
## stance makes their foe and walk back to their post when calm. Civilians never fight: they
## run for their door (or away) from a foe or a fight nearby and calm down after a while.
## Provocations wear off after the standing table's grudge_s.
class_name LifeBrain
extends MonsterBrain

var life_role := "townsfolk"
var fighter := false
## Where it should be now (Life sets it) and the door it runs to.
var post := Vector2.ZERO
var safe := Vector2.INF
var post_span := 2.0
var alarmed_until := -1.0
var _prov_at := {}
var _calm_at := 0.0

func _init(kind := "bruiser", home_pos := Vector2.ZERO) -> void:
	super(kind, home_pos)
	post = home_pos

func think(host: WorldHost, e: HostEntity, dt: float) -> PlayerInput:
	_expire()
	if fighter:
		home = post
		if state in [State.IDLE, State.WANDER] and target_id == 0 and absf(e.body.pos.x - post.x) > post_span + 4.0:
			_enter(State.RETURN)
		return super(host, e, dt)
	return _civilian(host, e, dt)

func _civilian(host: WorldHost, e: HostEntity, dt: float) -> PlayerInput:
	_t += dt
	var combat := host.system(HostSystem.COMBAT) as CombatSystem
	if combat == null or not combat.can_act(e):
		return PlayerInput.new() if combat == null else combat.filter_input(e, PlayerInput.new())
	var alarmed := _t < alarmed_until
	# calm and at its post: think twice a second
	if not alarmed and _t < _calm_at:
		return combat.filter_input(e, _hold(_last))
	if _t >= _sense_at:
		_sense_at = _t + 0.5
		var seen := _sense(host, combat, e)
		if seen != null and _d(e, seen) <= 18.0:
			_raise(seen.id)
			alarmed = true
	var goal := post
	var speed := 0.45
	if alarmed:
		speed = 1.0
		var foe := host.entity(target_id)
		if safe != Vector2.INF and (foe == null or signf(safe.x - e.body.pos.x) != signf(foe.body.pos.x - e.body.pos.x) \
				or absf(safe.x - e.body.pos.x) < absf(foe.body.pos.x - e.body.pos.x)):
			goal = safe
		elif foe != null:
			goal = e.body.pos + Vector2(signf(e.body.pos.x - foe.body.pos.x) * 12.0, 0.0)
		elif safe != Vector2.INF:
			goal = safe
	var inp := PlayerInput.new()
	if absf(goal.x - e.body.pos.x) > (0.6 if alarmed else post_span) or absf(goal.y - e.body.pos.y) > 3.0:
		inp = _go(host, e, goal, dt, speed, Vector2i(1, 2))
	elif not alarmed:
		follow.path = null
		_calm_at = _t + 0.5
		inp = _wander_small(e)
	_last = inp
	return combat.filter_input(e, inp)

## A few steps around the post now and then.
func _wander_small(e: HostEntity) -> PlayerInput:
	var inp := PlayerInput.new()
	var r := _rng(e)
	if r.randf() < 0.15:
		inp.move_x = (1.0 if r.randf() < 0.5 else -1.0) * 0.3
		if absf(e.body.pos.x + inp.move_x * 2.0 - post.x) > post_span:
			inp.move_x = -inp.move_x
	return inp

## Something frightening (a foe, a fight nearby): run for the door for a while.
func _raise(foe_id: int) -> void:
	alarmed_until = _t + float(Life.people_cfg().get("calm_s", 8.0))
	if foe_id != 0:
		target_id = foe_id

func alarm(foe: HostEntity) -> void:
	if fighter:
		alerted_by(foe)
	else:
		_raise(foe.id if foe != null else 0)

func provoke(host: WorldHost, e: HostEntity, src: int) -> void:
	_prov_at[src] = _t
	if fighter:
		super(host, e, src)
	else:
		provoked[src] = true
		_raise(src)

func alerted_by(foe: HostEntity) -> void:
	if not fighter:
		_raise(foe.id)
		return
	super(foe)

## Provocations wear off (Life's grudge time); a forgotten foe is let go.
func _expire() -> void:
	if provoked.is_empty():
		return
	var g := Life.num("grudge_s", 60.0)
	for id: int in provoked.keys():
		if _t - float(_prov_at.get(id, _t)) > g:
			provoked.erase(id)
			_prov_at.erase(id)
			if target_id == id:
				target_id = 0

## Life's people are only ever near players: never the far-away slow think.
func _nearest_player_dist(_host: WorldHost, _e: HostEntity) -> float:
	return 0.0
