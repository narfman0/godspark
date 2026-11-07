## M6 end to end: a raid from below, answered. Two players over the loopback on dev seed 37 (a drow
## town with a store and a smith, the ramp and a sinkhole climbing to the surface). They stand on a
## surface road and watch raiders from below fall on a caravan, on both clients; the sim records the
## ambush as one from below and the raided town posts guards at the way the raiders used. Back in
## that town its patron's keeper offers a bounty that names the way and the city. They follow the way
## down on foot, the real controller along the planner's path, never digging, into the city. Ann pays
## the toll and trades; Bob, his purse empty, is refused, walks in anyway and the guards turn on him,
## and he fights. Ann walks back up and turns the bounty in. The books agree: the raid's goods are in
## the city's stores, the watch is set, the bounty paid, the toll in the treasury, the audit clean.
## Cheats set the scene only: the raid, the caravan and the players' strength. The dice are not fixed:
## each run prints its seed and E2E_SEED=n replays that story.
extends "res://tests/test_m4_e2e.gd"

const RB := preload("res://tests/test_raids_below.gd")

var city := -1
var way := -1
var victim_town := -1
var raid_id := -1
var cargo := {}
var qid := ""
var stock0 := {}
var wealth0 := 0.0
var walk_s := 0.0
var bounty_role := "keeper"
## Stretches (8 x 8 tiles) of the way's cells -> frames a player spent in them.
var way_cells_seen := {}

func run(t_: TestLog) -> void:
	t = t_
	t0 = Time.get_ticks_msec()
	var given := OS.get_environment("E2E_SEED")
	_dice = int(given) if given != "" else randi()
	print("  dice seed %d" % _dice)
	var w := WorldGen.generate_named("dev", 37)
	rig = Rig.new(w, 0.03)
	rig.host.spawn = load("res://game/main.gd").spawn_for(w, rig.host.spawn)
	Systems.install_host(rig.host)
	_quiet_host()
	_age(30)
	_find_city()
	t.check(city >= 0 and road >= 0 and cells.size() > 40, "a drow city with a surface road to raid (%d, route %d)" % [city, road])
	if city < 0 or road < 0:
		return
	_join()
	if not _ready():
		t.check(false, "both players joined with every system")
		return
	_strong()
	for f: String in ["_the_ambush", "_the_bounty", "_the_way_down", "_the_toll", "_the_shop", "_the_guards", "_the_way_back", "_home_again", "_agree_below"]:
		var ms := Time.get_ticks_msec()
		var before := t.failures.size()
		call(f)
		print("  %s: %d ms, sim day %d, %s" % [f, Time.get_ticks_msec() - ms, Deals.day(rig.host.sim), "ok" if t.failures.size() == before else "%d failed" % (t.failures.size() - before)])
		if t.failures.size() > before and f in ["_the_ambush", "_the_bounty", "_the_way_down"]:
			break                        # the rest of the story stands on these
	print("  total %d ms" % (Time.get_ticks_msec() - t0))

# --- the scene --------------------------------------------------------------------------------

## The drow city, and the road its raiders would go for, with a town at each end and a walk.
func _find_city() -> void:
	var s_ := sim()
	for sid: int in WorldSim._sorted_keys(s_.settlements):
		var s: SimSettlement = s_.settlements[sid]
		if s.band != "surface" and s.culture == "drow" and DealsShop.has_store(rig.host.world, sid):
			city = sid
			break
	if city < 0:
		return
	s_.settlements[city].soldiers = maxi(s_.settlements[city].soldiers, 40)
	# a world a month old has hardly any trade to weigh: give its surface roads some
	for rid: int in WorldSim._sorted_keys(s_.route_by_id):
		var rr: Dictionary = s_.route_by_id[rid]
		if int(rr.cls) == WorldSim.ROAD and s_.settlements.has(int(rr.a)) and s_.settlements.has(int(rr.b)) and not s_.route_value.has(rid):
			RB.trade(s_, rid, s_.settlements[int(rr.a)].faction, 3000.0, 8.0)
	for tg: Dictionary in SimBelow.targets(s_, s_.settlements[city], true):
		var rr: Dictionary = s_.route_by_id[int(tg["route"])]
		if s_.settlements.has(int(rr.a)) and s_.settlements.has(int(rr.b)) and Places.route_path(rig.host.world, int(tg["route"])).size() > 60 \
				and s_.settlements[int(rr.a)].band == "surface" and s_.settlements[int(rr.a)].faction != s_.settlements[city].faction:
			road = int(tg["route"])
			T = int(rr.a)
			N = int(rr.b)
			cells = Places.route_path(rig.host.world, road)
			break

