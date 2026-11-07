## Real-time d20 combat on the host (HostSystem.COMBAT). A hit must physically connect, then
## the addon rolls: melee arcs at contact frames, projectiles that fly and stop on tiles,
## spell and breath areas with line of effect. Every weapon hit goes through
## AttackResolver.weapon_attack, every spell through SpellResolver.cast.
##
## Players send intents (CombatCodec ATTACK / CAST / CANCEL); brains call the API below.
## Results go to clients near the action as CombatCodec EVENTS; each player gets its own
## STATUS (cooldowns, slots, movement limits) and SPELLS (what it may cast).
##
## Brain API (host thread):
##   combat.can_act(e) -> bool
##   combat.start_attack(e, action := -1, aim := Vector2.INF, throw := false) -> bool
##       action: index into actions_of(e) (monsters), -1 = Multiattack or the default attack
##   combat.targets_in_reach(e, action := -1) -> Array[HostEntity]
##   combat.busy(e) -> bool;  combat.nearest_foe(e, max_tiles) -> HostEntity
##   combat.filter_input(e, inp) -> PlayerInput     # conditions (speed 0, prone, fear...)
##   combat.actions_of(e) -> Array                  # MonsterMoves actions
## Players:
##   combat.start_roll(e) -> String ("" = ok); combat.hurt_box(e) -> Rect2   the box blows must touch
## For other systems:
##   combat.damage(src_id, dst, amount, dtype, opts := {}) -> int
##   combat.in_combat(e) -> bool;  combat.cast(e, slug, level, aim) -> String ("" = ok)
## Docs: docs/tracks/combat.md.
class_name CombatSystem
extends HostSystem

const Ev := CombatCodec.Ev
const Mode := CombatCodec.Mode

## Per-entity combat state.
class Actor:
	var e: HostEntity
	var conc := ConcentrationTracker.new()
	## The running attack or cast: {kind, t0, contacts: [s], total, idx, steps, aim, ...}.
	var seq := {}
	var action_ready := 0.0
	var bonus_ready := 0.0
	var reaction_ready := 0.0
	## Next round boundary (host seconds); -1 until the creature first acts or is acted on.
	var round_at := -1.0
	## When lava next burns it (host seconds), while it touches lava; -1 when it does not.
	var burn_at := -1.0
	var last_hostile := -1000.0
	## The last blow traded with a foe, or swung at one.
	var last_foe := -1000.0
	var takeoff_y := 0.0
	var footed := true
	var dead_at := -1.0
	var downed_at := -1.0
	var prone_at := -1.0
	var killers: Array[int] = []
	## Seconds the host's copy of a player's body trails the player (one-way delay plus a
	## state's age), estimated from the clock its intents carry; bodies are led by vel * lead.
	var lead := 0.0
	var cond_mask := 0
	var effect_ids := {}
	var status_sig := ""
	var spells_key := ""
	var spells: Array = []
	var moves := {}
	var move_mult := 1.0
	var no_jump := false
	var fear_src := 0
	var last_refusal := ""
	var spells_sent := false
	## Action pace multiplier (Monsters' Frenzied affix): >1 shortens what follows the wind-up.
	var pace := 1.0
	## The dodge roll: host seconds it started at (from the intent's clock) and when the next
	## may start. Never set for creatures that do not roll.
	var roll_t0 := -1000.0
	var roll_ready := 0.0
	## Host seconds until its next Legendary Action may be taken (legendary()).
	var legendary_ready := 0.0

## The host, held weakly (the host holds its systems: a strong reference both ways would
## never be freed).
var host: WorldHost:
	get:
		return _host.get_ref() if _host != null else null
var _host: WeakRef
var sight: CombatSight
var resolver := SpellResolver.new()
## id -> Actor
var actors := {}
var projectiles: Array = []
var timers: Array = []
## Host seconds (tick_count / TICK_HZ) of the tick being run.
var now := 0.0
## Tests and the arena: keep every event (with its tick) in `recorded`.
var record := false
var recorded: Array = []
## Counters for the arena and the track notes.
var counts := {"swings": 0, "contacts": 0, "rolls": 0, "whiffs": 0, "projectiles": 0, "events": 0}
var _events: Array = []
var _touched := {}
var _by_name := {}
var _next_pid := 1
var _all: Array = []

func sys_id() -> int:
	return HostSystem.COMBAT

func attach(h: WorldHost) -> void:
	_host = weakref(h)
	sight = CombatSight.new(h)

func entity_added(_h: WorldHost, e: HostEntity) -> void:
	var a := Actor.new()
	a.e = e
	a.takeoff_y = e.body.pos.y
	actors[e.id] = a
	if e.combatant != null and not e.is_player():
		e.combatant.stats.character_name = "%s #%d" % [e.name, e.id]   # effects are keyed by name
	var slug := String(e.look.get("slug", ""))
	if not e.is_player() and slug != "" and host.srd.pack.has_row("monster", slug):
		a.moves = MonsterMoves.of(host.srd, slug)
	if e.combatant != null:
		_by_name[e.combatant.name] = e.id

func entity_removed(_h: WorldHost, e: HostEntity) -> void:
	actors.erase(e.id)
	projectiles = projectiles.filter(func(p: Dictionary) -> bool: return p["owner"] != e.id)

func handle(_h: WorldHost, e: HostEntity, kind: int, data: PackedByteArray) -> void:
	var a: Actor = actors.get(e.id)
	if a == null:
		return
	now = host.tick_count / float(K.TICK_HZ)
	match kind:
		CombatCodec.Msg.ATTACK:
			var d := CombatCodec.read_attack(data)
			if d.is_empty():
				return
			_set_lead(a, d["clock"])
			if not start_attack(e, -1, d["aim"], d["throw"]):
				a.last_refusal = _attack_refusal(a)
				host.send_sys(sys_id(), CombatCodec.Msg.REFUSED, CombatCodec.refused(kind, a.last_refusal), e.id)
		CombatCodec.Msg.CAST:
			var d := CombatCodec.read_cast(data)
			if d.is_empty():
				return
			_set_lead(a, d["clock"])
			a.last_refusal = cast(e, d["slug"], d["level"], d["aim"])
			if a.last_refusal != "":
				host.send_sys(sys_id(), CombatCodec.Msg.REFUSED, CombatCodec.refused(kind, a.last_refusal), e.id)
		CombatCodec.Msg.CANCEL:
			cancel(e)
		CombatCodec.Msg.ROLL:
			var d := CombatCodec.read_roll(data)
			if d.is_empty():
				return
			_set_lead(a, d["clock"])
			a.last_refusal = start_roll(e)
			if a.last_refusal != "":
				host.send_sys(sys_id(), CombatCodec.Msg.REFUSED, CombatCodec.refused(kind, a.last_refusal), e.id)

## Why an attack intent was refused, in a few words for the HUD.
func _attack_refusal(a: Actor) -> String:
	var e := a.e
	if e.combatant == null or is_downed(e) or a.downed_at >= 0.0:
		return "you are down"
	if not e.combatant.can_act():
		return "you cannot act"
	if not a.seq.is_empty() or now < a.action_ready - 1e-6:
		return "busy"
	if _rolling(a):
		return "rolling"
	return "not now"

func _set_lead(a: Actor, clock: float) -> void:
	if clock < 0.0:
		return
	var aim := CombatTempo.section("aim")
	# now - clock is the snapshot's trip plus the intent's (minus the client clock's own bias)
	var l := clampf((now - clock + float(aim.get("clock_bias_s", 0.025))) * 0.5 + 0.5 / K.TICK_HZ, 0.0, float(aim.get("max_lead_s", 0.25)))
	a.lead = l if a.lead <= 0.0 else lerpf(a.lead, l, 0.5)

# --- tick ---------------------------------------------------------------------------------

func tick(_h: WorldHost) -> void:
	now = host.tick_count / float(K.TICK_HZ)
	_all = []
	for a: Actor in actors.values():
		if a.e.combatant != null:
			_all.append(a.e.combatant)
	var gone: Array[Actor] = []
	for a: Actor in actors.values():
		_step_brainless(a)
		if a.e.combatant == null:
			continue
		if a.e.is_player() and cond_mask(a.e.combatant) != a.cond_mask:
			_touched[a.e.id] = true      # conditions changed outside combat (rules: down, up): tell the owner
		_fall(a)
		_burn(a)
		_round(a)
		_prone(a)
		_sequence(a)
		if _expire(a):
			gone.append(a)
	_step_projectiles()
	_step_timers()
	for a in gone:
		_remove_dead(a)
	_diff_touched()
	_send_status()
	_flush()

## SRD monsters with no brain still fall and can be shoved (the host only steps bodies
## with a brain): one empty input through the same controller.
func _step_brainless(a: Actor) -> void:
	var e := a.e
	if e.is_player() or e.brain != null or e.owner != HostEntity.NO_OWNER:
		return
	var inp := filter_input(e, PlayerInput.new())
	var step_dt := 1.0 / MoveStats.step_hz()
	for i in maxi(1, MoveStats.step_hz() / K.TICK_HZ):
		PlayerController.step(host.world, e.body, inp, e.stats, step_dt)
	e.flags = HostEntity.body_flags(e.body)

## Fall damage: the net drop from the last footing (floor, ladder, water, wall, flight)
## to the landing, in feet; SRD 1d6 per 10 ft at most 20d6, but gentler: nothing up to free_ft
## (20), and the roll times damage_mult (0.5). Players'
## bodies are the host's copy from accepted states (flags carry on_floor and modes).
func _fall(a: Actor) -> void:
	var b := a.e.body
	var footed := b.on_floor or b.climbing or b.swimming or b.clinging or b.flying or b.in_liquid > 0.3
	if footed:
		if not a.footed and b.on_floor and not b.swimming:
			var ft := (a.takeoff_y - b.pos.y) * K.TILE_FT
			_fall_damage(a, ft)
		a.takeoff_y = b.pos.y
	a.footed = footed

