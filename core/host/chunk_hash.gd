## A digest over a set of chunks, for comparing a client's partial world with the host's.
## `TileWorld.content_hash()` covers every chunk; a client only holds its interest area.
class_name ChunkHash
extends RefCounted

## SHA-256 hex over the given chunk coordinates (Array of Vector2i, any order, duplicates
## ignored): each chunk's coordinates then its fg, bg and liquid layers, in (cy, cx) order.
static func of(world: TileWorld, coords: Array) -> String:
	return raw(world, coords).hex_encode()

static func raw(world: TileWorld, coords: Array) -> PackedByteArray:
	var list: Array[Vector2i] = []
	var seen := {}
	for c: Vector2i in coords:
		if not seen.has(c):
			seen[c] = true
			list.append(c)
	list.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x))
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var head := PackedByteArray()
	head.resize(8)
	for c in list:
		head.encode_s32(0, c.x)
		head.encode_s32(4, c.y)
		ctx.update(head)
		if c.x < 0 or c.y < 0 or c.x >= world.chunks_x or c.y >= world.chunks_y:
			continue
		var ch := world.chunk_at(c.x, c.y)
		if ch == null:
			ctx.update(PackedByteArray([0xff]))   # unloaded: never equal to a held chunk
			continue
		ctx.update(ch.fg)
		ctx.update(ch.bg)
		ctx.update(ch.liquid)
		if not ch.objects.is_empty():
			ctx.update(ch.objects)
	return ctx.finish()
