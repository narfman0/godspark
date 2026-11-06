## Quests from the sim's state: work that exists because of what is happening (a lair hunting
## the roads, a caravan leaving, cargo taken by raiders still abroad, a hungry town, a raid on
## its way, a neighbour gone quiet; for patrons an apex lair or a siege). Offers are made from
## the sim as it stands and a hash of (world seed, site, day); checking a quest reads the sim
## and the players' positions only. DealsSystem accepts, pays and saves them.
##
##   DealsQuests.offers(sim, seed, sid, day) -> Array[quest]
##   DealsQuests.check(sim, q, ctx) -> String      new state, or "" (ctx: see DealsSystem._ctx)
## quest: {id, kind, site, giver, faction, day, title, why, goal, due, target, reward, state,
##         players: [names], progress: {have, need, text}, patron?}
class_name DealsQuests
extends RefCounted

const OPEN := ["active", "ready"]
const ENDED := ["done", "failed", "lapsed", "beaten", "abandoned"]

static func _Q() -> Dictionary:
	return Deals.quests()

static func kind_def(kind: String) -> Dictionary:
	return _Q()["kinds"].get(kind, {})

## The roles present at a site who give a kind of work (the first of `givers` the town has,
## else the keeper).
static func giver_for(kind: String, roles: Array) -> String:
	for r: String in kind_def(kind).get("givers", []):
		if r in roles:
			return r
	return "keeper"

## Today's offers at a settlement, from the sim as it stands. Stable for (seed, site, day)
## given the same sim state; DealsSystem keeps the first list of the day.
static func offers(sim: WorldSim, world_seed: int, sid: int, day: int) -> Array:
	var s: SimSettlement = sim.settlements.get(sid)
	if s == null:
		return []
	var out: Array = []
	for kind: String in ["defend", "bounty", "escort", "recover", "relief", "message", "hunt", "siege"]:
		var q := _make(sim, world_seed, sid, day, kind)
		if not q.is_empty():
			out.append(q)
	# keep the most pressing few (the order above), patron work always
	var plain := out.filter(func(q: Dictionary) -> bool: return not bool(q.get("patron", false)))
	var patron := out.filter(func(q: Dictionary) -> bool: return bool(q.get("patron", false)))
	return plain.slice(0, int(_Q()["max_offers"])) + patron

