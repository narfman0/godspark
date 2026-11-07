## M4 end to end: the living world as one thing. Two players over the loopback on a real
## generated world (dev seed 4, all five biomes: a human meadow town at the game's spawn and
## another across a ford, the road between them, holds in the deeps, lairs in the caves) with
## every system installed. They arrive in a town (arrival
## notice, people at their posts), talk to a merchant, buy and sell (the town's books move by
## exactly what changed hands), hear a rumour whose place is on the mirrored map, then take
## each kind of work and complete it by doing it: a message walked along the road and back, a
## bounty killed with real attacks (the sim's lair shrinks), a caravan escorted the length of
## its road through a forced ambush (it arrives with most of its people and cargo; the far
## town's stock grows), a raid met at the gate with the guards (the sim records it repelled),
## food bought in one town and carried to the hungry one, and stolen cargo cut from raiders on
## the road and brought back. Cheats only set the scene (a caravan, a raid, a famine, raiders
## with cargo, the players' strength, where a lair's creatures stand); everything that
## completes work is play. Then a patron's gift, save, stop, load, rejoin, and everything came
## back; the sim's audit is clean and host and clients agree. Each failure this test found was
## an integration bug (docs/tracks/m4-integration.md, docs/tracks/fix-round.md). The dice are not
## fixed: each run picks a seed and prints it, and E2E_SEED=n replays that story. A failure that
## comes and goes is a bug in the game or in this test, not noise.
extends RefCounted

const Rig := preload("res://tests/net_rig.gd")
const SAVE_DIR := "user://test_m4_e2e"
const NAMES := ["ann", "bob"]

var t: TestLog
var rig: Rig
## The players' town (the spawn town) and its neighbour along the road.
var T := -1
var N := -1
var road := -1
var cells: Array = []
var notices: Array = [[], []]
var xp_in: Array = [0, 0]
var standing_in: Array = [[], []]
var _near_k: Array = [-1, -1]
var _stuck: Array = [0.0, 0.0]
var _last_x: Array = [0.0, 0.0]
var _jump_t: Array = [0.0, 0.0]
var t0 := 0
var _dice := 0
## Why each attempt at a talk failed, as it stood at that moment.
var _talk_log: Array = []

func run(t_: TestLog) -> void:
	t = t_
	t0 = Time.get_ticks_msec()
	var given := OS.get_environment("E2E_SEED")
	_dice = int(given) if given != "" else randi()
	print("  dice seed %d" % _dice)
	var w := WorldGen.generate_named("dev", 4)
	rig = Rig.new(w, 0.03)
	rig.host.spawn = load("res://game/main.gd").spawn_for(w, rig.host.spawn)      # as the game does
	Systems.install_host(rig.host)
	_quiet_host()
	_age(30)
	_find_towns()
	t.check(T >= 0 and N >= 0 and road >= 0 and cells.size() > 20, "two towns joined by a road (%d, %d, route %d, %d cells)" % [T, N, road, cells.size()])
	if T < 0 or N < 0 or road < 0:
		return
	t.eq((w.meta["biomes"] as Array).size(), 5, "a world of five biomes")
	t.eq(sim().route_by_id[road].get("crossings", []), ["ford"], "and the road between the towns fords a river")
	_famine(T)
	_join()
	if not _ready():
		t.check(false, "both players joined with every system")
		return
	_strong()
	for f: String in ["_arrive", "_trade", "_message_and_relief", "_bounty", "_escort", "_defend", "_rumour", "_recover",
			"_patron", "_agree", "_persist"]:
		var ms := Time.get_ticks_msec()
		var before := t.failures.size()
		call(f)
		print("  %s: %d ms, sim day %d, %s" % [f, Time.get_ticks_msec() - ms, Deals.day(rig.host.sim), "ok" if t.failures.size() == before else "%d failed" % (t.failures.size() - before)])
	print("  total %d ms" % (Time.get_ticks_msec() - t0))

# --- setup -------------------------------------------------------------------------------------

func _quiet_host() -> void:
	var ms: MonstersSystem = sys(HostSystem.MONSTERS)
	ms.director_enabled = 0               # no random packs: the story sets its own fights
	ms.nav_fixed_slices = 8               # planning independent of machine load
	rig.host.rng.seed = _dice             # printed at the start: E2E_SEED=n replays a story
	ms.lairs_enabled = true               # the sim's lairs appear when someone is near
	(sys(HostSystem.RULES) as RulesSystem).cheats = true
	(sys(HostSystem.DEALS) as DealsSystem).cheats = true

## Let the world live a month before anyone arrives: news to hear (scene setting).
func _age(days: int) -> void:
	rig.host.sleep(days * 24.0)
	var guard := 0
	while rig.host.sim_behind() > 0 and guard < 20000:
		rig.host.tick()
		guard += 1

## A famine at a town: its granary nearly empty (scene setting for the relief work).
func _famine(sid: int) -> void:
	var s := town(sid)
	s.stock["food"] = SimEconomy.target(s, "food") * 0.12
	s.hungry = 3

## Sleep the world to the next morning (8:00), as a night passes: tomorrow's offers.
func next_day() -> void:
	idle()
	var h := rig.host.clock.hour_of_day()
	rig.host.sleep(fposmod(8.0 - h, 24.0) + (24.0 if fposmod(8.0 - h, 24.0) < 1.0 else 0.0))
	rig.until(func() -> bool: return rig.host.sim_behind() <= 0, 30.0)
	rig.run(2.0)
	_tough()

func _find_towns() -> void:
	var sim := rig.host.sim
	var bd := INF
	for sid: int in WorldSim._sorted_keys(sim.settlements):
		var s: SimSettlement = sim.settlements[sid]
		if s.band == "surface" and absf(s.x - rig.host.spawn.x) < bd:
			bd = absf(s.x - rig.host.spawn.x)
			T = sid
	var most := 0
	for r: Dictionary in sim.routes:
		if String(r.get("kind", "")) != "road":
			continue
		var other := int(r.b) if int(r.a) == T else (int(r.a) if int(r.b) == T else -1)
		if other >= 0 and sim.settlements.has(other) and (sim.settlements[other] as SimSettlement).pop() > most:
			most = (sim.settlements[other] as SimSettlement).pop()
			N = other
			road = int(r.id)
	if road >= 0:
		cells = Places.route_path(rig.host.world, road)
		if int(sim.route_by_id[road].a) != T:
			cells.reverse()                 # from T's street end to N's

func _join() -> void:
	for i in NAMES.size():
		var c := rig.add_client(NAMES[i])
		c.player_class = "fighter"
		var k := i
		c.welcomed.connect(func(cw: ClientWorld) -> void: _install(cw, k))

func _install(cw: ClientWorld, i: int) -> void:
	Systems.install_client(cw)
	var rc: RulesClient = cw.system(HostSystem.RULES)
	rc.notice.connect(func(text: String) -> void: notices[i].append(text))
	rc.xp_gained.connect(func(n: int, s: String) -> void: xp_in[i] += n)
	var lc: LifeClient = cw.system(HostSystem.LIFE)
	lc.standing_changed.connect(func(f: String, v: int, why: String) -> void: standing_in[i].append([f, v, why]))

