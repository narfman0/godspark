## The monsters system (HostSystem.MONSTERS): what makes the world dangerous. It spawns SRD
## monsters with brains (MonsterBrain), ranks (minion, standard, elite, champion, boss) and
## affixes, plans their paths within a per-tick budget (MonsterNav), fills each player's
## surroundings off-screen from the ecology table (SpawnDirector), turns the world sim's lairs
## into real creatures and writes kills back (LairLink), and tells clients each monster's rank,
## affixes and body (MonstersCodec INFO).
##
## For other systems and tools (host thread):
##   sys.spawn(slug, pos, opts := {}) -> HostEntity     opts: rank, affixes, home, pack, slot,
##       brain (archetype), lair, group, combatant (an NPC from make_npc), people (look key),
##       name, scale
##   sys.request_plan(e, goal, tol)                     brains ask; on_plan(path) answers
##   sys.director_enabled: -1 auto (on for worlds with depth bands), 0 off, 1 on
## Entity meta it sets (Object meta): rank, xp_mult, friendly (neutral creatures). Also
## look.rank, look.scale, look.affixes. Docs: docs/tracks/monsters.md.
class_name MonstersSystem
extends HostSystem

## Microseconds of path search per tick, all monsters together (fair round-robin).
const NAV_BUDGET_US := 800
const NAV_SLICE := 250
const NAV_MAX_EXPAND := 1500
## Ticks between INFO sweeps.
const INFO_EVERY := 10

var host: WorldHost:
	get:
		return _host.get_ref() if _host != null else null
var _host: WeakRef
var rng := RandomNumberGenerator.new()
## id -> MonsterBrain, for every monster this system spawned (kept after death until removal).
var mons := {}
var director: SpawnDirector
var lairs: LairLink
var director_enabled := -1
var lairs_enabled := true
## Tests: plan a fixed number of search slices per tick instead of a time budget, so the same
## inputs give the same paths on any machine and load.
var nav_fixed_slices := 0
var _queue: Array = []           # [{id, goal, tol, search}]
var _dirty: Array[Vector2i] = []
var _known := {}                 # player id -> {monster id: true}
var _gone_out := {}              # player id -> [monster ids]
var _next_pack := 1
## Counters for tests, tools and the track notes.
var stats := {"spawned": 0, "plans": 0, "plan_usec": 0, "plan_fail": 0, "nav_usec": 0, "split": 0,
	"coins": 0, "eaten": 0, "howls": 0, "tether": 0, "thorns": 0, "warded": 0}

func sys_id() -> int:
	return HostSystem.MONSTERS

func attach(h: WorldHost) -> void:
	_host = weakref(h)
	rng.seed = hash([h.world.world_seed, "monsters"])
	director = SpawnDirector.new(self)
	lairs = LairLink.new(self)
	h.world.tile_changed.connect(_on_tile)

func director_on() -> bool:
	if director_enabled >= 0:
		return director_enabled == 1
	return host.world.meta.has("bands")

# --- spawning --------------------------------------------------------------------------------

