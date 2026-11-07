## Run the strategic sim and print what happened.
##   godot --headless -s res://tools/run_history.gd -- seed=N years=200 sites=24 [csv=/path.csv] [quiet=1] [full=1]
##   godot --headless -s res://tools/run_history.gd -- seed=N years=200 world=dev         # sites and routes from WorldGen
##   godot --headless -s res://tools/run_history.gd -- seeds=1..30 years=200 sites=24   # sweep: health stats
##   godot --headless -s res://tools/run_history.gd -- seeds=1..10 years=100 world=dev [cache=/dir]   # on generated worlds; cache keeps what the sim reads of each
##   godot --headless -s res://tools/run_history.gd -- calibrate=1 [trials=200]          # SimCombat vs BattleSimulator
##   godot --headless -s res://tools/run_history.gd -- bench=1 sites=100 years=20        # tick cost
extends SceneTree

var _args := {}

func _initialize() -> void:
	var args := _args
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if args.has("calibrate"):
		_calibrate(int(args.get("trials", "200")))
	elif args.has("bench"):
		_bench(int(args.get("sites", "100")), int(args.get("years", "20")), int(args.get("seed", "1")))
	elif args.has("seeds"):
		var r: PackedStringArray = str(args.seeds).split("..")
		_sweep(int(r[0]), int(r[1]) if r.size() > 1 else int(r[0]), int(args.get("years", "200")), int(args.get("sites", "24")))
	else:
		_history(int(args.get("seed", "1")), int(args.get("years", "200")), int(args.get("sites", "24")),
			str(args.get("csv", "")), args.has("quiet"), args.has("full"))
	quit()

## What the sim reads of a generated world, kept in `cache` if given (the sim's own tuning runs
## far more often than the world changes).
func _world_meta(gen: String, seed: int) -> Dictionary:
	var path := "%s/%s_%d.json" % [str(_args.get("cache", "")), gen, seed]
	if _args.has("cache") and FileAccess.file_exists(path):
		return _with_width(JSON.parse_string(FileAccess.get_file_as_string(path)))
	var m: Dictionary = WorldGen.generate_named(gen, seed).meta
	if _args.has("cache"):
		var keep := {"sites": m.sites, "routes": m.routes, "width": (m.surface as Variant).size(), "barriers": m.get("barriers", {})}
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(keep))
		f.close()
	return m

func _with_width(m: Dictionary) -> Dictionary:
	var surface: Array = []
	surface.resize(int(m.width))
	m["surface"] = surface
	return m

# ── One history ──────────────────────────────────────────────────────────────

func _history(seed: int, years: int, n_sites: int, csv_path: String, quiet: bool, full: bool) -> void:
	var sim: WorldSim
	if _args.has("world"):  # a real generated world: world=dev|small|medium|large
		sim = WorldSim.from_meta(_world_meta(str(_args.world), seed), seed)
	else:
		sim = WorldSim.synthetic(n_sites, seed)
	_print_world(sim)
	var rows: PackedStringArray = ["year,site,name,culture,faction,pop,food,wealth"]
	var t0 := Time.get_ticks_usec()
	var bad: Array[String] = []
	var pops: Array = [sim.total_pop()]
	var trace := int(_args.get("trace", "0"))
	for y in years:
		if y < trace and y >= int(_args.get("trace_from", "0")):
			for q in 4:
				sim.step(WorldSim.SEASON_H)
				_trace(sim)
		else:
			sim.step(WorldSim.YEAR_H)
		for sid in WorldSim._sorted_keys(sim.settlements):
			var s: SimSettlement = sim.settlements[sid]
			rows.append("%d,%d,%s,%s,%s,%d,%d,%d" % [y + 1, s.id, s.name, s.culture, sim.faction_name(s.faction).replace(",", ""),
				s.pop(), int(s.stock.food), int(s.wealth)])
		pops.append(sim.total_pop())
		bad.append_array(sim.audit())
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	if not quiet:
		print("\n== Chronicle (%d events)" % sim.chronicle.size())
		if full or sim.chronicle.size() <= 300:
			for e in sim.chronicle:
				print(sim.describe(e))
		else:
			_digest(sim)
	print("\n== Population by decade: ", ", ".join(_every(pops, 10)))
	_print_final(sim)
	print("\n== Stats")
	var keys := sim.stats.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for k in keys:
		parts.append("%s=%d" % [k, sim.stats[k]])
	print("  ", " ".join(parts))
	print("  audit problems: %d%s" % [bad.size(), "" if bad.is_empty() else " (first: %s)" % bad[0]])
	print("  simulated %d years in %.0f ms" % [years, ms])
	if csv_path != "":
		var f := FileAccess.open(csv_path, FileAccess.WRITE)
		f.store_string("\n".join(rows) + "\n")
		f.close()
		print("  wrote ", csv_path)

