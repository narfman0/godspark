## A long soak: a host on a generated world with everything on (spawn director, Life, Deals,
## the places keeper, the sim), two scripted players wandering between towns along the routes,
## walking at run speed, talking, trading and taking work at random, hitting what comes near.
## Real ticks, no clients (their bodies are moved along the route cells by the script), at
## K.TICK_HZ of host time: a game day is K.DAY_SECONDS of host time.
##   godot --headless -s res://tools/soak.gd -- [days=3] [seed=3] [size=2048x1024]
## Reports script errors, tick times (and what the worst was doing), memory growth, entities
## over time, the sim's audit, what is materialized against the sim's books, chronicle lines,
## and quests offered, taken, completed, lapsed. Exit 1 on script errors or a dirty audit.
extends SceneTree

class ScriptErrors extends Logger:
	var count := 0
	var first := ""
	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _backtrace: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_SCRIPT:
			count += 1
			if first == "":
				first = "%s:%d %s: %s %s" % [file, line, function, code, rationale]

const RUN_SPEED := 8.0

var rng := RandomNumberGenerator.new()
var host: WorldHost
var errors := ScriptErrors.new()
## per player: {e, sid, path, i, f, wait}
var walkers: Array = []
var routes_at := {}
var seen_offers := {}
var counts := {"talks": 0, "buys": 0, "sells": 0, "takes": 0, "turnins": 0, "legs": 0, "swings": 0}

func _initialize() -> void:
	await process_frame
	OS.add_logger(errors)
	var o := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		o[kv[0]] = kv[1] if kv.size() > 1 else ""
	var days := float(o.get("days", 3))
	var sz := String(o.get("size", "2048x1024")).split("x")
	var world_seed := int(o.get("seed", 3))
	rng.seed = world_seed
	var t0 := Time.get_ticks_msec()
	var w := WorldGen.generate(int(sz[0]), int(sz[1]), world_seed)
	print("SOAK world %sx%s seed %d in %d ms" % [sz[0], sz[1], world_seed, Time.get_ticks_msec() - t0])
	host = WorldHost.new(w)
	Systems.install_host(host)
	host.profile = true
	_routes()
	for i in 2:
		var e := host.add_player("soak%d" % i, i + 2, {"class": ["fighter", "cleric"][i]})
		e.character.inventory.coin = 2000
		_tough(e)
		var sid := _start_site(i)
		e.body.pos = LifeTown.site_pos(host, sid) + Vector2(i * 2, 0)
		TileCollision.depenetrate(host.world, e.body)
		walkers.append({"e": e, "sid": sid, "path": [], "i": 0, "f": 0.0, "wait": 2.0 + i})
	var ticks := int(days * K.DAY_SECONDS * K.TICK_HZ)
	var us := PackedInt32Array()
	us.resize(ticks)
	var worst := 0
	var worst_what := ""
	var mem0 := Performance.get_monitor(Performance.MEMORY_STATIC)
	var hourly := int(K.DAY_SECONDS * K.TICK_HZ / 6.0)
	var quiet := true
	print("SOAK %d ticks (%.1f game days)" % [ticks, days])
	for t in ticks:
		_script_step()
		var a := Time.get_ticks_usec()
		host.tick()
		var d := Time.get_ticks_usec() - a
		us[t] = d
		if d > worst and t > 300:
			worst = d
			worst_what = "tick %d: %s; sim stepped %s; entities %d" % [t, _sys_times(), str(host.sim_usec.size() > 0 and host.sim_usec[host.sim_usec.size() - 1]), host.entities.size()]
		if t % hourly == 0:
			_report(t)
		if t % 3000 == 0:
			quiet = _books() and quiet
	us.sort()
	var sum := 0
	for x: int in us:
		sum += x
	var mem1 := Performance.get_monitor(Performance.MEMORY_STATIC)
	var audit := host.sim.audit()
	var deals: DealsSystem = host.system(HostSystem.DEALS)
	var life: LifeSystem = host.system(HostSystem.LIFE)
	print("SOAK tick avg %.2f ms, p99 %.2f ms, max %.2f ms (budget %.1f ms)" % [sum / float(ticks) / 1000.0, us[int(ticks * 0.99)] / 1000.0, us[ticks - 1] / 1000.0, 1000.0 / K.TICK_HZ])
	print("SOAK worst %s" % worst_what)
	print("SOAK memory static %.1f -> %.1f MB" % [mem0 / 1048576.0, mem1 / 1048576.0])
	print("SOAK chronicle %d lines, sim day %d" % [host.sim.chronicle.size(), Deals.day(host.sim)])
	print("SOAK script %s" % [counts])
	print("SOAK offers seen %d" % seen_offers.size())
	print("SOAK deals %s" % deals.summary())
	print("SOAK life %s" % life.summary())
	print("SOAK audit %s" % ("clean" if audit.is_empty() else str(audit)))
	print("SOAK books %s" % ("matched at every check" if quiet else "MISMATCH (see above)"))
	print("SOAK script errors %d %s" % [errors.count, errors.first])
	OS.remove_logger(errors)
	quit(0 if errors.count == 0 and audit.is_empty() and quiet else 1)