func _ready() -> bool:
	return rig.until(func() -> bool:
		for i in rig.clients.size():
			var c := rig.cw(i)
			if c == null or not c.area_ready() or rc(i) == null or rc(i).sheet.is_empty():
				return false
		return true, 10.0) >= 0.0

## Fighters of level 6 with a deep pool of hit points: the story is about the world, not
## about surviving a troll. (Scene setting, through the rules' own XP path.)
func _strong() -> void:
	var rules: RulesSystem = sys(HostSystem.RULES)
	for i in 2:
		rules.award_xp(he(i).id, LevelTrack.xp_for_level(6), "test")
		he(i).character.inventory.coin += 600
		he(i).character.inventory.changed[-1] = true
	rig.run(0.5)
	_tough()

func _tough() -> void:
	for i in 2:
		var c := he(i).combatant
		c.stats.max_hp = 900
		c.stats.current_hp = 900

func he(i: int) -> HostEntity:
	return rig.host_entity(i)

func sys(id: int) -> HostSystem:
	return rig.host.system(id)

func rc(i: int) -> RulesClient:
	return rig.cw(i).system(HostSystem.RULES) if rig.cw(i) != null else null

func dc(i: int) -> DealsClient:
	return rig.cw(i).system(HostSystem.DEALS) if rig.cw(i) != null else null

func lc(i: int) -> LifeClient:
	return rig.cw(i).system(HostSystem.LIFE) if rig.cw(i) != null else null

func ic(i: int) -> ItemsClient:
	return rig.cw(i).system(HostSystem.ITEMS) if rig.cw(i) != null else null

func cc(i: int) -> CombatClient:
	return rig.cw(i).system(HostSystem.COMBAT) if rig.cw(i) != null else null

func deals() -> DealsSystem:
	return sys(HostSystem.DEALS)

func life() -> LifeSystem:
	return sys(HostSystem.LIFE)

func sim() -> WorldSim:
	return rig.host.sim

func town(sid: int) -> SimSettlement:
	return sim().settlements.get(sid)

func idle() -> void:
	for i in rig.inputs.size():
		rig.inputs[i] = PlayerInput.new()

## Scene setting: put player i at a point (host teleport; the client follows the CORRECT).
func put(i: int, pos: Vector2) -> void:
	rig.host.teleport(he(i), pos)
	TileCollision.depenetrate(rig.host.world, he(i).body)
	_near_k[i] = -1

## A point on the town's street, dx from its middle (not on a roof).
func street(dx: float) -> Vector2:
	var st: Array = Places.place(rig.host.world, T)["street"]
	return Vector2((float(st[0]) + float(st[1])) * 0.5 + dx, float(st[2]))

# --- moving like a player ----------------------------------------------------------------------

## One frame of input for client i walking along `path` (feet cells) toward index `goal`:
## aim a few cells ahead, run at it, hold W where it rises (stairs), S where it falls (drop
## through walkways), jump when stuck.
func _steer(i: int, path: Array, goal: int) -> PlayerInput:
	var b: Body = rig.cw(i).body
	var inp := PlayerInput.new()
	var k: int = _near_k[i]
	var lo := 0 if k < 0 else maxi(0, k - 30)
	var hi := path.size() if k < 0 else mini(path.size(), k + 30)
	var bd := INF
	for j in range(lo, hi):
		var c: Vector2i = path[j]
		var d := absf(c.x + 0.5 - b.pos.x) + absf(c.y - b.pos.y) * 1.5
		if d < bd:
			bd = d
			k = j
	_near_k[i] = k
	var dir := 1 if goal > k else -1
	var aim: Vector2i = path[clampi(k + dir * 3, 0, path.size() - 1)]
	if k == goal or (absf(path[goal].x + 0.5 - b.pos.x) < 0.6 and absf(path[goal].y - b.pos.y) < 2.0):
		return inp
	var dx := aim.x + 0.5 - b.pos.x
	inp.move_x = signf(dx) if absf(dx) > 0.2 else 0.0
	var hall := TileDefs.ladder[rig.host.world.get_fg(floori(b.pos.x), floori(b.pos.y) + 1)] != 0
	if aim.y > b.pos.y + 0.5 and not hall:          # y grows upward; a ladder in a hall is not the road
		inp.up = true
	elif aim.y < b.pos.y - 1.5 and absf(dx) < 2.0:
		inp.down = true
	var dt := rig.frame_dt
	if absf(b.pos.x - float(_last_x[i])) < 0.02 and inp.move_x != 0.0:
		_stuck[i] = float(_stuck[i]) + dt
	else:
		_stuck[i] = 0.0
	_last_x[i] = b.pos.x
	if float(_stuck[i]) > 0.2 and float(_jump_t[i]) <= 0.0:
		_jump_t[i] = 0.35
		inp.jump_pressed = true
	if float(_jump_t[i]) > 0.0:
		_jump_t[i] = float(_jump_t[i]) - dt
		inp.jump = true
	return inp

## Walk both players along the road to path index `goal` (each from where it is). Returns
## seconds taken or -1.
func walk(goal: int, limit: float, who := [0, 1], also := Callable()) -> float:
	_near_k = [-1, -1]
	var took := rig.until(func() -> bool:
		var done := true
		for i in who:
			rig.inputs[i] = _steer(i, cells, goal)
			var c: Vector2i = cells[goal]
			# (past the end of the road counts: a chase can end further into town than it starts)
			if absf(c.x + 0.5 - rig.cw(i).body.pos.x) > 1.5 and int(_near_k[i]) != goal:
				done = false
		if also.is_valid():
			also.call()
		return done, limit)
	idle()
	return took

## Walk player i on its own to an x near it (in a town: the street is level enough).
func walk_x(i: int, x: float, limit := 20.0) -> float:
	var path: Array = []
	var from := floori(rig.cw(i).body.pos.x)
	var y := floori(rig.cw(i).body.pos.y)
	var step := 1 if x >= from else -1
	for xx in range(from, floori(x) + step, step):
		var st := Places.street_at(rig.host.world, xx)
		path.append(Vector2i(xx, st.y if st.x >= 0 else y))
	if path.size() < 2:
		return 0.0
	_near_k[i] = -1
	var took := rig.until(func() -> bool:
		rig.inputs[i] = _steer(i, path, path.size() - 1)
		return absf(rig.cw(i).body.pos.x - x) < 1.2, limit)
	idle()
	rig.run(0.3)
	return took

## The road ends at the street's end, and a long street's middle can be out of the town's
## sight: on down the street to the site, so its people appear.
func _into_town(sid: int) -> void:
	var sx: float = rig.host.sim.site_by_id[sid].x
	for i in NAMES.size():
		walk_x(i, sx + i * 2.0, 30.0)

## Path index nearest x.
func cell_at(x: float) -> int:
	var best := 0
	var bd := INF
	for j in cells.size():
		var d := absf(cells[j].x + 0.5 - x)
		if d < bd:
			bd = d
			best = j
	return best

# --- talking like a player ---------------------------------------------------------------------

