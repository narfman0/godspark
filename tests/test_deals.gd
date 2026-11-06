## Deals: talk and rumours, shops and smiths through the sim's books, quests from the sim's
## state, patrons, the wire, and that dealing never changes the world's history.
extends RefCounted

static func rig(deals := true) -> Dictionary:
	var w := WorldGen.generate(1024, 512, 4)
	var host := WorldHost.new(w)
	Dice.rng = host.rng
	var out := {"host": host}
	out["rules"] = RulesSystem.new()
	host.add_system(out["rules"])
	(out["rules"] as RulesSystem).cheats = true
	out["combat"] = CombatSystem.new()
	host.add_system(out["combat"])
	out["items"] = ItemsSystem.new()
	host.add_system(out["items"])
	var ms := MonstersSystem.new()
	ms.director_enabled = 0
	ms.lairs_enabled = false
	host.add_system(ms)
	out["ms"] = ms
	out["life"] = LifeSystem.new()
	host.add_system(out["life"])
	if deals:
		out["deals"] = DealsSystem.new()
		host.add_system(out["deals"])
	return out

static func put(host: WorldHost, name: String, pos: Vector2) -> HostEntity:
	var e := host.add_player(name, host.entities.size() + 2, {"class": "fighter"})
	e.body.pos = pos
	TileCollision.depenetrate(host.world, e.body)
	e.combatant.stats.max_hp = 9999
	e.combatant.stats.current_hp = 9999
	return e

static func ticks(host: WorldHost, n: int) -> void:
	for i in n:
		host.tick()

static func advance(host: WorldHost, hours: float) -> void:
	host.sleep(hours)
	var guard := 0
	while host.sim_behind() > 0 and guard < 3000:
		host.tick()
		guard += 1
	ticks(host, 65)

## The surface settlement nearest the middle of the world.
static func town_of(host: WorldHost) -> int:
	var best := -1
	var bd := INF
	for sid: int in WorldSim._sorted_keys(host.sim.settlements):
		var s: SimSettlement = host.sim.settlements[sid]
		if s.band != "surface":
			continue
		var d := absf(s.x - host.world.width / 2.0)
		if d < bd:
			bd = d
			best = sid
	return best

static func neighbour(host: WorldHost, sid: int) -> int:
	for e: Array in host.sim.adj.get(sid, []):
		if host.sim.settlements.has(int(e[0])) and int(e[0]) != sid:
			return int(e[0])
	return -1

## A person of a role at a site that Life shows, or null.
static func person(life: LifeSystem, sid: int, role: String) -> HostEntity:
	for e: HostEntity in life.actors_at(sid):
		if String(e.get_meta("sim")["role"]) == role:
			return e
	return null

## Stand beside x (as the cheat does) and settle.
static func beside(host: WorldHost, p: HostEntity, x: HostEntity) -> void:
	p.body.pos = x.body.pos + Vector2(1.5, 0)
	TileCollision.depenetrate(host.world, p.body)

func run(t: TestLog) -> void:
	for f: String in ["_codec", "_talk", "_shop", "_quests", "_patron", "_wander"]:
		var t0 := Time.get_ticks_msec()
		call(f, t)
		print("  %s: %d ms" % [f, Time.get_ticks_msec() - t0])

# --- the wire ----------------------------------------------------------------------------------

