## A moving box in the tile world. Tile units, y up; `pos` is the bottom centre of the box
## (its feet). Pure state: TileCollision moves it, PlayerController drives it.
##
##   var b := Body.for_size("medium")   # 1.5 x 2.5 tiles
##   b.pos = Vector2(100.5, 64)
class_name Body
extends RefCounted

var pos := Vector2.ZERO
var vel := Vector2.ZERO
var size := Vector2(1.5, 2.5)
## -1 left, +1 right. Last horizontal direction the body wanted to go.
var facing := 1

# Contacts, refreshed by TileCollision.move and TileCollision.update_contacts.
var on_floor := false
var on_ceiling := false
var on_wall := false
## -1 wall touching the left side, +1 the right side, 0 none (left wins if both).
var wall_dir := 0
## 0..1: fraction of the box height under liquid (centre column). PlayerController updates it.
var in_liquid := 0.0

# Controller state (part of the deterministic state: copy it when snapshotting a body).
## Seconds left in which a jump still counts as from the ground (coyote time).
var coyote := 0.0
## Seconds left in which a buffered jump press will fire on landing.
var jump_buffer := 0.0
## True while rising from a jump and the button is still held (variable height).
var jumping := false
## Holding a ladder: no gravity, ladder tops are not floors.
var climbing := false
## Clinging to a wall (bodies with a climb speed).
var clinging := false
## Flying (bodies with a fly speed, while airborne).
var flying := false
## Swimming (in_liquid at or over the swim threshold).
var swimming := false
## Platform tops at or above this y are ignored (dropped through). NO_DROP when unset.
var drop_y := NO_DROP
## On a staircase: arrived on a tread by a step up or down or a landing (not by walking level
## onto one from a walkway). Keeps stepping along the stairs; cleared off them.
var on_stairs := false
## Seconds S (down) has been held while standing, toward an S-drop through a one-way floor;
## -1 when S was already held off the floor (on a ladder, in the air): it must be let go first.
var down_t := 0.0
## Tiles stepped up (positive) or snapped down (negative) on the last step, for view smoothing.
var stepped := 0.0
# Spark abilities (MoveStats.air_jumps, dash_*): untouched while those are off.
## Air jumps left before landing.
var air_jumps_left := 0
## Seconds of dash left, its direction, and cooldown left.
var dash_left := 0.0
var dash_dir := 0
var dash_cd := 0.0
## The dodge roll (core/combat/dodge.gd): seconds into it (-1: not rolling), its direction and
## speed, and cooldown left.
var roll_t := -1.0
var roll_dir := 0
var roll_speed := 0.0
var roll_cd := 0.0
## Double-tap detection: last tapped direction, seconds it stays open, last move_x.
var tap_dir := 0
var tap_t := 0.0
var last_move_x := 0.0

const NO_DROP := 1 << 30

static func for_size(size_name: String) -> Body:
	var b := Body.new()
	b.size = MoveStats.size_of(size_name)
	return b

func left() -> float:
	return pos.x - size.x * 0.5

func right() -> float:
	return pos.x + size.x * 0.5

func top() -> float:
	return pos.y + size.y

func center() -> Vector2:
	return Vector2(pos.x, pos.y + size.y * 0.5)

func rect() -> Rect2:
	return Rect2(pos.x - size.x * 0.5, pos.y, size.x, size.y)

## Copy of every field, for replays, rollback and tests.
func duplicate_body() -> Body:
	var b := Body.new()
	b.pos = pos
	b.vel = vel
	b.size = size
	b.facing = facing
	b.on_floor = on_floor
	b.on_ceiling = on_ceiling
	b.on_wall = on_wall
	b.wall_dir = wall_dir
	b.in_liquid = in_liquid
	b.coyote = coyote
	b.jump_buffer = jump_buffer
	b.jumping = jumping
	b.climbing = climbing
	b.clinging = clinging
	b.flying = flying
	b.swimming = swimming
	b.drop_y = drop_y
	b.down_t = down_t
	b.on_stairs = on_stairs
	b.stepped = stepped
	b.air_jumps_left = air_jumps_left
	b.dash_left = dash_left
	b.dash_dir = dash_dir
	b.dash_cd = dash_cd
	b.roll_t = roll_t
	b.roll_dir = roll_dir
	b.roll_speed = roll_speed
	b.roll_cd = roll_cd
	b.tap_dir = tap_dir
	b.tap_t = tap_t
	b.last_move_x = last_move_x
	return b
