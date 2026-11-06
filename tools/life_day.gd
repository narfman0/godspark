## A day in the life (headless): on a generated world a scripted player stands in the spawn
## town for a game day, then walks the road to the next settlement. Prints what appeared
## when (people by role, guards, caravans, raiders, fights and their outcome) and the sim's
## books for both towns before and after, with what explains the difference.
##   godot --headless -s res://tools/life_day.gd -- seed=3 [cheats=1] [director=0] [perf=1]
## cheats=1 (default) sends a caravan to the town in the morning and a raid in the evening,
## so a single day has both; the sim's own parties show up too. perf=1 also measures the
## host tick with the town full, a caravan and a raid on screen and two players.
extends SceneTree

var host: WorldHost
var life: LifeSystem
var p: HostEntity
var seen_people := {}
var seen_parties := {}
var stats0 := {}
var chron0 := 0
var tick_us: Array = []
var debug := false

func _initialize() -> void:
	var o := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		o[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var seed_v := int(o.get("seed", "3"))
	debug = o.get("debug", "0") == "1"
	var w := WorldGen.generate(1024, 512, seed_v)
	host = WorldHost.new(w)
	Systems.install_host(host)
	life = host.system(HostSystem.LIFE)
	var ms: MonstersSystem = host.system(HostSystem.MONSTERS)
	ms.director_enabled = int(o.get("director", "0"))
	var home := _spawn_town()
	if host.sim == null or home < 0:
		print("no sim or no town")
		quit(1)
		return
	var next := _neighbour(home)
	p = host.add_player("walker", 2, {"class": "fighter"})
	p.combatant.stats.max_hp = 9999
	p.combatant.stats.current_hp = 9999
	_to(LifeTown.site_pos(host, home) + Vector2(0, 3))
	print("== seed %d: %s (%s, %s, %s) and %s; %s" % [seed_v, _name(home), host.sim.settlements[home].culture,
		host.sim.settlements[home].tier, host.sim.faction_name(host.sim.settlements[home].faction), _name(next) if next >= 0 else "-",
		WorldClock.describe(host.clock.hours())])
	_books("before", [home, next])
	chron0 = host.sim.chronicle.size()
	stats0 = life.stats.duplicate()
	var cheats: bool = o.get("cheats", "1") != "0"
	# the day in the spawn town, hour by hour: 10 real seconds watched, then the rest of the hour
	for hour in 24:
		if cheats and hour == 1 and next >= 0:
			var c := life.cheat_party("caravan", next, home, 0.97)
			print("  [cheat] a caravan from %s is %s" % [_name(next), "on the road" if c > 0 else "not sent (no road)"])
		if cheats and hour == 12 and next >= 0:
			var r := life.cheat_party("raid", next, home, 0.99, 6)
			print("  [cheat] raiders from %s are near" % _name(next) if r > 0 else "  [cheat] no raid (no road)")
		_run(600)
		_report(home)
		host.sleep(1.0 - 600.0 / WorldClock.TICKS_PER_HOUR)
		_catch_up()
	# then walk the road to the next settlement
	if next >= 0:
		var rid := host.sim.route_id(home, next)
		if rid < 0:
			var path := host.sim.path_between(home, next, WorldSim.ROAD | WorldSim.DEEP | WorldSim.LINK)
			rid = host.sim.route_id(path[0], path[1]) if path.size() >= 2 else -1
		print("-- %s: walking %s to %s" % [WorldClock.describe(host.clock.hours()), host.sim.route_name(rid), _name(next)])
		var r: Dictionary = host.sim.route_by_id.get(rid, {})
		var forward := int(r.get("a", home)) == home
		for k in 11:
			var tt := float(k) / 10.0
			var raw := life.road.route_pos(host, rid, tt if forward else 1.0 - tt)
			var at := life.road.ground(host, raw)
			if k == 10:
				at = LifeTown.site_pos(host, next) + Vector2(0, 3)
			_to(at if at != Vector2.INF else raw)
			_run(300)
			_report(next if k >= 8 else home)
	print("  walker at %s; %s at %s, materialized %s" % [p.body.pos, _name(next), LifeTown.site_pos(host, next), life.town.active.has(next)])
	_books("after", [home, next])
	_explain()
	if o.get("perf", "0") == "1":
		_perf(home, next)
	quit(0)

func _spawn_town() -> int:
	var sp := host.spawn
	var best := -1
	var bd := INF
	for sid: int in WorldSim._sorted_keys(host.sim.settlements):
		var s: SimSettlement = host.sim.settlements[sid]
		var d := absf(s.x - sp.x) + (0.0 if s.band == "surface" else 4096.0)
		if d < bd:
			bd = d
			best = sid
	return best

func _neighbour(sid: int) -> int:
	var best := -1
	for o: int in WorldSim._sorted_keys(host.sim.settlements):
		if o == sid or host.sim.path_between(sid, o, WorldSim.ROAD | WorldSim.DEEP | WorldSim.LINK).is_empty():
			continue
		if best < 0 or absf(host.sim.settlements[o].x - host.sim.settlements[sid].x) < absf(host.sim.settlements[best].x - host.sim.settlements[sid].x):
			best = o
	return best

func _name(sid: int) -> String:
	return host.sim.settlements[sid].name if host.sim.settlements.has(sid) else "site %d" % sid

func _to(pos: Vector2) -> void:
	p.body.pos = pos
	TileCollision.depenetrate(host.world, p.body)

func _run(n: int) -> void:
	for i in n:
		p.combatant.stats.current_hp = maxi(p.combatant.stats.current_hp, 9000)
		var t0 := Time.get_ticks_usec()
		host.tick()
		tick_us.append(Time.get_ticks_usec() - t0)
		host.outbox.clear()

func _catch_up() -> void:
	var g := 0
	while host.sim_behind() > 0 and g < 5000:
		host.tick()
		host.outbox.clear()
		g += 1

func _report(sid: int) -> void:
	var bits: Array = []
	var roles := {}
	var where := {}
	for e: HostEntity in life.actors_at(sid):
		var r := String(e.get_meta("sim")["role"])
		roles[r] = int(roles.get(r, 0)) + 1
		if not seen_people.has(e.id):
			seen_people[e.id] = true
		if e.brain is LifeBrain and not (e.brain as LifeBrain).fighter:
			var b: LifeBrain = e.brain
			var k := "running" if b.alarmed_until > b._t else ("at work" if b.post_span == 2.0 else ("in the square" if b.post_span == 5.0 else "at home"))
			where[k] = int(where.get(k, 0)) + 1
	if not roles.is_empty():
		bits.append("%s: %s; townsfolk %s" % [_name(sid), _fmt(roles), _fmt(where)])
	for pid: int in life.road.active:
		var sp: SimParty = host.sim.parties.get(pid)
		var n := life.actors_of(pid).filter(func(e: HostEntity) -> bool: return not e.look.get("wagon", false)).size()
		if sp == null:
			continue
		var tag := "%s %d of %s" % [sp.kind, pid, host.sim.faction_name(sp.faction) if sp.faction >= 0 else sp.culture]
		if not seen_parties.has(pid):
			seen_parties[pid] = true
			tag = "NEW " + tag
		var rr: Dictionary = life.road.active[pid]
		if debug:
			print("    debug party %d: hold %s arrival %s raid %s blow %s calm %s leg %d/%d frac %.3f state %s" % [pid, rr["hold"], rr["arrival"],
				not (rr["raid"] as Dictionary).is_empty(), rr.get("blow", "-"), rr.get("calm_until", "-"), sp.leg, sp.path.size(), sp.frac, sp.state])
		var st := "fighting" if sp.frozen else ("going home" if String(sp.plan.get("leg", "")) == "home" else "travelling")
		bits.append("%s: %d of %d shown%s, %s%s" % [tag, n, sp.size(), " with %d wagon(s)" % sp.wagons if sp.wagons > 0 else "", st,
			", cargo " + str(sp.cargo) if not sp.cargo.is_empty() else ""])
	var d := {}
	for k: String in ["town_deaths", "party_deaths", "clashes", "ambushes_done", "raids", "raids_done", "raids_stopped", "raids_stalled", "dropped"]:
		var v := int(life.stats.get(k, 0)) - int(stats0.get(k, 0))
		if v != 0:
			d[k] = v
	if not d.is_empty():
		bits.append("so far " + _fmt(d))
	print("  %s  %s" % [WorldClock.describe(host.clock.hours()).substr(7), " | ".join(bits)])
	for i in range(chron0, host.sim.chronicle.size()):
		print("      chronicle: " + host.sim.describe(host.sim.chronicle[i]))
	chron0 = host.sim.chronicle.size()

static func _fmt(d: Dictionary) -> String:
	var out: Array = []
	for k: String in WorldSim._sorted_keys(d):
		out.append("%s %s" % [d[k], k])
	return ", ".join(out)

var _book := {}

func _books(label: String, sids: Array) -> void:
	for sid: int in sids:
		if sid < 0:
			continue
		if not host.sim.settlements.has(sid):
			print("  books %s: %s is gone" % [label, _name(sid)])
			continue
		var s: SimSettlement = host.sim.settlements[sid]
		var stock := []
		for g: String in WorldSim._sorted_keys(s.stock):
			stock.append("%s %.0f" % [g, s.stock[g]])
		print("  books %s: %s pop %d (workers %d, dependants %d, soldiers %d = %s), %s, coin %.0f" % [label, s.name, s.pop(),
			s.workers, s.dependants, s.soldiers, s.garrison(), ", ".join(stock), s.wealth])
		_book["%s:%d" % [label, sid]] = {"pop": s.pop(), "soldiers": s.soldiers, "wealth": s.wealth}

func _explain() -> void:
	var deaths := int(life.stats["town_deaths"]) - int(stats0.get("town_deaths", 0))
	print("  real-time deaths written back: town %d, parties %d; shown %d people, %d parties; holds %d" % [deaths,
		int(life.stats["party_deaths"]) - int(stats0.get("party_deaths", 0)), seen_people.size(), seen_parties.size(),
		int(life.stats.get("holds", 0))])
	print("  audit: %s" % [host.sim.audit()])

## Tick cost with a full town, a caravan and a raid on screen and two players.
func _perf(home: int, next: int) -> void:
	var q := host.add_player("second", 3, {"class": "wizard"})
	q.combatant.stats.max_hp = 9999
	q.combatant.stats.current_hp = 9999
	var s: SimSettlement = host.sim.settlements[home]
	s.workers = maxi(s.workers, 2500)
	s.soldiers = maxi(s.soldiers, 120)
	s.tier = "city"
	_to(LifeTown.site_pos(host, home) + Vector2(0, 3))
	q.body.pos = p.body.pos + Vector2(6, 0)
	TileCollision.depenetrate(host.world, q.body)
	var c := life.cheat_party("caravan", next, home, 0.95, 10)
	_run(130)
	var r := life.cheat_party("raid", next, home, 0.8, 10)
	_run(70)
	print("PERF raid %d materialized %s with %d shown" % [r, life.road.active.has(r), life.actors_of(r).size()])
	tick_us.clear()
	_run(1800)
	var raid_left := life.actors_of(r).size()
	var sorted := tick_us.duplicate()
	sorted.sort()
	var sum := 0
	for u: int in sorted:
		sum += u
	var n := 0
	for e: HostEntity in host.entities.values():
		if not e.is_player():
			n += 1
	print("PERF %d actors (town %d, caravan %d, raid %d), 2 players: tick avg %.2f ms, p99 %.2f ms, max %.2f ms" % [n,
		life.actors_at(home).size(), life.actors_of(c).size(), raid_left, float(sum) / sorted.size() / 1000.0,
		sorted[floori(sorted.size() * 0.99)] / 1000.0, sorted[-1] / 1000.0])
	# snapshot bytes for a player in the busy town (entity records in view)
	var in_view := 0
	for e: HostEntity in host.entities.values():
		if e != p and absf(e.body.pos.x - p.body.pos.x) <= 96 and absf(e.body.pos.y - p.body.pos.y) <= 96:
			in_view += 1
	print("PERF snapshot: %d entities in the player's interest area -> about %d B per snapshot (6 + 17 each)" % [in_view, 6 + 17 * in_view])