func _fall_damage(a: Actor, ft: float) -> void:
	var f := CombatTempo.section("fall")
	if ft <= float(f.get("free_ft", 20.0)):
		return
	var dice := mini(floori(ft / float(f.get("ft_per_die", 10.0))), int(f.get("max_dice", 20)))
	if dice < 1:
		return
	# Featherfall and fall-resist gear take a share off (1.0: no fall damage)
	var resist := clampf(_tag(a.e, "fall_resist"), 0.0, 1.0)
	if resist >= 1.0:
		return
	var amount := floori(Dice.roll_nd(dice, 6) * float(f.get("damage_mult", 0.5)) * (1.0 - resist))
	if amount > 0:
		damage(0, a.e, amount, SRD.DamageType.BLUDGEONING, {"what": "fall"})

## Lava (TileDefs.burn): a body whose box touches it takes fire damage at once, then again every
## every_s while it stays (data/combat.json lava: 2d6 fire a round, the SRD's fire damage, so
## resistance and immunity apply through take_damage).
func _burn(a: Actor) -> void:
	if not touches_lava(host.world, a.e.body):
		a.burn_at = -1.0
		return
	if a.burn_at >= 0.0 and now < a.burn_at - 1e-6:
		return
	var d := CombatTempo.section("lava")
	a.burn_at = now + float(d.get("every_s", K.ROUND_SECONDS))
	var amount := Dice.roll_nd(int(d.get("dice", 2)), int(d.get("sides", 6)))
	damage(0, a.e, amount, String(d.get("type", "fire")), {"what": "lava"})

## Does any cell under the body's box hold lava?
static func touches_lava(world: TileWorld, b: Body) -> bool:
	var burn := TileDefs.burn
	for y in range(floori(b.pos.y + 0.01), ceili(b.top() - 0.01)):
		for x in range(floori(b.left() + 0.01), ceili(b.right() - 0.01)):
			var id := world.get_fg(x, y)
			if id < burn.size() and burn[id] != 0:
				return true
	return false

## Every ROUND_SECONDS of a creature's own round clock: the end of its turn and the start
## of the next (effects expire, repeat saves, once-per-turn features reset, recharges).
func _round(a: Actor) -> void:
	if a.round_at < 0.0 or now < a.round_at - 1e-6:
		return
	a.round_at = maxf(a.round_at + K.ROUND_SECONDS, now + 1e-3)
	var c := a.e.combatant
	for ev: Dictionary in SRDEffects.turn_ended(_all, c):
		var tid := _id_of_name(String(ev.get("target", "")))
		_emit(Ev.SAVE, _id_of_name(String(ev.get("source", ""))), tid, {"dc": ev.get("dc", 0), "saved": ev.get("saved", false),
			"what": String(ev.get("effect", ""))})
	SRDEffects.turn_started(_all, c)
	if not a.e.is_player():
		MonsterSpells.recharge(c)
		MonsterActions.start_turn(c)
	for b: Actor in actors.values():
		if b.e.combatant != null and (b.cond_mask != 0 or not b.effect_ids.is_empty() or not b.e.combatant.effects.all().is_empty()):
			_touched[b.e.id] = true

func _start_clock(a: Actor) -> void:
	if a.round_at >= 0.0 or a.e.combatant == null:
		return
	a.round_at = now + K.ROUND_SECONDS
	a.e.combatant.turn_flags.clear()
	a.e.combatant.action_economy.reset_turn()
	a.e.combatant.action_economy.reset_reaction()

## Prone: the creature stands after prone_stand_s (standing costs movement in the SRD).
func _prone(a: Actor) -> void:
	var c := a.e.combatant
	if not c.conditions.has(SRD.Condition.PRONE):
		a.prone_at = -1.0
		return
	if a.prone_at < 0.0:
		a.prone_at = now
		return
	var held_by_effect := c.effects.of_type("condition").any(func(x: Dictionary) -> bool: return String(x.get("condition", "")) == "prone")
	if now - a.prone_at >= float(CombatTempo.section("conditions").get("prone_stand_s", 1.0)) and c.can_act() \
			and not held_by_effect and not c.conditions.has(SRD.Condition.UNCONSCIOUS):
		c.conditions.remove(SRD.Condition.PRONE)
		a.prone_at = -1.0
		_touched[a.e.id] = true

func _sequence(a: Actor) -> void:
	var s := a.seq
	if s.is_empty():
		return
	if not can_act(a.e):
		_end_seq(a, true)
		return
	var t := now - float(s["t0"])
	var contacts: Array = s["contacts"]
	while int(s["idx"]) < contacts.size() and t >= float(contacts[int(s["idx"])]) - 1e-6:
		var i := int(s["idx"])
		s["idx"] = i + 1
		counts["contacts"] += 1
		_contact(a, s, i)
		if a.seq.is_empty():
			return
	if t >= float(s["total"]) - 1e-6:
		_end_seq(a, false)

func _end_seq(a: Actor, canceled: bool) -> void:
	if canceled and not a.seq.is_empty():
		_emit(Ev.CANCEL, a.e.id, 0, {})
	a.seq = {}
	_touched[a.e.id] = true       # movement limits during a swing or cast end with it

## Monster corpses go after their linger; downed players without a rules system respawn.
## Returns true when the actor should be removed.
func _expire(a: Actor) -> bool:
	var c := a.e.combatant
	if a.e.is_player():
		if a.downed_at >= 0.0 and c.current_hp > 0:
			a.downed_at = -1.0
			_touched[a.e.id] = true     # movement limits lift with it
		if a.downed_at >= 0.0 and not _rules_has("player_dropped") \
				and now - a.downed_at >= float(CombatTempo.section("death").get("player_respawn_s", 3.0)):
			c.stats.current_hp = c.stats.max_hp
			c.death_saves.revive()
			c.conditions.clear_all()
			a.downed_at = -1.0
			_place(a, host.spawn)
			_emit(Ev.HEAL, 0, a.e.id, {"amount": c.stats.max_hp, "hp": c.current_hp})
			_touched[a.e.id] = true
		return false
	return a.dead_at >= 0.0 and now - a.dead_at >= float(CombatTempo.section("death").get("monster_linger_s", 1.5))

func _remove_dead(a: Actor) -> void:
	if not host.entities.has(a.e.id):
		return
	var rules := host.system(HostSystem.RULES)
	if rules != null and rules.has_method("on_kill"):
		rules.call("on_kill", a.e, a.killers)
	var items := host.system(HostSystem.ITEMS)
	if items != null and items.has_method("on_kill"):
		items.call("on_kill", a.e)
	host.remove_entity(a.e.id)

## A summed gear and spark tag of a player (items.tags: swing_recovery, cast_move,
## knockback_resist, fall_resist ...); 0 without the items system.
func _tag(e: HostEntity, name: String) -> float:
	if e == null or not e.is_player():
		return 0.0
	var items := host.system(HostSystem.ITEMS)
	if items == null or not items.has_method("tags"):
		return 0.0
	return float((items.call("tags", e) as Dictionary).get(name, 0.0))

func _rules_has(m: String) -> bool:
	var rules := host.system(HostSystem.RULES)
	return rules != null and rules.has_method(m)

# --- brain and system API -------------------------------------------------------------------

## Did e deal or take a blow within the last `s` seconds?
func fought_within(e: HostEntity, s: float) -> bool:
	var a: Actor = actors.get(e.id)
	return a != null and now - a.last_hostile <= s

func actor(e: HostEntity) -> Actor:
	return actors.get(e.id) if e != null else null

func can_act(e: HostEntity) -> bool:
	var a := actor(e)
	if a == null or e.combatant == null or a.dead_at >= 0.0 or a.downed_at >= 0.0:
		return false
	if e.combatant.current_hp <= 0 or not e.combatant.can_act():
		return false
	return not is_downed(e)

func is_downed(e: HostEntity) -> bool:
	var a := actor(e)
	if a != null and a.downed_at >= 0.0:
		return true
	var rules := host.system(HostSystem.RULES)
	return rules != null and rules.has_method("is_downed") and bool(rules.call("is_downed", e))

func busy(e: HostEntity) -> bool:
	var a := actor(e)
	return a != null and (not a.seq.is_empty() or now < a.action_ready - 1e-6)

func in_combat(e: HostEntity) -> bool:
	var a := actor(e)
	return a != null and now - a.last_hostile <= CombatTempo.num("in_combat_s", 5.0)

func actions_of(e: HostEntity) -> Array:
	var a := actor(e)
	return a.moves.get("actions", []) if a != null else []

## Who fights whom. With Life installed (HostSystem.LIFE) its stance decides (monsters fight
## guards, guards fight raiders, standing with factions); without it, monsters and players.
func hostile(x: HostEntity, y: HostEntity) -> bool:
	var life := _life_sys()
	if life != null:
		return bool(life.call("hostile", x, y))
	return x.is_player() != y.is_player()

var _life: HostSystem = null

func _life_sys() -> HostSystem:
	if _life == null:
		var h := host
		if h != null and h.systems.has(HostSystem.LIFE):
			_life = h.system(HostSystem.LIFE)
	return _life

## With Life: a player's attack aimed right at a creature it is not hostile to (a townsperson,
## a neutral beast) is allowed (Life then makes it and its faction hostile), except while the
## player is fighting foes (then a bystander under the aim is not hit). Areas and sweeps
## never hit FRIENDLY or NEUTRAL creatures. Without Life: never (nothing changes). A fight lasts
## as long as in_combat_s after the last blow traded with a foe or swung at one, so a swing still
## falling when its foe dies, by anyone's hand, does not make enemies of the guard beside it.
func _aimed(a: Actor, b: Actor, aim: Variant) -> bool:
	if _life_sys() == null or not a.e.is_player() or b.e.is_player() or not aim is Vector2 or aim == Vector2.INF:
		return false
	if not b.e.body.rect().grow(0.5).has_point(aim):
		return false
	# in the middle of a fight a blow that lands on a bystander is a miss, not a choice
	if now - a.last_foe <= CombatTempo.num("in_combat_s", 5.0) and not hostile(a.e, b.e):
		return false
	if now - a.last_hostile <= CombatTempo.num("in_combat_s", 5.0) and not hostile(a.e, b.e):
		var foes := false
		for o: Actor in actors.values():
			if o != a and _targetable(o) and hostile(a.e, o.e) and now - o.last_hostile <= CombatTempo.num("in_combat_s", 5.0):
				foes = true
				break
		if foes:
			return false
	# a foe at the aim point is what it was aimed at, not the bystander beside it
	return not _foe_at(a, aim)

