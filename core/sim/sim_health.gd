## Health statistics of one simulated history, for sweeps and invariant tests.
class_name SimHealth
extends RefCounted

## Run a synthetic world for `years` and summarise it. Keys: pop0, pop1, pop_min, pop_max,
## settl0, settl1, fell, founded, caravans, trade_done, ambushes, raids, wars, conquests,
## sacks, famines, lairs_cleared, bad (audit problems), ratio, shocks..., sig (chronicle
## signature), and flags trade_and_raids, grew, declined, fell_any, collapsed, exploded,
## shock_seen.
static func run(seed: int, years: int, n_sites: int) -> Dictionary:
	var sim := WorldSim.synthetic(n_sites, seed)
	var pop0 := sim.total_pop()
	var settl0 := sim.settlements.size()
	var pop_min := pop0
	var pop_max := pop0
	var first := {}
	var peak := {}
	var grew := false
	var declined := false
	var bad := 0
	for sid in sim.settlements:
		first[sid] = sim.settlements[sid].pop()
		peak[sid] = first[sid]
	for y in years:
		sim.step(WorldSim.YEAR_H)
		var p := sim.total_pop()
		pop_min = mini(pop_min, p)
		pop_max = maxi(pop_max, p)
		bad += sim.audit().size()
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
		"migrations": int(st.get("migrations", 0)),
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
	var kinds: PackedStringArray = []
	for e in sim.chronicle:
		if SimChronicle.WEIGHT.get(e.kind, 0) >= 5:
			kinds.append("%s@%d" % [e.kind, int(e.t) / WorldSim.YEAR_H])
	h["sig"] = hash(",".join(kinds))
	return h