## The nearest person of a role Life has told player i about (PEOPLE), or -1. Where they
## stand comes from the client's view when in sight, else from the host (the player knows
## where the shrine is).
func person_near(i: int, role: String, site := -1) -> int:
	var best := -1
	var bd := INF
	for id: int in lc(i).people:
		var info: Dictionary = lc(i).people[id]
		if String(info.get("role", "")) != role or not bool(info.get("talk", false)):
			continue
		if site >= 0 and (String(info.get("kind", "")) != "settlement" or int(info.get("of", -1)) != site):
			continue
		var at := person_pos(i, id)
		if at == Vector2.INF:
			continue
		var d: float = at.distance_to(rig.cw(i).body.pos)
		if d < bd:
			bd = d
			best = id
	return best

func person_pos(i: int, id: int) -> Vector2:
	if rig.cw(i).remotes.has(id):
		return rig.cw(i).remotes[id].pos
	var e := rig.host.entity(id)
	return e.body.pos if e != null else Vector2.INF

## Walk up to a person, looking again as they go (they may be on their way somewhere).
func _walk_up(i: int, pid: int, limit: float) -> void:
	var left := limit
	while left > 0.0 and person_pos(i, pid) != Vector2.INF:
		var x: float = person_pos(i, pid).x
		var me := rig.cw(i).body.pos.x
		if absf(x - me) <= 3.0:
			return
		var took := walk_x(i, x + (1.5 if me > x else -1.5), 2.0)
		left -= took if took >= 0.0 else 2.0

## Walk up to a person of a role and open a conversation (through the client). "" or why not.
func talk_to(i: int, role: String, site := -1) -> String:
	rig.until(func() -> bool: return person_near(i, role, site) >= 0, 8.0)      # the town appears within a scan or two
	var pid := person_near(i, role, site)
	if pid < 0:
		return "no %s known" % role
	_talk_log = []
	for attempt in 6:
		_walk_up(i, pid, 40.0)
		dc(i).talk(pid)
		if rig.until(func() -> bool: return dc(i).talking() and int(dc(i).conversation.get("id", -1)) == pid, 1.0) >= 0.0:
			return ""
		if rig.host.entity(pid) == null:
			return "gone"
		_talk_log.append("%d: %s; me %s host %s, %s %s host %s" % [attempt, dc(i).last_note, rig.cw(i).body.pos, he(i).body.pos, role, person_pos(i, pid), rig.host.entity(pid).body.pos])
		if attempt >= 2:                  # a roof or an upper floor: step back onto the street
			put(i, person_pos(i, pid) + Vector2(1.2, 0.2))
			rig.run(0.6)
	return "no answer (%s; in_combat %s/%s)" % [" | ".join(_talk_log), (sys(HostSystem.COMBAT) as CombatSystem).in_combat(he(i)), (sys(HostSystem.COMBAT) as CombatSystem).in_combat(rig.host.entity(pid))]

func choose(i: int, opt: String) -> bool:
	dc(i).choose(opt)
	return rig.until(func() -> bool: return String(dc(i).conversation.get("view", "")) != "main" or not dc(i).talking() \
		or opt.begins_with("turn_in") or opt == "patron", 1.0) >= 0.0

func has_option(i: int, opt: String) -> bool:
	return (dc(i).conversation.get("options", []) as Array).any(func(o: Dictionary) -> bool: return String(o["id"]) == opt)

## Take an offered quest of a kind from the open conversation (opening the work view first).
func take(i: int, kind: String) -> String:
	if not has_option(i, "quests"):
		return ""
	choose(i, "quests")
	rig.run(0.3)
	for q: Dictionary in dc(i).conversation.get("offers", []):
		if String(q["kind"]) == kind:
			var qid := String(q["id"])
			dc(i).accept(qid)
			rig.until(func() -> bool: return not mirror(i, qid).is_empty(), 2.0)
			return qid
	return ""

## The client's quest log entry.
func mirror(i: int, qid: String) -> Dictionary:
	for q: Dictionary in dc(i).quests:
		if String(q["id"]) == qid:
			return q
	return {}

func offered_kinds(sid: int) -> Array:
	return deals().offers_at(sid).map(func(q: Dictionary) -> String: return "%s(%s)" % [q["kind"], q.get("giver", "?")])

# --- fighting like a player --------------------------------------------------------------------

## One frame of fighting for player i, as a player would: the nearest remote that `pick`
## accepts; close in until the boxes nearly touch, jump at one above, swing at its middle.
func fight(i: int, pick: Callable) -> bool:
	var cw := rig.cw(i)
	var inp := PlayerInput.new()
	rig.inputs[i] = inp
	var best: ClientWorld.RemoteEntity = null
	var bpos := Vector2.ZERO
	var bd := INF
	for r: ClientWorld.RemoteEntity in cw.remotes.values():
		if r.kind == HostEntity.Kind.PLAYER or (r.max_hp > 0 and r.hp <= 0) or not bool(pick.call(r)):
			continue
		var p: Vector2 = cw.sample_remote(r.id).get("pos", r.pos)
		var d := p.distance_to(cw.body.pos)
		if d < bd:
			bd = d
			best = r
			bpos = p
	if best == null:
		return false
	var me := cw.body.rect()
	var them := Rect2(bpos - Vector2(best.size.x * 0.5, 0.0), best.size)
	var dx := them.get_center().x - me.get_center().x
	var dy := them.get_center().y - me.get_center().y
	var gap := HitShapes.gap(me, them)
	if absf(dx) > (me.size.x + them.size.x) * 0.5 + 0.6:
		inp.move_x = signf(dx)
	cw.body.facing = 1 if dx >= 0.0 else -1
	if absf(dx) > 0.3 and absf(cw.body.pos.x - float(_last_x[i])) < 0.02 and inp.move_x != 0.0:
		_stuck[i] = float(_stuck[i]) + rig.frame_dt
	else:
		_stuck[i] = 0.0
	_last_x[i] = cw.body.pos.x
	if (dy > 1.5 and absf(dx) < 4.0) or float(_stuck[i]) > 0.25:
		inp.jump = true
		inp.jump_pressed = cw.body.on_floor
		inp.up = true
	if gap < 1.8 and cc(i).can_attack():
		cc(i).attack(them.get_center())
	rig.inputs[i] = cc(i).filter_input(inp)
	return true

## Remotes that are raiders (Life's people of a raid party) on client i.
func raider_pick(i: int) -> Callable:
	return func(r: ClientWorld.RemoteEntity) -> bool:
		var info: Dictionary = lc(i).person(r.id)
		return String(info.get("role", "")) == "raider"

func monster_pick(i: int) -> Callable:
	return func(r: ClientWorld.RemoteEntity) -> bool: return not lc(i).is_person(r.id)

# --- 1. arrival --------------------------------------------------------------------------------

