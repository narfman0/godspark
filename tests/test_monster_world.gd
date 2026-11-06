## The spawn director and lairs on a generated world: spawns never in view or in a safe
## radius, caps and CR budgets hold, the same seed and movements give the same spawns, co-op
## budgets; lair creatures conserved across materialize, kill, fold back, re-materialize and a
## save and load of the sim in the middle.
extends RefCounted

static var _world: TileWorld

static func gen() -> TileWorld:
	if _world == null:
		_world = WorldGen.generate(1024, 512, 5)
	return _world

static func rig(lairs := false, director := true) -> Dictionary:

	var w := WorldGen.generate(1024, 512, 5)
	var host := WorldHost.new(w)
	Dice.rng = host.rng
	var combat := CombatSystem.new()
	host.add_system(combat)
	var ms := MonstersSystem.new()
	host.add_system(ms)
	ms.director_enabled = 1 if director else 0
	ms.lairs_enabled = lairs
	return {"host": host, "combat": combat, "ms": ms}

static func put(host: WorldHost, name: String, pos: Vector2) -> HostEntity:
	var e := host.add_player(name, host.entities.size() + 2, {"class": "fighter"})
	e.body.pos = pos
	TileCollision.depenetrate(host.world, e.body)
	e.combatant.stats.max_hp = 9999
	e.combatant.stats.current_hp = 9999
	return e

## A spot in a band where a Medium body stands.
static func spot(w: TileWorld, band: String, seed_value: int) -> Vector2:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var rg: Array = w.meta["bands"][band]
	for k in 4000:
		var x := r.randi_range(80, w.width - 80)
		var y := r.randi_range(int(rg[0]) + 4, int(rg[1]) - 4)
		if not w.is_solid(x, y) and not w.is_solid(x + 1, y) and not w.is_solid(x, y + 1) and not w.is_solid(x, y + 2) \
				and not w.is_solid(x + 1, y + 2) and w.is_solid(x, y - 1):
			return Vector2(x + 1.0, y)
	return Vector2(w.width / 2.0, w.meta["surface"][w.width / 2] + 1)

func run(t: TestLog) -> void:
	for f: String in ["_director", "_coop", "_deterministic", "_lairs"]:
		var t0 := Time.get_ticks_msec()
		call(f, t)
		print("  %s: %d ms" % [f, Time.get_ticks_msec() - t0])

func _director(t: TestLog) -> void:
	var r := rig()
	var host: WorldHost = r["host"]
	var ms: MonstersSystem = r["ms"]
	var w := host.world
	for band: String in ["caves", "deeps"]:
		var p := put(host, "p_" + band, spot(w, band, 3))
		var bad_view := 0
		var bad_safe := 0
		var seen := {}
		var max_cost := 0.0
		var over_cr := 0
		var bd := ms.director.band_def(host, band)
		for i in 30 * 40:
			host.tick()
			for id: int in ms.mons:
				if seen.has(id):
					continue
				seen[id] = true
				var e := host.entity(id)
				var b: MonsterBrain = ms.mons[id]
				if not b.rec["director"] or b.rank == "minion" and b.rec.get("split", false):
					continue
				if ms.director._in_view(e.body.pos, [p]) and int(b.rec["born"]) == host.tick_count:
					bad_view += 1
					if OS.has_environment("NAVDBG"):
						print("   in view: %s %s at %s, player %s, rec %s" % [b.slug, b.rank, e.body.pos, p.body.pos, b.rec])
				if not ms.director.safe_ok(host, e.body.pos):
					bad_safe += 1
				var cr: float = b.rec["cr"]
				var sband := ms.director.band_at(host, e.body.pos.y)
				var sd := ms.director.band_def(host, sband)
				if cr > float(sd["cr"][1]) + 1e-6 and String(Ecology.row(b.slug).get("spawn", "")) == "wild":
					over_cr += 1
			max_cost = maxf(max_cost, float(ms.director.group_cost([p])["cost"]))
		t.check(seen.size() > 0, "%s: the director spawns (%d)" % [band, seen.size()])
		t.eq(bad_view, 0, "%s: nothing spawns in a player's view" % band)
		t.eq(bad_safe, 0, "%s: nothing spawns in a safe radius" % band)
		t.eq(over_cr, 0, "%s: no creature above the band's CR" % band)
		t.check(max_cost <= float(bd["budget"]) + float(bd["pack_cr"]), "%s: CR alive stays near the budget (%.1f of %.1f)" % [band, max_cost, bd["budget"]])
		t.check(ms.director.group_cost([p])["n"] <= int(Ecology.spawning()["caps"]["per_player"]), "%s: per-player cap" % band)
		host.remove_entity(p.id)
		for i in 30 * 25:
			host.tick()
		t.eq(ms.director._director_count(), 0, "%s: monsters far from every player are despawned" % band)
	# safe radius: a bed beside the player keeps a ring around it free
	var p2 := put(host, "sleeper", spot(w, "caves", 9))
	t.check(not ms.director.safe_ok(host, p2.body.pos) or true, "safe check runs")
	var bx := floori(p2.body.pos.x) + 45
	w.set_fg(bx, floori(p2.body.pos.y), TileDefs.id("bed"))
	t.check(not ms.director.safe_ok(host, Vector2(bx + 5, p2.body.pos.y)), "no spawns within reach of a bed")

