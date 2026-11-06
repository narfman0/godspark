## Keeps each player group's surroundings populated, off-screen, from a CR budget set by the
## depth band and the time of day (data/ecology/spawning.json), with creatures from the
## ecology table for the local biome and band, grouped as packs (a leader, standards,
## minions) with rank rolls. Players closer than group_tiles share one budget; players far
## apart each get their own. Hard caps per player and in all. Never inside a player's view
## rectangle (plus a margin), never within the safe radius of a settlement site, a campfire or
## a bed. Fliers may spawn in open sky; water creatures only in liquid. Monsters far from every
## player for a while (and not fighting) are removed. Raider packs of peoples (bandits on
## surface roads at night, drow near deep-road exits) are SRD NPCs from the addon's make_npc
## when it exists. Seeded: the same player movements give the same spawns.
class_name SpawnDirector
extends RefCounted

var sys: MonstersSystem
var rng := RandomNumberGenerator.new()
var _t := 0.0
var _next := 0.0
## Group id (its first player's id) -> director time before which it gets no new pack: a
## lull after one of its director monsters dies, so a cleared area stays clear a while.
var _lull := {}
var _settlements: Array[Vector2] = []
## Counters for tests and tools.
var stats := {"packs": 0, "spawned": 0, "rejected_view": 0, "rejected_safe": 0, "no_spot": 0, "despawned": 0,
	"raiders": 0, "over_budget": 0}
## Last spawn reasons (tools).
var log: Array = []
var keep_log := false

func _init(s: MonstersSystem) -> void:
	sys = s
	rng.seed = hash([s.host.world.world_seed, "director"])

static func cfg() -> Dictionary:
	return Ecology.spawning()

func tick(h: WorldHost, dt: float) -> void:
	_t += dt
	_despawn(h, dt)
	if _t < _next:
		return
	_next = _t + float(cfg().get("period_s", 1.5))
	for g: Array in groups(h):
		_fill(h, g)

## Player groups: players within group_tiles of each other (chained) share a budget. Sorted
## by the smallest id in each, so the order is stable.
func groups(h: WorldHost) -> Array:
	var ps: Array = []
	for e: HostEntity in h.entities.values():
		if e.is_player():
			ps.append(e)
	ps.sort_custom(func(a: HostEntity, b: HostEntity) -> bool: return a.id < b.id)
	var r := float(cfg().get("group_tiles", 64))
	var out: Array = []
	var seen := {}
	for p: HostEntity in ps:
		if seen.has(p.id):
			continue
		var g: Array = [p]
		seen[p.id] = true
		var i := 0
		while i < g.size():
			for q: HostEntity in ps:
				if not seen.has(q.id) and q.body.pos.distance_to(g[i].body.pos) <= r:
					seen[q.id] = true
					g.append(q)
			i += 1
		out.append(g)
	return out

## The band name at a row (world meta.bands), "surface" when unknown.
func band_at(h: WorldHost, y: float) -> String:
	var bands: Variant = h.world.meta.get("bands", {})
	if bands is Dictionary:
		for k: String in bands:
			var r: Array = bands[k]
			if y >= float(r[0]) and y <= float(r[1]) + 1.0:
				return k
	return "surface"

func biome_at(h: WorldHost, x: float, band: String) -> String:
	var bb: Dictionary = cfg().get("band_biome", {})
	if bb.has(band):
		return String(bb[band])
	for s: Variant in h.world.meta.get("biomes", []):
		if s is Dictionary and x >= float(s["x0"]) and x <= float(s["x1"]) + 1.0:
			return String(s["biome"])
	return "meadow"

func is_night(h: WorldHost) -> bool:
	return WorldClock.sun_at(h.clock.hours()) < 0.5

func band_def(h: WorldHost, band: String) -> Dictionary:
	var b: Dictionary = cfg()["bands"].get(band, cfg()["bands"]["surface"])
	if b.has("any"):
		return b["any"]
	return b["night"] if is_night(h) else b["day"]

