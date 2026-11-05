## The platformer controller: turns a PlayerInput into velocity, then moves the body with
## TileCollision. Used by a client for its own player and by the host for monsters and to
## validate what clients send. Pure function of (world, body state, input, stats, dt).
##
## Fixed step: call it at MoveStats.step_hz() (60 Hz, dt = 1/60). The caller accumulates
## real time and runs whole steps; given the same inputs from the same body state it
## produces bit-identical results. Other dt values work but feel and test bounds assume 60.
##
## Modes, picked fresh each step in this order:
##   fly     stats.fly_speed > 0 and (airborne, or up/jump held): no gravity
##   ladder  body.climbing: grabbed with up (overlapping a ladder) or down (also from a
##           ladder top); jump lets go (with a jump unless down is held)
##   swim    in_liquid >= swim_threshold: weak gravity against buoyancy, drag, jump/up
##           swims up, a jump press strokes up, or leaps if the head is out
##   cling   stats.climb_speed > 0 and pushing into a wall: walk up walls (spiders);
##           jump kicks off the wall
##   ground  everything else: run with accel/friction, air control, gravity with
##           terminal velocity, coyote time, jump buffer, variable height, one-way
##           platforms (down + jump drops through), step-up and step-down of
##           stats.step_tiles
## Burrow is a stub: burrowers move as walkers until digging-while-moving lands (see
## docs/tracks/movement.md).
class_name PlayerController
extends RefCounted

## Timers below this count as expired (float sums of 1/60 aren't exact).
const T_EPS := 1e-6

static func step(world: TileWorld, body: Body, input: PlayerInput, stats: MoveStats, dt: float) -> void:
	TileCollision.update_contacts(world, body)
	body.in_liquid = TileCollision.liquid_fraction(world, body)
	body.stepped = 0.0
	if input.move_x > 0.0:
		body.facing = 1
	elif input.move_x < 0.0:
		body.facing = -1

	if body.drop_y != Body.NO_DROP:
		if body.pos.y > body.drop_y + TileCollision.EPS or (body.on_floor and body.pos.y < body.drop_y - TileCollision.EPS):
			body.drop_y = Body.NO_DROP

	if body.on_floor:
		body.coyote = stats.coyote_time
	else:
		body.coyote = maxf(0.0, body.coyote - dt)
	if input.jump_pressed:
		body.jump_buffer = stats.buffer_time
	else:
		body.jump_buffer = maxf(0.0, body.jump_buffer - dt)

	# --- pick the mode ---
	body.flying = stats.fly_speed > 0.0 and (not body.on_floor or input.up or input.jump)
	body.swimming = not body.flying and body.in_liquid >= stats.swim_threshold
	if body.flying:
		body.climbing = false
	elif body.climbing:
		if not TileCollision.ladder_at(world, body):
			body.climbing = false
	elif not input.jump_pressed and ((input.up and TileCollision.ladder_at(world, body))
			or (input.down and TileCollision.ladder_at(world, body, true) and not body.swimming)):
		body.climbing = true
		body.drop_y = Body.NO_DROP
	if body.flying or body.climbing or body.swimming or stats.climb_speed <= 0.0 or body.wall_dir == 0:
		body.clinging = false
	else:
		var toward := signf(input.move_x) == body.wall_dir
		var away := input.move_x != 0.0 and not toward
		body.clinging = toward or (body.clinging and not away)

	if body.flying:
		_fly(world, body, input, stats, dt)
	elif body.climbing:
		_ladder(world, body, input, stats, dt)
	elif body.swimming:
		_swim(world, body, input, stats, dt)
	elif body.clinging:
		_cling(world, body, input, stats, dt)
	else:
		_ground(world, body, input, stats, dt)

# --- modes ---------------------------------------------------------------------------

static func _ground(world: TileWorld, body: Body, input: PlayerInput, stats: MoveStats, dt: float) -> void:
	var target := input.move_x * stats.run_speed
	if body.on_floor:
		_approach_x(body, target, stats.ground_accel, stats.ground_friction, stats.turn_accel, dt)
	else:
		_approach_x(body, target, stats.air_accel, stats.air_friction, stats.air_accel, dt)

	var dropped := false
	if input.down and input.jump_pressed and body.on_floor and TileCollision.on_platform_only(world, body):
		body.drop_y = roundi(body.pos.y)
		body.on_floor = false
		body.jump_buffer = 0.0
		body.coyote = 0.0
		dropped = true
	elif body.jump_buffer > T_EPS and body.coyote > T_EPS:
		body.vel.y = stats.jump_velocity
		body.jumping = true
		body.jump_buffer = 0.0
		body.coyote = 0.0
		body.on_floor = false
	if body.jumping:
		if body.vel.y <= 0.0:
			body.jumping = false
		elif not input.jump:
			body.vel.y *= stats.release_cut
			body.jumping = false

	var g := stats.gravity * (stats.fall_gravity_mult if body.vel.y < 0.0 else 1.0)
	body.vel.y = maxf(body.vel.y - g * dt, -stats.terminal_fall)
	_move(world, body, stats, dt, not dropped)

