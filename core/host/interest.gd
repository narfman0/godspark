## Interest areas: which chunks and entities a player needs. A square of chunks around the
## chunk holding the player's centre, `radius` chunks each way (Chebyshev distance).
## Things are added at `radius` and dropped past `radius + 1`, so a player walking along a
## chunk border does not make chunks flicker in and out.
class_name Interest
extends RefCounted

const DEFAULT_RADIUS := 2

static func chunk_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / K.CHUNK), floori(pos.y / K.CHUNK))

static func dist(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

## Chunks within `radius` of `center` that exist in the world, nearest first (ties by
## Euclidean distance, then row, then column, so the order is deterministic).
static func around(world: TileWorld, center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cy in range(maxi(0, center.y - radius), mini(world.chunks_y, center.y + radius + 1)):
		for cx in range(maxi(0, center.x - radius), mini(world.chunks_x, center.x + radius + 1)):
			out.append(Vector2i(cx, cy))
	sort_by_distance(out, center)
	return out

static func sort_by_distance(list: Array[Vector2i], center: Vector2i) -> void:
	list.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := (a - center).length_squared()
		var db := (b - center).length_squared()
		if da != db:
			return da < db
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x)

## Chunks a body's box (grown by `margin` tiles) touches, clipped to the world.
static func chunks_under(world: TileWorld, rect: Rect2, margin: float) -> Array[Vector2i]:
	var r := rect.grow(margin)
	var out: Array[Vector2i] = []
	var x0 := maxi(0, floori(r.position.x / K.CHUNK))
	var x1 := mini(world.chunks_x - 1, floori(r.end.x / K.CHUNK))
	var y0 := maxi(0, floori(r.position.y / K.CHUNK))
	var y1 := mini(world.chunks_y - 1, floori(r.end.y / K.CHUNK))
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			out.append(Vector2i(cx, cy))
	return out
