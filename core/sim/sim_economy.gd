## Food, goods, coin and people: production, consumption, prices, population, trade
## caravans, migration and the founding of daughter settlements.
class_name SimEconomy
extends RefCounted

## Food per day a size-1 site of a 1.0 biome yields at full working capacity.
const FOOD_CAP := 70.0
## Food one person eats per day (goods.json food.need / 365, rounded to the sim's 360-day year).
const EAT := 0.1
## Food per day one farm worker produces on unworked land (diminishing toward the cap).
const WORKER_FOOD := 0.38
## Season multipliers on surface farming: spring, summer, autumn (harvest), winter.
const SEASON_F := [0.75, 1.1, 1.55, 0.6]
## Food surplus (over an ordinary year's eating) at which births reach their full rate.
const GROW_MARGIN := 0.3
## Per year: births at full food security, natural deaths.
const BIRTH := 0.048
const DEATH := 0.022
## Share of unfed people who die per econ tick.
const STARVE := 0.025
## Dependants who come of age per year.
const AGING := 1.0 / 14.0
## Coin per worker per day, coin per soldier per day, wealth spent per year.
const INCOME := 0.012
const UPKEEP := 0.05
const WEALTH_DECAY := 0.06
## Below this population a settlement is abandoned.
const ABANDON_POP := 12
## Caravan: minimum expected profit in coin, cost per wagon per travel day.
const MIN_PROFIT := 25.0
const WAGON_DAY_COST := 5.0
const SHOCK_DAYS := 360
## Roughly how many people one unit of daily food capacity feeds at equilibrium.
const EQ_PER_CAP := 6.5
## Local price of a good at its stock target, as a share of base: where the land gives none,
## and where it gives a full 1.0 share (data/sim/biomes.json). Goods no land gives sit at 1.
const LAND_PRICE_NONE := 1.3
const LAND_PRICE_FULL := 0.7
## A town keeps this many stock targets of a good before hands go elsewhere, plus this many for
## each 1.0 of biome share: what the land yields, it stockpiles to sell.
const KEEP_BASE := 2.0
const KEEP_LAND := 3.0
## A town with this much coin a head buys food up to this many stock targets, enough that its
## people grow past what its own land feeds (see grow_f in _tick_settlement).
const RICH_FOOD_COIN := 3.0
const RICH_FOOD_STOCK := 1.9
## What a unit of game feeds, once the granary is empty.
const GAME_FOOD := 3.0
## Yield of a field with no water to spare, as a share of a watered one.
const DRY_FIELD := 0.55
## Food spoils at this share of its rate with salt to hand, and at this share with none.
const SPOIL_SALTED := 0.5
const SPOIL_UNSALTED := 1.5
## Natural deaths with reagents to hand, and with none, as a share of DEATH.
const DEATH_TENDED := 0.85
const DEATH_UNTENDED := 1.2
## Stone stock under this share of target: walls in disrepair, a step worse (SimConflict.wall_ac).
const STONE_LOW := 0.25

## A good's stock target: what a year's need asks to keep, times what the people want of it
## (cultures.json wants).
static func target(s: SimSettlement, g: String) -> float:
	var d: Dictionary = SimData.goods[g]
	return (s.workers + s.dependants + s.soldiers) * float(d.need) * float(d.target_years) * SimData.want_f(s.culture, g)

## A good's price: its base, moved by what the land here gives and by the stock against target.
static func price(s: SimSettlement, g: String) -> float:
	return price_at(s, g, target(s, g))

## price() for a target already worked out (the hot loops ask for both).
static func price_at(s: SimSettlement, g: String, tg: float) -> float:
	var d: Dictionary = SimData.goods[g]
	if tg <= 0.0:
		return float(d.base)
	var st: float = s.stock.get(g, 0.0)
	return float(d.base) * land_price(s, g) * clampf(pow(tg / maxf(st, 0.05 * tg), 0.8), 0.25, 6.0)

## What the land does to a good's price here (1 for goods no land gives, or a site with no row).
static func land_price(s: SimSettlement, g: String) -> float:
	if not s.land.has(g):
		return 1.0
	return lerpf(LAND_PRICE_NONE, LAND_PRICE_FULL, clampf(float(s.land[g]), 0.0, 1.0))

## The stock of a good past which a town puts no more hands on it.
static func stock_cap(s: SimSettlement, g: String) -> float:
	return target(s, g) * (KEEP_BASE + KEEP_LAND * float(s.land.get(g, 0.0)))

## Food reserve as a fraction of one season's eating.
static func security(s: SimSettlement) -> float:
	var need := s.pop() * EAT * 90.0
	return s.stock.get("food", 0.0) / need if need > 0.0 else 1.0

static func _round(sim: WorldSim, x: float) -> int:
	if x <= 0.0:
		return 0
	return int(floor(x + sim.rng.randf()))

# ── Econ tick ────────────────────────────────────────────────────────────────

