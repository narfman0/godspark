## Life (HostSystem.LIFE): the sim's people in the world. Who fights whom (stance, through
## combat.hostile and the monster brains), each player's standing with each sim faction,
## settlements and road parties materialized near players and written back as they fight
## (LifeTown, LifeRoad), and the client mirror (LifeCodec, LifeClient).
##
##   life.stance(a, b) -> int        Life.HOSTILE / NEUTRAL / FRIENDLY (symmetric)
##   life.hostile(a, b) -> bool      stance == HOSTILE (what combat and brains ask)
##   life.faction_of(e) -> String    "players", a sim faction id ("3"), or "wild"
##   life.standing(entity_id, faction) -> int      -100..100 (a Bond sets a floor)
##   life.add_standing(entity_id, faction, n, why)
##   life.actors_at(site_id), life.actors_of(party_id) -> Array[HostEntity]
##   life.cheat_party(kind, from_site, to_site, frac := 0.9) -> int   (tests, smokes: party id)
## Entity meta on what it spawns: sim {kind: settlement | party, id, role, ...}, faction,
## talk, friendly, torch (guards at night). Docs: docs/tracks/life.md.
class_name LifeSystem
extends HostSystem

var host: WorldHost:
	get:
		return _host.get_ref() if _host != null else null
var _host: WeakRef
var town: LifeTown
var road: LifeRoad
## Materialize at all (stance and standing work regardless).
var enabled := true
## Print what happens (tools).
var debug := false
## entity id -> {kind, id, role, slot?}: every actor Life spawned
var actors := {}
## player entity id -> {faction: int}
var _standing := {}
## faction -> {entity id: until (host seconds)}: attacked that faction's people
var _grudge := {}
## counters per key (people generations), saved with the world
var _gen := {}
var _credited := {}          # lair id -> true (clear_lair paid once)
var _seen_dead := {}
var _cache := {}
var _cache_tick := -1
var _t := 0.0
var _sim: WorldSim = null
var _out_people: Array = []  # [info] to announce
var _out_gone: Array = []
var _factions_sent := {}     # player id -> faction count sent
var stats := {"towns": 0, "parties": 0, "folded": 0, "spawned": 0, "town_deaths": 0, "party_deaths": 0,
	"clashes": 0, "ambushes_done": 0, "raids": 0, "raids_done": 0, "raids_stopped": 0, "dropped": 0, "standing_changes": 0}

func sys_id() -> int:
	return HostSystem.LIFE

func attach(h: WorldHost) -> void:
	_host = weakref(h)
	SimData.ensure()
	town = LifeTown.new(self)
	road = LifeRoad.new(self)

func monsters(h: WorldHost) -> MonstersSystem:
	return h.system(HostSystem.MONSTERS) as MonstersSystem

func now() -> float:
	return host.tick_count / float(K.TICK_HZ)

# --- stance ----------------------------------------------------------------------------------

func faction_of(e: HostEntity) -> String:
	return Life.faction_of(e)

func hostile(a: HostEntity, b: HostEntity) -> bool:
	return stance(a, b) == Life.HOSTILE

## Who fights whom, the same both ways:
## - players among themselves, and people of one faction: FRIENDLY
## - a grudge (one attacked the other's faction or provoked the creature): HOSTILE
## - wild creatures: HOSTILE to everyone not wild, unless the ecology table calls them
##   neutral (NEUTRAL) or a player has their Bond (FRIENDLY); NEUTRAL among themselves
## - a player and a faction's people: by standing (raiders by raiders_spare_at); a Bond
##   with the people raises standing to bond_floor
## - two factions: HOSTILE at war, or when one side is out raiding and the sim's own raid
##   test says so (SimConflict._hostile); FRIENDLY with good relations, else NEUTRAL
func stance(a: HostEntity, b: HostEntity) -> int:
	if a == b:
		return Life.FRIENDLY
	var h := host
	if h.tick_count != _cache_tick:
		_cache.clear()
		_cache_tick = h.tick_count
	var key := mini(a.id, b.id) * 1048576 + maxi(a.id, b.id)
	if _cache.has(key):
		return _cache[key]
	var s := _stance(a, b)
	_cache[key] = s
	return s

