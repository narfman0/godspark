## Health statistics of one simulated history, for sweeps and invariant tests.
class_name SimHealth
extends RefCounted

## A settlement counts as rich in a season with this much coin a head and a full granary
## (the smith's own line for a rich town, data/deals/prices.json).
const RICH_COIN := 3.0
## Food security under this is a town short of food: what makes one raid for it (SimConflict).
const SHORT_FOOD := 0.35
## Tier a place must reach to be called a town.
const TOWN_POP := 600

## Run a synthetic world for `years` and summarise it. Keys: pop0, pop1, pop_min, pop_max,
## settl0, settl1, fell, founded, caravans, trade_done, ambushes, raids, wars, conquests,
## sacks, famines, lairs_cleared, bad (audit problems), ratio, shocks..., sig (chronicle
## signature), biomes (below), and flags trade_and_raids, grew, declined, fell_any, collapsed,
## exploded, shock_seen.
static func run(seed: int, years: int, n_sites: int) -> Dictionary:
	return observe(WorldSim.synthetic(n_sites, seed), years)

## The same for a sim already built, say on a generated world. `biomes`: biome -> {seasons,
## hungry, short, rich: settlement-seasons of each; people: sum of populations over them; start, end:
## settlements; pop0, pop1: people; top: largest place at the end; towns: places at the end of
## TOWN_POP or more; cultures: culture -> settlements at the start}.
static func observe(sim: WorldSim, years: int) -> Dictionary:
	sim.ledger_on = true
	var pop0 := sim.total_pop()
	var settl0 := sim.settlements.size()
	var pop_min := pop0
	var pop_max := pop0
	var first := {}
	var peak := {}
	var grew := false
	var declined := false
	var bad := 0
	var biomes := {}
	var deep0 := {}
	var deep_min := 1 << 30
	for sid in sim.settlements:
		if sim.settlements[sid].band != "surface":
			deep0[sid] = true
	for sid in sim.settlements:
		first[sid] = sim.settlements[sid].pop()
		peak[sid] = first[sid]
		var row := _biome_row(biomes, sim, sid)
		row.start += 1
		row.pop0 += first[sid]
		var who: String = sim.settlements[sid].culture
		row.cultures[who] = int(row.cultures.get(who, 0)) + 1
	for y in years:
		for q in 4:
			sim.step(WorldSim.SEASON_H)
			_sample(sim, biomes)
		var p := sim.total_pop()
		pop_min = mini(pop_min, p)
		pop_max = maxi(pop_max, p)
		bad += sim.audit().size()
		deep_min = mini(deep_min, deep_count(sim))
		for sid in sim.settlements:
			var sp: int = sim.settlements[sid].pop()
			if not first.has(sid):
				first[sid] = sp
				peak[sid] = sp
			peak[sid] = maxi(peak[sid], sp)
			if sp >= first[sid] * 1.5 and sp >= 100:
				grew = true
			if sp <= peak[sid] * 0.6 and peak[sid] >= 80:
				declined = true
	for sid in sim.settlements:
		var row := _biome_row(biomes, sim, sid)
		var sp: int = sim.settlements[sid].pop()
		row.end += 1
		row.pop1 += sp
		row.top = maxi(row.top, sp)
		if sp >= TOWN_POP:
			row.towns += 1
	var st := sim.stats
	var pop1 := sim.total_pop()
	var h := {
		"pop0": pop0, "pop1": pop1, "pop_min": pop_min, "pop_max": pop_max,
		"settl0": settl0, "settl1": sim.settlements.size(),
		"fell": int(st.get("abandoned", 0)), "founded": int(st.get("founded", 0)),
		"caravans": int(st.get("caravans_sent", 0)), "trade_done": int(st.get("caravans_arrived", 0)),
		"ambushes": int(st.get("ambushes", 0)), "raids": int(st.get("settlement_raids", 0)),
		"wars": int(st.get("wars", 0)), "conquests": int(st.get("conquests", 0)), "sacks": int(st.get("sacks", 0)),
		"famines": int(st.get("famines", 0)), "lairs_cleared": int(st.get("lairs_cleared", 0)),
		"migrations": int(st.get("migrations", 0)), "trade_value": int(st.get("trade_value", 0)),
		"shocks": int(st.get("shocks", 0)), "shock_price": int(st.get("shock_price", 0)),
		"shock_import": int(st.get("shock_import", 0)), "shock_migr": int(st.get("shock_migr", 0)),
		"shock_raid": int(st.get("shock_raid", 0)), "shock_any": int(st.get("shock_any", 0)),
		"bad": bad, "ratio": float(pop1) / maxf(pop0, 1.0),
		"events": sim.chronicle.size(),
	}
	h["trade_and_raids"] = h.trade_done > 0 and (h.ambushes + h.raids) > 0
	h["grew"] = grew
	h["declined"] = declined
	h["fell_any"] = h.fell + h.conquests + h.sacks > 0
	h["collapsed"] = pop1 < pop0 * 0.25 or sim.settlements.is_empty()
	h["exploded"] = pop_max > pop0 * 6
	h["shock_seen"] = h.shock_any > 0
	h["bad_any"] = bad > 0
	h["biomes"] = biomes
	h["routes"] = route_shares(sim)
	var deep_cult := {}
	var survived := 0
	for sid in sim.settlements:
		var s: SimSettlement = sim.settlements[sid]
		if s.band != "surface":
			deep_cult[s.culture] = int(deep_cult.get(s.culture, 0)) + 1
			if deep0.has(sid):
				survived += 1
	h["deep"] = {"start": deep0.size(), "end": deep_count(sim), "survived": survived,
		"min": deep_min if deep_min < (1 << 30) else deep0.size(), "cultures": deep_cult}
	h["below"] = below(sim)
	var kinds: PackedStringArray = []
	for e in sim.chronicle:
		if SimChronicle.WEIGHT.get(e.kind, 0) >= 5:
			kinds.append("%s@%d" % [e.kind, int(e.t) / WorldSim.YEAR_H])
	h["sig"] = hash(",".join(kinds))
	return h