static func tick(sim: WorldSim) -> void:
	var abandon: Array = []
	for sid in WorldSim._sorted_keys(sim.settlements):
		var s: SimSettlement = sim.settlements[sid]
		_tick_settlement(sim, s, WorldSim.ECON_DAYS)
		if s.pop() < ABANDON_POP:
			abandon.append(s)
	for s in abandon:
		abandon_settlement(sim, s, "dwindled")
	for rid in sim.route_threat.keys():
		sim.route_threat[rid] *= 0.93
		if sim.route_threat[rid] < 0.05:
			sim.route_threat.erase(rid)
	for rid in sim.route_traffic.keys():
		var tr: Dictionary = sim.route_traffic[rid]
		for f in tr.keys():
			tr[f] *= 0.9
			if tr[f] < 0.05:
				tr.erase(f)
		if tr.is_empty():
			sim.route_traffic.erase(rid)
	for rid in sim.route_value.keys():
		var rv: Dictionary = sim.route_value[rid]
		for f in rv.keys():
			rv[f] *= 0.9
			if rv[f] < 1.0:
				rv.erase(f)
		if rv.is_empty():
			sim.route_value.erase(rid)

static func _tick_settlement(sim: WorldSim, s: SimSettlement, days: int) -> void:
	var c := SimData.culture(s.culture)
	var pop := s.pop()
	if pop <= 0:
		return
	var dt_year := float(days) / WorldSim.YEAR_DAYS
	var sec := security(s)
	# Labour: more hands go to the fields when food is short.
	var farm_share := clampf(0.66 + (0.7 - sec) * 0.25, 0.6, 0.85)
	var farm_l := s.workers * farm_share
	var craft_l := s.workers - farm_l
	var tools_ok := clampf(s.stock.tools / maxf(target(s, "tools") * 0.5, 1.0), 0.0, 1.0)
	var toolf := 1.0 + 0.25 * tools_ok
	var season_f: float = SEASON_F[sim.season_index()] if s.seasonal else 1.0
	# Crafts: labour follows the land's strengths; a quarter makes tools and fine goods.
	var raw_l := craft_l * 0.75
	var raw_cap := 0.0
	for g in SimData.raw_goods:
		raw_cap += float(s.cap.get(g, 0.0)) + 0.01
	var raw_day := {}
	var craft: float = float(c.craft)
	for g in SimData.raw_goods:
		var cap_g: float = float(s.cap.get(g, 0.0))
		var cg: float = cap_g + 0.01
		var l := raw_l * cg / raw_cap
		# Full woodpiles and ore heaps send hands back to the fields.
		var want := clampf(2.0 - s.stock[g] / maxf(stock_cap(s, g), 1.0), 0.0, 1.0)
		farm_l += l * (1.0 - want)
		var d: Dictionary = SimData.goods[g]
		var skill: float = craft if d.get("craft", false) else 1.0
		raw_day[g] = cap_g * (1.0 - exp(-l * want * float(d.labour) * skill * toolf / cg))
	# Wells give what they give, up to twice what a town keeps.
	s.stock.water = minf(s.stock.water + s.cap.water * days, maxf(s.stock.water, stock_cap(s, "water") * 2.0))
	var water_ok := clampf(s.stock.water / maxf(target(s, "water") * 0.5, 1.0), 0.0, 1.0)
	var food_day := 0.0
	var food_norm := 0.0   # an ordinary day's yield, no season or weather
	var cf: float = s.cap.food
	if cf > 0.0:
		food_norm = cf * (1.0 - exp(-farm_l * WORKER_FOOD * toolf / cf)) * lerpf(DRY_FIELD, 1.0, water_ok)
		food_day = food_norm * season_f * s.weather
	if s.besieged_by >= 0:
		food_day *= 0.3
	var make_l := craft_l * 0.25
	var stock: Dictionary = s.stock
	stock.food += food_day * days
	for g in SimData.raw_goods:
		stock[g] += float(raw_day[g]) * days
	var tools_made := minf(make_l * 0.7 * 0.015 * float(c.craft) * days, minf(stock.ore, stock.timber))
	stock.ore -= tools_made
	stock.timber -= tools_made
	stock.tools += tools_made
	# Fine goods are cut from crystal first, then worked from ore.
	var crystal: float = stock.get("crystal", 0.0)
	var lux_made := minf(make_l * 0.3 * 0.012 * float(c.luxury) * days, stock.ore * 2.0 + crystal * 2.0)
	var from_crystal := minf(lux_made * 0.5, crystal)
	if stock.has("crystal"):
		stock.crystal = crystal - from_crystal
	stock.ore = maxf(stock.ore - (lux_made * 0.5 - from_crystal), 0.0)
	stock.luxuries += lux_made
	# Eating.
	var need := pop * EAT * days
	var fed := 1.0
	if stock.food < need and stock.game > 0.0:
		var eaten := minf(stock.game, (need - stock.food) / GAME_FOOD)
		stock.game -= eaten
		stock.food += eaten * GAME_FOOD
	if stock.food >= need:
		stock.food -= need
	else:
		fed = stock.food / need
		stock.food = 0.0
	# Other needs and wear. ok[g]: how much of this tick's need for g was there.
	var ok := {}
	for g in SimData.used_goods:
		var used := pop * float(SimData.goods[g].use) * dt_year
		ok[g] = minf(stock[g] / maxf(used, 0.001), 1.0)
		stock[g] = maxf(stock[g] - used, 0.0)
	var timber_ok: float = ok.timber
	var lux_ok: float = ok.luxuries
	for g in SimData.good_names:
		var spoil := float(SimData.goods[g].spoil)
		if g == "food":
			spoil *= lerpf(SPOIL_UNSALTED, SPOIL_SALTED, ok.salt)
		stock[g] = maxf(float(stock[g]) * (1.0 - spoil * dt_year), 0.0)
	# Coin.
	s.wealth += s.workers * INCOME * days * (0.6 + 0.4 * s.morale)
	s.wealth -= s.soldiers * UPKEEP * days
	s.wealth -= s.wealth * WEALTH_DECAY * dt_year
	if s.wealth < 0.0:
		s.wealth = 0.0
		var desert := _round(sim, s.soldiers * 0.05)
		s.soldiers -= desert
		s.workers += desert
	# People.
	sec = security(s)
	# Families grow when the land yields comfortably more than the town eats in an ordinary
	# year, or when the granary is full (bought or plundered food counts too).
	var ratio := food_norm / maxf(pop * EAT, 0.001)
	var grow_f := clampf(maxf((ratio - 1.0) / GROW_MARGIN, (sec - 1.0) / 1.5), 0.0, 1.0)
	var births := pop * BIRTH * dt_year * (0.2 + 0.8 * grow_f) * fed * (0.6 + 0.4 * timber_ok) * (0.8 + 0.4 * s.morale)
	var deaths := pop * DEATH * dt_year * lerpf(DEATH_UNTENDED, DEATH_TENDED, ok.reagents)
	var starving := pop * (1.0 - fed) * STARVE
	var nb := _round(sim, births)
	var nd := _round(sim, deaths)
	var ns := _round(sim, starving)
	s.dependants += nb
	_kill(sim, s, nd, false)
	_kill(sim, s, ns, true)
	sim.stats_add("born", nb)
	sim.stats_add("died", nd)
	sim.stats_add("starved", ns)
	if ns > 0:
		sim.stats_add("starved_" + s.culture, ns)
	var grown := _round(sim, s.dependants * AGING * dt_year)
	grown = mini(grown, s.dependants)
	s.dependants -= grown
	s.workers += grown
	# Garrison.
	var at_war := false
	if sim.factions.has(s.faction):
		at_war = not sim.factions[s.faction].wars.is_empty()
	var temper := 1.0
	if sim.factions.has(s.faction):
		temper = {"raider": 1.25, "expansionist": 1.15, "trader": 0.9, "isolationist": 1.0}.get(sim.factions[s.faction].temperament, 1.0)
	var want := int(s.pop() * float(c.soldiers) * temper * (1.5 if at_war else 1.0))
	if s.wealth < s.soldiers * UPKEEP * 30.0:
		want = int(want * 0.7)
	if s.soldiers < want:
		var rec := mini(mini(want - s.soldiers, maxi(int(s.workers * 0.02), 1)), maxi(s.workers - 5, 0))
		s.soldiers += rec
		s.workers -= rec
	elif s.soldiers > want * 1.3:
		var dis := maxi(int((s.soldiers - want) * 0.2), 1)
		s.soldiers -= dis
		s.workers += dis
	# Morale.
	var raided := sim.t - s.last_raided < 90 * WorldSim.DAY_H
	var m_target := 0.45 + 0.3 * clampf(sec, 0.0, 1.0) + 0.15 * lux_ok - (0.2 if raided else 0.0) \
		- (0.1 if at_war else 0.0) - (0.25 if fed < 0.95 else 0.0) - (0.1 if s.tribute_to >= 0 else 0.0)
	s.morale = clampf(s.morale + (m_target - s.morale) * 0.15, 0.0, 1.0)
	# Hunger, famine and the food-shock record.
	var p_food := price(s, "food")
	if fed < 0.97:
		s.hungry += 1
	else:
		s.hungry = 0
		if s.shock.is_empty():
			s.price_ref = s.price_ref + (p_food - s.price_ref) * 0.02
	if s.hungry == 2 and s.shock.is_empty():
		sim.stats_add("famines", 1)
		s.shock = {"t": sim.t, "price0": s.price_ref, "maxp": p_food, "imports": 0, "migrants": 0, "raids": 0}
		sim.log_event("famine", {"site": s.name, "price_pct": int(p_food / maxf(s.price_ref, 0.01) * 100.0),
			"pop": s.pop(), "culture": s.culture})
	if not s.shock.is_empty():
		s.shock.maxp = maxf(s.shock.maxp, p_food)
		if sim.t - int(s.shock.t) >= SHOCK_DAYS * WorldSim.DAY_H:
			_close_shock(sim, s)
	# Tier changes, with a margin so a town at the line doesn't flicker.
	var p2 := s.pop()
	var nt := SimSettlement.tier_for(p2)
	if nt != s.tier:
		var up := SimSettlement.TIERS.find(nt) > SimSettlement.TIERS.find(s.tier)
		var line: int = SimSettlement.TIER_POP[maxi(SimSettlement.TIERS.find(nt), SimSettlement.TIERS.find(s.tier))]
		if (up and p2 >= line * 1.1) or (not up and p2 < line * 0.9):
			sim.log_event("tier_up" if up else "tier_down", {"site": s.name, "tier": nt, "pop": p2})
			s.tier = nt

