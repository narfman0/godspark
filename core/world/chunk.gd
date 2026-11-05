## One CHUNK x CHUNK block of tiles. Layers are flat arrays, index = lx + ly * CHUNK.
## Also the chunk's dressing objects (trees, rocks, cave fungi): records anchored at a cell of
## this chunk (see Dressing).
class_name Chunk
extends RefCounted

const N := K.CHUNK
const CELLS := N * N
## Bytes per object record: u16 dressing id, u8 lx, u8 ly (the footprint's bottom-left
## cell, in this chunk), u8 variant.
const OBJ_BYTES := 5
## First byte of a blob that carries objects (a plain zstd frame starts with 0x28).
const OBJ_MARK := 0xD0
## More records than this in one chunk is a corrupt blob.
const MAX_OBJECTS := CELLS

var cx: int
var cy: int
var fg := PackedByteArray()      ## foreground tile id, u16 little-endian per cell
var bg := PackedByteArray()      ## background wall id, u8 per cell
var liquid := PackedByteArray()  ## u8 per cell: low 4 bits level 0-15, high bits kind
var objects := PackedByteArray() ## OBJ_BYTES per record
## True once it differs from what worldgen made (the saver's concern).
var modified := false

func _init(chunk_x: int, chunk_y: int) -> void:
	cx = chunk_x
	cy = chunk_y
	fg.resize(CELLS * 2)
	bg.resize(CELLS)
	liquid.resize(CELLS)

## All layers (and objects) in one zstd blob, for saves and for sending to clients.
## Without objects: zstd(fg + bg + liquid). With objects: OBJ_MARK, u16 count, then
## zstd(fg + bg + liquid + records).
func to_bytes() -> PackedByteArray:
	var raw := PackedByteArray()
	raw.append_array(fg)
	raw.append_array(bg)
	raw.append_array(liquid)
	if objects.is_empty():
		return raw.compress(FileAccess.COMPRESSION_ZSTD)
	raw.append_array(objects)
	var out := PackedByteArray([OBJ_MARK, 0, 0])
	out.encode_u16(1, object_count())
	out.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD))
	return out

## Decode a blob. On a bad blob the layers come out the wrong size (callers check).
func from_bytes(blob: PackedByteArray) -> void:
	var n := 0
	var body := blob
	if blob.size() >= 3 and blob[0] == OBJ_MARK:
		n = blob.decode_u16(1)
		body = blob.slice(3)
		if n > MAX_OBJECTS:
			fg = PackedByteArray()
			return
	var want := CELLS * 4 + n * OBJ_BYTES
	var raw := body.decompress(want, FileAccess.COMPRESSION_ZSTD) if not body.is_empty() else PackedByteArray()
	if raw.size() != want:
		fg = PackedByteArray()
		bg = PackedByteArray()
		liquid = PackedByteArray()
		objects = PackedByteArray()
		return
	fg = raw.slice(0, CELLS * 2)
	bg = raw.slice(CELLS * 2, CELLS * 3)
	liquid = raw.slice(CELLS * 3, CELLS * 4)
	objects = raw.slice(CELLS * 4)

func object_count() -> int:
	return objects.size() / OBJ_BYTES

## Record i as Vector4i(id, lx, ly, variant).
func object_at(i: int) -> Vector4i:
	var o := i * OBJ_BYTES
	return Vector4i(objects.decode_u16(o), objects[o + 2], objects[o + 3], objects[o + 4])

func add_object(id: int, lx: int, ly: int, variant: int) -> void:
	var o := objects.size()
	objects.resize(o + OBJ_BYTES)
	objects.encode_u16(o, id)
	objects[o + 2] = lx
	objects[o + 3] = ly
	objects[o + 4] = variant & 0xff

func remove_object(i: int) -> void:
	var o := i * OBJ_BYTES
	var tail := objects.slice(o + OBJ_BYTES)
	objects.resize(o)
	objects.append_array(tail)
