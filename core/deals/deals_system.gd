## Deals (HostSystem.DEALS): talk, trade, quests and patrons with the sim's people. A player
## near a person Life shows (meta `talk`) asks to talk; the host answers with what that person
## says now and what they offer: rumours (real chronicle events with places), a shop (the
## store's shelves and the smith's rack, from the sim's stocks and prices), work (quests made
## from the sim's state), services (a bed, healing) and patronage. Buying and selling go
## through the sim's books (WorldSim.player_trade); rewards through Items (inventory), Rules
## (award_xp, add_deed, set_bed, heal) and Life (add_standing). Everything Deals makes up
## (lines, racks, offers) comes from hashes of (world seed, ids, day): looking never changes
## the sim. Messages: DealsCodec; client mirror: DealsClient. Docs: docs/tracks/deals.md.
##
##   deals.talk(e, person_id) -> String       "" or a refusal word (what TALK_TO does)
##   deals.offers_at(sid) -> Array            today's quest offers at a settlement
##   deals.quest(qid) -> Dictionary; deals.summary() -> String
class_name DealsSystem
extends HostSystem

## Tiles (body centres) within which a player may start talking, and keep talking.
## Past the prompt's range (DealsClient.PROMPT_RANGE) by a walking person's way in 0.4 s: the
## view's delay and a round trip. E only goes out with the prompt showing, so this is no reach.
const TALK_RANGE := 6.5
const KEEP_RANGE := 8.5
## Ended quests are kept this many game days (so offline party members see the outcome).
const KEEP_ENDED_DAYS := 30
const MAX_KNOWN := 120

var host: WorldHost:
	get:
		return _host.get_ref() if _host != null else null
var _host: WeakRef
var cheats := false
## Quest id -> where its moving target was last told to the players.
var _pointed := {}
var debug := false
## player id -> open conversation {person, site, kind, role, of, faction, view, shop}
var talks := {}
## player id -> [rumour] heard (newest last)
var known := {}
## player id -> {qid: ended quest snapshot}
var logs := {}
## player id -> {faction: highest tier gift given}
var gifts := {}
## player id -> {faction: tier last sent}
var _patron_sent := {}
## site id -> {day, list}: the day's offers, kept for the day
var offers := {}
## qid -> quest (accepted; ended ones for KEEP_ENDED_DAYS)
var quests := {}
## site id -> {day, sold: {piece index: true}}
var sold := {}
## chronicle name -> site id, for rumours about places that have since fallen
var names := {}
## player id -> {site id: true}: sites the player has stood at (saved; the map's discovery)
var seen := {}
## The last ATLAS site list sent (a digest), to send it again only on change.
var _atlas_digest := ""
var stats := {"talks": 0, "refused": 0, "bought": 0, "sold": 0, "coin_in": 0, "coin_out": 0, "accepted": 0,
	"done": 0, "failed": 0, "lapsed": 0, "beaten": 0, "rumours": 0, "gifts": 0}

func sys_id() -> int:
	return HostSystem.DEALS

func attach(h: WorldHost) -> void:
	_host = weakref(h)
	SimData.ensure()
	Items.ensure()
	cheats = RulesSystem.cmdline_cheats()

func _sys(h: WorldHost, id: int) -> HostSystem:
	return h.system(id) if h != null else null

func life() -> LifeSystem:
	return _sys(host, HostSystem.LIFE) as LifeSystem

func _rules() -> HostSystem:
	return _sys(host, HostSystem.RULES)

func _items() -> HostSystem:
	return _sys(host, HostSystem.ITEMS)

func _seed() -> int:
	return host.world.world_seed

# --- saving ------------------------------------------------------------------------------------

func save_player(e: HostEntity) -> Dictionary:
	return {"known": (known.get(e.id, []) as Array).duplicate(true), "log": (logs.get(e.id, {}) as Dictionary).duplicate(true),
		"gifts": (gifts.get(e.id, {}) as Dictionary).duplicate(), "seen": (seen.get(e.id, {}) as Dictionary).keys()}

func load_player(e: HostEntity, d: Dictionary) -> void:
	var k: Array = []
	for r: Variant in d.get("known", []):
		if r is Dictionary:
			k.append(_rumour_clean(r))
	known[e.id] = k
	var lg := {}
	var src: Variant = d.get("log", {})
	if src is Dictionary:
		for qid: String in src:
			lg[qid] = src[qid]
	logs[e.id] = lg
	var g := {}
	var gs: Variant = d.get("gifts", {})
	if gs is Dictionary:
		for f: String in gs:
			g[f] = int(gs[f])
	gifts[e.id] = g
	var sn := {}
	for sid: Variant in d.get("seen", []):
		sn[int(sid)] = true
	seen[e.id] = sn

static func _rumour_clean(r: Dictionary) -> Dictionary:
	var out := r.duplicate()
	for k: String in ["id", "t", "site", "tiles"]:
		out[k] = int(r.get(k, -1))
	return out

func save_world() -> Dictionary:
	var sd := {}
	for sid: int in sold:
		sd[str(sid)] = {"day": int(sold[sid]["day"]), "sold": (sold[sid]["sold"] as Dictionary).keys()}
	var od := {}
	for sid: int in offers:
		od[str(sid)] = offers[sid]
	return {"quests": quests.duplicate(true), "offers": od, "sold": sd, "names": names.duplicate()}

func load_world(d: Dictionary) -> void:
	quests = {}
	var q: Variant = d.get("quests", {})
	if q is Dictionary:
		for qid: String in q:
			quests[qid] = DealsCodec.quest(q[qid])
	offers = {}
	var o: Variant = d.get("offers", {})
	if o is Dictionary:
		for k: String in o:
			var list: Array = []
			for x: Variant in o[k].get("list", []):
				list.append(DealsCodec.quest(x))
			offers[int(k)] = {"day": int(o[k].get("day", -1)), "list": list}
	sold = {}
	var s: Variant = d.get("sold", {})
	if s is Dictionary:
		for k: String in s:
			var m := {}
			for i: Variant in s[k].get("sold", []):
				m[int(i)] = true
			sold[int(k)] = {"day": int(s[k].get("day", -1)), "sold": m}
	names = {}
	var n: Variant = d.get("names", {})
	if n is Dictionary:
		for k: String in n:
			names[k] = int(n[k])

# --- joining and leaving ----------------------------------------------------------------------

func entity_added(h: WorldHost, e: HostEntity) -> void:
	if not e.is_player():
		return
	if not known.has(e.id):
		known[e.id] = []
	if not logs.has(e.id):
		logs[e.id] = {}
	if not gifts.has(e.id):
		gifts[e.id] = {}
	if not seen.has(e.id):
		seen[e.id] = {}
	_send(e.id, DealsCodec.Msg.RUMOUR, {"rumours": known[e.id], "all": true})
	_send_quests(e)
	_patron_sent.erase(e.id)
	if h.sim != null:
		_send(e.id, DealsCodec.Msg.ATLAS, {"t": h.sim.t, "sites": atlas_sites(), "routes": atlas_routes(),
			"seen": (seen[e.id] as Dictionary).keys(), "all": true})