# --- a raid from below, on screen ------------------------------------------------------------------

func _the_ambush() -> void:
	var s_ := sim()
	var l := life()
	var rr: Dictionary = s_.route_by_id[road]
	raid_id = l.cheat_below(city, road, "road", 0.5, 12)
	var cid := l.cheat_party("caravan", int(rr.a), int(rr.b), 0.3, 3)
	t.check(raid_id > 0 and cid > 0, "raiders from %s wait on %s, a caravan comes" % [s_.settlements[city].name, s_.route_name(road)])
	if raid_id <= 0 or cid <= 0:
		return
	var ra: SimParty = s_.parties[raid_id]
	var cv: SimParty = s_.parties[cid]
	t.eq(cv.route, road, "the caravan is on that road")
	way = SimBelow.way_of(ra)
	cv.frac = 0.40 if int(rr.a) == cv.path[cv.leg] else 0.60
	cargo = cv.cargo.duplicate()
	victim_town = cv.home
	stock0 = s_.settlements[city].stock.duplicate()
	# they watch from up the road, past the raiders and away from the caravan: near enough to see it,
	# far enough that the raiders (who fall on strangers abroad) have the caravan to go for
	var far := 0.5 + 46.0 / float(cells.size())
	if int(rr.a) != cv.path[cv.leg]:
		far = 1.0 - far
	var by := l.road.route_pos(rig.host, road, far)
	put(0, by + Vector2(0.0, 2.0))
	put(1, by + Vector2(3.0, 2.0))
	rig.run(3.0)
	var raiders := l.actors_of(raid_id)
	t.check(raiders.size() >= 6, "the raid is on screen (%d)" % raiders.size())
	var seen := [0, 0]
	for e: HostEntity in raiders:
		for i in 2:
			if rig.cw(i).remotes.has(e.id):
				seen[i] += 1
	t.check(seen[0] == raiders.size() and seen[1] == raiders.size(), "both clients have every raider (%d, %d of %d)" % [seen[0], seen[1], raiders.size()])
	var names: Array = raiders.map(func(e: HostEntity) -> String: return e.name)
	print("    the raid: %s" % [names.slice(0, 4)])
	t.check(names.all(func(n: String) -> bool: return ", " in n), "named by their people's roles")
	var chron := s_.chronicle.size()
	var took := rig.until(func() -> bool:
		for i in range(chron, s_.chronicle.size()):
			if String(s_.chronicle[i].kind) == "ambush" and bool(s_.chronicle[i].get("below", false)):
				return true
		return false, 280.0)
	var line := ""
	for i in range(chron, s_.chronicle.size()):
		if String(s_.chronicle[i].kind) == "ambush":
			line = s_.describe(s_.chronicle[i])
	print("    %s (%.0f s)" % [line, took])
	t.check(took >= 0.0, "the ambush is fought on screen and the sim records it as one from below")
	t.check(line.contains(s_.route_name(way)), "the chronicle says which way they came up (%s)" % line)
	t.check(s_.way_watch.has(way), "the raided town posts guards at that way")

# --- the bounty ----------------------------------------------------------------------------------

func _the_bounty() -> void:
	var s_ := sim()
	put(0, Vector2(Places.place(rig.host.world, victim_town)["street"][0] + 12.0, Places.place(rig.host.world, victim_town)["street"][2]))
	put(1, he(0).body.pos + Vector2(3.0, 0.0))
	rig.run(1.0)
	_into_town_of(victim_town)
	# patron work: ann has earned her standing with this town (scene setting)
	life().add_standing(he(0).id, str(town(victim_town).faction), 60, "test")
	rig.run(0.5)
	var role := "keeper"
	if talk_to(0, role, victim_town) != "":
		role = "priest"
		t.eq(talk_to(0, role, victim_town), "", "the patron's %s" % role)
	qid = take(0, "below")
	bounty_role = role
	t.check(qid != "", "the %s of %s offers a bounty (%s)" % [role, town(victim_town).name, offered_kinds(victim_town)])
	if qid == "":
		return
	dc(0).leave()
	rig.run(0.3)
	var q := mirror(0, qid)
	var goal := String(q.get("goal", ""))
	print("    %s" % goal)
	t.check(goal.contains(s_.route_name(way)), "it names the way")
	t.check(goal.contains(s_.settlements[city].name), "and the city")
	t.check(not String(deals().quest(qid).get("state", "")).is_empty(), "the host has it")

