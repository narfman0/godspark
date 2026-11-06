## Movement and everything with teeth: party travel and encounters, raids on caravans and
## settlements, patrols, monster lairs and their hunting packs, expeditions, war, sieges,
## conquest, sack and tribute.
class_name SimConflict
extends RefCounted

## Raid launch chance per econ tick per unit of raiding drive.
const RAID_P := 0.02
## Lair hunt chance per day at full hunger, per party on a hunted route.
const LAIR_HUNT := 0.03
## Raiders can carry this much loot each (food units; coin is unlimited).
const CARRY := 25
const AMBUSH_DAYS := 12
const PATROL_DAYS := 20
const SIEGE_DAYS := 40
const TEMPER_RAID := {"raider": 0.35, "expansionist": 0.12, "trader": 0.0, "isolationist": 0.0}

# ── Parties: movement, arrivals, encounters ──────────────────────────────────

static func tick_parties(sim: WorldSim, hours: int) -> void:
	for pid in sim.parties.keys():
		if not sim.parties.has(pid):
			continue
		var p: SimParty = sim.parties[pid]
		if p.frozen:
			continue        # held by real time (Life)
		match p.state:
			"travel":
				_advance(sim, p, float(hours))
			"ambush", "patrol":
				p.timer -= hours
				if p.timer <= 0.0:
					SimEconomy._go_home(sim, p)
	_encounters(sim, hours)

static func _advance(sim: WorldSim, p: SimParty, hours: float) -> void:
	while hours > 0.0 and p.state == "travel":
		if p.path.size() < 2 or p.leg >= p.path.size() - 1:
			_arrive(sim, p)
			return
		var leg_h: float = sim.leg_hours(p.kind, p.route)
		# Raiders and patrols stop halfway along their target route.
		var stop_frac := 1.0
		if p.route == p.target and p.plan.get("mode", "") == "route" and p.plan.get("leg", "out") == "out":
			stop_frac = 0.5
		var remain := (stop_frac - p.frac) * leg_h
		if hours < remain:
			p.frac += hours / leg_h
			return
		hours -= maxf(remain, 0.0)
		if stop_frac < 1.0:
			p.frac = stop_frac
			p.state = "ambush" if p.kind == "raid" else "patrol"
			p.timer = (AMBUSH_DAYS if p.kind == "raid" else PATROL_DAYS) * WorldSim.DAY_H
			return
		p.leg += 1
		p.frac = 0.0
		if p.leg >= p.path.size() - 1:
			_arrive(sim, p)
			return
		p.route = sim.route_id(p.path[p.leg], p.path[p.leg + 1])

static func _arrive(sim: WorldSim, p: SimParty) -> void:
	var home_leg: bool = p.plan.get("leg", "out") == "home"
	if not home_leg and _handed_off(sim, p):
		p.frozen = true     # players are watching: the fight is fought in real time (Life)
		return
	match p.kind:
		"caravan":
			SimEconomy.caravan_arrive(sim, p)
		"migrants":
			if home_leg:
				SimEconomy.return_home(sim, p)
			else:
				SimEconomy.migrants_arrive(sim, p)
		"settlers":
			if home_leg:
				SimEconomy.return_home(sim, p)
			else:
				SimEconomy.settlers_arrive(sim, p)
		"pack":
			if home_leg:
				_pack_home(sim, p)
			else:
				_pack_attack(sim, p)
		_:
			if home_leg:
				SimEconomy.return_home(sim, p)
				return
			match p.kind:
				"raid":
					if p.plan.get("mode", "") == "settlement":
						_raid_settlement(sim, p)
					else:
						SimEconomy._go_home(sim, p)
				"army":
					_begin_siege(sim, p)
				"expedition":
					_assault_lair(sim, p)
				_:
					SimEconomy._go_home(sim, p)

## A raid or monster attack arriving at a settlement players watch is handed to real time.
static func _handed_off(sim: WorldSim, p: SimParty) -> bool:
	if not (p.kind == "pack" or (p.kind == "raid" and p.plan.get("mode", "") == "settlement")):
		return false
	var here: int = p.path[p.path.size() - 1] if not p.path.is_empty() else -1
	return sim.settlements.has(here) and sim.settlements[here].watched

static func _encounters(sim: WorldSim, hours: int) -> void:
	# Ambushes are checked every party tick (an hour: trips are short now); patrol clashes and
	# lair hunts every 6 hours as before (lair hunts scaled by _exposure, so the danger of a
	# trip stays what it was).
	var slow := sim.t % 6 == 0
	var on_route := {}
	for pid in sim.parties:
		var p: SimParty = sim.parties[pid]
		if p.route < 0 or p.path.size() < 2 or p.leg >= p.path.size() - 1:
			continue
		if not on_route.has(p.route):
			on_route[p.route] = []
		on_route[p.route].append(p)
	for rid in on_route:
		var list: Array = on_route[rid]
		# Patrols hunt raiders waiting in ambush.
		for pa in list:
			if pa.state != "patrol" or not sim.parties.has(pa.id):
				continue
			for ra in list:
				if ra.state == "ambush" and sim.parties.has(ra.id) and sim.parties.has(pa.id) \
						and slow and _hostile(sim, ra.faction, pa.faction, false) and sim.rng.randf() < 0.25 \
						and not (pa.watched or ra.watched):
					_patrol_clash(sim, pa, ra, rid)
		# Raiders spring on travellers.
		for ra in list:
			if ra.state != "ambush" or not sim.parties.has(ra.id):
				continue
			for v in list:
				if not sim.parties.has(ra.id) or ra.state != "ambush":
					break
				if v.state != "travel" or not sim.parties.has(v.id):
					continue
				if not (v.kind in ["caravan", "migrants", "settlers"]):
					continue
				if not _hostile(sim, ra.faction, v.faction, true):
					continue
				if sim.rng.randf() < 0.65 and not (ra.watched or v.watched):
					var helpers: Array = []
					for pa in list:
						if pa.state == "patrol" and sim.parties.has(pa.id) and not _hostile(sim, pa.faction, v.faction, false) \
								and _hostile(sim, pa.faction, ra.faction, false):
							helpers.append(pa)
					_ambush(sim, ra, v, rid, helpers)
		# Lairs hunt along the route.
		if not slow:
			continue
		for v in list:
			if not sim.parties.has(v.id) or v.state == "siege" or v.kind == "pack":
				continue
			for lsid in sim.route_lair_sites.get(rid, []):
				if not sim.lairs.has(lsid):
					continue
				var l: SimLair = sim.lairs[lsid]
				if l.out > 0 or l.count() == 0:
					continue
				var chance := LAIR_HUNT * l.hunger * l.hunger * 6.0 / 24.0 * _exposure(sim, rid)
				if sim.rng.randf() < chance and not v.watched:
					if _lair_hunt(sim, l, v, rid):
						break

## How much shorter a trip is on screen than in planning distance: hazards that scale with time
## on the road are scaled up by it so the danger of one trip stays what it was.
static func _exposure(sim: WorldSim, rid: int) -> float:
	return float(sim.route_hours[rid]) / maxf(sim.leg_hours("caravan", rid), 0.05)

