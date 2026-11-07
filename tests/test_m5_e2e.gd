## M5 end to end: scarcity on a real world of five biomes (dev seed 15). Two players arrive in the
## meadow town at the game's spawn, where salt is dear because the land gives none, and buy a sack
## to prove it. They walk the road over the range to the desert town beyond it, on foot through
## the pass; salt is cheap there, and they buy a load. The town's caravan loads salt for the
## meadow; they take its escort, walk with it back into the pass, and raiders waiting at the road's
## middle fall on it there, in real time, on both clients. They beat them off, the caravan comes
## down into the meadow, the town's salt stock and books move by what it carried, and the players
## sell their own load at a profit. Cheats set the scene only: the caravan's load and the raiders.
## The dice are not fixed: each run prints its seed, and E2E_SEED=n replays that story.
extends "res://tests/test_m4_e2e.gd"

const GOOD := "salt"
const BASE := "trade:salt"

## The range under the road, the road's indices over its pass, the rows of the pass by column.
var rg := {}
var over := Vector2i(-1, -1)
var pass_rows := {}
var paid_n := 0
var bought_n := 0

func run(t_: TestLog) -> void:
	t = t_
	t0 = Time.get_ticks_msec()
	var given := OS.get_environment("E2E_SEED")
	_dice = int(given) if given != "" else randi()
	print("  dice seed %d" % _dice)
	var w := WorldGen.generate_named("dev", 15)
	rig = Rig.new(w, 0.03)
	rig.host.spawn = load("res://game/main.gd").spawn_for(w, rig.host.spawn)
	Systems.install_host(rig.host)
	_quiet_host()
	_age(30)
	_find_towns()
	t.check(T >= 0 and N >= 0 and road >= 0 and over.x >= 0, "two towns with a pass between them (%d, %d, route %d, over cells %s)" % [T, N, road, over])
	if T < 0 or N < 0 or road < 0 or over.x < 0:
		return
	t.eq(BiomeIds.strip(w.meta).size(), 5, "a world of five biomes")
	_join()
	if not _ready():
		t.check(false, "both players joined with every system")
		return
	_strong()
	for f: String in ["_arrive", "_dear_here", "_over_the_pass", "_cheap_there", "_the_salt_train", "_sell_at_home", "_agree"]:
		var ms := Time.get_ticks_msec()
		var before := t.failures.size()
		call(f)
		print("  %s: %d ms, sim day %d, %s" % [f, Time.get_ticks_msec() - ms, Deals.day(rig.host.sim), "ok" if t.failures.size() == before else "%d failed" % (t.failures.size() - before)])
	print("  total %d ms" % (Time.get_ticks_msec() - t0))

## The spawn town, and its neighbour over a pass.
func _find_towns() -> void:
	var sim := rig.host.sim
	var bd := INF
	for sid: int in WorldSim._sorted_keys(sim.settlements):
		var s: SimSettlement = sim.settlements[sid]
		if s.band == "surface" and absf(s.x - rig.host.spawn.x) < bd:
			bd = absf(s.x - rig.host.spawn.x)
			T = sid
	for r: Dictionary in sim.routes:
		var other := int(r.b) if int(r.a) == T else (int(r.a) if int(r.b) == T else -1)
		if String(r.get("kind", "")) == "road" and "pass" in r.get("crossings", []) and sim.settlements.has(other):
			N = other
			road = int(r.id)
			cells = Places.route_path(rig.host.world, road)
			if int(r.a) != T:
				cells.reverse()
	if road < 0:
		return
	for row: Dictionary in rig.host.world.meta["barriers"]["ranges"]:
		for q: Array in row["pass"]["path"]:
			pass_rows[int(q[0])] = int(q[1])
		rg = row
	for j in cells.size():
		if pass_rows.get(cells[j].x, -9999) == cells[j].y:
			if over.x < 0:
				over.x = j
			over.y = j
	print("    %s (%s) to %s (%s): %d cells, over the pass at %s, %.0f caravan hours" % [town(T).name, sim.site_by_id[T].biome, town(N).name, sim.site_by_id[N].biome, cells.size(), over, sim.leg_hours("caravan", road)])