func entity_removed(_h: WorldHost, e: HostEntity) -> void:
	talks.erase(e.id)
	if e.is_player():
		_patron_sent.erase(e.id)
	else:
		for pid: int in talks.keys():
			if int(talks[pid]["person"]) == e.id:
				_close(pid, "gone")

# --- the wire ----------------------------------------------------------------------------------

func _send(pid: int, kind: int, d: Dictionary) -> void:
	host.send_sys(sys_id(), kind, DealsCodec.write(d), pid)

func _note(pid: int, op: int, word: String) -> void:
	_send(pid, DealsCodec.Msg.NOTE, {"op": op, "ok": word == "", "word": word if word != "" else "ok"})

func handle(_h: WorldHost, e: HostEntity, kind: int, data: PackedByteArray) -> void:
	if e == null or not e.is_player():
		return
	var d := DealsCodec.read(data)
	var why := ""
	match kind:
		DealsCodec.Msg.TALK_TO:
			why = talk(e, int(d.get("e", 0)))
		DealsCodec.Msg.CHOOSE:
			why = choose(e, String(d.get("o", "")))
		DealsCodec.Msg.LEAVE:
			if talks.has(e.id):
				_close(e.id, "left")
		DealsCodec.Msg.BUY:
			why = buy(e, String(d.get("l", "")), int(d.get("n", 1)))
		DealsCodec.Msg.SELL:
			why = sell(e, int(d.get("s", -1)), int(d.get("n", 1)))
		DealsCodec.Msg.SERVICE:
			why = service(e, String(d.get("id", "")))
		DealsCodec.Msg.ACCEPT:
			why = accept(e, String(d.get("q", "")))
		DealsCodec.Msg.ABANDON:
			why = abandon(e, String(d.get("q", "")))
		DealsCodec.Msg.TURN_IN:
			why = turn_in(e, String(d.get("q", "")))
		DealsCodec.Msg.CHEAT:
			why = cheat(e, d) if cheats else "no_cheats"
		_:
			return
	if kind != DealsCodec.Msg.LEAVE:
		_note(e.id, kind, why)

# --- talking -----------------------------------------------------------------------------------

## May e talk to x now? "" or why not: no_one, no_talk, far, no_sight, fight, down, hostile.
func can_talk(e: HostEntity, x: HostEntity, keep := false) -> String:
	if x == null or x == e or x.body == null:
		return "no_one"
	if not bool(x.get_meta("talk", false)):
		return "no_talk"
	var out_of_reach := DealsTalk.reach(host.world, e.body, x.body.rect(), KEEP_RANGE if keep else TALK_RANGE, not keep)
	if out_of_reach != "":
		return out_of_reach
	var combat := _sys(host, HostSystem.COMBAT)
	if combat != null and combat.has_method("in_combat") and (bool(combat.call("in_combat", e)) or bool(combat.call("in_combat", x))):
		return "fight"
	var rules := _rules()
	if rules != null and rules.has_method("is_downed") and bool(rules.call("is_downed", e)):
		return "down"
	var l := life()
	if l != null and l.stance(e, x) == Life.HOSTILE:
		return "hostile"
	return ""

## Open a conversation with person `pid`. "" or a refusal word.
func talk(e: HostEntity, person_id: int) -> String:
	var x := host.entity(person_id)
	var why := can_talk(e, x)
	if why != "":
		stats["refused"] += 1
		return why
	var info: Dictionary = x.get_meta("sim", {})
	var kind := String(info.get("kind", ""))
	var site := int(info.get("id", -1)) if kind == "settlement" else -1
	if kind == "party" and host.sim != null and host.sim.parties.has(int(info.get("id", -1))):
		site = (host.sim.parties[int(info["id"])] as SimParty).home
	talks[e.id] = {"person": x.id, "site": site, "kind": kind, "role": String(info.get("role", "townsfolk")),
		"of": int(info.get("id", -1)), "faction": Life.faction_of(x), "view": "main", "shop": ""}
	stats["talks"] += 1
	_send_talk(e)
	return ""

func _close(pid: int, why: String) -> void:
	var t: Dictionary = talks.get(pid, {})
	talks.erase(pid)
	if host.entity(pid) == null:
		return
	if String(t.get("shop", "")) != "":
		_send(pid, DealsCodec.Msg.SHOP, {"open": false})
	_send(pid, DealsCodec.Msg.TALK, {"open": false, "why": why, "line": String(Deals.lines()["closing"].get(why, ""))})

## The roles a settlement has (for who gives which work): Life's first roles by tier, guards
## when it has soldiers, townsfolk.
func roles_at(sid: int) -> Array:
	var s: SimSettlement = host.sim.settlements.get(sid)
	if s == null:
		return []
	var out: Array = Life.first_roles(s.culture, s.tier).duplicate()
	if s.soldiers > 0:
		out.append("guard")
	out.append("townsfolk")
	return out

func _person(e: HostEntity, t: Dictionary) -> Dictionary:
	var x := host.entity(int(t["person"]))
	var s: SimSettlement = host.sim.settlements.get(int(t["site"])) if host.sim != null else null
	return {"key": "%s:%d" % [String(t["kind"]), int(t["of"])] + ":" + (x.name if x != null else ""), "role": t["role"],
		"name": x.name if x != null else "", "culture": s.culture if s != null else ""}

## The options this person has for this player now.
func options(e: HostEntity, t: Dictionary) -> Array:
	var L: Dictionary = Deals.lines()["offers"]
	var out: Array = [{"id": "rumours", "label": L["rumours"]}]
	var sid := int(t["site"])
	var role := String(t["role"])
	if String(t["kind"]) != "settlement" or host.sim == null or not host.sim.settlements.has(sid):
		out.append({"id": "bye", "label": L["bye"]})
		return out
	var s: SimSettlement = host.sim.settlements[sid]
	if role == "merchant" and DealsShop.has_store(host.world, sid):
		out.append({"id": "shop", "label": L["shop"]})
	if role == "smith" and DealsShop.has_smithy(host.world, sid):
		out.append({"id": "smith", "label": L["smith"]})
	if not _offers_by(sid, role, e).is_empty():
		out.append({"id": "quests", "label": L["quests"]})
	var pt := patron_tier(e.id, str(s.faction))
	if role == "keeper" and DealsShop.has_building(host.world, sid, "tavern"):
		var price := bed_price(e, sid)
		out.append({"id": "bed", "label": L["bed_free"] if price == 0 else Deals.fill(L["bed"], {"price": price})})
	if role == "priest" and DealsShop.has_building(host.world, sid, "shrine"):
		out.append({"id": "heal", "label": Deals.fill(L["heal"], {"price": heal_price(e)})})
	if DealsPatron.is_patron_role(role) and pt >= 1:
		out.append({"id": "patron", "label": Deals.fill(L["patron"], {"faction": host.sim.faction_name(s.faction)})})
	for qid: String in WorldSim._sorted_keys(quests):
		var q: Dictionary = quests[qid]
		if int(q["site"]) == sid and String(q["state"]) in DealsQuests.OPEN and e.name in (q["players"] as Array) \
				and not DealsQuests.self_ending(q):
			out.append({"id": "turn_in:" + qid, "label": Deals.fill(L["turn_in"], {"title": q["title"]})})
	out.append({"id": "bye", "label": L["bye"]})
	return out

