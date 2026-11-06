## The client half of Deals: the open conversation, the shop as this player would pay, the
## quest log, the rumours heard (with site ids for a map) and patron tiers. Every request is
## validated on the host; answers come back as `note(op, ok, word)` and the mirrors update.
##
##   var dc := cw.system(HostSystem.DEALS) as DealsClient
##   dc.talk_changed.connect(func(c): ...)      c: {open, id, name, role, site, line, options, ...}
##   dc.talk(entity_id); dc.choose("shop"); dc.buy("s2", 1); dc.sell(14, 5); dc.leave()
##   dc.accept(qid); dc.turn_in(qid); dc.abandon(qid); dc.service("bed")
## State: conversation, shop, quests, rumours, patrons (see the signals). Docs:
## docs/tracks/deals.md ("The client surface").
class_name DealsClient
extends ClientSystem

signal talk_changed(conversation: Dictionary)
signal shop_changed(shop: Dictionary)
signal quests_changed(quests: Array)
## Rumours heard just now; rumours_reset: the whole list came back (on joining).
signal rumour_heard(rumours: Array)
signal rumours_reset()
signal patron_changed(patrons: Dictionary)
signal note(op: int, ok: bool, word: String)
## The atlas changed (sites, routes or seen); `fresh` the sites first stood at just now.
signal atlas_changed(fresh: Array)

var cw: ClientWorld
## {} when closed; else {open, id, name, role, site, faction, line, view, options: [{id, label}],
## rumours?, offers?}
var conversation := {}
## {} when closed; else {open, kind, site, town, listings: [{id, item, n, price}], sell: {slot: price}, wealth}
var shop := {}
## The quest log: open quests (with progress and `where`) and ended ones (state done, failed,
## lapsed, beaten, abandoned).
var quests: Array = []
## Rumours heard, oldest first: {id, text, kind, t, site, dir, dist, tiles}.
var rumours: Array = []
## faction id -> {tier, standing, given, suspended, name}
var patrons := {}
## The last closing reason and line ({why, line}).
var closed := {}
## The last answer from the host per request kind.
var last_note := {}
## ATLAS (for the map and place banners): site id -> {id, kind, name, culture, tier, pop,
## faction, state, work, lair, apex, ruin}; routes [{id, a, b, kind, name, path: [Vector2i]}];
## seen: site id -> true (stood at); sim_t: the sim hour when last heard, at clock_h.
var sites := {}
var routes: Array = []
var seen := {}
var sim_t := 0
var clock_h := 0.0

## How near a person must be for the talk prompt (the host allows DealsSystem.TALK_RANGE).
const PROMPT_RANGE := 4.0

func sys_id() -> int:
	return HostSystem.DEALS

func attach(c: ClientWorld) -> void:
	cw = c

func handle(kind: int, data: PackedByteArray) -> void:
	var d := DealsCodec.read(data)
	match kind:
		DealsCodec.Msg.TALK:
			if bool(d.get("open", false)):
				d["id"] = int(d.get("id", 0))
				d["site"] = int(d.get("site", -1))
				for k: String in ["rumours", "new"]:
					if d.has(k):
						d[k] = (d[k] as Array).map(func(r: Variant) -> Dictionary: return _rumour(r))
				if d.has("offers"):
					d["offers"] = (d["offers"] as Array).map(func(q: Variant) -> Dictionary: return _quest(q))
				conversation = d
			else:
				conversation = {}
				shop = {}
				closed = {"why": String(d.get("why", "")), "line": String(d.get("line", ""))}
			talk_changed.emit(conversation)
		DealsCodec.Msg.SHOP:
			if bool(d.get("open", false)):
				var ls: Array = []
				for l: Dictionary in d.get("listings", []):
					ls.append({"id": String(l["id"]), "item": DealsCodec.item(l["item"]), "n": int(l["n"]), "price": int(l["price"])})
				d["listings"] = ls
				var sp := {}
				for k: String in d.get("sell", {}):
					sp[int(k)] = int(d["sell"][k])
				d["sell"] = sp
				d["site"] = int(d.get("site", -1))
				d["wealth"] = int(d.get("wealth", 0))
				shop = d
			else:
				shop = {}
			shop_changed.emit(shop)
		DealsCodec.Msg.QUESTS:
			quests = (d.get("quests", []) as Array).map(func(q: Variant) -> Dictionary: return _quest(q))
			quests_changed.emit(quests)
		DealsCodec.Msg.RUMOUR:
			var list: Array = (d.get("rumours", []) as Array).map(func(r: Variant) -> Dictionary: return _rumour(r))
			if bool(d.get("all", false)):
				rumours = list
				rumours_reset.emit()
			else:
				rumours.append_array(list)
				rumour_heard.emit(list)
		DealsCodec.Msg.PATRON:
			patrons = {}
			var src: Dictionary = d.get("patrons", {})
			for f: String in src:
				var p: Dictionary = src[f]
				patrons[f] = {"tier": int(p.get("tier", 0)), "standing": int(p.get("standing", 0)), "given": int(p.get("given", 0)),
					"suspended": bool(p.get("suspended", false)), "name": String(p.get("name", ""))}
			patron_changed.emit(patrons)
		DealsCodec.Msg.ATLAS:
			sim_t = int(d.get("t", sim_t))
			clock_h = cw.hours() if cw != null else 0.0
			if bool(d.get("all", false)):
				sites = {}
				seen = {}
			for sd: Dictionary in d.get("sites", []):
				var x := sd.duplicate()
				for k: String in ["id", "pop"]:
					if x.has(k):
						x[k] = int(x[k])
				sites[int(x["id"])] = x
			if d.has("routes"):
				routes = []
				for r: Dictionary in d["routes"]:
					var pts: Array = []
					for c: Array in r.get("path", []):
						pts.append(Vector2i(int(c[0]), int(c[1])))
					routes.append({"id": int(r["id"]), "a": int(r["a"]), "b": int(r["b"]), "kind": String(r.get("kind", "")),
						"name": String(r.get("name", "")), "path": pts})
			var fresh: Array = []
			for sid: Variant in d.get("seen", []):
				if not seen.has(int(sid)):
					seen[int(sid)] = true
					fresh.append(int(sid))
			atlas_changed.emit(fresh if not bool(d.get("all", false)) else [])
		DealsCodec.Msg.NOTE:
			var op := int(d.get("op", 0))
			last_note[op] = String(d.get("word", ""))
			note.emit(op, bool(d.get("ok", false)), String(d.get("word", "")))