func _into_town_of(sid: int) -> void:
	var sx: float = sim().site_by_id[sid].x
	for i in NAMES.size():
		walk_x(i, sx + i * 2.0, 40.0)

# --- on foot, down the way -----------------------------------------------------------------------

## Both players along the planner's way to `goal`, the real controller on each client. Replans a
## player the follower lost. Returns seconds taken, or -1.
func _foot(goal: Vector2, limit: float, who: Array = [0, 1]) -> float:
	var st := NavMaps.stats("medium")
	var prof := MonsterNav.profile(st, 0.0)
	var world := rig.host.world
	var f := {}
	var fails := {}
	var banned := {}
	var plan := func(i: int) -> bool:
		var nf := f[i] as NavFollow
		# a follower that gave up on an edge: round it, if the planner has a way round
		if nf.failed and nf.path != null and nf.i > 0 and nf.i < nf.path.size():
			var a: Vector2i = nf.path.nodes[nf.i - 1]
			var z: Vector2i = nf.path.nodes[nf.i]
			banned[Vector4i(a.x, a.y, z.x, z.y)] = true
		var p := DescentBot._whole(world, prof, rig.cw(i).body.pos, goal, banned).result()
		if p == null:
			banned.clear()
			p = DescentBot._whole(world, prof, rig.cw(i).body.pos, goal).result()
		if p != null:
			nf.set_path(p)
		return p != null
	for i: int in who:
		f[i] = NavFollow.new()
		fails[i] = 0
		if not plan.call(i):
			t.check(false, "%s has a way to %s" % [NAMES[i], goal])
			return -1.0
	var gn := MonsterNav.node_of(prof, goal)
	var dt := rig.frame_dt
	var took := rig.until(func() -> bool:
		var done := true
		for i: int in who:
			var b: Body = rig.cw(i).body
			var here := MonsterNav.node_of(prof, b.pos)
			if absi(here.x - gn.x) <= 3 and absi(here.y - gn.y) <= 2 and (b.on_floor or b.on_stairs or b.climbing):
				rig.inputs[i] = PlayerInput.new()
				continue
			done = false
			var cell := Vector2i(floori(b.pos.x) >> 3, floori(b.pos.y) >> 3)
			if way_cells_seen.has(cell):
				way_cells_seen[cell] = int(way_cells_seen[cell]) + 1
			var inp := (f[i] as NavFollow).input(world, b, dt, 2.0)
			if inp == null:
				inp = PlayerInput.new()
				if (f[i] as NavFollow).failed or b.on_floor or b.climbing:
					fails[i] = int(fails[i]) + 1
					if int(fails[i]) <= 60:
						plan.call(i)
			rig.inputs[i] = inp
		return done, limit)
	idle()
	print("    %.0f s on foot to %s, %s replans, ended at %s" % [took, goal, fails.values(), who.map(func(i: int) -> Vector2: return rig.cw(i).body.pos)])
	return took

func _the_way_down() -> void:
	var s_ := sim()
	var h0 := rig.host.world.content_hash()
	var mouth := life().below.mouth(rig.host, way)
	t.check(mouth != Vector2.INF, "the way has a mouth (%s)" % mouth)
	var r: Dictionary = s_.route_by_id[way]
	var pts: Array = [mouth]
	if r.has("bottom"):
		pts.append(Vector2(float(r["bottom"][0]) + 0.5, float(r["bottom"][1])))
	var place := Places.place(rig.host.world, city)
	var st: Array = place["street"]
	pts.append(Vector2((float(st[0]) + float(st[1])) * 0.5, float(st[2])))
	way_cells_seen.clear()
	for c: Vector2i in life().below.way_cells(rig.host, way):
		way_cells_seen[Vector2i(c.x >> 3, c.y >> 3)] = 0
	for p: Vector2 in pts:
		var took := _foot(p, 500.0)
		t.check(took >= 0.0, "both reached %s on foot (%.0f s)" % [p, took])
		if took < 0.0:
			return
		walk_s += took
	var walked := way_cells_seen.values().filter(func(n: int) -> bool: return n > 0).size()
	print("    the way (%s): %d of %d stretches of it walked" % [SimBelow.way_kind(s_, way), walked, way_cells_seen.size()])
	t.check(walked * 2 >= way_cells_seen.size(), "they went by the way the bounty named (%d of %d stretches)" % [walked, way_cells_seen.size()])
	t.eq(rig.host.world.content_hash(), h0, "and nobody dug")
	t.check(he(0).body.pos.y < 400.0, "they are deep below (row %.0f)" % he(0).body.pos.y)
	rig.run(1.5)