## A foe at this point, or a few tiles off (a running foe, by the time a blow lands)?
func _foe_at(a: Actor, aim: Vector2) -> bool:
	for o: Actor in actors.values():
		if o != a and _targetable(o) and o.e.body.rect().grow(3.0).has_point(aim) and hostile(a.e, o.e):
			return true
	return false

func _targetable(b: Actor) -> bool:
	return b.e.combatant != null and b.dead_at < 0.0 and b.downed_at < 0.0 and b.e.combatant.current_hp > 0

## The host checks players' states against the same limits their client applies from STATUS
## (WorldHost.move_limits): conditions, speed effects, downed.
func move_limits(_h: WorldHost, e: HostEntity) -> Dictionary:
	var a := actor(e)
	if a == null or not e.is_player() or (a.move_mult >= 1.0 and not a.no_jump and a.fear_src == 0):
		return {}
	var out := {"mult": a.move_mult, "no_jump": a.no_jump}
	var src := host.entity(a.fear_src) if a.fear_src != 0 else null
	if src != null:
		out["fear"] = src.body.pos
	return out

## Alive (downed counts, dead does not): a target for spells on allies.
func _helpable(b: Actor) -> bool:
	if b.e.combatant == null or b.dead_at >= 0.0 or b.e.combatant.death_saves.is_dead:
		return false
	return not (_rules_has("is_dead") and bool(host.system(HostSystem.RULES).call("is_dead", b.e)))

## Brains feed their input through this (players: CombatClient.filter_input does the same
## from STATUS): speed 0 holds still, Prone crawls, Frightened cannot step toward the source.
func filter_input(e: HostEntity, inp: PlayerInput) -> PlayerInput:
	var a := actor(e)
	if a == null:
		return inp
	return CombatSystem.apply_limits(inp, a.move_mult, a.no_jump, e.body.pos,
		host.entity(a.fear_src).body.pos if a.fear_src != 0 and host.entity(a.fear_src) != null else Vector2.INF)

## Shared by the host and the client: scale move_x, drop jumps, refuse steps toward `fear`.
static func apply_limits(inp: PlayerInput, mult: float, no_jump: bool, pos: Vector2, fear: Vector2) -> PlayerInput:
	if mult < 1.0:
		inp.move_x = inp.move_x * mult
		if mult <= 0.0:
			inp.up = false
			inp.down = false
	if no_jump:
		inp.jump = false
		inp.jump_pressed = false
	if fear != Vector2.INF and inp.move_x != 0.0 and signf(inp.move_x) == signf(fear.x - pos.x):
		inp.move_x = 0.0
	return inp

## The nearest hostile creature `e` can see within max_tiles, or null.
func nearest_foe(e: HostEntity, max_tiles: float) -> HostEntity:
	var best: HostEntity = null
	var bd := max_tiles
	for b: Actor in actors.values():
		if b.e == e or not hostile(e, b.e) or not _targetable(b):
			continue
		var d := b.e.body.pos.distance_to(e.body.pos)
		if d <= bd and sight.can_see(e, b.e):
			bd = d
			best = b.e
	return best

## Hostile creatures the given action (or the default / Multiattack's first) could touch now,
## ignoring facing: melee within reach, ranged within normal range; line of sight needed.
func targets_in_reach(e: HostEntity, action := -1) -> Array[HostEntity]:
	var out: Array[HostEntity] = []
	var a := actor(e)
	if a == null or e.combatant == null:
		return out
	var reach := K.ft(CombatTempo.reach_ft(host.srd, e.combatant.weapon))
	var rng := K.ft(CombatTempo.range_ft(host.srd, e.combatant.weapon).x) if e.combatant.weapon != null and e.combatant.weapon.is_ranged() else 0.0
	var act := _pick_action(a, action)
	if not act.is_empty():
		reach = K.ft(float(act.get("reach_ft", 5.0))) if act["kind"] != "ranged" else 0.0
		rng = K.ft(float(act.get("range_ft", 0.0))) if act["kind"] == "ranged" else 0.0
	var rect := e.body.rect()
	for b: Actor in actors.values():
		if b.e == e or not hostile(e, b.e) or not _targetable(b):
			continue
		var r := b.e.body.rect()
		var g := HitShapes.gap(rect, r)
		if (g <= reach + HitShapes.EPS or (rng > 0.0 and g <= rng)) and HitShapes.line_to(host.world, rect.get_center(), r):
			out.append(b.e)
	return out

func _pick_action(a: Actor, action: int) -> Dictionary:
	var acts: Array = a.moves.get("actions", [])
	if acts.is_empty():
		return {}
	if action >= 0 and action < acts.size():
		return acts[action]
	var multi: Array = a.moves.get("multi", [])
	if not multi.is_empty():
		return acts[int(multi[0])]
	var d := int(a.moves.get("default", -1))
	return acts[d] if d >= 0 else {}

## Start an Attack action: Extra Attack (players) or Multiattack (monsters, action -1) are
## combo swings inside it. aim: a point in tile units (INF: straight ahead). False when the
## creature cannot act, is mid-sequence or on cooldown, or the action is not ready.
## What e holds as others should see it, in SWING's `what` form: its weapon, or the names of the
## actions it would swing first. Goes out with ENT_ADD, so a body has its weapon before it swings.
func shown_wield(e: HostEntity) -> String:
	var a := actor(e)
	if a == null or e.combatant == null:
		return ""
	if a.moves.is_empty():
		var w := e.combatant.weapon
		return w.weapon_name if w != null else ""
	var acts: Array = a.moves.get("actions", [])
	var idxs: Array = a.moves.get("multi", [])
	if idxs.is_empty() and int(a.moves.get("default", -1)) >= 0:
		idxs = [int(a.moves["default"])]
	var names := PackedStringArray()
	for i: int in idxs:
		names.append(String(acts[i]["name"]))
	return ", ".join(names)

func start_attack(e: HostEntity, action := -1, aim := Vector2.INF, throw := false) -> bool:
	var a := actor(e)
	if a == null or not can_act(e) or not a.seq.is_empty() or now < a.action_ready - 1e-6 or _rolling(a):
		return false
	var c := e.combatant
	if aim == Vector2.INF or not (is_finite(aim.x) and is_finite(aim.y)):
		aim = e.body.rect().get_center() + Vector2(e.body.facing * 4.0, 0)
	var steps: Array = []
	var tempo := {}
	var mode: int = Mode.MELEE
	var what := ""
	var tempo_name := "monster"
	var reach_ft := 5.0
	if a.moves.is_empty():
		var w := c.weapon
		var props := CombatTempo.weapon_props(host.srd, w)
		var two := w != null and "versatile" in props and c.equipment.shield == null
		var ranged := w != null and w.is_ranged()
		var do_throw := throw and not ranged and CombatTempo.range_ft(host.srd, w).y > 0.0
		var cls := CombatTempo.weapon_class(host.srd, w, two, do_throw)
		var n := c.kit.attacks_per_action() if c.kit != null else 1
		for i in n:
			steps.append({"type": "ranged" if ranged or do_throw else "melee", "weapon": w, "two": two, "throw": do_throw, "cls": cls})
		tempo = CombatTempo.weapon_tempo(cls).duplicate()
		# Quickhand and swing-recovery affixes: a shorter recovery after the swing (the wind-up
		# and every roll stay as they are)
		var quick := clampf(_tag(e, "swing_recovery"), 0.0, float(CombatTempo.section("tags").get("swing_recovery_max", 0.5)))
		tempo["recovery"] = float(tempo.get("recovery", 0.4)) * (1.0 - quick)
		mode = Mode.THROW if do_throw else (Mode.RANGED if ranged else Mode.MELEE)
		what = w.weapon_name if w != null else "Unarmed Strike"
		tempo_name = cls
		reach_ft = CombatTempo.reach_ft(host.srd, w)
	else:
		var acts: Array = a.moves.get("actions", [])
		var idxs: Array = []
		if action >= 0:
			if action >= acts.size():
				return false
			idxs = [action]
		elif not (a.moves.get("multi", []) as Array).is_empty():
			idxs = a.moves["multi"]
		elif int(a.moves.get("default", -1)) >= 0:
			idxs = [int(a.moves["default"])]
		else:
			return false
		var names := PackedStringArray()
		tempo = CombatTempo.weapon_tempo("monster").duplicate()
		for i: int in idxs:
			var act: Dictionary = acts[i]
			names.append(String(act["name"]))
			if act["kind"] == "save":
				if not MonsterSpells.save_action_ready(c, act["save"]):
					return false
				steps.append({"type": "save", "act": act})
				mode = Mode.SAVE_ACTION
				tempo["windup"] = float(CombatTempo.section("cast").get("breath_windup", 0.8))
			else:
				steps.append({"type": act["kind"], "act": act, "weapon": act["weapon"], "cls": "monster"})
				reach_ft = maxf(reach_ft, float(act.get("reach_ft", 5.0)))
				if act["kind"] == "ranged":
					mode = Mode.RANGED
		what = ", ".join(names)
	var tl := CombatTempo.timeline(tempo, steps.size())
	if a.pace != 1.0 and a.pace > 0.0:
		tl = _paced(tl, a.pace)
	a.seq = {"kind": "attack", "t0": now, "contacts": tl["contacts"], "total": tl["total"], "idx": 0,
		"steps": steps, "aim": aim, "sweep": int(tempo.get("sweep", 0))}
	a.action_ready = now + float(tl["total"])
	a.last_hostile = now
	if e.is_player() and _foe_at(a, aim):
		a.last_foe = now
	_touched[e.id] = true
	_start_clock(a)
	counts["swings"] += 1
	var cs: Array = tl["contacts"]
	_emit(Ev.SWING, e.id, 0, {"mode": mode, "swings": steps.size(), "windup": tl["windup"], "total": tl["total"],
		"gap": float(cs[1]) - float(cs[0]) if cs.size() > 1 else 0.0, "tempo": tempo_name, "reach_ft": reach_ft,
		"aim": aim, "what": what})
	return true