func _stance(a: HostEntity, b: HostEntity) -> int:
	if a.is_player() and b.is_player():
		return Life.FRIENDLY
	if _grudged(a, b) or _grudged(b, a) or _provoked(a, b) or _provoked(b, a):
		return Life.HOSTILE
	var fa := Life.faction_of(a)
	var fb := Life.faction_of(b)
	if a.is_player():
		return _vs_player(a, b, fb)
	if b.is_player():
		return _vs_player(b, a, fa)
	if fa == "wild" or fb == "wild":
		if fa == fb:
			return Life.NEUTRAL
		return Life.NEUTRAL if _calm_beast(a if fa == "wild" else b) else Life.HOSTILE
	if fa == fb:
		return Life.FRIENDLY
	return _factions(a, b, int(fa), int(fb))

func _grudged(holder: HostEntity, other: HostEntity) -> bool:
	var g: Dictionary = _grudge.get(Life.faction_of(holder), {})
	return not g.is_empty() and float(g.get(other.id, -1.0)) > now()

static func _provoked(x: HostEntity, y: HostEntity) -> bool:
	return x.brain is MonsterBrain and (x.brain as MonsterBrain).provoked.has(y.id)

static func _calm_beast(w: HostEntity) -> bool:
	return w.brain is MonsterBrain and (w.brain as MonsterBrain).hostility == "neutral" and not (w.brain is LifeBrain)

static func _raider(x: HostEntity) -> bool:
	var s: Variant = x.get_meta("sim", {})
	return s is Dictionary and String((s as Dictionary).get("party", "")) in ["raid", "army"]

## The factions a raider's party is out to raid (its target settlement, or the towns at the
## ends of the route it waits on).
static func _raid_targets(sim: WorldSim, x: HostEntity) -> Array:
	var info: Dictionary = x.get_meta("sim", {})
	var p: SimParty = sim.parties.get(int(info.get("id", -1)))
	return LifeRoad._raid_victims(sim, p) if p != null else []

func _vs_player(p: HostEntity, x: HostEntity, fx: String) -> int:
	if fx == "wild":
		if x.brain is MonsterBrain:
			var bk := (x.brain as MonsterBrain).bond_key
			if bk != "" and _bond(p.id, bk) >= 1:
				return Life.FRIENDLY
		return Life.NEUTRAL if _calm_beast(x) else Life.HOSTILE
	if fx == "players":
		return Life.FRIENDLY
	var s := standing(p.id, fx)
	if _raider(x):
		return Life.NEUTRAL if s >= int(Life.num("raiders_spare_at", 60)) else Life.HOSTILE
	if s <= int(Life.num("hostile_at", -40)):
		return Life.HOSTILE
	if s >= int(Life.num("friendly_at", 30)):
		return Life.FRIENDLY
	return Life.NEUTRAL

func _factions(a: HostEntity, b: HostEntity, fa: int, fb: int) -> int:
	var sim := host.sim
	if sim == null:
		return Life.NEUTRAL
	# as in the sim: peoples fight only at war, or when one side is out raiding
	var fw: SimFaction = sim.factions.get(fa)
	if fw != null and fw.at_war(fb):
		return Life.HOSTILE
	if (_raider(a) or _raider(b)) and SimConflict._hostile(sim, fa, fb, true):
		return Life.HOSTILE
	if (_raider(a) and fb in _raid_targets(sim, a)) or (_raider(b) and fa in _raid_targets(sim, b)):
		return Life.HOSTILE
	if sim.factions.has(fa) and (sim.factions[fa] as SimFaction).rel(fb) >= 40.0:
		return Life.FRIENDLY
	return Life.NEUTRAL

func _bond(pid: int, key: String) -> int:
	var rules := host.system(HostSystem.RULES)
	if rules == null or not rules.has_method("bond"):
		return 0
	return int(rules.call("bond", pid, key))

# --- standing --------------------------------------------------------------------------------

func standing(entity_id: int, faction: String) -> int:
	var v := int((_standing.get(entity_id, {}) as Dictionary).get(faction, int(Life.num("start", 0))))
	var sim := host.sim if host != null else null
	if sim != null and faction.is_valid_int() and sim.factions.has(int(faction)):
		if _bond(entity_id, "people:" + (sim.factions[int(faction)] as SimFaction).culture) >= 1:
			v = maxi(v, int(Life.num("bond_floor", 30)))
	return clampi(v, -100, 100)