func _trace(sim: WorldSim) -> void:
	print("-- %s" % SimChronicle.stamp(sim.t - 1))
	for sid in WorldSim._sorted_keys(sim.settlements):
		var s: SimSettlement = sim.settlements[sid]
		print("  %-12s %-9s pop %4d (w%4d d%4d s%3d) food %6d sec %.2f p %.2f cap %.0f wx %.2f mor %.2f hungry %d wealth %d timber %d ore %d tools %d lux %d" % [
			s.name, s.culture, s.pop(), s.workers, s.dependants, s.soldiers, int(s.stock.food), SimEconomy.security(s),
			SimEconomy.price(s, "food"), s.cap.food, s.weather, s.morale, s.hungry, int(s.wealth),
			int(s.stock.timber), int(s.stock.ore), int(s.stock.tools), int(s.stock.luxuries)])

func _every(arr: Array, n: int) -> PackedStringArray:
	var out: PackedStringArray = []
	for i in range(0, arr.size(), n):
		out.append(str(arr[i]))
	return out

func _print_world(sim: WorldSim) -> void:
	print("== World seed %d: %d sites, %d routes, %d settlements, %d lairs, %d factions, %d people" % [
		sim.seed, sim.sites.size(), sim.routes.size(), sim.settlements.size(), sim.lairs.size(),
		sim.factions.size(), sim.total_pop()])
	for s in sim.sites:
		var what := ""
		if sim.settlements.has(s.id):
			var st: SimSettlement = sim.settlements[s.id]
			what = "%s, %s %s of %s (%d)" % [st.name, SimData.culture(st.culture).adj, st.tier, sim.faction_name(st.faction), st.pop()]
		elif sim.lairs.has(s.id):
			var l: SimLair = sim.lairs[s.id]
			what = "%s: %s" % [l.name, _members(l.monsters)]
		else:
			what = "(%s)" % ("ruins" if sim.ruins.has(s.id) else "empty " + str(s.kind))
		print("  x=%6d %-8s %-10s %-10s %s" % [int(s.x), s.band, s.biome, s.kind, what])
	for fid in WorldSim._sorted_keys(sim.factions):
		var f: SimFaction = sim.factions[fid]
		print("  faction %s: %s, %s" % [f.name, f.culture, f.temperament])
	if _args.has("trace"):
		for r in sim.routes:
			print("  route %d: %d-%d cls %d %.0f h" % [r.id, r.a, r.b, r.cls, sim.route_hours[r.id]])
		for sid in WorldSim._sorted_keys(sim.settlements):
			var s: SimSettlement = sim.settlements[sid]
			var mask := sim.mask_for(SimData.culture(s.culture).mobility)
			var dist: Dictionary = sim.paths_from(sid, mask)[0]
			var reach: PackedStringArray = []
			for o in WorldSim._sorted_keys(sim.settlements):
				if o != sid and dist.has(o):
					reach.append("%s %.0fd" % [sim.settlements[o].name, dist[o] / 24.0])
			print("  %s (site %d, %s) reaches: %s" % [s.name, sid, s.culture, ", ".join(reach)])

func _members(m: Dictionary) -> String:
	var parts: PackedStringArray = []
	var keys := m.keys()
	keys.sort()
	for k in keys:
		parts.append("%d %s" % [m[k], k])
	return ", ".join(parts)

func _digest(sim: WorldSim) -> void:
	var by_decade := {}
	for e in sim.chronicle:
		var d := int(e.t) / (WorldSim.YEAR_H * 10)
		if not by_decade.has(d):
			by_decade[d] = []
		by_decade[d].append(e)
	for d in WorldSim._sorted_keys(by_decade):
		var evs: Array = by_decade[d]
		var counts := {}
		for e in evs:
			counts[e.kind] = int(counts.get(e.kind, 0)) + 1
		var ck := counts.keys()
		ck.sort()
		var cs: PackedStringArray = []
		for k in ck:
			cs.append("%s %d" % [k, counts[k]])
		print("\n-- Years %d-%d: %s" % [d * 10 + 1, d * 10 + 10, ", ".join(cs)])
		var ranked := evs.duplicate()
		ranked.sort_custom(func(a, b):
			var wa: int = SimChronicle.WEIGHT.get(a.kind, 0)
			var wb: int = SimChronicle.WEIGHT.get(b.kind, 0)
			return wa > wb or (wa == wb and int(a.t) < int(b.t)))
		var top := ranked.slice(0, 8)
		top.sort_custom(func(a, b): return int(a.t) < int(b.t))
		for e in top:
			print("  ", sim.describe(e))