## Legendary Actions (the addon's MonsterActions, from the stat block): between its own actions a
## creature with uses left takes one at a time, at most one every legendary.gap_s (data/combat.json),
## out of its action economy: an attack option swings that action at the foe (the aboleth's Lash: one
## Tentacle), an action option uses it (Psychic Drain: Consume Memories, and it heals). Uses come back
## at the start of its round (MonsterActions.start_turn in _round); a lair creature (meta in_lair) has
## its lair's count. Psychic Drain is taken first while hurt. True when one was taken.
func legendary(e: HostEntity, foe: HostEntity) -> bool:
	var a := actor(e)
	var c := e.combatant
	if a == null or c == null or c.legendary.is_empty() or not a.seq.is_empty() or not can_act(e) or foe == null:
		return false
	if now < a.legendary_ready - 1e-6 or now >= a.action_ready - 1e-6:
		return false        # its own action is ready: that comes first
	var in_lair := bool(e.get_meta("in_lair", false))
	var ctx := {"charmed_or_grappled": holds_any(e)}
	var opts: Array = (c.legendary.get("options", []) as Array).duplicate()
	if c.current_hp < c.stats.max_hp:
		opts.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return String(x.get("heal", "")) != "" and String(y.get("heal", "")) == "")
	var acts: Array = a.moves.get("actions", [])
	var aim := foe.body.rect().get_center()
	for opt: Dictionary in opts:
		if not MonsterActions.legendary_available(c, opt, in_lair, ctx):
			continue
		var idx := -1
		for i in acts.size():
			if String(acts[i]["name"]) == String(opt.get("action", "")):
				idx = i
		if idx < 0 or not foe in targets_in_reach(e, idx):
			continue
		var saved := a.action_ready
		a.action_ready = now
		var ok := start_attack(e, idx, aim)
		a.action_ready = saved
		if not ok:
			continue
		var ev := MonsterActions.use_legendary(c, opt, in_lair, ctx)
		if int(ev.get("heal", 0)) > 0:
			_emit(Ev.HEAL, e.id, e.id, {"amount": int(ev["heal"]), "hp": c.current_hp})
		a.legendary_ready = now + float(CombatTempo.section("legendary").get("gap_s", 2.0))
		counts["legendary"] = int(counts.get("legendary", 0)) + 1
		return true
	return false

## Does e hold anyone: a creature Charmed or Grappled with e as the source of the condition?
func holds_any(e: HostEntity) -> bool:
	if e.combatant == null:
		return false
	var me := e.combatant.name
	for b: Actor in actors.values():
		if b.e == e or b.e.combatant == null or b.dead_at >= 0.0:
			continue
		for eff: Dictionary in b.e.combatant.effects.of_type("condition"):
			if String(eff.get("source", "")) == me and String(eff.get("condition", "")) in ["charmed", "grappled"]:
				return true
	return false

## Hidden (the SRD's Hide: the Invisible condition, which ends when it makes an attack roll): a
## lurker waiting in the dark. Clients hear it as a CONDITION event.
func set_hidden(e: HostEntity, on: bool) -> void:
	var c := e.combatant
	if c == null or c.effects.has_id("hidden") == on:
		return
	if on:
		c.effects.add({"id": "hidden", "type": "condition", "condition": "invisible", "source": c.name, "of": c.name,
			"ends_on_attack": true})
	else:
		c.effects.remove_id("hidden")
	_touched[e.id] = true

func is_hidden(e: HostEntity) -> bool:
	return e.combatant != null and e.combatant.effects.has_id("hidden")

## A client that has just begun to see e hears at once if it is Invisible: CONDITION events go only
## to who watched it change (HostEndpoint, with ENT_ADD).
func tell_unseen(e: HostEntity, to: int) -> void:
	if e.combatant != null and e.combatant.conditions.has(SRD.Condition.INVISIBLE):
		var ev := {"kind": Ev.CONDITION, "src": 0, "dst": e.id, "cond": SRD.Condition.INVISIBLE, "on": true}
		host.send_sys(sys_id(), CombatCodec.Msg.EVENTS, CombatCodec.events(host.tick_count, [ev]), to)

## Faster (pace > 1) or slower actions: the wind-up (the readable telegraph) is kept, what
## comes after it (follow-up contacts, recovery) is divided by pace. Used by the Monsters
## track's Frenzied affix through set_pace.
static func _paced(tl: Dictionary, pace: float) -> Dictionary:
	var w := float(tl["windup"])
	var out := tl.duplicate()
	var cs: Array = []
	for c: float in tl["contacts"]:
		cs.append(w + (c - w) / pace)
	out["contacts"] = cs
	out["total"] = w + (float(tl["total"]) - w) / pace
	return out

func set_pace(e: HostEntity, mult: float) -> void:
	var a := actor(e)
	if a != null:
		a.pace = maxf(mult, 0.1)

## Stop a sequence still in its wind-up (nothing has rolled): the action is not spent.
func cancel(e: HostEntity) -> void:
	var a := actor(e)
	if a == null or a.seq.is_empty() or int(a.seq["idx"]) > 0:
		return
	if String(a.seq.get("casting", "")) == "bonus_action":
		a.bonus_ready = now
	a.action_ready = now
	_end_seq(a, true)

## A player's body started a dodge roll: its client predicted it and says so. The host keeps
## the roll's clock from the moment the client pressed (now less the one-way delay), so the
## tuck falls where the player saw it. A wind-up is cancelled (nothing rolled, the action is
## not spent); once a contact has begun the swing is committed and the roll is refused. "" = ok.
func start_roll(e: HostEntity) -> String:
	var a := actor(e)
	if a == null or not e.is_player():
		return "no body"
	if not can_act(e):
		return "you cannot act"
	if a.move_mult < 1.0:
		return "you cannot roll"
	if not a.seq.is_empty() and int(a.seq["idx"]) > 0:
		return "swing committed"
	if now < a.roll_ready - float(Dodge.conf().get("host_slack_s", 0.12)):
		return "dodge not ready"
	if not a.seq.is_empty():
		cancel(e)
	a.roll_t0 = now - a.lead
	a.roll_ready = a.roll_t0 + Dodge.cooldown()
	_emit(Ev.ROLL, e.id, 0, {"duration": Dodge.duration()})
	return ""

## Still rolling, past the slack a packet's jitter needs?
func _rolling(a: Actor) -> bool:
	return now < a.roll_t0 + Dodge.duration() - float(Dodge.conf().get("host_slack_s", 0.12))

## The box a blow must touch: the body's, or its tuck in the middle of a roll.
func hurt_box(e: HostEntity) -> Rect2:
	var a := actor(e)
	if a == null or a.roll_t0 < -1.0:
		return e.body.rect()
	return Dodge.hurt_rect(e.body.rect(), now - a.roll_t0)

## Damage from anything (traps, falls, effects): through the addon's take_damage, so
## resistances, immunities, temporary hit points and Concentration apply. dtype: an
## SRD.DamageType or its name. Returns the hit points lost.
func damage(src_id: int, dst: HostEntity, amount: int, dtype: Variant, opts := {}) -> int:
	var b := actor(dst)
	if b == null or dst.combatant == null or amount <= 0 or b.dead_at >= 0.0:
		return 0
	var t: int = SRDContent.damage_type_from(String(dtype)) if dtype is String else int(dtype)
	var dealt := dst.combatant.take_damage(amount, t as SRD.DamageType, bool(opts.get("crit", false)))
	_emit(Ev.DAMAGE, src_id, dst.id, {"amount": dealt, "dtype": t, "hp": dst.combatant.current_hp})
	_after_damage(b, dealt, src_id, bool(opts.get("crit", false)))
	return dealt

# --- contacts ---------------------------------------------------------------------------------

func _rect(a: Actor) -> Rect2:
	var r := a.e.body.rect()
	if a.e.is_player() and a.lead > 0.0:
		r.position += (a.e.body.vel * a.lead).limit_length(float(CombatTempo.section("aim").get("max_lead_tiles", 2.5)))
	return r

func _contact(a: Actor, s: Dictionary, i: int) -> void:
	var step: Dictionary = s["steps"][i]
	var c := a.e.combatant
	if step.has("act") and step["act"].has("weapon"):
		c.weapon = step["act"]["weapon"]
		c.hit_riders = step["act"]["riders"]
	match String(step["type"]):
		"melee":
			_melee(a, s, step)
		"ranged":
			_launch_weapon(a, s, step)
		"save":
			_save_action(a, s, step)
		"spell":
			_cast_now(a, s["ab"], int(s["level"]), s["aim"])

## Is a blow's way clear? From the middle of the body or from its shoulders: a creature on a
## ledge or stair above the chest is still in reach of the arm over the edge.
func _melee_from(center: Vector2, rect: Rect2, r: Rect2) -> Vector2:
	return center if HitShapes.line_to(host.world, center, r) else Vector2(center.x, rect.end.y - 0.3)

func _melee_line(center: Vector2, rect: Rect2, r: Rect2) -> bool:
	return HitShapes.line_to(host.world, center, r) \
		or HitShapes.line_to(host.world, Vector2(center.x, rect.end.y - 0.3), r)