static func _close_shock(sim: WorldSim, s: SimSettlement) -> void:
	var sh: Dictionary = s.shock
	sim.stats_add("shocks", 1)
	var rose: bool = sh.maxp >= sh.price0 * 1.5
	if rose: sim.stats_add("shock_price", 1)
	if sh.imports > 0: sim.stats_add("shock_import", 1)
	if sh.migrants > 0: sim.stats_add("shock_migr", 1)
	if sh.raids > 0: sim.stats_add("shock_raid", 1)
	if rose and (sh.imports > 0 or sh.migrants > 0 or sh.raids > 0):
		sim.stats_add("shock_any", 1)
	s.shock = {}

## Remove n people; famine takes the old and young first, ordinary deaths are spread out.
static func _kill(sim: WorldSim, s: SimSettlement, n: int, famine: bool) -> void:
	if n <= 0:
		return
	var pop := s.pop()
	n = mini(n, pop)
	var d := mini(int(round(n * float(s.dependants) / maxf(pop, 1) * (1.3 if famine else 1.0))), s.dependants)
	s.dependants -= d
	n -= d
	var so := mini(int(n * float(s.soldiers) / maxf(s.soldiers + s.workers, 1)), s.soldiers)
	s.soldiers -= so
	n -= so
	var w := mini(n, s.workers)
	s.workers -= w
	n -= w
	if n > 0:
		var d2 := mini(n, s.dependants)
		s.dependants -= d2
		n -= d2
		s.soldiers -= mini(n, s.soldiers)