func _print_final(sim: WorldSim) -> void:
	print("\n== Final state, year %d" % sim.year())
	print("  %-14s %-10s %-26s %-7s %6s %6s %6s %5s %4s" % ["settlement", "culture", "faction", "tier", "pop", "food", "wealth", "mor", "sol"])
	for sid in WorldSim._sorted_keys(sim.settlements):
		var s: SimSettlement = sim.settlements[sid]
		print("  %-14s %-10s %-26s %-7s %6d %6d %6d %5.2f %4d" % [s.name, s.culture, sim.faction_name(s.faction).left(26),
			s.tier, s.pop(), int(s.stock.food), int(s.wealth), s.morale, s.soldiers])
	for lid in WorldSim._sorted_keys(sim.lairs):
		var l: SimLair = sim.lairs[lid]
		print("  lair %s: %s (hunger %.2f)" % [l.name, _members(l.monsters), l.hunger])
	var wars: PackedStringArray = []
	for fid in WorldSim._sorted_keys(sim.factions):
		var f: SimFaction = sim.factions[fid]
		for gid in WorldSim._sorted_keys(f.wars):
			if gid > fid:
				wars.append("%s vs %s" % [f.name, sim.faction_name(gid)])
	print("  wars: %s" % (", ".join(wars) if not wars.is_empty() else "none"))
	print("  parties abroad: %d" % sim.parties.size())

# ── Sweep ────────────────────────────────────────────────────────────────────