## An SRD monster with a brain, rank and affixes, standing near pos. Null for an unknown slug.
func spawn(slug: String, pos: Vector2, opts := {}) -> HostEntity:
	var h := host
	var srow: Dictionary = h.srd.pack.get_row("monster", slug)
	if srow.is_empty():
		return null
	var d: Dictionary = srow.get("data", {})
	var eco := Ecology.row(slug)
	var c: Combatant = opts.get("combatant")
	if c == null:
		c = h.srd.make_monster(slug)
	if c == null:
		return null
	var size := String(opts.get("size", WorldHost.monster_size(d)))
	var speeds := WorldHost.monster_speeds(d)
	if opts.has("combatant"):
		# an NPC from make_npc: the species' size and walking speed
		size = String(opts.get("size", c.size))
		speeds["walk"] = c.stats.speed
	var stats := MoveStats.from_srd(speeds, size)
	var rank := String(opts.get("rank", "standard"))
	var affixes: Array = (opts.get("affixes", []) as Array).duplicate()
	_apply_rank(c, slug, rank)
	var arch := String(opts.get("brain", eco.get("brain", "bruiser")))
	# opts.brain_obj: a MonsterBrain subclass made by the caller (Life's people)
	var brain: MonsterBrain = opts["brain_obj"] if opts.get("brain_obj") is MonsterBrain else MonsterBrain.new(arch, Vector2(opts.get("home", pos)))
	brain.slug = slug
	brain.rank = rank
	brain.hostility = String(eco.get("hostility", "hostile"))
	brain.flees = bool(eco.get("flee", false))
	brain.bond_key = String(opts.get("bond", eco.get("bond", "")))
	brain.pack_id = int(opts.get("pack", 0))
	brain.slot = int(opts.get("slot", 0))
	var rd := Ecology.rank_def(rank)
	var scale := float(opts.get("scale", rd.get("scale", 1.0)))
	var name := String(opts.get("name", srow.get("name", slug)))
	var names := PackedStringArray()
	for a: String in affixes:
		names.append(String(Ecology.affixes().get(a, {}).get("name", a)))
	if not names.is_empty():
		name = " ".join(names) + " " + name
	var look := {"kind": "monster", "slug": slug, "name": name, "size": stats.size, "color": Color(0.6, 0.2, 0.2),
		"rank": rank, "scale": scale, "affixes": affixes}
	if opts.has("people"):
		look["people"] = String(opts["people"])
	var rec := {"rank": rank, "affixes": affixes, "lair": int(opts.get("lair", -1)), "group": int(opts.get("group", 0)),
		"dead": false, "born": h.tick_count, "far_t": 0.0, "dig": 0.0, "coins": 0, "howled": false, "cost": 0.0,
		"cr": Ecology.cr_of(h.srd, slug), "ward_max": 0, "calm_t": 0.0, "fx_t": 0.0, "people": String(opts.get("people", "")),
		"leader": bool(opts.get("leader", false)), "director": bool(opts.get("director", false))}
	rec["cost"] = Ecology.cost(rec["cr"]) * float(rd.get("xp_mult", 1.0))
	if float(speeds.get("burrow", 0)) > 0.0:
		rec["dig"] = MonsterNav.ROCK_HARDNESS if float(speeds.get("burrow", 0)) >= 20.0 else MonsterNav.SOFT_HARDNESS
	brain.rec = rec
	if Burrow.is_burrower(slug) and stats.burrow_speed > 0.0:
		# a burrower digs as it moves (Burrow, within its cap), not through the planner
		brain.burrow = Burrow.new(slug, stats)
		rec["dig"] = 0.0
	for a: String in affixes:
		_affix_setup(a, stats, c, rec, brain)
	MonsterNav.profile(stats, float(rec["dig"]))      # its jumps are recorded now, not in the planner
	var e := h.add_monster(stats, pos, brain, look, c)
	e.set_meta("rank", rank)
	e.set_meta("xp_mult", float(rd.get("xp_mult", 1.0)))
	if brain.hostility == "neutral":
		e.set_meta("friendly", true)
	mons[e.id] = brain
	var combat := h.system(HostSystem.COMBAT)
	if "frenzied" in affixes and combat != null and combat.has_method("set_pace"):
		combat.call("set_pace", e, float(Ecology.affixes()["frenzied"].get("pace", 1.5)))
	self.stats["spawned"] += 1
	return e

func new_pack() -> int:
	_next_pack += 1
	return _next_pack

## Hit points by rank: minion 1, elite the hit dice's maximum, champion double that, standard
## and boss as written.
func _apply_rank(c: Combatant, slug: String, rank: String) -> void:
	var how := String(Ecology.rank_def(rank).get("hp", "as_written"))
	var mx := c.stats.max_hp
	match how:
		"one":
			mx = 1
		"max":
			mx = maxi(Ecology.max_hp(host.srd, slug), c.stats.max_hp)
		"max2":
			mx = 2 * maxi(Ecology.max_hp(host.srd, slug), c.stats.max_hp)
	c.stats.max_hp = mx
	c.stats.current_hp = mx