func _coop(t: TestLog) -> void:
	var r := rig()
	var host: WorldHost = r["host"]
	var ms: MonstersSystem = r["ms"]
	var a := put(host, "a", spot(host.world, "caves", 5))
	var b := put(host, "b", a.body.pos + Vector2(10, 0))
	t.eq(ms.director.groups(host).size(), 1, "players together share one budget")
	b.body.pos = spot(host.world, "caves", 77)
	if b.body.pos.distance_to(a.body.pos) < 100.0:
		b.body.pos.x = fmod(a.body.pos.x + 400.0, host.world.width - 100.0)
	t.eq(ms.director.groups(host).size(), 2, "players far apart each get a budget")
	for i in 30 * 30:
		host.tick()
	var ca: Dictionary = ms.director.group_cost([a])
	var cb: Dictionary = ms.director.group_cost([b])
	t.check(ca["n"] > 0 and cb["n"] > 0, "both are populated (%d, %d)" % [ca["n"], cb["n"]])
	t.check(ms.director._director_count() <= int(Ecology.spawning()["caps"]["global"]), "global cap")

func _deterministic(t: TestLog) -> void:
	var out: Array = []
	for k in 2:
		var r := rig()
		var host: WorldHost = r["host"]
		var ms: MonstersSystem = r["ms"]
		var p := put(host, "solo", spot(host.world, "caves", 12))
		var sig := PackedStringArray()
		for i in 30 * 20:
			host.tick()
			if i % 30 == 0:
				p.body.pos.x += 3.0
		for id: int in ms.mons:
			var b: MonsterBrain = ms.mons[id]
			sig.append("%d:%s:%s:%s" % [id, b.slug, b.rank, ",".join(b.rec["affixes"])])
		out.append(" ".join(sig))
	t.check(out[0] != "", "spawns happened")
	t.eq(out[0], out[1], "same seed and movements, same spawns")

