## Deals over three game days (headless): on a generated world a player stands in the spawn
## town; each day prints its people and what each offers (with the line they say), the smith's
## rack and the store's shelves at this player's prices, the work on offer and why, and the
## news. Between days the world is pushed: raiders arrive (Life's cheat) after day 1, and a
## famine is forced after day 2 (the granary emptied), so the offers visibly follow the world.
## On day 1 a round of buying and selling prints the town's books and the player's purse
## before and after, then the sim's audit.
##   godot --headless -s res://tools/deals_day.gd -- seed=3 [days=3]
extends SceneTree

var host: WorldHost
var life: LifeSystem
var deals: DealsSystem
var p: HostEntity

func _initialize() -> void:
	var o := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		o[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var seed_v := int(o.get("seed", "3"))
	var w := WorldGen.generate(1024, 512, seed_v)
	host = WorldHost.new(w)
	Systems.install_host(host)
	life = host.system(HostSystem.LIFE)
	deals = host.system(HostSystem.DEALS)
	var ms: MonstersSystem = host.system(HostSystem.MONSTERS)
	ms.director_enabled = 0
	if host.sim == null or deals == null or life == null:
		print("no sim, deals or life")
		quit(1)
		return
	var home := _spawn_town()
	var next := _neighbour(home)
	p = host.add_player("trader", 2, {"class": "fighter"})
	p.combatant.stats.max_hp = 9999
	p.combatant.stats.current_hp = 9999
	p.character.inventory.coin = 500
	_to(LifeTown.site_pos(host, home) + Vector2(0, 3))
	var s: SimSettlement = host.sim.settlements[home]
	print("== seed %d: %s, %s %s %s of %s; neighbour %s" % [seed_v, s.name, "an" if s.culture[0] in "aeiou" else "a", s.culture, s.tier, host.sim.faction_name(s.faction),
		host.sim._site_label(next) if next >= 0 else "-"])
	# a little history first, so there is news
	host.sleep(24.0 * 20)
	_catch_up()
	for day in int(o.get("days", "3")):
		_run(70)
		_day(home)
		if day == 0:
			_trade(home)
		if day == 0 and next >= 0:
			print("")
			life.schedule("raid", 0.0, home)
			_to(LifeTown.site_pos(host, home) + Vector2(0, 3))
			_run(30 * 120)
			var n := 0
			for i in range(host.sim.chronicle.size() - 1, -1, -1):
				if int(host.sim.chronicle[i]["t"]) < host.sim.t - 24 or n >= 3:
					break
				print("  chronicle: " + host.sim.describe(host.sim.chronicle[i]))
				n += 1
		if day == 1 and host.sim.settlements.has(home):
			var hs: SimSettlement = host.sim.settlements[home]
			hs.stock["food"] = SimEconomy.target(hs, "food") * 0.04
			hs.hungry = 2
			print("\n  [cheat] blight: the granary of %s is all but empty" % hs.name)
		host.sleep(24.0)
		_catch_up()
	print("\n  sim audit after %d days: %s" % [int(o.get("days", "3")), str(host.sim.audit()) if not host.sim.audit().is_empty() else "clean"])
	print("  " + deals.summary())
	quit(0)

func _day(sid: int) -> void:
	if not host.sim.settlements.has(sid):
		print("\n-- %s: the town is gone" % WorldClock.describe(host.clock.hours()))
		return
	var s: SimSettlement = host.sim.settlements[sid]
	print("\n-- %s (sim day %d) at %s: %d souls, wealth %d, food %d (price %.2f), ore %d (price %.2f), tools %d; %s" % [
		WorldClock.describe(host.clock.hours()), Deals.day(host.sim), s.name, s.pop(), roundi(s.wealth), roundi(float(s.stock["food"])),
		SimEconomy.price(s, "food"), roundi(float(s.stock["ore"])), SimEconomy.price(s, "ore"), roundi(float(s.stock["tools"])),
		", ".join(DealsTalk.situation(host.sim, sid))])
	var seen := {}
	for x: HostEntity in life.actors_at(sid):
		var role := String(x.get_meta("sim")["role"])
		if not bool(x.get_meta("talk", false)) or (seen.has(role) and role in ["guard", "townsfolk"]):
			continue
		seen[role] = true
		_to(x.body.pos + Vector2(1.5, 0))
		var why := deals.talk(p, x.id)
		if why != "":
			print("  %s (%s): will not talk (%s)" % [x.name, role, why])
			continue
		var t: Dictionary = deals.talks[p.id]
		var opts: Array = deals.options(p, t).map(func(op: Dictionary) -> String: return String(op["label"]))
		print("  %s (%s): \"%s\"\n      offers: %s" % [x.name, role, DealsTalk.line(host.sim, host.world.world_seed, deals._person(p, t), sid,
			host.clock.hour_of_day()), " | ".join(opts)])
		deals._close(p.id, "left")
	for r: Dictionary in DealsTalk.rumours(host.sim, sid, "keeper", deals.names):
		print("  news (a keeper's): %s%s" % [r["text"], "  [site %d, %s]" % [int(r["site"]), (String(r["dist"]) + " " + String(r["dir"])).strip_edges()] if int(r["site"]) >= 0 else ""])
	var smith := deals.listings(p, sid, "smith")
	print("  the smith's rack (%d):" % smith.size())
	for l: Dictionary in smith:
		print("      %-44s %5d coin" % [ItemGen.name(l["item"]), int(l["price"])])
	var shelves := deals.listings(p, sid, "store")
	print("  the store: " + ", ".join(shelves.filter(func(l: Dictionary) -> bool: return int(l["n"]) > 0).map(func(l: Dictionary) -> String:
		return "%s x%d @%d" % [ItemGen.name(l["item"]), int(l["n"]), int(l["price"])])))
	var empty: Array = shelves.filter(func(l: Dictionary) -> bool: return int(l["n"]) == 0).map(func(l: Dictionary) -> String: return ItemGen.name(l["item"]))
	if not empty.is_empty():
		print("      sold out: " + ", ".join(empty))
	var offers := deals.offers_at(sid)
	print("  work on offer (%d):" % offers.size())
	for q: Dictionary in offers:
		print("      [%s, from the %s%s] %s: %s Reward %d coin, %d standing, %d XP%s" % [q["kind"], q.get("giver", "?"),
			", patrons only" if bool(q.get("patron", false)) else "", q["title"], q["why"], int(q["reward"]["coin"]),
			int(q["reward"]["standing"]), int(q["reward"]["xp"]), ", and a piece of smith work" if bool(q["reward"]["item"]) else ""])
		print("          %s" % q["goal"])

## A round of buying and selling through the open shops, with the books before and after.
func _trade(sid: int) -> void:
	var s: SimSettlement = host.sim.settlements[sid]
	var inv := p.character.inventory
	var b0 := _books(s)
	var c0 := inv.coin
	print("\n  books before: %s; purse %d" % [b0, c0])
	deals.talks[p.id] = {"person": 0, "site": sid, "kind": "settlement", "role": "merchant", "of": sid, "faction": str(s.faction),
		"view": "shop", "shop": "store"}
	for want: Array in [["tile:rope", 2], ["trade:food", 40], ["supplies", 10]]:
		for l: Dictionary in deals.listings(p, sid, "store"):
			if String(l["item"]["base"]) == want[0]:
				print("    buy %d %s @%d: %s" % [want[1], ItemGen.name(l["item"]), int(l["price"]), _ok(deals.buy(p, String(l["id"]), int(want[1])))])
	deals.talks[p.id]["shop"] = "smith"
	var rack := deals.listings(p, sid, "smith")
	if not rack.is_empty():
		print("    buy %s @%d: %s" % [ItemGen.name(rack[0]["item"]), int(rack[0]["price"]), _ok(deals.buy(p, String(rack[0]["id"]), 1))])
	inv.add(Items.make("ore:iron", 30))
	inv.add({"base": "longsword", "count": 1, "material": "iron", "quality": "fine"})
	for base: String in ["ore:iron", "longsword"]:
		for i in Inventory.SIZE:
			var it := inv.at(i)
			if String(it.get("base", "")) == base:
				var n := Items.count(it)
				var before := inv.coin
				var why := deals.sell(p, i, n)
				print("    sell %d %s: %s%s" % [n, ItemGen.name(it), _ok(why), " for %d" % (inv.coin - before) if why == "" else ""])
				break
	deals.talks.erase(p.id)
	print("  books after:  %s; purse %d (%+d)" % [_books(s), inv.coin, inv.coin - c0])
	host.sleep(24.0 * 7)
	_catch_up()
	print("  a week later: %s; audit %s" % [_books(s), "clean" if host.sim.audit().is_empty() else str(host.sim.audit())])

static func _ok(why: String) -> String:
	return "ok" if why == "" else "refused (%s)" % why

func _books(s: SimSettlement) -> String:
	return "wealth %.1f, food %.1f, timber %.1f, ore %.1f, tools %.1f" % [s.wealth, float(s.stock["food"]), float(s.stock["timber"]),
		float(s.stock["ore"]), float(s.stock["tools"])]

func _spawn_town() -> int:
	var best := -1
	var bd := INF
	for sid: int in WorldSim._sorted_keys(host.sim.settlements):
		var s: SimSettlement = host.sim.settlements[sid]
		var d := absf(s.x - host.spawn.x) + (0.0 if s.band == "surface" else 4096.0)
		if d < bd:
			bd = d
			best = sid
	return best

func _neighbour(sid: int) -> int:
	for e: Array in host.sim.adj.get(sid, []):
		if host.sim.settlements.has(int(e[0])) and int(e[0]) != sid:
			return int(e[0])
	return -1

func _to(pos: Vector2) -> void:
	p.body.pos = pos
	TileCollision.depenetrate(host.world, p.body)

func _run(n: int) -> void:
	for i in n:
		p.combatant.stats.current_hp = maxi(p.combatant.stats.current_hp, 9000)
		host.tick()
		host.outbox.clear()

func _catch_up() -> void:
	var g := 0
	while host.sim_behind() > 0 and g < 20000:
		host.tick()
		host.outbox.clear()
		g += 1