func _codec(t: TestLog) -> void:
	var dc := DealsClient.new()
	var item := {"base": "longsword", "count": 1, "material": "iron", "quality": "fine", "affixes": ["embers"]}
	dc.handle(DealsCodec.Msg.SHOP, DealsCodec.write({"open": true, "kind": "smith", "site": 4, "town": "Calwick",
		"listings": [{"id": "r0", "item": item, "n": 1, "price": 38}], "sell": {"12": 5}, "wealth": 900}))
	t.eq(dc.shop["listings"][0]["item"], item, "a listing's item survives the wire")
	t.eq(dc.shop["listings"][0]["price"], 38, "price is an int")
	t.eq(dc.shop["sell"].get(12), 5, "sell prices by slot (int keys)")
	var q := {"id": "q4.2.bounty", "kind": "bounty", "site": 4, "day": 2, "due": 300, "state": "active", "title": "Bounty",
		"target": {"lair": 9, "n": 3, "base": 5}, "reward": {"coin": 40, "standing": 6, "xp": 120, "item": true},
		"progress": {"have": 1, "need": 3, "text": "1 of 3"}, "players": ["ann"]}
	dc.handle(DealsCodec.Msg.QUESTS, DealsCodec.write({"quests": [q]}))
	t.eq(dc.quests[0], q, "a quest round-trips (ints come back as ints)")
	t.eq(dc.quests_in("active").size(), 1, "active quests")
	dc.handle(DealsCodec.Msg.RUMOUR, DealsCodec.write({"rumours": [{"id": 7, "text": "x", "site": 3, "t": 40, "tiles": 200, "dir": "east", "dist": "a short walk"}], "all": true}))
	dc.handle(DealsCodec.Msg.RUMOUR, DealsCodec.write({"rumours": [{"id": 8, "text": "y", "site": -1, "t": 41, "tiles": 0}], "all": false}))
	t.eq(dc.rumours.size(), 2, "rumours accumulate")
	t.eq(dc.map_marks().size(), 1, "map marks are the rumours with a site")
	t.eq(dc.rumours[0]["site"], 3, "site ids are ints")
	dc.handle(DealsCodec.Msg.TALK, DealsCodec.write({"open": true, "id": 12, "name": "Bo", "role": "merchant", "site": 4, "line": "Hi",
		"options": [{"id": "shop", "label": "Show me"}], "view": "main"}))
	t.check(dc.talking() and dc.conversation["id"] == 12, "a conversation opens")
	dc.handle(DealsCodec.Msg.TALK, DealsCodec.write({"open": false, "why": "far", "line": "You walked off"}))
	t.check(not dc.talking() and not dc.shopping() and dc.closed["why"] == "far", "and closes (shop too)")
	dc.handle(DealsCodec.Msg.PATRON, DealsCodec.write({"patrons": {"3": {"tier": 1, "standing": 30, "given": 1, "suspended": false, "name": "X"}}}))
	t.eq(dc.patrons["3"]["tier"], 1, "patron tiers")
	t.eq(DealsCodec.read(DealsCodec.write({"a": 1})), {"a": 1.0}, "JSON payloads")

# --- 1. talk -----------------------------------------------------------------------------------

func _talk(t: TestLog) -> void:
	var r := rig()
	var host: WorldHost = r["host"]
	var deals: DealsSystem = r["deals"]
	var life: LifeSystem = r["life"]
	var sid := town_of(host)
	var s: SimSettlement = host.sim.settlements[sid]
	var p := put(host, "ann", LifeTown.site_pos(host, sid) + Vector2(0, 3))
	ticks(host, 70)
	var keeper := person(life, sid, "keeper")
	var guard := person(life, sid, "guard")
	t.check(keeper != null and guard != null, "the town shows a keeper and a guard")
	if keeper == null or guard == null:
		return
	t.eq(deals.talk(p, keeper.id) if p.body.pos.distance_to(keeper.body.pos) > 6.0 else "far", "far", "too far to talk")
	beside(host, p, keeper)
	t.eq(deals.talk(p, keeper.id), "", "talks to the keeper beside them")
	t.check(deals.talks.has(p.id), "a conversation is open")
	var opts := deals.options(p, deals.talks[p.id]).map(func(o: Dictionary) -> String: return o["id"])
	t.check("rumours" in opts and "bye" in opts, "the keeper offers rumours (%s)" % ",".join(opts))
	# a real event about the town, told as a rumour with its place
	var lid := -1
	for l: int in WorldSim._sorted_keys(host.sim.lairs):
		lid = l
		break
	if lid >= 0:
		host.sim.log_event("monster_raid", {"what": "wolf pack", "lair": host.sim.lairs[lid].name, "site": s.name, "won": true,
			"killed": 3, "food": 40})
	var told := DealsTalk.rumours(host.sim, sid, "keeper", {})
	t.check(not told.is_empty() and int(told[0]["id"]) == host.sim.chronicle.size() - 1, "the newest event is told first")
	t.eq(int(told[0]["site"]), sid, "with the site it concerns")
	t.check(String(told[0]["text"]).contains(s.name), "in the chronicle's words")
	t.check(DealsTalk.rumours(host.sim, sid, "smith", {}).filter(func(x: Dictionary) -> bool: return int(x["id"]) == told[0]["id"]).is_empty(),
		"a smith does not pass on a monster raid (priests and keepers do)")
	t.eq(deals.choose(p, "rumours"), "", "asks for news")
	t.check((deals.known[p.id] as Array).any(func(x: Dictionary) -> bool: return int(x["id"]) == int(told[0]["id"])), "hearing records it")
	var n0 := (deals.known[p.id] as Array).size()
	deals.choose(p, "rumours")
	t.eq((deals.known[p.id] as Array).size(), n0, "hearing it again adds nothing")
	# lines are data-driven and stable for the hour
	var who := {"key": "x", "role": "guard", "name": "Hal", "culture": s.culture}
	var l1 := DealsTalk.line(host.sim, 4, who, sid, 9.0)
	t.eq(DealsTalk.line(host.sim, 4, who, sid, 9.5), l1, "the same line within the hour band")
	t.check(l1 != "", "a guard says something: " + l1)
	s.hungry = 3
	t.check("hungry" in DealsTalk.situation(host.sim, sid), "a hungry town knows it")
	s.hungry = 0
	# walking away ends it
	p.body.pos += Vector2(30, 0)
	TileCollision.depenetrate(host.world, p.body)
	ticks(host, 16)
	t.check(not deals.talks.has(p.id), "walking away ends the conversation")
	# a hostile person will not talk
	beside(host, p, guard)
	life.add_standing(p.id, str(s.faction), -100, "test")
	t.eq(deals.talk(p, guard.id), "hostile", "a hostile guard will not talk")
	life.add_standing(p.id, str(s.faction), 100, "test")
	t.eq(deals.talk(p, guard.id), "", "made up: the guard talks")
	# the person leaving ends it
	life.unspawn(host, guard.id)
	ticks(host, 16)
	t.check(not deals.talks.has(p.id), "the person leaving ends the conversation")
	# saved with the player
	var saved := deals.save_player(p)
	var d2 := DealsSystem.new()
	d2.load_player(p, JSON.parse_string(JSON.stringify(saved)))
	t.eq((d2.known[p.id] as Array).size(), (deals.known[p.id] as Array).size(), "known rumours survive a save")
	t.eq(int(d2.known[p.id][0]["id"]), int(deals.known[p.id][0]["id"]), "with their ids as ints")

