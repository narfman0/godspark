## A path from MonsterNav: nodes (left column, feet row) from the start, and for each the
## edge that reaches it (how[i] & 15 = MonsterNav.Edge, how[i] >> 4 = extra: the jump index
## into prof.jumps, or the cling side and height). how[0] = -1.
class_name NavPath
extends RefCounted

var prof: NavProfile
var nodes: Array[Vector2i] = []
var how := PackedInt32Array()
## True if it ends at the goal (false: the reachable node nearest it).
var reached := false
var goal := Vector2i.ZERO
var cost := 0.0

func size() -> int:
	return nodes.size()

func end_node() -> Vector2i:
	return nodes[nodes.size() - 1] if not nodes.is_empty() else Vector2i.ZERO

## Cells the path's bodies cover, grown by a margin: a tile change inside it may break it.
func bounds(margin := 2) -> Rect2i:
	if nodes.is_empty():
		return Rect2i()
	var lo := nodes[0]
	var hi := nodes[0]
	for n in nodes:
		lo = Vector2i(mini(lo.x, n.x), mini(lo.y, n.y))
		hi = Vector2i(maxi(hi.x, n.x), maxi(hi.y, n.y))
	return Rect2i(lo - Vector2i(margin, margin), hi - lo + Vector2i(prof.cw + 2 * margin, prof.ch + 2 * margin))

func describe() -> String:
	var names := MonsterNav.EDGE_NAMES
	var parts := PackedStringArray()
	for i in nodes.size():
		var e := how[i]
		parts.append(("%s>" % names[e & 15] if e >= 0 else "") + "%d,%d" % [nodes[i].x, nodes[i].y])
	return " ".join(parts)

## How many edges of each kind (for tests and reports).
func counts() -> Dictionary:
	var out := {}
	for i in range(1, how.size()):
		var e := how[i] & 15
		out[e] = int(out.get(e, 0)) + 1
	return out
