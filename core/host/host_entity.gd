## One thing the host tracks in the world: a player (moved by its owner's client, checked
## by the host) or, from M2, a monster (simulated by the host through a brain).
##
## `owner` is an opaque peer id from the net layer; NO_OWNER means the host drives the
## entity itself (monsters). Core never interprets it beyond that.
class_name HostEntity
extends RefCounted

enum Kind { PLAYER, MONSTER }

const NO_OWNER := 0
const NO_DIG := Vector2i(-(1 << 30), -(1 << 30))

var id := 0
var kind := Kind.PLAYER
var name := ""
var owner := NO_OWNER
var body: Body
var stats: MoveStats
## What the view needs to draw it: {kind, size: Vector2, color}. Looks table later.
var look := {}
## Host-simulated entities: an object with think(host: WorldHost, e: HostEntity, dt: float)
## -> PlayerInput, called once per host tick. Null for client-owned players.
var brain: Object = null
## Last input fed to the controller (host-simulated entities).
var input := PlayerInput.new()

# Validation of client-owned movement (see WorldHost.submit_state).
## Bumped on every correction; states stamped with an older epoch are ignored.
var epoch := 0
## Client step counter (60 Hz) of the last accepted state; -1 before the first.
var last_seq := -1
## Host tick of the last accepted state (or of the join / correction).
var last_state_tick := 0
var corrections := 0
var states_accepted := 0
## Body flag bits from the client (facing, contacts, modes), for snapshots.
var flags := 0

# A held dig, advanced by the host every tick.
var dig_target := NO_DIG
var dig_req := 0
var dig := TileEdit.DigProgress.new()

## Flag bits shared by the client STATE message and entity snapshots.
const F_RIGHT := 1
const F_FLOOR := 2
const F_CLIMB := 4
const F_SWIM := 8
const F_FLY := 16
const F_CLING := 32
const F_DIG := 64
const F_JUMP := 128

static func body_flags(b: Body, digging := false) -> int:
	return ((F_RIGHT if b.facing > 0 else 0) | (F_FLOOR if b.on_floor else 0)
			| (F_CLIMB if b.climbing else 0) | (F_SWIM if b.swimming else 0)
			| (F_FLY if b.flying else 0) | (F_CLING if b.clinging else 0)
			| (F_DIG if digging else 0) | (F_JUMP if b.jumping else 0))

## Copy the presentational flags back onto a body (facing and modes; contacts are
## recomputed by whoever simulates it).
static func apply_flags(b: Body, f: int) -> void:
	b.facing = 1 if f & F_RIGHT else -1
	b.on_floor = f & F_FLOOR != 0
	b.climbing = f & F_CLIMB != 0
	b.swimming = f & F_SWIM != 0
	b.flying = f & F_FLY != 0
	b.clinging = f & F_CLING != 0
	b.jumping = f & F_JUMP != 0

## Animation state name for the view, from flag bits.
static func state_name(f: int, vel: Vector2) -> String:
	if f & F_DIG:
		return "dig"
	if f & F_CLIMB:
		return "climb"
	if f & F_SWIM:
		return "swim"
	if f & F_FLY:
		return "fly"
	if f & F_CLING:
		return "cling"
	if not (f & F_FLOOR):
		return "jump" if vel.y > 0.0 else "fall"
	return "run" if absf(vel.x) > 0.5 else "idle"

func is_player() -> bool:
	return kind == Kind.PLAYER

func digging() -> bool:
	return dig_target != NO_DIG