func _melee(a: Actor, s: Dictionary, step: Dictionary) -> void:
	var c := a.e.combatant
	var rect := _rect(a)
	var center := rect.get_center()
	var dir := HitShapes.aim_dir(center, s["aim"], a.e.body.facing)
	var reach := K.ft(float(step["act"]["reach_ft"])) if step.has("act") else K.ft(CombatTempo.reach_ft(host.srd, c.weapon))
	var half := float(CombatTempo.section("melee").get("arc_half_angle_deg", 70.0))
	var touched: Array = []
	var under := 0
	for b: Actor in actors.values():
		if b == a or not _targetable(b):
			continue
		var foe := hostile(a.e, b.e)
		if not foe and not _aimed(a, b, s["aim"]):
			continue
		var r := hurt_box(b.e)
		if HitShapes.in_arc(rect, dir, reach, half, r) and _melee_line(center, rect, r):
			if r != b.e.body.rect() and Dodge.under_blow(r, rect, Vector2(s["aim"]).y):
				under = b.e.id
				continue
			touched.append([HitShapes.gap(rect, r), r.get_center().distance_to(s["aim"]), b, foe])
	if touched.is_empty():
		counts["whiffs"] += 1
		_emit(Ev.WHIFF, a.e.id, under, {})
		return
	touched.sort_custom(func(x: Array, y: Array) -> bool: return HitShapes.nearer_touch(x[3], x[0], x[1], y[3], y[0], y[1]))
	var primary: Actor = touched[0][2]
	var opts := {"two_handed": bool(step.get("two", false))}
	var ev := _weapon_attack(a, primary, opts, _melee_from(center, rect, primary.e.body.rect()))
	# cleave and sweeps touch foes only (with Life: never a friendly or neutral bystander)
	var rest: Array = touched.slice(1).filter(func(x: Array) -> bool: return x[3]).map(func(x: Array) -> Actor: return x[2])
	# Cleave (mastery): one more full attack, once per turn, on a creature within 5 ft of the first.
	if ev.get("cleave_available", false):
		for b: Actor in rest:
			if HitShapes.gap(primary.e.body.rect(), b.e.body.rect()) <= _within5() + HitShapes.EPS and b.e.combatant.current_hp > 0:
				_weapon_attack(a, b, {"two_handed": opts["two_handed"], "cleave": true}, _melee_from(center, rect, b.e.body.rect()))
				rest.erase(b)
				break
	for k in mini(int(s.get("sweep", 0)), rest.size()):
		_sweep(a, rest[k], step, center)

func _within5() -> float:
	return float(CombatTempo.section("melee").get("within_5ft_tiles", 2.0))

## One SRD weapon attack against a touched target, with the positional facts. {} if the
## target has full cover (nothing rolls).
func _weapon_attack(a: Actor, b: Actor, opts_in: Dictionary, from: Vector2) -> Dictionary:
	var c := a.e.combatant
	var t := b.e.combatant
	var opts := opts_in.duplicate()
	var r := b.e.body.rect()
	opts["within_5ft"] = HitShapes.gap(_rect(a), r) <= _within5() + HitShapes.EPS
	var cov := HitShapes.cover(host.world, from, r)
	if cov == SRD.Cover.FULL:
		return {}
	opts["cover"] = cov
	_sight_opts(a, b, opts)
	if not opts.has("ally_adjacent"):
		opts["ally_adjacent"] = _ally_near(a, b)
	var ev := AttackResolver.weapon_attack(c, t, opts)
	counts["rolls"] += 1
	_engage(a, b)
	var total := int(ev.get("d20", 0)) + int(ev.get("attack_bonus", 0)) + int(ev.get("bonus_dice", 0))
	_emit(Ev.CRIT if ev.get("crit", false) else (Ev.HIT if ev.get("hit", false) else Ev.MISS), a.e.id, b.e.id,
		{"d20": ev.get("d20", 0), "total_roll": total, "ac": ev.get("target_ac", 0)})
	var dealt := int(ev.get("damage_dealt", 0))
	if dealt > 0:
		_emit(Ev.DAMAGE, a.e.id, b.e.id, {"amount": dealt, "dtype": c.weapon.damage_type if c.weapon != null else SRD.DamageType.BLUDGEONING,
			"hp": t.current_hp})
	if ev.has("push_feet"):
		_push(b, from, int(ev["push_feet"]))
	_after_damage(b, dealt, a.e.id, bool(ev.get("crit", false)))
	return ev

## A sweep: the same arc grazing another creature. An attack roll (no crit doubling), and on
## a hit half the weapon's dice, no ability modifier (data: sweep.damage_fraction).
func _sweep(a: Actor, b: Actor, step: Dictionary, from: Vector2) -> void:
	var c := a.e.combatant
	var t := b.e.combatant
	var cov := HitShapes.cover(host.world, from, b.e.body.rect())
	if cov == SRD.Cover.FULL:
		return
	var d20 := Dice.roll_d20()
	var bonus := c.attack_modifier()
	var ac := t.armor_class + SRDRules.cover_ac_bonus(cov)
	var hit := d20 == 20 or (d20 != 1 and d20 + bonus >= ac)
	counts["rolls"] += 1
	_engage(a, b)
	_emit(Ev.HIT if hit else Ev.MISS, a.e.id, b.e.id, {"d20": d20, "total_roll": d20 + bonus, "ac": ac})
	if not hit:
		return
	var w := c.weapon
	var dice := 1
	var dtype := SRD.DamageType.BLUDGEONING
	if w != null:
		var two := bool(step.get("two", false)) and w.versatile_die_count > 0
		dice = Dice.roll_nd(w.versatile_die_count if two else w.die_count, w.versatile_die_sides if two else w.die_sides)
		dtype = w.damage_type
	var dmg := maxi(1, floori(dice * float(CombatTempo.section("sweep").get("damage_fraction", 0.5))))
	var dealt := t.take_damage(dmg, dtype)
	_emit(Ev.DAMAGE, a.e.id, b.e.id, {"amount": dealt, "dtype": dtype, "hp": t.current_hp})
	_after_damage(b, dealt, a.e.id)

func _engage(a: Actor, b: Actor) -> void:
	a.last_hostile = now
	b.last_hostile = now
	if hostile(a.e, b.e):
		a.last_foe = now
		b.last_foe = now
	_start_clock(a)
	_start_clock(b)
	_touched[a.e.id] = true
	_touched[b.e.id] = true

## Unseen target: Disadvantage; unseen attacker: Advantage (light, Darkvision, sight lines).
func _sight_opts(a: Actor, b: Actor, opts: Dictionary) -> void:
	if not sight.can_see(a.e, b.e):
		opts["disadvantage"] = true
	if sight.sun_shy(a.e) and sight.in_sunlight(CombatSight.eye(a.e)):
		opts["disadvantage"] = true       # Sunlight Sensitivity
	if not sight.can_see(b.e, a.e):
		opts["advantage"] = true

func _ally_near(a: Actor, b: Actor) -> bool:
	var r := b.e.body.rect()
	for o: Actor in actors.values():
		if o == a or o == b or hostile(o.e, a.e) or not _targetable(o) or not o.e.combatant.can_act():
			continue
		if HitShapes.gap(o.e.body.rect(), r) <= _within5() + HitShapes.EPS:
			return true
	return false

## A hostile, active creature within 5 ft (ranged attacks then have Disadvantage).
func _foe_adjacent(a: Actor) -> bool:
	var r := _rect(a)
	for o: Actor in actors.values():
		if hostile(o.e, a.e) and _targetable(o) and o.e.combatant.can_act() \
				and HitShapes.gap(o.e.body.rect(), r) <= _within5() + HitShapes.EPS:
			return true
	return false

func _after_damage(b: Actor, dealt: int, src: int, crit := false) -> void:
	var c := b.e.combatant
	# Other systems hear of every hit taken (and of misses: dealt 0) before the 0 HP check, so
	# they may still change hit points (Monsters: wards, tethers, minions, thorns, provocation).
	for sys: HostSystem in host.systems.values():
		if sys != self and sys.has_method("on_combat_damage"):
			sys.call("on_combat_damage", b.e, dealt, src)
	if dealt > 0:
		b.last_hostile = now
		_touched[b.e.id] = true
		_start_clock(b)
		if src > 0 and not src in b.killers:
			b.killers.append(src)
		if b.conc.is_concentrating:
			var was := b.conc.active_ability.spell_id
			if not b.conc.damage_concentration_check(dealt):
				_emit(Ev.EFFECT, src, b.e.id, {"on": false, "what": "concentration:" + was})
	if c.current_hp <= 0:
		_drop(b, src, dealt, crit)

## 0 hit points: monsters die (DEATH, removed after a linger, then on_kill hooks); players
## are downed (DOWNED, then rules.player_dropped, or the fallback respawn). A hit that lands
## on a player already down is a failed death save (two on a critical hit): player_dropped
## again with the crit flag.
func _drop(b: Actor, src: int, dealt := 0, crit := false) -> void:
	if b.e.is_player():
		if b.downed_at >= 0.0 or (_rules_has("is_downed") and is_downed(b.e)):
			if dealt > 0 and _rules_has("player_dropped"):
				host.system(HostSystem.RULES).call("player_dropped", b.e, crit)
			return
		b.downed_at = now
		b.seq = {}
		b.conc.end()
		_emit(Ev.DOWNED, src, b.e.id, {})
		if _rules_has("player_dropped"):
			host.system(HostSystem.RULES).call("player_dropped", b.e)
		return
	if b.dead_at >= 0.0:
		return
	b.dead_at = now
	b.seq = {}
	b.conc.end()
	b.e.brain = null
	_emit(Ev.DEATH, src, b.e.id, {})

## Move a body (push, respawn). Monsters move at once; a player's client gets the host's
## position through the existing CORRECT path (new epoch), as a refused state would.
func _place(a: Actor, pos: Vector2) -> void:
	host.teleport(a.e, pos)
	a.takeoff_y = a.e.body.pos.y
	a.footed = true

## Push (Thunderwave, the Push mastery): a horizontal shove away from `from`, swept against
## tiles. Monsters are moved here; a player's client sweeps its own body on the PUSH event.
func _push(b: Actor, from: Vector2, feet: int) -> void:
	var tiles := feet / 5.0 * CombatTempo.num("push_tiles_per_5ft", 2.0)
	tiles *= 1.0 - clampf(_tag(b.e, "knockback_resist"), 0.0, 1.0)     # Surefoot
	if tiles <= 0.0:
		return
	var dx := signf(b.e.body.rect().get_center().x - from.x)
	if dx == 0.0:
		dx = 1.0
	var d := Vector2(dx * tiles, 0.0)
	_emit(Ev.PUSH, 0, b.e.id, {"push": d})
	if b.e.is_player():
		return
	var v := b.e.body.vel
	b.e.body.vel = d
	TileCollision.move(host.world, b.e.body, 1.0)
	b.e.body.vel = Vector2(0.0, minf(v.y, 0.0))