## Take n civilians (workers and dependants in proportion) out of a settlement.
static func take_people(s: SimSettlement, n: int) -> int:
	n = mini(n, s.workers + s.dependants)
	var dep := mini(int(n * float(s.dependants) / maxf(s.workers + s.dependants, 1)), s.dependants)
	var wk := mini(n - dep, s.workers)
	s.dependants -= dep
	s.workers -= wk
	return dep + wk

static func abandon_settlement(sim: WorldSim, s: SimSettlement, why: String) -> void:
	if not sim.settlements.has(s.id):
		return
	var left := s.workers + s.dependants + s.soldiers
	var fname := sim.faction_name(s.faction)
	sim.settlements.erase(s.id)
	sim.ruins[s.id] = true
	sim.stats_add("abandoned", 1)
	sim.log_event("abandoned", {"site": s.name, "why": why, "faction": fname, "left": left,
		"founded_year": s.founded / WorldSim.YEAR_H + 1})
	# Survivors walk to the nearest friendly settlement, if any.
	if left > 0:
		var dst := _nearest_friendly(sim, s.id, s.faction, s.culture, "migrants")
		if dst >= 0:
			var p := sim.new_party("migrants", s.faction, s.culture, s.id, {})
			p.people = left
			p.members = {str(SimData.culture(s.culture).people): left}
			p.cargo = {"food": int(s.stock.food)}
			p.plan = {"src_name": s.name}
			if not sim.send(p, dst, sim.mask_for(SimData.culture(s.culture).mobility)):
				sim.remove_party(p)
	for pid in sim.parties:
		var p: SimParty = sim.parties[pid]
		if p.state == "siege" and p.target == s.id:
			p.state = "travel"
	SimConflict.check_faction_alive(sim, s.faction)

static func _nearest_friendly(sim: WorldSim, from: int, faction: int, culture: String, kind: String) -> int:
	var mask := sim.mask_for(SimData.culture(culture).mobility)
	var reach: float = WorldSim.REACH_DAYS[kind] * WorldSim.DAY_H * WorldSim.SPEED[kind]
	var best := -1
	var best_h := INF
	for sid in WorldSim._sorted_keys(sim.settlements):
		if sid == from:
			continue
		var o: SimSettlement = sim.settlements[sid]
		var friendly := o.faction == faction
		if not friendly and sim.factions.has(faction) and sim.factions[faction].rel(o.faction) < 0.0:
			continue
		var h := sim.hours_between(from, sid, mask)
		if not friendly:
			h *= 1.5
		if h < best_h and h <= reach:
			best_h = h
			best = sid
	return best

# ── Decisions: caravans, migration ───────────────────────────────────────────

static func decide(sim: WorldSim, s: SimSettlement) -> void:
	if s.besieged_by >= 0:
		return
	_maybe_migrate(sim, s)
	if not sim.settlements.has(s.id):
		return
	var max_c := 1 + s.pop() / 500
	if s.out_caravans < max_c and s.workers >= 10 and sim.rng.randf() < 0.35:
		_plan_caravan(sim, s)

## Prices, stocks and stock targets of every settlement, built once per econ tick so trade
## planning doesn't recompute them per pair. Not saved: rebuilt before every use.
static func build_market(sim: WorldSim) -> void:
	var m := {}
	var n := SimData.good_names.size()
	for sid in sim.settlements:
		var s: SimSettlement = sim.settlements[sid]
		var row := PackedFloat64Array()
		row.resize(n * 3)
		for i in n:
			var g: String = SimData.good_names[i]
			var tg := target(s, g)
			row[i] = price_at(s, g, tg)
			row[n + i] = s.stock[g]
			row[2 * n + i] = tg
		m[sid] = row
	sim.market = m