func add_standing(entity_id: int, faction: String, n: int, why: String) -> void:
	if n == 0 or not Life.is_sim_faction(faction):
		return
	var e := host.entity(entity_id)
	if e == null or not e.is_player():
		return
	if not _standing.has(entity_id):
		_standing[entity_id] = {}
	var d: Dictionary = _standing[entity_id]
	d[faction] = clampi(int(d.get(faction, int(Life.num("start", 0)))) + n, -100, 100)
	_cache.clear()
	stats["standing_changes"] += 1
	if debug:
		print("LIFE standing %s with %s %+d -> %d: %s" % [e.name, faction, n, int(d[faction]), why])
	host.send_sys(sys_id(), LifeCodec.Msg.STANDING, LifeCodec.write({"faction": faction, "value": standing(entity_id, faction),
		"why": why, "n": n}), entity_id)

func save_player(e: HostEntity) -> Dictionary:
	return {"standing": (_standing.get(e.id, {}) as Dictionary).duplicate()}

func load_player(e: HostEntity, d: Dictionary) -> void:
	var s := {}
	var src: Variant = d.get("standing", {})
	if src is Dictionary:
		for k: String in src:
			s[k] = int(src[k])
	_standing[e.id] = s

func save_world() -> Dictionary:
	return {"gen": _gen.duplicate(), "credited": WorldSim._sorted_keys(_credited)}

func load_world(d: Dictionary) -> void:
	_gen = {}
	for k: String in d.get("gen", {}):
		_gen[k] = int(d["gen"][k])
	for k: Variant in d.get("credited", []):
		_credited[int(k)] = true

func generation(key: String) -> int:
	return int(_gen.get(key, 0))

func bump(key: String) -> void:
	_gen[key] = generation(key) + 1

# --- spawning --------------------------------------------------------------------------------

## A person (or a party's beast): an SRD stat block through make_npc with the culture's
## species and lineage, spawned through Monsters (brains, nav, bodies) with a LifeBrain.
func spawn_person(h: WorldHost, o: Dictionary) -> HostEntity:
	var ms := monsters(h)
	if ms == null:
		return null
	var slug := String(o["slug"])
	if not h.srd.pack.has_row("monster", slug):
		return null
	var culture := String(o.get("culture", ""))
	var c: Dictionary = SimData.cultures.get(culture, {})
	var pos: Vector2 = o["pos"]
	var brain := LifeBrain.new(String(Ecology.row(slug).get("brain", "bruiser")), pos)
	brain.fighter = bool(o.get("fighter", false))
	brain.life_role = String(o.get("role", "townsfolk"))
	brain.post = o.get("post", pos)
	brain.post_span = float(o.get("span", 2.0))
	if o.has("safe"):
		brain.safe = o["safe"]
	var opts := {"brain_obj": brain, "home": pos}
	if String(o.get("name", "")) != "":
		opts["name"] = String(o["name"])
	if culture != "":
		opts["bond"] = "people:" + culture
	var species := String(c.get("species", ""))
	if species != "" and h.srd.has_method("make_npc"):
		var npc: Variant = h.srd.call("make_npc", slug, species, String(c.get("lineage", "")))
		if npc != null:
			opts["combatant"] = npc
	var pk := Life.people_key(culture, String(o.get("role", "")), slug, bool(o.get("female", false))) if culture != "" else ""
	if pk != "":
		opts["people"] = pk
	var e := ms.spawn(slug, pos, opts)
	if e == null:
		return null
	brain.hostility = "hostile"       # Life's stance decides, not the ecology table
	brain.flees = true
	if bool(o.get("friendly", false)):
		e.set_meta("friendly", true)
	else:
		e.remove_meta("friendly")
	var info: Dictionary = (o.get("sim", {}) as Dictionary).duplicate()
	e.set_meta("sim", info)
	if int(o.get("faction", -1)) >= 0:
		e.set_meta("faction", str(int(o["faction"])))
	if bool(o.get("talk", false)):
		e.set_meta("talk", true)
	actors[e.id] = info
	stats["spawned"] += 1
	_out_people.append(_info(e))
	return e