## Open the merchant's shop at a town; the shelf row of a base, or {}.
func _shop(i: int, sid: int, base: String) -> Dictionary:
	t.eq(talk_to(i, "merchant", sid), "", "a merchant at %s" % town(sid).name)
	choose(i, "shop")
	rig.until(func() -> bool: return dc(i).shopping(), 2.0)
	t.check(dc(i).shopping(), "the shop at %s opened" % town(sid).name)
	for l: Dictionary in dc(i).shop.get("listings", []):
		if String(l["item"]["base"]) == base:
			return l
	return {}

func _buy(i: int, sid: int, l: Dictionary, n: int) -> int:
	var s := town(sid)
	var inv := he(i).character.inventory
	var c0 := inv.coin
	var w0 := s.wealth
	var g0 := float(s.stock[GOOD])
	var had := inv.count_base(BASE)
	dc(i).buy(String(l["id"]), n)
	rig.until(func() -> bool: return inv.count_base(BASE) >= had + n, 2.0)
	t.eq(inv.count_base(BASE), had + n, "%d salt in the pack" % n)
	var paid := c0 - inv.coin
	t.check(paid > 0 and is_equal_approx(s.wealth, w0 + paid), "%d coin paid; %s's purse rose by as much (%.1f)" % [paid, s.name, s.wealth - w0])
	t.check(is_equal_approx(float(s.stock[GOOD]), g0 - n), "the salt came out of %s's stock (%.1f -> %.1f)" % [s.name, g0, s.stock[GOOD]])
	return paid

# --- salt is dear where they stand ----------------------------------------------------------------

var each_t := 0

func _dear_here() -> void:
	var s := town(T)
	var n := town(N)
	t.check(SimEconomy.price(n, GOOD) * 1.5 < SimEconomy.price(s, GOOD), "salt is scarce here and plentiful over the range (%.2f against %.2f)" % [SimEconomy.price(s, GOOD), SimEconomy.price(n, GOOD)])
	t.eq(float(s.land.get(GOOD, 0.0)), 0.0, "the land here gives none")
	t.check(float(n.land.get(GOOD, 0.0)) > 1.0, "the land there is full of it")
	var l := _shop(0, T, BASE)
	t.check(not l.is_empty() and int(l["n"]) > 0, "salt on the shelf here")
	if not l.is_empty():
		each_t = int(l["price"])
		_buy(0, T, l, 1)
		paid_n = 0
	dc(0).leave()
	rig.run(0.3)

# --- the road over the range, on foot ---------------------------------------------------------------

func _over_the_pass() -> void:
	var h0 := rig.host.world.content_hash()
	var st := {"on": 0, "off": 0}
	_near_k = [-1, -1]
	var took := walk(cells.size() - 1, 300.0, [0, 1], func() -> void:
		var b: Body = he(0).body
		var x := floori(b.pos.x)
		if pass_rows.has(x) and b.on_floor:
			st["on" if absf(b.pos.y - int(pass_rows[x])) <= 3.0 else "off"] = int(st["on" if absf(b.pos.y - int(pass_rows[x])) <= 3.0 else "off"]) + 1)
	print("    walked %d cells over the range in %.1f s (ann at %s), %d on the pass, %d off it" % [cells.size(), took, rig.cw(0).body.pos, st["on"], st["off"]])
	t.check(took >= 0.0, "both walked the road over the range (%.0f s)" % took)
	t.check(int(st["on"]) > (over.y - over.x) / 4 and int(st["off"]) == 0, "by the pass (%d steps on it, %d off it)" % [st["on"], st["off"]])
	t.eq(rig.host.world.content_hash(), h0, "and nobody dug")
	_into_town(N)
	rig.run(1.5)

# --- salt is cheap across it ------------------------------------------------------------------------

func _cheap_there() -> void:
	var l := _shop(0, N, BASE)
	t.check(not l.is_empty() and int(l["n"]) >= 12, "salt on the shelf here too (%s)" % [l.get("n", 0)])
	if not l.is_empty():
		t.check(int(l["price"]) * 3 < each_t * 2, "at a good deal less (%d a sack against %d)" % [l["price"], each_t])
		bought_n = mini(12, int(l["n"]))
		paid_n = _buy(0, N, l, bought_n)
	dc(0).leave()
	rig.run(0.3)