func _arrive() -> void:
	rig.run(3.0)
	var s := town(T)
	for i in 2:
		t.check(notices[i].any(func(n: String) -> bool: return s.name in n), "player %d had the arrival notice for %s (%s)" % [i, s.name, notices[i]])
	var shown := life().actors_at(T)
	t.check(shown.size() >= 8, "%s shows its people (%d)" % [s.name, shown.size()])
	print("    roles shown: %s; first roles %s" % [shown.map(func(e: HostEntity) -> String: return "%s%s" % [e.get_meta("sim")["role"], "" if e.get_meta("talk", false) else "(mute)"]), Life.people_cfg()["first_roles"].get(s.tier, [])])
	var at_post := 0
	var with_post := 0
	for e: HostEntity in shown:
		var role := String(e.get_meta("sim")["role"])
		var anchors := Places.anchors(rig.host.world, T, role)
		if anchors.is_empty() or role in ["guard", "townsfolk"]:
			continue
		with_post += 1
		for a: Vector2i in anchors:
			if e.body.pos.distance_to(Vector2(a.x + 0.5, a.y)) <= 4.0:
				at_post += 1
				break
	t.check(with_post > 0 and at_post * 2 >= with_post, "the keeper, smith, merchant and priest are at their posts (%d of %d)" % [at_post, with_post])
	for i in 2:
		t.check(lc(i).people_at(T).size() >= shown.size() - 2, "client %d knows the people (%d)" % [i, lc(i).people_at(T).size()])
		t.check(dc(i).sites.has(T) and dc(i).seen.has(T), "client %d: %s is on the map and seen" % [i, s.name])

# --- 2. a merchant: buy and sell; the books balance --------------------------------------------

func _trade() -> void:
	var s := town(T)
	t.eq(talk_to(0, "merchant", T), "", "ann talks to the merchant")
	t.check(has_option(0, "shop"), "the merchant keeps a shop")
	choose(0, "shop")
	rig.until(func() -> bool: return dc(0).shopping(), 2.0)
	t.check(dc(0).shopping(), "the shop opened")
	var rope := {}
	for l: Dictionary in dc(0).shop.get("listings", []):
		if String(l["item"]["base"]) == "tile:rope":
			rope = l
	t.check(not rope.is_empty() and int(rope["n"]) > 0, "rope on the shelf")
	var w0 := s.wealth
	var timber0 := float(s.stock["timber"])
	var coin0 := he(0).character.inventory.coin
	var rope0 := he(0).character.inventory.count_base("tile:rope")
	var audit0 := sim().audit()
	if not rope.is_empty():
		dc(0).buy(String(rope["id"]), 2)
		rig.until(func() -> bool: return he(0).character.inventory.count_base("tile:rope") > rope0, 2.0)
		var paid := coin0 - he(0).character.inventory.coin
		if paid == 0:
			print("    buy: %s listing %s coin %d" % [dc(0).last_note, rope, coin0])
		t.eq(he(0).character.inventory.count_base("tile:rope"), rope0 + 2, "two ropes in the pack")
		t.check(paid > 0 and is_equal_approx(s.wealth, w0 + paid), "paid %d; the town's wealth rose by as much (%.1f)" % [paid, s.wealth - w0])
		t.check(is_equal_approx(float(s.stock["timber"]), timber0 - 2.0 * float(rope["units"]) if rope.has("units") else timber0 - 2.0), "the rope came out of its timber (%.1f -> %.1f)" % [timber0, s.stock["timber"]])
	# sell ore found underground
	he(0).character.inventory.add(Items.make("ore:iron", 6))
	he(0).character.inventory.changed[-1] = true
	rig.run(0.5)
	var slot := -1
	var inv := he(0).character.inventory
	for k in inv.slots.size():
		if not inv.slots[k].is_empty() and String(inv.slots[k]["base"]) == "ore:iron":
			slot = k
	t.check(slot >= 0, "ore in the pack")
	var w1 := s.wealth
	var ore1 := float(s.stock["ore"])
	var c1 := inv.coin
	dc(0).sell(slot, 6)
	rig.until(func() -> bool: return inv.count_base("ore:iron") == 0, 2.0)
	var got := inv.coin - c1
	t.check(got > 0 and is_equal_approx(s.wealth, w1 - got), "sold 6 ore for %d; the town paid it (%.1f)" % [got, w1 - s.wealth])
	t.check(float(s.stock["ore"]) > ore1, "the ore went into its stock (%.1f -> %.1f)" % [ore1, s.stock["ore"]])
	rig.run(0.5)
	t.eq(ic(0).coin(), inv.coin, "the client's coin matches the host")
	t.eq(sim().audit(), audit0, "the audit is as clean as before (%s)" % [sim().audit()])
	dc(0).leave()
	rig.run(0.3)

# --- 3. a rumour, and its place on the map ------------------------------------------------------

func _rumour() -> void:
	put(0, street(-2.0))
	put(1, street(2.0))
	rig.run(1.0)
	var heard := false
	for role: String in ["keeper", "merchant", "guard", "priest", "smith"]:
		if talk_to(1, role, T) != "":
			continue
		choose(1, "rumours")
		rig.run(0.4)
		if not dc(1).rumours.is_empty():
			heard = true
			break
		dc(1).leave()
		rig.run(0.2)
	t.check(heard, "bob heard a rumour (%d; chronicle %d: %s)" % [dc(1).rumours.size(), sim().chronicle.size(), sim().chronicle.slice(-4).map(func(e: Dictionary) -> String: return sim().describe(e))])
	if heard:
		var r: Dictionary = dc(1).rumours[0]
		print("    rumour: %s" % r.get("text", ""))
		var sid := int(r.get("site", -1))
		t.check(sid < 0 or dc(1).sites.has(sid), "its place (%d) is on bob's map" % sid)
		t.check(dc(1).map_marks().size() >= 1, "and marked")
	dc(1).leave()
	rig.run(0.3)


# --- 4. a message walked to the next town and back; food carried to the hungry one -------------