# --- 2. shops ----------------------------------------------------------------------------------

func _shop(t: TestLog) -> void:
	var r := rig()
	var host: WorldHost = r["host"]
	var deals: DealsSystem = r["deals"]
	var life: LifeSystem = r["life"]
	var sid := town_of(host)
	var s: SimSettlement = host.sim.settlements[sid]
	var p := put(host, "bob", LifeTown.site_pos(host, sid) + Vector2(0, 3))
	ticks(host, 70)
	var merchant := person(life, sid, "merchant")
	t.check(merchant != null, "a merchant")
	if merchant == null:
		return
	beside(host, p, merchant)
	t.eq(deals.talk(p, merchant.id), "", "talks to the merchant")
	t.eq(deals.choose(p, "shop"), "" if DealsShop.has_store(host.world, sid) else "no_option", "opens the shop")
	if not DealsShop.has_store(host.world, sid):
		deals.talks[p.id]["shop"] = "store"
	var shelf := deals.listings(p, sid, "store")
	var rope := {}
	for l: Dictionary in shelf:
		if String(l["item"]["base"]) == "tile:rope":
			rope = l
	t.check(not rope.is_empty() and int(rope["n"]) > 0, "rope on the shelf (%s)" % str(rope))
	t.check(shelf.any(func(l: Dictionary) -> bool: return String(l["item"]["base"]) == "trade:food"), "food as a trade good")
	# buying moves coin to the town and takes the goods out of its stock
	var inv := p.character.inventory
	inv.coin = 500
	var w0 := s.wealth
	var timber0 := float(s.stock["timber"])
	var ropes0 := inv.count_base("tile:rope")
	t.eq(deals.buy(p, String(rope["id"]), 2), "", "buys two ropes")
	t.eq(inv.coin, 500 - 2 * int(rope["price"]), "the player paid")
	t.check(is_equal_approx(s.wealth, w0 + 2 * int(rope["price"])), "the town got the coin")
	t.check(is_equal_approx(float(s.stock["timber"]), timber0 - 2.0 * float(rope["units"])), "the timber came out of its stock")
	t.eq(inv.count_base("tile:rope"), ropes0 + 2, "the ropes are in the pack")
	t.eq(deals.buy(p, String(rope["id"]), 99999), "none_left", "cannot buy more than there is")
	inv.coin = 0
	t.eq(deals.buy(p, String(rope["id"]), 1), "coin", "cannot buy without coin")
	# selling ore: the local price, the town pays out of its wealth, the ore enters its stock
	inv.add(Items.make("ore:iron", 20))
	var slot := -1
	for i in Inventory.SIZE:
		if String(inv.at(i).get("base", "")) == "ore:iron":
			slot = i
	var sp: Dictionary = deals.sell_prices(p, sid)
	t.check(sp.has(str(slot)), "the town will buy iron ore")
	var ore0 := float(s.stock["ore"])
	var w1 := s.wealth
	t.eq(deals.sell(p, slot, 20), "", "sells 20 iron ore")
	t.eq(inv.coin, 20 * int(sp[str(slot)]), "paid the quoted price")
	t.check(is_equal_approx(s.wealth, w1 - inv.coin), "out of the town's wealth")
	t.check(is_equal_approx(float(s.stock["ore"]), ore0 + 20 * 0.5), "ore (units) into its stock")
	inv.add(Items.make("tile:rubble", 5))
	for i in Inventory.SIZE:
		if String(inv.at(i).get("base", "")) == "tile:rubble":
			slot = i
	t.eq(deals.sell(p, slot, 5), "worthless", "rubble is worthless")
	# loot gear sells for a fraction of its value
	var sword := {"base": "longsword", "count": 1, "material": "iron", "quality": "fine"}
	t.check(is_equal_approx(DealsShop.sell_each(host.sim, sid, sword), Items.value(sword) * 0.25), "gear at a quarter of its value")
	# a town that cannot pay
	var rich := s.wealth
	s.wealth = 1.0
	inv.add(Items.make("trade:luxuries", 10))
	for i in Inventory.SIZE:
		if String(inv.at(i).get("base", "")) == "trade:luxuries":
			slot = i
	t.eq(deals.sell(p, slot, 10), "poor", "a broke town cannot pay")
	s.wealth = rich
	# prices move with standing
	var m0 := DealsShop.buy_mult({"standing": 0})
	t.check(DealsShop.buy_mult({"standing": 100}) < m0 and DealsShop.buy_mult({"standing": -60}) > m0, "standing moves prices")
	t.check(DealsShop.buy_mult({"price_mult": 0.15}) < m0 and DealsShop.sell_mult({"price_mult": 0.15}) > 1.0, "Silver Tongue")
	t.check(DealsShop.buy_mult({"bond": 1}) < m0, "a Bond with the people")
	t.check(DealsShop.buy_mult({"standing": 100, "bond": 1, "price_mult": 0.5, "patron": 3}) >= 0.6, "never below the floor")
	# the smith's rack: deterministic per day, sold pieces stay sold, the town decides it
	var day := Deals.day(host.sim)
	var rack := DealsShop.rack(host.sim, 4, sid, day, {})
	t.check(not rack.is_empty(), "the smith has a rack (%d)" % rack.size())
	t.eq(DealsShop.rack(host.sim, 4, sid, day, {}), rack, "the same rack all day")
	t.check(DealsShop.rack(host.sim, 4, sid, day + 1, {}) != rack, "a new rack tomorrow")
	t.eq(DealsShop.rack(host.sim, 4, sid, day, {0: true}).size(), rack.size() - 1, "a sold piece is gone for the day")
	for l: Dictionary in rack:
		t.check(Items.budget_of(l["item"]).x <= 3 and Items.budget_of(l["item"]).y <= 3 and not l["item"].has("magic"), "smith work is plain and within the budget")
		break
	var saved := {"tier": s.tier, "wealth": s.wealth, "ore": s.stock["ore"], "workers": s.workers, "culture": s.culture}
	s.tier = "city"
	s.workers = 3000
	s.wealth = 30000.0
	s.stock["ore"] = 3000.0
	s.stock["tools"] = 3000.0
	s.culture = "dwarf"
	var city := DealsShop.rack(host.sim, 4, sid, day, {})
	s.tier = "hamlet"
	s.workers = 40
	s.wealth = 5.0
	s.culture = "elf"
	var hamlet := DealsShop.rack(host.sim, 4, sid, day, {})
	s.stock["ore"] = 0.0
	var bare := DealsShop.rack(host.sim, 4, sid, day, {})
	var qi := func(l: Array) -> float:
		var n := 0.0
		for x: Dictionary in l:
			n += Items.quality_order().find(String(x["item"]["quality"]))
		return n / maxf(1.0, l.size())
	t.check(city.size() > hamlet.size(), "a city's rack is bigger (%d vs %d)" % [city.size(), hamlet.size()])
	t.check(qi.call(city) > qi.call(hamlet) + 0.5, "and finer (%.2f vs %.2f)" % [qi.call(city), qi.call(hamlet)])
	var dwarf_kinds: Dictionary = Deals.prices()["smith"]["kinds"]["dwarf"]
	t.check(city.all(func(x: Dictionary) -> bool: return dwarf_kinds.has(String(x["item"]["base"]))), "dwarves make dwarf things")
	var elf_kinds: Dictionary = Deals.prices()["smith"]["kinds"]["elf"]
	t.check(hamlet.all(func(x: Dictionary) -> bool: return elf_kinds.has(String(x["item"]["base"]))), "elves make elf things")
	t.check(bare.size() == 1 and String(bare[0]["item"]["quality"]) == "crude", "no ore: one crude piece")
	s.tier = saved["tier"]
	s.wealth = saved["wealth"]
	s.stock["ore"] = saved["ore"]
	s.workers = saved["workers"]
	s.culture = saved["culture"]
	# buying from the rack through the books
	deals.talks[p.id]["shop"] = "smith"
	var rk := deals.listings(p, sid, "smith")
	inv.coin = 100000
	var ore1 := float(s.stock["ore"])
	var w2 := s.wealth
	t.eq(deals.buy(p, String(rk[0]["id"]), 1), "", "buys the first piece on the rack")
	t.check(is_equal_approx(s.wealth, w2 + int(rk[0]["price"])), "the town got the coin")
	t.check(float(s.stock["ore"]) < ore1 or String(rk[0]["good"]) == "", "its ore went down")
	t.eq(deals.listings(p, sid, "smith").size(), rk.size() - 1, "the piece is gone from the rack")
	t.eq(deals.buy(p, String(rk[0]["id"]), 1), "no_listing", "and cannot be bought twice")
	# a week of the sim afterwards behaves
	advance(host, 24.0 * 7)
	t.eq(host.sim.audit(), [] as Array[String], "the sim's audit after a week: no negative books")
	t.check(deals.listings(p, sid, "smith").size() >= 1, "the rack restocks with the days")
	# services
	var keeper := person(life, sid, "keeper")
	if keeper != null:
		beside(host, p, keeper)
		t.eq(deals.talk(p, keeper.id), "", "talks to the keeper")
		var has_tavern := DealsShop.has_building(host.world, sid, "tavern")
		var bw := s.wealth
		var why := deals.service(p, "bed")
		t.eq(why, "" if has_tavern else "no_service", "a bed at the tavern")
		if has_tavern:
			t.check(p.character.bed is Vector2i and p.character.bed_inn, "the respawn point is the inn")
			t.check(s.wealth > bw, "the town got paid")
			var rp := (r["rules"] as RulesSystem).respawn_point(p)
			t.check(rp.distance_to(Vector2(p.character.bed.x + 0.5, p.character.bed.y)) < 0.01, "Rules respawns there")