func _affix_setup(a: String, stats: MoveStats, c: Combatant, rec: Dictionary, brain: MonsterBrain) -> void:
	var def: Dictionary = Ecology.affixes().get(a, {})
	match a:
		"shielded":
			var w := maxi(int(def.get("ward_min", 8)), roundi(float(def.get("ward_per_cr", 6)) * maxf(float(rec["cr"]), 1.0)))
			rec["ward_max"] = w
			c.stats.temp_hp = w
		"tunnelling":
			rec["dig"] = maxf(float(rec["dig"]), float(def.get("hardness", 0.6)))
		"skittering":
			stats.run_speed *= float(def.get("move_mult", 1.35))

## Affixes a monster may roll: by archetype and medium.
func affix_pool(slug: String) -> Array:
	var eco := Ecology.row(slug)
	var out: Array = []
	for id: String in Ecology.affixes():
		if id.begins_with("_"):
			continue
		var nf: Array = Ecology.affixes()[id].get("not_for", [])
		if String(eco.get("brain", "")) in nf or String(eco.get("medium", "")) in nf:
			continue
		out.append(id)
	return out

func roll_affixes(slug: String, n: int, r: RandomNumberGenerator) -> Array:
	var pool := affix_pool(slug)
	var out: Array = []
	for i in n:
		if pool.is_empty():
			break
		var k := r.randi_range(0, pool.size() - 1)
		out.append(pool[k])
		pool.remove_at(k)
	return out

# --- paths ------------------------------------------------------------------------------------

func request_plan(e: HostEntity, goal: Vector2, tol: Vector2i) -> void:
	for q: Dictionary in _queue:
		if q["id"] == e.id:
			q["goal"] = goal
			q["tol"] = tol
			q["search"] = null
			return
	_queue.append({"id": e.id, "goal": goal, "tol": tol, "search": null})

func profile_of(e: HostEntity) -> NavProfile:
	var b: Variant = mons.get(e.id)
	var dig := float(b.rec.get("dig", 0.0)) if b != null and b.rec is Dictionary else 0.0
	return MonsterNav.profile(e.stats, dig)

## Work through queued searches within NAV_BUDGET_US, a slice at a time, round-robin.
func _nav_tick() -> void:
	var t0 := Time.get_ticks_usec()
	var h := host
	var guard := 0
	var fixed := nav_fixed_slices > 0
	while not _queue.is_empty() and (fixed or Time.get_ticks_usec() - t0 < NAV_BUDGET_US) and guard < (nav_fixed_slices if fixed else 64):
		guard += 1
		var left0 := NAV_BUDGET_US - (Time.get_ticks_usec() - t0)
		if left0 < 200 and not fixed:
			break
		var q: Dictionary = _queue.pop_front()
		var e := h.entity(int(q["id"]))
		var brain: Variant = mons.get(int(q["id"]))
		if e == null or brain == null or e.brain == null:
			continue
		if q["search"] == null:
			q["search"] = MonsterNav.start(h.world, profile_of(e), e.body.pos, q["goal"], q["tol"], true, NAV_MAX_EXPAND)
			if "max_drop" in brain:
				(q["search"] as NavSearch).max_drop = int(brain.get("max_drop"))
		var s: NavSearch = q["search"]
		var left := NAV_BUDGET_US - (Time.get_ticks_usec() - t0)
		if s.step(NAV_SLICE, 1 << 30 if fixed else maxi(left, 50)):
			stats["plans"] += 1
			stats["plan_usec"] += s.usec
			var p := s.result()
			if p == null:
				stats["plan_fail"] += 1
			brain.on_plan(p)
		else:
			_queue.append(q)
	stats["nav_usec"] += Time.get_ticks_usec() - t0

func _on_tile(x: int, y: int, layer: int, _old: int, _now: int) -> void:
	if layer == TileWorld.Layer.FG and _dirty.size() < 256:
		_dirty.append(Vector2i(x, y))

## Paths through a changed cell are dropped (the brain replans).
func _invalidate() -> void:
	if _dirty.is_empty():
		return
	for id: int in mons:
		var b: MonsterBrain = mons[id]
		if b.follow.path == null:
			continue
		var r := b.follow.path.bounds()
		for c in _dirty:
			if r.has_point(c):
				b.follow.path = null
				break
	_dirty.clear()

# --- tick --------------------------------------------------------------------------------------