static func _hostile(sim: WorldSim, a: int, b: int, raiding: bool) -> bool:
	if a == b or a < 0 or b < 0:
		return a != b
	if not sim.factions.has(a) or not sim.factions.has(b):
		return true
	var fa: SimFaction = sim.factions[a]
	if fa.at_war(b):
		return true
	var limit := -30.0
	if raiding:
		limit = 25.0 if fa.temperament == "raider" else -25.0
	return fa.rel(b) < limit

# ── Fights and their bookkeeping ─────────────────────────────────────────────

static func people_slug(culture: String) -> String:
	if SimData.cultures.has(culture):
		return str(SimData.cultures[culture].people)
	return "commoner"

## Remove the dead from a party; non-combatant losses come out of `people`.
static func party_losses(p: SimParty, dead: Dictionary) -> int:
	var total := 0
	var pslug := people_slug(p.culture)
	var before := p.size()
	var keys := dead.keys()
	keys.sort()
	for slug in keys:
		var n: int = mini(int(dead[slug]), int(p.members.get(slug, 0)))
		if n <= 0:
			continue
		if slug == pslug and not p.plan.has("levy"):
			var have: int = p.members[slug]
			var pd := mini(int(round(n * float(mini(p.people, have)) / maxf(have, 1))), p.people)
			p.people -= pd
		p.members[slug] = int(p.members[slug]) - n
		if p.members[slug] <= 0:
			p.members.erase(slug)
		total += n
	if p.plan.has("levy") and before > 0:
		p.people = mini(int(round(p.people * float(p.size()) / before)), p.size())
	p.people = mini(p.people, p.size())
	return total

## A settlement's defenders: the garrison plus armed townsfolk. Returns [side, militia].
static func defenders(s: SimSettlement) -> Array:
	var side := s.garrison()
	var militia := mini(int(s.workers * 0.1), 150)
	SimEconomy._add_member(side, people_slug(s.culture), militia)
	return [side, militia]

static func wall_ac(s: SimSettlement) -> int:
	return {"hamlet": 0, "village": 1, "town": 2, "city": 3}.get(s.tier, 0)

## Apply losses to a settlement's defenders. Returns the number killed.
static func settlement_losses(s: SimSettlement, dead: Dictionary, militia: int) -> int:
	var gar := s.garrison()
	var pslug := people_slug(s.culture)
	var killed := 0
	var keys := dead.keys()
	keys.sort()
	for slug in keys:
		var n: int = dead[slug]
		killed += n
		if slug == pslug:
			var g: int = gar.get(slug, 0)
			var mil := mini(int(round(n * float(militia) / maxf(militia + g, 1))), militia)
			var wk := mini(mil, s.workers)
			s.workers -= wk
			s.soldiers = maxi(s.soldiers - (n - wk), 0)
		else:
			s.soldiers = maxi(s.soldiers - n, 0)
	return killed

static func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	for k in b:
		out[k] = int(out.get(k, 0)) + int(b[k])
	return out

## Split a merged side's losses back over its parties, in proportion to what each brought.
static func _split_dead(dead: Dictionary, parts: Array) -> Array:
	var out: Array = []
	for i in parts.size():
		out.append({})
	var keys := dead.keys()
	keys.sort()
	for slug in keys:
		var n: int = dead[slug]
		var total := 0
		for p in parts:
			total += int(p.members.get(slug, 0))
		var left := n
		for i in parts.size():
			var have: int = parts[i].members.get(slug, 0)
			var share := left if i == parts.size() - 1 else mini(int(round(n * float(have) / maxf(total, 1))), left)
			share = mini(share, have)
			if share > 0:
				out[i][slug] = share
				left -= share
	return out

static func _rel_hit(sim: WorldSim, victim: int, attacker: int, amount: float) -> void:
	if sim.factions.has(victim) and sim.factions.has(attacker) and victim != attacker:
		var v: SimFaction = sim.factions[victim]
		v.relations[attacker] = maxf(v.rel(attacker) - amount, -100.0)
		var a: SimFaction = sim.factions[attacker]
		a.relations[victim] = maxf(a.rel(victim) - amount * 0.3, -100.0)

static func _home_name(sim: WorldSim, p: SimParty) -> String:
	if p.plan.has("src_name"):
		return str(p.plan.src_name)
	return sim._site_label(p.home) if sim.site_by_id.has(p.home) else "?"

static func _adj(culture: String) -> String:
	return str(SimData.cultures[culture].adj) if SimData.cultures.has(culture) else culture

static func _take_loot(p: SimParty, from_cargo: Dictionary, cap: int) -> Dictionary:
	var taken := {}
	for g in SimData.good_names:
		var have: int = from_cargo.get(g, 0)
		if have <= 0 or cap <= 0:
			continue
		var n := mini(have, cap)
		from_cargo[g] = have - n
		if from_cargo[g] <= 0:
			from_cargo.erase(g)
		p.cargo[g] = int(p.cargo.get(g, 0)) + n
		taken[g] = n
		cap -= n
	return taken

static func _ambush(sim: WorldSim, ra: SimParty, v: SimParty, rid: int, helpers: Array) -> void:
	var parts: Array = [v]
	parts.append_array(helpers)
	var side := {}
	for p in parts:
		side = _merge(side, p.members)
	var res := SimCombat.resolve(sim.rng, ra.members, side, {"a_ambush": 0.5, "a_break": 0.5, "b_break": 0.6})
	var raider_dead := party_losses(ra, res.a_dead)
	var splits := _split_dead(res.b_dead, parts)
	var victim_dead := 0
	for i in parts.size():
		victim_dead += party_losses(parts[i], splits[i])
	ambush_outcome(sim, ra, v, rid, helpers, res.winner == "a", raider_dead, victim_dead)

## The rest of an ambush once its fight is decided: here, or in real time by Life (losses
## already written back). Loot, captives, threat, relations, the chronicle, who goes home.
static func ambush_outcome(sim: WorldSim, ra: SimParty, v: SimParty, rid: int, helpers: Array, won: bool,
		raider_dead: int, victim_dead: int) -> void:
	sim.stats_add("battles", 1)
	sim.stats_add("ambushes", 1)
	var loot_food := 0
	var loot_goods := 0
	var loot_coin := 0
	var captives := 0
	if won and ra.size() > 0:
		sim.stats_add("ambush_wins", 1)
		var taken := _take_loot(ra, v.cargo, ra.size() * CARRY)
		for g in taken:
			if g == "food": loot_food += taken[g]
			else: loot_goods += taken[g]
		loot_coin = int(v.coin)
		ra.coin += v.coin
		v.coin = 0.0
		if bool(SimData.cultures.get(ra.culture, {}).get("takes_captives", false)) and v.people > 0:
			captives = mini(v.people, maxi(ra.size() / 2, 1))
			var vs := people_slug(v.culture)
			v.people -= captives
			v.members[vs] = int(v.members.get(vs, 0)) - captives
			if v.members[vs] <= 0:
				v.members.erase(vs)
			SimEconomy._add_member(ra.members, vs, captives)
			ra.people += captives
			ra.plan["captives"] = float(int(ra.plan.get("captives", 0.0)) + captives)
		if v.kind == "caravan":
			sim.stats_add("caravans_lost", 1)
	sim.route_threat[rid] = float(sim.route_threat.get(rid, 0.0)) + 1.0 + victim_dead * 0.1
	_rel_hit(sim, v.faction, ra.faction, 14.0 if won else 7.0)
	sim.log_event("ambush", {
		"raiders": _adj(ra.culture), "rfaction": sim.faction_name(ra.faction), "rfrom": _home_name(sim, ra),
		"victim": v.kind, "vfrom": _home_name(sim, v), "vfaction": sim.faction_name(v.faction), "route": sim.route_name(rid),
		"won": won, "killed": victim_dead, "lost": raider_dead, "food": loot_food, "goods": loot_goods,
		"coin": loot_coin, "captives": captives, "patrol": not helpers.is_empty(), "motive": str(ra.plan.get("motive", "plunder")),
	})
	_after_fight(sim, v)
	for h in helpers:
		_after_fight(sim, h)
	if sim.parties.has(ra.id):
		if ra.size() == 0:
			_wiped(sim, ra)
		else:
			SimEconomy._go_home(sim, ra)
	if won and sim.parties.has(v.id) and v.plan.get("leg", "out") == "out":
		SimEconomy._go_home(sim, v)

