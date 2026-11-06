## What people say, and the rumours they pass on. Pure functions of the sim as it stands,
## the world seed, the person and the hour: nothing here rolls the sim's generator or
## changes the sim.
##
##   DealsTalk.situation(sim, sid) -> Array[String]     hungry, besieged, raided, war, ...
##   DealsTalk.line(sim, seed, person, sid, hour) -> String
##   DealsTalk.rumours(sim, sid, role, seen, n := -1) -> [{id, text, kind, site, dir, dist, tiles, t}]
##   DealsTalk.reach(world, body, their_box, tiles, sight) -> "" or far, no_sight (host and client)
class_name DealsTalk
extends RefCounted

## How far back rumours go (game days).
const RUMOUR_DAYS := 60
## Rumours told at once by role (others: 3).
const TELL := {"keeper": 5, "guard": 4, "merchant": 4}
## Days since a raid that the town still talks about it.
const RAIDED_DAYS := 30
## Wealth per head that makes a town prosperous.
const RICH := 2.0

## Can `me` speak to someone in the box `them`? "", "far" or "no_sight". The host's refusal and
## the client's prompt both ask this, on their own copies of the world.
static func reach(world: TileWorld, me: Body, them: Rect2, tiles: float, sight := true) -> String:
	if me.center().distance_to(them.get_center()) > tiles:
		return "far"
	if sight and not HitShapes.line_to(world, CombatSight.eye_of(me), them):
		return "no_sight"
	return ""

## The town's situation from the sim, most pressing first.
static func situation(sim: WorldSim, sid: int) -> Array:
	var out: Array = []
	var s: SimSettlement = sim.settlements.get(sid)
	if s == null:
		return out
	if s.besieged_by >= 0:
		out.append("besieged")
	if sim.t - s.last_raided < RAIDED_DAYS * WorldSim.DAY_H or raided_lately(sim, s):
		out.append("raided")
	if foe_of(sim, s.faction) >= 0:
		out.append("war")
	if hungry(sim, s):
		out.append("hungry")
	if caravan_due(sim, sid) >= 0:
		out.append("caravan_due")
	if s.pop() > 0 and s.wealth / float(s.pop()) >= RICH and s.morale >= 0.6:
		out.append("prosperous")
	if out.is_empty():
		out.append("quiet")
	return out

## A raid or a monster attack on the town in the chronicle within RAIDED_DAYS (won or not).
static func raided_lately(sim: WorldSim, s: SimSettlement) -> bool:
	var since := sim.t - RAIDED_DAYS * WorldSim.DAY_H
	for i in range(sim.chronicle.size() - 1, -1, -1):
		var e: Dictionary = sim.chronicle[i]
		if int(e.get("t", 0)) < since:
			break
		if String(e.get("kind", "")) in ["raid", "raid_repelled", "monster_raid", "apex_wrath", "sacked"] and str(e.get("site", "")) == s.name:
			return true
	return false

static func hungry(_sim: WorldSim, s: SimSettlement) -> bool:
	return s.hungry > 0 or SimEconomy.price(s, "food") >= 2.0 * float(SimData.goods["food"]["base"])

## A faction this one is at war with (lowest id), or -1.
static func foe_of(sim: WorldSim, fid: int) -> int:
	var f: SimFaction = sim.factions.get(fid)
	if f == null:
		return -1
	var ids: Array = f.wars.keys()
	ids.sort()
	for o: Variant in ids:
		if sim.factions.has(int(o)):
			return int(o)
	return -1

## The site a caravan coming here is from (the first such party), or -1.
static func caravan_due(sim: WorldSim, sid: int) -> int:
	for pid: int in WorldSim._sorted_keys(sim.parties):
		var p: SimParty = sim.parties[pid]
		if p.kind == "caravan" and p.dest == sid and p.state == "travel" and p.home != sid:
			return p.home
	return -1

static func hour_band(hour: float) -> String:
	if hour >= 5.0 and hour < 11.0:
		return "morning"
	if hour >= 11.0 and hour < 17.0:
		return "day"
	if hour >= 17.0 and hour < 21.0:
		return "evening"
	return "night"

