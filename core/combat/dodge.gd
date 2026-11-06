## The dodge roll, the same on the client that predicts it and the host that owns hits. All
## numbers come from data/combat.json "dodge". A roll is a move and a smaller hurt box, nothing
## more: no attack roll, AC, DC or die changes, and it is not a spark.
##
##   PlayerController starts and steps it on the body (Body.roll_t seconds in, -1 when not
##   rolling; Body.roll_cd cooldown left). The client tells the host with CombatCodec.Msg.ROLL;
##   the host keeps its own clock from there and tests hits against hurt_rect().
##
## A hit is physical, so the roll has to make the hit shape miss: for the middle frames
## (hurt_from_s..hurt_to_s) the body is a low tuck at its feet. Arrows pass over it and an area
## that reaches it still catches it. A melee arc is wide enough to reach the floor, so a tuck
## inside it is under the blow only if it is below the line of the swing, which runs through
## the point the attacker aimed at when it wound up. A creature too_big_tiles tall or more
## fills the space its blow comes through: nothing is under it.
class_name Dodge
extends RefCounted

const EPS := 1e-6

static func conf() -> Dictionary:
	return CombatTempo.section("dodge")

static func duration() -> float:
	return float(conf().get("duration_s", 0.4))

static func cooldown() -> float:
	return float(conf().get("cooldown_s", 1.0))

## Tiles per second of a roll from a standstill.
static func base_speed() -> float:
	return float(conf().get("distance_tiles", 2.0)) / maxf(duration(), 0.01)

## May this body start a roll now? On the ground (or just off it), doing nothing else.
static func can_start(b: Body) -> bool:
	return b.roll_t < 0.0 and b.roll_cd <= EPS and b.dash_left <= EPS and (b.on_floor or b.coyote > EPS) \
		and not (b.climbing or b.swimming or b.clinging or b.flying)

## Start a roll in the facing direction. From a run it keeps the run's speed (keep_run_speed):
## a roll is never a brake.
static func begin(b: Body) -> void:
	b.roll_dir = 1 if b.facing >= 0 else -1
	b.roll_speed = base_speed()
	if bool(conf().get("keep_run_speed", true)) and signf(b.vel.x) == float(b.roll_dir):
		b.roll_speed = maxf(b.roll_speed, absf(b.vel.x))
	b.roll_t = 0.0
	b.roll_cd = cooldown()
	b.jumping = false

## One controller step of the clock, before the mode is picked.
static func tick(b: Body, input: PlayerInput, dt: float) -> void:
	if b.roll_cd > 0.0:
		b.roll_cd = maxf(0.0, b.roll_cd - dt)
	if b.roll_t >= 0.0:
		b.roll_t += dt
		if b.roll_t >= duration() - EPS:
			b.roll_t = -1.0
	elif input.roll and can_start(b):
		begin(b)

## Is a body t seconds into a roll tucked?
static func tucked(t: float) -> bool:
	var c := conf()
	return t >= float(c.get("hurt_from_s", 0.08)) - EPS and t < float(c.get("hurt_to_s", 0.32)) - EPS

## The box blows must touch, t seconds into a roll: the body's own box, or the tuck at its feet.
static func hurt_rect(r: Rect2, t: float) -> Rect2:
	if not tucked(t):
		return r
	var c := conf()
	var size := r.size * Vector2(float(c.get("hurt_width_mult", 0.6)), float(c.get("hurt_height_mult", 0.32)))
	return Rect2(r.position.x + (r.size.x - size.x) * 0.5, r.position.y, size.x, size.y)

## Does a blow from `att`, aimed at height aim_y, pass over this tuck? The whole box has to be
## under the swing's line; nothing is under the blow of a creature too big to miss.
static func under_blow(hurt: Rect2, att: Rect2, aim_y: float) -> bool:
	var c := conf()
	if att.size.y >= float(c.get("too_big_tiles", 5.0)):
		return false
	return hurt.end.y < aim_y - float(c.get("blow_clearance_tiles", 0.3))