func _sweep(a: int, b: int, years: int, n_sites: int) -> void:
	var agg := {}
	var sigs := {}
	var biomes := {}
	var routes := {"pass": {}, "river": {}, "flat": {}, "deep": {}, "link": {}}
	var deep := {"start": 0, "end": 0, "survived": 0, "min": 0, "worlds": 0, "cultures": {}}
	var below := {}
	var below_lines: PackedStringArray = []
	var lines: PackedStringArray = []
	var n := 0
	var lo0 := 1 << 40
	var hi0 := 0
	var t0 := Time.get_ticks_usec()
	for seed in range(a, b + 1):
		var h: Dictionary
		if _args.has("world"):
			h = SimHealth.observe(WorldSim.from_meta(_world_meta(str(_args.world), seed), seed), years)
		else:
			h = SimHealth.run(seed, years, n_sites)
		n += 1
		_add_biomes(biomes, h.biomes)
		for kind in routes:
			for k in h.routes[kind]:
				routes[kind][k] = float(routes[kind].get(k, 0.0)) + float(h.routes[kind][k])
		sigs[h.sig] = true
		var hd: Dictionary = h.get("deep", {})
		if int(hd.get("start", 0)) > 0:
			deep.worlds += 1
		for k in ["start", "end", "survived", "min"]:
			deep[k] += int(hd.get(k, 0))
		for c in hd.get("cultures", {}):
			deep.cultures[c] = int(deep.cultures.get(c, 0)) + int(hd.cultures[c])
		var hb: Dictionary = h.get("below", {})
		for k in hb:
			if k == "by":
				var by: Dictionary = below.get("by", {})
				for c in hb.by:
					by[c] = int(by.get(c, 0)) + int(hb.by[c])
				below["by"] = by
			else:
				below[k] = int(below.get(k, 0)) + int(hb[k])
		below_lines.append("seed %3d: raids from below %3d, ambushes %3d (won %3d), goods taken %5d, home %3d with %5d goods %5d coin; watches %2d, fights at the mouth %2d (won %2d); bounties %2d; %s" % [
			seed, int(hb.get("sent", 0)), int(hb.get("ambushes", 0)), int(hb.get("wins", 0)), int(hb.get("taken", 0)), int(hb.get("home", 0)),
			int(hb.get("goods_home", 0)), int(hb.get("coin_home", 0)), int(hb.get("watches", 0)), int(hb.get("watch_fights", 0)),
			int(hb.get("watch_wins", 0)), int(hb.get("bounties", 0)), hb.get("by", {})])
		lines.append("seed %3d: pop %5d -> %5d (min %5d, max %5d)  settl %2d -> %2d  fell %2d  founded %2d  caravans %4d  ambush %3d  raids %3d  wars %2d  conq %d sack %d  famine %3d  lairs cleared %2d  bad %d" % [
			seed, h.pop0, h.pop1, h.pop_min, h.pop_max, h.settl0, h.settl1, h.fell, h.founded, h.caravans, h.ambushes,
			h.raids, h.wars, h.conquests, h.sacks, h.famines, h.lairs_cleared, h.bad])
		lo0 = mini(lo0, h.pop0)
		hi0 = maxi(hi0, h.pop0)
		for k in h:
			if k != "sig" and (h[k] is int or h[k] is float):
				agg[k] = float(agg.get(k, 0.0)) + float(h[k])
		for flag in ["trade_and_raids", "grew", "declined", "fell_any", "collapsed", "exploded", "shock_seen", "bad_any"]:
			if h.get(flag, false):
				agg["n_" + flag] = int(agg.get("n_" + flag, 0)) + 1
		agg["shocks"] = float(agg.get("shocks", 0.0))
	for l in lines:
		print(l)
	var secs := (Time.get_ticks_usec() - t0) / 1e6
	print("\n== Sweep: %d seeds x %d years x %d sites in %.1f s" % [n, years, n_sites, secs])
	print("  worlds with negative stocks/pops: %d" % int(agg.get("n_bad_any", 0)))
	for flag in ["trade_and_raids", "grew", "declined", "fell_any", "collapsed", "exploded", "shock_seen"]:
		print("  worlds %-16s %d / %d" % [flag, int(agg.get("n_" + flag, 0)), n])
	print("  mean final/initial pop: %.2f" % (agg.get("ratio", 0.0) / n))
	var sh: float = agg.get("shocks", 0.0)
	if sh > 0:
		print("  food shocks: %d; price rose >=50%%: %.0f%%; food imported: %.0f%%; migration: %.0f%%; raids launched: %.0f%%; price rise + any response: %.0f%%" % [
			int(sh), 100.0 * agg.get("shock_price", 0.0) / sh, 100.0 * agg.get("shock_import", 0.0) / sh,
			100.0 * agg.get("shock_migr", 0.0) / sh, 100.0 * agg.get("shock_raid", 0.0) / sh, 100.0 * agg.get("shock_any", 0.0) / sh])
	print("  per world means: caravans %.0f, ambushes %.0f, settlement raids %.0f, wars %.1f, conquests %.1f, sacks %.1f, foundings %.1f, settlements fallen %.1f, lairs cleared %.1f" % [
		agg.caravans / n, agg.ambushes / n, agg.raids / n, agg.wars / n, agg.conquests / n, agg.sacks / n,
		agg.founded / n, agg.fell / n, agg.lairs_cleared / n])
	print("  mean trade value %.0f, famines %.1f, starting people %.0f (%d-%d), ending people %.0f" % [
		agg.get("trade_value", 0.0) / n, agg.famines / n, agg.pop0 / n, lo0, hi0, agg.pop1 / n])
	print("  distinct chronicle signatures: %d / %d" % [sigs.size(), n])
	_print_biomes(biomes, n)
	var dc: Array = deep.cultures.keys()
	dc.sort_custom(func(p, q): return deep.cultures[p] > deep.cultures[q])
	print("  deep settlements: %d worlds with any; a world %.1f at the start, %.1f at the end, the fewest %.1f; %d of %d of the first still stand; at the end: %s" % [
		deep.worlds, deep.start / float(n), deep.end / float(n), deep.min / float(n), deep.survived, deep.start,
		", ".join(dc.map(func(c): return "%s %d" % [c, deep.cultures[c]]))])
	print("\n== Raids from below (deep raiders up a way to a surface road), per seed")
	for l in below_lines:
		print("  " + l)
	var fn := float(n)
	print("  a world: raids from below %.1f, ambushes on surface roads %.1f (won %.1f), goods taken %.0f, raids home %.1f carrying %.0f goods and %.0f coin, watches posted %.1f, fights at the mouth %.1f (won %.1f, %.0f goods taken back), bounties offered %.1f; by %s" % [
		below.get("sent", 0) / fn, below.get("ambushes", 0) / fn, below.get("wins", 0) / fn, below.get("taken", 0) / fn,
		below.get("home", 0) / fn, below.get("goods_home", 0) / fn, below.get("coin_home", 0) / fn, below.get("watches", 0) / fn,
		below.get("watch_fights", 0) / fn, below.get("watch_wins", 0) / fn, below.get("recovered", 0) / fn, below.get("bounties", 0) / fn,
		below.get("by", {})])
	for kind in routes:
		var r: Dictionary = routes[kind]
		var nr := maxf(r.get("routes", 0.0), 1.0)
		print("  %-6s roads: %.1f a world; each carried %.0f coin in %.0f trips (%.0f a trip), %.1f ambushes (%.1f lost), %.1f lair attacks" % [
			kind, r.get("routes", 0.0) / n, r.get("value", 0.0) / nr, r.get("trips", 0.0) / nr, r.get("value", 0.0) / maxf(r.get("trips", 0.0), 1.0),
			r.get("ambushes", 0.0) / nr, r.get("taken", 0.0) / nr, r.get("beasts", 0.0) / nr])