func _send_talk(e: HostEntity, extra := {}) -> void:
	var t: Dictionary = talks.get(e.id, {})
	if t.is_empty():
		return
	var x := host.entity(int(t["person"]))
	var line := String(extra.get("line", ""))
	if line == "" and host.sim != null:
		line = DealsTalk.line(host.sim, _seed(), _person(e, t), int(t["site"]), host.clock.hour_of_day())
	var d := {"open": true, "id": int(t["person"]), "name": x.name if x != null else "", "role": t["role"], "site": int(t["site"]),
		"faction": t["faction"], "line": line, "view": t["view"], "options": options(e, t)}
	for k: String in extra:
		if k != "line":
			d[k] = extra[k]
	_send(e.id, DealsCodec.Msg.TALK, d)

## Pick an option of the open conversation. "" or a refusal word.
func choose(e: HostEntity, o: String) -> String:
	var t: Dictionary = talks.get(e.id, {})
	if t.is_empty():
		return "not_talking"
	var allowed := false
	for op: Dictionary in options(e, t):
		if String(op["id"]) == o:
			allowed = true
	if not allowed:
		return "no_option"
	var sid := int(t["site"])
	if o == "bye":
		_close(e.id, "left")
		return ""
	if o.begins_with("turn_in:"):
		return turn_in(e, o.trim_prefix("turn_in:"))
	match o:
		"rumours":
			var told := DealsTalk.rumours(host.sim, sid, String(t["role"]), names) if host.sim != null and host.sim.site_by_id.has(sid) else []
			_learn_names()
			var fresh := hear(e, told)
			var L := Deals.lines()
			var lead := String(Deals.pick(L["rumour_lead"].get(String(t["role"]), L["rumour_lead"]["_"]), [_seed(), e.name, sid, Deals.day(host.sim)]))
			# "New": they had not heard it, and it is news in the world
			var news := fresh.filter(func(r: Dictionary) -> bool: return DealsTalk.is_news(float(r["t"]), float(host.sim.t)))
			var stale := not told.is_empty() and told.all(func(r: Dictionary) -> bool: return not DealsTalk.is_news(float(r["t"]), float(host.sim.t)))
			if stale:
				lead = String(Deals.pick(L["rumour_stale"], [_seed(), e.name, sid, Deals.day(host.sim)]))
			var line := lead if not told.is_empty() else String(Deals.pick(L["rumour_none"], [_seed(), sid, Deals.day(host.sim)]))
			t["view"] = "rumours"
			_send_talk(e, {"line": line, "rumours": told, "new": news})
		"shop", "smith":
			t["view"] = o
			t["shop"] = "store" if o == "shop" else "smith"
			_send_talk(e, {"line": _line_for(e, t)})
			send_shop(e)
		"quests":
			t["view"] = "quests"
			_send_talk(e, {"line": _line_for(e, t), "offers": _offers_by(sid, String(t["role"]), e)})
		"bed", "heal":
			return service(e, o)
		"patron":
			t["view"] = "patron"
			var why := claim_gift(e, sid)
			_send_talk(e, {"line": why if why != "" else "You have had all we can give, for now. Keep it up."})
	return ""

func _line_for(e: HostEntity, t: Dictionary) -> String:
	return DealsTalk.line(host.sim, _seed(), _person(e, t), int(t["site"]), host.clock.hour_of_day())

## Record rumours a player has heard; returns the newly heard ones (and sends them).
func hear(e: HostEntity, told: Array) -> Array:
	var have: Array = known.get(e.id, [])
	var ids := {}
	for r: Dictionary in have:
		ids[int(r["id"])] = true
	var fresh: Array = []
	for r: Dictionary in told:
		if not ids.has(int(r["id"])):
			fresh.append(r)
			have.append(r)
	while have.size() > MAX_KNOWN:
		have.pop_front()
	known[e.id] = have
	if not fresh.is_empty():
		stats["rumours"] += fresh.size()
		_send(e.id, DealsCodec.Msg.RUMOUR, {"rumours": fresh, "all": false})
	return fresh

## Remember the names of places as they are now (rumours about them after they fall).
func _learn_names() -> void:
	for sid: int in host.sim.settlements:
		names[host.sim.settlements[sid].name] = sid
	for lid: int in host.sim.lairs:
		names[host.sim.lairs[lid].name] = lid

# --- shops -------------------------------------------------------------------------------------

## Price modifiers for a player with a faction: standing, Bond, Silver Tongue, patron tier.
func mods(e: HostEntity, faction: String) -> Dictionary:
	var out := {"standing": 0, "bond": 0, "price_mult": 0.0, "patron": 0}
	var l := life()
	if l != null and Life.is_sim_faction(faction):
		out["standing"] = l.standing(e.id, faction)
		out["patron"] = patron_tier(e.id, faction)
	var rules := _rules()
	if rules != null and rules.has_method("bond") and host.sim != null and faction.is_valid_int() and host.sim.factions.has(int(faction)):
		out["bond"] = int(rules.call("bond", e.id, "people:" + (host.sim.factions[int(faction)] as SimFaction).culture))
	var items := _items()
	if items != null and items.has_method("tags"):
		out["price_mult"] = float((items.call("tags", e) as Dictionary).get("price_mult", 0.0))
	return out

func _sold_today(sid: int) -> Dictionary:
	var day := Deals.day(host.sim)
	var rec: Dictionary = sold.get(sid, {})
	if int(rec.get("day", -1)) != day:
		rec = {"day": day, "sold": {}}
		sold[sid] = rec
	return rec["sold"]