static func _plan_caravan(sim: WorldSim, s: SimSettlement) -> void:
	var c := SimData.culture(s.culture)
	var n := SimData.good_names.size()
	# What this town can spare (live numbers).
	var goods: Array = []
	for i in n:
		var g: String = SimData.good_names[i]
		var tg := target(s, g)
		var surplus: float = s.stock[g] - tg * (1.1 if g == "food" else 0.8)
		var carry: float = SimData.goods[g].carry
		if surplus >= carry * 0.5:
			goods.append([i, g, surplus, carry, price_at(s, g, tg)])
	if goods.is_empty():
		return
	var mask := sim.mask_for(c.mobility)
	var reach: float = WorldSim.REACH_DAYS.caravan * WorldSim.DAY_H
	var dist: Dictionary = sim.paths_from(s.id, mask)[0]
	var me: SimFaction = sim.factions[s.faction]
	var best_profit := MIN_PROFIT
	var best: Array = []
	var max_wagons := clampi(s.workers / 40, 1, 6)
	var cands: Array = sim.within(s.id, mask, reach)
	# a people that goes down (cultures.json goes_down) takes the way at its own town to the deep
	# town at its foot, and no further: the deeps are no short cut between surface towns
	var down := {}
	if bool(c.get("goes_down", false)):
		for nr: Array in sim.adj.get(s.id, []):
			var rid := int(nr[1])
			if int(sim.route_by_id[rid].cls) == WorldSim.LINK and float(sim.route_travel_h[rid]) <= reach:
				down[int(nr[0])] = float(sim.route_travel_h[rid])
		cands = cands + down.keys()
	for sid in cands:
		if not sim.settlements.has(sid):
			continue
		var hours: float = down[sid] if down.has(sid) else dist[sid]
		var d: SimSettlement = sim.settlements[sid]
		if d.besieged_by >= 0:
			continue
		if d.faction != s.faction:
			if me.at_war(d.faction) or me.rel(d.faction) < float(c.get("trade_floor", -20.0)):
				continue
		var row: PackedFloat64Array = sim.market.get(sid, PackedFloat64Array())
		if row.is_empty():
			continue
		var days := hours / WorldSim.DAY_H
		var iso := 0.6 if d.faction != s.faction and sim.factions.has(d.faction) and sim.factions[d.faction].temperament == "isolationist" else 1.0
		for e in goods:
			var i: int = e[0]
			var ps: float = e[4]
			var pd: float = row[i]
			if pd < ps * 1.25:
				continue
			var carry: float = e[3]
			var wanted := row[2 * n + i] * (RICH_FOOD_STOCK if i == 0 and d.wealth >= d.pop() * RICH_FOOD_COIN else 1.3)
			var demand := maxf(wanted - row[n + i], 0.0)
			var amount := minf(minf(e[2], demand), max_wagons * carry)
			amount = minf(amount, d.wealth * 0.8 / pd)
			if amount < carry * 0.5:
				continue
			var wagons := int(ceil(amount / carry))
			var profit := amount * (pd - ps) * iso - wagons * days * 2.0 * WAGON_DAY_COST
			if profit > best_profit:
				best_profit = profit
				best = [sid, e[1], int(amount), wagons, ps, 0.0, amount * (pd - ps) * iso, pd]
	if best.is_empty():
		return
	if down.has(int(best[0])):
		mask = mask | WorldSim.LINK
	# Danger on the way only matters for the deal actually considered.
	var risk := _path_risk(sim, s.id, best[0], mask)
	if best_profit - best[6] * risk < MIN_PROFIT:
		return
	best[5] = risk
	if best.is_empty():
		return
	var dst: int = best[0]
	var good: String = best[1]
	var amount: int = best[2]
	var wagons: int = best[3]
	var drivers := mini(wagons, s.workers - 5)
	if drivers <= 0:
		return
	var esc_n := mini(int(2 + wagons + risk * 20.0), int(s.soldiers * 0.4))
	var members := SimData.allocate(c.escort, esc_n)
	var p := sim.new_party("caravan", s.faction, s.culture, s.id, members)
	p.people = drivers
	_add_member(p.members, str(c.people), drivers)
	p.wagons = wagons
	p.cargo = {good: amount}
	p.plan = {"good": good, "paid": float(best[4]), "dest_name": sim.settlements[dst].name, "escort": float(esc_n)}
	if not sim.send(p, dst, mask):
		sim.remove_party(p)
		return
	s.stock[good] -= float(amount)
	s.workers -= drivers
	s.soldiers -= esc_n
	s.out_caravans += 1
	sim.stats_add("caravans_sent", 1)
	_mark_traffic(sim, p, {good: float(best[7])})

static func _add_member(m: Dictionary, slug: String, n: int) -> void:
	if n > 0:
		m[slug] = int(m.get(slug, 0)) + n

## Recent ambushes and lair attacks along a path, as a 0..0.6 risk.
static func _path_risk(sim: WorldSim, a: int, b: int, mask: int) -> float:
	var path := sim.path_between(a, b, mask)
	var r := 0.0
	for i in range(path.size() - 1):
		r += sim.route_threat.get(sim.route_id(path[i], path[i + 1]), 0.0)
	return clampf(r * 0.08, 0.0, 0.6)

## A caravan sets out along its path: every route on it sees the wagons and what they carry,
## priced at what the far end will pay (`prices`: good -> coin a unit). That is what raiders
## hear about.
static func _mark_traffic(sim: WorldSim, p: SimParty, prices: Dictionary) -> void:
	var value := 0.0
	for g in p.cargo:
		value += float(p.cargo[g]) * float(prices.get(g, SimData.goods[g].base))
	for i in range(p.path.size() - 1):
		var rid := sim.route_id(p.path[i], p.path[i + 1])
		if not sim.route_traffic.has(rid):
			sim.route_traffic[rid] = {}
		var tr: Dictionary = sim.route_traffic[rid]
		tr[p.faction] = float(tr.get(p.faction, 0.0)) + 1.0
		var rv: Dictionary = sim.route_value.get(rid, {})
		rv[p.faction] = float(rv.get(p.faction, 0.0)) + value
		sim.route_value[rid] = rv
	if sim.ledger_on:
		_ledger_trip(sim, p, prices, value)

