## One CHUNK x CHUNK block of tiles. Layers are flat arrays, index = lx + ly * CHUNK.
class_name Chunk
extends RefCounted

const N := K.CHUNK
const CELLS := N * N

var cx: int
var cy: int
var fg := PackedByteArray()      ## foreground tile id, u16 little-endian per cell
var bg := PackedByteArray()      ## background wall id, u8 per cell
var liquid := PackedByteArray()  ## u8 per cell: low 4 bits level 0-15, high bits kind
## True once it differs from what worldgen made (the saver's concern).
var modified := false

func _init(chunk_x: int, chunk_y: int) -> void:
	cx = chunk_x
	cy = chunk_y
	fg.resize(CELLS * 2)
	bg.resize(CELLS)
	liquid.resize(CELLS)

## All layers in one zstd blob, for saves and for sending to clients.
func to_bytes() -> PackedByteArray:
	var raw := PackedByteArray()
	raw.append_array(fg)
	raw.append_array(bg)
	raw.append_array(liquid)
	return raw.compress(FileAccess.COMPRESSION_ZSTD)

func from_bytes(blob: PackedByteArray) -> void:
	var raw := blob.decompress(CELLS * 4, FileAccess.COMPRESSION_ZSTD)
	fg = raw.slice(0, CELLS * 2)
	bg = raw.slice(CELLS * 2, CELLS * 3)
	liquid = raw.slice(CELLS * 3, CELLS * 4)
