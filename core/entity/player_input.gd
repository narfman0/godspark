## One controller step's worth of intent. The view (or an AI, or a replay) fills it; core
## never reads the Input singleton. `to_bytes()` / `from_bytes()` are lossless: move_x is
## stored quantized to 1/127 so it survives a byte, and the setters quantize on write.
##
## Wire layout (little-endian):
##   u8 flags   bit0 jump held, 1 jump_pressed, 2 up, 3 down, 4 dig, 5 place, 6 use
##   s8 move_x  * 127
##   if dig, place or use:  s16 target.x, s16 target.y
##   if place:              u16 place_tile
## So 2 bytes when only moving, 6 or 8 with a tile intent.
class_name PlayerInput
extends RefCounted

const QUANT := 127.0

var move_x := 0.0:
	set(v):
		move_x = roundf(clampf(v, -1.0, 1.0) * QUANT) / QUANT
var jump := false
var jump_pressed := false
var up := false
var down := false
var dig := false
var place := false
var use := false
## Tile the dig/place/use intents aim at (tile coordinates, s16 range).
var target := Vector2i.ZERO:
	set(v):
		target = Vector2i(clampi(v.x, -32768, 32767), clampi(v.y, -32768, 32767))
## Tile id to place when `place` is set.
var place_tile := 0:
	set(v):
		place_tile = clampi(v, 0, 65535)

func has_target() -> bool:
	return dig or place or use

func to_bytes() -> PackedByteArray:
	var flags := (int(jump) | int(jump_pressed) << 1 | int(up) << 2 | int(down) << 3
			| int(dig) << 4 | int(place) << 5 | int(use) << 6)
	var b := PackedByteArray()
	b.resize(2 + (4 if has_target() else 0) + (2 if place else 0))
	b[0] = flags
	b.encode_s8(1, int(roundf(move_x * QUANT)))
	if has_target():
		b.encode_s16(2, target.x)
		b.encode_s16(4, target.y)
	if place:
		b.encode_u16(6, place_tile)
	return b

## Null if the bytes are malformed (too short for their flags).
static func from_bytes(b: PackedByteArray) -> PlayerInput:
	if b.size() < 2:
		return null
	var p := PlayerInput.new()
	var flags := int(b[0])
	p.jump = flags & 1 != 0
	p.jump_pressed = flags & 2 != 0
	p.up = flags & 4 != 0
	p.down = flags & 8 != 0
	p.dig = flags & 16 != 0
	p.place = flags & 32 != 0
	p.use = flags & 64 != 0
	p.move_x = b.decode_s8(1) / QUANT
	if p.has_target():
		if b.size() < 6:
			return null
		p.target = Vector2i(b.decode_s16(2), b.decode_s16(4))
	if p.place:
		if b.size() < 8:
			return null
		p.place_tile = b.decode_u16(6)
	return p

func equals(o: PlayerInput) -> bool:
	return (o != null and move_x == o.move_x and jump == o.jump and jump_pressed == o.jump_pressed
			and up == o.up and down == o.down and dig == o.dig and place == o.place and use == o.use
			and (not has_target() or target == o.target) and (not place or place_tile == o.place_tile))