## What a person says on being spoken to: a greeting by role, then the town's situation
## (or the hour when nothing is happening), now and then a word of the culture.
## person: {id (stable key), role, name, culture}.
static func line(sim: WorldSim, world_seed: int, person: Dictionary, sid: int, hour: float) -> String:
	var L := Deals.lines()
	var role := String(person.get("role", "_"))
	var key := [world_seed, "talk", String(person.get("key", person.get("name", ""))), Deals.day(sim), hour_band(hour)]
	var greet: Array = L["greet"].get(role, L["greet"]["_"])
	var parts: Array = [String(Deals.pick(greet, key + ["g"]))]
	var s: SimSettlement = sim.settlements.get(sid)
	if s != null:
		var sit: String = situation(sim, sid)[0]
		var vars := {"town": s.name, "faction": sim.faction_name(s.faction)}
		var foe := foe_of(sim, s.faction)
		vars["foe"] = sim.faction_name(foe) if foe >= 0 else "someone"
		var due := caravan_due(sim, sid)
		vars["dest"] = sim._site_label(due) if due >= 0 else "somewhere"
		if sit == "quiet" and Deals.h(key + ["q"]) % 2 == 0:
			parts.append(String(Deals.pick(L["time"][hour_band(hour)], key + ["t"])))
		else:
			parts.append(Deals.fill(String(Deals.pick(L["situation"][sit], key + ["s"])), vars))
		var cl: Array = L["culture"].get(s.culture, [])
		if not cl.is_empty() and Deals.h(key + ["c"]) % 3 == 0:
			parts.append(String(Deals.pick(cl, key + ["cw"])))
	else:
		parts.append(String(Deals.pick(L["time"][hour_band(hour)], key + ["t"])))
	return " ".join(parts)

## The names a town's talk is about: the town, its faction, its neighbours, the routes out
## of it and the lairs on them. name -> true.
static func concerns(sim: WorldSim, sid: int) -> Dictionary:
	var out := {}
	var s: SimSettlement = sim.settlements.get(sid)
	if s != null:
		out[s.name] = true
		out[sim.faction_name(s.faction)] = true
	for n: int in Deals.neighbours(sim, sid):
		out[sim._site_label(n)] = true
		if sim.settlements.has(n):
			out[sim.faction_name(sim.settlements[n].faction)] = true
	for rid: int in Deals.routes_of(sim, sid):
		out[sim.route_name(rid)] = true
	for lid: int in Deals.lairs_on_routes(sim, sid):
		out[sim.lairs[lid].name] = true
	return out

const NAME_FIELDS := ["site", "lair", "to", "from", "vfrom", "rfrom", "pfrom", "a", "b", "army", "faction",
	"rfaction", "dfaction", "old", "route", "places"]
const SITE_FIELDS := ["site", "lair", "to", "from", "vfrom", "rfrom", "pfrom"]

## Recent chronicle events about a town, its faction, its routes and neighbours, that a person
## of `role` would know (data/deals/lines.json `knows`), newest first. Each with the site it
## concerns (or -1) and where that is from the town. seen: name -> site id for fallen places.
static func rumours(sim: WorldSim, sid: int, role: String, seen: Dictionary, n := -1) -> Array:
	var L := Deals.lines()
	var knows: Array = L["knows"].get(role, L["knows"].get("townsfolk", []))
	var all := "*" in knows
	if n < 0:
		n = int(TELL.get(role, 3))
	var about := concerns(sim, sid)
	var since := sim.t - RUMOUR_DAYS * WorldSim.DAY_H
	var out: Array = []
	var i := sim.chronicle.size() - 1
	while i >= 0 and out.size() < n:
		var e: Dictionary = sim.chronicle[i]
		if int(e.get("t", 0)) < since:
			break
		if (all or String(e.get("kind", "")) in knows) and _about(e, about):
			out.append(rumour(sim, sid, i, seen))
		i -= 1
	return out

static func _about(e: Dictionary, about: Dictionary) -> bool:
	for f: String in NAME_FIELDS:
		if not e.has(f):
			continue
		var v := str(e[f])
		if about.has(v):
			return true
		if f == "places":
			for k: String in about:
				if k in v:
					return true
	return false

## One chronicle entry as a rumour told at a town.
static func rumour(sim: WorldSim, sid: int, index: int, seen: Dictionary) -> Dictionary:
	var e: Dictionary = sim.chronicle[index]
	var site := -1
	for f: String in SITE_FIELDS:
		if e.has(f):
			site = Deals.site_named(sim, str(e[f]), seen)
			if site >= 0:
				break
	if site < 0 and e.has("route"):
		for rid: int in Deals.routes_of(sim, sid):
			if sim.route_name(rid) == str(e["route"]):
				var r: Dictionary = sim.route_by_id[rid]
				site = int(r.b) if int(r.a) == sid else int(r.a)
	var out := {"id": index, "text": sim.describe(e), "kind": String(e.get("kind", "")), "t": int(e.get("t", 0)), "site": site,
		"dir": "", "dist": "", "tiles": 0}
	if site >= 0 and sim.site_by_id.has(site) and sim.site_by_id.has(sid):
		out.merge(Deals.where(sim, sid, site), true)
		out["site"] = site
	return out