## A party with no one left is gone; settle its home's counters.
static func _wiped(sim: WorldSim, p: SimParty) -> void:
	if sim.settlements.has(p.home):
		var h: SimSettlement = sim.settlements[p.home]
		match p.kind:
			"caravan": h.out_caravans = maxi(h.out_caravans - 1, 0)
			"raid": h.out_raids = maxi(h.out_raids - 1, 0)
			_: h.out_other = maxi(h.out_other - 1, 0)
	if p.kind == "pack" and sim.lairs.has(p.home):
		sim.lairs[p.home].out = maxi(sim.lairs[p.home].out - 1, 0)
	sim.remove_party(p)

static func _after_fight(sim: WorldSim, p: SimParty) -> void:
	if sim.parties.has(p.id) and p.size() == 0:
		_wiped(sim, p)

static func _patrol_clash(sim: WorldSim, pa: SimParty, ra: SimParty, rid: int) -> void:
	var res := SimCombat.resolve(sim.rng, pa.members, ra.members, {"a_break": 0.5, "b_break": 0.5})
	sim.stats_add("battles", 1)
	sim.stats_add("patrol_clashes", 1)
	var pd := party_losses(pa, res.a_dead)
	var rd := party_losses(ra, res.b_dead)
	var won: bool = res.winner == "a"
	sim.log_event("patrol_clash", {"patrol": sim.faction_name(pa.faction), "pfrom": _home_name(sim, pa),
		"raiders": _adj(ra.culture), "rfaction": sim.faction_name(ra.faction), "route": sim.route_name(rid),
		"won": won, "plost": pd, "rlost": rd})
	_rel_hit(sim, pa.faction, ra.faction, 5.0)
	sim.route_threat[rid] = maxf(float(sim.route_threat.get(rid, 0.0)) - (2.0 if won else 0.0), 0.0)
	_after_fight(sim, pa)
	_after_fight(sim, ra)
	if won and sim.parties.has(ra.id):
		SimEconomy._go_home(sim, ra)
	elif not won and sim.parties.has(pa.id):
		SimEconomy._go_home(sim, pa)

# ── Lairs ────────────────────────────────────────────────────────────────────

static func _lair_name(l: SimLair) -> String:
	return l.name

static func _lair_what(l: SimLair) -> String:
	for e in SimData.lairs.get(l.family, []):
		if e.id == l.kind:
			return str(e.name)
	return "monsters"

## Returns true if the lair attacked.
static func _lair_hunt(sim: WorldSim, l: SimLair, v: SimParty, rid: int) -> bool:
	var o := SimCombat.odds(l.monsters, v.members)
	if o < 0.4 and l.hunger < 0.85:
		return false
	var res := SimCombat.resolve(sim.rng, l.monsters, v.members, {"a_ambush": 0.4, "a_break": 0.4, "b_break": 0.6})
	sim.stats_add("battles", 1)
	sim.stats_add("lair_attacks", 1)
	var slain := _lair_losses(l, res.a_dead)
	var killed := party_losses(v, res.b_dead)
	var won: bool = res.winner == "a"
	var eaten := 0
	if won:
		eaten = mini(int(v.cargo.get("food", 0)), 40 * maxi(l.count(), 1))
		if eaten > 0:
			v.cargo.food = int(v.cargo.food) - eaten
	l.hunger = clampf(l.hunger - killed * 0.08 - eaten / 300.0 - (0.1 if won else 0.0), 0.0, 1.0)
	sim.stats_add("lair_kills", killed)
	sim.route_threat[rid] = float(sim.route_threat.get(rid, 0.0)) + 0.7
	if sim.settlements.has(v.home):
		var h: SimSettlement = sim.settlements[v.home]
		h.grievance[l.id] = float(h.grievance.get(l.id, 0.0)) + killed + (2.0 if won else 1.0)
	if killed > 0 or slain > 0 or eaten > 0:
		sim.log_event("lair_attack", {"lair": l.name, "what": _lair_what(l), "victim": v.kind,
			"vfrom": _home_name(sim, v), "route": sim.route_name(rid), "won": won, "killed": killed,
			"slain": slain, "food": eaten})
	_after_fight(sim, v)
	if won and sim.parties.has(v.id) and v.plan.get("leg", "out") == "out" and v.kind != "army":
		SimEconomy._go_home(sim, v)
	if l.count() == 0:
		_lair_gone(sim, l, "")
	return true

static func _lair_losses(l: SimLair, dead: Dictionary) -> int:
	var n := 0
	for slug in dead:
		var k: int = mini(int(dead[slug]), int(l.monsters.get(slug, 0)))
		l.monsters[slug] = int(l.monsters[slug]) - k
		if l.monsters[slug] <= 0:
			l.monsters.erase(slug)
		n += k
	return n

static func _lair_gone(sim: WorldSim, l: SimLair, by: String) -> void:
	sim.lairs.erase(l.id)
	var site: Dictionary = sim.site_by_id[l.id]
	if site.kind in ["settlement", "ruin"]:
		sim.ruins[l.id] = true
	if by == "":
		sim.log_event("lair_empty", {"lair": l.name, "what": _lair_what(l)})

static func _family_mask(fam: String) -> int:
	match fam:
		"surface": return WorldSim.ROAD | WorldSim.LINK
		"portal": return WorldSim.ROAD | WorldSim.DEEP | WorldSim.LINK
	return WorldSim.DEEP | WorldSim.LINK