func _sys_times() -> String:
	var parts := PackedStringArray()
	for k: int in host.sys_usec:
		if int(host.sys_usec[k]) > 500:
			parts.append("sys %d %.1f ms" % [k, int(host.sys_usec[k]) / 1000.0])
	return ", ".join(parts)

func _routes() -> void:
	for r: Dictionary in host.world.meta.get("routes", []):
		var path := Places.route_path(host.world, int(r["id"]))
		if path.size() < 3:
			continue
		for s: int in [int(r["a"]), int(r["b"])]:
			if not routes_at.has(s):
				routes_at[s] = []
			routes_at[s].append({"to": int(r["b"]) if s == int(r["a"]) else int(r["a"]), "path": path, "forward": s == int(r["a"])})

func _start_site(i: int) -> int:
	var towns: Array = []
	for sid: int in WorldSim._sorted_keys(host.sim.settlements):
		if routes_at.has(sid) and (host.sim.settlements[sid] as SimSettlement).band == "surface":
			towns.append(sid)
	return towns[i % towns.size()] if not towns.is_empty() else WorldSim._sorted_keys(host.sim.settlements)[0]

static func _tough(e: HostEntity) -> void:
	e.combatant.stats.max_hp = 5000
	e.combatant.stats.current_hp = 5000

func _script_step() -> void:
	var dt := 1.0 / K.TICK_HZ
	for w: Dictionary in walkers:
		var e: HostEntity = w["e"]
		_tough(e)
		var rules := host.system(HostSystem.RULES) as RulesSystem
		if rules.is_downed(e):
			continue
		_swing(e)
		if (w["path"] as Array).is_empty():
			w["wait"] = float(w["wait"]) - dt
			if float(w["wait"]) <= 0.0:
				_at_site(w)
			continue
		var path: Array = w["path"]
		w["f"] = float(w["f"]) + RUN_SPEED * dt
		var k := int(w["f"])
		if k >= path.size() - 1:
			w["sid"] = int(w["to"])
			w["path"] = []
			w["wait"] = 3.0
			counts["legs"] += 1
			continue
		var c: Vector2i = path[k]
		host.teleport(e, Vector2(c.x + 0.5, c.y))

## Hit whatever hostile is in reach, as a player would, now and then.
func _swing(e: HostEntity) -> void:
	if host.tick_count % 20 != int(e.id) % 20:
		return
	var combat := host.system(HostSystem.COMBAT) as CombatSystem
	var life := host.system(HostSystem.LIFE) as LifeSystem
	for m: HostEntity in host.entities.values():
		if m.is_player() or m.body == null or m.body.pos.distance_to(e.body.pos) > 3.0:
			continue
		if life.stance(e, m) == Life.HOSTILE:
			if combat.start_attack(e, -1, m.body.rect().get_center(), false):
				counts["swings"] += 1
			return