func _message_and_relief() -> void:
	var s := town(T)
	var n := town(N)
	print("    offers at %s: %s" % [s.name, offered_kinds(T)])
	t.eq(talk_to(0, "keeper", T), "", "ann talks to the keeper")
	var msg := take(0, "message")
	t.check(msg != "", "the keeper has word to carry (%s)" % msg)
	t.check(int(deals().quest(msg).get("target", {}).get("site", -1)) == N, "to %s" % n.name)
	dc(0).leave()
	var giver := String(DealsQuests.kind_def("relief")["givers"][0])
	var relief := ""
	for role: String in ["priest", "keeper"]:
		if talk_to(0, role, T) == "":
			relief = take(0, "relief")
			dc(0).leave()
			if relief != "":
				break
	t.check(relief != "", "the hungry town asks for food (%s)" % giver)
	var need := int(deals().quest(relief).get("target", {}).get("n", 0)) if relief != "" else 0
	# bob joins the message: shared work
	if talk_to(1, "keeper", T) == "":
		take(1, "message")
		dc(1).leave()
	rig.run(0.5)
	t.eq((deals().quest(msg).get("players", []) as Array).size(), 2, "both carry the message")
	# the road: walk it
	var took := walk(cells.size() - 1, 240.0)
	print("    walked %d cells to %s in %.1f s (ann at %s, bob at %s)" % [cells.size(), n.name, took, rig.cw(0).body.pos, rig.cw(1).body.pos])
	t.check(took >= 0.0, "both walked the road to %s (%.0f s)" % [n.name, took])
	_into_town(N)
	rig.run(1.5)
	t.eq(String(deals().quest(msg).get("state", "")), "ready", "the message is delivered: go back")
	t.eq(String(mirror(0, msg).get("state", "")), "ready", "ann's log says so")
	# buy food here for the hungry town
	var food_n0 := float(n.stock["food"])
	var bought := 0
	if talk_to(0, "merchant", N) == "" and has_option(0, "shop"):
		choose(0, "shop")
		rig.until(func() -> bool: return dc(0).shopping(), 2.0)
		for l: Dictionary in dc(0).shop.get("listings", []):
			if String(l["item"]["base"]) == "trade:food":
				dc(0).buy(String(l["id"]), mini(need, int(l["n"])))
				rig.until(func() -> bool: return he(0).character.inventory.count_base("trade:food") > 0, 2.0)
				bought = he(0).character.inventory.count_base("trade:food")
		dc(0).leave()
	t.check(bought >= need and need > 0, "ann bought %d food in %s (needs %d)" % [bought, n.name, need])
	t.check(float(n.stock["food"]) < food_n0, "out of %s's stock (%.0f -> %.0f)" % [n.name, food_n0, n.stock["food"]])
	# and back
	took = walk(0, 240.0)
	t.check(took >= 0.0, "and walked back to %s (%.0f s)" % [s.name, took])
	_into_town(T)
	rig.run(1.0)
	var c0 := he(0).character.inventory.coin
	var xp0 := he(0).character.xp
	if talk_to(0, "keeper", T) == "":
		t.check(has_option(0, "turn_in:" + msg), "the keeper takes the news")
		choose(0, "turn_in:" + msg)
		rig.until(func() -> bool: return String(mirror(0, msg).get("state", "")) == "done", 2.0)
		dc(0).leave()
	t.eq(String(deals().quest(msg).get("state", "")), "done", "the message is done")
	t.check(he(0).character.inventory.coin > c0 and he(0).character.xp > xp0, "paid in coin and XP")
	t.eq(String(mirror(1, msg).get("state", "")), "done", "bob's log says done too")
	var food0 := float(s.stock["food"])
	var price0 := SimEconomy.price(s, "food")
	for role: String in ["priest", "keeper"]:
		if talk_to(0, role, T) == "" and has_option(0, "turn_in:" + relief):
			choose(0, "turn_in:" + relief)
			rig.until(func() -> bool: return String(mirror(0, relief).get("state", "")) == "done", 2.0)
			dc(0).leave()
			break
		dc(0).leave()
	t.eq(String(deals().quest(relief).get("state", "")), "done", "the food is delivered")
	t.check(is_equal_approx(float(s.stock["food"]), food0 + need), "it entered %s's stock (%.0f -> %.0f)" % [s.name, food0, s.stock["food"]])
	t.check(SimEconomy.price(s, "food") < price0, "and the price of food fell (%.2f -> %.2f)" % [price0, SimEconomy.price(s, "food")])
	t.eq(sim().audit(), [] as Array[String], "the audit is clean")

# --- 5. a bounty: the lair's creatures killed with real blows -----------------------------------

func _bounty() -> void:
	var s := town(T)
	t.eq(talk_to(0, "guard", T), "", "ann talks to a guard")
	var qid := take(0, "bounty")
	dc(0).leave()
	t.check(qid != "", "the guard has a bounty")
	if qid == "":
		return
	if talk_to(1, "guard", T) == "":
		take(1, "bounty")
		dc(1).leave()
	var q := deals().quest(qid)
	var lid := int(q["target"]["lair"])
	var l: SimLair = sim().lairs[lid]
	var n0 := l.count()
	var need := int(q["target"]["n"])
	print("    bounty on %s: %s, kill %d" % [l.name, l.monsters, need])
	# oozes shrug off blades: a player takes a hammer (bought, here given)
	for i in 2:
		he(i).character.inventory.add(Items.make("warhammer"))
		he(i).character.inventory.changed[-1] = true
	rig.run(0.5)
	for i in 2:
		var inv := he(i).character.inventory
		for k in inv.slots.size():
			if not inv.slots[k].is_empty() and String(inv.slots[k]["base"]) == "warhammer":
				ic(i).equip(k, "main_hand")
	rig.run(0.5)
	t.check(String((sys(HostSystem.ITEMS) as ItemsSystem).wielded(he(0)).get("base", "")) == "warhammer", "ann wields a warhammer")
	# scene: the players at the lair's mouth (the walk there is the message's kind of travel)
	var at := Deals.site_xy(sim(), lid)
	put(0, at + Vector2(-6, 1))
	put(1, at + Vector2(-8, 1))
	rig.run(2.0)
	var ms: MonstersSystem = sys(HostSystem.MONSTERS)
	var shown := (ms.lairs.active.get(lid, {}).get("ids", {}) as Dictionary).size()
	t.check(shown == n0, "the lair's %d creatures are there (%d)" % [n0, shown])
	var xp0 := [he(0).character.xp, he(1).character.xp]
	var took := rig.until(func() -> bool:
		_tough()
		fight(0, monster_pick(0))
		fight(1, monster_pick(1))
		return n0 - (sim().lairs[lid] as SimLair).count() >= need if sim().lairs.has(lid) else true, 180.0)
	idle()
	rig.run(1.5)
	var left := (sim().lairs[lid] as SimLair).count() if sim().lairs.has(lid) else 0
	if took < 0.0:
		for id: int in ms.lairs.active.get(lid, {}).get("ids", {}):
			var m := rig.host.entity(id)
			if m != null:
				print("    left: %s at %s hp %s; seen by ann %s" % [m.name, m.body.pos, m.vitals(), rig.cw(0).remotes.has(id)])
		print("    ann at %s, bob at %s; ann sent %d attacks, combat counts %s" % [he(0).body.pos, he(1).body.pos, cc(0).sent, (sys(HostSystem.COMBAT) as CombatSystem).counts])
	t.check(took >= 0.0, "killed %d of the lair in %.0f s (%d left in the sim)" % [n0 - left, took, left])
	t.check(left <= n0 - need, "the sim's lair shrank (%d -> %d)" % [n0, left])
	t.eq(String(deals().quest(qid).get("state", "")), "ready", "the bounty is ready")
	t.check(he(0).character.xp > int(xp0[0]) and he(1).character.xp > int(xp0[1]), "both earned XP in the fight")
	# home to hand it in
	put(0, street(2.0))
	put(1, street(4.0))
	rig.run(2.0)
	var c0 := he(0).character.inventory.coin
	var w0 := s.wealth
	if talk_to(0, "guard", T) == "" and has_option(0, "turn_in:" + qid):
		choose(0, "turn_in:" + qid)
		rig.until(func() -> bool: return String(mirror(0, qid).get("state", "")) == "done", 2.0)
	dc(0).leave()
	t.eq(String(deals().quest(qid).get("state", "")), "done", "the bounty is paid")
	t.check(he(0).character.inventory.coin > c0 and s.wealth < w0, "out of %s's purse (%.0f)" % [s.name, w0 - s.wealth])
# --- 6. an escort along the road, through an ambush ---------------------------------------------

## Path index nearest a point.
func cell_near(pos: Vector2) -> int:
	var best := 0
	var bd := INF
	for j in cells.size():
		var d := absf(cells[j].x + 0.5 - pos.x) + absf(cells[j].y - pos.y)
		if d < bd:
			bd = d
			best = j
	return best