## The listings of a shop as this player would pay.
func listings(e: HostEntity, sid: int, kind: String) -> Array:
	var s: SimSettlement = host.sim.settlements.get(sid)
	if s == null:
		return []
	var base: Array
	if kind == "smith":
		var day := Deals.day(host.sim)
		var rec: Dictionary = sold.get(sid, {})
		base = DealsShop.rack(host.sim, _seed(), sid, day, rec.get("sold", {}) if int(rec.get("day", -1)) == day else {})
	else:
		base = DealsShop.shelves(host.sim, sid)
	var m := DealsShop.buy_mult(mods(e, str(s.faction)))
	var out: Array = []
	for l: Dictionary in base:
		var row := l.duplicate()
		row["price"] = DealsShop.price(int(l["each"]), m)
		out.append(row)
	return out

## What the town pays this player for one of the item in each inventory slot.
func sell_prices(e: HostEntity, sid: int) -> Dictionary:
	var s: SimSettlement = host.sim.settlements.get(sid)
	var out := {}
	if s == null or e.character == null:
		return out
	var m := mods(e, str(s.faction))
	for i in Inventory.SIZE:
		var it := e.character.inventory.at(i)
		if it.is_empty():
			continue
		var each := DealsShop.sell_for(host.sim, sid, it, m)
		if each >= 0.5:
			out[str(i)] = maxi(1, floori(each))
	return out

func send_shop(e: HostEntity) -> void:
	var t: Dictionary = talks.get(e.id, {})
	var kind := String(t.get("shop", ""))
	if kind == "":
		return
	var sid := int(t["site"])
	var s: SimSettlement = host.sim.settlements.get(sid)
	if s == null:
		return
	var ls: Array = []
	for l: Dictionary in listings(e, sid, kind):
		ls.append({"id": l["id"], "item": l["item"], "n": l["n"], "price": l["price"]})
	_send(e.id, DealsCodec.Msg.SHOP, {"open": true, "kind": kind, "site": sid, "town": s.name, "listings": ls,
		"sell": sell_prices(e, sid), "wealth": floori(s.wealth)})

func _shop_open(e: HostEntity) -> Dictionary:
	var t: Dictionary = talks.get(e.id, {})
	if t.is_empty() or String(t.get("shop", "")) == "" or host.sim == null or not host.sim.settlements.has(int(t["site"])):
		return {}
	return t

## Buy n of a listing in the open shop. Coin goes to the town's wealth, the goods come out of
## its stock (WorldSim.player_trade). "" or: not_shopping, no_listing, none_left, coin, full.
func buy(e: HostEntity, lid: String, n: int) -> String:
	var t := _shop_open(e)
	if t.is_empty():
		return "not_shopping"
	if e.character == null:
		return "no_body"
	n = maxi(1, n)
	var sid := int(t["site"])
	var row := {}
	for l: Dictionary in listings(e, sid, String(t["shop"])):
		if String(l["id"]) == lid:
			row = l
	if row.is_empty():
		return "no_listing"
	if int(row["n"]) < n:
		return "none_left"
	var cost := int(row["price"]) * n
	var inv := e.character.inventory
	if inv.coin < cost:
		return "coin"
	var item := Items.with_count(row["item"], n)
	if inv.room_for(item) < n:
		return "full"
	var good := String(row["good"])
	if not host.sim.player_trade(sid, good, -float(row["units"]) * n, -float(cost)):
		return "none_left"
	inv.coin -= cost
	inv.changed[-1] = true
	inv.add(item)
	if String(t["shop"]) == "smith":
		_sold_today(sid)[int(lid.trim_prefix("r"))] = true
	stats["bought"] += n
	stats["coin_in"] += cost
	_deed(e, "trade", 1)
	if debug:
		print("DEALS %s bought %d %s for %d at %s" % [e.name, n, ItemGen.name(item), cost, host.sim.settlements[sid].name])
	send_shop(e)
	return ""

## Sell n of the stack in inventory slot `slot` to the open shop's town. Trade goods and ore
## go into its stock; the coin comes out of its wealth (never more than wealth_cap of it).
## "" or: not_shopping, empty, worthless, poor.
func sell(e: HostEntity, slot: int, n: int) -> String:
	var t := _shop_open(e)
	if t.is_empty():
		return "not_shopping"
	if e.character == null or slot < 0 or slot >= Inventory.SIZE:
		return "bad_index"
	var inv := e.character.inventory
	var it := inv.at(slot)
	if it.is_empty():
		return "empty"
	n = clampi(n, 1, Items.count(it))
	var sid := int(t["site"])
	var s: SimSettlement = host.sim.settlements[sid]
	var each := DealsShop.sell_for(host.sim, sid, it, mods(e, str(s.faction)))
	if each < 0.5:
		return "worthless"
	var pay := maxi(1, floori(each)) * n
	if pay > s.wealth * float(Deals.prices()["wealth_cap"]):
		return "poor"
	var g := DealsShop.good_of(it)
	var camp := DealsShop.camp_row(it)
	if not camp.is_empty():
		g = [String(camp["good"]), float(camp.get("units", 1.0))]
	if not host.sim.player_trade(sid, String(g[0]), float(g[1]) * n, float(pay)):
		return "poor"
	inv.take(slot, n)
	inv.coin += pay
	inv.changed[-1] = true
	stats["sold"] += n
	stats["coin_out"] += pay
	_deed(e, "trade", 1)
	if debug:
		print("DEALS %s sold %d %s for %d at %s" % [e.name, n, ItemGen.name(it), pay, s.name])
	send_shop(e)
	return ""

# --- services ----------------------------------------------------------------------------------

func bed_price(e: HostEntity, sid: int) -> int:
	var s: SimSettlement = host.sim.settlements.get(sid)
	if s == null:
		return 0
	if patron_tier(e.id, str(s.faction)) >= 1:
		return 0
	return int(Deals.prices()["services"]["bed"]["price"].get(s.tier, 3))

func heal_price(e: HostEntity) -> int:
	var c := e.combatant
	var cfg: Dictionary = Deals.prices()["services"]["heal"]
	if c == null:
		return int(cfg["min"])
	return maxi(int(cfg["min"]), ceili((c.stats.max_hp - c.stats.current_hp) * float(cfg["per_hp"])))