static func _make(sim: WorldSim, world_seed: int, sid: int, day: int, kind: String) -> Dictionary:
	var s: SimSettlement = sim.settlements[sid]
	var key := [world_seed, "quest", sid, day, kind]
	var d := kind_def(kind)
	var vars := {"town": s.name, "faction": sim.faction_name(s.faction)}
	var target := {}
	var x := 0.0          # the size of the job, for the coin
	match kind:
		"bounty", "hunt":
			var cand: Array = []
			for lid: int in Deals.lairs_on_routes(sim, sid):
				cand.append(lid)
			for lid: Variant in s.grievance:
				if sim.lairs.has(int(lid)) and not int(lid) in cand:
					cand.append(int(lid))
			if cand.is_empty() or kind == "hunt":
				var here := Deals.site_xy(sim, sid)
				var best := -1
				var bd := float(d.get("reach", 900))
				for lid: int in WorldSim._sorted_keys(sim.lairs):
					var l0: SimLair = sim.lairs[lid]
					if l0.apex != (kind == "hunt"):
						continue
					var dd := Deals.site_xy(sim, lid).distance_to(here)
					if dd < bd:
						bd = dd
						best = lid
				if best >= 0 and not best in cand:
					cand.append(best)
			cand = cand.filter(func(lid: int) -> bool: return sim.lairs.has(lid) and sim.lairs[lid].count() > 0 and sim.lairs[lid].apex == (kind == "hunt"))
			if cand.is_empty():
				return {}
			cand.sort()
			var lid: int = Deals.pick(cand, key)
			var l: SimLair = sim.lairs[lid]
			var n := l.count() if kind == "hunt" or l.count() <= 3 else maxi(2, ceili(l.count() / 2.0))
			target = {"lair": lid, "n": n, "base": l.count()}
			vars.merge({"lair": l.name, "what": SimConflict._lair_what(l), "n": n})
			vars.merge(Deals.where(sim, sid, lid))
			x = n * maxf(1.0, SimData.group_xp(l.monsters) / maxf(1.0, l.count()) / 50.0)
		"escort":
			for pid: int in WorldSim._sorted_keys(sim.parties):
				var p: SimParty = sim.parties[pid]
				if p.kind == "caravan" and p.home == sid and p.state == "travel" and not p.frozen and String(p.plan.get("leg", "out")) == "out" \
						and p.leg == 0 and p.frac < 0.35 and p.path.size() >= 2:
					var dest: int = p.path[p.path.size() - 1]
					target = {"party": pid, "dest": dest, "base": p.size()}
					vars["dest"] = sim._site_label(dest)
					vars.merge(Deals.where(sim, sid, dest))
					x = p.size()
					break
			if target.is_empty():
				return {}
		"recover":
			var since := sim.t - 30 * WorldSim.DAY_H
			for i in range(sim.chronicle.size() - 1, -1, -1):
				var e: Dictionary = sim.chronicle[i]
				if int(e.get("t", 0)) < since:
					break
				if String(e.get("kind", "")) != "ambush" or str(e.get("vfrom", "")) != s.name or not bool(e.get("won", false)):
					continue
				var home := Deals.site_named(sim, str(e.get("rfrom", "")), {})
				for pid: int in WorldSim._sorted_keys(sim.parties):
					var p: SimParty = sim.parties[pid]
					if p.kind != "raid" or p.home != home or p.cargo.is_empty():
						continue
					var goods: Array = p.cargo.keys()
					goods.sort()
					var g: String = goods[0]
					var n := mini(int(p.cargo[g]), 60)
					if n <= 0:
						continue
					target = {"party": pid, "good": g, "n": n, "from": home}
					vars.merge({"good": g, "n": n, "site": sim._site_label(home), "raiders": "%s raiders" % SimConflict._adj(p.culture)})
					x = n * float(SimData.goods[g]["base"])
					break
				if not target.is_empty():
					break
			if target.is_empty():
				return {}
		"relief":
			if not DealsTalk.hungry(sim, s):
				return {}
			var n := clampi(s.pop() / 2, 20, 300)
			target = {"good": "food", "n": n}
			vars["n"] = n
			x = n * SimEconomy.price(s, "food") * 1.1
		"defend":
			for pid: int in WorldSim._sorted_keys(sim.parties):
				var p: SimParty = sim.parties[pid]
				if p.kind in ["raid", "army"] and p.target == sid and p.state == "travel" and String(p.plan.get("leg", "out")) == "out" \
						and String(p.plan.get("mode", "settlement")) == "settlement":
					target = {"party": pid, "from": p.home, "base": p.size(), "mark": sim.chronicle.size()}
					vars.merge({"site": sim._site_label(p.home), "raiders": "%s raiders" % SimConflict._adj(p.culture)})
					x = p.size()
					break
			if target.is_empty():
				return {}
		"message":
			var cand: Array = Deals.neighbours(sim, sid)
			if cand.is_empty():
				return {}
			var to: int = Deals.pick(cand, key)
			target = {"site": to}
			vars["site"] = sim._site_label(to)
			vars.merge(Deals.where(sim, sid, to))
			x = float(vars["tiles"])
		"siege":
			for oid: int in WorldSim._sorted_keys(sim.settlements):
				var o: SimSettlement = sim.settlements[oid]
				if o.faction == s.faction and o.besieged_by >= 0 and sim.parties.has(o.besieged_by):
					var army: SimParty = sim.parties[o.besieged_by]
					target = {"site": oid, "party": army.id}
					vars.merge({"site": o.name, "raiders": sim.faction_name(army.faction)})
					vars.merge(Deals.where(sim, sid, oid))
					x = 1.0
					break
			if target.is_empty():
				return {}
	var coin_d: Array = d.get("coin", [10, 0])
	var coin := float(coin_d[0]) + float(coin_d[1]) * x
	if kind == "relief":
		coin = x
	coin = minf(coin, s.wealth * float(_Q()["wealth_share"]))
	var why := Deals.fill(String(Deals.pick(d["why"], key + ["why"])), vars)
	var goal := Deals.fill(String(d["goal"]), vars)
	var q := {"id": "q%d.%d.%s" % [sid, day, kind], "kind": kind, "site": sid, "faction": str(s.faction), "day": day,
		"title": _title(kind, vars), "why": why, "goal": goal, "due": sim.t + int(float(d.get("days", 5)) * WorldSim.DAY_H),
		"target": target, "state": "offered", "players": [],
		"reward": {"coin": maxi(0, floori(coin)), "standing": int(d.get("standing", 0)), "xp": int(d.get("xp", 0)),
			"item": Deals.h(key + ["item"]) % 1000 < int(float(d.get("item", 0.0)) * 1000.0)},
		"progress": {"have": 0, "need": int(target.get("n", 1)), "text": ""}}
	if bool(d.get("patron", false)):
		q["patron"] = true
	return q

static func _title(kind: String, v: Dictionary) -> String:
	match kind:
		"bounty":
			return "Bounty: the %s" % v.get("lair", "lair")
		"hunt":
			return "Hunt: %s" % v.get("lair", "the beast")
		"escort":
			return "Escort to %s" % v.get("dest", "?")
		"recover":
			return "Recover the %s" % v.get("good", "goods")
		"relief":
			return "Food for %s" % v.get("town", "the town")
		"defend":
			return "Defend %s" % v.get("town", "the town")
		"message":
			return "Word to %s" % v.get("site", "?")
		"siege":
			return "Break the siege of %s" % v.get("site", "?")
	return kind

## Is this quest still offered (the thing it is about still there)?
static func still_valid(sim: WorldSim, q: Dictionary) -> bool:
	var t: Dictionary = q["target"]
	if not sim.settlements.has(int(q["site"])):
		return false
	match String(q["kind"]):
		"bounty", "hunt":
			return sim.lairs.has(int(t["lair"]))
		"escort":
			var p: SimParty = sim.parties.get(int(t["party"]))
			return p != null and String(p.plan.get("leg", "out")) == "out" and p.leg == 0
		"recover", "defend", "siege":
			return sim.parties.has(int(t["party"]))
	return true

