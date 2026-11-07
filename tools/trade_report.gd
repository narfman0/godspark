## What the caravans carried, over what, and who robbed them. Reads the sim's trade ledger, so
## the line "caravans carry scarce goods across barriers and get raided for them" can be checked
## by reading this.
##   godot --headless -s res://tools/trade_report.gd -- gen=medium seed=N [days=3600] [cache=/dir]
## Prints every surface and deep route west to east, the flows of goods between biomes, and how
## barrier roads compare with flat ones. cache as in tools/run_history.gd.
extends SceneTree

var _args := {}

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var gen := str(_args.get("gen", "medium"))
	var seed := int(_args.get("seed", "1"))
	var days := int(_args.get("days", "3600"))
	var sim := WorldSim.from_meta(_meta(gen, seed), seed)
	sim.ledger_on = true
	var t0 := Time.get_ticks_msec()
	sim.step(days * WorldSim.DAY_H)
	print("== Trade report: %s seed %d, %d days (%.1f years) in %d ms: %d settlements, %d people, audit problems %d" % [
		gen, seed, days, days / float(WorldSim.YEAR_DAYS), Time.get_ticks_msec() - t0, sim.settlements.size(), sim.total_pop(), sim.audit().size()])
	_routes(sim)
	_flows(sim)
	_compare(sim, days)
	quit()

func _meta(gen: String, seed: int) -> Dictionary:
	var path := "%s/%s_%d.json" % [str(_args.get("cache", "")), gen, seed]
	if _args.has("cache") and FileAccess.file_exists(path):
		var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var surface: Array = []
		surface.resize(int(m.width))
		m["surface"] = surface
		return m
	return WorldGen.generate_named(gen, seed).meta

func _cross(r: Dictionary) -> String:
	return "+".join(r.get("crossings", [])) if not r.get("crossings", []).is_empty() else "-"

func _biome(sim: WorldSim, sid: int) -> String:
	return str(sim.site_by_id[sid].biome).left(6)

func _goods(row: Dictionary) -> String:
	var goods: Array = row.get("goods", {}).keys()
	goods.sort_custom(func(a, b): return int(row.goods[a]) * float(SimData.goods[a].base) > int(row.goods[b]) * float(SimData.goods[b].base))
	var parts: PackedStringArray = []
	for g in goods.slice(0, 4):
		parts.append("%s %d" % [g, row.goods[g]])
	return ", ".join(parts)

func _raiders(row: Dictionary) -> String:
	var keys: Array = row.get("raiders", {}).keys()
	keys.sort()
	var parts: PackedStringArray = []
	for k in keys:
		parts.append("%s %d" % [k, row.raiders[k]])
	return " ".join(parts)

func _routes(sim: WorldSim) -> void:
	print("\n== Routes, west to east (goods carried by value of a unit at base price; crossings used)")
	print("  %4s %-6s %-6s %6s %5s %-12s %6s %9s %5s %5s %8s %5s  %s" % ["id", "from", "to", "length", "hours", "crossings", "trips", "value", "ambus", "taken", "lost", "beast", "goods / raiders"])
	var rows: Array = sim.routes.duplicate()
	rows.sort_custom(func(a, b): return _west(sim, a) < _west(sim, b) or (_west(sim, a) == _west(sim, b) and a.id < b.id))
	for r in rows:
		if r.has("trail") and not sim.ledger.has(r.id):
			continue
		var row: Dictionary = sim.ledger.get(r.id, {})
		print("  %4d %-6s %-6s %6d %5d %-12s %6d %9d %5d %5d %8d %5d  %s  %s" % [r.id, _biome(sim, r.a), _biome(sim, r.b), int(r.length), int(sim.route_hours[r.id]),
			_cross(r), row.get("trips", 0), int(row.get("value", 0.0)), row.get("ambushes", 0), row.get("taken", 0), int(row.get("lost", 0.0)), row.get("beasts", 0), _goods(row), _raiders(row)])

func _west(sim: WorldSim, r: Dictionary) -> float:
	return minf(sim.site_by_id[r.a].x, sim.site_by_id[r.b].x)

func _flows(sim: WorldSim) -> void:
	var keys: Array = sim.flows.keys()
	keys.sort_custom(func(a, b): return float(sim.flows[a][1]) > float(sim.flows[b][1]))
	print("\n== Flows of goods between biomes, the top 24 by value (of %d)" % keys.size())
	print("  %-9s %-10s %-10s %9s %10s %7s  %s" % ["good", "from", "to", "units", "value", "a unit", "crossed"])
	for k in keys.slice(0, 24):
		var p: PackedStringArray = str(k).split("|")
		var f: Array = sim.flows[k]
		print("  %-9s %-10s %-10s %9d %10d %7.2f  %s" % [p[0], p[1], p[2], f[0], int(f[1]), float(f[1]) / maxf(f[0], 1), p[3] if p[3] != "" else "-"])

func _compare(sim: WorldSim, days: int) -> void:
	var over := {"value": 0.0, "n": 0, "units": 0}
	var unlike := 0.0
	var all := 0.0
	for k in sim.flows:
		var p: PackedStringArray = str(k).split("|")
		var f: Array = sim.flows[k]
		all += float(f[1])
		if p[3] != "":
			over.value += float(f[1])
			over.units += int(f[0])
		if p[1] != p[2]:
			unlike += float(f[1])
	var shares := SimHealth.route_shares(sim)
	print("\n== Barrier roads against flat roads")
	for kind in ["pass", "river", "flat"]:
		var r: Dictionary = shares[kind]
		var nr := maxf(r.routes, 1.0)
		print("  %-6s %2d roads: each %9d coin in %5d trips (%4d coin a trip), %5.1f ambushes, %5.1f lost, %4.1f lair attacks" % [kind, r.routes, int(r.value / nr), int(r.trips / nr),
			int(r.value / maxf(r.trips, 1.0)), r.ambushes / nr, r.taken / nr, r.beasts / nr])
	var trips := int(sim.stats.get("caravans_sent", 0))
	var ambushes := int(sim.stats.get("ambushes", 0))
	print("\n== In a line: %d caravans in %d days; %d%% of the coin carried crossed a barrier, %d%% moved between unlike biomes; %d ambushes, %d caravans lost." % [
		trips, days, roundi(100.0 * over.value / maxf(all, 1.0)), roundi(100.0 * unlike / maxf(all, 1.0)), ambushes, int(sim.stats.get("caravans_lost", 0))])