## A service of the person spoken to: "bed" (keeper, tavern: the respawn point through
## Rules.set_bed) or "heal" (priest, shrine: all hit points through Rules.heal). "" or a word.
func service(e: HostEntity, id: String) -> String:
	var t: Dictionary = talks.get(e.id, {})
	if t.is_empty():
		return "not_talking"
	var sid := int(t["site"])
	if host.sim == null or not host.sim.settlements.has(sid):
		return "no_service"
	var role := String(t["role"])
	var inv := e.character.inventory if e.character != null else null
	if inv == null:
		return "no_body"
	var rules := _rules()
	match id:
		"bed":
			if role != "keeper" or not DealsShop.has_building(host.world, sid, "tavern"):
				return "no_service"
			if rules == null or not rules.has_method("set_bed"):
				return "no_rules"
			var price := bed_price(e, sid)
			if inv.coin < price:
				return "coin"
			if price > 0 and not host.sim.player_trade(sid, "", 0.0, -float(price)):
				return "no_service"
			inv.coin -= price
			inv.changed[-1] = true
			rules.call("set_bed", e, _bed_cell(sid, e), true)
			_send_talk(e, {"line": "Room's yours. Mind the stairs." if price > 0 else "On the house. Our patron's friends sleep free."})
		"heal":
			if role != "priest" or not DealsShop.has_building(host.world, sid, "shrine"):
				return "no_service"
			var c := e.combatant
			if c == null or c.stats.current_hp >= c.stats.max_hp:
				return "full_hp"
			if rules == null or not rules.has_method("heal"):
				return "no_rules"
			var price := heal_price(e)
			if inv.coin < price:
				return "coin"
			if not host.sim.player_trade(sid, "", 0.0, -float(price)):
				return "no_service"
			inv.coin -= price
			inv.changed[-1] = true
			rules.call("heal", e, c.stats.max_hp - c.stats.current_hp)
			_send_talk(e, {"line": "There. Try to keep it that way."})
		_:
			return "no_service"
	stats["coin_in"] += 0
	return ""

## The feet cell of the tavern's keeper anchor (else the player's own feet).
func _bed_cell(sid: int, e: HostEntity) -> Vector2i:
	for b: Dictionary in Places.buildings(host.world, sid, "tavern"):
		for cell: Array in b.get("anchors", {}).get("keeper", []):
			return Vector2i(int(cell[0]), int(cell[1]))
	return Vector2i(floori(e.body.pos.x), floori(e.body.pos.y))

# --- quests ------------------------------------------------------------------------------------

## Today's offers at a settlement (made once a day from the sim as it then stands), each with
## the status it has now (offered, or the accepted quest's state).
func offers_at(sid: int) -> Array:
	if host.sim == null or not host.sim.settlements.has(sid):
		return []
	var day := Deals.day(host.sim)
	var rec: Dictionary = offers.get(sid, {})
	if int(rec.get("day", -1)) != day:
		var roles := roles_at(sid)
		var list: Array = DealsQuests.offers(host.sim, _seed(), sid, day)
		for q: Dictionary in list:
			q["giver"] = DealsQuests.giver_for(String(q["kind"]), roles)
		rec = {"day": day, "list": list}
		offers[sid] = rec
	var out: Array = []
	for q: Dictionary in rec["list"]:
		var v: Dictionary = quests.get(String(q["id"]), q)
		if v == q and not DealsQuests.still_valid(host.sim, q):
			continue
		out.append(v)
	return out

## Offers a role at a site gives this player (patron work only to patrons of the faction).
func _offers_by(sid: int, role: String, e: HostEntity) -> Array:
	var out: Array = []
	for q: Dictionary in offers_at(sid):
		if String(q.get("giver", "keeper")) != role:
			continue
		if bool(q.get("patron", false)) and patron_tier(e.id, String(q["faction"])) < int(DealsPatron.cfg()["work_tier"]):
			continue
		if String(q["state"]) in DealsQuests.ENDED:
			continue
		out.append(q)
	return out

func quest(qid: String) -> Dictionary:
	return quests.get(qid, {})

## Take on (or join) an offered quest at the site of the open conversation. "" or a word.
func accept(e: HostEntity, qid: String) -> String:
	var t: Dictionary = talks.get(e.id, {})
	if t.is_empty():
		return "not_talking"
	var q := {}
	for o: Dictionary in _offers_by(int(t["site"]), String(t["role"]), e):
		if String(o["id"]) == qid:
			q = o
	if q.is_empty():
		return "no_quest"
	if e.name in (q["players"] as Array):
		return "already"
	if not quests.has(qid):
		q = q.duplicate(true)
		q["state"] = "active"
		quests[qid] = q
		stats["accepted"] += 1
		if String(q["kind"]) == "escort":
			host.sim.hold_party(int(q["target"]["party"]), true)
			q["target"]["held_at"] = host.sim.t
		if String(q["kind"]) in ["bounty", "hunt"] and host.sim.lairs.has(int(q["target"]["lair"])):
			q["target"]["left"] = (host.sim.lairs[int(q["target"]["lair"])] as SimLair).count()
	else:
		q = quests[qid]
	(q["players"] as Array).append(e.name)
	_send_quests_of(q)
	_send_talk(e, {"line": "Good. Don't make me regret it.", "offers": _offers_by(int(t["site"]), String(t["role"]), e)})
	return ""

## Leave a quest; the last to leave ends it (escort and defence cost standing).
func abandon(e: HostEntity, qid: String) -> String:
	var q: Dictionary = quests.get(qid, {})
	if q.is_empty() or not e.name in (q["players"] as Array) or not String(q["state"]) in DealsQuests.OPEN:
		return "no_quest"
	(q["players"] as Array).erase(e.name)
	var pen := int(DealsQuests.kind_def(String(q["kind"])).get("abandon", 0))
	var l := life()
	if pen != 0 and l != null:
		l.add_standing(e.id, String(q["faction"]), pen, "abandoned: " + String(q["title"]))
	_snapshot(e, q, "abandoned")
	if (q["players"] as Array).is_empty():
		_end(q, "abandoned")
	_send_quests(e)
	return ""

## Hand in a quest at its giver's town: deliveries take the goods (they enter the town's
## stock), the rest must be ready. Pays the party members near. "" or a word.
func turn_in(e: HostEntity, qid: String) -> String:
	var q: Dictionary = quests.get(qid, {})
	if q.is_empty() or not e.name in (q["players"] as Array) or not String(q["state"]) in DealsQuests.OPEN:
		return "no_quest"
	if DealsQuests.self_ending(q):
		return "not_here"
	var sid := int(q["site"])
	if host.sim == null or not host.sim.settlements.has(sid):
		return "gone"
	if not Deals.at_site(host.world, host.sim, sid, e.body.pos, float(Deals.quests()["turn_in_margin"])):
		return "far"
	if DealsQuests.delivers(q):
		var base := "trade:" + String(q["target"]["good"])
		var need := int(q["target"]["n"])
		# the party pools what it carries: goods picked up by whoever touched them first
		var carriers: Array = [e]
		var have := e.character.inventory.count_base(base)
		for name: String in q["players"]:
			var o := host.player_named(name)
			if o != null and o != e and o.character != null \
					and Deals.at_site(host.world, host.sim, sid, o.body.pos, float(Deals.quests()["turn_in_margin"])):
				carriers.append(o)
				have += o.character.inventory.count_base(base)
		if have < need:
			return "missing"
		if not host.sim.player_trade(sid, String(q["target"]["good"]), float(need), 0.0):
			return "gone"
		var left := need
		for c: HostEntity in carriers:
			var take := mini(left, c.character.inventory.count_base(base))
			if take > 0:
				c.character.inventory.remove_base(base, take)
				left -= take
		q["progress"]["have"] = need
	elif String(q["state"]) != "ready":
		return "not_ready"
	_pay(q, Deals.site_xy(host.sim, sid), 1.0)
	_end(q, "done")
	return ""