## A band's table at a place: on the surface and in the sky, near a settlement the "ramp"
## table's near row (by day or night) is blended toward the band's own with distance, so a
## new player by the spawn settlement meets small, minion-heavy packs and the world gets
## harder as they walk out (data: spawning.json ramp).
func band_def_at(h: WorldHost, band: String, pos: Vector2) -> Dictionary:
	var bd := band_def(h, band)
	var rp: Dictionary = cfg().get("ramp", {})
	if rp.is_empty() or not band in (rp.get("bands", ["surface", "sky"]) as Array):
		return bd
	var near: Dictionary = rp.get("night" if is_night(h) else "day", {})
	if near.is_empty():
		return bd
	var d := settlement_dist(h, pos)
	var n0 := float(rp.get("near_tiles", 120))
	var n1 := float(rp.get("far_tiles", 480))
	var f := clampf((d - n0) / maxf(1.0, n1 - n0), 0.0, 1.0)
	var out := bd.duplicate(true)
	var cr: Array = bd.get("cr", [0, 1])
	out["cr"] = [float(cr[0]), lerpf(float(near.get("max_cr", cr[1])), float(cr[1]), f)]
	out["budget"] = lerpf(float(near.get("budget", bd.get("budget", 4.0))), float(bd.get("budget", 4.0)), f)
	out["pack_cr"] = lerpf(float(near.get("pack_cr", bd.get("pack_cr", 4.0))), float(bd.get("pack_cr", 4.0)), f)
	out["minion_share"] = lerpf(float(near.get("minion_share", cfg().get("minion_share", 0.6))), float(cfg().get("minion_share", 0.6)), f)
	out["standard_only"] = f < float(rp.get("ranks_from", 0.5))
	out["ramp"] = f
	return out

## Tiles to the nearest surface or sky settlement site (INF without one).
func settlement_dist(h: WorldHost, p: Vector2) -> float:
	if _settlements.is_empty():
		for s: Variant in h.world.meta.get("sites", []):
			if s is Dictionary and s.get("kind") == "settlement" and String(s.get("band", "surface")) in ["surface", "sky"]:
				_settlements.append(Vector2(float(s["x"]), float(s["y"])))
		if _settlements.is_empty():
			_settlements.append(Vector2.INF)
	var best := INF
	for s: Vector2 in _settlements:
		if s != Vector2.INF:
			best = minf(best, s.distance_to(p))
	return best

## CR cost alive for a group (monsters the director spawned for it).
func group_cost(g: Array) -> Dictionary:
	var ids := {}
	for p: HostEntity in g:
		ids[p.id] = true
	var cost := 0.0
	var n := 0
	for id: int in sys.mons:
		var r: Dictionary = sys.mons[id].rec
		if r["director"] and not r["dead"] and ids.has(int(r["group"])):
			cost += float(r["cost"])
			n += 1
	return {"cost": cost, "n": n}

func _director_count() -> int:
	var n := 0
	for id: int in sys.mons:
		var r: Dictionary = sys.mons[id].rec
		if r["director"] and not r["dead"]:
			n += 1
	return n

## One of the director's monsters died: its group gets a lull (data: lull_s by band and time).
func killed(rec: Dictionary, band: String, night: bool) -> void:
	if not bool(rec.get("director", false)):
		return
	var l: Dictionary = cfg().get("lull_s", {})
	var s := float(l.get(band + (":night" if night else ":day"), l.get(band, l.get("default", 0.0))))
	var gid := int(rec.get("group", 0))
	_lull[gid] = maxf(float(_lull.get(gid, 0.0)), _t + s)

func _fill(h: WorldHost, g: Array) -> void:
	var anchor: HostEntity = g[0]
	if _t < float(_lull.get(g[0].id, 0.0)):
		stats["lull"] = int(stats.get("lull", 0)) + 1
		return
	# no new packs while someone in the group rests (a camp is a refuge; brains still hunt)
	var rules := h.system(HostSystem.RULES)
	if rules != null and rules.has_method("is_resting"):
		for p: HostEntity in g:
			if bool(rules.call("is_resting", p)):
				return
	var band := band_at(h, anchor.body.pos.y)
	var bd := band_def_at(h, band, anchor.body.pos)
	var budget := float(bd.get("budget", 4.0))
	var have := group_cost(g)
	var caps: Dictionary = cfg().get("caps", {})
	var cap_group := int(caps.get("per_player", 24)) * g.size()
	if have["n"] >= cap_group or _director_count() >= int(caps.get("global", 120)):
		return
	var left := budget - float(have["cost"])
	if left < 0.125:
		return
	# one pack per attempt slot: the spot first, then what lives there
	for attempt in int(cfg().get("attempts", 10)):
		var who: HostEntity = g[rng.randi_range(0, g.size() - 1)]
		var spot := _spot(h, who, g)
		if spot == Vector2.INF:
			continue
		var sband := band_at(h, spot.y)
		var sdef := band_def_at(h, sband, spot)
		var room := minf(left, float(sdef.get("pack_cr", 4.0)))
		if _raiders(h, g, spot, sband, room):
			return
		var pack := build_pack(h, sband, biome_at(h, spot.x, sband), sdef, room)
		if pack.is_empty():
			continue
		_place_pack(h, pack, spot, g[0].id, sband)
		return
	stats["no_spot"] += 1

