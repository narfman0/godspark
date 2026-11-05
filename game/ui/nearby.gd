## What is near the own player in the client's mirror of the world (for prompts and to enable
## buttons; the host checks again): stations by tile, downed allies.
class_name Nearby
extends RefCounted

const CAMPFIRE := "campfire"
const BED := "bed"
const SHRINE := "shrine"

## The nearest cell holding `tile_name` within `r` tiles of the body's box, or (-1, -1).
static func tile(cw: ClientWorld, tile_name: String, r := 3) -> Vector2i:
	if cw == null or cw.world == null:
		return Vector2i(-1, -1)
	var id := TileDefs.id(tile_name)
	var box := cw.body.rect().grow(r)
	var best := Vector2i(-1, -1)
	var bd := INF
	var c := cw.body.center()
	for y in range(floori(box.position.y), floori(box.end.y) + 1):
		for x in range(floori(box.position.x), floori(box.end.x) + 1):
			if cw.world.in_bounds(x, y) and cw.world.get_fg(x, y) == id:
				var d := Vector2(x + 0.5, y + 0.5).distance_squared_to(c)
				if d < bd:
					bd = d
					best = Vector2i(x, y)
	return best

static func has(cw: ClientWorld, tile_name: String, r := 3) -> bool:
	return tile(cw, tile_name, r).x >= 0

## The nearest downed (not dead) ally within `r` tiles (centres): its id, or 0.
static func downed_ally(cw: ClientWorld, rules: RulesClient, r := 3.0) -> int:
	if rules == null:
		return 0
	var best := 0
	var bd := r
	for id: int in rules.downed:
		if id == cw.my_id or rules.state_of(id) == RulesCodec.Down.DEAD:
			continue
		var re: ClientWorld.RemoteEntity = cw.remotes.get(id)
		if re == null:
			continue
		var d := (re.pos + Vector2(0, re.size.y * 0.5)).distance_to(cw.body.center())
		if d <= bd:
			bd = d
			best = id
	return best