func unspawn(h: WorldHost, id: int) -> void:
	actors.erase(id)
	if h.entity(id) != null:
		h.remove_entity(id)

func _info(e: HostEntity) -> Dictionary:
	var s: Dictionary = e.get_meta("sim", {})
	var d := {"id": e.id, "role": String(s.get("role", "")), "kind": String(s.get("kind", "")), "of": int(s.get("id", -1)),
		"faction": Life.faction_of(e), "talk": bool(e.get_meta("talk", false)), "name": e.name,
		"torch": String(s.get("role", "")) == "guard" and String(s.get("kind", "")) == "settlement",
		"wagon": String(s.get("role", "")) == "wagon"}
	# Interface: who a road party is (its plate: "Caravan of X, bound for Y"), as spawned
	if String(s.get("kind", "")) == "party":
		d["party"] = String(s.get("party", ""))
		var p: SimParty = host.sim.parties.get(int(s.get("id", -1))) if host != null and host.sim != null else null
		if p != null:
			d["home"] = p.home
			d["dest"] = p.dest
	return d

func actors_at(site_id: int) -> Array[HostEntity]:
	return town.actors_at(host, site_id)

func actors_of(party_id: int) -> Array[HostEntity]:
	return road.actors_of(host, party_id)

static func nearest(players: Array, pos: Vector2) -> float:
	var best := INF
	for p: HostEntity in players:
		var d := p.body.pos - pos
		best = minf(best, maxf(absf(d.x), absf(d.y)))
	return best

## Sim goods as item records: trade goods when Items has a row for them ("trade:<good>"),
## else their worth in coin.
static func good_item(good: String, n: int) -> Dictionary:
	Items.ensure()
	if Items.exists("trade:" + good):
		return Items.make("trade:" + good, n)
	var base := float((SimData.goods.get(good, {}) as Dictionary).get("base", 1.0))
	return Items.coin(maxi(1, roundi(base * n)))

# --- tick --------------------------------------------------------------------------------------

func tick(h: WorldHost) -> void:
	var dt := h.dt()
	_t += dt
	if h.sim == null:
		return
	if _sim != h.sim:
		_reset(h)
	_deaths(h)
	if _t >= float(Life.people_cfg().get("scan_s", 1.0)):
		_t = 0.0
		var players: Array = []
		for p: HostEntity in h.entities.values():
			if p.is_player():
				players.append(p)
		if enabled and monsters(h) != null:
			town.scan(h, players)
			road.scan(h, players)
		_expire_grudges()
		_run_scheduled(h)
		for p: HostEntity in players:
			if int(_factions_sent.get(p.id, -1)) != h.sim.factions.size():
				_send_factions(h, p)
	_flush(h)

## The sim was replaced (a load): everything shown goes, and is shown again from the new one.
func _reset(h: WorldHost) -> void:
	for sid: int in town.active.keys():
		town.fold(h, sid)
	for pid: int in road.active.keys():
		road.fold(h, pid)
	road.clashes.clear()
	road.settled.clear()
	road._paths.clear()
	_sim = h.sim

## Deaths of any creature (Monsters marks them): Life's people are written back; kills by
## players move standing.
func _deaths(h: WorldHost) -> void:
	var ms := monsters(h)
	if ms == null:
		return
	for id: int in ms.mons:
		var b: MonsterBrain = ms.mons[id]
		if not b.rec["dead"] or _seen_dead.has(id):
			continue
		_seen_dead[id] = true
		var e := h.entity(id)
		if e != null:
			_died(h, e, b)

