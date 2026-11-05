## A character's kindled sparks: stars in the order kindled, joined by lines (the sigil).
## `slots` comes from the level (LevelTrack.spark_slots); the owner sets it. Each star keeps
## the spot it was inked at, also when its spark is swapped, so the drawing is stable.
## Saved in the Character record (Character.sparks).
##
##   var con := Constellation.new(); con.slots = LevelTrack.spark_slots(level)
##   con.kindle({"id": "fleet", "rank": 0})       # true if a slot was free and it is new
##   var old := con.swap(0, {"id": "fleet", "rank": 1})   # the replaced spark {id, rank}
class_name Constellation
extends RefCounted

## Grid the stars are placed on (x, y in 0..GRID-1).
const GRID := 16

var slots := 0
## [{id: String, rank: int, at: [x, y]}] in kindling order.
var kindled: Array = []
## Salt for star placement (the character's name), so two characters draw differently.
var salt := ""

func size() -> int:
	return kindled.size()

func has_spark(id: String) -> bool:
	for k: Dictionary in kindled:
		if String(k["id"]) == id:
			return true
	return false

## Why a spark cannot be kindled now ("" if it can): unknown, full, duplicate.
func kindle_refusal(spark: Dictionary) -> String:
	if not Sparks.exists(String(spark.get("id", ""))):
		return "unknown"
	if kindled.size() >= slots:
		return "full"
	if has_spark(String(spark["id"])):
		return "duplicate"
	return ""

func kindle(spark: Dictionary) -> bool:
	if kindle_refusal(spark) != "":
		return false
	kindled.append({"id": String(spark["id"]), "rank": clampi(int(spark.get("rank", 0)), 0, Sparks.RANKS - 1),
			"at": _spot(kindled.size())})
	return true

## Why star i cannot take this spark ("" if it can): unknown, no_star, duplicate.
func swap_refusal(i: int, spark: Dictionary) -> String:
	if not Sparks.exists(String(spark.get("id", ""))):
		return "unknown"
	if i < 0 or i >= kindled.size():
		return "no_star"
	if String(kindled[i]["id"]) != String(spark["id"]) and has_spark(String(spark["id"])):
		return "duplicate"
	return ""

## Put a spark on star i. Returns the spark that was there ({id, rank}), {} if refused.
func swap(i: int, spark: Dictionary) -> Dictionary:
	if swap_refusal(i, spark) != "":
		return {}
	var old: Dictionary = kindled[i]
	kindled[i] = {"id": String(spark["id"]), "rank": clampi(int(spark.get("rank", 0)), 0, Sparks.RANKS - 1), "at": old["at"]}
	return {"id": old["id"], "rank": old["rank"]}

## [{id, rank}] for Sparks.apply.
func list() -> Array:
	var out: Array = []
	for k: Dictionary in kindled:
		out.append({"id": k["id"], "rank": k["rank"]})
	return out

## The drawing: {stars: [Vector2i], lines: [[a, b]]} (lines join stars in kindling order).
func sigil() -> Dictionary:
	var stars: Array = []
	var lines: Array = []
	for i in kindled.size():
		var at: Array = kindled[i]["at"]
		stars.append(Vector2i(int(at[0]), int(at[1])))
		if i > 0:
			lines.append([i - 1, i])
	return {"stars": stars, "lines": lines}

## A free grid spot for star n, near the previous one, from a hash of salt and n.
func _spot(n: int) -> Array:
	var taken := {}
	for k: Dictionary in kindled:
		taken[Vector2i(int(k["at"][0]), int(k["at"][1]))] = true
	var prev := Vector2i(GRID / 2, GRID / 2)
	if not kindled.is_empty():
		prev = Vector2i(int(kindled[-1]["at"][0]), int(kindled[-1]["at"][1]))
	var h := hash("%s:%d" % [salt, n])
	for tries in 64:
		var dx := ((h >> (tries % 24)) % 7) - 3
		var dy := ((h >> ((tries + 7) % 24)) % 7) - 3
		var p := Vector2i(clampi(prev.x + dx, 0, GRID - 1), clampi(prev.y + dy, 0, GRID - 1))
		if n == 0:
			p = Vector2i(GRID / 2, GRID / 2)
		if not taken.has(p):
			return [p.x, p.y]
		h = hash(h + tries)
	for y in GRID:
		for x in GRID:
			if not taken.has(Vector2i(x, y)):
				return [x, y]
	return [0, 0]

func to_dict() -> Dictionary:
	var out: Array = []
	for k: Dictionary in kindled:
		out.append({"id": k["id"], "rank": k["rank"], "at": [int(k["at"][0]), int(k["at"][1])]})
	return {"kindled": out}

static func from_dict(d: Variant) -> Constellation:
	var c := Constellation.new()
	if d is Dictionary:
		for k: Variant in d.get("kindled", []):
			if k is Dictionary and Sparks.exists(String(k.get("id", ""))):
				var at: Array = k.get("at", [0, 0])
				c.kindled.append({"id": String(k["id"]), "rank": int(k.get("rank", 0)), "at": [int(at[0]), int(at[1])]})
	return c