## A pack for a place: [{slug, rank, leader}], within `room` CR (rank-weighted). Empty if
## nothing fits.
func build_pack(h: WorldHost, band: String, biome: String, bd: Dictionary, room: float) -> Array:
	var cr: Array = bd.get("cr", [0, 1])
	var cands := Ecology.roster(h.srd, band, biome, is_night(h), float(cr[0]), minf(float(cr[1]), room))
	# promote (the nadir): sometimes a pack of a shallower band's creatures, all elites and
	# champions, which fills the band's missing CRs with what the SRD has
	var promo: Dictionary = bd.get("promote", {})
	var ranks_w: Dictionary = {}
	if not promo.is_empty() and rng.randf() < float(promo.get("chance", 0.0)):
		var pcr: Array = promo.get("cr", [0, 1])
		var pb := String(promo.get("from_band", band))
		var pc := Ecology.roster(h.srd, pb, String(cfg().get("band_biome", {}).get(pb, biome)), is_night(h), float(pcr[0]), float(pcr[1]))
		if not pc.is_empty():
			cands = pc
			ranks_w = promo.get("ranks", {})
	if cands.is_empty():
		return []
	var total := 0.0
	for c: Dictionary in cands:
		total += float(c["row"].get("w", 1.0))
	var roll := rng.randf() * total
	var pick: Dictionary = cands[cands.size() - 1]
	for c: Dictionary in cands:
		roll -= float(c["row"].get("w", 1.0))
		if roll <= 0.0:
			pick = c
			break
	var row: Dictionary = pick["row"]
	var out: Array = []
	var used := 0.0
	var plain := bool(bd.get("standard_only", false))
	var share := float(bd.get("minion_share", cfg().get("minion_share", 0.6)))
	var lead_rank := "standard" if plain else (_weighted_rank(ranks_w) if not ranks_w.is_empty() else _rank_roll(band))
	var lead_cost := Ecology.cost(pick["cr"]) * float(Ecology.rank_def(lead_rank).get("xp_mult", 1.0))
	if lead_cost > room:
		lead_rank = "standard"
		lead_cost = Ecology.cost(pick["cr"])
	var leads: Array = row.get("leader_of", [])
	var follower := String(pick["slug"])
	var fr := row
	if not leads.is_empty():
		follower = String(leads[rng.randi_range(0, leads.size() - 1)])
		fr = Ecology.row(follower)
	out.append({"slug": pick["slug"], "rank": lead_rank, "leader": true})
	used += lead_cost
	var pr: Array = fr.get("pack", [1, 1])
	var n := rng.randi_range(int(pr[0]), int(pr[1])) - (0 if not leads.is_empty() else 1)
	var fcr := Ecology.cr_of(h.srd, follower)
	for i in n:
		var rk := "minion" if bool(fr.get("minion", false)) and rng.randf() < share and ranks_w.is_empty() \
			else ("standard" if plain else (_weighted_rank(ranks_w) if not ranks_w.is_empty() else _rank_roll(band)))
		var c := Ecology.cost(fcr) * float(Ecology.rank_def(rk).get("xp_mult", 1.0))
		if used + c > room:
			if rk != "minion" and bool(fr.get("minion", false)) and used + Ecology.cost(fcr) * 0.25 <= room:
				rk = "minion"
				c = Ecology.cost(fcr) * 0.25
			else:
				break
		out.append({"slug": follower, "rank": rk, "leader": false})
		used += c
	return out

func _weighted_rank(w: Dictionary) -> String:
	var total := 0.0
	for k: String in w:
		total += float(w[k])
	var r := rng.randf() * total
	for k: String in w:
		r -= float(w[k])
		if r <= 0.0:
			return k
	return "elite"

func _rank_roll(band: String) -> String:
	var w: Dictionary = cfg()["rank_roll"].get(band, {"standard": 1})
	var total := 0.0
	for k: String in w:
		total += float(w[k])
	var r := rng.randf() * total
	for k: String in w:
		r -= float(w[k])
		if r <= 0.0:
			return k
	return "standard"