func _died(h: WorldHost, e: HostEntity, b: MonsterBrain) -> void:
	var combat := h.system(HostSystem.COMBAT) as CombatSystem
	var killers: Array = []
	if combat != null and combat.actor(e) != null:
		killers = Array(combat.actor(e).killers)
	var info: Dictionary = actors.get(e.id, {})
	if debug:
		print("LIFE died %s (%s) at %s post %s killers %s" % [e.name, info.get("role", "-"), e.body.pos, (e.brain as LifeBrain).post if e.brain is LifeBrain else b.home,
			killers.map(func(k: int) -> String: return h.entity(k).name if h.entity(k) != null else str(k))])
	if not info.is_empty():
		actors.erase(e.id)
		_out_gone.append(e.id)
		if String(info.get("kind", "")) == "settlement":
			town.died(h, int(info["id"]), e, info)
		else:
			road.died(h, int(info["id"]), e, info, killers)
	var players: Array = killers.filter(func(id: int) -> bool: return h.entity(id) != null and h.entity(id).is_player())
	if players.is_empty():
		return
	var fe := Life.faction_of(e)
	var where := e.body.pos
	for pl: int in players:
		if Life.is_sim_faction(fe):
			var guard := String(info.get("role", "")) in ["guard", "escort", "soldier"]
			if not _raider(e):
				add_standing(pl, fe, int(Life.num("kill_guard" if guard else "kill_member", -20)), "killed one of their people")
			if String(info.get("kind", "")) == "settlement" and h.sim.settlements.has(int(info["id"])):
				h.sim.log_event("slain_by_players", {"by": h.entity(pl).name, "who": "a " + String(info.get("role", "person")),
					"site": h.sim.settlements[int(info["id"])].name})
		# its enemies near a faction's people are glad
		for f: String in _factions_near(h, where):
			if f != fe and _faction_hostile(h, f, e):
				add_standing(pl, f, int(Life.num("kill_raider" if _raider(e) else "kill_enemy", 3)), "killed an enemy near their people")
	# lairs that preyed on a faction's people and routes
	var lid := int(b.rec.get("lair", -1)) if b.rec is Dictionary else -1
	if lid >= 0:
		var cleared := not h.sim.lairs.has(lid) or (h.sim.lairs[lid] as SimLair).count() == 0
		for f: int in _preyed_on(h.sim, lid):
			for pl: int in players:
				add_standing(pl, str(f), int(Life.num("lair_kill", 1)), "hunted a lair that preyed on them")
				if cleared and not _credited.has(lid):
					add_standing(pl, str(f), int(Life.num("clear_lair", 12)), "cleared a lair that preyed on them")
		if cleared:
			_credited[lid] = true

## Factions whose shown people are within near_tiles of a point.
func _factions_near(h: WorldHost, pos: Vector2) -> Array:
	var r := Life.num("near_tiles", 80.0)
	var out: Array = []
	for id: int in actors:
		var a := h.entity(id)
		if a == null or a.body.pos.distance_to(pos) > r:
			continue
		var f := Life.faction_of(a)
		if Life.is_sim_faction(f) and not f in out:
			out.append(f)
	return out

## Would faction f's people fight x? Asked of one of its shown people.
func _faction_hostile(h: WorldHost, f: String, x: HostEntity) -> bool:
	for id: int in actors:
		var a := h.entity(id)
		if a != null and a != x and Life.faction_of(a) == f and not _raider(a):
			return _stance(a, x) == Life.HOSTILE
	return false

## Factions with a grievance against the lair, or whose settlements' routes it hunts.
static func _preyed_on(sim: WorldSim, lid: int) -> Array:
	var out: Array = []
	for sid: int in WorldSim._sorted_keys(sim.settlements):
		var s: SimSettlement = sim.settlements[sid]
		if s.grievance.has(lid) and not s.faction in out:
			out.append(s.faction)
	for rid: int in sim.route_lair_sites:
		if lid in sim.route_lair_sites[rid] and sim.route_by_id.has(rid):
			for sid: int in [int(sim.route_by_id[rid].a), int(sim.route_by_id[rid].b)]:
				if sim.settlements.has(sid) and not sim.settlements[sid].faction in out:
					out.append(sim.settlements[sid].faction)
	return out