# --- 3. quests ---------------------------------------------------------------------------------

func _quests(t: TestLog) -> void:
	var r := rig()
	var host: WorldHost = r["host"]
	var deals: DealsSystem = r["deals"]
	var life: LifeSystem = r["life"]
	var rules: RulesSystem = r["rules"]
	var sid := town_of(host)
	var s: SimSettlement = host.sim.settlements[sid]
	var p := put(host, "cat", LifeTown.site_pos(host, sid) + Vector2(0, 3))
	var p2 := put(host, "dan", LifeTown.site_pos(host, sid) + Vector2(2, 3))
	ticks(host, 70)
	# famine and a departing caravan: work appears for them
	s.hungry = 3
	var nb := neighbour(host, sid)
	var cid := life.cheat_party("caravan", sid, nb, 0.02) if nb >= 0 else -1
	if cid > 0:
		host.sim.parties[cid].leg = 0
		host.sim.parties[cid].route = host.sim.route_id(host.sim.parties[cid].path[0], host.sim.parties[cid].path[1])
	var list := deals.offers_at(sid)
	var kinds := list.map(func(q: Dictionary) -> String: return q["kind"])
	print("  offers at %s: %s (escort party %d)" % [s.name, ", ".join(list.map(func(q: Dictionary) -> String: return "%s from the %s" % [q["kind"], q.get("giver", "?")])), cid])
	t.check("relief" in kinds, "a hungry town asks for food (%s)" % ",".join(kinds))
	t.check(cid < 0 or "escort" in kinds, "a leaving caravan wants an escort")
	t.check("message" in kinds, "the keeper has a message to carry")
	t.eq(deals.offers_at(sid), list, "the same offers all day")
	t.eq(DealsQuests.offers(host.sim, host.world.world_seed, sid, Deals.day(host.sim)).map(func(q: Dictionary) -> String: return q["id"]),
		list.map(func(q: Dictionary) -> String: return q["id"]), "made from (seed, site, day) and the sim")
	for q: Dictionary in list:
		t.check(String(q["why"]) != "" and String(q["goal"]) != "" and int(q["due"]) > host.sim.t, "%s: why, goal and a time limit" % q["kind"])
		t.check(int(q["reward"]["coin"]) <= s.wealth * 0.2 + 1, "%s: coin bounded by the town's wealth" % q["kind"])
	# relief: accept from the priest (or keeper), deliver food, it enters the stock
	var relief: Dictionary = list.filter(func(q: Dictionary) -> bool: return q["kind"] == "relief")[0] if "relief" in kinds else {}
	if not relief.is_empty():
		var giver := person(life, sid, String(relief["giver"]))
		t.check(giver != null, "the giver (%s) is here" % relief["giver"])
		if giver != null:
			beside(host, p, giver)
			t.eq(deals.talk(p, giver.id), "", "talks to the giver")
			t.check(deals.options(p, deals.talks[p.id]).any(func(o: Dictionary) -> bool: return o["id"] == "quests"), "they have work")
			t.eq(deals.accept(p, String(relief["id"])), "", "accepts the relief")
			t.eq(deals.accept(p, String(relief["id"])), "already", "once")
			var qid := String(relief["id"])
			t.eq(deals.turn_in(p, qid), "missing", "no food yet")
			var n := int(relief["target"]["n"])
			p.character.inventory.add(Items.make("trade:food", n))
			var food0 := float(s.stock["food"])
			var w0 := s.wealth
			var c0 := p.character.inventory.coin
			var xp0 := p.character.xp
			var st0 := life.standing(p.id, str(s.faction))
			t.eq(deals.turn_in(p, qid), "", "delivers the food")
			t.check(is_equal_approx(float(s.stock["food"]), food0 + n), "the food entered the town's stock")
			t.eq(p.character.inventory.count_base("trade:food"), 0, "out of the pack")
			var paid := p.character.inventory.coin - c0
			t.check(paid > 0 and is_equal_approx(s.wealth, w0 - paid), "paid %d out of the town's wealth" % paid)
			t.check(p.character.xp > xp0, "XP")
			t.check(life.standing(p.id, str(s.faction)) > st0, "standing")
			t.eq(String(deals.quest(qid)["state"]), "done", "done")
			t.check(int(p.character.deeds.get("quest", 0)) >= 1, "a deed for Rules")
	s.hungry = 0
	# message: go there and come back; shared with a second player
	var msg: Dictionary = list.filter(func(q: Dictionary) -> bool: return q["kind"] == "message")[0] if "message" in kinds else {}
	if not msg.is_empty():
		var keeper := person(life, sid, "keeper")
		beside(host, p, keeper)
		beside(host, p2, keeper)
		deals.talk(p, keeper.id)
		deals.talk(p2, keeper.id)
		var qid := String(msg["id"])
		t.eq(deals.accept(p, qid), "", "accepts the message")
		t.eq(deals.accept(p2, qid), "", "a friend joins")
		t.eq((deals.quest(qid)["players"] as Array).size(), 2, "shared by both")
		t.eq(deals.turn_in(p, qid), "not_ready", "not there yet")
		var to := int(msg["target"]["site"])
		p.body.pos = Deals.site_xy(host.sim, to) + Vector2(0, 2)
		TileCollision.depenetrate(host.world, p.body)
		ticks(host, 31)
		t.eq(String(deals.quest(qid)["state"]), "ready", "visited: ready to turn in")
		p.body.pos = LifeTown.site_pos(host, sid) + Vector2(0, 3)
		TileCollision.depenetrate(host.world, p.body)
		var c1 := p2.character.inventory.coin
		t.eq(deals.turn_in(p, qid), "", "turned in")
		t.check(p2.character.inventory.coin >= c1, "the friend nearby shares the pay")
		var log1: Array = deals.quest_log(p2)
		t.check(log1.any(func(q: Dictionary) -> bool: return q["id"] == qid and q["state"] == "done"), "in the friend's log as done")
	# escort: the caravan waits for its escort, then goes
	var esc: Dictionary = list.filter(func(q: Dictionary) -> bool: return q["kind"] == "escort")[0] if "escort" in kinds else {}
	if not esc.is_empty():
		var m := person(life, sid, "merchant")
		if m == null:
			m = person(life, sid, "keeper")
		beside(host, p, m)
		deals.talk(p, m.id)
		if String(esc["giver"]) == "keeper" or m.get_meta("sim")["role"] == esc["giver"]:
			t.eq(deals.accept(p, String(esc["id"])), "", "accepts the escort")
			var cp: SimParty = host.sim.parties[cid]
			t.check(cp.held, "the caravan is held for its escort")
			var f0 := cp.frac
			host.sim.step(1)
			t.eq(cp.frac, f0, "it does not move while held")
			p.body.pos = deals._party_pos(cp)
			TileCollision.depenetrate(host.world, p.body)
			ticks(host, 31)
			t.check(not cp.held, "the escort is beside it: it leaves")
			t.eq(deals.abandon(p, String(esc["id"])), "", "gives it up")
			t.eq(String(deals.quest(String(esc["id"]))["state"]), "abandoned", "abandoned")
	# bounty: a lair that another party clears is "someone got there first"
	var lid := -1
	for l: int in WorldSim._sorted_keys(host.sim.lairs):
		if not host.sim.lairs[l].apex:
			lid = l
			break
	if lid >= 0:
		var q := {"id": "qtest.bounty", "kind": "bounty", "site": sid, "faction": str(s.faction), "day": 0, "title": "Bounty", "why": "",
			"goal": "", "due": host.sim.t + 200, "target": {"lair": lid, "n": 2, "base": host.sim.lairs[lid].count(), "left": host.sim.lairs[lid].count()},
			"state": "active", "players": ["cat"], "reward": {"coin": 40, "standing": 4, "xp": 50, "item": false}, "progress": {"have": 0, "need": 2, "text": ""}}
		deals.quests[q["id"]] = q
		# a kill near the lair by the party counts
		p.body.pos = Deals.site_xy(host.sim, lid) + Vector2(0, 2)
		var slug: String = host.sim.lairs[lid].monsters.keys()[0]
		host.sim.lair_killed(lid, slug, "cat")
		ticks(host, 31)
		t.eq(int(deals.quest(q["id"])["progress"]["have"]), 1, "a kill at the lair counts")
		p.body.pos = LifeTown.site_pos(host, sid) + Vector2(0, 3)
		var w3 := s.wealth
		SimConflict._lair_gone(host.sim, host.sim.lairs[lid], "")
		ticks(host, 31)
		t.eq(String(deals.quest(q["id"])["state"]), "beaten", "cleared by someone else: beaten")
		t.check(s.wealth <= w3, "partial thanks (%.0f)" % (w3 - s.wealth))
	# the town falls: open quests lapse
	var q2 := {"id": "qtest.msg", "kind": "message", "site": sid, "faction": str(s.faction), "day": 0, "title": "M", "why": "", "goal": "",
		"due": host.sim.t + 200, "target": {"site": nb}, "state": "active", "players": ["cat"],
		"reward": {"coin": 1, "standing": 1, "xp": 1, "item": false}, "progress": {"have": 0, "need": 1, "text": ""}}
	deals.quests[q2["id"]] = q2
	var keep_f := s.faction
	s.faction = s.faction + 1000
	ticks(host, 31)
	t.eq(String(deals.quest(q2["id"])["state"]), "lapsed", "the town changed hands: the quest lapses")
	s.faction = keep_f
	# saved with the world and the players, and survives a reload
	var w: Dictionary = JSON.parse_string(JSON.stringify(deals.save_world()))
	var pl: Dictionary = JSON.parse_string(JSON.stringify(deals.save_player(p)))
	var d2 := DealsSystem.new()
	d2.load_world(w)
	t.eq(d2.quests.keys().size(), deals.quests.keys().size(), "quests survive a reload")
	for qid: String in deals.quests:
		t.eq(JSON.stringify(d2.quests[qid]), JSON.stringify(DealsCodec.quest(JSON.parse_string(JSON.stringify(deals.quests[qid])))), "quest %s the same" % qid)
		break
	d2.load_player(p, pl)
	t.eq((d2.logs[p.id] as Dictionary).keys().size(), (deals.logs[p.id] as Dictionary).keys().size(), "the log survives")
	t.eq(int((d2.offers.get(sid, {}) as Dictionary).get("day", -1)), Deals.day(host.sim), "today's offers survive (the same all day)")
	t.check(rules != null, "rules present")