static func _rumour(r: Variant) -> Dictionary:
	var d: Dictionary = (r as Dictionary).duplicate() if r is Dictionary else {}
	for k: String in ["id", "t", "site", "tiles"]:
		d[k] = int(d.get(k, -1))
	return d

static func _quest(q: Variant) -> Dictionary:
	return DealsCodec.quest(q)

# --- state ---------------------------------------------------------------------------------

func talking() -> bool:
	return not conversation.is_empty()

func shopping() -> bool:
	return not shop.is_empty()

## Quests by state ("active" includes "ready").
func quests_in(state: String) -> Array:
	return quests.filter(func(q: Dictionary) -> bool:
		var s := String(q.get("state", ""))
		return s == state or (state == "active" and s == "ready"))

## Rumours with a place, for the map: [{site, text, dir, dist}].
func map_marks() -> Array:
	return rumours.filter(func(r: Dictionary) -> bool: return int(r["site"]) >= 0)

## The sim's hour now, from the last ATLAS and the clock since (quest `due` is in sim hours).
func sim_hour() -> float:
	return sim_t + ((cw.hours() - clock_h) if cw != null else 0.0)

## A site's name ("" when unknown).
func site_name(sid: int) -> String:
	return String(sites.get(sid, {}).get("name", ""))

# --- requests (validated on the host) -------------------------------------------------------

## The nearest person the host would talk to now, or 0: what the talk prompt shows.
func nearest_person() -> int:
	var lc := cw.system(HostSystem.LIFE) as LifeClient if cw != null else null
	if lc == null:
		return 0
	var best := 0
	var bd := INF
	for id: int in lc.people:
		var r: ClientWorld.RemoteEntity = cw.remotes.get(id)
		if r == null:
			continue
		var d := cw.body.center().distance_to(r.pos + Vector2(0.0, r.size.y * 0.5))
		if d < bd and would_talk(id):
			bd = d
			best = id
	return best

## Would the host talk to this person now? The same reach as DealsSystem.can_talk, from a little
## nearer (PROMPT_RANGE: a person may walk on while the request travels), and its other
## refusals as far as a client can tell: a fight, being down, a faction's hostility. A grudge
## is known to the host alone: that one is still refused after the prompt.
func would_talk(id: int) -> bool:
	var lc := cw.system(HostSystem.LIFE) as LifeClient
	var r: ClientWorld.RemoteEntity = cw.remotes.get(id)
	if lc == null or r == null or not bool(lc.person(id).get("talk", false)):
		return false
	var cc := cw.system(HostSystem.COMBAT) as CombatClient
	if cc != null and (cc.in_fight(cw.my_id) or cc.in_fight(id)):
		return false
	var rc := cw.system(HostSystem.RULES) as RulesClient
	if rc != null and rc.is_downed():
		return false
	var f := String(lc.person(id).get("faction", ""))
	if Life.is_sim_faction(f) and lc.standing(f) <= int(Life.num("hostile_at", -40)):
		return false
	return DealsTalk.reach(cw.world, cw.body, Rect2(r.pos - Vector2(r.size.x * 0.5, 0.0), r.size), PROMPT_RANGE) == ""

func talk(entity_id: int) -> void:
	_send(DealsCodec.Msg.TALK_TO, {"e": entity_id})

func choose(option_id: String) -> void:
	_send(DealsCodec.Msg.CHOOSE, {"o": option_id})

func leave() -> void:
	_send(DealsCodec.Msg.LEAVE, {})

func buy(listing_id: String, n := 1) -> void:
	_send(DealsCodec.Msg.BUY, {"l": listing_id, "n": n})

func sell(inventory_slot: int, n := 1) -> void:
	_send(DealsCodec.Msg.SELL, {"s": inventory_slot, "n": n})

func service(id: String) -> void:
	_send(DealsCodec.Msg.SERVICE, {"id": id})

func accept(quest_id: String) -> void:
	_send(DealsCodec.Msg.ACCEPT, {"q": quest_id})

func abandon(quest_id: String) -> void:
	_send(DealsCodec.Msg.ABANDON, {"q": quest_id})

func turn_in(quest_id: String) -> void:
	_send(DealsCodec.Msg.TURN_IN, {"q": quest_id})

## Cheats (the host must run with `cheats`): {op: goto, role} / {op: coin, n} / {op: give, base, n}
## / {op: standing, faction, n} / {op: complete, q}.
func cheat(d: Dictionary) -> void:
	_send(DealsCodec.Msg.CHEAT, d)

func _send(kind: int, d: Dictionary) -> void:
	if cw != null:
		cw.send_sys(sys_id(), kind, DealsCodec.write(d))
