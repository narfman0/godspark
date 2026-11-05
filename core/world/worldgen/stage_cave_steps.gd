## Stage "cave_steps": makes noise-cave shafts climbable by a Medium walker. In every column,
## a tall run of air (taller than STEP rows above its floor) next to a wall gets one-tile
## ledges stuck to that wall, STEP rows apart, left walls and right walls offset by half a
## STEP, so a body can zig-zag up a shaft by jumping ledge to ledge. A ledge goes in only
## where the shaft stays at least OPEN tiles wide beside it, so nothing gets pinched shut.
## Only below the crust (no ledges in the open sky) and above the nadir floor. One pass over
## the grid; no RNG.
extends RefCounted

const GenContext := preload("gen_context.gd")
## Rows between ledges on the same wall (a Medium jump clears 3 with room).
const STEP := 6
## Air tiles a shaft must keep beside a ledge.
const OPEN := 3
## Air runs shorter than this need no ledges (a jump reaches the top).
const TALL := 5
## Widening passes (each opens slots one cell further).
const WIDEN := 3

static func run(c: GenContext, _rng: RandomNumberGenerator) -> void:
	for k in WIDEN:
		_widen(c)
	var w := c.w
	var fg := c.fg
	var air := c.AIR
	var ladder := TileDefs.id("ladder")
	var top := 0
	for x in w:
		top = maxi(top, c.ground[x] - 14)
	for x in range(1, w - 1):
		var y := 1
		var lim := mini(top, c.ground[x] - 14)
		while y < lim:
			if fg[y * w + x] != air or fg[(y - 1) * w + x] == air:
				y += 1
				continue
			# an air run with a floor at y: its height
			var y1 := y
			while y1 < lim and fg[y1 * w + x] == air:
				y1 += 1
			var wall_l := fg[y * w + x - 1] != air and fg[(y + 1) * w + x - 1] != air and fg[y * w + x + 1] == air
			var wall_r := fg[y * w + x + 1] != air and fg[(y + 1) * w + x + 1] != air and fg[y * w + x - 1] == air
			if y1 - y >= TALL and (wall_l or wall_r) and fg[y * w + x - 1] != ladder and fg[y * w + x - 2] != ladder:
				# a tall run against a wall on its left: hang a ladder (roots) up the wall
				for yy in range(y, y1):
					fg[yy * w + x] = ladder
			y = y1
	return

## OPEN air cells from the ledge's other side outward, on its row and the rows above it a
## body passes through.
static func _open_beside(fg: PackedByteArray, w: int, x: int, y: int, dir: int, air: int) -> bool:
	for k in range(1, OPEN + 1):
		var xx := x + dir * k
		if xx < 0 or xx >= w:
			return false
		for dy in 3:
			if fg[(y + dy) * w + xx] != air:
				return false
	return true

## Widen (the caves band): rock with air on both sides across a gap narrower than a body (one or two cells of
## air between rock, horizontally or vertically) is opened by one cell, below the crust.
## Pinch points a 2x3 body cannot pass become passable; open caves barely change.
static func _widen(c: GenContext) -> void:
	var w := c.w
	var fg := c.fg
	var air := c.AIR
	var bedrock := c.BEDROCK
	var out := fg.duplicate()
	var cb: Array = c.bands.get("caves", [2, c.h - 4])     # the noise caves' cramped band only
	for y in range(maxi(2, int(cb[0])), mini(c.h - 3, int(cb[1]) + 1)):
		var row := y * w
		for x in range(2, w - 3):
			if y > c.ground[x] - 14:
				continue
			var i := row + x
			if fg[i] != air:
				continue
			# a horizontal slot under 3 tall: open the cell above (or below)
			var up1 := fg[i + w] == air
			var up2 := up1 and fg[i + 2 * w] == air
			var dn1 := fg[i - w] == air
			if not up2 and not (up1 and dn1):
				var j := i + (w if not up1 else 2 * w)
				if fg[j] != bedrock and j < (c.ground[x] - 14) * w:
					out[j] = air
			# a vertical slot under 2 wide: open the cell to the right
			if fg[i - 1] != air and fg[i + 1] != air and fg[i + 2] != bedrock:
				out[i + 1] = air
	c.fg = out