## Combat's hook: e was hit (or missed) by src. Attacking a faction's people makes it hostile
## to the attacker for grudge_s (and costs a player standing when it was not already a
## foe); guards nearby run to the fight, townsfolk run for their doors; two parties coming
## to blows start a real-time ambush.
func on_combat_damage(e: HostEntity, _dealt: int, src: int) -> void:
	var h := host
	var a := h.entity(src)
	if a == null or a == e:
		return
	var fe := Life.faction_of(e)
	# an unprovoked attack (not between foes already) makes the whole faction hostile
	if Life.is_sim_faction(fe) and Life.faction_of(a) != fe and (not hostile(a, e) or _grudged(e, a)):
		if not _grudge.has(fe):
			_grudge[fe] = {}
		var fresh := float((_grudge[fe] as Dictionary).get(a.id, -1.0)) <= now()
		_grudge[fe][a.id] = now() + Life.num("grudge_s", 60.0)
		_cache.clear()
		if a.is_player() and fresh:
			add_standing(a.id, fe, int(Life.num("attack_member", -5)), "attacked one of their people")
	var ie: Dictionary = actors.get(e.id, {})
	var ia: Dictionary = actors.get(a.id, {})
	for inf: Dictionary in [ie, ia]:
		if String(inf.get("kind", "")) == "settlement":
			road.raid_blow(int(inf["id"]))
			town.fight_at(int(inf["id"]))
		elif String(inf.get("kind", "")) == "party":
			road.blow(int(inf["id"]))
	if String(ie.get("kind", "")) == "party" and String(ia.get("kind", "")) == "party" and int(ie["id"]) != int(ia["id"]):
		road.clash(h, int(ia["id"]), int(ie["id"]))
	if a.is_player() and String(ie.get("kind", "")) == "party":
		for k: String in road.clashes:
			if int(road.clashes[k]["ra"]) == int(ie["id"]) or int(road.clashes[k]["v"]) == int(ie["id"]):
				road.clashes[k]["players"][a.id] = true
	_alarm(h, e, a)

## People near a fight react: fighters of the victim's faction take on the attacker if it is
## their foe; civilians within 30 tiles run.
func _alarm(h: WorldHost, victim: HostEntity, attacker: HostEntity) -> void:
	for id: int in actors:
		var x := h.entity(id)
		if x == null or not (x.brain is LifeBrain) or x == attacker:
			continue
		var b: LifeBrain = x.brain
		var d := x.body.pos.distance_to(victim.body.pos)
		if b.fighter:
			if d <= 40.0 and hostile(x, attacker):
				b.alarm(attacker)
		elif d <= 30.0 and (hostile(x, attacker) or x == victim):
			b.alarm(attacker)

func _expire_grudges() -> void:
	var t := now()
	for f: String in _grudge.keys():
		var g: Dictionary = _grudge[f]
		for id: int in g.keys():
			if float(g[id]) <= t:
				g.erase(id)
		if g.is_empty():
			_grudge.erase(f)

func entity_removed(h: WorldHost, e: HostEntity) -> void:
	_seen_dead.erase(e.id)
	if actors.has(e.id):
		actors.erase(e.id)
		_out_gone.append(e.id)
	if e.is_player():
		_factions_sent.erase(e.id)

func entity_added(h: WorldHost, e: HostEntity) -> void:
	if e.is_player():
		_factions_sent.erase(e.id)
		var all: Array = []
		for id: int in actors:
			if h.entity(id) != null:
				all.append(_info(h.entity(id)))
		for i in range(0, all.size(), 40):
			h.send_sys(sys_id(), LifeCodec.Msg.PEOPLE, LifeCodec.write({"people": all.slice(i, i + 40)}), e.id)

func _send_factions(h: WorldHost, p: HostEntity) -> void:
	var list: Array = []
	for fid: int in WorldSim._sorted_keys(h.sim.factions):
		var f: SimFaction = h.sim.factions[fid]
		list.append({"id": str(fid), "name": f.name, "culture": f.culture, "alive": f.alive, "standing": standing(p.id, str(fid))})
	_factions_sent[p.id] = h.sim.factions.size()
	h.send_sys(sys_id(), LifeCodec.Msg.FACTIONS, LifeCodec.write({"factions": list}), p.id)

func _flush(h: WorldHost) -> void:
	if not _out_people.is_empty():
		for i in range(0, _out_people.size(), 40):
			h.send_sys(sys_id(), LifeCodec.Msg.PEOPLE, LifeCodec.write({"people": _out_people.slice(i, i + 40)}))
		_out_people.clear()
	if not _out_gone.is_empty():
		h.send_sys(sys_id(), LifeCodec.Msg.GONE, LifeCodec.write({"ids": _out_gone}))
		_out_gone = []