## Spawn a pack as the director does (ranks, affixes, archers, a leader): pack is
## [{slug, rank, leader}] (build_pack's shape). Tests, smokes and debug options use it.
func spawn_pack(pack: Array, spot: Vector2, band := "surface") -> Array:
	return _place_pack(sys.host, pack, spot, 0, band)

func _place_pack(h: WorldHost, pack: Array, spot: Vector2, group: int, band: String) -> Array:
	var pid := sys.new_pack()
	var out: Array = []
	var viewers: Array = []
	for p: HostEntity in h.entities.values():
		if p.is_player():
			viewers.append(p)
	for i in pack.size():
		var m: Dictionary = pack[i]
		var off := (i - (pack.size() - 1) * 0.5) * 1.6
		var pos := _stand_near(h, spot + Vector2(off, 0.0), String(m["slug"]))
		if pos == Vector2.INF or absf(pos.y - spot.y) > 4.0 or (group != 0 and _in_view(pos, viewers)):
			pos = spot          # not down a shaft beside it, nor spread into a player's view
		if band in ["surface", "sky"] and _flies(h, String(m["slug"])):
			# fliers wait in the open sky above the spot
			var up := pos + Vector2(0.0, 8.0 + rng.randf() * 6.0)
			if not _blocked(h.world, floori(up.x - 1.0), floori(up.y), 3, 4):
				pos = up
		var rd := Ecology.rank_def(String(m["rank"]))
		var opts := {"rank": m["rank"], "pack": pid, "slot": i, "home": spot, "group": group, "director": true,
			"leader": m["leader"], "affixes": sys.roll_affixes(String(m["slug"]), int(rd.get("affixes", 0)), rng)}
		_maybe_archer(h, String(m["slug"]), opts)
		for k: String in m:
			if not k in ["slug", "rank", "leader"]:
				opts[k] = m[k]
		var e := sys.spawn(String(m["slug"]), pos, opts)
		if e != null:
			out.append(e)
			stats["spawned"] += 1
	stats["packs"] += 1
	if keep_log:
		var names := PackedStringArray()
		for m: Dictionary in pack:
			names.append("%s(%s)" % [m["slug"], m["rank"]])
		log.append({"t": _t, "band": band, "at": spot, "pack": names})
	return out

func _flies(h: WorldHost, slug: String) -> bool:
	var spd: Variant = h.srd.pack.get_row("monster", slug).get("data", {}).get("speed", {})
	return spd is Dictionary and int(spd.get("fly", 0)) > 0

## A pack member with both melee and ranged attacks sometimes hangs back as an archer.
func _maybe_archer(h: WorldHost, slug: String, opts: Dictionary) -> void:
	var eco := Ecology.row(slug)
	if String(eco.get("brain", "")) not in ["bruiser", "skirmisher"] or int(opts["slot"]) == 0:
		return
	var moves := MonsterMoves.of(h.srd, slug)
	var melee := false
	var ranged := false
	for a: Dictionary in moves.get("actions", []):
		melee = melee or a["kind"] == "melee"
		ranged = ranged or a["kind"] == "ranged"
	if melee and ranged and rng.randf() < 0.35:
		opts["brain"] = "archer"

## Howling: n more of e's kind come running from off-screen. Returns how many came.
func call_pack(e: HostEntity, b: MonsterBrain, n: int) -> int:
	var h := sys.host
	var players: Array = []
	for p: HostEntity in h.entities.values():
		if p.is_player():
			players.append(p)
	var got := 0
	for i in n:
		var spot := Vector2.INF
		for k in 12:
			var dx := rng.randf_range(10.0, 30.0) * (1.0 if rng.randf() < 0.5 else -1.0)
			var c := _stand_near(h, e.body.pos + Vector2(dx, 6.0), b.slug)
			if c != Vector2.INF and not _in_view(c, players):
				spot = c
				break
		if spot == Vector2.INF:
			continue
		var m := sys.spawn(b.slug, spot, {"rank": "minion" if bool(Ecology.row(b.slug).get("minion", false)) else "standard",
			"pack": b.pack_id, "slot": b.slot + 10 + i, "home": b.home, "group": int(b.rec["group"]), "director": true,
			"people": String(b.rec.get("people", ""))})
		if m != null:
			var foe := h.entity(b.target_id)
			if foe != null:
				(m.brain as MonsterBrain).alerted_by(foe)
			got += 1
	return got

# --- where ------------------------------------------------------------------------------------