func _add_biomes(into: Dictionary, row: Dictionary) -> void:
	for b in row:
		if not into.has(b):
			into[b] = {"worlds": 0}
		into[b].worlds += 1
		for k in row[b]:
			if k == "cultures":
				var into_c: Dictionary = into[b].get(k, {})
				for c in row[b][k]:
					into_c[c] = int(into_c.get(c, 0)) + row[b][k][c]
				into[b][k] = into_c
			elif k == "top":
				into[b][k] = maxi(int(into[b].get(k, 0)), row[b][k])
			else:
				into[b][k] = int(into[b].get(k, 0)) + row[b][k]

func _print_biomes(biomes: Dictionary, n: int) -> void:
	print("\n== Per biome, %d worlds: settlements and people are means per world" % n)
	print("  %-10s %6s %7s %7s %7s %7s %7s %6s %7s %7s %7s" % ["biome", "worlds", "settl0", "settl1", "pop0", "pop1", "per pl", "top", "hungry", "short", "rich"])
	var keys := biomes.keys()
	keys.sort()
	for b in keys:
		var r: Dictionary = biomes[b]
		var w := float(n)
		var seasons := maxf(r.seasons, 1.0)
		print("  %-10s %6d %7.1f %7.1f %7.0f %7.0f %7.0f %6d %6.1f%% %6.1f%% %6.1f%%   towns %.1f" % [b, r.worlds, r.start / w, r.end / w, r.pop0 / w, r.pop1 / w,
			float(r.people) / seasons, r.top, 100.0 * r.hungry / seasons, 100.0 * r.short / seasons, 100.0 * r.rich / seasons, r.towns / w])
		var who: Array = r.cultures.keys()
		who.sort_custom(func(p, q): return r.cultures[p] > r.cultures[q])
		print("             settled by: %s" % ", ".join(who.slice(0, 6).map(func(c): return "%s %d" % [c, r.cultures[c]])))

# ── Calibration ──────────────────────────────────────────────────────────────