static func _tick_lairs(sim: WorldSim) -> void:
	for lid in WorldSim._sorted_keys(sim.lairs):
		if not sim.lairs.has(lid):
			continue
		var l: SimLair = sim.lairs[lid]
		# Wild prey keeps a modest lair at most 3/4 hungry; a crowded one needs travellers.
		var ceiling := 0.75 if l.count() <= maxi(int(l.max_n * 0.6), 1) else 1.0
		if l.hunger < ceiling:
			l.hunger = minf(l.hunger + 0.0015 * l.hunger_rate * WorldSim.ECON_DAYS, ceiling)
		# Only a lair too big for the wild prey around it (hunger past 3/4) hunts towns.
		if l.out > 0 or l.count() == 0 or l.hunger < 0.78:
			continue
		var urge := (l.hunger - 0.6) / 0.4
		if sim.rng.randf() > 0.04 * urge * urge:
			continue
		# Hunt the nearest settlement within a short walk that looks beatable.
		var mask := _family_mask(l.family)
		var pr: Array = sim.paths_from(l.id, mask)
		var reach: float = WorldSim.REACH_DAYS.pack * WorldSim.DAY_H * WorldSim.SPEED.pack
		var best := -1
		var best_h := INF
		for sid in pr[2]:
			if not sim.settlements.has(sid) or pr[0][sid] > reach:
				continue
			var s: SimSettlement = sim.settlements[sid]
			if SimCombat.odds(l.monsters, defenders(s)[0], wall_ac(s)) < 0.45:
				continue
			if pr[0][sid] < best_h:
				best_h = pr[0][sid]
				best = sid
		if best < 0:
			continue
		var p := sim.new_party("pack", -1, l.kind, l.id, l.monsters.duplicate())
		p.plan = {"src_name": l.name}
		if not sim.send(p, best, mask):
			sim.remove_party(p)
			continue
		l.monsters = {}
		l.out = 1

static func _pack_attack(sim: WorldSim, p: SimParty) -> void:
	var here: int = p.path[p.path.size() - 1]
	if not sim.settlements.has(here):
		SimEconomy._go_home(sim, p)
		return
	var s: SimSettlement = sim.settlements[here]
	var dm := defenders(s)
	var res := SimCombat.resolve(sim.rng, p.members, dm[0], {"a_break": 0.5, "b_break": 0.45, "b_ac": wall_ac(s)})
	var slain := party_losses(p, res.a_dead)
	var killed := settlement_losses(s, res.b_dead, dm[1])
	pack_outcome(sim, p, s, res.winner == "a", killed, slain)

## The rest of a monster attack on a settlement once its fight is decided (here, or in real
## time by Life with losses already written back).
static func pack_outcome(sim: WorldSim, p: SimParty, s: SimSettlement, won: bool, killed: int, slain: int) -> void:
	var l: SimLair = sim.lairs.get(p.home)
	sim.stats_add("battles", 1)
	sim.stats_add("monster_raids", 1)
	var eaten_people := 0
	var eaten_food := 0
	if won and p.size() > 0:
		eaten_people = mini(mini(int(s.pop() * 0.03), p.size() * 2), s.workers + s.dependants)
		SimEconomy._kill(sim, s, eaten_people, false)
		eaten_food = int(s.stock.food * 0.1)
		s.stock.food -= float(eaten_food)
		s.last_raided = sim.t
	if l != null:
		l.hunger = clampf(l.hunger - (killed + eaten_people) * 0.06 - eaten_food / 400.0, 0.0, 1.0)
	s.grievance[p.home] = float(s.grievance.get(p.home, 0.0)) + killed + eaten_people + 2.0
	var what := _lair_what(l) if l != null else "monsters"
	sim.log_event("monster_raid", {"lair": str(p.plan.get("src_name", "?")), "what": what, "site": s.name,
		"won": won, "killed": killed + eaten_people, "slain": slain, "food": eaten_food})
	if p.size() == 0:
		_wiped(sim, p)
		return
	p.plan["leg"] = "home"
	if not sim.send(p, p.home, _family_mask(l.family if l != null else "portal")):
		_pack_home(sim, p)

static func _pack_home(sim: WorldSim, p: SimParty) -> void:
	if sim.lairs.has(p.home):
		var l: SimLair = sim.lairs[p.home]
		for slug in p.members:
			l.monsters[slug] = int(l.monsters.get(slug, 0)) + int(p.members[slug])
		l.out = maxi(l.out - 1, 0)
	sim.remove_party(p)

static func _assault_lair(sim: WorldSim, p: SimParty) -> void:
	var lid: int = p.target
	if not sim.lairs.has(lid):
		SimEconomy._go_home(sim, p)
		return
	var l: SimLair = sim.lairs[lid]
	var res := SimCombat.resolve(sim.rng, p.members, l.monsters, {"a_break": 0.5, "b_break": 0.95, "b_ac": 1})
	sim.stats_add("battles", 1)
	sim.stats_add("expeditions", 1)
	var lost := party_losses(p, res.a_dead)
	var slain := _lair_losses(l, res.b_dead)
	var won: bool = res.winner == "a" or l.count() == 0
	var hoard := 0
	if won:
		sim.stats_add("lairs_cleared", 1)
		hoard = int(SimData.group_xp(res.b_dead) * 0.05 + (600.0 if l.apex else 0.0))
		p.coin += hoard
		if sim.settlements.has(p.home):
			sim.settlements[p.home].grievance.erase(lid)
		# Any hunting pack still out has nowhere to come back to.
		_lair_gone(sim, l, "cleared")
	elif sim.settlements.has(p.home):
		var h: SimSettlement = sim.settlements[p.home]
		h.grievance[lid] = float(h.grievance.get(lid, 0.0)) * 0.5
	sim.log_event("lair_cleared" if won else "expedition_failed", {"lair": l.name, "what": _lair_what(l),
		"from": _home_name(sim, p), "faction": sim.faction_name(p.faction), "lost": lost, "slain": slain, "hoard": hoard})
	if p.size() == 0:
		_wiped(sim, p)
	else:
		SimEconomy._go_home(sim, p)

# ── Decisions (each econ tick) ───────────────────────────────────────────────

static func tick_decisions(sim: WorldSim) -> void:
	SimEconomy.build_market(sim)
	for sid in WorldSim._sorted_keys(sim.settlements):
		if not sim.settlements.has(sid):
			continue
		var s: SimSettlement = sim.settlements[sid]
		var t0 := Time.get_ticks_usec() if sim.profile else 0
		SimEconomy.decide(sim, s)
		t0 = sim._prof("d_trade", t0)
		if not sim.settlements.has(sid):
			continue
		_maybe_raid(sim, s)
		t0 = sim._prof("d_raid", t0)
		_maybe_patrol(sim, s)
		_maybe_expedition(sim, s)
		t0 = sim._prof("d_other", t0)
	_tick_lairs(sim)
	_tick_sieges(sim)