## A spot in the ring around `who`, off every player's screen and out of every safe radius.
func _spot(h: WorldHost, who: HostEntity, g: Array) -> Vector2:
	var ring: Dictionary = cfg().get("ring", {})
	var lo := float(ring.get("min", 40))
	var hi := float(ring.get("max", 62))
	var players: Array = []
	for p: HostEntity in h.entities.values():
		if p.is_player():
			players.append(p)
	for k in 6:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(lo, hi)
		var c := who.body.pos + Vector2(cos(ang) * dist, sin(ang) * dist * 0.6)
		var s := _stand_near(h, c, "")
		if s == Vector2.INF:
			continue
		if _in_view(s, players):
			stats["rejected_view"] += 1
			continue
		if not safe_ok(h, s):
			stats["rejected_safe"] += 1
			continue
		return s
	return Vector2.INF

func _in_view(p: Vector2, players: Array) -> bool:
	var v: Dictionary = cfg().get("view", {})
	var hw := float(v.get("half_w", 32)) + float(v.get("margin", 6))
	var hh := float(v.get("half_h", 18)) + float(v.get("margin", 6))
	for q: HostEntity in players:
		var c := q.body.center()
		if absf(p.x - c.x) <= hw and absf(p.y - c.y) <= hh:
			return true
	return false

## Not near a settlement site, a lit campfire or a bed.
func safe_ok(h: WorldHost, p: Vector2) -> bool:
	var sf: Dictionary = cfg().get("safe", {})
	var sr := float(sf.get("settlement_tiles", 72))
	for s: Variant in h.world.meta.get("sites", []):
		if not (s is Dictionary and s.get("kind") == "settlement"):
			continue
		var pr: Array = Places.place(h.world, int(s["id"])).get("rect", [])
		if pr.size() == 4:   # a laid-out place: its rect and a margin (places track)
			var m := float(sf.get("place_margin_tiles", 24))
			if Rect2(float(pr[0]) - m, float(pr[1]) - m, float(pr[2]) + 2.0 * m, float(pr[3]) + 2.0 * m).has_point(p):
				return false
		elif Vector2(float(s["x"]), float(s["y"])).distance_to(p) <= sr:
			return false
	var r := int(maxf(float(sf.get("campfire_tiles", 20)), float(sf.get("bed_tiles", 20))))
	var fire := TileDefs.id("campfire")
	var bed := TileDefs.id("bed")
	for y in range(floori(p.y) - r, floori(p.y) + r + 1, 1):
		for x in range(floori(p.x) - r, floori(p.x) + r + 1):
			var id := h.world.get_fg(x, y)
			if id == fire or id == bed:
				return false
	return true

## The nearest spot below or around `c` where a Medium (or the slug's) body stands.
func _stand_near(h: WorldHost, c: Vector2, slug: String) -> Vector2:
	var w := h.world
	var cw := 2
	var ch := 3
	if slug != "":
		var sz := MoveStats.size_of(WorldHost.monster_size(h.srd.pack.get_row("monster", slug).get("data", {})))
		cw = ceili(sz.x - 1e-3)
		ch = ceili(sz.y - 1e-3)
	var x := floori(c.x)
	if x < 4 or x > w.width - 5:
		return Vector2.INF
	var y := clampi(floori(c.y), 2, w.height - ch - 2)
	# up out of rock, then down to a floor
	var up := 0
	while up < 24 and _blocked(w, x, y, cw, ch):
		y += 1
		up += 1
	if _blocked(w, x, y, cw, ch):
		return Vector2.INF
	for d in 40:
		if y <= 1:
			return Vector2.INF
		if _blocked(w, x, y - 1, cw, 1) or _floor(w, x, y - 1, cw):
			return Vector2(x + cw * 0.5, y)
		y -= 1
	return Vector2.INF

static func _blocked(w: TileWorld, x: int, y: int, cw: int, ch: int) -> bool:
	for r in range(y, y + ch):
		for c in range(x, x + cw):
			if w.is_solid(c, r):
				return true
	return false

static func _floor(w: TileWorld, x: int, y: int, cw: int) -> bool:
	for c in range(x, x + cw):
		if TileDefs.platform[w.get_fg(c, y)] != 0:
			return true
	return false

# --- raiders ----------------------------------------------------------------------------------