## The trade ledger's books for one trip: per route, and per flow of a good between biomes.
static func _ledger_trip(sim: WorldSim, p: SimParty, prices: Dictionary, value: float) -> void:
	var crossed: Array = []
	for i in range(p.path.size() - 1):
		var rid := sim.route_id(p.path[i], p.path[i + 1])
		var row := sim.ledger_row(rid)
		row.trips += 1
		row.value += value
		for g in p.cargo:
			row.goods[g] = int(row.goods.get(g, 0)) + int(p.cargo[g])
		crossed.append_array(sim.route_by_id[rid].get("crossings", []))
	crossed.sort()
	var from: String = sim.site_by_id[p.path[0]].biome
	var to: String = sim.site_by_id[p.path[p.path.size() - 1]].biome
	for g in p.cargo:
		var key := "%s|%s|%s|%s" % [g, from, to, ",".join(crossed)]
		var f: Array = sim.flows.get(key, [0, 0.0])
		f[0] += int(p.cargo[g])
		f[1] += float(p.cargo[g]) * float(prices.get(g, SimData.goods[g].base))
		sim.flows[key] = f

## A caravan reaches its market: sell, buy a return load, head home.
static func caravan_arrive(sim: WorldSim, p: SimParty) -> void:
	var here: int = p.path[p.path.size() - 1]
	if p.plan.get("leg", "out") == "home":
		return_home(sim, p)
		return
	if not sim.settlements.has(here):
		_go_home(sim, p)
		return
	var d: SimSettlement = sim.settlements[here]
	var sold_value := 0.0
	# what it brought, before the market takes it (Deals: did most of an escorted cargo arrive?)
	var brought := 0
	for g in p.cargo:
		brought += int(p.cargo[g])
	p.plan["brought"] = brought
	for g in SimData.good_names:
		var n: int = p.cargo.get(g, 0)
		if n <= 0:
			continue
		var pd := price(d, g)
		var can := mini(n, int(d.wealth * 0.9 / maxf(pd, 0.01)))
		if can <= 0:
			continue
		d.stock[g] += float(can)
		d.wealth -= can * pd
		p.coin += can * pd
		sold_value += can * pd
		p.cargo[g] = n - can
		if g == "food" and not d.shock.is_empty():
			d.shock.imports = int(d.shock.imports) + 1
	_clean_cargo(p)
	# Return load: the good that sells best at home, paid from the takings.
	if sim.settlements.has(p.home):
		var home: SimSettlement = sim.settlements[p.home]
		var best_g := ""
		var best_r := 1.25
		for g in SimData.good_names:
			var surplus: float = d.stock[g] - target(d, g)
			if surplus < float(SimData.goods[g].carry) * 0.3:
				continue
			var r := price(home, g) / maxf(price(d, g), 0.01)
			if r > best_r:
				best_r = r
				best_g = g
		if best_g != "":
			var pg := price(d, best_g)
			var cap := p.wagons * float(SimData.goods[best_g].carry)
			var n := int(minf(minf(cap, d.stock[best_g] - target(d, best_g)), p.coin * 0.7 / pg))
			if n > 0:
				d.stock[best_g] -= float(n)
				d.wealth += n * pg
				p.coin -= n * pg
				p.cargo[best_g] = int(p.cargo.get(best_g, 0)) + n
	sim.stats_add("caravans_arrived", 1)
	sim.stats_add("trade_value", int(sold_value))
	var back_prices := {}
	if sim.settlements.has(p.home):
		for g in p.cargo:
			back_prices[g] = price(sim.settlements[p.home], g)
	# Trade warms relations.
	if d.faction != p.faction and sim.factions.has(p.faction) and sim.factions.has(d.faction):
		var a: SimFaction = sim.factions[p.faction]
		var b: SimFaction = sim.factions[d.faction]
		a.relations[b.id] = minf(a.rel(b.id) + 2.5, 80.0)
		b.relations[a.id] = minf(b.rel(a.id) + 2.5, 80.0)
		if not a.partners.has(b.id):
			a.partners[b.id] = true
			b.partners[a.id] = true
			sim.log_event("trade_opened", {"a": a.name, "b": b.name, "from": sim._site_label(p.home), "to": d.name,
				"good": p.plan.get("good", "goods")})
	_go_home(sim, p)
	if sim.parties.has(p.id) and not p.cargo.is_empty():
		_mark_traffic(sim, p, back_prices)

static func _clean_cargo(p: SimParty) -> void:
	for g in p.cargo.keys():
		if p.cargo[g] <= 0:
			p.cargo.erase(g)

static func _go_home(sim: WorldSim, p: SimParty) -> void:
	p.plan["leg"] = "home"
	var dst := p.home
	if not sim.settlements.has(dst):
		dst = _nearest_friendly(sim, p.path[p.path.size() - 1] if not p.path.is_empty() else p.home,
			p.faction, p.culture if SimData.cultures.has(p.culture) else "human", "migrants")
		if dst < 0:
			_disband(sim, p)
			return
		p.plan["rehome"] = float(dst)
	var c: Dictionary = SimData.cultures.get(p.culture, SimData.cultures["human"])
	var list: Array = c.raid_mobility if p.kind in ["raid", "army", "patrol", "expedition"] else c.mobility
	if not sim.send(p, dst, sim.mask_for(list)):
		if not sim.send(p, dst, WorldSim.ROAD | WorldSim.DEEP | WorldSim.LINK):
			_disband(sim, p)