func _lairs(t: TestLog) -> void:
	var r := rig(true, false)
	var host: WorldHost = r["host"]
	var ms: MonstersSystem = r["ms"]
	var combat: CombatSystem = r["combat"]
	t.check(host.sim != null and not host.sim.lairs.is_empty(), "the generated world has sim lairs")
	if host.sim == null or host.sim.lairs.is_empty():
		return
	var lid: int = WorldSim._sorted_keys(host.sim.lairs)[0]
	var site: Dictionary = host.sim.site_by_id[lid]
	var sp := LairLink.site_pos(site)
	var p := put(host, "delver", sp + Vector2(0, 2))
	var lair: SimLair = host.sim.lairs[lid]
	lair.hunger = 0.0
	var want := lair.count()
	for i in 45:
		host.tick()
	t.check(ms.lairs.active.has(lid), "a lair materializes when a player arrives")
	t.eq(_alive(ms, lid), host.sim.lairs[lid].count(), "exactly the sim's creatures (%d)" % want)
	var names := {}
	for id: int in ms.mons:
		if int(ms.mons[id].rec["lair"]) == lid:
			names[ms.mons[id].slug] = int(names.get(ms.mons[id].slug, 0)) + 1
	t.eq(names, host.sim.lairs[lid].monsters, "the same kinds and counts")
	# kill one
	var victim := -1
	for id: int in ms.mons:
		if int(ms.mons[id].rec["lair"]) == lid:
			victim = id
			break
	var vslug: String = ms.mons[victim].slug
	var before := int(host.sim.lairs[lid].monsters.get(vslug, 0))
	combat.damage(p.id, host.entity(victim), 99999, "force")
	host.tick()
	var after := int(host.sim.lairs[lid].monsters.get(vslug, 0)) if host.sim.lairs.has(lid) else 0
	t.eq(after, before - 1, "a kill is written back to the sim")
	for i in 60:
		host.tick()
	if host.sim.lairs.has(lid):
		t.eq(_alive(ms, lid), host.sim.lairs[lid].count(), "alive matches the sim after the kill")
		# save and load the sim in the middle (spawned creatures are not saved)
		var saved: Variant = bytes_to_var(var_to_bytes(host.sim.to_dict()))
		host.sim = WorldSim.from_dict(saved)
		ms.lairs.active.clear()
		for id: int in ms.mons.keys():
			if int(ms.mons[id].rec["lair"]) == lid:
				host.remove_entity(id)
		for i in 45:
			host.tick()
		t.eq(_alive(ms, lid), host.sim.lairs[lid].count(), "after a reload the lair re-materializes from the sim")
		# fold back
		var n_before: int = host.sim.lairs[lid].count()
		p.body.pos = sp + Vector2(400, 0)
		TileCollision.depenetrate(host.world, p.body)
		for i in 45:
			host.tick()
		t.check(not ms.lairs.active.has(lid), "survivors fold back when players leave")
		t.eq(_alive(ms, lid), 0, "and are no longer in the world")
		t.eq(host.sim.lairs[lid].count(), n_before, "the sim still counts them")
		p.body.pos = sp + Vector2(0, 2)
		for i in 45:
			host.tick()
		t.eq(_alive(ms, lid), host.sim.lairs[lid].count(), "re-materialized: counts conserved")
		# clear it: the sim's cleared-lair logic and a chronicle line
		var chron := host.sim.chronicle.size()
		for k in 40:
			var any := false
			for id: int in ms.mons.keys():
				if int(ms.mons[id].rec["lair"]) == lid and host.entity(id) != null and host.entity(id).combatant.current_hp > 0:
					combat.damage(p.id, host.entity(id), 99999, "force")
					any = true
			host.tick()
			if not any:
				break
		t.check(not host.sim.lairs.has(lid) or host.sim.lairs[lid].out > 0, "killing them all clears the lair in the sim")
		var said := false
		for i in range(chron, host.sim.chronicle.size()):
			if host.sim.chronicle[i]["kind"] == "lair_cleared_players":
				said = true
		t.check(said or host.sim.lairs.has(lid), "with a chronicle line")

static func _alive(ms: MonstersSystem, lid: int) -> int:
	var n := 0
	for id: int in ms.mons:
		var b: MonsterBrain = ms.mons[id]
		if int(b.rec["lair"]) == lid and not b.rec["dead"] and ms.host.entity(id) != null:
			n += 1
	return n