## Where the quest's thing is (tiles), for "near" checks; INF when nowhere.
static func target_pos(sim: WorldSim, q: Dictionary, party_pos: Callable) -> Vector2:
	var t: Dictionary = q["target"]
	match String(q["kind"]):
		"bounty", "hunt":
			return Deals.site_xy(sim, int(t["lair"]))
		"escort":
			var p: SimParty = sim.parties.get(int(t["party"]))
			return party_pos.call(p) if p != null else Vector2.INF
		"message", "siege":
			return Deals.site_xy(sim, int(t["site"]))
	return Deals.site_xy(sim, int(q["site"]))

## Advance an active quest from the sim and the players' positions. Returns the new state
## ("ready", "done", "failed", "lapsed", "beaten") or "" when nothing changed (progress may
## have). ctx: {near: Callable(pos, tiles) -> Array[player names in q.players],
## party_pos: Callable(SimParty) -> Vector2}. Escort holding and release are DealsSystem's.
static func check(sim: WorldSim, q: Dictionary, ctx: Dictionary) -> String:
	var t: Dictionary = q["target"]
	var pr: Dictionary = q["progress"]
	var near: Callable = ctx["near"]
	var nt := float(_Q()["near_tiles"])
	var sid := int(q["site"])
	if not sim.settlements.has(sid) or str(sim.settlements[sid].faction) != String(q["faction"]):
		return "lapsed"
	var kind := String(q["kind"])
	match kind:
		"bounty", "hunt":
			var lid := int(t["lair"])
			var now: int = (sim.lairs[lid] as SimLair).count() if sim.lairs.has(lid) else 0
			var last := int(t.get("left", t["base"]))
			if now < last:
				if not (near.call(Deals.site_xy(sim, lid), nt) as Array).is_empty():
					pr["have"] = int(pr["have"]) + (last - now)
				t["left"] = now
			elif now > last:
				t["left"] = now
			pr["text"] = "%d of %d" % [mini(int(pr["have"]), int(pr["need"])), int(pr["need"])]
			if int(pr["have"]) >= int(pr["need"]):
				return "ready" if String(q["state"]) != "ready" else ""
			if not sim.lairs.has(lid):
				return "beaten"
		"escort":
			var p: SimParty = sim.parties.get(int(t["party"]))
			if p == null:
				return "failed"
			if String(p.plan.get("leg", "out")) == "home":
				var with := float(t.get("with", 0)) / maxf(1.0, float(t.get("seen", 0)))
				if p.size() * 2 >= int(t["base"]) and with >= 0.5:
					return "done"
				return "failed"
			if not p.held and p.state == "travel":
				t["seen"] = int(t.get("seen", 0)) + 1
				var at: Vector2 = (ctx["party_pos"] as Callable).call(p)
				if not (near.call(at, 60.0) as Array).is_empty():
					t["with"] = int(t.get("with", 0)) + 1
			pr["text"] = "%d of %d with the caravan" % [p.size(), int(t["base"])]
		"recover":
			if not sim.parties.has(int(t["party"])) and String(q["state"]) == "active":
				pr["text"] = "the raiders are home; the goods may be anywhere"
		"defend":
			var mark := int(t.get("mark", 0))
			var town: String = sim.settlements[sid].name
			for i in range(mark, sim.chronicle.size()):
				var e: Dictionary = sim.chronicle[i]
				var k := String(e.get("kind", ""))
				if (k == "raid" or k == "raid_repelled") and str(e.get("site", "")) == town:
					var won := k == "raid" and bool(e.get("won", false))
					if won:
						return "failed"
					return "done" if not (near.call(Deals.site_xy(sim, sid), nt) as Array).is_empty() else "beaten"
			t["mark"] = sim.chronicle.size()
			if not sim.parties.has(int(t["party"])):
				return "lapsed"
		"message":
			if not bool(t.get("visited", false)) and not (near.call(Deals.site_xy(sim, int(t["site"])), 30.0) as Array).is_empty():
				t["visited"] = true
				pr["have"] = 1
				pr["text"] = "visited; go back"
				return "ready"
		"siege":
			var oid := int(t["site"])
			if not sim.settlements.has(oid) or str(sim.settlements[oid].faction) != String(q["faction"]):
				return "failed"
			if not (near.call(Deals.site_xy(sim, oid), nt) as Array).is_empty():
				t["visited"] = true
			if sim.settlements[oid].besieged_by < 0:
				return "done" if bool(t.get("visited", false)) else "beaten"
	if sim.t > int(q["due"]) and String(q["state"]) != "ready":
		return "lapsed"
	return ""

## Delivery quests take goods at the turn-in.
static func delivers(q: Dictionary) -> bool:
	return String(q["kind"]) in ["recover", "relief"]

## Quests that end by themselves (paid where they end) rather than at a turn-in.
static func self_ending(q: Dictionary) -> bool:
	return String(q["kind"]) in ["escort", "defend", "siege"]