# --- projectiles --------------------------------------------------------------------------------

func _launch_weapon(a: Actor, s: Dictionary, step: Dictionary) -> void:
	var c := a.e.combatant
	var w: WeaponData = step.get("weapon")
	var kind := "arrow"
	var rng := Vector2.ZERO
	if step.has("act"):
		rng = Vector2(float(step["act"].get("range_ft", 80.0)), float(step["act"].get("range_long_ft", 320.0)))
	else:
		kind = CombatTempo.projectile_kind(host.srd, w, bool(step.get("throw", false)))
		rng = CombatTempo.range_ft(host.srd, w)
	var opts := {}
	if _foe_adjacent(a):
		opts["disadvantage"] = true
	_spawn(a, kind, s["aim"], {"weapon": w, "riders": c.hit_riders, "opts": opts,
		"normal": K.ft(rng.x), "max": K.ft(maxf(rng.y, rng.x))})

## A projectile from the attacker's centre toward `aim` (lobbed to pass through it).
func _spawn(a: Actor, kind: String, aim: Vector2, extra: Dictionary) -> Dictionary:
	var row: Dictionary = CombatTempo.section("projectiles").get(kind, {"speed": 40.0, "gravity": 0.0})
	var from := _rect(a).get_center()
	var speed := float(row["speed"])
	var g := float(row["gravity"])
	var dir := HitShapes.ballistic_dir(from, aim, speed, g)
	var p := {"pid": _next_pid, "owner": a.e.id, "pos": from, "origin": from, "vel": dir * speed, "g": g,
		"kind": kind, "born": now, "dist": 0.0, "aim": aim}
	p.merge(extra, true)
	_next_pid += 1
	projectiles.append(p)
	counts["projectiles"] += 1
	_emit(Ev.PROJECTILE, a.e.id, 0, {"pid": p["pid"], "pkind": maxi(0, CombatCodec.PKINDS.find(kind)), "pos": from,
		"vel": p["vel"], "gravity": g})
	return p

func _step_projectiles() -> void:
	if projectiles.is_empty():
		return
	var dt := 1.0 / K.TICK_HZ
	var life := float(CombatTempo.section("projectiles").get("max_life_s", 4.0))
	var keep: Array = []
	for p: Dictionary in projectiles:
		var owner: Actor = actors.get(p["owner"])
		if owner == null:
			continue
		var done := false
		var vel: Vector2 = p["vel"]
		var n := maxi(1, ceili(vel.length() * dt / 0.5))
		var sdt := dt / n
		for k in n:
			var a0: Vector2 = p["pos"]
			vel.y -= float(p["g"]) * sdt
			var a1 := a0 + vel * sdt
			var seg := a1 - a0
			var tile_t := 2.0
			var hit := TileCollision.raycast(host.world, a0, a1)
			if hit["hit"]:
				tile_t = float(hit["distance"]) / maxf(seg.length(), 1e-6)
			var best: Actor = null
			var best_t := tile_t
			for b: Actor in actors.values():
				if b == owner or not _targetable(b):
					continue
				var bt := HitShapes.segment_box(a0, a1, hurt_box(b.e))
				if bt >= 0.0 and bt < best_t and (hostile(owner.e, b.e) or _aimed(owner, b, p["aim"])):
					best_t = bt
					best = b
			if best != null or tile_t <= 1.0:
				var at := a0 + seg * minf(best_t, 1.0)
				p["dist"] = float(p["dist"]) + seg.length() * minf(best_t, 1.0)
				p["pos"] = at
				_emit(Ev.IMPACT, p["owner"], best.e.id if best != null else 0, {"pid": p["pid"], "pos": at})
				if best != null:
					_projectile_hit(owner, best, p)
				done = true
				break
			p["pos"] = a1
			p["dist"] = float(p["dist"]) + seg.length()
			if float(p["dist"]) > float(p.get("max", 1e9)) or now - float(p["born"]) > life or not host.world.in_bounds(floori(a1.x), floori(a1.y)):
				_emit(Ev.IMPACT, p["owner"], 0, {"pid": p["pid"], "pos": a1})
				done = true
				break
		p["vel"] = vel
		if not done:
			keep.append(p)
	projectiles = keep

func _projectile_hit(a: Actor, b: Actor, p: Dictionary) -> void:
	var opts: Dictionary = p.get("opts", {}).duplicate()
	if float(p["dist"]) > float(p.get("normal", 1e9)):
		opts["disadvantage"] = true   # long range
	if p.has("ab"):
		_spell_hit(a, b, p, opts)
		return
	var c := a.e.combatant
	var keep_w := c.weapon
	var keep_r := c.hit_riders
	c.weapon = p.get("weapon")
	c.hit_riders = p.get("riders", [])
	_weapon_attack(a, b, opts, p["origin"])
	c.weapon = keep_w
	c.hit_riders = keep_r

# --- spells -------------------------------------------------------------------------------------

## How a spell finds its targets: area, self, ally (heals and buffs), darts (auto-hit
## projectiles), foe (save spells and hostile marks: picked near the aim), melee (touch spell
## attacks: the arc), bolt (ranged spell attacks: a projectile per ray).
static func spell_shape(ab: AbilityData) -> String:
	if ab.area_size > 0:
		return "area"
	if ab.range_feet == 0 and not ab.has_damage() and not ab.is_healing():
		return "self"
	if ab.is_healing() or (not ab.has_damage() and not ab.uses_save and not ab.hostile):
		return "ally"
	if ab.projectiles > 0 and ab.auto_hit:
		return "darts"
	if ab.uses_save or not ab.has_damage():
		return "foe"
	if ab.range_feet <= 5:
		return "melee"
	return "bolt"

## "" when the machine can cast it, else why not.
static func spell_support(ab: AbilityData) -> String:
	if ab == null:
		return "not in the pack"
	if SRDContent.TAG_NO_MECHANICS in ab.tags:
		return "no mechanics in the addon (disabled or not extracted)"
	if not ab.summon.is_empty():
		return "summons a force (needs a host-side summon)"
	for t: Dictionary in ab.effects:
		if String(t.get("type", "")) == "teleport":
			return "teleport (would move a client-owned body)"
	if not ab.casting_time in ["action", "bonus_action", "reaction"]:
		return "casting time %s (not a combat cast)" % ab.casting_time
	if ab.casting_time == "reaction" and spell_shape(ab) != "self":
		return "reaction trigger not modelled (only self reactions such as Shield)"
	return ""

## The spells `e` may cast: [{slug, name, level, flags, ab, support}]; players from their
## character's prepared list (attack and save spells first), monsters none yet.
func spells_of(e: HostEntity) -> Array:
	var a := actor(e)
	if a == null or e.character == null:
		return []
	var key := "%s:%d:%d" % [e.character.class_slug, e.character.level, e.character.build.hash()]
	if key == a.spells_key:
		return a.spells
	a.spells_key = key
	var ability := host.srd.spellcasting_ability(e.character.class_slug)
	var first: Array = []
	var rest: Array = []
	for slug: String in e.character.resolved().get("spells", []):
		if not host.srd.pack.has_row("spell", slug):
			continue
		var ab := host.srd.make_spell(slug, maxi(0, ability) as SRD.Ability)
		var why := spell_support(ab)
		var flags := 0
		if ab.has_damage() and (ab.uses_save or not ab.auto_hit):
			flags |= CombatCodec.SPELL_DAMAGE
		if ab.casting_time == "bonus_action":
			flags |= CombatCodec.SPELL_BONUS
		if ab.casting_time == "reaction":
			flags |= CombatCodec.SPELL_REACTION
		if ab.concentration:
			flags |= CombatCodec.SPELL_CONCENTRATION
		if ab.is_healing():
			flags |= CombatCodec.SPELL_HEAL
		if ab.area_size > 0:
			flags |= CombatCodec.SPELL_AREA
		if why == "":
			flags |= CombatCodec.SPELL_SUPPORTED
		var row := {"slug": slug, "name": ab.ability_name, "level": ab.slot_level, "flags": flags, "ab": ab, "support": why}
		if flags & CombatCodec.SPELL_DAMAGE:
			first.append(row)
		else:
			rest.append(row)
	a.spells = first + rest
	return a.spells

## Cast a prepared spell at `level` (>= its own; 0 for cantrips) toward `aim`. Action and
## bonus-action spells wind up, then resolve at the contact frame (the slot is spent there);
## reactions (Shield) resolve at once. Returns "" or why it was refused.
func cast(e: HostEntity, slug: String, level: int, aim: Vector2) -> String:
	var a := actor(e)
	if a == null or e.combatant == null:
		return "no combatant"
	if not can_act(e):
		return "cannot act"
	var entry := {}
	for s: Dictionary in spells_of(e):
		if s["slug"] == slug:
			entry = s
	if entry.is_empty():
		return "not prepared"
	if String(entry["support"]) != "":
		return String(entry["support"])
	var ab: AbilityData = entry["ab"]
	var c := e.combatant
	var lvl := 0 if ab.slot_level == 0 else maxi(level, ab.slot_level)
	if lvl > 0 and (c.energy_slots == null or not c.energy_slots.has_slot(lvl)):
		return "no level %d slot" % lvl
	if aim == Vector2.INF or not (is_finite(aim.x) and is_finite(aim.y)):
		aim = e.body.rect().get_center() + Vector2(e.body.facing * 4.0, 0)
	var ct := ab.casting_time
	if ct == "reaction":
		if now < a.reaction_ready - 1e-6:
			return "reaction not ready"
		a.reaction_ready = now + float(CombatTempo.section("timers").get("reaction_s", K.ROUND_SECONDS))
		_start_clock(a)
		_emit(Ev.SWING, e.id, 0, {"mode": Mode.CAST, "swings": 1, "windup": 0.0, "total": 0.0, "tempo": "cast", "aim": aim, "what": slug})
		_cast_now(a, ab, lvl, aim)
		return ""
	if not a.seq.is_empty() or now < a.action_ready - 1e-6 or _rolling(a):
		return "busy"
	if ct == "bonus_action":
		if now < a.bonus_ready - 1e-6:
			return "bonus action not ready"
		a.bonus_ready = now + float(CombatTempo.section("timers").get("bonus_s", K.ROUND_SECONDS))
	var tempo := CombatTempo.cast_tempo(ct)
	var tl := CombatTempo.timeline(tempo, 1)
	a.seq = {"kind": "cast", "t0": now, "contacts": tl["contacts"], "total": tl["total"], "idx": 0,
		"steps": [{"type": "spell"}], "aim": aim, "ab": ab, "level": lvl, "casting": ct}
	if ct == "action":
		a.action_ready = now + float(tl["total"])
	_touched[e.id] = true
	_start_clock(a)
	counts["swings"] += 1
	_emit(Ev.SWING, e.id, 0, {"mode": Mode.AREA if ab.area_size > 0 else Mode.CAST, "swings": 1, "tempo": "cast", "windup": tl["windup"],
		"total": tl["total"], "aim": aim, "what": slug})
	return ""