## Scene: raiders on the road ahead of a party (a raid out to waylay the road's traffic).
func waylay(at_frac: float, n := 5) -> SimParty:
	var s := town(3) if sim().settlements.has(3) else town(N)
	var home := 3 if sim().settlements.has(3) else N
	var c := SimData.culture(s.culture)
	var r := sim().new_party("raid", s.faction, s.culture, home, SimData.allocate(c.raiders, n))
	r.plan = {"mode": "route", "motive": "plunder", "leg": "out"}
	r.target = road
	r.path = [N, T] as Array[int]
	r.leg = 0
	r.route = road
	r.frac = 1.0 - at_frac if int(sim().route_by_id[road].a) == T else at_frac
	r.state = "travel"
	r.dest = T
	s.out_raids += 1
	return r

func _escort() -> void:
	next_day()
	var s := town(T)
	var n := town(N)
	var cid := life().cheat_party("caravan", T, N, 0.02)
	var cp: SimParty = sim().parties.get(cid)
	t.check(cp != null and cp.leg == 0 and cp.route == road, "a caravan leaves %s for %s (scene)" % [s.name, n.name])
	if cp == null:
		return
	var food_n0 := float(n.stock["food"])
	var cargo0: int = int(cp.cargo.get("food", 0))
	t.eq(talk_to(0, "merchant", T), "", "ann talks to the merchant")
	var qid := take(0, "escort")
	dc(0).leave()
	t.check(qid != "", "the merchant wants an escort (%s)" % [offered_kinds(T)])
	if qid == "":
		return
	if talk_to(1, "merchant", T) == "":
		take(1, "escort")
		dc(1).leave()
	t.check(cp.held, "the caravan waits for its escort")
	var f0 := cp.frac
	rig.run(5.0)
	var at := life().road.party_pos(rig.host, cp)
	if _near_any(at, 40.0):
		t.check(true, "(the escort was already beside it)")
	else:
		t.eq(cp.frac, f0, "it does not leave without them")
	# walk to it; it leaves when they are beside it
	walk(cell_near(at), 60.0)
	rig.run(2.0)
	t.check(not cp.held, "the escort is beside it: it leaves")
	# (a dictionary: lambdas capture locals by value)
	var st := {"ambushed": false, "raid": null, "fought": 0.0, "with": 0, "frames": 0}
	var took := rig.until(func() -> bool:
		_tough()
		var pos := life().road.party_pos(rig.host, cp) if sim().parties.has(cid) else Vector2.INF
		if pos == Vector2.INF:
			return true
		var fr := float(sim().party_position(cp)["frac"]) if int(sim().party_position(cp)["route"]) == road else 1.0
		if int(sim().route_by_id[road].a) != T:
			fr = 1.0 - fr
		if not st["ambushed"] and fr >= 0.35:
			st["ambushed"] = true
			st["raid"] = waylay(minf(fr + 0.04, 0.95), 3)
		var raid: SimParty = st["raid"]
		var foes := raid != null and sim().parties.has(raid.id) \
			and life().road.actors_of(rig.host, raid.id).any(func(e: HostEntity) -> bool: return e.body.pos.distance_to(pos) < 30.0)
		for i in 2:
			if foes and fight(i, raider_pick(i)):
				st["fought"] = float(st["fought"]) + rig.frame_dt * 0.5
			else:
				rig.inputs[i] = _steer(i, cells, clampi(cell_near(pos) + (2 if i == 0 else -2), 0, cells.size() - 1))
		st["frames"] = int(st["frames"]) + 1
		if int(st["frames"]) % 30 == 0:
			var w: Variant = mirror(0, qid).get("where")
			if w is Array and Vector2(w[0], w[1]) != st.get("where", Vector2.ZERO):
				st["where"] = Vector2(w[0], w[1])
				st["pointer"] = int(st.get("pointer", 0)) + 1
			for e: HostEntity in life().road.actors_of(rig.host, cid):
				st["looked"] = int(st.get("looked", 0)) + 1
				if e.body.on_floor or e.body.on_stairs:
					st["grounded"] = int(st.get("grounded", 0)) + 1
		if int(st["frames"]) % 600 == 0:
			print("      t=%.0f caravan %s fr %.2f frozen %s %d | ann %s bob %s | raid %s" % [int(st["frames"]) / 60.0, pos, fr, cp.frozen, cp.size(),
				he(0).body.pos, he(1).body.pos, "-" if raid == null else "%d %s" % [raid.size(), raid.state]])
		if _near_any(pos, 12.0):
			st["with"] = int(st["with"]) + 1
		return String(cp.plan.get("leg", "out")) == "home", 400.0)
	idle()
	rig.run(1.5)
	var raid: SimParty = st["raid"]
	print("    escort: %.0f s on the road, %.0f s fighting, beside it %d%% of the time; caravan %d of %d, plan %s; raid %s" % [took, st["fought"], roundi(100.0 * int(st["with"]) / maxi(1, int(st["frames"]))),
		cp.size(), int(deals().quest(qid)["target"]["base"]), cp.plan, "gone" if raid == null or not sim().parties.has(raid.id) else "left %d" % raid.size()])
	t.check(took >= 0.0, "the caravan reached %s (%.0f s)" % [n.name, took])
	t.check(int(st.get("pointer", 0)) >= 20, "the escort's pointer kept up with it (%d updates)" % int(st.get("pointer", 0)))
	t.check(int(st.get("grounded", 0)) * 100 >= int(st.get("looked", 0)) * 85, "its people and wagons walk on the road (%d of %d looks on a floor)" % [int(st.get("grounded", 0)), int(st.get("looked", 0))])
	_into_town(N)      # the caravan turns round at the site, which a long street can hide from its end
	var dest_now := -1
	for id: int in lc(0).people:
		var pi: Dictionary = lc(0).people[id]
		if String(pi.get("kind", "")) == "party" and int(pi.get("of", -1)) == cid:
			dest_now = int(pi.get("dest", -1))
	rig.run(1.5)
	for id: int in lc(0).people:
		var pi: Dictionary = lc(0).people[id]
		if String(pi.get("kind", "")) == "party" and int(pi.get("of", -1)) == cid:
			dest_now = int(pi.get("dest", -1))
	t.eq(dest_now, T, "its plates now say it is bound home")
	t.check(bool(st["ambushed"]) and float(st["fought"]) > 1.0, "the ambush on the way was fought (%.0f s)" % st["fought"])
	t.check(raid != null and (not sim().parties.has(raid.id) or raid.size() < 3), "the raiders were beaten off")
	t.check(cp.size() * 2 >= int(deals().quest(qid)["target"]["base"]), "it arrived with most of its people (%d)" % cp.size())
	t.check(int(cp.plan.get("brought", 0)) * 2 >= cargo0, "and most of its cargo (%d of %d)" % [int(cp.plan.get("brought", 0)), cargo0])
	t.check(float(n.stock["food"]) > food_n0, "%s's food stock grew (%.0f -> %.0f)" % [n.name, food_n0, n.stock["food"]])
	t.eq(String(deals().quest(qid).get("state", "")), "done", "the escort is done and paid where it arrived")
	t.eq(String(mirror(1, qid).get("state", "")), "done", "bob's log says so")
	t.eq(sim().audit(), [] as Array[String], "the audit is clean")