# --- cheats (tests, tools, smokes) ------------------------------------------------------------

var _scheduled: Array = []

## Host cheat: in `after_s` host seconds a raid (or caravan) from the nearest other settlement
## arrives at `to_site` (default: the settlement nearest the spawn point). Raids arriving at
## a watched settlement are fought in real time.
func schedule(kind: String, after_s: float, to_site := -1) -> void:
	_scheduled.append({"kind": kind, "at": now() + after_s, "to": to_site})

func _run_scheduled(h: WorldHost) -> void:
	for i in range(_scheduled.size() - 1, -1, -1):
		var job: Dictionary = _scheduled[i]
		if now() < float(job["at"]):
			continue
		_scheduled.remove_at(i)
		var to := int(job["to"])
		var sim := h.sim
		if to < 0:
			var bd := INF
			for sid: int in WorldSim._sorted_keys(sim.settlements):
				var d := absf(sim.settlements[sid].x - h.spawn.x)
				if d < bd:
					bd = d
					to = sid
		var from := -1
		var fd := INF
		for sid: int in WorldSim._sorted_keys(sim.settlements):
			if sid == to or sim.path_between(sid, to, WorldSim.ROAD | WorldSim.DEEP | WorldSim.LINK).is_empty():
				continue
			var d := absf(sim.settlements[sid].x - sim.settlements[to].x)
			if d < fd:
				fd = d
				from = sid
		var pid := cheat_party(String(job["kind"]), from, to, 1.0)
		if pid > 0:
			var p: SimParty = sim.parties[pid]
			p.leg = p.path.size() - 1
			p.frac = 0.0
			SimConflict._arrive(sim, p)
		print("LIFE cheat: %s %d from %s arrives at %s (%s)" % [job["kind"], pid, sim._site_label(from) if from >= 0 else "-",
			sim._site_label(to) if to >= 0 else "-", "fought in real time" if pid > 0 and sim.parties.has(pid) and sim.parties[pid].frozen else "resolved"])

func summary() -> String:
	return "towns %d, parties %d, spawned %d, alive %d, town deaths %d, party deaths %d, raids %d (done %d, stalled %d), ambushes %d, standing changes %d" % [
		stats["towns"], stats["parties"], stats["spawned"], actors.size(), stats["town_deaths"], stats["party_deaths"], stats["raids"],
		stats["raids_done"], int(stats.get("raids_stalled", 0)), stats["ambushes_done"], stats["standing_changes"]]

## Put a raid or a caravan on the road from one settlement to another, `frac` of the way along
## its last leg (raids attack the target on arrival). Returns the party id, or -1.
func cheat_party(kind: String, from_site: int, to_site: int, frac := 0.9, n := 6) -> int:
	var sim := host.sim
	if sim == null or not sim.settlements.has(from_site) or not sim.settlements.has(to_site):
		return -1
	var s: SimSettlement = sim.settlements[from_site]
	var c := SimData.culture(s.culture)
	var p: SimParty
	if kind == "raid":
		p = sim.new_party("raid", s.faction, s.culture, from_site, SimData.allocate(c.raiders, n))
		p.plan = {"mode": "settlement", "motive": "plunder", "leg": "out"}
		p.target = to_site
		s.out_raids += 1
	else:
		p = sim.new_party("caravan", s.faction, s.culture, from_site, SimData.allocate(c.escort, n))
		SimEconomy._add_member(p.members, String(c.people), 2)
		p.people = 2
		p.wagons = 1
		p.cargo = {"food": 100}
		p.plan = {"good": "food", "paid": 1.0, "dest_name": sim.settlements[to_site].name, "escort": float(n), "leg": "out"}
		s.out_caravans += 1
	if not sim.send(p, to_site, WorldSim.ROAD | WorldSim.DEEP | WorldSim.LINK):
		sim.remove_party(p)
		return -1
	p.leg = maxi(0, p.path.size() - 2)
	p.route = sim.route_id(p.path[p.leg], p.path[p.leg + 1])
	p.frac = frac
	return p.id