## A copy of a spell that resolves one ray or dart (projectile spells fly one by one).
static func _single(ab: AbilityData, dart: bool) -> AbilityData:
	var d: AbilityData = ab.duplicate()
	d.effects = ab.effects
	d.immune_if = ab.immune_if
	d.summon = ab.summon
	d.casting_ability = ab.casting_ability
	d.projectiles = 1 if dart else 0
	d.upcast_projectiles = 0
	return d

func _cast_now(a: Actor, ab: AbilityData, level: int, aim: Vector2) -> void:
	var c := a.e.combatant
	var rect := _rect(a)
	var center := rect.get_center()
	var shape := spell_shape(ab)
	var targets: Array = []
	var opts := {"cover": {}, "within_5ft": {}}
	var origin := center
	match shape:
		"area":
			var res := _area(a, ab, aim, ab.range_feet == 0)
			targets = res["targets"]
			opts["cover"] = res["cover"]
			origin = res["origin"]
		"darts", "foe":
			targets = _pick(a, aim, true, ab)
		"ally":
			targets = _pick(a, aim, false, ab)
		"melee":
			var half := float(CombatTempo.section("melee").get("arc_half_angle_deg", 70.0))
			var dir := HitShapes.aim_dir(center, aim, a.e.body.facing)
			var best: Actor = null
			var bg := 1e9
			for b: Actor in actors.values():
				if b == a or not _targetable(b) or not (hostile(a.e, b.e) or _aimed(a, b, aim)):
					continue
				var r := hurt_box(b.e)
				if r != b.e.body.rect() and Dodge.under_blow(r, rect, aim.y):
					continue
				if HitShapes.in_arc(rect, dir, K.ft(5), half, r) and _melee_line(center, rect, r) and HitShapes.gap(rect, r) < bg:
					bg = HitShapes.gap(rect, r)
					best = b
			if best != null:
				targets = [best]
	if shape in ["darts", "foe", "ally", "melee"] and targets.is_empty():
		_emit(Ev.CANCEL, a.e.id, 0, {})   # nothing to target: the slot is not spent
		return
	if level > 0 and a.e.is_player() and (c.energy_slots == null or not c.energy_slots.use_slot(level)):
		_emit(Ev.CANCEL, a.e.id, 0, {})
		return
	if shape == "bolt" or shape == "darts":
		var n := ab.projectile_count(level) if ab.projectiles > 0 else 1
		var kind := "dart" if shape == "darts" else "spell"
		var opts2 := {}
		if shape == "bolt" and _foe_adjacent(a):
			opts2["disadvantage"] = true
		var at: Vector2 = (targets[0] as Actor).e.body.rect().get_center() if shape == "darts" else aim
		for i in n:
			_spawn(a, kind, at, {"ab": _single(ab, shape == "darts"), "level": level, "opts": opts2,
				"normal": K.ft(maxf(ab.range_feet, 5)), "max": K.ft(maxf(ab.range_feet, 5)) + 2.0})
		_after_cast(a, ab, [])
		return
	for b: Actor in targets:
		opts["within_5ft"][b.e.combatant.name] = HitShapes.gap(rect, b.e.body.rect()) <= _within5() + HitShapes.EPS
		if shape != "area":
			opts["cover"][b.e.combatant.name] = HitShapes.cover(host.world, center, b.e.body.rect())
		if b != a and hostile(a.e, b.e):
			_engage(a, b)
		elif b != a:
			_start_clock(b)
	var combatants: Array = targets.map(func(b: Actor) -> Combatant: return b.e.combatant)
	var evs := resolver.cast(c, ab, combatants, level, a.conc if ab.concentration else null, opts)
	_spell_events(a, ab, evs, origin)
	_after_cast(a, ab, targets)

func _spell_hit(a: Actor, b: Actor, p: Dictionary, opts_in: Dictionary) -> void:
	var ab: AbilityData = p["ab"]
	var opts := opts_in.duplicate()
	var r := b.e.body.rect()
	opts["cover"] = HitShapes.cover(host.world, p["origin"], r)
	if opts["cover"] == SRD.Cover.FULL:
		return
	opts["within_5ft"] = HitShapes.gap(_rect(a), r) <= _within5() + HitShapes.EPS
	_sight_opts(a, b, opts)
	_engage(a, b)
	var evs := resolver.cast(a.e.combatant, ab, [b.e.combatant], int(p["level"]), null, opts)
	counts["rolls"] += 1
	_spell_events(a, ab, evs, p["origin"])

## Area targets: the shape from its origin (self-centred shapes start at the caster; others
## at the aim point, clamped to range and stopped by the first wall), every creature it
## overlaps with line of effect from the origin, with cover per target.
func _area(a: Actor, ab: AbilityData, aim: Vector2, from_self: bool) -> Dictionary:
	var center := _rect(a).get_center()
	var dir := HitShapes.aim_dir(center, aim, a.e.body.facing)
	var origin := center
	if not from_self:
		var p := aim
		var rng := K.ft(maxf(ab.range_feet, 5))
		if p.distance_to(center) > rng:
			p = center + dir * rng
		origin = HitShapes.reach_point(host.world, center, p)
	var size := K.ft(ab.area_size)
	var out := {"targets": [], "cover": {}, "origin": origin}
	# with Life, harmful areas spare FRIENDLY and NEUTRAL creatures (and the caster)
	var spare := _life_sys() != null and (ab.has_damage() or ab.uses_save or ab.hostile)
	for b: Actor in actors.values():
		if not _targetable(b) or (from_self and b == a):
			continue
		if spare and not hostile(a.e, b.e) and not _aimed(a, b, aim):
			continue
		var r := hurt_box(b.e)
		if HitShapes.in_area(ab.area_shape, origin, dir, size, 0.0, r) and HitShapes.line_to(host.world, origin, r):
			out["targets"].append(b)
			out["cover"][b.e.combatant.name] = HitShapes.cover(host.world, origin, r)
	return out

## Creatures nearest the aim point (within pick_radius of it, else the nearest in range):
## foes for hostile spells, the caster and its allies for heals and buffs. Range and sight
## line from the caster; touch means within 5 ft.
func _pick(a: Actor, aim: Vector2, foes: bool, ab: AbilityData) -> Array:
	var rect := _rect(a)
	var center := rect.get_center()
	var rng := K.ft(5) if ab.range_feet <= 5 else K.ft(ab.range_feet)
	var cands: Array = []
	for b: Actor in actors.values():
		# spells on allies (Cure Wounds, Healing Word) reach a downed player too: that is how a
		# spell gets them up; spells on foes never touch the downed
		var ok := _targetable(b) if foes else _helpable(b)
		if not ok or (foes and (b == a or not (hostile(a.e, b.e) or _aimed(a, b, aim)))) or (not foes and hostile(a.e, b.e)):
			continue
		var r := b.e.body.rect()
		if b != a and (HitShapes.gap(rect, r) > rng + HitShapes.EPS or not HitShapes.line_to(host.world, center, r)):
			continue
		cands.append([HitShapes.nearest(r, aim).distance_to(aim), b])
	cands.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	var limit := maxi(1, ab.target_limit(maxi(ab.slot_level, 1)))
	var out: Array = []
	for x: Array in cands:
		if out.size() >= limit:
			break
		if float(x[0]) > float(CombatTempo.num("pick_radius", 3.0)) and not out.is_empty():
			break
		out.append(x[1])
	return out

func _save_action(a: Actor, s: Dictionary, step: Dictionary) -> void:
	var f: Dictionary = step["act"]["save"]
	var c := a.e.combatant
	var ab := MonsterSpells.save_ability(f)
	MonsterSpells.spend_save_action(c, f)
	var targets: Array
	var opts := {"cover": {}}
	var origin := _rect(a).get_center()
	if ab.area_size > 0:
		var res := _area(a, ab, s["aim"], ab.range_feet == 0)
		targets = res["targets"]
		opts["cover"] = res["cover"]
		origin = res["origin"]
	else:
		targets = _pick(a, s["aim"], true, ab)
	for b: Actor in targets:
		_engage(a, b)
	var evs := resolver.cast(c, ab, targets.map(func(b: Actor) -> Combatant: return b.e.combatant), -1, null, opts)
	counts["rolls"] += 1
	_spell_events(a, ab, evs, origin)

func _spell_events(a: Actor, ab: AbilityData, evs: Array, from: Vector2) -> void:
	for ev: Dictionary in evs:
		var tid := _id_of_name(String(ev.get("target", "")))
		var b: Actor = actors.get(tid)
		var dealt := int(ev.get("damage_dealt", 0))
		match String(ev.get("type", "")):
			"spell_attack", "spell_projectile":
				if ev.has("d20"):
					var total := int(ev["d20"]) + int(ev.get("attack_bonus", 0)) + int(ev.get("bonus_dice", 0))
					_emit(Ev.CRIT if ev.get("crit", false) else (Ev.HIT if ev.get("hit", false) else Ev.MISS), a.e.id, tid,
						{"d20": ev["d20"], "total_roll": total, "ac": ev.get("target_ac", 0)})
			"spell_save":
				_emit(Ev.SAVE, a.e.id, tid, {"dc": ev.get("dc", 0), "saved": ev.get("saved", false), "what": ab.spell_id})
			"spell_heal":
				_emit(Ev.HEAL, a.e.id, tid, {"amount": ev.get("healed", 0), "hp": ev.get("target_hp_after", 0)})
				if b != null and b.e.combatant.current_hp > 0:
					b.downed_at = -1.0
					# the addon's heal raised it from 0 HP: Rules gets the player up now
					if b.e.is_player() and _rules_has("heal") and is_downed(b.e):
						host.system(HostSystem.RULES).call("heal", b.e, b.e.combatant.current_hp)
		if dealt > 0:
			_emit(Ev.DAMAGE, a.e.id, tid, {"amount": dealt, "dtype": ab.damage_type, "hp": ev.get("target_hp_after", 0)})
		if b != null:
			_touched[tid] = true
			if ev.has("push_feet"):
				_push(b, from, int(ev["push_feet"]))
			_after_damage(b, dealt, a.e.id, bool(ev.get("crit", false)))
	_touched[a.e.id] = true