static func _maybe_raid(sim: WorldSim, s: SimSettlement) -> void:
	if s.out_raids > 0 or s.soldiers < 6 or s.besieged_by >= 0 or sim.t < int(s.cooldowns.get("raid", 0)):
		return
	var f: SimFaction = sim.factions[s.faction]
	var c := SimData.culture(s.culture)
	var sec := SimEconomy.security(s)
	var hungry := sec < 0.35 or s.hungry > 0
	var drive: float = float(c.raid) + float(TEMPER_RAID.get(f.temperament, 0.0))
	if hungry:
		drive += (0.35 - minf(sec, 0.35)) * 2.0 + 0.2
	if s.wealth < s.pop() * 0.5:
		drive += 0.1
	if not f.wars.is_empty():
		drive += 0.25
	if sim.rng.randf() > drive * RAID_P:
		return
	var mask := sim.mask_for(c.raid_mobility)
	var reach: float = WorldSim.REACH_DAYS.raid * WorldSim.DAY_H * WorldSim.SPEED.raid
	var pr: Array = sim.paths_from(s.id, mask)
	var dist: Dictionary = pr[0]
	var ids: Array = pr[2]
	var cands: Array = []
	var total := 0.0
	for rid in WorldSim._sorted_keys(sim.route_traffic):
		var r: Dictionary = sim.route_by_id[rid]
		if (r.cls & mask) == 0:
			continue
		var h := minf(dist.get(r.a, INF), dist.get(r.b, INF))
		if h > reach:
			continue
		var w := 0.0
		var tr: Dictionary = sim.route_traffic[rid]
		for fid in WorldSim._sorted_keys(tr):
			if fid != s.faction and (_hostile(sim, s.faction, fid, true) or (hungry and f.rel(fid) < 40.0)):
				w += float(tr[fid])
		if w > 0.0:
			w *= 1.0 - 0.5 * h / reach
			cands.append(["route", rid, w])
			total += w
	var n_raid := mini(int(s.soldiers * 0.6), 60)
	var comp := SimData.allocate(c.raiders, n_raid)
	for sid in ids:
		if not sim.settlements.has(sid) or dist[sid] > reach:
			continue
		var d: SimSettlement = sim.settlements[sid]
		if d.faction == s.faction or not _hostile(sim, s.faction, d.faction, true):
			continue
		var o := SimCombat.odds(comp, defenders(d)[0], wall_ac(d))
		if o < 0.6:
			continue
		var loot: float = d.stock.food * (2.0 if hungry else 0.5) + d.wealth
		var w2: float = loot / 600.0 * o * (1.0 - 0.5 * dist[sid] / reach)
		if sim.t - d.last_raided < 180 * WorldSim.DAY_H:
			w2 *= 0.3
		cands.append(["settlement", sid, w2])
		total += w2
	if cands.is_empty():
		return
	var roll := sim.rng.randf() * total
	var pick: Array = cands[cands.size() - 1]
	for cnd in cands:
		roll -= cnd[2]
		if roll <= 0.0:
			pick = cnd
			break
	var p: SimParty
	if pick[0] == "route":
		var r: Dictionary = sim.route_by_id[pick[1]]
		var near: int = r.a if dist.get(r.a, INF) <= dist.get(r.b, INF) else r.b
		var far: int = r.b if near == r.a else r.a
		var n := clampi(int(s.soldiers * 0.4), 4, 30)
		p = sim.new_party("raid", s.faction, s.culture, s.id, SimData.allocate(c.raiders, n))
		p.target = pick[1]
		p.plan = {"mode": "route", "motive": "hunger" if hungry else "plunder"}
		var path := sim.path_between(s.id, near, mask)
		if path.is_empty():
			sim.remove_party(p)
			return
		path.append(far)
		p.path = path
		p.leg = 0
		p.frac = 0.0
		p.dest = far
		p.route = sim.route_id(path[0], path[1])
		p.state = "travel"
	else:
		p = sim.new_party("raid", s.faction, s.culture, s.id, comp)
		p.target = pick[1]
		p.plan = {"mode": "settlement", "motive": "hunger" if hungry else "plunder"}
		if not sim.send(p, pick[1], mask):
			sim.remove_party(p)
			return
	s.soldiers -= p.size()
	s.out_raids += 1
	s.cooldowns["raid"] = sim.t + 120 * WorldSim.DAY_H
	sim.stats_add("raids_sent", 1)
	if not s.shock.is_empty():
		s.shock.raids = int(s.shock.raids) + 1

static func _raid_settlement(sim: WorldSim, p: SimParty) -> void:
	var here: int = p.path[p.path.size() - 1]
	if not sim.settlements.has(here):
		SimEconomy._go_home(sim, p)
		return
	var d: SimSettlement = sim.settlements[here]
	var dm := defenders(d)
	# Raiders want loot, not a last stand; defenders fall back behind doors once hurt.
	var res := SimCombat.resolve(sim.rng, p.members, dm[0], {"a_break": 0.4, "b_break": 0.35, "b_ac": wall_ac(d)})
	var lost := party_losses(p, res.a_dead)
	var killed := settlement_losses(d, res.b_dead, dm[1])
	raid_outcome(sim, p, d, res.winner == "a" and p.size() > 0, killed, lost)

## The rest of a raid on a settlement once its fight is decided: here, or in real time by
## Life (losses already written back). Plunder, captives, relations, the chronicle, home.
static func raid_outcome(sim: WorldSim, p: SimParty, d: SimSettlement, won: bool, killed: int, lost: int) -> void:
	sim.stats_add("battles", 1)
	sim.stats_add("settlement_raids", 1)
	won = won and p.size() > 0
	var food := 0
	var coin := 0
	var captives := 0
	if won:
		sim.stats_add("raid_wins", 1)
		var cap := p.size() * CARRY
		food = int(minf(d.stock.food * 0.3, cap))
		d.stock.food -= float(food)
		p.cargo["food"] = int(p.cargo.get("food", 0)) + food
		var rest := cap - food
		for g in ["luxuries", "tools", "ore"]:
			var n := int(minf(d.stock[g] * 0.4, rest))
			if n > 0:
				d.stock[g] -= float(n)
				p.cargo[g] = int(p.cargo.get(g, 0)) + n
				rest -= n
		coin = int(d.wealth * 0.3)
		d.wealth -= coin
		p.coin += coin
		if bool(SimData.culture(p.culture).takes_captives):
			captives = SimEconomy.take_people(d, mini(int(d.pop() * 0.05), p.size()))
			SimEconomy._add_member(p.members, people_slug(d.culture), captives)
			p.people += captives
			p.plan["captives"] = float(captives)
		d.morale = maxf(d.morale - 0.15, 0.0)
		d.last_raided = sim.t
	_rel_hit(sim, d.faction, p.faction, 20.0 if won else 10.0)
	sim.log_event("raid", {"raiders": _adj(p.culture), "rfaction": sim.faction_name(p.faction),
		"rfrom": _home_name(sim, p), "site": d.name, "won": won, "killed": killed, "lost": lost, "food": food,
		"coin": coin, "captives": captives, "motive": str(p.plan.get("motive", "plunder"))})
	if d.pop() < SimEconomy.ABANDON_POP:
		SimEconomy.abandon_settlement(sim, d, "raided")
	if p.size() == 0:
		_wiped(sim, p)
	else:
		SimEconomy._go_home(sim, p)

static func _maybe_patrol(sim: WorldSim, s: SimSettlement) -> void:
	if s.out_other > 0 or s.soldiers < 10 or s.besieged_by >= 0:
		return
	if sim.t < int(s.cooldowns.get("patrol", 0)):
		return
	var c := SimData.culture(s.culture)
	var mask := sim.mask_for(c.raid_mobility)
	var dist: Dictionary = sim.paths_from(s.id, mask)[0]
	var reach: float = WorldSim.REACH_DAYS.patrol * WorldSim.DAY_H * WorldSim.SPEED.patrol
	var best := -1
	var best_t := 1.2
	for rid in WorldSim._sorted_keys(sim.route_threat):
		var tr: Dictionary = sim.route_traffic.get(rid, {})
		if not tr.has(s.faction):
			continue
		var r: Dictionary = sim.route_by_id[rid]
		if (r.cls & mask) == 0 or minf(dist.get(r.a, INF), dist.get(r.b, INF)) > reach:
			continue
		if sim.route_threat[rid] > best_t:
			best_t = sim.route_threat[rid]
			best = rid
	if best < 0:
		return
	var r: Dictionary = sim.route_by_id[best]
	var near: int = r.a if dist.get(r.a, INF) <= dist.get(r.b, INF) else r.b
	var far: int = r.b if near == r.a else r.a
	var path := sim.path_between(s.id, near, mask)
	if path.is_empty():
		return
	path.append(far)
	var n := clampi(int(s.soldiers * 0.3), 4, 25)
	var p := sim.new_party("patrol", s.faction, s.culture, s.id, SimData.allocate(c.escort, n))
	p.target = best
	p.plan = {"mode": "route"}
	p.path = path
	p.dest = far
	p.route = sim.route_id(path[0], path[1])
	s.soldiers -= p.size()
	s.out_other += 1
	s.cooldowns["patrol"] = sim.t + 30 * WorldSim.DAY_H
	sim.stats_add("patrols", 1)