func tick(h: WorldHost) -> void:
	_invalidate()
	_nav_tick()
	var dt := h.dt()
	var combat := h.system(HostSystem.COMBAT)
	for id: int in mons.keys():
		var e := h.entity(id)
		var b: MonsterBrain = mons[id]
		if e == null:
			continue
		var rec: Dictionary = b.rec
		if e.combatant != null and e.combatant.current_hp <= 0:
			if not rec["dead"]:
				rec["dead"] = true
				_died(e, b)
			continue
		if not (rec["affixes"] as Array).is_empty():
			Affixes.tick(self, e, b, dt, combat)
	if lairs_enabled and h.sim != null:
		lairs.tick(h, dt)
	if director_on():
		director.tick(h, dt)
	if h.tick_count % INFO_EVERY == 0:
		_send_info(h)

func _died(e: HostEntity, b: MonsterBrain) -> void:
	var rec: Dictionary = b.rec
	director.killed(rec, director.band_at(host, e.body.pos.y), director.is_night(host))
	if int(rec["lair"]) >= 0:
		lairs.killed(e, b)
	if "splitting" in rec["affixes"]:
		Affixes.split(self, e, b)

func entity_removed(h: WorldHost, e: HostEntity) -> void:
	if e.is_player():
		_known.erase(e.id)
		_gone_out.erase(e.id)
		return
	var b: Variant = mons.get(e.id)
	if b == null:
		return
	mons.erase(e.id)
	lairs.removed(e, b)
	for pid: int in _known:
		if (_known[pid] as Dictionary).has(e.id):
			(_known[pid] as Dictionary).erase(e.id)
			if not _gone_out.has(pid):
				_gone_out[pid] = []
			_gone_out[pid].append(e.id)
	for i in range(_queue.size() - 1, -1, -1):
		if _queue[i]["id"] == e.id:
			_queue.remove_at(i)

## Combat's hook: every hit (dealt > 0) or miss (0) a creature takes, before its 0 HP check.
func on_combat_damage(e: HostEntity, dealt: int, src: int) -> void:
	var b: Variant = mons.get(e.id)
	if b == null:
		return
	var h := host
	if src != 0:
		b.provoke(h, e, src)
	if dealt <= 0:
		return
	Affixes.on_damage(self, e, b, dealt, src)

# --- client info ------------------------------------------------------------------------------

func info_of(e: HostEntity, b: MonsterBrain) -> Dictionary:
	var flags := 0
	if b.hostility == "neutral":
		flags |= MonstersCodec.F_NEUTRAL
	if int(b.rec["lair"]) >= 0:
		flags |= MonstersCodec.F_LAIR
	if bool(b.rec.get("leader", false)):
		flags |= MonstersCodec.F_LEADER
	return {"id": e.id, "rank": b.rank, "slug": b.slug, "people": String(b.rec.get("people", "")),
		"scale": float(e.look.get("scale", 1.0)), "flags": flags, "affixes": b.rec["affixes"]}

## Each player gets INFO for monsters entering its interest area, GONE for those removed.
func _send_info(h: WorldHost) -> void:
	var reach := float((Interest.DEFAULT_RADIUS + 1) * K.CHUNK)
	for p: HostEntity in h.entities.values():
		if not p.is_player():
			continue
		if not _known.has(p.id):
			_known[p.id] = {}
		var known: Dictionary = _known[p.id]
		var out: Array = []
		for id: int in mons:
			if known.has(id):
				continue
			var e := h.entity(id)
			if e == null:
				continue
			var d := e.body.pos - p.body.pos
			if absf(d.x) <= reach and absf(d.y) <= reach:
				known[id] = true
				out.append(info_of(e, mons[id]))
				if out.size() >= 200:
					break
		if not out.is_empty():
			h.send_sys(sys_id(), MonstersCodec.Msg.INFO, MonstersCodec.write_info(out), p.id)
		var gone: Array = _gone_out.get(p.id, [])
		if not gone.is_empty():
			h.send_sys(sys_id(), MonstersCodec.Msg.GONE, MonstersCodec.write_gone(gone.slice(0, 255)), p.id)
			_gone_out[p.id] = []

# --- helpers for the director, lairs and affixes ------------------------------------------------

func alive_count() -> int:
	var n := 0
	for id: int in mons:
		if not mons[id].rec["dead"]:
			n += 1
	return n