# --- the gate -------------------------------------------------------------------------------------

func _the_toll() -> void:
	var c := town(city)
	wealth0 = c.wealth
	var due := life().toll_due(he(0), city)
	t.check(due > 0, "the city wants a toll of ann (%d)" % due)
	t.eq(talk_to(0, "guard", city), "", "ann finds a guard")
	t.check(has_option(0, "toll"), "who asks it")
	var coin := he(0).character.inventory.coin
	choose(0, "toll")
	rig.until(func() -> bool: return he(0).character.inventory.coin < coin, 3.0)
	t.eq(coin - he(0).character.inventory.coin, due, "she pays it")
	t.check(is_equal_approx(c.wealth, wealth0 + due), "into the city's treasury")
	t.eq(life().toll_due(he(0), city), 0, "and owes no more")
	dc(0).leave()
	rig.run(0.3)
	# Bob has nothing left: the same guard, and no way to pay
	he(1).character.inventory.coin = 0
	he(1).character.inventory.changed[-1] = true
	rig.run(0.3)
	t.eq(talk_to(1, "guard", city), "", "bob finds a guard")
	var rc0 := deals().pay_toll(he(1), false)
	t.eq(rc0, "coin", "and cannot pay")
	t.check(life().toll_due(he(1), city) > 0, "so he still owes it")
	dc(1).leave()
	rig.run(0.3)

func _the_shop() -> void:
	var c := town(city)
	t.eq(talk_to(0, "merchant", city), "", "ann finds a merchant in %s" % c.name)
	choose(0, "shop")
	rig.until(func() -> bool: return dc(0).shopping(), 2.0)
	t.check(dc(0).shopping(), "the shop opened")
	var ls: Array = dc(0).shop.get("listings", [])
	t.check(not ls.is_empty(), "with goods")
	if ls.is_empty():
		return
	var l: Dictionary = ls[0]
	var w0 := c.wealth
	var coin := he(0).character.inventory.coin
	dc(0).buy(String(l["id"]), 1)
	rig.until(func() -> bool: return he(0).character.inventory.coin < coin, 2.0)
	var paid := coin - he(0).character.inventory.coin
	t.check(paid > 0 and is_equal_approx(c.wealth, w0 + paid), "she buys %s for %d: the purse rose by as much (%.1f)" % [l["item"].get("base", "?"), paid, c.wealth - w0])
	dc(0).leave()
	rig.run(0.3)

## Bob past the gate unpaid: the grace runs out, the city's people turn on him, and he fights.
func _the_guards() -> void:
	var c := town(city)
	var soldiers0 := c.soldiers
	var deaths0 := int(sim().stats.get("real_deaths", 0))
	var bob := he(1)
	var standing0 := life().standing(bob.id, str(c.faction))
	var span := life().town_span(city)
	var mid := (span.x + span.y) * 0.5
	walk_x(1, mid, 30.0)
	t.check(life().inside_gate(city, bob.body.pos), "bob stands past the gate")
	var foe := func() -> HostEntity:
		var best: HostEntity = null
		var bd := INF
		for e: HostEntity in _townsfolk():
			var d := e.body.pos.distance_to(bob.body.pos) + (0.0 if _role(e) == "guard" else 1000.0)
			if life().stance(bob, e) == Life.HOSTILE and d < bd:
				bd = d
				best = e
		return best
	t.check(foe.call() == null, "the street lets him be at first: he has a little while to find a guard")
	var turned := rig.until(func() -> bool: return foe.call() != null, 40.0)
	t.check(turned >= 5.0, "his grace runs out and the town turns on him (%.0f s)" % turned)
	var g: HostEntity = foe.call()
	t.check(g != null and _role(g) == "guard", "a guard comes for him (%s)" % (g.name if g != null else "nobody"))
	if g == null:
		return
	var id := g.id
	var took := rig.until(func() -> bool:
		fight(1, func(r: ClientWorld.RemoteEntity) -> bool: return r.id == id)
		return rig.host.entity(id) == null or rig.host.entity(id).combatant.stats.current_hp <= 0, 90.0)
	idle()
	t.check(took >= 0.0, "he cuts %s down in the street (%.0f s)" % [g.name, took])
	rig.run(1.0)
	# (the sim's own hours move a garrison too: the kill is in its books as a death in real time)
	t.check(c.soldiers < soldiers0 and int(sim().stats.get("real_deaths", 0)) > deaths0, "and the sim has the guard dead: the garrison %d -> %d" % [soldiers0, c.soldiers])
	t.check(life().standing(bob.id, str(c.faction)) < standing0, "his standing with the city fell (%d -> %d)" % [standing0, life().standing(bob.id, str(c.faction))])