## Pay a quest's reward (times share) to its players within near_tiles of `at`: coin out of
## the giver town's wealth (split), standing, XP, deeds and, if the quest has one, an item.
func _pay(q: Dictionary, at: Vector2, share: float) -> void:
	var sid := int(q["site"])
	var payees: Array = []
	for name: String in q["players"]:
		var p := host.player_named(name)
		if p != null and p.body.pos.distance_to(at) <= float(Deals.quests()["near_tiles"]) * 1.5:
			payees.append(p)
	if payees.is_empty():
		return
	var r: Dictionary = q["reward"]
	var coin := 0
	if host.sim.settlements.has(sid):
		var s: SimSettlement = host.sim.settlements[sid]
		coin = mini(floori(float(r["coin"]) * share), floori(s.wealth * float(Deals.quests()["wealth_share"])))
		if coin > 0 and not host.sim.player_trade(sid, "", 0.0, float(coin)):
			coin = 0
	var each := ceili(coin / float(payees.size())) if coin > 0 else 0
	var l := life()
	var rules := _rules()
	for p: HostEntity in payees:
		if each > 0 and p.character != null:
			p.character.inventory.coin += each
			p.character.inventory.changed[-1] = true
		var st := roundi(int(r["standing"]) * share)
		if l != null and st != 0:
			l.add_standing(p.id, String(q["faction"]), st, "work: " + String(q["title"]))
		if rules != null and rules.has_method("award_xp") and int(r["xp"]) > 0:
			rules.call("award_xp", p.id, roundi(int(r["xp"]) * share), "quest")
		_deed(p, "quest", 1)
		_deed(p, "quest:" + String(q["kind"]), 1)
		if bool(r.get("item", false)) and share >= 1.0 and host.sim.settlements.has(sid) and p.character != null:
			var it := DealsShop.piece(host.sim, _seed(), sid, Deals.day(host.sim), 2000 + Deals.h([q["id"], p.name]) % 1000, 1, false, "",
				clampi(p.character.level, 1, 100))
			var left := p.character.inventory.add(it)
			if not left.is_empty():
				var items := _items()
				if items != null and items.has_method("drop"):
					items.call("drop", p.body.center(), [left])
		q["paid"] = int(q.get("paid", 0)) + each

func _deed(e: HostEntity, counter: String, n: int) -> void:
	var rules := _rules()
	if rules != null and rules.has_method("add_deed"):
		rules.call("add_deed", e.id, counter, n)

## A quest ends: snapshot into each player's log, release what it held.
func _end(q: Dictionary, state: String) -> void:
	q["state"] = state
	q["ended_at"] = host.sim.t if host.sim != null else 0
	if stats.has(state):
		stats[state] += 1
	if String(q["kind"]) == "escort" and host.sim != null:
		host.sim.hold_party(int(q["target"]["party"]), false)
	if debug:
		print("DEALS quest %s %s (%s)" % [q["id"], state, ", ".join(q["players"])])
	for name: String in q["players"]:
		var p := host.player_named(name)
		if p != null:
			_snapshot(p, q, state)
	_send_quests_of(q)

func _snapshot(e: HostEntity, q: Dictionary, state: String) -> void:
	if not logs.has(e.id):
		logs[e.id] = {}
	var snap := {"id": q["id"], "kind": q["kind"], "title": q["title"], "goal": q["goal"], "why": q["why"], "site": q["site"],
		"state": state, "faction": q["faction"], "paid": int(q.get("paid", 0)), "progress": (q["progress"] as Dictionary).duplicate()}
	logs[e.id][String(q["id"])] = snap

## The player's quest log: open quests they are in, then what ended (their snapshots, or the
## world's record when it ended while they were away).
func quest_log(e: HostEntity) -> Array:
	var out: Array = []
	var lg: Dictionary = logs.get(e.id, {})
	for qid: String in WorldSim._sorted_keys(quests):
		var q: Dictionary = quests[qid]
		if not e.name in (q["players"] as Array):
			continue
		if String(q["state"]) in DealsQuests.OPEN:
			out.append(_view(q))
		elif not lg.has(qid):
			_snapshot(e, q, String(q["state"]))
	for qid: String in WorldSim._sorted_keys(lg):
		if not (quests.has(qid) and String(quests[qid]["state"]) in DealsQuests.OPEN and e.name in (quests[qid]["players"] as Array)):
			out.append(lg[qid])
	return out

func _view(q: Dictionary) -> Dictionary:
	var v := {}
	for k: String in ["id", "kind", "title", "goal", "why", "site", "state", "faction", "due", "reward", "progress", "players", "giver"]:
		if q.has(k):
			v[k] = q[k]
	if host.sim != null:
		v["where"] = DealsQuests.target_pos(host.sim, q, _party_pos)
		var tp: Vector2 = v["where"]
		v["where"] = [tp.x, tp.y] if tp != Vector2.INF else null
		var t: Dictionary = q["target"]
		for k: String in ["lair", "site", "dest"]:
			if t.has(k):
				v["target_site"] = int(t[k])
				break
	return v

func _send_quests(e: HostEntity) -> void:
	_send(e.id, DealsCodec.Msg.QUESTS, {"quests": quest_log(e)})

func _send_quests_of(q: Dictionary) -> void:
	for name: String in q["players"]:
		var p := host.player_named(name)
		if p != null:
			_send_quests(p)

func _party_pos(p: SimParty) -> Vector2:
	var l := life()
	if l != null and l.road != null:
		return l.road.party_pos(host, p)
	if p.path.size() < 2 or p.leg >= p.path.size() - 1:
		return Deals.site_xy(host.sim, p.path[p.path.size() - 1] if not p.path.is_empty() else p.home)
	return Deals.site_xy(host.sim, p.path[p.leg]).lerp(Deals.site_xy(host.sim, p.path[p.leg + 1]), p.frac)

## Names of a quest's players within `tiles` of `pos`.
func _near(q: Dictionary, pos: Vector2, tiles: float) -> Array:
	var out: Array = []
	if pos == Vector2.INF:
		return out
	for name: String in q["players"]:
		var p := host.player_named(name)
		if p != null and p.body.pos.distance_to(pos) <= tiles:
			out.append(name)
	return out

## Names of a quest's players at a site (its place's rect grown by margin).
func _at(q: Dictionary, site: int, margin: float) -> Array:
	var out: Array = []
	for name: String in q["players"]:
		var p := host.player_named(name)
		if p != null and Deals.at_site(host.world, host.sim, site, p.body.pos, margin):
			out.append(name)
	return out