# --- the salt train -----------------------------------------------------------------------------------

## Raiders waiting at the road's middle (a route raid stops there), out of a third town.
func _waylay() -> SimParty:
	var home := -1
	for sid: int in WorldSim._sorted_keys(sim().settlements):
		var s := town(sid)
		if sid != T and sid != N and s.band == "surface" and (home < 0 or s.faction != town(T).faction):
			home = sid
	var s := town(home)
	var c := SimData.culture(s.culture)
	var r := sim().new_party("raid", s.faction, s.culture, home, SimData.allocate(c.raiders, 4))
	r.plan = {"mode": "route", "motive": "plunder", "leg": "out"}
	r.target = road
	r.path = [T, N] as Array[int]
	r.leg = 0
	r.route = road
	r.frac = 0.45
	r.state = "travel"
	r.dest = N
	s.out_raids += 1
	return r

func _the_salt_train() -> void:
	next_day()
	var s := town(T)
	var n := town(N)
	var load_n := mini(60, floori(float(n.stock[GOOD]) * 0.5))
	var cid := life().cheat_party("caravan", N, T, 0.3)
	var cp: SimParty = sim().parties.get(cid)
	t.check(cp != null, "a caravan leaves %s for %s (scene)" % [n.name, s.name])
	if cp == null:
		return
	cp.cargo = {GOOD: load_n}
	cp.plan["good"] = GOOD
	n.stock[GOOD] = float(n.stock[GOOD]) - load_n
	t.eq(talk_to(0, "merchant", N), "", "ann talks to the merchant")
	var qid := take(0, "escort")
	dc(0).leave()
	t.check(qid != "", "the merchant wants an escort (%s)" % [offered_kinds(N)])
	if qid == "":
		return
	if talk_to(1, "merchant", N) == "":
		take(1, "escort")
		dc(1).leave()
	var at := life().road.party_pos(rig.host, cp)
	walk(cell_near(at), 60.0)
	rig.run(2.0)
	t.check(not cp.held, "the escort is beside it: it leaves")
	var raid := _waylay()
	var st := {"seen": 0, "fought": 0.0, "fight_x": -1, "frames": 0, "with": 0, "salt": float(s.stock[GOOD]), "wealth": s.wealth, "jump": 0.0, "last": Vector2.INF}
	var took := rig.until(func() -> bool:
		_tough()
		var home := String(cp.plan.get("leg", "out")) == "home"
		if not home:
			st["salt"] = float(s.stock[GOOD])
			st["wealth"] = s.wealth
		var pos := life().road.party_pos(rig.host, cp) if sim().parties.has(cid) else Vector2.INF
		if pos == Vector2.INF:
			return true
		var last: Vector2 = st["last"]
		if last != Vector2.INF and absf(cp.frac - float(st.get("frac", cp.frac))) < 0.2:
			st["jump"] = maxf(float(st["jump"]), last.distance_to(pos))
		st["last"] = pos
		st["frac"] = cp.frac
		var foes := sim().parties.has(raid.id) and life().road.actors_of(rig.host, raid.id).any(func(e: HostEntity) -> bool: return e.body.pos.distance_to(pos) < 40.0 or _near_any(e.body.pos, 40.0))
		var both := 0
		for r: ClientWorld.RemoteEntity in rig.cw(0).remotes.values():
			if String(lc(0).person(r.id).get("role", "")) == "raider":
				both |= 1
		for r: ClientWorld.RemoteEntity in rig.cw(1).remotes.values():
			if String(lc(1).person(r.id).get("role", "")) == "raider":
				both |= 2
		if foes and both == 3:
			st["seen"] = int(st["seen"]) + 1
		for i in 2:
			if foes and fight(i, raider_pick(i)):
				st["fought"] = float(st["fought"]) + rig.frame_dt * 0.5
				if int(st["fight_x"]) < 0:
					st["fight_x"] = floori(he(i).body.pos.x)
			else:
				rig.inputs[i] = _steer(i, cells, clampi(cell_near(pos) + (2 if i == 0 else -2), 0, cells.size() - 1))
		st["frames"] = int(st["frames"]) + 1
		if int(st["frames"]) % 1200 == 0:
			print("      t=%.0f caravan %s %s frozen %s %d | ann %s bob %s | raid %d %s" % [int(st["frames"]) / 60.0, pos, cp.state, cp.frozen, cp.size(), he(0).body.pos, he(1).body.pos, raid.size(), raid.state])
		if _near_any(pos, 12.0):
			st["with"] = int(st["with"]) + 1
		return home, 1200.0)
	idle()
	rig.run(1.5)
	print("    escort: %.0f s on the road, %.0f s fighting from x=%d (range %d..%d), %d frames with raiders on both clients; caravan %d people, brought %d; raid %s" % [took, st["fought"], st["fight_x"], rg["x0"], rg["x1"], st["seen"], cp.size(), int(cp.plan.get("brought", 0)), "gone" if not sim().parties.has(raid.id) else "left %d" % raid.size()])
	t.check(took >= 0.0, "the caravan reached %s (%.0f s)" % [s.name, took])
	t.check(int(st["seen"]) > 30, "both clients saw the raiders fall on it (%d frames)" % st["seen"])
	t.check(float(st["fought"]) > 1.0, "the ambush was fought (%.0f s)" % st["fought"])
	t.check(int(st["fight_x"]) >= int(rg["x0"]) - 40 and int(st["fight_x"]) <= int(rg["x1"]) + 40, "in the pass (x=%d, range %d..%d)" % [st["fight_x"], rg["x0"], rg["x1"]])
	t.check(not sim().parties.has(raid.id) or raid.size() < 4, "the raiders were beaten off")
	var got := float(s.stock[GOOD]) - float(st["salt"])
	t.check(int(cp.plan.get("brought", 0)) * 2 >= load_n, "most of the salt came through (%d of %d)" % [int(cp.plan.get("brought", 0)), load_n])
	t.check(got >= int(cp.plan.get("brought", 0)) * 0.8, "%s's salt stock grew by what it carried (%.0f, brought %d)" % [s.name, got, int(cp.plan.get("brought", 0))])
	t.check(s.wealth < float(st["wealth"]), "and the town paid for it (%.0f -> %.0f)" % [st["wealth"], s.wealth])
	t.check(float(st["jump"]) < 6.0, "the caravan never jumped on screen (at most %.1f tiles between looks)" % st["jump"])
	t.eq(String(deals().quest(qid).get("state", "")), "done", "the escort is done and paid")
	t.eq(sim().audit(), [] as Array[String], "the audit is clean")

