## A group on the move: caravan, raid, patrol, army, migrants, settlers, expedition or
## monster pack. Its position is recoverable as (route id, fraction along the route from
## route.a), which is what materialization needs.
class_name SimParty
extends RefCounted

var id := 0
var kind := "caravan"
var faction := -1         # owner faction, -1 for monsters
var culture := ""         # culture id, or lair kind for monster packs
var home := -1            # settlement or lair site id
var members := {}         # slug -> count (whole creatures)
var people := 0           # non-combatants among members who return to the workforce
var wagons := 0
var cargo := {}           # good -> int
var coin := 0.0
var path: Array[int] = [] # site ids, path[0] is where this leg started
var leg := 0              # travelling from path[leg] to path[leg + 1]
var frac := 0.0           # 0..1 along the current leg, in travel direction
var route := -1           # route id of the current leg
var state := "travel"     # travel | ambush | patrol | siege | done
var timer := 0.0          # hours left in ambush / patrol / siege
var target := -1          # target site id (settlement, lair) or route id for ambushes
var dest := -1            # final site of the current path
var plan := {}            # kind-specific extras; values are floats or strings only (JSON-safe)
# Materialization (Life track), transient: not saved, never set by the sim itself.
## Someone is watching it as real actors: its fights are fought in real time, not resolved here.
var watched := false
## Held by real time as well: the sim neither moves it nor runs its timers or arrival.
var frozen := false

func size() -> int:
	return SimData.count(members)

func cur_site() -> int:
	return path[leg] if leg < path.size() else -1

func to_dict() -> Dictionary:
	return {"id": id, "kind": kind, "faction": faction, "culture": culture, "home": home,
		"members": members.duplicate(), "people": people, "wagons": wagons, "cargo": cargo.duplicate(),
		"coin": coin, "path": Array(path), "leg": leg, "frac": frac, "route": route, "state": state,
		"timer": timer, "target": target, "dest": dest, "plan": plan.duplicate(true)}

static func from_dict(d: Dictionary) -> SimParty:
	var p := SimParty.new()
	p.id = int(d.id); p.kind = d.kind; p.faction = int(d.faction); p.culture = d.culture
	p.home = int(d.home)
	for k in d.members:
		p.members[k] = int(d.members[k])
	p.people = int(d.people); p.wagons = int(d.wagons)
	for k in d.cargo:
		p.cargo[k] = int(d.cargo[k])
	p.coin = float(d.coin)
	for s in d.path:
		p.path.append(int(s))
	p.leg = int(d.leg); p.frac = float(d.frac); p.route = int(d.route); p.state = d.state
	p.timer = float(d.timer); p.target = int(d.target); p.dest = int(d.dest)
	p.plan = (d.plan as Dictionary).duplicate(true)
	return p