func _calibrate(trials: int) -> void:
	var srd := SRDContent.new()
	var bs := BattleSimulator.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var old_rng := Dice.rng
	Dice.rng = RandomNumberGenerator.new()
	Dice.rng.seed = 999
	var matchups := [
		[{"bandit": 6}, {"guard": 6}],
		[{"goblin-warrior": 8}, {"guard": 5}],
		[{"bandit": 5, "bandit-captain": 1}, {"guard": 6, "commoner": 4}],
		[{"scout": 4, "spy": 2}, {"warrior-infantry": 6}],
		[{"wolf": 6}, {"guard": 3, "commoner": 4}],
		[{"ogre": 2}, {"guard": 8}],
		[{"owlbear": 1}, {"warrior-infantry": 6}],
		[{"gnoll-warrior": 5, "hyena": 3}, {"warrior-infantry": 8}],
		[{"giant-spider": 4}, {"scout": 5}],
		[{"hobgoblin-warrior": 6, "goblin-warrior": 6}, {"guard": 10, "guard-captain": 1}],
		[{"troll": 1}, {"guard": 10}],
		[{"warrior-veteran": 2}, {"bandit": 8}],
	]
	print("== SimCombat vs BattleSimulator, %d trials each, fight to the finish" % trials)
	print("  %-44s %8s %8s %8s | %8s %8s | %8s %8s" % ["matchup (A vs B)", "BS A win", "fast", "fast-c", "BS A dead", "fast", "BS B dead", "fast"])
	var bs_us := 0
	var fast_us := 0
	var err_full := 0.0
	var err_c := 0.0
	for mu in matchups:
		var a: Dictionary = mu[0]
		var b: Dictionary = mu[1]
		var bs_win := 0
		var bs_adead := 0.0
		var bs_bdead := 0.0
		var t0 := Time.get_ticks_usec()
		for i in trials:
			var pa := _build(srd, a)
			var pb := _build(srd, b)
			var r := bs.run(pa, pb)
			if r.party_won: bs_win += 1
			bs_adead += _dead_count(pa)
			bs_bdead += _dead_count(pb)
		bs_us += Time.get_ticks_usec() - t0
		var fw := [0, 0]
		var fa := [0.0, 0.0]
		var fb := [0.0, 0.0]
		t0 = Time.get_ticks_usec()
		for mode in 2:
			for i in trials:
				var r := SimCombat.resolve(rng, a, b, {"compat": mode == 1})
				if r.winner == "a": fw[mode] += 1
				fa[mode] += SimData.count(r.a_dead)
				fb[mode] += SimData.count(r.b_dead)
		fast_us += Time.get_ticks_usec() - t0
		var label := "%s vs %s" % [_members(a), _members(b)]
		print("  %-44s %7.0f%% %7.0f%% %7.0f%% | %8.1f %8.1f | %8.1f %8.1f" % [label.left(44), 100.0 * bs_win / trials,
			100.0 * fw[0] / trials, 100.0 * fw[1] / trials, bs_adead / trials, fa[1] / trials, bs_bdead / trials, fb[1] / trials])
		err_full += absf(float(fw[0] - bs_win)) / trials
		err_c += absf(float(fw[1] - bs_win)) / trials
	print("  mean |win-rate difference|: full model %.1f pts, compat model %.1f pts" % [100.0 * err_full / matchups.size(), 100.0 * err_c / matchups.size()])
	print("  time per fight: BattleSimulator %.0f us (incl. building combatants), SimCombat %.1f us" % [
		float(bs_us) / (trials * matchups.size()), float(fast_us) / (2 * trials * matchups.size())])
	print("  (fast = multiattack and all damage parts; fast-c = BattleSimulator's model: one attack, first damage part; dead counts use fast-c)")
	Dice.rng = old_rng

func _build(srd: SRDContent, side: Dictionary) -> Array:
	var out: Array = []
	var keys := side.keys()
	keys.sort()
	var id := 1
	for slug in keys:
		for i in int(side[slug]):
			out.append(srd.make_monster(slug, id))
			id += 1
	return out

func _dead_count(arr: Array) -> float:
	var n := 0
	for c in arr:
		if not c.is_alive:
			n += 1
	return n

# ── Benchmark ────────────────────────────────────────────────────────────────

func _bench(n_sites: int, years: int, seed: int) -> void:
	var sim := WorldSim.synthetic(n_sites, seed)
	sim.profile = true
	print("== Bench: %d sites (%d settlements, %d lairs), %d years" % [n_sites, sim.settlements.size(), sim.lairs.size(), years])
	var t0 := Time.get_ticks_usec()
	var worst := 0
	for d in years * WorldSim.YEAR_DAYS:
		var t1 := Time.get_ticks_usec()
		sim.step(WorldSim.DAY_H)
		worst = maxi(worst, Time.get_ticks_usec() - t1)
	var us := Time.get_ticks_usec() - t0
	var days := years * WorldSim.YEAR_DAYS
	print("  total %.2f s; per simulated day %.3f ms (worst day %.2f ms); per hour %.4f ms; per econ tick (5 days) %.2f ms" % [
		us / 1e6, us / 1000.0 / days, worst / 1000.0, us / 1000.0 / (days * 24), us / 1000.0 / days * 5])
	var pk := sim.prof.keys()
	pk.sort()
	for k in pk:
		print("  %-10s %8.1f ms total, %.3f ms per day" % [k, sim.prof[k] / 1000.0, sim.prof[k] / 1000.0 / days])
	print("  end: %d settlements, %d people, %d parties abroad, %d events" % [sim.settlements.size(), sim.total_pop(), sim.parties.size(), sim.chronicle.size()])