# --- and the rest of the load sold at home ----------------------------------------------------------

func _sell_at_home() -> void:
	var s := town(T)
	_into_town(T)
	rig.run(1.0)
	_shop(0, T, BASE)
	var inv := he(0).character.inventory
	var slot := -1
	for k in inv.slots.size():
		if not inv.slots[k].is_empty() and String(inv.slots[k]["base"]) == BASE:
			slot = k
	t.check(slot >= 0, "the salt is in ann's pack")
	if slot < 0:
		return
	var n := inv.count_base(BASE)
	var w0 := s.wealth
	var g0 := float(s.stock[GOOD])
	var c0 := inv.coin
	dc(0).sell(slot, n)
	rig.until(func() -> bool: return inv.count_base(BASE) == 0, 2.0)
	var got := inv.coin - c0
	t.check(got > 0 and is_equal_approx(s.wealth, w0 - got), "sold %d salt for %d; %s paid it (%.1f)" % [n, got, s.name, w0 - s.wealth])
	t.check(is_equal_approx(float(s.stock[GOOD]), g0 + n), "the salt went into its stock (%.1f -> %.1f)" % [g0, s.stock[GOOD]])
	t.check(got > paid_n, "a profit on the trip: paid %d over the range, sold for %d here" % [paid_n, got])
	dc(0).leave()
	rig.run(0.5)
	t.eq(ic(0).coin(), inv.coin, "the client's coin matches the host")