func _role(e: HostEntity) -> String:
	return String((e.get_meta("sim", {}) as Dictionary).get("role", ""))

## The people of the city Life has on the street.
func _townsfolk() -> Array:
	var out: Array = []
	for e: HostEntity in rig.host.entities.values():
		var info: Variant = e.get_meta("sim", {})
		if info is Dictionary and String((info as Dictionary).get("kind", "")) == "settlement" and int((info as Dictionary).get("id", -1)) == city:
			out.append(e)
	return out

# --- home ------------------------------------------------------------------------------------------

func _the_way_back() -> void:
	t.eq(String(deals().quest(qid).get("state", "")), "ready", "standing in the city, the bounty is ready")
	var r0 := mirror(0, qid)
	t.eq(String(r0.get("state", "")), "ready", "ann's log says so")
	var place := Places.place(rig.host.world, victim_town)
	var st: Array = place["street"]
	var took := _foot(Vector2((float(st[0]) + float(st[1])) * 0.5, float(st[2])), 500.0, [0])
	t.check(took >= 0.0, "ann walks back up to %s (%.0f s)" % [town(victim_town).name, took])

func _home_again() -> void:
	var inv := he(0).character.inventory
	var coin := inv.coin
	var role := bounty_role
	t.eq(talk_to(0, role, victim_town), "", "ann goes back to the %s" % role)
	t.check(has_option(0, "turn_in:" + qid), "who takes the word")
	choose(0, "turn_in:" + qid)
	rig.until(func() -> bool: return inv.coin > coin, 3.0)
	t.check(inv.coin > coin, "the bounty is paid (%d)" % (inv.coin - coin))
	t.eq(String(deals().quest(qid).get("state", "")), "done", "and it is done")
	dc(0).leave()
	rig.run(0.3)

func _agree_below() -> void:
	var s_ := sim()
	# let the raid go home: the sim's own days
	put(1, Vector2(float(s_.site_by_id[victim_town].x), float(s_.site_by_id[victim_town].y)))
	rig.run(1.0)
	var guard := 0
	while s_.parties.has(raid_id) and guard < 40:
		_age(1)
		guard += 1
	t.check(not s_.parties.has(raid_id), "the raid is home or gone")
	var home := int(s_.stats.get("below_goods_home", 0))
	var taken := int(s_.stats.get("below_taken", 0))
	print("    raiders took %d, carried home %d, chronicle: %s" % [taken, home, _home_line()])
	if taken > 0:
		t.check(home > 0 and home <= taken, "the city's stores received what they carried (%d of %d)" % [home, taken])
	t.check(int(s_.stats.get("way_watches", 0)) >= 1, "the watch is in the sim's books")
	t.eq(s_.audit(), [] as Array[String], "the audit is clean")
	for i in 2:
		t.eq(ic(i).coin(), he(i).character.inventory.coin, "%s's client has %s coin right" % [NAMES[i], "her" if i == 0 else "his"])
	t.eq(String(mirror(0, qid).get("state", "done")), "done", "ann's log has the bounty done")
	put(1, he(0).body.pos + Vector2(2.0, 0.0))
	rig.run(3.0)
	t.check(rig.in_sync(0) and rig.in_sync(1), "both clients hold the same tiles as the host")

func _home_line() -> String:
	var s_ := sim()
	for i in range(s_.chronicle.size() - 1, -1, -1):
		if String(s_.chronicle[i].kind) == "raid_home":
			return s_.describe(s_.chronicle[i])
	return "(none)"