## Trade over surface roads by what they cross, from the sim's ledger: "pass", "river" (a road
## with a ford or bridge and no pass) and "flat", each {routes, value, trips, ambushes, taken,
## beasts}, plus "barrier", pass and river together; and below: "deep" (roads between underground
## sites) and "link" (a deep site to the surface, by a way up).
static func route_shares(sim: WorldSim) -> Dictionary:
	var out := {}
	for kind in ["pass", "river", "flat", "barrier", "deep", "link"]:
		out[kind] = {"routes": 0, "value": 0.0, "trips": 0, "ambushes": 0, "taken": 0, "beasts": 0}
	for r in sim.routes:
		if r.has("trail"):
			continue
		if r.cls != WorldSim.ROAD:
			# deep roads between underground sites, and links between a deep site and the surface
			var row: Dictionary = out["deep" if r.cls == WorldSim.DEEP else "link"]
			var l: Dictionary = sim.ledger.get(r.id, {})
			row.routes += 1
			for k in ["value", "trips", "ambushes", "taken", "beasts"]:
				row[k] += l.get(k, 0)
			continue
		var kind := "flat"
		if "pass" in r.crossings:
			kind = "pass"
		elif not r.crossings.is_empty():
			kind = "river"
		var led: Dictionary = sim.ledger.get(r.id, {})
		var rows: Array = [out[kind], out.barrier] if kind != "flat" else [out.flat]
		for row in rows:
			row.routes += 1
			for k in ["value", "trips", "ambushes", "taken", "beasts"]:
				row[k] += led.get(k, 0)
	return out

static func _biome_row(biomes: Dictionary, sim: WorldSim, sid: int) -> Dictionary:
	var b: String = sim.site_by_id[sid].biome
	if not biomes.has(b):
		biomes[b] = {"seasons": 0, "hungry": 0, "short": 0, "rich": 0, "people": 0, "start": 0, "end": 0,
			"pop0": 0, "pop1": 0, "top": 0, "towns": 0, "cultures": {}}
	return biomes[b]

static func _sample(sim: WorldSim, biomes: Dictionary) -> void:
	for sid in sim.settlements:
		var s: SimSettlement = sim.settlements[sid]
		var row := _biome_row(biomes, sim, sid)
		var p := s.pop()
		row.seasons += 1
		row.people += p
		var sec := SimEconomy.security(s)
		if s.hungry > 0:
			row.hungry += 1
		if s.hungry > 0 or sec < SHORT_FOOD:
			row.short += 1
		elif sec >= 1.0 and s.wealth >= p * RICH_COIN:
			row.rich += 1

## Raids from below (SimBelow): sent, ambushes on surface roads and won, goods and coin taken and
## carried home, how many came home, watches posted at ways and their fights, bounties a raided
## town's patron would offer (an ambush from below on one of its caravans while the raiders' city
## stands), and raids by culture.
static func below(sim: WorldSim) -> Dictionary:
	var st := sim.stats
	var out := {"sent": int(st.get("raids_below", 0)), "ambushes": int(st.get("below_ambushes", 0)),
		"wins": int(st.get("below_wins", 0)), "taken": int(st.get("below_taken", 0)), "coin_taken": int(st.get("below_coin_taken", 0)),
		"home": int(st.get("below_home", 0)), "goods_home": int(st.get("below_goods_home", 0)), "coin_home": int(st.get("below_coin_home", 0)),
		"watches": int(st.get("way_watches", 0)), "watch_fights": int(st.get("watch_fights", 0)), "watch_wins": int(st.get("watch_wins", 0)),
		"recovered": int(st.get("watch_recovered", 0)), "bounties": 0, "by": {}}
	for e: Dictionary in sim.chronicle:
		if String(e.get("kind", "")) != "ambush" or not bool(e.get("below", false)):
			continue
		out.by[str(e.get("raiders", "?"))] = int(out.by.get(str(e.get("raiders", "?")), 0)) + 1
		if sim.site_by_id.has(int(e.get("vhome", -1))) and SimData.band_family(sim.site_by_id[int(e.get("vhome", -1))].band) == "surface":
			out.bounties += 1
	return out

## Settlements below the surface.
static func deep_count(sim: WorldSim) -> int:
	var n := 0
	for sid in sim.settlements:
		if sim.settlements[sid].band != "surface":
			n += 1
	return n