func _raiders(h: WorldHost, g: Array, spot: Vector2, band: String, room: float) -> bool:
	var rs: Dictionary = cfg().get("raiders", {})
	for key: String in rs:
		if key.begins_with("_"):
			continue
		var r: Dictionary = rs[key]
		if not band in r.get("bands", []):
			continue
		if String(r.get("time", "any")) == "night" and not is_night(h):
			continue
		if r.has("near_deep_road") and not _near_deep_road(h, spot, float(r["near_deep_road"])):
			continue
		if rng.randf() >= float(r.get("chance", 0.1)):
			continue
		var pack := raider_pack(h, String(r["culture"]), r, room)
		if pack.is_empty():
			continue
		_place_pack(h, pack, spot, g[0].id, band)
		stats["raiders"] += 1
		return true
	return false

func _near_deep_road(h: WorldHost, p: Vector2, r: float) -> bool:
	var sites: Array = h.world.meta.get("sites", [])
	for rt: Variant in h.world.meta.get("routes", []):
		if not (rt is Dictionary and rt.get("kind") == "deep_road"):
			continue
		for k: String in ["a", "b"]:
			var i := int(rt[k])
			if i >= 0 and i < sites.size() and absf(float(sites[i]["x"]) - p.x) <= r:
				return true
	return false

## A raider party of a culture's recipe as SRD NPCs: [{slug, rank, leader, combatant, people}].
func raider_pack(h: WorldHost, culture: String, r: Dictionary, room: float) -> Array:
	var cult: Dictionary = SimData.culture(culture)
	var recipe: Array = cult.get("raiders", [])
	if recipe.is_empty():
		return []
	var species := String(cult.get("species", "human"))
	var lineage := String(cult.get("lineage", ""))
	var pr: Array = r.get("pack", [3, 5])
	var n := rng.randi_range(int(pr[0]), int(pr[1]))
	var total := 0.0
	for e: Array in recipe:
		total += float(e[1])
	var out: Array = []
	var used := 0.0
	var best := -1.0
	var lead := 0
	for i in n:
		var x := rng.randf() * total
		var role := String(recipe[recipe.size() - 1][0])
		for e: Array in recipe:
			x -= float(e[1])
			if x <= 0.0:
				role = String(e[0])
				break
		var cr := Ecology.cr_of(h.srd, role)
		var rk := "minion" if bool(Ecology.row(role).get("minion", false)) and rng.randf() < 0.4 else "standard"
		var c := Ecology.cost(cr) * float(Ecology.rank_def(rk).get("xp_mult", 1.0))
		if used + c > room and not out.is_empty():
			continue
		used += c
		var people := String(r.get("people", species)) + ":" + _people_role(role)
		var m := {"slug": role, "rank": rk, "leader": false, "people": people,
			"bond": "people:" + culture}
		var srd: Variant = h.srd
		if srd.has_method("make_npc"):
			var npc: Variant = srd.call("make_npc", role, species, lineage)
			if npc != null:
				m["combatant"] = npc
				m["name"] = String(npc.stats.character_name)
		out.append(m)
		if cr > best:
			best = cr
			lead = out.size() - 1
	if not out.is_empty():
		out[lead]["leader"] = true
		var first: Dictionary = out[lead]
		out.remove_at(lead)
		out.insert(0, first)
	return out

static func _people_role(role: String) -> String:
	match role:
		"bandit", "bandit-captain", "tough", "tough-boss", "warrior-infantry", "warrior-veteran", "assassin":
			return "raider"
		"priest-acolyte":
			return "priest"
	return role

# --- despawn ----------------------------------------------------------------------------------

func _despawn(h: WorldHost, dt: float) -> void:
	var d: Dictionary = cfg().get("despawn", {})
	var far := float(d.get("far_tiles", 96))
	var after := float(d.get("after_s", 20.0))
	var combat := h.system(HostSystem.COMBAT)
	var gone: Array = []
	for id: int in sys.mons:
		var b: MonsterBrain = sys.mons[id]
		var rec: Dictionary = b.rec
		if not rec["director"] or rec["dead"]:
			continue
		var e := h.entity(id)
		if e == null:
			continue
		var near := false
		for p: HostEntity in h.entities.values():
			if p.is_player() and p.body.pos.distance_to(e.body.pos) <= far:
				near = true
				break
		var fighting: bool = combat != null and combat.has_method("in_combat") and combat.in_combat(e)
		if near or fighting:
			rec["far_t"] = 0.0
			continue
		rec["far_t"] = float(rec["far_t"]) + dt
		if float(rec["far_t"]) >= after:
			gone.append(id)
	for id: int in gone:
		h.remove_entity(id)
		stats["despawned"] += 1