static func _maybe_expedition(sim: WorldSim, s: SimSettlement) -> void:
	if s.out_other > 0 or s.soldiers < 8 or s.besieged_by >= 0 or s.grievance.is_empty():
		return
	var lid := -1
	var worst := 10.0
	for k in WorldSim._sorted_keys(s.grievance):
		if not sim.lairs.has(k):
			s.grievance.erase(k)
			continue
		if s.grievance[k] > worst:
			worst = s.grievance[k]
			lid = k
	if lid < 0:
		return
	var l: SimLair = sim.lairs[lid]
	if l.out > 0:
		return
	var c := SimData.culture(s.culture)
	var n := mini(int(s.soldiers * 0.7), 120)
	var comp := SimData.allocate(c.army, n)
	if SimCombat.odds(comp, l.monsters, 1) < 0.65:
		return
	var p := sim.new_party("expedition", s.faction, s.culture, s.id, comp)
	p.target = lid
	if not sim.send(p, lid, sim.mask_for(c.raid_mobility) | WorldSim.LINK):
		sim.remove_party(p)
		return
	s.soldiers -= n
	s.out_other += 1

# ── Sieges ───────────────────────────────────────────────────────────────────

static func _begin_siege(sim: WorldSim, p: SimParty) -> void:
	var here: int = p.path[p.path.size() - 1]
	if not sim.settlements.has(here):
		SimEconomy._go_home(sim, p)
		return
	var d: SimSettlement = sim.settlements[here]
	var f: SimFaction = sim.factions.get(p.faction)
	if f == null or not f.at_war(d.faction) or d.besieged_by >= 0:
		SimEconomy._go_home(sim, p)
		return
	p.state = "siege"
	p.timer = SIEGE_DAYS * WorldSim.DAY_H
	p.target = here
	d.besieged_by = p.id
	sim.stats_add("sieges", 1)
	sim.log_event("siege", {"army": sim.faction_name(p.faction), "from": _home_name(sim, p), "site": d.name,
		"dfaction": sim.faction_name(d.faction), "n": p.size()})

static func _tick_sieges(sim: WorldSim) -> void:
	for pid in sim.parties.keys():
		if not sim.parties.has(pid):
			continue
		var p: SimParty = sim.parties[pid]
		if p.state != "siege":
			continue
		var d: SimSettlement = sim.settlements.get(p.target)
		if d == null or d.besieged_by != p.id:
			if d != null and d.besieged_by == p.id:
				d.besieged_by = -1
			SimEconomy._go_home(sim, p)
			continue
		p.timer -= WorldSim.ECON_H
		var f: SimFaction = sim.factions.get(p.faction)
		if f == null or not f.at_war(d.faction):
			d.besieged_by = -1
			SimEconomy._go_home(sim, p)
			continue
		if sim.rng.randf() < 0.25 + (0.4 if d.hungry > 0 else 0.0):
			_assault(sim, p, d)
		elif p.timer <= 0.0:
			d.besieged_by = -1
			sim.log_event("siege_lifted", {"army": sim.faction_name(p.faction), "site": d.name})
			SimEconomy._go_home(sim, p)

static func _assault(sim: WorldSim, p: SimParty, d: SimSettlement) -> void:
	var dm := defenders(d)
	var res := SimCombat.resolve(sim.rng, p.members, dm[0], {"a_break": 0.5, "b_break": 0.85, "b_ac": wall_ac(d)})
	sim.stats_add("battles", 1)
	var lost := party_losses(p, res.a_dead)
	var killed := settlement_losses(d, res.b_dead, dm[1])
	var f: SimFaction = sim.factions[p.faction]
	var enemy := d.faction
	_war_loss(sim, p.faction, enemy, lost)
	_war_loss(sim, enemy, p.faction, killed)
	d.besieged_by = -1
	if res.winner != "a" or p.size() == 0:
		sim.log_event("siege_broken", {"army": f.name, "site": d.name, "lost": lost, "killed": killed})
		if p.size() == 0:
			_wiped(sim, p)
		else:
			SimEconomy._go_home(sim, p)
		return
	var outcome := "tribute"
	match f.temperament:
		"expansionist": outcome = "conquest"
		"raider": outcome = "sack"
		"trader": outcome = "tribute" if sim.rng.randf() < 0.6 else "conquest"
		_: outcome = "tribute" if sim.rng.randf() < 0.7 else "sack"
	if outcome == "tribute" and d.tribute_to == f.id:
		outcome = "conquest"
	d.cooldowns["spared"] = sim.t + 2 * WorldSim.YEAR_H
	var old_faction := sim.faction_name(enemy)
	match outcome:
		"conquest":
			sim.stats_add("conquests", 1)
			d.faction = f.id
			d.tribute_to = -1
			var stay := mini(p.size() / 2, p.size())
			d.soldiers += stay
			_shrink_party(p, stay)
			d.morale = 0.3
			sim.log_event("conquered", {"army": f.name, "site": d.name, "old": old_faction, "killed": killed, "lost": lost})
			check_faction_alive(sim, enemy)
		"sack":
			sim.stats_add("sacks", 1)
			var coin := int(d.wealth * 0.6)
			d.wealth -= coin
			p.coin += coin
			var food := int(minf(d.stock.food * 0.5, p.size() * CARRY))
			d.stock.food -= float(food)
			p.cargo["food"] = int(p.cargo.get("food", 0)) + food
			var dead := int(d.pop() * 0.2)
			SimEconomy._kill(sim, d, dead, false)
			var captives := 0
			if bool(SimData.culture(p.culture).takes_captives):
				captives = SimEconomy.take_people(d, int(d.pop() * 0.1))
				SimEconomy._add_member(p.members, people_slug(d.culture), captives)
				p.people += captives
				p.plan["captives"] = float(captives)
			d.morale = 0.1
			d.last_raided = sim.t
			sim.log_event("sacked", {"army": f.name, "site": d.name, "killed": killed + dead, "coin": coin,
				"captives": captives})
			if d.pop() < SimEconomy.ABANDON_POP:
				SimEconomy.abandon_settlement(sim, d, "sacked")
		_:
			sim.stats_add("tributes", 1)
			d.tribute_to = f.id
			d.tribute_until = sim.t + 10 * WorldSim.YEAR_H
			sim.log_event("tribute", {"army": f.name, "site": d.name, "killed": killed})
	if sim.factions.has(enemy) and f.wars.has(enemy):
		f.wars[enemy].weariness = float(f.wars[enemy].weariness) - 1.0
		var e: SimFaction = sim.factions[enemy]
		if e.wars.has(f.id):
			e.wars[f.id].weariness = float(e.wars[f.id].weariness) + 3.0
	if sim.parties.has(p.id):
		SimEconomy._go_home(sim, p)