# --- 4. patrons --------------------------------------------------------------------------------

func _patron(t: TestLog) -> void:
	var r := rig()
	var host: WorldHost = r["host"]
	var deals: DealsSystem = r["deals"]
	var life: LifeSystem = r["life"]
	var sid := town_of(host)
	var s: SimSettlement = host.sim.settlements[sid]
	var p := put(host, "eve", LifeTown.site_pos(host, sid) + Vector2(0, 3))
	ticks(host, 70)
	var f := str(s.faction)
	t.eq(deals.patron_tier(p.id, f), 0, "a stranger has no patron")
	t.eq(DealsPatron.tier(24), 0, "tier 0 below 25")
	t.eq(DealsPatron.tier(50), 2, "tier 2 at 50")
	var keeper := person(life, sid, "keeper")
	if keeper == null:
		t.check(false, "a keeper")
		return
	beside(host, p, keeper)
	deals.talk(p, keeper.id)
	t.check(not deals.options(p, deals.talks[p.id]).any(func(o: Dictionary) -> bool: return o["id"] == "patron"), "no patronage yet")
	life.add_standing(p.id, f, 30, "test")
	t.eq(deals.patron_tier(p.id, f), 1, "standing 30: tier 1")
	t.check(deals.options(p, deals.talks[p.id]).any(func(o: Dictionary) -> bool: return o["id"] == "patron"), "the keeper takes you on")
	var before := p.character.inventory.filled().size()
	t.eq(deals.choose(p, "patron"), "", "asks the patron")
	t.eq(int(deals.gifts[p.id][f]), 1, "the tier-1 gift is given")
	t.check(p.character.inventory.filled().size() > before, "a made-to-order piece")
	deals.choose(p, "patron")
	t.eq(int(deals.gifts[p.id][f]), 1, "once")
	if DealsShop.has_building(host.world, sid, "tavern"):
		t.eq(deals.bed_price(p, sid), 0, "a patron sleeps free")
	life.add_standing(p.id, f, 50, "test")
	deals.choose(p, "patron")
	t.eq(int(deals.gifts[p.id][f]), 3, "tiers 2 and 3: magic items")
	var magic := p.character.inventory.slots.filter(func(it: Dictionary) -> bool: return it.has("magic") and it.get("base") != "potions-of-healing")
	t.check(magic.size() >= 2, "two SRD magic items (%s)" % ", ".join(magic.map(func(it: Dictionary) -> String: return String(it["magic"]))))
	life.add_standing(p.id, f, -100, "test")
	t.eq(deals.patron_tier(p.id, f), 0, "falling out of favour suspends it")
	ticks(host, 31)
	t.check(true, "patron mirror sent")