## Back at home (or a new home): people, soldiers, goods and coin rejoin the settlement.
static func return_home(sim: WorldSim, p: SimParty) -> void:
	var here: int = p.path[p.path.size() - 1] if not p.path.is_empty() else p.home
	if not sim.settlements.has(here):
		if here == p.home:
			_go_home(sim, p)
			if sim.parties.has(p.id) and p.path.size() >= 2:
				return
		_disband(sim, p)
		return
	var s: SimSettlement = sim.settlements[here]
	var people_slug := str(SimData.cultures.get(p.culture, SimData.cultures["human"]).people)
	var soldiers := p.size() - p.people
	var captives := int(p.plan.get("captives", 0.0))
	s.workers += p.people
	s.soldiers += maxi(soldiers, 0)
	for g in p.cargo:
		s.stock[g] = float(s.stock.get(g, 0.0)) + float(p.cargo[g])
	s.wealth += p.coin
	if here == p.home:
		match p.kind:
			"caravan": s.out_caravans = maxi(s.out_caravans - 1, 0)
			"raid": s.out_raids = maxi(s.out_raids - 1, 0)
			_: s.out_other = maxi(s.out_other - 1, 0)
	elif sim.settlements.has(p.home):
		var h: SimSettlement = sim.settlements[p.home]
		match p.kind:
			"caravan": h.out_caravans = maxi(h.out_caravans - 1, 0)
			"raid": h.out_raids = maxi(h.out_raids - 1, 0)
			_: h.out_other = maxi(h.out_other - 1, 0)
	if p.kind == "caravan":
		sim.stats_add("caravans_done", 1)
	if SimBelow.is_below(p):
		SimBelow.came_home(sim, p)
	sim.remove_party(p)

## A party with nowhere to go: its people scatter (counted, never silently lost).
static func _disband(sim: WorldSim, p: SimParty) -> void:
	sim.stats_add("scattered", p.size())
	if sim.settlements.has(p.home):
		var h: SimSettlement = sim.settlements[p.home]
		match p.kind:
			"caravan": h.out_caravans = maxi(h.out_caravans - 1, 0)
			"raid": h.out_raids = maxi(h.out_raids - 1, 0)
			_: h.out_other = maxi(h.out_other - 1, 0)
	sim.remove_party(p)

static func _maybe_migrate(sim: WorldSim, s: SimSettlement) -> void:
	if s.hungry < 2 and s.morale > 0.25:
		return
	if sim.t < int(s.cooldowns.get("migrate", 0)):
		return
	var c := SimData.culture(s.culture)
	var mask := sim.mask_for(c.mobility)
	var reach: float = WorldSim.REACH_DAYS.migrants * WorldSim.DAY_H * WorldSim.SPEED.migrants
	var pr: Array = sim.paths_from(s.id, mask)
	var best := -1
	var best_score := 0.25
	for sid in pr[2]:
		if sid == s.id or not sim.settlements.has(sid) or pr[0][sid] > reach:
			continue
		var d: SimSettlement = sim.settlements[sid]
		if d.faction != s.faction and sim.factions.has(s.faction) and sim.factions[s.faction].rel(d.faction) < -10.0:
			continue
		if d.besieged_by >= 0 or d.hungry > 0 or security(d) < 0.6:
			continue
		var score: float = minf(security(d), 1.5) + d.morale * 0.5 - pr[0][sid] / reach * 0.4
		if d.culture == s.culture: score += 0.3
		if d.faction == s.faction: score += 0.2
		if score > best_score:
			best_score = score
			best = sid
	s.cooldowns["migrate"] = sim.t + 90 * WorldSim.DAY_H
	if best < 0:
		return
	var want := mini(int(s.pop() * (0.12 if s.hungry >= 2 else 0.06)), 300)
	if want < 8:
		return
	var n := take_people(s, want)
	if n <= 0:
		return
	var p := sim.new_party("migrants", s.faction, s.culture, s.id, {str(c.people): n})
	p.people = n
	var food := int(minf(s.stock.food, n * EAT * 20.0))
	s.stock.food -= float(food)
	if food > 0:
		p.cargo = {"food": food}
	p.plan = {"src_name": s.name, "dest_name": sim.settlements[best].name}
	if not sim.send(p, best, mask):
		s.workers += n
		s.stock.food += float(food)
		sim.remove_party(p)
		return
	s.out_other += 1
	if not s.shock.is_empty():
		s.shock.migrants = int(s.shock.migrants) + 1
	sim.stats_add("migrations", 1)
	sim.stats_add("migrants", n)
	sim.log_event("migrants", {"from": s.name, "to": sim.settlements[best].name, "n": n,
		"why": "hunger" if s.hungry >= 2 else "despair"})