## Remove n soldiers from an army (they stay behind as a garrison).
static func _shrink_party(p: SimParty, n: int) -> void:
	var keys := p.members.keys()
	keys.sort()
	var total := p.size()
	var left := n
	for slug in keys:
		if left <= 0:
			break
		var k := mini(int(ceil(float(p.members[slug]) * n / maxf(total, 1))), mini(left, p.members[slug]))
		p.members[slug] = int(p.members[slug]) - k
		if p.members[slug] <= 0:
			p.members.erase(slug)
		left -= k
	p.people = mini(p.people, p.size())

static func _war_loss(sim: WorldSim, a: int, b: int, n: int) -> void:
	if sim.factions.has(a) and sim.factions[a].wars.has(b):
		var w: Dictionary = sim.factions[a].wars[b]
		w.losses = int(w.losses) + n
		w.weariness = float(w.weariness) + n / 40.0

static func check_faction_alive(sim: WorldSim, fid: int) -> void:
	if not sim.factions.has(fid) or not sim.factions[fid].alive:
		return
	for sid in sim.settlements:
		if sim.settlements[sid].faction == fid:
			return
	var f: SimFaction = sim.factions[fid]
	f.alive = false
	for gid in WorldSim._sorted_keys(f.wars):
		if sim.factions.has(gid):
			sim.factions[gid].wars.erase(fid)
	f.wars.clear()
	sim.stats_add("factions_fallen", 1)
	sim.log_event("faction_fell", {"faction": f.name, "culture": f.culture})

# ── Factions (monthly): relations, war and peace, armies ─────────────────────

static func tick_factions(sim: WorldSim) -> void:
	var ids := WorldSim._sorted_keys(sim.factions)
	for fid in ids:
		var f: SimFaction = sim.factions[fid]
		if not f.alive:
			continue
		for gid in ids:
			if gid == fid or not sim.factions[gid].alive:
				continue
			var g: SimFaction = sim.factions[gid]
			var base := sim.base_relation(f, g)
			f.relations[gid] = f.rel(gid) + (base - f.rel(gid)) * 0.03
	for fid in ids:
		var f: SimFaction = sim.factions[fid]
		if not f.alive:
			continue
		for gid in WorldSim._sorted_keys(f.wars):
			var w: Dictionary = f.wars[gid]
			w.weariness = float(w.weariness) + 0.12
			var g: SimFaction = sim.factions.get(gid)
			if g == null or not g.alive:
				f.wars.erase(gid)
				continue
			var gw: float = g.wars[fid].weariness if g.wars.has(fid) else 0.0
			if w.weariness + gw > 10.0 + sim.rng.randf() * 10.0:
				_make_peace(sim, f, g)
		for gid in ids:
			if gid == fid or f.at_war(gid) or not sim.factions[gid].alive:
				continue
			if f.rel(gid) > -60.0:
				continue
			var mult: float = {"expansionist": 2.0, "raider": 1.3, "trader": 0.6, "isolationist": 0.35}.get(f.temperament, 1.0)
			if sim.rng.randf() > 0.04 * mult:
				continue
			if not _can_reach_faction(sim, f, gid):
				continue
			var g: SimFaction = sim.factions[gid]
			f.wars[gid] = {"since": sim.t, "weariness": 0.0, "losses": 0}
			g.wars[fid] = {"since": sim.t, "weariness": 0.0, "losses": 0}
			sim.stats_add("wars", 1)
			sim.log_event("war", {"a": f.name, "b": g.name, "rel": int(f.rel(gid))})
		if not f.wars.is_empty():
			_maybe_army(sim, f)

static func _make_peace(sim: WorldSim, f: SimFaction, g: SimFaction) -> void:
	var w: Dictionary = f.wars[g.id]
	var years := (sim.t - int(w.since)) / float(WorldSim.YEAR_H)
	f.wars.erase(g.id)
	g.wars.erase(f.id)
	f.relations[g.id] = -15.0
	g.relations[f.id] = -15.0
	sim.stats_add("peaces", 1)
	sim.log_event("peace", {"a": f.name, "b": g.name, "years": int(round(years)), "losses": int(w.losses)})

static func _can_reach_faction(sim: WorldSim, f: SimFaction, gid: int) -> bool:
	var c := SimData.culture(f.culture)
	var mask := sim.mask_for(c.raid_mobility)
	var reach: float = WorldSim.REACH_DAYS.army * WorldSim.DAY_H * WorldSim.SPEED.army
	for sid in WorldSim._sorted_keys(sim.settlements):
		var s: SimSettlement = sim.settlements[sid]
		if s.faction != f.id:
			continue
		var dist: Dictionary = sim.paths_from(sid, mask)[0]
		for tid in sim.settlements:
			if sim.settlements[tid].faction == gid and dist.get(tid, INF) <= reach:
				return true
	return false

static func _maybe_army(sim: WorldSim, f: SimFaction) -> void:
	for pid in sim.parties:
		var q: SimParty = sim.parties[pid]
		if q.kind == "army" and q.faction == f.id:
			return
	if sim.rng.randf() > 0.5:
		return
	var c := SimData.culture(f.culture)
	var mask := sim.mask_for(c.raid_mobility)
	var reach: float = WorldSim.REACH_DAYS.army * WorldSim.DAY_H * WorldSim.SPEED.army
	var best: Array = []
	var best_w := 0.0
	for sid in WorldSim._sorted_keys(sim.settlements):
		var s: SimSettlement = sim.settlements[sid]
		if s.faction != f.id or s.soldiers < 15 or s.besieged_by >= 0 or s.out_other > 0:
			continue
		var levy := int(s.workers * 0.08)
		var n := int(s.soldiers * 0.7) + levy
		var comp := SimData.allocate(c.army, n)
		var pr: Array = sim.paths_from(sid, mask)
		var dist: Dictionary = pr[0]
		for tid in pr[2]:
			if not sim.settlements.has(tid) or dist[tid] > reach:
				continue
			var d: SimSettlement = sim.settlements[tid]
			if not f.at_war(d.faction) or d.besieged_by >= 0 or sim.t < int(d.cooldowns.get("spared", 0)):
				continue
			var o := SimCombat.odds(comp, defenders(d)[0], wall_ac(d))
			if o < 0.6:
				continue
			var w: float = o * (d.pop() + d.wealth * 0.2) * (1.0 - 0.4 * dist[tid] / reach)
			if w > best_w:
				best_w = w
				best = [sid, tid, comp, levy]
	if best.is_empty():
		return
	var s: SimSettlement = sim.settlements[best[0]]
	var p := sim.new_party("army", f.id, f.culture, s.id, best[2])
	p.people = best[3]
	p.plan = {"levy": float(best[3])}
	p.target = best[1]
	if not sim.send(p, best[1], mask):
		sim.remove_party(p)
		return
	s.workers -= int(best[3])
	s.soldiers -= p.size() - int(best[3])
	s.out_other += 1
	sim.stats_add("armies", 1)
	sim.log_event("army", {"army": f.name, "from": s.name, "site": sim.settlements[best[1]].name, "n": p.size()})

