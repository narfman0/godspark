## World-wide constants. Tile units everywhere in core: x right, y up, (0, 0) is the
## bottom-left tile. An entity's position is the bottom centre of its box (its feet).
class_name K
extends RefCounted

## One tile is 2.5 ft, so an SRD 5 ft square is 2x2 tiles.
const TILE_FT := 2.5
## Size of a tile in the 3D view, in metres. The Synty survey may adjust it.
const TILE_M := 0.75
## Tiles per chunk side.
const CHUNK := 32
## Host simulation ticks per second.
const TICK_HZ := 30
## Real seconds in one combat round (an SRD round is 6 s of game time).
const ROUND_SECONDS := 2.0

static func ft(feet: float) -> float:
	return feet / TILE_FT