## Spell durations from the table: the cast's timed effects stop counting turns and end on
## a timer instead (a minute is 20 s); Concentration ends with it.
func _after_cast(a: Actor, ab: AbilityData, targets: Array) -> void:
	var dur := CombatTempo.duration_s(String(host.srd.pack.get_row("spell", ab.spell_id).get("data", {}).get("duration", "")))
	if dur <= 0.0:
		return
	var ids: Array[int] = [a.e.id]
	for b: Actor in targets:
		if not b.e.id in ids:
			ids.append(b.e.id)
	for id in ids:
		var b: Actor = actors.get(id)
		if b == null or b.e.combatant == null:
			continue
		for eff: Dictionary in b.e.combatant.effects.all():
			if String(eff.get("id", "")).begins_with(ab.spell_id + "-") and String(eff.get("expires", "")) != "":
				eff["expires"] = ""
				eff["timed"] = true
	timers.append({"at": now + dur, "caster": a.e.id, "slug": ab.spell_id, "targets": ids, "conc": ab.concentration})

func _step_timers() -> void:
	if timers.is_empty():
		return
	var keep: Array = []
	for t: Dictionary in timers:
		if now < float(t["at"]) - 1e-6:
			keep.append(t)
			continue
		var a: Actor = actors.get(t["caster"])
		if t["conc"] and a != null and a.conc.is_concentrating and a.conc.active_ability.spell_id == t["slug"]:
			a.conc.end()
		for id: int in t["targets"]:
			var b: Actor = actors.get(id)
			if b == null or b.e.combatant == null:
				continue
			for eff: Dictionary in b.e.combatant.effects.all().duplicate():
				if eff.get("timed", false) and String(eff.get("id", "")).begins_with(String(t["slug"]) + "-"):
					b.e.combatant.effects.remove_id(String(eff["id"]))
			_touched[id] = true
	timers = keep

# --- conditions, status, events -------------------------------------------------------------

func _id_of_name(n: String) -> int:
	var id: int = _by_name.get(n, 0)
	var a: Actor = actors.get(id)
	if a != null and a.e.combatant != null and a.e.combatant.name == n:
		return id
	for b: Actor in actors.values():
		if b.e.combatant != null and b.e.combatant.name == n:
			_by_name[n] = b.e.id
			return b.e.id
	return 0

static func cond_mask(c: Combatant) -> int:
	var m := 0
	for i in SRD.Condition.DEAD + 1:
		if c.conditions.has(i as SRD.Condition):
			m |= 1 << i
	return m

func _diff_touched() -> void:
	for id: int in _touched:
		var a: Actor = actors.get(id)
		if a == null or a.e.combatant == null:
			continue
		var c := a.e.combatant
		var m := cond_mask(c)
		if m != a.cond_mask:
			for i in SRD.Condition.DEAD + 1:
				var was := a.cond_mask & (1 << i) != 0
				var is_on := m & (1 << i) != 0
				if was != is_on:
					_emit(Ev.CONDITION, _condition_source(c, i), id, {"cond": i, "on": is_on})
			a.cond_mask = m
		var ids := {}
		for eff: Dictionary in c.effects.all():
			var k := String(eff.get("id", ""))
			if k != "":
				ids[k] = true
		for k: String in ids:
			if not a.effect_ids.has(k):
				_emit(Ev.EFFECT, _id_of_name(String(c.effects.all().filter(func(x: Dictionary) -> bool: return x.get("id", "") == k)[0].get("source", ""))),
					id, {"on": true, "what": k})
		for k: String in a.effect_ids:
			if not ids.has(k):
				_emit(Ev.EFFECT, 0, id, {"on": false, "what": k})
		a.effect_ids = ids
		_move_rules(a)
	_touched.clear()

func _condition_source(c: Combatant, cond: int) -> int:
	var key := String(SRD.Condition.find_key(cond)).to_lower()
	for eff: Dictionary in c.effects.of_type("condition"):
		if String(eff.get("condition", "")) == key:
			return _id_of_name(String(eff.get("source", "")))
	return 0

## Movement limits from conditions and speed effects (data/combat.json "conditions").
func _move_rules(a: Actor) -> void:
	var c := a.e.combatant
	var cd := CombatTempo.section("conditions")
	var mult := 1.0
	var no_jump := false
	for n: String in cd.get("speed_zero", []):
		if c.conditions.has(SRDEffects.condition_from(n)):
			mult = 0.0
	for n: String in cd.get("no_jump", []):
		if c.conditions.has(SRDEffects.condition_from(n)):
			no_jump = true
	if mult > 0.0 and c.conditions.has(SRD.Condition.PRONE):
		mult = float(cd.get("prone_crawl", 0.5))
	if mult > 0.0 and c.stats.speed > 0:
		mult *= float(c.speed) / float(c.stats.speed)
	if mult > 0.0 and not a.seq.is_empty():
		# moving while swinging or casting (data: 1.0 = full speed, the feel as played);
		# Steady (cast_move) and the like win back a share of any slowdown while casting
		var base := float(CombatTempo.section("tempo_move").get("cast" if String(a.seq.get("kind", "")) == "cast" else "swing", 1.0))
		if String(a.seq.get("kind", "")) == "cast":
			base = lerpf(base, 1.0, clampf(_tag(a.e, "cast_move"), 0.0, 1.0))
		mult *= base
	if a.dead_at >= 0.0 or a.downed_at >= 0.0:
		mult = 0.0
		no_jump = true
	a.move_mult = mult
	a.no_jump = no_jump or mult <= 0.0
	a.fear_src = _condition_source(c, SRD.Condition.FRIGHTENED) if c.conditions.has(SRD.Condition.FRIGHTENED) else 0

func status_of(a: Actor) -> Dictionary:
	var c := a.e.combatant
	var slots := []
	for l in range(1, 10):
		slots.append([c.energy_slots.slots_remaining_at(l), c.energy_slots.slots_max_at(l)] if c.energy_slots != null else [0, 0])
	var flags := (CombatCodec.ST_NO_JUMP if a.no_jump else 0) | (CombatCodec.ST_NO_ACTIONS if not c.can_act() else 0) \
		| (CombatCodec.ST_DOWNED if a.downed_at >= 0.0 else 0) | (CombatCodec.ST_CONCENTRATING if a.conc.is_concentrating else 0)
	return {"action": maxf(0.0, a.action_ready - now), "bonus": maxf(0.0, a.bonus_ready - now),
		"reaction": maxf(0.0, a.reaction_ready - now), "move_mult": a.move_mult, "flags": flags, "fear_src": a.fear_src,
		"slots": slots, "concentration": a.conc.active_ability.spell_id if a.conc.is_concentrating else "",
		"temp_hp": c.stats.temp_hp, "reach_ft": CombatTempo.reach_ft(host.srd, c.weapon),
		"range_ft": CombatTempo.range_ft(host.srd, c.weapon).y if c.weapon != null and c.weapon.is_ranged() else 0}

func _send_status() -> void:
	for a: Actor in actors.values():
		if not a.e.is_player() or a.e.combatant == null:
			continue
		if host.tick_count % K.TICK_HZ == 0 or a.spells_key == "":
			var before := a.spells_key
			var list := spells_of(a.e)
			if a.spells_key != before or not a.spells_sent:
				a.spells_sent = true
				host.send_sys(sys_id(), CombatCodec.Msg.SPELLS, CombatCodec.spells(list), a.e.id)
		var st := status_of(a)
		var sig := "%.3f|%.3f|%.3f|%s|%d|%d|%s|%s|%d|%d|%d" % [a.action_ready, a.bonus_ready, a.reaction_ready, a.move_mult, st["flags"],
			a.fear_src, st["slots"], st["concentration"], st["temp_hp"], st["reach_ft"], st["range_ft"]]
		if sig != a.status_sig:
			a.status_sig = sig
			host.send_sys(sys_id(), CombatCodec.Msg.STATUS, CombatCodec.status(st), a.e.id)

func _emit(kind: int, src: int, dst: int, fields: Dictionary) -> void:
	var ev := fields.duplicate()
	ev["kind"] = kind
	ev["src"] = src
	ev["dst"] = dst
	var at: HostEntity = host.entity(dst) if dst != 0 else null
	if at == null:
		at = host.entity(src)
	var pos: Vector2 = at.body.pos if at != null else Vector2(ev.get("pos", Vector2.ZERO))
	_events.append([pos, ev])
	counts["events"] += 1
	if record:
		var r := ev.duplicate()
		r["t"] = host.tick_count
		recorded.append(r)

## One EVENTS message per chunk of origin per tick (interest is by chunk), at most 120 events each.
func _flush() -> void:
	if _events.is_empty():
		return
	var groups := {}
	for pe: Array in _events:
		var c := Interest.chunk_of(pe[0])
		if not groups.has(c):
			groups[c] = []
		groups[c].append(pe[1])
	_events = []
	for c: Vector2i in groups:
		var list: Array = groups[c]
		var at := Vector2((c.x + 0.5) * K.CHUNK, (c.y + 0.5) * K.CHUNK)
		for i in range(0, list.size(), 120):
			host.send_sys_near(sys_id(), CombatCodec.Msg.EVENTS, CombatCodec.events(host.tick_count, list.slice(i, i + 120)), at)
