## Shared pieces of the Deals track: its data tables, hash-seeded choices (never the sim's
## generator, never the rules dice), where things are from a town, and names to site ids.
##
##   Deals.lines() / prices() / quests()     data/deals/*.json
##   Deals.rng([world seed, "rack", site, day]) -> RandomNumberGenerator
##   Deals.pick(arr, key) -> Variant          one element by a hash of key
##   Deals.where(sim, from_site, to_site) -> {site, dir, dist, tiles}
## Docs: docs/tracks/deals.md.
class_name Deals
extends RefCounted

const LINES_PATH := "res://data/deals/lines.json"
const PRICES_PATH := "res://data/deals/prices.json"
const QUESTS_PATH := "res://data/deals/quests.json"
static var _lines := {}
static var _prices := {}
static var _quests := {}

static func lines() -> Dictionary:
	if _lines.is_empty():
		_lines = JSON.parse_string(FileAccess.get_file_as_string(LINES_PATH))
	return _lines

static func prices() -> Dictionary:
	if _prices.is_empty():
		_prices = JSON.parse_string(FileAccess.get_file_as_string(PRICES_PATH))
	return _prices

static func quests() -> Dictionary:
	if _quests.is_empty():
		_quests = JSON.parse_string(FileAccess.get_file_as_string(QUESTS_PATH))
	return _quests

static func num(d: Dictionary, key: String, def: float) -> float:
	return float(d.get(key, def))

## A non-negative hash of a key.
static func h(key: Array) -> int:
	return hash(key) & 0x7fffffff

static func rng(key: Array) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(key)
	return r

static func pick(arr: Array, key: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[h(key) % arr.size()]

## A key of a weights dictionary {key: weight}, chosen by r.
static func weighted(r: RandomNumberGenerator, weights: Dictionary) -> String:
	var keys: Array = weights.keys()
	keys.sort()
	var w: Array = []
	for k: String in keys:
		w.append(float(weights[k]))
	return String(keys[ItemGen.weighted(r, w)]) if not keys.is_empty() else ""

## The game day of the sim (whole days since it began).
static func day(sim: WorldSim) -> int:
	return sim.t / WorldSim.DAY_H

## A site's position in tiles (x, y), from the sim's site table.
static func site_xy(sim: WorldSim, sid: int) -> Vector2:
	var s: Dictionary = sim.site_by_id.get(sid, {})
	return Vector2(float(s.get("x", 0)), float(s.get("y", 0)))

## Is pos at a site: inside its place's rect grown by `margin` tiles, or (a site without a
## place) within `margin` + 30 tiles of its cell.
static func at_site(world: TileWorld, sim: WorldSim, sid: int, pos: Vector2, margin: float) -> bool:
	var pl := Places.place(world, sid) if world != null else {}
	var r: Array = pl.get("rect", [])
	if r.size() == 4:
		return Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])).grow(margin).has_point(pos)
	return pos.distance_to(site_xy(sim, sid)) <= margin + 30.0

## Where `to` lies from `from`: a rough direction and distance in words, and the tiles.
static func where(sim: WorldSim, from: int, to: int) -> Dictionary:
	var a := site_xy(sim, from)
	var b := site_xy(sim, to)
	var d := b - a
	var tiles := roundi(d.length())
	var dir := "east" if d.x >= 0.0 else "west"
	if absf(d.y) > 60.0 and absf(d.y) > absf(d.x) * 0.5:
		dir = ("below and " if d.y < 0.0 else "above and ") + dir
	var dist := "close by"
	if tiles > 1500:
		dist = "far away"
	elif tiles > 700:
		dist = "a long walk"
	elif tiles > 300:
		dist = "a fair walk"
	elif tiles > 120:
		dist = "a short walk"
	if from == to:
		dir = ""
		dist = "here"
	return {"site": to, "dir": dir, "dist": dist, "tiles": tiles}

## A name in the chronicle -> site id: settlements and lairs as they are now, then names Deals
## has seen before (`seen`: name -> site id), else -1.
static func site_named(sim: WorldSim, name: String, seen: Dictionary) -> int:
	if name == "":
		return -1
	for sid: int in sim.settlements:
		if sim.settlements[sid].name == name:
			return sid
	for lid: int in sim.lairs:
		if sim.lairs[lid].name == name:
			return lid
	return int(seen.get(name, -1))

## Adjacent site ids of a site (by any route), sorted.
static func neighbours(sim: WorldSim, sid: int) -> Array:
	var out: Array = []
	for nr: Array in sim.adj.get(sid, []):
		if not int(nr[0]) in out:
			out.append(int(nr[0]))
	out.sort()
	return out

## The towns a message goes to: by road, or down a link only for a town with no road (a surface
## keeper does not send word to the drow by a sinkhole's rope).
static func message_towns(sim: WorldSim, sid: int) -> Array:
	var out: Array = []
	for nr: Array in sim.adj.get(sid, []):
		if int(sim.route_by_id[int(nr[1])].cls) != WorldSim.LINK and not int(nr[0]) in out:
			out.append(int(nr[0]))
	out.sort()
	return out if not out.is_empty() else neighbours(sim, sid)

## Route ids touching a site.
static func routes_of(sim: WorldSim, sid: int) -> Array:
	var out: Array = []
	for nr: Array in sim.adj.get(sid, []):
		if not int(nr[1]) in out:
			out.append(int(nr[1]))
	out.sort()
	return out

## Lair site ids that hunt the routes out of a site.
static func lairs_on_routes(sim: WorldSim, sid: int) -> Array:
	var out: Array = []
	for rid: int in routes_of(sim, sid):
		for lid: Variant in sim.route_lair_sites.get(rid, []):
			if sim.lairs.has(int(lid)) and not int(lid) in out:
				out.append(int(lid))
	out.sort()
	return out

static func fill(text: String, vars: Dictionary) -> String:
	var out := text
	for k: String in vars:
		out = out.replace("{%s}" % k, str(vars[k]))
	return out