func _check_quests() -> void:
	var sim := host.sim
	for qid: String in WorldSim._sorted_keys(quests):
		var q: Dictionary = quests[qid]
		var st := String(q["state"])
		if st in DealsQuests.ENDED:
			if sim.t - int(q.get("ended_at", sim.t)) > KEEP_ENDED_DAYS * WorldSim.DAY_H:
				quests.erase(qid)
			continue
		if String(q["kind"]) == "escort":
			_escort_hold(q)
		var before := JSON.stringify(q["progress"])
		var ctx := {"near": func(pos: Vector2, tiles: float) -> Array: return _near(q, pos, tiles), "party_pos": _party_pos,
			"at": func(site: int, margin: float) -> Array: return _at(q, site, margin)}
		var now := DealsQuests.check(sim, q, ctx)
		match now:
			"":
				if JSON.stringify(q["progress"]) != before:
					_send_quests_of(q)
			"ready":
				q["state"] = "ready"
				_send_quests_of(q)
			"done":
				_pay(q, DealsQuests.target_pos(sim, q, _party_pos) if String(q["kind"]) != "defend" else Deals.site_xy(sim, int(q["site"])), 1.0)
				_end(q, "done")
			"beaten":
				_pay(q, Deals.site_xy(sim, int(q["site"])), float(DealsQuests.kind_def(String(q["kind"])).get("beaten", 0.0)))
				_end(q, "beaten")
			_:
				_end(q, now)

## An escort's target moves: its players' `where` is resent when the caravan has gone 3 tiles,
## so the tracker's pointer keeps up with it (at most every 1.5 s, escorts only).
func _refresh_moving() -> void:
	for qid: String in quests:
		var q: Dictionary = quests[qid]
		if String(q["kind"]) != "escort" or not String(q["state"]) in DealsQuests.OPEN:
			continue
		var at := DealsQuests.target_pos(host.sim, q, _party_pos)
		if at == Vector2.INF or at.distance_to(_pointed.get(qid, Vector2.INF)) < 3.0:
			continue
		_pointed[qid] = at
		_send_quests_of(q)

## A held caravan leaves when one of its escorts is beside it, or after hold_h game hours.
func _escort_hold(q: Dictionary) -> void:
	var p: SimParty = host.sim.parties.get(int(q["target"]["party"]))
	if p == null or not p.held:
		return
	var waited := host.sim.t - int(q["target"].get("held_at", host.sim.t))
	if not _near(q, _party_pos(p), 40.0).is_empty() or waited >= int(DealsQuests.kind_def("escort").get("hold_h", 3)):
		host.sim.hold_party(p.id, false)
		if debug:
			print("DEALS escort %s: the caravan leaves" % q["id"])

# --- patrons -----------------------------------------------------------------------------------

func patron_tier(pid: int, faction: String) -> int:
	var l := life()
	if l == null or not Life.is_sim_faction(faction):
		return 0
	return DealsPatron.tier(l.standing(pid, faction))

## A patron's gift for each tier reached and not yet given. Returns what was said.
func claim_gift(e: HostEntity, sid: int) -> String:
	var s: SimSettlement = host.sim.settlements.get(sid)
	if s == null or e.character == null:
		return ""
	var f := str(s.faction)
	var tier := patron_tier(e.id, f)
	var given := int((gifts.get(e.id, {}) as Dictionary).get(f, 0))
	var said: Array = []
	var items := _items()
	for t in range(given + 1, tier + 1):
		var g := DealsPatron.gift(host.sim, _seed(), sid, f, t, e.name, e.character.level,
			items.call("wielded", e) if items != null and items.has_method("wielded") else {})
		var left := e.character.inventory.add(g["item"])
		if not left.is_empty() and items != null and items.has_method("drop"):
			items.call("drop", e.body.center(), [left])
		said.append("%s (%s)" % [g["why"], ItemGen.name(g["item"])])
		gifts[e.id][f] = t
		stats["gifts"] += 1
	if not said.is_empty():
		_send_patrons(e, true)
	return " ".join(said)

func _send_patrons(e: HostEntity, force := false) -> void:
	var l := life()
	if l == null or host.sim == null:
		return
	var d := {}
	var sig := {}
	for fid: int in WorldSim._sorted_keys(host.sim.factions):
		var f := str(fid)
		var st := l.standing(e.id, f)
		var t := DealsPatron.tier(st)
		var given := int((gifts.get(e.id, {}) as Dictionary).get(f, 0))
		sig[f] = [t, given]
		if t > 0 or given > 0:
			d[f] = {"tier": t, "standing": st, "given": given, "suspended": t == 0 and given > 0, "name": host.sim.faction_name(fid)}
	if not force and _patron_sent.get(e.id) == sig:
		return
	_patron_sent[e.id] = sig
	_send(e.id, DealsCodec.Msg.PATRON, {"patrons": d})

# --- tick --------------------------------------------------------------------------------------

func tick(h: WorldHost) -> void:
	if h.sim == null:
		return
	if h.tick_count % 15 == 0:
		for pid: int in talks.keys():
			var e := h.entity(pid)
			if e == null:
				talks.erase(pid)
				continue
			var why := can_talk(e, h.entity(int(talks[pid]["person"])), true)
			if why != "":
				_close(pid, {"no_one": "gone", "no_talk": "gone", "far": "far", "fight": "fight", "down": "fight", "hostile": "hostile"}.get(why, why))
	if h.tick_count % 30 == 7:
		_check_quests()
		for e: HostEntity in h.entities.values():
			if e.is_player():
				_send_patrons(e)
	if h.tick_count % 30 == 19:
		_atlas_tick(h)
	if h.tick_count % 45 == 11:
		_refresh_moving()

# --- the atlas (Interface: the world map, place banners) ----------------------------------------

## Every site as the map shows it: settlements with name, culture, tier, people, faction, their
## situation (DealsTalk.situation) and who has work today; lairs with name and kind; ruins.
func atlas_sites() -> Array:
	var out: Array = []
	var sim := host.sim
	var fallen := {}
	for n: String in names:
		fallen[int(names[n])] = n
	for s: Dictionary in sim.sites:
		var sid := int(s["id"])
		var d := {"id": sid, "kind": String(s["kind"])}
		if sim.settlements.has(sid):
			var st: SimSettlement = sim.settlements[sid]
			d.merge({"name": st.name, "culture": st.culture, "tier": st.tier, "pop": st.pop(), "faction": str(st.faction),
				"state": DealsTalk.situation(sim, sid)})
			if _player_near(sid):
				d["work"] = work_roles(sid)
		elif sim.lairs.has(sid):
			var l: SimLair = sim.lairs[sid]
			d.merge({"name": l.name, "lair": l.kind, "apex": l.apex})
		else:
			d["ruin"] = sim.ruins.has(sid) or String(s["kind"]) == "ruin" or String(s["kind"]) == "settlement"
			d["name"] = String(fallen.get(sid, ""))
		out.append(d)
	return out