static func _ladder(world: TileWorld, body: Body, input: PlayerInput, stats: MoveStats, dt: float) -> void:
	body.jumping = false
	if input.jump_pressed:
		body.climbing = false
		body.jump_buffer = 0.0
		body.vel.x = input.move_x * stats.run_speed
		if input.down:
			body.vel.y = 0.0
		else:
			body.vel.y = stats.jump_velocity
			body.jumping = true
	else:
		body.vel.y = (int(input.up) - int(input.down)) * stats.ladder_speed
		body.vel.x = input.move_x * stats.ladder_side_speed
	TileCollision.move(world, body, dt)

static func _swim(world: TileWorld, body: Body, input: PlayerInput, stats: MoveStats, dt: float) -> void:
	body.jumping = false
	_approach_x(body, input.move_x * stats.swim_speed, stats.swim_accel, stats.swim_accel, stats.swim_accel, dt)
	if input.jump_pressed:
		if body.in_liquid < stats.leap_below:
			body.vel.y = maxf(body.vel.y, stats.jump_velocity * stats.leap_mult)
		else:
			body.vel.y = maxf(body.vel.y, stats.swim_speed * stats.stroke_mult)
		body.jump_buffer = 0.0
	elif input.down:
		body.vel.y = move_toward(body.vel.y, -stats.swim_speed, stats.swim_accel * dt)
	elif (input.up or input.jump) and body.vel.y < stats.swim_speed:
		body.vel.y = move_toward(body.vel.y, stats.swim_speed, stats.swim_accel * dt)
	else:
		body.vel.y += (body.in_liquid * stats.buoyancy - stats.water_gravity) * dt
		body.vel.y *= maxf(0.0, 1.0 - stats.water_drag * dt)
		body.vel.y = maxf(body.vel.y, -stats.max_sink)
	if body.vel.y < -stats.swim_speed:
		body.vel.y = move_toward(body.vel.y, -stats.swim_speed, stats.water_brake * dt)
	_move(world, body, stats, dt, false)

static func _cling(world: TileWorld, body: Body, input: PlayerInput, stats: MoveStats, dt: float) -> void:
	body.jumping = false
	if input.jump_pressed:
		body.clinging = false
		body.jump_buffer = 0.0
		body.vel.x = -body.wall_dir * stats.run_speed
		body.vel.y = stats.jump_velocity * stats.climb_jump_mult
		body.jumping = true
		body.facing = -body.wall_dir
	else:
		var toward := signf(input.move_x) == body.wall_dir
		if input.down:
			body.vel.y = -stats.climb_speed
		elif input.up or toward:
			body.vel.y = stats.climb_speed
		else:
			body.vel.y = 0.0
		body.vel.x = body.wall_dir * 1.0     # keep pressed against the wall
	TileCollision.move(world, body, dt)

static func _fly(world: TileWorld, body: Body, input: PlayerInput, stats: MoveStats, dt: float) -> void:
	body.jumping = false
	var vy := float(int(input.up or input.jump) - int(input.down))
	var target := Vector2(input.move_x, vy)
	if target.length() > 1.0:
		target = target.normalized()
	target *= stats.fly_speed
	var a := stats.fly_accel * dt
	body.vel = Vector2(move_toward(body.vel.x, target.x, a), move_toward(body.vel.y, target.y, a))
	TileCollision.move(world, body, dt)

# --- shared ----------------------------------------------------------------------------

## Accelerate vel.x toward target: `accel` when speeding up, `turn` when reversing,
## `decel` when letting go or above the target speed.
static func _approach_x(body: Body, target: float, accel: float, decel: float, turn: float, dt: float) -> void:
	var v: float = body.vel.x
	var rate := accel
	if target == 0.0 or absf(v) > absf(target) and signf(v) == signf(target):
		rate = decel
	elif v != 0.0 and signf(v) != signf(target):
		rate = turn
	body.vel.x = move_toward(v, target, rate * dt)

## Move with step-up (walking into a ledge up to step_tiles high) and step-down (walking off
## a drop of up to step_tiles snaps down instead of falling), both only from the floor.
static func _move(world: TileWorld, body: Body, stats: MoveStats, dt: float, allow_snap: bool) -> void:
	var was_floor := body.on_floor
	var dx: float = body.vel.x * dt
	if was_floor and dx != 0.0 and stats.step_tiles > 0:
		_try_step_up(world, body, stats, dx)
	TileCollision.move(world, body, dt)
	if allow_snap and was_floor and not body.on_floor and body.vel.y <= 0.0 and body.stepped == 0.0:
		var limit := float(stats.step_tiles) + TileCollision.EPS
		var free := TileCollision.free_below(world, body, limit)
		if free < limit:
			body.pos = Vector2(body.pos.x, body.pos.y - free)
			body.vel.y = 0.0
			body.stepped = -free
			TileCollision.update_contacts(world, body)

static func _try_step_up(world: TileWorld, body: Body, stats: MoveStats, dx: float) -> void:
	var l := body.left()
	var r := body.right()
	var b: float = body.pos.y
	var blocked: bool = TileCollision._sweep_x(world, l, r, b, b + body.size.y, dx)[0]
	if not blocked:
		return
	var base := float(roundi(b))
	var x0 := minf(l, l + dx)
	var x1 := maxf(r, r + dx)
	for k in range(1, stats.step_tiles + 1):
		var lifted := base + k
		if not TileCollision.overlaps_solid(world, Rect2(x0, lifted, x1 - x0, body.size.y)):
			body.pos = Vector2(body.pos.x, lifted)
			body.stepped = lifted - b
			body.vel.y = maxf(body.vel.y, 0.0)
			return