func _near_any(pos: Vector2, tiles: float) -> bool:
	for i in 2:
		if he(i).body.pos.distance_to(pos) <= tiles:
			return true
	return false

# --- 7. a raid met at the gate -------------------------------------------------------------------

func _defend() -> void:
	next_day()
	var s := town(T)
	var from := 3 if sim().settlements.has(3) else N
	var rid := life().cheat_party("raid", from, T, 0.55, 6)
	var raid: SimParty = sim().parties.get(rid)
	t.check(raid != null, "raiders from %s are on their way (scene)" % town(from).name)
	if raid == null:
		return
	put(0, street(-2.0))
	put(1, street(2.0))
	rig.run(1.5)
	var st0 := life().standing(he(0).id, str(s.faction))
	var chron0 := sim().chronicle.size()
	var talked := talk_to(0, "guard", T)
	t.eq(talked, "", "ann talks to a guard")
	var qid := take(0, "defend")
	dc(0).leave()
	t.check(qid != "", "the guard asks for help (%s)" % [offered_kinds(T)])
	if qid == "":
		return
	if talk_to(1, "guard", T) == "":
		take(1, "defend")
		dc(1).leave()
	var soldiers0 := s.soldiers
	var st := {"blows": 0}
	var took := rig.until(func() -> bool:
		_tough()
		for i in 2:
			if not fight(i, raider_pick(i)):
				rig.inputs[i] = PlayerInput.new()
			else:
				st["blows"] = int(st["blows"]) + 1
		return String(deals().quest(qid).get("state", "")) in DealsQuests.ENDED, 240.0)
	idle()
	rig.run(1.5)
	var line := {}
	for i in range(chron0, sim().chronicle.size()):
		if String(sim().chronicle[i].get("kind", "")) in ["raid", "raid_repelled"]:
			line = sim().chronicle[i]
	print("    defend: %.0f s, %d raiders left, garrison %d -> %d; %s" % [took, raid.size(), soldiers0, s.soldiers, sim().describe(line) if not line.is_empty() else "no line"])
	t.check(took >= 0.0 and int(st["blows"]) > 0, "the raid came and was fought at the gate (%.0f s)" % took)
	t.check(not line.is_empty() and not bool(line.get("won", false)), "the sim records it repelled")
	t.eq(String(deals().quest(qid).get("state", "")), "done", "the defence is done and paid")
	t.check(life().standing(he(0).id, str(s.faction)) > st0, "standing rose (%d -> %d)" % [st0, life().standing(he(0).id, str(s.faction))])
	t.eq(lc(0).standing(str(s.faction)), life().standing(he(0).id, str(s.faction)), "the client sees the same standing")
	t.eq(sim().audit(), [] as Array[String], "the audit is clean")

# --- 8. stolen cargo cut from raiders on the road ------------------------------------------------

func _recover() -> void:
	next_day()
	var s := town(T)
	var raid := waylay(0.25, 4)
	raid.cargo = {"tools": 12}
	raid.plan["motive"] = "plunder"
	sim().log_event("ambush", {"raiders": SimConflict._adj(raid.culture), "rfaction": sim().faction_name(raid.faction), "rfrom": SimConflict._home_name(sim(), raid),
		"victim": "caravan", "vfrom": s.name, "vfaction": sim().faction_name(s.faction), "route": sim().route_name(road), "won": true, "killed": 3, "lost": 0,
		"food": 0, "goods": 12, "coin": 0, "captives": 0, "patrol": false, "motive": "plunder"})
	put(0, street(-2.0))
	put(1, street(2.0))
	rig.run(1.5)
	t.eq(talk_to(0, "merchant", T), "", "ann talks to the merchant")
	var qid := take(0, "recover")
	dc(0).leave()
	t.check(qid != "", "the merchant wants the goods back (%s)" % [offered_kinds(T)])
	if qid == "":
		return
	if talk_to(1, "merchant", T) == "":
		take(1, "recover")
		dc(1).leave()
	var need := int(deals().quest(qid)["target"]["n"])
	# walk out along the road until they are met
	var pos := life().road.party_pos(rig.host, raid)
	walk(clampi(cell_near(pos) - 12, 0, cells.size() - 1), 60.0)
	var took := rig.until(func() -> bool:
		_tough()
		for i in 2:
			if not fight(i, raider_pick(i)):
				var at := life().road.party_pos(rig.host, raid) if sim().parties.has(raid.id) else he(i).body.pos
				rig.inputs[i] = _steer(i, cells, cell_near(at))
		return not sim().parties.has(raid.id), 120.0)
	idle()
	rig.run(1.0)
	if took < 0.0:
		for e: HostEntity in life().road.actors_of(rig.host, raid.id):
			var br := e.brain as MonsterBrain
			print("    left: %s %d at %s hp %s floor %s; target %s; post %s; seen %s; ann %s bob %s; raid %s frozen %s plan %s" % [e.name, e.id, e.body.pos, e.vitals(), e.body.on_floor, br.target_id if br != null else -1, (e.brain as LifeBrain).post if e.brain is LifeBrain else "-", rig.cw(0).remotes.has(e.id), he(0).body.pos, he(1).body.pos, raid.state, raid.frozen, raid.plan])
	t.check(took >= 0.0, "the raiders on the road are dead (%.0f s)" % took)
	var items: ItemsSystem = sys(HostSystem.ITEMS)
	var dropped := 0
	for d: Drops.Drop in items.drops.list.values():
		if String(d.item.get("base", "")) == "trade:tools":
			dropped += int(d.item.get("count", 1))
	var held := func() -> int: return he(0).character.inventory.count_base("trade:tools") + he(1).character.inventory.count_base("trade:tools")
	t.check(dropped + int(held.call()) >= need, "their cargo fell where they did (%d dropped, %d picked up, %d asked)" % [dropped, held.call(), need])
	# pick it up: walk over each drop
	for attempt in 3:
		for d: Drops.Drop in items.drops.list.values():
			if String(d.item.get("base", "")) == "trade:tools":
				# past it from either side: arriving above a drop on a ledge doesn't reach it
				walk_x(0, d.pos.x + [0.0, -2.5, 2.5][attempt], 10.0)
				rig.run(0.5)
	t.check(int(held.call()) >= need, "the goods are in the players' packs (%d of %d, %d left on the ground)" % [held.call(), need, items.drops.list.values().filter(func(d: Drops.Drop) -> bool: return String(d.item.get("base", "")) == "trade:tools").size()])
	# carry them home
	var back := walk(0, 120.0)
	t.check(back >= 0.0, "and home along the road (%.0f s; ann %s, bob %s)" % [back, rig.cw(0).body.pos, rig.cw(1).body.pos])
	_into_town(T)
	rig.run(1.0)
	var tools0 := float(s.stock["tools"])
	var c0 := he(0).character.inventory.coin
	var why := talk_to(0, "merchant", T)
	t.eq(why, "", "ann is back at the merchant (at %s, bob %s, merchant %s)" % [rig.cw(0).body.pos, rig.cw(1).body.pos, person_pos(0, person_near(0, "merchant", T))])
	if why == "" and has_option(0, "turn_in:" + qid):
		choose(0, "turn_in:" + qid)
		rig.until(func() -> bool: return String(mirror(0, qid).get("state", "")) == "done", 2.0)
	dc(0).leave()
	if String(deals().quest(qid).get("state", "")) != "done":
		print("    hand-in: why %s, option %s, ann %s has %d, bob %s has %d, need %d, options %s, bob at site %s" % [why, has_option(0, "turn_in:" + qid), he(0).body.pos, he(0).character.inventory.count_base("trade:tools"), he(1).body.pos, he(1).character.inventory.count_base("trade:tools"), need, dc(0).conversation.get("options", []), Deals.at_site(rig.host.world, sim(), T, he(1).body.pos, float(Deals.quests()["turn_in_margin"]))])
	t.eq(String(deals().quest(qid).get("state", "")), "done", "the goods are handed in (%s)" % [dc(0).last_note])
	t.check(is_equal_approx(float(s.stock["tools"]), tools0 + need), "back in %s's stock (%.0f -> %.0f)" % [s.name, tools0, s.stock["tools"]])
	t.check(he(0).character.inventory.coin >= c0, "paid")
	t.eq(int(held.call()), 0, "out of both packs (the party pools what it carries)")