## At a town: speak to a few of the people, trade, take and hand in work, then pick a road.
func _at_site(w: Dictionary) -> void:
	var e: HostEntity = w["e"]
	var sid := int(w["sid"])
	var deals: DealsSystem = host.system(HostSystem.DEALS)
	var life: LifeSystem = host.system(HostSystem.LIFE)
	var shown := life.actors_at(sid)
	var inv := e.character.inventory
	for x: HostEntity in shown:
		if rng.randf() > 0.25 or not bool(x.get_meta("talk", false)):
			continue
		e.body.pos = x.body.pos + Vector2(1.2, 0.0)
		if deals.talk(e, x.id) != "":
			continue
		counts["talks"] += 1
		var t: Dictionary = deals.talks.get(e.id, {})
		for op: Dictionary in deals.options(e, t):
			var id := String(op["id"])
			if id.begins_with("turn_in:"):
				if deals.choose(e, id) == "":
					counts["turnins"] += 1
			elif id == "rumours" or (id in ["shop", "smith"] and rng.randf() < 0.7):
				deals.choose(e, id)
				if id != "rumours":
					_trade(e, sid)
			elif id == "quests" and rng.randf() < 0.8:
				deals.choose(e, id)
				for q: Dictionary in deals._offers_by(sid, String(t["role"]), e):
					seen_offers[String(q["id"])] = true
					if rng.randf() < 0.6 and deals.accept(e, String(q["id"])) == "":
						counts["takes"] += 1
			elif id == "patron":
				deals.choose(e, id)
		deals._close(e.id, "left")
	if inv.coin < 200:
		inv.coin += 1000
	var ways: Array = routes_at.get(sid, [])
	if ways.is_empty():
		w["wait"] = 30.0
		# no stored route from here: go back to any settlement that has one
		var back := _start_site(rng.randi_range(0, 3))
		w["sid"] = back
		host.teleport(e, LifeTown.site_pos(host, back))
		return
	var r: Dictionary = ways[rng.randi_range(0, ways.size() - 1)]
	var p: Array = (r["path"] as Array).duplicate()
	if not bool(r["forward"]):
		p.reverse()
	w["path"] = p
	w["to"] = int(r["to"])
	w["f"] = 0.0

func _trade(e: HostEntity, sid: int) -> void:
	var deals: DealsSystem = host.system(HostSystem.DEALS)
	var kind := String(deals.talks[e.id].get("shop", ""))
	var list := deals.listings(e, sid, kind)
	if not list.is_empty() and rng.randf() < 0.6:
		var l: Dictionary = list[rng.randi_range(0, list.size() - 1)]
		if int(l["n"]) > 0 and deals.buy(e, String(l["id"]), 1) == "":
			counts["buys"] += 1
	var inv := e.character.inventory
	for i in Inventory.SIZE:
		if not inv.at(i).is_empty() and rng.randf() < 0.1 and deals.sell(e, i, 1) == "":
			counts["sells"] += 1

## Shown people never exceed the books: guards vs soldiers, members vs the party.
func _books() -> bool:
	var life: LifeSystem = host.system(HostSystem.LIFE)
	var ok := true
	for sid: int in life.town.active:
		var s: SimSettlement = host.sim.settlements.get(sid)
		if s == null:
			continue
		var guards := 0
		var folk := 0
		for e: HostEntity in life.actors_at(sid):
			if String(e.get_meta("sim")["role"]) == "guard":
				guards += 1
			else:
				folk += 1
		if guards > s.soldiers or folk > s.workers + s.dependants:
			print("SOAK BOOKS %s shows %d guards of %d, %d folk of %d" % [s.name, guards, s.soldiers, folk, s.workers + s.dependants])
			ok = false
	for pid: int in life.road.active:
		var p: SimParty = host.sim.parties.get(pid)
		if p != null and (life.road.active[pid]["ids"] as Dictionary).size() > p.size():
			print("SOAK BOOKS party %d shows %d of %d" % [pid, (life.road.active[pid]["ids"] as Dictionary).size(), p.size()])
			ok = false
	return ok

func _report(t: int) -> void:
	var ms: MonstersSystem = host.system(HostSystem.MONSTERS)
	var life: LifeSystem = host.system(HostSystem.LIFE)
	var items: ItemsSystem = host.system(HostSystem.ITEMS)
	var deals: DealsSystem = host.system(HostSystem.DEALS)
	print("SOAK t=%6.0f s day %d: entities %d (monsters %d, life %d), drops %d, parties %d, quests %d, chronicle %d, mem %.1f MB, audit %d" % [t / float(K.TICK_HZ), Deals.day(host.sim),
		host.entities.size(), ms.mons.size(), life.actors.size(), items.drops.list.size(), host.sim.parties.size(), deals.quests.size(), host.sim.chronicle.size(),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, host.sim.audit().size()])