# ── Yearly: lairs breed, starve, spread; dragons demand tribute; tribute is paid ──

static func tick_year(sim: WorldSim) -> void:
	for lid in WorldSim._sorted_keys(sim.lairs):
		if not sim.lairs.has(lid):
			continue
		var l: SimLair = sim.lairs[lid]
		if l.out > 0:
			continue
		if l.hunger > 0.95 and l.count() > 0:
			var lose := maxi(int(l.count() * 0.25), 1)
			var keys := l.monsters.keys()
			keys.sort()
			for slug in keys:
				if lose <= 0:
					break
				var k := mini(lose, int(l.monsters[slug]))
				l.monsters[slug] = int(l.monsters[slug]) - k
				if l.monsters[slug] <= 0:
					l.monsters.erase(slug)
				lose -= k
			l.hunger = 0.7
			if l.count() == 0:
				_lair_gone(sim, l, "")
				continue
		elif l.hunger < 0.5 and l.grow != "" and l.count() < l.max_n:
			var add := mini(maxi(int(l.count() * 0.2), 1), l.max_n - l.count())
			l.monsters[l.grow] = int(l.monsters.get(l.grow, 0)) + add
		if l.apex and l.hunger > 0.4:
			_apex_demand(sim, l)
	# New lairs in ruins, empty lair sites and open portals.
	for s in sim.sites:
		var sid: int = s.id
		if sim.lairs.has(sid) or sim.settlements.has(sid):
			continue
		var chance := 0.0
		if s.kind == "lair":
			chance = 0.1
		elif sim.ruins.has(sid):
			chance = 0.08
		elif s.kind == "portal":
			chance = 0.04
		if chance > 0.0 and sim.rng.randf() < chance:
			sim._spawn_lair(sid, "portal" if s.kind == "portal" else SimData.band_family(s.band), true)
	_maybe_outlaws(sim)
	# Tribute.
	for sid in WorldSim._sorted_keys(sim.settlements):
		var s: SimSettlement = sim.settlements[sid]
		if s.tribute_to < 0:
			continue
		var f: SimFaction = sim.factions.get(s.tribute_to)
		if sim.t >= s.tribute_until or f == null or not f.alive or s.faction == s.tribute_to:
			s.tribute_to = -1
			continue
		var amount := s.wealth * 0.2
		s.wealth -= amount
		if sim.settlements.has(f.capital) and sim.settlements[f.capital].faction == f.id:
			sim.settlements[f.capital].wealth += amount
		else:
			for oid in WorldSim._sorted_keys(sim.settlements):
				if sim.settlements[oid].faction == f.id:
					f.capital = oid
					sim.settlements[oid].wealth += amount
					break
		sim.stats_add("tribute_paid", int(amount))

## Hard times breed outlaws: desperate folk from a hungry or miserable town break away and
## make a bandit camp at a free surface site, a new raider faction. More likely in a world
## with no raiders at all.
static func _maybe_outlaws(sim: WorldSim) -> void:
	var any_raider := false
	for fid in sim.factions:
		var f: SimFaction = sim.factions[fid]
		if f.alive and f.temperament == "raider":
			any_raider = true
			break
	for sid in WorldSim._sorted_keys(sim.settlements):
		if not sim.settlements.has(sid):
			continue
		var s: SimSettlement = sim.settlements[sid]
		if s.band != "surface" or s.pop() < 80 or s.culture == "bandit" or SimData.culture(s.culture).monstrous:
			continue
		var misery := 0.0
		if not s.shock.is_empty(): misery += 0.5
		if s.morale < 0.45: misery += 0.5
		if s.tribute_to >= 0: misery += 0.3
		if misery <= 0.0:
			continue
		var chance := 0.04 * misery * (3.0 if not any_raider else 1.0)
		if sim.rng.randf() > chance:
			continue
		var reach := 16.0 * WorldSim.DAY_H
		var site := -1
		for oid in sim.within(sid, WorldSim.ROAD | WorldSim.LINK, reach):
			var os: Dictionary = sim.site_by_id[oid]
			var empty_den: bool = os.kind == "lair" and not sim.lairs.has(oid) and not sim.settlements.has(oid) \
				and SimData.band_family(os.band) == "surface"
			if SimEconomy.free_site(sim, oid, "bandit") or empty_den:
				site = oid
				break
		if site < 0:
			continue
		var n := mini(clampi(int(s.pop() * 0.08), 15, 60), s.workers - 5)
		if n < 15:
			continue
		s.workers -= n
		var f := sim._new_faction("bandit")
		f.temperament = "raider"
		f.capital = site
		for gid in WorldSim._sorted_keys(sim.factions):
			if gid != f.id:
				var g: SimFaction = sim.factions[gid]
				var r := sim._base_relation(f, g) + (-25.0 if g.id == s.faction else 0.0)
				f.relations[gid] = r
				g.relations[f.id] = r
		var camp := sim._new_settlement(site, "bandit", f.id, 0)
		camp.soldiers = int(n * 0.4)
		camp.workers = n - camp.soldiers
		camp.dependants = 0
		for g in SimData.good_names:
			camp.stock[g] = 0.0
		camp.stock.food = n * SimEconomy.EAT * 60.0
		camp.wealth = 0.0
		camp.tier = SimSettlement.tier_for(camp.pop())
		camp.weather = sim.region_weather.get(sim.region_of(camp), 1.0)
		sim.stats_add("outlaw_camps", 1)
		sim.log_event("outlaws", {"from": s.name, "site": camp.name, "faction": f.name, "n": n,
			"why": "hunger" if not s.shock.is_empty() else ("tribute" if s.tribute_to >= 0 else "misery")})
		any_raider = true

static func _apex_demand(sim: WorldSim, l: SimLair) -> void:
	var near: Array = []
	for sid in WorldSim._sorted_keys(sim.settlements):
		var s: SimSettlement = sim.settlements[sid]
		if absf(s.x - l.x) < sim.world_w * 0.12 and (s.band == l.family or l.family == "portal"):
			near.append([absf(s.x - l.x), sid])
	near.sort()
	if near.is_empty():
		return
	var s: SimSettlement = sim.settlements[near[0][1]]
	var demand := maxf(40.0, s.wealth * 0.15)
	if true:
		if s.wealth >= demand:
			s.wealth -= demand
			l.hunger = 0.1
			sim.stats_add("dragon_tribute", 1)
			sim.log_event("apex_tribute", {"lair": l.name, "what": _lair_what(l), "site": s.name, "coin": int(demand)})
		else:
			var dead := int(s.pop() * 0.03) + 1
			SimEconomy._kill(sim, s, dead, false)
			var burnt := int(s.stock.food * 0.25)
			s.stock.food -= float(burnt)
			s.last_raided = sim.t
			l.hunger = 0.2
			s.grievance[l.id] = float(s.grievance.get(l.id, 0.0)) + dead
			sim.log_event("apex_wrath", {"lair": l.name, "what": _lair_what(l), "site": s.name, "killed": dead, "food": burnt})
			if s.pop() < SimEconomy.ABANDON_POP:
				SimEconomy.abandon_settlement(sim, s, "burned")