# --- 9. a patron's gift, and the smith's rack -----------------------------------------------------

func _patron() -> void:
	var s := town(T)
	var f := str(s.faction)
	var st := life().standing(he(0).id, f)
	t.check(st >= 25, "the work done raised ann's standing to a patron's notice (%d)" % st)
	var tier := deals().patron_tier(he(0).id, f)
	t.check(tier >= 1, "tier %d" % tier)
	var bag0 := _bag(0)
	if talk_to(0, "keeper", T) == "" and has_option(0, "patron"):
		choose(0, "patron")
		rig.until(func() -> bool: return _bag(0) != bag0, 2.0)
	dc(0).leave()
	rig.run(0.5)
	t.check(_bag(0) != bag0, "the gift is in ann's pack")
	t.eq(int(dc(0).patrons.get(f, {}).get("given", 0)), tier, "the client knows the gift was given")
	# a piece from the smith's rack: sold for the day
	he(0).character.inventory.coin += 2000
	he(0).character.inventory.changed[-1] = true
	if talk_to(0, "smith", T) == "" and has_option(0, "smith"):
		choose(0, "smith")
		rig.until(func() -> bool: return dc(0).shopping(), 2.0)
		var listings: Array = dc(0).shop.get("listings", [])
		t.check(not listings.is_empty(), "the smith has a rack")
		if not listings.is_empty():
			var bag1 := _bag(0)
			dc(0).buy(String(listings[0]["id"]), 1)
			rig.until(func() -> bool: return _bag(0) != bag1, 2.0)
			t.check(_bag(0) != bag1, "bought a piece")
	dc(0).leave()
	rig.run(0.5)
	t.check(not (deals()._sold_today(T) as Dictionary).is_empty(), "the rack remembers it")

## Everything in a player's pack, comparable.
func _bag(i: int) -> String:
	var out: Array = []
	for it: Dictionary in he(i).character.inventory.slots:
		if not it.is_empty():
			out.append("%s x%d" % [it.get("base", ""), int(it.get("count", 1))])
	out.sort()
	return ", ".join(out)

## Host and both clients tell the same story.
func _agree() -> void:
	rig.run(1.0)
	var f := str(town(T).faction)
	for i in 2:
		t.eq(ic(i).coin(), he(i).character.inventory.coin, "client %d's coin" % i)
		t.eq(lc(i).standing(f), life().standing(he(i).id, f), "client %d's standing" % i)
		t.eq(int(rc(i).sheet.get("xp", -1)), he(i).character.xp, "client %d's XP" % i)
		t.eq(int(rc(i).sheet.get("level", -1)), he(i).character.level, "client %d's level" % i)
		var host_log: Array = deals().quest_log(he(i)).map(func(q: Dictionary) -> String: return "%s:%s" % [q["id"], q["state"]])
		var mirror_log: Array = dc(i).quests.map(func(q: Dictionary) -> String: return "%s:%s" % [q["id"], q["state"]])
		host_log.sort()
		mirror_log.sort()
		t.eq(mirror_log, host_log, "client %d's quest log" % i)
		t.check(rig.in_sync(i), "client %d's world matches the host's" % i)
	t.eq(sim().audit(), [] as Array[String], "the sim's audit is clean at the end")
	print("    deals: %s" % deals().summary())
	print("    life: %s" % life().summary())

# --- 10. save, stop, load, rejoin ----------------------------------------------------------------

func _snap(i: int) -> Dictionary:
	var f := str(town(T).faction)
	var e := he(i)
	var q: Array = deals().quest_log(e).map(func(x: Dictionary) -> String: return "%s:%s" % [x["id"], x["state"]])
	q.sort()
	var seen: Array = (deals().seen.get(e.id, {}) as Dictionary).keys().map(func(k: Variant) -> int: return int(k))
	seen.sort()
	return {"coin": e.character.inventory.coin, "bag": _bag(i), "standing": life().standing(e.id, f), "quests": q,
		"rumours": (deals().known.get(e.id, []) as Array).size(), "seen": seen, "gifts": int((deals().gifts.get(e.id, {}) as Dictionary).get(f, 0)),
		"level": e.character.level, "xp": e.character.xp}

func _persist() -> void:
	var before := [_snap(0), _snap(1)]
	var sold0 := JSON.stringify((deals()._sold_today(T) as Dictionary).keys())
	var dir := ProjectSettings.globalize_path(SAVE_DIR)
	_rm(dir)
	for i in 2:
		rig.clients[i].leave() if rig.clients[i].has_method("leave") else rig.cut(i)
	rig.run(0.5)
	rig.host.world_saver = WorldSave.save
	t.eq(rig.host.save(dir), OK, "saved")
	var w2 := WorldSave.load(dir)
	t.check(w2 != null, "the world loads")
	if w2 == null:
		return
	rig = Rig.new(w2, 0.03)
	Systems.install_host(rig.host)
	_quiet_host()
	t.eq(rig.host.load_players(dir), 2, "two player records")
	t.check(rig.host.load_state(dir), "host state loads")
	_join()
	t.check(_ready(), "both rejoined")
	rig.run(2.0)
	var after := [_snap(0), _snap(1)]
	for i in 2:
		for k: String in before[i]:
			t.eq(after[i][k], before[i][k], "player %d: %s persisted" % [i, k])
		t.eq(dc(i).rumours.size(), int(before[i]["rumours"]), "client %d heard its rumours again" % i)
		t.check(dc(i).seen.size() == (before[i]["seen"] as Array).size(), "client %d: the map remembers" % i)
		t.eq(ic(i).coin(), he(i).character.inventory.coin, "client %d's coin" % i)
		t.eq(lc(i).standing(str(town(T).faction)), int(before[i]["standing"]), "client %d's standing" % i)
	t.eq(JSON.stringify((deals()._sold_today(T) as Dictionary).keys()), sold0, "the rack stays sold today")
	t.eq(sim().audit(), [] as Array[String], "the audit is clean after the load")
	_rm(dir)

func _rm(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_rm(dir.path_join(sub))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