## Migrants arrive: they join whoever lives there (or found a home if it is empty).
static func migrants_arrive(sim: WorldSim, p: SimParty) -> void:
	var here: int = p.path[p.path.size() - 1]
	if sim.settlements.has(p.home):
		sim.settlements[p.home].out_other = maxi(sim.settlements[p.home].out_other - 1, 0)
	if sim.settlements.has(here):
		var s: SimSettlement = sim.settlements[here]
		var dep := int(p.people * 0.35)
		s.dependants += dep
		s.workers += p.people - dep
		s.soldiers += maxi(p.size() - p.people, 0)
		for g in p.cargo:
			s.stock[g] += float(p.cargo[g])
		s.wealth += p.coin
		sim.stats_add("migrants_settled", p.people)
		sim.remove_party(p)
		return
	_disband(sim, p)

# ── Yearly: founding daughter settlements ────────────────────────────────────

static func tick_year(sim: WorldSim) -> void:
	for sid in WorldSim._sorted_keys(sim.settlements):
		if not sim.settlements.has(sid):
			continue
		var s: SimSettlement = sim.settlements[sid]
		_maybe_found(sim, s)

static func _maybe_found(sim: WorldSim, s: SimSettlement) -> void:
	if s.pop() < 320 or security(s) < 0.7 or s.morale < 0.5 or s.out_other > 0 or s.besieged_by >= 0:
		return
	var f: SimFaction = sim.factions[s.faction]
	var drive: float = {"expansionist": 0.4, "trader": 0.22, "raider": 0.15, "isolationist": 0.08}.get(f.temperament, 0.2)
	if sim.rng.randf() > drive:
		return
	var c := SimData.culture(s.culture)
	var mask := sim.mask_for(c.mobility)
	var reach: float = WorldSim.REACH_DAYS.settlers * WorldSim.DAY_H * WorldSim.SPEED.settlers
	var pr: Array = sim.paths_from(s.id, mask)
	var best := -1
	var best_score := INF
	for sid in pr[2]:
		if not free_site(sim, sid, s.culture) or pr[0][sid] > reach:
			continue
		# Near first, but a people walks further for land that suits it.
		var score: float = (pr[0][sid] + 12.0) / (0.5 + SimData.fit(s.culture, sim.site_by_id[sid].biome))
		if score < best_score:
			best_score = score
			best = sid
	if best < 0:
		return
	var n := take_people(s, clampi(int(s.pop() * 0.14), 45, 250))
	var esc := mini(int(s.soldiers * 0.15), 12)
	var members := SimData.allocate(c.escort, esc)
	_add_member(members, str(c.people), n)
	var p := sim.new_party("settlers", s.faction, s.culture, s.id, members)
	p.people = n
	var food := int(minf(s.stock.food * 0.3, n * EAT * 120.0))
	var timber := int(minf(s.stock.timber * 0.3, n * 1.0))
	var coin := s.wealth * 0.15
	s.stock.food -= float(food)
	s.stock.timber -= float(timber)
	s.wealth -= coin
	s.soldiers -= esc
	p.cargo = {"food": food, "timber": timber}
	p.coin = coin
	p.plan = {"src_name": s.name}
	p.target = best
	if not sim.send(p, best, mask):
		s.workers += n
		s.soldiers += esc
		s.stock.food += float(food)
		s.stock.timber += float(timber)
		s.wealth += coin
		sim.remove_party(p)
		return
	s.out_other += 1
	sim.stats_add("settlers_sent", 1)

## A settlement site with nobody living there and no monsters, in bands the culture uses.
static func free_site(sim: WorldSim, sid: int, culture: String) -> bool:
	if sim.settlements.has(sid) or sim.lairs.has(sid):
		return false
	var site: Dictionary = sim.site_by_id[sid]
	if site.kind != "settlement" and not (site.kind == "ruin" and sim.ruins.has(sid)):
		return false
	return SimData.band_family(site.band) in SimData.culture(culture).bands

static func settlers_arrive(sim: WorldSim, p: SimParty) -> void:
	var here: int = p.path[p.path.size() - 1]
	if sim.settlements.has(p.home):
		sim.settlements[p.home].out_other = maxi(sim.settlements[p.home].out_other - 1, 0)
	if here == p.target and free_site(sim, here, p.culture) and sim.factions.has(p.faction) and sim.factions[p.faction].alive:
		var s := sim._new_settlement(here, p.culture, p.faction, 0)
		s.workers = p.people - int(p.people * 0.3)
		s.dependants = int(p.people * 0.3)
		s.soldiers = maxi(p.size() - p.people, 0)
		for g in SimData.good_names:
			s.stock[g] = float(p.cargo.get(g, 0))
		s.wealth = p.coin
		s.tier = SimSettlement.tier_for(s.pop())
		s.weather = sim.region_weather.get(sim.region_of(s), 1.0)
		sim.stats_add("founded", 1)
		sim.log_event("founded", {"site": s.name, "from": str(p.plan.get("src_name", "?")),
			"faction": sim.faction_name(p.faction), "n": s.pop(), "ruin": sim.site_by_id[here].kind == "ruin"})
		sim.remove_party(p)
		return
	# The site was taken or the founders' people are gone: go home, or join someone.
	p.kind = "migrants"
	p.plan["leg"] = "home"
	var dst := p.home if sim.settlements.has(p.home) else _nearest_friendly(sim, here, p.faction, p.culture, "migrants")
	if dst < 0 or not sim.send(p, dst, sim.mask_for(SimData.culture(p.culture).mobility)):
		_disband(sim, p)
		return
	if sim.settlements.has(p.home):
		sim.settlements[p.home].out_other += 1