# --- 5. looking never changes history ----------------------------------------------------------

func _wander(t: TestLog) -> void:
	var ra := rig(true)
	var rb := rig(false)
	var ha: WorldHost = ra["host"]
	var hb: WorldHost = rb["host"]
	var deals: DealsSystem = ra["deals"]
	var la: LifeSystem = ra["life"]
	var p := put(ha, "wanderer", ha.spawn)
	for fid: int in ha.sim.factions:
		la.add_standing(p.id, str(fid), 100, "a friend to all")
	var towns: Array = WorldSim._sorted_keys(ha.sim.settlements)
	var talked := 0
	var browsed := 0
	var offered := 0
	for step in 28:
		var sid: int = towns[step % towns.size()]
		if ha.sim.settlements.has(sid):
			p.body.pos = LifeTown.site_pos(ha, sid) + Vector2(0, 3)
			TileCollision.depenetrate(ha.world, p.body)
		ticks(ha, 65)
		ticks(hb, 65)
		for x: HostEntity in la.actors_at(sid):
			if not bool(x.get_meta("talk", false)):
				continue
			beside(ha, p, x)
			if deals.talk(p, x.id) != "":
				continue
			talked += 1
			for o: Dictionary in deals.options(p, deals.talks[p.id]):
				if String(o["id"]) in ["rumours", "shop", "smith", "quests"]:
					deals.choose(p, String(o["id"]))
					browsed += 1
			offered += deals.offers_at(sid).size()
		advance(ha, 6.0)
		advance(hb, 6.0)
	print("  wanderer: talked %d, browsed %d, offers seen %d, rumours heard %d" % [talked, browsed, offered, (deals.known[p.id] as Array).size()])
	t.check(talked > 10 and browsed > 10, "the wanderer talked %d times and browsed %d (offers seen %d)" % [talked, browsed, offered])
	t.eq(ha.sim.t, hb.sim.t, "a game week on both")
	t.eq(ha.sim.rng.state, hb.sim.rng.state, "talk, rumours, shops and offers never touched the sim's generator")
	t.check(ha.sim.to_dict().hash() == hb.sim.to_dict().hash(), "the sims are identical after a week of dealing without buying")