## Roles at a settlement with ordinary work on offer today, for the marks over people. Reads
## the day's offers when someone has asked already, else previews them (DealsQuests.offers is
## pure) without keeping them, so the first real ask still makes the day's list.
func work_roles(sid: int) -> Array:
	var day := Deals.day(host.sim)
	var rec: Dictionary = offers.get(sid, {})
	var list: Array
	var roles := roles_at(sid)
	if int(rec.get("day", -1)) == day:
		list = offers_at(sid)
	else:
		list = DealsQuests.offers(host.sim, _seed(), sid, day)
		for q: Dictionary in list:
			q["giver"] = DealsQuests.giver_for(String(q["kind"]), roles)
	var out := {}
	for q: Dictionary in list:
		if String(q["state"]) == "offered" and not bool(q.get("patron", false)):
			out[String(q.get("giver", "keeper"))] = true
	return out.keys()

## Route paths, every 8th feet cell and both ends (static: sent on join).
func atlas_routes() -> Array:
	var out: Array = []
	for r: Dictionary in host.world.meta.get("routes", []):
		var path := Places.route_path(host.world, int(r["id"]))
		var pts: Array = []
		for i in path.size():
			if i % 8 == 0 or i == path.size() - 1:
				pts.append([path[i].x, path[i].y])
		var sr: Dictionary = host.sim.route_by_id.get(int(r["id"]), {}) if host.sim != null else {}
		out.append({"id": int(r["id"]), "a": int(r["a"]), "b": int(r["b"]), "kind": String(r.get("kind", "")),
			"name": String(sr.get("name", "")), "path": pts})
	return out

func _player_near(sid: int) -> bool:
	for e: HostEntity in host.entities.values():
		if e.is_player() and Deals.at_site(host.world, host.sim, sid, e.body.pos, 120.0):
			return true
	return false

## Once a second: sites players reach for the first time; the site list when it changed.
func _atlas_tick(h: WorldHost) -> void:
	for e: HostEntity in h.entities.values():
		if not e.is_player():
			continue
		var sn: Dictionary = seen.get(e.id, {})
		seen[e.id] = sn
		var fresh: Array = []
		for s: Dictionary in h.sim.sites:
			var sid := int(s["id"])
			if not sn.has(sid) and Deals.at_site(h.world, h.sim, sid, e.body.pos, 8.0 if String(s["kind"]) == "settlement" else 4.0):
				sn[sid] = true
				fresh.append(sid)
		if not fresh.is_empty():
			_send(e.id, DealsCodec.Msg.ATLAS, {"t": h.sim.t, "seen": fresh})
	if h.tick_count % 150 != 19:
		return
	var sites := atlas_sites()
	var dig := JSON.stringify(sites.map(func(d: Dictionary) -> Dictionary:
		var c := d.duplicate()
		c["pop"] = int(c.get("pop", 0)) / 10
		return c)).md5_text()
	if dig != _atlas_digest:
		_atlas_digest = dig
		for e: HostEntity in h.entities.values():
			if e.is_player():
				_send(e.id, DealsCodec.Msg.ATLAS, {"t": h.sim.t, "sites": sites})

# --- cheats (tests, tools, smokes) -------------------------------------------------------------

## ops: goto {role}: stand beside the nearest person of a role Life shows; coin {n}; give
## {base, n}; standing {faction, n}; complete {q}: make an open quest ready (bounty, hunt,
## message) or give the party the delivery.
func cheat(e: HostEntity, d: Dictionary) -> String:
	match String(d.get("op", "")):
		"goto":
			var l := life()
			if l == null:
				return "no_life"
			var best: HostEntity = null
			var bd := INF
			for id: int in l.actors:
				var x := host.entity(id)
				if x != null and String(l.actors[id].get("role", "")) == String(d.get("role", "")) and bool(x.get_meta("talk", false)):
					var dd := x.body.pos.distance_to(e.body.pos)
					if dd < bd:
						bd = dd
						best = x
			if best == null:
				return "no_one"
			host.teleport(e, best.body.pos + Vector2(1.5, 0.0))
			TileCollision.depenetrate(host.world, e.body)
			return ""
		"coin":
			e.character.inventory.coin += int(d.get("n", 0))
			e.character.inventory.changed[-1] = true
			return ""
		"give":
			var it := Items.make(String(d.get("base", "")), int(d.get("n", 1)))
			if not Items.exists(String(it["base"])):
				return "unknown"
			e.character.inventory.add(it)
			return ""
		"standing":
			if life() == null:
				return "no_life"
			life().add_standing(e.id, String(d.get("faction", "")), int(d.get("n", 0)), "cheat")
			return ""
		"report":
			var qs := quest_log(e)
			var last: Dictionary = qs[qs.size() - 1] if not qs.is_empty() else {}
			var f := String(last.get("faction", ""))
			var l := life()
			print("DEALSCHECK host name=%s coin=%d rope=%d ore=%d quest=%s standing=%d rumours=%d" % [e.name, e.character.inventory.coin,
				e.character.inventory.count_base("tile:rope"), e.character.inventory.count_base("ore:iron"), String(last.get("state", "-")),
				l.standing(e.id, f) if l != null and f != "" else 0, (known.get(e.id, []) as Array).size()])
			print("HOSTSTATS deals: " + summary())
			return ""
		"complete":
			var q: Dictionary = quests.get(String(d.get("q", "")), {})
			if q.is_empty() or not String(q["state"]) in DealsQuests.OPEN:
				return "no_quest"
			if DealsQuests.delivers(q):
				e.character.inventory.add(Items.make("trade:" + String(q["target"]["good"]), int(q["target"]["n"])))
				return ""
			if String(q["kind"]) in ["bounty", "hunt", "message"]:
				q["progress"]["have"] = int(q["progress"]["need"])
				q["target"]["visited"] = true
				q["state"] = "ready"
				_send_quests_of(q)
				return ""
			return "cannot"
	return "unknown"

func summary() -> String:
	return "talks %d (refused %d), bought %d, sold %d, coin to towns %d, coin from towns %d, rumours %d, quests accepted %d (done %d, failed %d, lapsed %d, beaten %d), gifts %d" % [
		stats["talks"], stats["refused"], stats["bought"], stats["sold"], stats["coin_in"], stats["coin_out"], stats["rumours"],
		stats["accepted"], stats["done"], stats["failed"], stats["lapsed"], stats["beaten"], stats["gifts"]]
