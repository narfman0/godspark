## Saves and loads a TileWorld as a directory:
##   world.json        {format, width, height, seed, region, meta}
##   r_<rx>_<ry>.bin   one per REGION x REGION chunks: "GSR1", then per chunk in row order
##                     (cy, then cx) a u8 modified flag, a u32 length and the
##                     Chunk.to_bytes() zstd blob.
## Every file is written under a .tmp name and renamed into place; world.json goes last,
## so a crash mid-save leaves the previous world.json pointing at complete regions.
##   WorldSave.save(world, "user://worlds/a")   WorldSave.load("user://worlds/a")
class_name WorldSave
extends RefCounted

const FORMAT := 1
const REGION := 16
const MAGIC := "GSR1"

static func save(world: TileWorld, dir: String) -> Error:
	var err := DirAccess.make_dir_recursive_absolute(dir)
	if err != OK:
		return err
	var rw := ceili(float(world.chunks_x) / REGION)
	var rh := ceili(float(world.chunks_y) / REGION)
	for ry in rh:
		for rx in rw:
			var buf := PackedByteArray()
			buf.append_array(MAGIC.to_ascii_buffer())
			for cy in range(ry * REGION, mini(world.chunks_y, (ry + 1) * REGION)):
				for cx in range(rx * REGION, mini(world.chunks_x, (rx + 1) * REGION)):
					var c := world.chunk_at(cx, cy)
					var blob := c.to_bytes()
					var head := PackedByteArray()
					head.resize(5)
					head[0] = 1 if c.modified else 0
					head.encode_u32(1, blob.size())
					buf.append_array(head)
					buf.append_array(blob)
			err = _write_atomic(dir.path_join("r_%d_%d.bin" % [rx, ry]), buf)
			if err != OK:
				return err
	var info := {"format": FORMAT, "width": world.width, "height": world.height,
		"seed": world.world_seed, "region": REGION, "meta": world.meta}
	return _write_atomic(dir.path_join("world.json"), JSON.stringify(info, "\t").to_utf8_buffer())

static func load(dir: String) -> TileWorld:
	var path := dir.path_join("world.json")
	if not FileAccess.file_exists(path):
		return null
	var info: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not info is Dictionary or int(info.get("format", -1)) != FORMAT:
		return null
	var w := int(info.get("width", 0))
	var h := int(info.get("height", 0))
	if w <= 0 or h <= 0 or w % K.CHUNK != 0 or h % K.CHUNK != 0 or int(info.get("region", 0)) != REGION:
		return null
	var world := TileWorld.new(w, h, int(info.get("seed", 0)))
	var rw := ceili(float(world.chunks_x) / REGION)
	var rh := ceili(float(world.chunks_y) / REGION)
	for ry in rh:
		for rx in rw:
			var buf := FileAccess.get_file_as_bytes(dir.path_join("r_%d_%d.bin" % [rx, ry]))
			if buf.size() < 4 or buf.slice(0, 4).get_string_from_ascii() != MAGIC:
				return null
			var at := 4
			for cy in range(ry * REGION, mini(world.chunks_y, (ry + 1) * REGION)):
				for cx in range(rx * REGION, mini(world.chunks_x, (rx + 1) * REGION)):
					if at + 5 > buf.size():
						return null
					var n := buf.decode_u32(at + 1)
					if at + 5 + n > buf.size():
						return null
					var c := world.chunk_at(cx, cy)
					c.from_bytes(buf.slice(at + 5, at + 5 + n))
					if c.fg.size() != Chunk.CELLS * 2 or c.bg.size() != Chunk.CELLS or c.liquid.size() != Chunk.CELLS:
						return null
					c.modified = buf[at] != 0
					at += 5 + n
	world.meta = _ints(info.get("meta", {}))
	return world

## JSON reads every number as a float; meta only holds integers, so whole floats go back.
static func _ints(v: Variant) -> Variant:
	if v is float and is_equal_approx(v, roundf(v)) and absf(v) < 9.0e15:
		return int(v)
	if v is Array:
		var out: Array = []
		for e: Variant in v:
			out.append(_ints(e))
		return out
	if v is Dictionary:
		var out := {}
		for key: Variant in v:
			out[key] = _ints(v[key])
		return out
	return v

static func _write_atomic(path: String, data: PackedByteArray) -> Error:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(data)
	f.close()
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)  # platforms that won't rename over a file
		err = DirAccess.rename_absolute(tmp, path)
	return err
