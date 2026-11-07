## The strategic world simulation: settlements, factions, lairs and parties on a strip of
## sites joined by routes. Headless, seeded, deterministic, plain serializable state.
##   var sim := WorldSim.synthetic(24, 7)
##   sim.step(24 * 360)                 # one year
##   for e in sim.chronicle: print(sim.describe(e))
## Cadence: parties move every PARTY_H hours, the economy and decisions run every ECON_H
## hours, factions decide monthly, weather and growth are yearly.
class_name WorldSim
extends RefCounted

const DAY_H := 24
const YEAR_DAYS := 360
const YEAR_H := DAY_H * YEAR_DAYS
const SEASON_H := YEAR_H / 4
const SEASONS := ["spring", "summer", "autumn", "winter"]
const PARTY_H := 1
const ECON_DAYS := 5
const ECON_H := ECON_DAYS * DAY_H
const MONTH_H := 30 * DAY_H

## A caravan crosses the whole strip in this many days.
const CROSS_DAYS := 24.0
## Route classes (bit mask for path finding).
const ROAD := 1
const DEEP := 2
const LINK := 4
const SPEED := {"caravan": 1.0, "migrants": 0.8, "settlers": 0.85, "raid": 1.5, "patrol": 1.2,
	"army": 0.9, "expedition": 1.1, "pack": 1.4}
## On-screen pace: how fast parties really move, in tiles per real second, watched or not
## (a wagon 1.5, people on foot 2.5). A game hour is K.DAY_SECONDS / 24 real seconds, so a
## caravan covers 75 tiles of route in a game hour. Planning (reach, costs, risk) still uses
## `route_hours` (the old strategic distances: who trades with and raids whom is unchanged);
## movement uses `route_travel_h`.
const TRAVEL_TPS := {"caravan": 1.5, "settlers": 1.5, "migrants": 2.5, "raid": 2.5, "patrol": 2.5,
	"army": 2.5, "expedition": 2.5, "pack": 2.5}
const GAME_HOUR_S := float(K.DAY_SECONDS) / DAY_H
## Furthest a party will go, in days of travel at its own speed.
const REACH_DAYS := {"caravan": 18.0, "migrants": 20.0, "settlers": 20.0, "raid": 10.0, "patrol": 8.0,
	"army": 14.0, "expedition": 10.0, "pack": 5.0}

var seed := 0
var t := 0                    # hours since the start
var rng := RandomNumberGenerator.new()
var sites: Array = []         # [{id, kind, x, y, biome, band, size}]
var routes: Array = []        # [{id, a, b, kind, length, name, cls}]
var settlements := {}         # site id -> SimSettlement
var lairs := {}               # site id -> SimLair
var factions := {}            # id -> SimFaction
var parties := {}             # id -> SimParty (ids ascending = insertion order)
var ruins := {}               # site id -> true (fallen settlements and lair-free ruin sites)
var chronicle: Array = []     # [{t, kind, ...}]
var stats := {}               # counters, ints
var route_threat := {}        # route id -> float, decays
var route_traffic := {}       # route id -> {faction id: float}, decays
var route_value := {}         # route id -> {faction id: coin of cargo sent along it}, decays
var region_weather := {}      # region index -> float, this year
## Guards a surface town posted at a way up after a raid from below (SimBelow): link route id ->
## {home, faction, culture, n, n0, until, since}. Saved.
var way_watch := {}
var taken_names := {}
var next_party := 1
var next_faction := 1
var world_x0 := 0.0
var world_w := 1.0

# Derived, rebuilt on load.
var site_by_id := {}          # id -> site dict
var route_by_id := {}         # id -> route dict
var adj := {}                 # site id -> [[neighbour id, route id], ...]
var route_hours := {}         # route id -> hours at speed 1 (planning distance)
var route_travel_h := {}      # route id -> game hours for a wagon at 1.5 tiles a second
var route_lair_sites := {}    # route id -> [site ids a lair there would hunt from]
var edge := {}                # "a:b" -> route id
var market := {}              # SimEconomy.build_market, per econ tick
## Trade ledger for reports and sweeps, not saved. On only when a tool asks: `ledger_on` true fills
## `ledger`, route id -> {goods: {good: units}, value, trips, ambushes, taken, lost, beasts,
## raiders: {culture: n}} and `flows`, "good|from biome|to biome|crossings" -> [units, value].
var ledger_on := false
var ledger := {}
var flows := {}
var _paths := {}              # cache: src * 8 + mask -> [dist, prev, ids]
var _within := {}             # cache for within()
var _base_rel := {}           # cache for base_relation()

# ── Construction ─────────────────────────────────────────────────────────────

static func from_meta(meta: Dictionary, world_seed: int) -> WorldSim:
	var sim := WorldSim.new()
	sim._setup(meta.get("sites", []), meta.get("routes", []), world_seed,
		float(meta.get("surface", []).size()), meta.get("barriers", {}), meta.get("ways", []))
	return sim

## Biomes of the stand-alone layout (canonical ids, data/biomes.json).
const SYNTH_SURFACE: Array = ["meadow", "forest", "hills", "mountain", "coast", "desert", "swamp", "tundra", "jungle"]
const SYNTH_DEEP: Array = ["fungal", "caves", "crystal", "deep_lake", "magma"]

## A made-up strip: settlements, lairs, ruins and portals on the surface, in the caves and
## in the deeps, joined by roads, deep roads and links between them.
static func synthetic(n_sites: int, world_seed: int) -> WorldSim:
	var r := RandomNumberGenerator.new()
	r.seed = hash([world_seed, "synthetic"])
	var width := 180.0 * n_sites
	var bands := []
	var sites_out: Array = []
	var cur_biome: String = SYNTH_SURFACE[r.randi_range(0, SYNTH_SURFACE.size() - 1)]
	for i in n_sites:
		var roll := r.randf()
		var band := "surface" if roll < 0.55 else ("caves" if roll < 0.72 else "deeps")
		var kroll := r.randf()
		var kind := "settlement" if kroll < 0.55 else ("lair" if kroll < 0.82 else ("ruin" if kroll < 0.95 else "portal"))
		var x := (i + 0.2 + r.randf() * 0.6) / n_sites * width
		var biome := ""
		if band == "surface":
			if r.randf() < 0.45:
				cur_biome = SYNTH_SURFACE[r.randi_range(0, SYNTH_SURFACE.size() - 1)]
			biome = cur_biome
		elif band == "caves":
			biome = "caves" if r.randf() < 0.6 else SYNTH_DEEP[r.randi_range(0, SYNTH_DEEP.size() - 1)]
		else:
			biome = SYNTH_DEEP[r.randi_range(0, SYNTH_DEEP.size() - 1)]
		var y := 700.0 if band == "surface" else (420.0 if band == "caves" else 150.0)
		sites_out.append({"id": i, "kind": kind, "x": x, "y": y + r.randf_range(-30, 30), "biome": biome,
			"band": band, "size": float(r.randi_range(1, 3))})
	# Routes: chain each family left to right, then link caves and deeps upward.
	var routes_out: Array = []
	var by_fam := {"surface": [], "caves": [], "deeps": []}
	for s in sites_out:
		by_fam[s.band].append(s)
	var rid := 0
	for fam in ["surface", "caves", "deeps"]:
		var arr: Array = by_fam[fam]
		for j in range(1, arr.size()):
			var a: Dictionary = arr[j - 1]
			var b: Dictionary = arr[j]
			routes_out.append({"id": rid, "a": a.id, "b": b.id, "kind": "road" if fam == "surface" else "deep_road",
				"length": absf(b.x - a.x) * r.randf_range(1.05, 1.35)})
			rid += 1
	# Caves join the deeps where they overlap; some underground sites climb to the surface.
	for fam_pair in [["caves", "deeps", 0.5], ["caves", "surface", 0.55], ["deeps", "surface", 0.25]]:
		for s in by_fam[fam_pair[0]]:
			if r.randf() > fam_pair[2] or by_fam[fam_pair[1]].is_empty():
				continue
			var best: Dictionary = {}
			for o in by_fam[fam_pair[1]]:
				if best.is_empty() or absf(o.x - s.x) < absf(best.x - s.x):
					best = o
			routes_out.append({"id": rid, "a": s.id, "b": best.id, "kind": "deep_road",
				"length": absf(best.x - s.x) + absf(best.y - s.y) * 0.8})
			rid += 1
	var sim := WorldSim.new()
	sim._setup(sites_out, routes_out, world_seed, width)
	return sim

func _setup(in_sites: Array, in_routes: Array, world_seed: int, width: float, barriers := {}, ways := []) -> void:
	SimData.ensure()
	seed = world_seed
	rng.seed = hash([world_seed, "worldsim"])
	for s in in_sites:
		sites.append({"id": int(s.id), "kind": str(s.kind), "x": float(s.x), "y": float(s.y),
			"biome": str(s.get("biome", "")), "band": str(s.get("band", "surface")), "size": float(s.get("size", 1))})
	sites.sort_custom(func(p, q): return p.x < q.x or (p.x == q.x and p.id < q.id))
	var x0 := INF
	var x1 := -INF
	for s in sites:
		x0 = minf(x0, s.x); x1 = maxf(x1, s.x)
	world_x0 = 0.0 if width > 0.0 else x0
	world_w = maxf(width if width > 0.0 else x1 - x0, 1.0)
	for r in in_routes:
		routes.append({"id": int(r.id), "a": int(r.a), "b": int(r.b), "kind": str(r.kind),
			"length": float(r.get("length", 0.0)), "name": "", "cls": 0})
	_index_sites()
	_add_ways(ways)
	var barrier_rows := _barrier_rows(barriers)
	_add_trails(barrier_rows)
	for r in routes:
		var a: Dictionary = site_by_id[r.a]
		var b: Dictionary = site_by_id[r.b]
		r["crossings"] = _crossed(barrier_rows, a, b)
	_index_routes()
	for r in routes:
		r.name = SimNames.make(rng, "place", taken_names)
	_seed_world()

## Ways between the surface and the deeps that worldgen knows of besides its own ascent route
## (meta.ways: [{kind, top: [x, y], bottom: [x, y], path?: [[x, y]] top to bottom}], a cave mouth,
## sinkhole or buried ruin; the descent track fills it with its sinkholes): each joins the deep settlement nearest its bottom to the surface
## settlement nearest its top, unless a route already does, as a link (`way` names its kind).
## Its length is the walk: across at each end, and the climb. Caravans use it when it pays.
func _add_ways(ways: Array) -> void:
	var next_id := 0
	for r in routes:
		next_id = maxi(next_id, int(r.id) + 1)
	for w: Variant in ways:
		if not w is Dictionary or not (w as Dictionary).has("top") or not (w as Dictionary).has("bottom"):
			continue
		var top := Vector2(float(w.top[0]), float(w.top[1]))
		var bottom := Vector2(float(w.bottom[0]), float(w.bottom[1]))
		var up := _nearest_settlement_site(top, true)
		var down := _nearest_settlement_site(bottom, false)
		if up.is_empty() or down.is_empty():
			continue
		var joined := false
		for r in routes:
			if (int(r.a) == int(up.id) and int(r.b) == int(down.id)) or (int(r.a) == int(down.id) and int(r.b) == int(up.id)):
				joined = true
		if joined:
			continue
		var length := absf(top.x - float(up.x)) + absf(bottom.x - float(down.x)) + absf(top.y - bottom.y) * 1.5 + absf(top.x - bottom.x)
		var link := {"id": next_id, "a": int(down.id), "b": int(up.id), "kind": "deep_road", "length": length,
			"name": "", "cls": 0, "way": str(w.get("kind", "way")), "top": [top.x, top.y], "bottom": [bottom.x, bottom.y]}
		if w.get("path") is Array:
			link["path"] = (w.path as Array).duplicate(true)     # top to bottom (a sinkhole's rope: M6 deep)
		routes.append(link)
		next_id += 1

func _nearest_settlement_site(p: Vector2, surface: bool) -> Dictionary:
	var best: Dictionary = {}
	var bd := INF
	for s in sites:
		if s.kind != "settlement" or (SimData.band_family(s.band) == "surface") != surface:
			continue
		var d := absf(float(s.x) - p.x) + absf(float(s.y) - p.y) * 0.5
		if d < bd:
			bd = d
			best = s
	return best

## World meta's barriers as flat rows: {kind, x0, x1}, the columns a surface walk must clear.
## The same rule as Barriers.crossings: a river's banks count for two columns each side.
static func _barrier_rows(barriers: Dictionary) -> Array:
	var out: Array = []
	for rg in barriers.get("ranges", []):
		out.append({"kind": "pass", "x0": float(rg.x0), "x1": float(rg.x1)})
	for rv in barriers.get("rivers", []):
		out.append({"kind": str(rv.kind), "x0": float(rv.x0) - 2.0, "x1": float(rv.x1) + 2.0})
	return out

## What a surface walk between two sites crosses, as kinds. Nothing underground crosses: the
## caves run under a range and a river's bed.
static func _crossed(rows: Array, a: Dictionary, b: Dictionary) -> Array:
	var out: Array = []
	if SimData.band_family(a.band) != "surface" or SimData.band_family(b.band) != "surface":
		return out
	var lo := minf(a.x, b.x)
	var hi := maxf(a.x, b.x)
	for row in rows:
		if lo < row.x0 and hi > row.x1:
			out.append(row.kind)
	out.sort()
	return out

## What a list of crossings adds to a route's length.
func crossing_length(kinds: Array) -> float:
	var n := 0.0
	for k in kinds:
		n += float(SimData.crossing_cost.get(k, 0.0))
	return n * world_w

## Sites with no route get a trail to the nearest site in the same band family, so every
## lair and hamlet can be reached by someone. A trail over a barrier costs what a road over it
## does, so the nearest site can be the one on this side.
func _add_trails(barrier_rows := []) -> void:
	var linked := {}
	for r in routes:
		linked[r.a] = true; linked[r.b] = true
	var next_id := 0
	for r in routes:
		next_id = maxi(next_id, r.id + 1)
	for s in sites:
		if linked.has(s.id):
			continue
		var fam := SimData.band_family(s.band)
		var best: Dictionary = {}
		var best_d := INF
		for o in sites:
			if o.id == s.id or SimData.band_family(o.band) != fam:
				continue
			var d := absf(o.x - s.x) + crossing_length(_crossed(barrier_rows, s, o))
			if d < best_d:
				best = o
				best_d = d
		if best.is_empty():
			for o in sites:
				if o.id != s.id and (best.is_empty() or absf(o.x - s.x) < absf(best.x - s.x)):
					best = o
		if best.is_empty():
			continue
		routes.append({"id": next_id, "a": s.id, "b": best.id, "kind": "road" if fam == "surface" else "deep_road",
			"length": absf(best.x - s.x) + absf(best.y - s.y) * 0.5 + crossing_length(_crossed(barrier_rows, s, best)),
			"name": "", "cls": 0, "trail": true})
		linked[s.id] = true; linked[best.id] = true
		next_id += 1

func _index_sites() -> void:
	site_by_id.clear()
	for s in sites:
		site_by_id[s.id] = s

func _index_routes() -> void:
	route_by_id.clear(); adj.clear(); route_hours.clear(); edge.clear(); _paths.clear(); _within.clear()
	route_lair_sites.clear()
	for s in sites:
		adj[s.id] = []
	for r in routes:
		var a: Dictionary = site_by_id[r.a]
		var b: Dictionary = site_by_id[r.b]
		var fa := SimData.band_family(a.band)
		var fb := SimData.band_family(b.band)
		if fa == "surface" and fb == "surface":
			r.cls = ROAD
		elif fa != "surface" and fb != "surface":
			r.cls = DEEP
		else:
			r.cls = LINK
		if r.length <= 0.0:
			r.length = absf(a.x - b.x) + absf(a.y - b.y)
		route_by_id[r.id] = r
		adj[r.a].append([r.b, r.id])
		adj[r.b].append([r.a, r.id])
		edge["%d:%d" % [r.a, r.b]] = r.id
		edge["%d:%d" % [r.b, r.a]] = r.id
		route_hours[r.id] = maxf(r.length / world_w * CROSS_DAYS * DAY_H, 6.0)
		route_travel_h[r.id] = maxf(r.length / (1.5 * GAME_HOUR_S), 0.05)
		# Lair sites whose hunters reach this route: its endpoints, and same-family sites
		# whose x lies within the route's span plus a margin.
		var lo := minf(a.x, b.x) - world_w * 0.015
		var hi := maxf(a.x, b.x) + world_w * 0.015
		var near: Array = []
		for s in sites:
			var fam := SimData.band_family(s.band)
			var ok: bool = s.id == r.a or s.id == r.b
			if not ok and s.x >= lo and s.x <= hi:
				ok = fam == fa or fam == fb or (r.cls == DEEP and fam != "surface")
			if ok:
				near.append(s.id)
		route_lair_sites[r.id] = near

# ── World seeding ────────────────────────────────────────────────────────────

func _seed_world() -> void:
	var prev_culture := {"surface": "", "caves": "", "deeps": ""}
	var settled: Array = []
	for s in sites:
		var fam := SimData.band_family(s.band)
		if s.kind == "settlement":
			var c := _pick_culture(s, prev_culture[fam])
			if c == "":
				continue
			prev_culture[fam] = c
			if rng.randf() < 0.8:
				settled.append([s, c])
		elif s.kind == "lair":
			_spawn_lair(s.id, fam, false)
		elif s.kind == "ruin":
			ruins[s.id] = true
			if rng.randf() < 0.4:
				_spawn_lair(s.id, fam, false)
		elif s.kind == "portal":
			if rng.randf() < 0.5:
				_spawn_lair(s.id, "portal", false)
	# Ensure a world has a few people in it.
	if settled.size() < 2:
		for s in sites:
			if s.kind == "settlement" and settled.size() < 2 and not _in_settled(settled, s.id):
				settled.append([s, _pick_culture(s, "")])
	# Factions: runs of the same culture in a band family, at most three settlements each.
	var run_fac := -1
	var run_key := ""
	var run_n := 0
	for e in settled:
		var s: Dictionary = e[0]
		var c: String = e[1]
		var key := SimData.band_family(s.band) + ":" + c
		if key != run_key or run_n >= 3 or rng.randf() < 0.25:
			run_fac = _new_faction(c).id
			run_key = key
			run_n = 0
		run_n += 1
		var st := _new_settlement(s.id, c, run_fac, _initial_pop(s, c))
		if factions[run_fac].capital < 0:
			factions[run_fac].capital = st.id
	for fid in factions:
		for gid in factions:
			if fid != gid:
				factions[fid].relations[gid] = _base_relation(factions[fid], factions[gid]) + rng.randf_range(-15.0, 15.0)
	_roll_weather()

func _in_settled(arr: Array, sid: int) -> bool:
	for e in arr:
		if e[0].id == sid:
			return true
	return false

func _pick_culture(s: Dictionary, prev: String) -> String:
	var fam := SimData.band_family(s.band)
	# Neighbours tend to be kin, so long as the land suits them.
	if prev != "" and fam in SimData.culture(prev).bands and rng.randf() < 0.25 * minf(SimData.fit(prev, s.biome), 2.0):
		return prev
	var total := 0.0
	var ws: Array = []
	for cid in SimData.culture_ids:
		var c: Dictionary = SimData.cultures[cid]
		var w := 0.0
		if fam in c.bands:
			w = float(c.weight) * float(c.biomes.get(s.biome, 0.4))
		ws.append(w)
		total += w
	if total <= 0.0:
		return ""
	var roll := rng.randf() * total
	for i in ws.size():
		roll -= ws[i]
		if roll <= 0.0:
			return SimData.culture_ids[i]
	return SimData.culture_ids[ws.size() - 1]

## Start somewhere between a third and four fifths of what the land can feed.
func _initial_pop(s: Dictionary, c: String) -> int:
	var b := SimData.biome(s.biome, s.band)
	var cap := float(b.food) * _size_factor(s) * SimEconomy.FOOD_CAP * float(SimData.culture(c).farm)
	return maxi(int(cap * SimEconomy.EQ_PER_CAP * rng.randf_range(0.35, 0.8)), 40)

static func _size_factor(s: Dictionary) -> float:
	var sz: float = s.size
	if sz > 6.0:
		sz = sz / 32.0
	return clampf(sz, 0.5, 4.0)

func _new_faction(culture_id: String) -> SimFaction:
	var f := SimFaction.new()
	f.id = next_faction
	next_faction += 1
	f.culture = culture_id
	var c := SimData.culture(culture_id)
	f.temperament = _weighted_key(c.temperament)
	var forms: Array = c.faction_forms
	var n := SimNames.make(rng, culture_id if SimData.names.has(culture_id) else "place", taken_names)
	f.name = str(forms[rng.randi_range(0, forms.size() - 1)]).replace("{n}", n)
	factions[f.id] = f
	return f

func _weighted_key(weights: Dictionary) -> String:
	var keys := weights.keys()
	keys.sort()
	var total := 0.0
	for k in keys:
		total += float(weights[k])
	var roll := rng.randf() * total
	for k in keys:
		roll -= float(weights[k])
		if roll <= 0.0:
			return k
	return keys[keys.size() - 1]

## Where relations drift back to: culture affinity and temperament (both fixed), cached.
func base_relation(a: SimFaction, b: SimFaction) -> float:
	var key := a.id * 100003 + b.id
	if not _base_rel.has(key):
		_base_rel[key] = _base_relation(a, b)
	return _base_rel[key]

func _base_relation(a: SimFaction, b: SimFaction) -> float:
	var ca := SimData.culture(a.culture)
	var cb := SimData.culture(b.culture)
	var r := 0.0
	if a.culture == b.culture:
		r += 25.0
	if bool(ca.monstrous) != bool(cb.monstrous):
		r -= 20.0
	# a people apart (the drow) is estranged from every other
	if a.culture != b.culture:
		r -= maxf(float(ca.get("estranged", 0.0)), float(cb.get("estranged", 0.0)))
	if a.temperament == "raider" or b.temperament == "raider":
		r -= 10.0
	return r

func _new_settlement(site_id: int, culture_id: String, faction_id: int, p: int) -> SimSettlement:
	var s := SimSettlement.new()
	s.id = site_id
	s.culture = culture_id
	s.faction = faction_id
	s.name = SimNames.make(rng, culture_id, taken_names)
	var c := SimData.culture(culture_id)
	s.soldiers = int(p * float(c.soldiers))
	s.dependants = int(p * 0.35)
	s.workers = maxi(p - s.soldiers - s.dependants, 0)
	s.founded = t
	_derive_settlement(s)
	for g in SimData.good_names:
		s.stock[g] = SimEconomy.target(s, g) * (1.3 if g == "food" else 0.8)
	s.wealth = p * 2.0
	s.tier = SimSettlement.tier_for(p)
	settlements[site_id] = s
	ruins.erase(site_id)
	return s

func _derive_settlement(s: SimSettlement) -> void:
	var site: Dictionary = site_by_id[s.id]
	var b := SimData.biome(site.biome, site.band)
	var c := SimData.culture(s.culture)
	var sf := _size_factor(site)
	# What a people makes, its land gives it more of (cultures.json makes): the share, so the
	# yield, the local price and the stockpile all follow.
	var mk: Dictionary = SimData.makes.get(s.culture, {})
	if not mk.is_empty():
		b = b.duplicate()
		for g: String in mk:
			b[g] = float(b.get(g, 0.0)) * float(mk[g])
	s.land = b
	s.cap = {"food": float(b.food) * sf * SimEconomy.FOOD_CAP * float(c.farm)}
	for g in SimData.goods:
		if SimData.goods[g].has("cap"):
			s.cap[g] = float(b.get(g, 0.0)) * sf * float(SimData.goods[g].cap)
	s.seasonal = bool(b.seasonal) and SimData.band_family(site.band) == "surface"
	s.band = SimData.band_family(site.band)
	s.x = site.x

func _spawn_lair(site_id: int, fam: String, log_it: bool) -> SimLair:
	var table: Array = SimData.lairs.get(fam, SimData.lairs["surface"])
	var site: Dictionary = site_by_id[site_id]
	# The draw as it has always been, on the sim's generator: a row by weight, then its members.
	var total := 0.0
	for e in table:
		total += float(e.w)
	var roll := rng.randf() * total
	var def: Dictionary = table[table.size() - 1]
	for e in table:
		roll -= float(e.w)
		if roll <= 0.0:
			def = e
			break
	var members := _lair_members(def, rng)
	# Where that row may not stand (its biomes or bands), or the ground favours some row (biome_w),
	# the lair is drawn again by those rules on its own generator, never the sim's: a world with
	# none of this draws its lairs, and everything after them, as before.
	var own := RandomNumberGenerator.new()
	own.seed = hash([seed, "lair", site_id, t])
	if lair_weight(def, site) <= 0.0 or _favoured(table, site):
		def = _pick_lair(table, site, own)
		members = _lair_members(def, own)
	for m: Variant in def.get("charmed", []):
		var n := own.randi_range(int(m[1]), int(m[2]))
		if n > 0:
			members[str(m[0])] = int(members.get(str(m[0]), 0)) + n
	var where := _site_label(site_id)
	var l := SimLair.new()
	l.id = site_id
	l.kind = def.id
	l.family = fam
	l.apex = bool(def.get("apex", false))
	l.grow = str(def.get("grow", ""))
	l.max_n = int(def.max)
	l.hunger_rate = float(def.hunger)
	l.monsters = members
	var words: Array = def.words
	l.name = SimNames.make(rng, "place", taken_names) + " " + str(words[rng.randi_range(0, words.size() - 1)])
	l.hunger = rng.randf_range(0.1, 0.5)
	l.x = site_by_id[site_id].x
	l.biome = str(site_by_id[site_id].get("biome", ""))
	lairs[site_id] = l
	if log_it:
		log_event("lair_new", {"lair": l.name, "what": SimConflict._lair_what(l), "site": where, "n": l.count()})
	return l

static func _lair_members(def: Dictionary, r: RandomNumberGenerator) -> Dictionary:
	var out := {}
	for m in def.members:
		var n := r.randi_range(int(m[1]), int(m[2]))
		if n > 0:
			out[str(m[0])] = n
	return out

## Does some row of the table favour this site's biome (biome_w)?
static func _favoured(table: Array, site: Dictionary) -> bool:
	var biome := str(site.get("biome", ""))
	for e: Dictionary in table:
		if (e.get("biome_w", {}) as Dictionary).has(biome):
			return true
	return false

## A row by lair_weight at a site (the last allowed one when every weight is 0).
static func _pick_lair(table: Array, site: Dictionary, r: RandomNumberGenerator) -> Dictionary:
	var total := 0.0
	for e in table:
		total += lair_weight(e, site)
	var roll := r.randf() * total
	var def: Dictionary = table[table.size() - 1]
	for e in table:
		var w := lair_weight(e, site)
		if w <= 0.0:
			continue
		def = e
		roll -= w
		if roll <= 0.0:
			break
	return def

## A lairs.json row's weight at a site: 0 where its `biomes` or `bands` leave the site out, times
## its `biome_w` for the site's biome.
static func lair_weight(e: Dictionary, site: Dictionary) -> float:
	var biome := str(site.get("biome", ""))
	if e.has("biomes") and not biome in (e.biomes as Array):
		return 0.0
	if e.has("bands") and not str(site.get("band", "")) in (e.bands as Array):
		return 0.0
	return float(e.w) * float((e.get("biome_w", {}) as Dictionary).get(biome, 1.0))

# ── Stepping ─────────────────────────────────────────────────────────────────

## Advance the world by whole hours.
func step(hours: int) -> void:
	var end := t + hours
	while t < end:
		var next := mini(end, (t / PARTY_H + 1) * PARTY_H)
		t = next
		var t0 := Time.get_ticks_usec() if profile else 0
		if t % PARTY_H == 0:
			SimConflict.tick_parties(self, PARTY_H)
			t0 = _prof("parties", t0)
		if t % ECON_H == 0:
			SimEconomy.tick(self)
			t0 = _prof("economy", t0)
			SimConflict.tick_decisions(self)
			t0 = _prof("decisions", t0)
		if t % MONTH_H == 0:
			SimConflict.tick_factions(self)
			t0 = _prof("factions", t0)
		if t % YEAR_H == 0:
			_tick_year()
			t0 = _prof("year", t0)

## Section timings in microseconds when `profile` is on (not saved).
var profile := false
var prof := {}

func _prof(key: String, t0: int) -> int:
	if not profile:
		return 0
	var now := Time.get_ticks_usec()
	prof[key] = int(prof.get(key, 0)) + now - t0
	return now

func _tick_year() -> void:
	_roll_weather()
	SimEconomy.tick_year(self)
	SimConflict.tick_year(self)

func year() -> int:
	return t / YEAR_H + 1

func season() -> String:
	return SEASONS[(t % YEAR_H) / SEASON_H]

func season_index() -> int:
	return (t % YEAR_H) / SEASON_H

## Harvest factor for the year, per region of the strip. A bad region is chronicled.
func _roll_weather() -> void:
	var n_regions := 5
	region_weather.clear()
	for i in n_regions * 2:
		var deep := i >= n_regions
		var w := rng.randfn(1.0, 0.05 if deep else 0.12)
		var roll := rng.randf()
		var blight := false
		if roll < (0.035 if deep else 0.07):
			w = rng.randf_range(0.42, 0.68)
			blight = true
		elif roll > 0.94 and not deep:
			w = rng.randf_range(1.2, 1.4)
		region_weather[i] = clampf(w, 0.2, 1.5)
		if blight and t > 0:
			var names: Array = []
			for sid in _sorted_keys(settlements):
				var s: SimSettlement = settlements[sid]
				if region_of(s) == i:
					names.append(s.name)
			if not names.is_empty():
				stats_add("bad_harvests", 1)
				log_event("bad_harvest", {"deep": deep, "places": ", ".join(names), "pct": int(w * 100)})
	for sid in settlements:
		var s: SimSettlement = settlements[sid]
		s.weather = region_weather[region_of(s)]

func region_of(s: SimSettlement) -> int:
	var i := clampi(int((s.x - world_x0) / world_w * 5.0), 0, 4)
	return i + (5 if s.band != "surface" else 0)

# ── Graph and paths ──────────────────────────────────────────────────────────

func mask_for(list: Array) -> int:
	var m := 0
	for k in list:
		match k:
			"road": m |= ROAD
			"deep": m |= DEEP
			"link": m |= LINK
	return m

## Dijkstra over the route graph for one source and route-class mask, cached.
## Returns [dist: {site: hours}, prev: {site: previous site}, reachable site ids sorted].
func paths_from(src: int, mask: int) -> Array:
	var key := src * 8 + mask
	if _paths.has(key):
		return _paths[key]
	var dist := {src: 0.0}
	var prev := {}
	var done := {}
	var frontier := [src]
	while not frontier.is_empty():
		var bi := 0
		for i in range(1, frontier.size()):
			if dist[frontier[i]] < dist[frontier[bi]]:
				bi = i
		var u: int = frontier[bi]
		frontier.remove_at(bi)
		if done.has(u):
			continue
		done[u] = true
		for e in adj[u]:
			var r: Dictionary = route_by_id[e[1]]
			if (r.cls & mask) == 0:
				continue
			var v: int = e[0]
			var nd: float = dist[u] + route_hours[e[1]]
			if not dist.has(v) or nd < dist[v]:
				dist[v] = nd
				prev[v] = u
				frontier.append(v)
	var ids := dist.keys()
	ids.sort()
	var res := [dist, prev, ids]
	_paths[key] = res
	return res

## Site ids reachable from src within `hours` (sorted by id), cached.
func within(src: int, mask: int, hours: float) -> Array:
	var key := "%d:%d:%d" % [src, mask, int(hours)]
	if _within.has(key):
		return _within[key]
	var pr: Array = paths_from(src, mask)
	var out: Array = []
	for sid in pr[2]:
		if sid != src and pr[0][sid] <= hours:
			out.append(sid)
	_within[key] = out
	return out

## Site ids from src to dst inclusive, or [] when unreachable.
func path_between(src: int, dst: int, mask: int) -> Array[int]:
	var out: Array[int] = []
	var pr: Array = paths_from(src, mask)
	if not pr[0].has(dst):
		return out
	var cur := dst
	while cur != src:
		out.append(cur)
		cur = pr[1][cur]
	out.append(src)
	out.reverse()
	return out

func hours_between(src: int, dst: int, mask: int) -> float:
	var pr: Array = paths_from(src, mask)
	return pr[0].get(dst, INF)

func route_id(a: int, b: int) -> int:
	return edge.get("%d:%d" % [a, b], -1)

# ── Parties: creation, routing, position ─────────────────────────────────────

func new_party(kind: String, faction: int, culture: String, home: int, members: Dictionary) -> SimParty:
	var p := SimParty.new()
	p.id = next_party
	next_party += 1
	p.kind = kind
	p.faction = faction
	p.culture = culture
	p.home = home
	p.members = members
	parties[p.id] = p
	return p

## Point a party at dst from wherever it stands. Returns false if no path.
func send(p: SimParty, dst: int, mask: int) -> bool:
	var on_route := p.path.size() >= 2 and p.leg < p.path.size() - 1
	if not on_route:
		var here := p.home if p.path.is_empty() else p.path[mini(p.leg, p.path.size() - 1)]
		var path := path_between(here, dst, mask)
		if path.is_empty():
			return false
		p.path = path
		p.leg = 0
		p.frac = 0.0
	else:
		var a := p.path[p.leg]
		var b := p.path[p.leg + 1]
		var leg_h: float = route_hours[p.route]
		var via_b := (1.0 - p.frac) * leg_h + hours_between(b, dst, mask)
		var via_a := p.frac * leg_h + hours_between(a, dst, mask)
		if via_b == INF and via_a == INF:
			return false
		var path: Array[int]
		if via_b <= via_a:
			path = path_between(b, dst, mask)
			path.push_front(a)
		else:
			path = path_between(a, dst, mask)
			path.push_front(b)
			p.frac = 1.0 - p.frac
		p.path = path
		p.leg = 0
	p.dest = dst
	p.state = "travel"
	p.route = route_id(p.path[0], p.path[1]) if p.path.size() >= 2 else -1
	return true

## World x of a party (tile units).
func party_x(p: SimParty) -> float:
	if p.path.is_empty():
		return site_by_id[p.home].x if site_by_id.has(p.home) else 0.0
	if p.leg >= p.path.size() - 1:
		return site_by_id[p.path[p.path.size() - 1]].x
	var a: Dictionary = site_by_id[p.path[p.leg]]
	var b: Dictionary = site_by_id[p.path[p.leg + 1]]
	return lerpf(a.x, b.x, p.frac)

## Where a party stands as (route id, fraction from route.a), or route -1 at a site.
func party_position(p: SimParty) -> Dictionary:
	if p.path.size() < 2 or p.leg >= p.path.size() - 1:
		return {"route": -1, "frac": 0.0, "site": p.path[p.path.size() - 1] if not p.path.is_empty() else p.home}
	var r: Dictionary = route_by_id[p.route]
	var f := p.frac if r.a == p.path[p.leg] else 1.0 - p.frac
	return {"route": p.route, "frac": f, "site": -1}

## Game hours a party of its kind needs for a route at its on-screen pace.
func leg_hours(kind: String, rid: int) -> float:
	return float(route_travel_h[rid]) * 1.5 / float(TRAVEL_TPS.get(kind, 2.5))

func remove_party(p: SimParty) -> void:
	parties.erase(p.id)

## Materialization write-back (Monsters track): players killed one `slug` of the lair at
## site_id. When nothing is left at home and no hunting pack is out, the lair is gone as if an
## expedition had cleared it, with a chronicle line. False if the lair has no such creature.
func lair_killed(site_id: int, slug: String, by := "adventurers") -> bool:
	var l: SimLair = lairs.get(site_id)
	if l == null or int(l.monsters.get(slug, 0)) <= 0:
		return false
	l.monsters[slug] = int(l.monsters[slug]) - 1
	if int(l.monsters[slug]) <= 0:
		l.monsters.erase(slug)
	stats_add("lair_player_kills", 1)
	if l.count() == 0 and l.out == 0:
		stats_add("lairs_cleared", 1)
		log_event("lair_cleared_players", {"lair": l.name, "what": SimConflict._lair_what(l), "by": by})
		SimConflict._lair_gone(self, l, "players")
	return true

# ── Materialization write-back (Life track) ──────────────────────────────────
# Real-time fights write their deaths here as they happen; the sim stays the truth, so
# folding actors back needs no further bookkeeping. None of these use the sim's rng.

## One member of a party died in real time (non-combatants come out of `people`). A party
## with no one left is gone, its home's counters settled. False if it had no such member.
## wipe = false keeps an emptied party for the caller's outcome call (SimConflict.*_outcome).
func party_member_killed(pid: int, slug: String, wipe := true) -> bool:
	var p: SimParty = parties.get(pid)
	if p == null or int(p.members.get(slug, 0)) <= 0:
		return false
	SimConflict.party_losses(p, {slug: 1})
	stats_add("real_deaths", 1)
	if p.size() == 0 and wipe:
		SimConflict._wiped(self, p)
	return true

## A person of a settlement died in real time: a soldier (the garrison shrinks by one) or a
## civilian (a worker, else a dependant). False if there was no one of that kind left.
func settlement_person_killed(sid: int, soldier: bool) -> bool:
	var s: SimSettlement = settlements.get(sid)
	if s == null:
		return false
	if soldier:
		if s.soldiers <= 0:
			return false
		s.soldiers -= 1
	elif s.workers > 0:
		s.workers -= 1
	elif s.dependants > 0:
		s.dependants -= 1
	else:
		return false
	stats_add("real_deaths", 1)
	return true

## Take `n` of a good (or coin with good "coin") out of a party's load: what players knocked
## loose from it. Returns how much was really there.
func party_take_cargo(pid: int, good: String, n: int) -> int:
	var p: SimParty = parties.get(pid)
	if p == null or n <= 0:
		return 0
	if good == "coin":
		var c := mini(n, int(p.coin))
		p.coin -= c
		return c
	var have := int(p.cargo.get(good, 0))
	var k := mini(have, n)
	if k > 0:
		p.cargo[good] = have - k
		if int(p.cargo[good]) <= 0:
			p.cargo.erase(good)
	return k

# ── Players' dealings (Deals track) ──────────────────────────────────────────
# What players buy, sell, deliver and are paid enters the books here. None of these use the
# sim's rng.

## A settlement trades with players: `n` units of `good` come into its stock (n < 0: go out
## of it) and `coin` leaves its wealth (coin < 0: comes in). good "" moves coin only (a
## reward). Refused (false, nothing changes) when a stock or the wealth would go negative.
func player_trade(sid: int, good: String, n: float, coin: float) -> bool:
	var s: SimSettlement = settlements.get(sid)
	if s == null or (good != "" and not s.stock.has(good)):
		return false
	if good != "" and float(s.stock[good]) + n < 0.0:
		return false
	if s.wealth - coin < 0.0:
		return false
	if good != "":
		s.stock[good] = float(s.stock[good]) + n
	s.wealth -= coin
	stats_add("player_trades", 1)
	return true

## Hold a party where it stands (players getting ready to escort it) or let it go.
func hold_party(pid: int, on: bool) -> bool:
	var p: SimParty = parties.get(pid)
	if p == null:
		return false
	p.held = on
	return true

# ── Trade ledger ─────────────────────────────────────────────────────────────

## The ledger's row for a route, made on first use.
func ledger_row(rid: int) -> Dictionary:
	if not ledger.has(rid):
		ledger[rid] = {"goods": {}, "value": 0.0, "trips": 0, "ambushes": 0, "taken": 0, "lost": 0.0,
			"beasts": 0, "raiders": {}}
	return ledger[rid]

# ── Queries ──────────────────────────────────────────────────────────────────

## Settlements, lairs and parties whose x lies in [x0, x1]: what a player's interest
## bubble would materialize.
func entities_near(x0: float, x1: float) -> Dictionary:
	var out := {"settlements": [], "lairs": [], "parties": []}
	for sid in _sorted_keys(settlements):
		var s: SimSettlement = settlements[sid]
		if s.x >= x0 and s.x <= x1:
			out.settlements.append(s)
	for lid in _sorted_keys(lairs):
		var l: SimLair = lairs[lid]
		if l.x >= x0 and l.x <= x1:
			out.lairs.append(l)
	for pid in parties:
		var p: SimParty = parties[pid]
		var px := party_x(p)
		if px >= x0 and px <= x1:
			out.parties.append(p)
	return out

func total_pop() -> int:
	var n := 0
	for sid in settlements:
		n += settlements[sid].pop()
	return n

func people_in_parties() -> int:
	var n := 0
	for pid in parties:
		var p: SimParty = parties[pid]
		n += p.people
	return n

## Invariant check: negative or non-finite stocks, populations, counts. [] when healthy.
func audit() -> Array[String]:
	var bad: Array[String] = []
	for sid in settlements:
		var s: SimSettlement = settlements[sid]
		if s.workers < 0 or s.dependants < 0 or s.soldiers < 0:
			bad.append("%s: negative cohort %d/%d/%d" % [s.name, s.workers, s.dependants, s.soldiers])
		for g in s.stock:
			if s.stock[g] < -1e-6 or is_nan(s.stock[g]) or is_inf(s.stock[g]):
				bad.append("%s: %s stock %f" % [s.name, g, s.stock[g]])
		if s.wealth < -1e-6 or is_nan(s.wealth):
			bad.append("%s: wealth %f" % [s.name, s.wealth])
		if s.out_caravans < 0 or s.out_raids < 0 or s.out_other < 0:
			bad.append("%s: negative away counter" % s.name)
	for pid in parties:
		var p: SimParty = parties[pid]
		for k in p.members:
			if p.members[k] < 0:
				bad.append("party %d: negative %s" % [p.id, k])
		for k in p.cargo:
			if p.cargo[k] < 0:
				bad.append("party %d: negative cargo %s" % [p.id, k])
		if p.people < 0 or p.coin < -1e-6:
			bad.append("party %d: negative people/coin" % p.id)
	for lid in lairs:
		for k in lairs[lid].monsters:
			if lairs[lid].monsters[k] < 0:
				bad.append("lair %d: negative %s" % [lid, k])
	return bad

# ── Chronicle ────────────────────────────────────────────────────────────────

## Append an event. Values must be ints, bools or strings (JSON-stable).
func log_event(kind: String, data: Dictionary) -> void:
	var e := {"t": t, "kind": kind}
	e.merge(data)
	chronicle.append(e)

func describe(e: Dictionary) -> String:
	return SimChronicle.describe(e)

func stats_add(key: String, n: int) -> void:
	stats[key] = int(stats.get(key, 0)) + n

func faction_name(fid: int) -> String:
	return factions[fid].name if factions.has(fid) else "no one"

func _site_label(sid: int) -> String:
	if settlements.has(sid):
		return settlements[sid].name
	if lairs.has(sid):
		return lairs[sid].name
	var s: Dictionary = site_by_id[sid]
	return "the %s %s" % [s.biome if s.biome != "" else s.band, "ruins" if ruins.has(sid) else "wilds"]

func route_name(rid: int) -> String:
	if not route_by_id.has(rid):
		return "the wilds"
	var r: Dictionary = route_by_id[rid]
	return "the %s %s" % [r.name, "road" if r.cls == ROAD else ("deep road" if r.cls == DEEP else "shaft road")]

static func _sorted_keys(d: Dictionary) -> Array:
	var k := d.keys()
	k.sort()
	return k

# ── Serialization ────────────────────────────────────────────────────────────

func to_dict() -> Dictionary:
	var ss: Array = []
	for sid in _sorted_keys(settlements):
		ss.append(settlements[sid].to_dict())
	var ls: Array = []
	for lid in _sorted_keys(lairs):
		ls.append(lairs[lid].to_dict())
	var fs: Array = []
	for fid in _sorted_keys(factions):
		fs.append(factions[fid].to_dict())
	var ps: Array = []
	for pid in _sorted_keys(parties):
		ps.append(parties[pid].to_dict())
	var rt := {}
	for k in route_threat:
		rt[str(k)] = route_threat[k]
	var tr := {}
	for k in route_traffic:
		var inner := {}
		for f in route_traffic[k]:
			inner[str(f)] = route_traffic[k][f]
		tr[str(k)] = inner
	var rv := {}
	for k in route_value:
		var inner := {}
		for f in route_value[k]:
			inner[str(f)] = route_value[k][f]
		rv[str(k)] = inner
	var rw := {}
	for k in region_weather:
		rw[str(k)] = region_weather[k]
	var ru: Array = _sorted_keys(ruins)
	var tn: Array = taken_names.keys()
	tn.sort()
	return {
		"version": 1, "seed": seed, "t": t, "rng_seed": str(rng.seed), "rng_state": str(rng.state),
		"sites": sites.duplicate(true), "routes": routes.duplicate(true),
		"settlements": ss, "lairs": ls, "factions": fs, "parties": ps, "ruins": ru,
		"chronicle": chronicle.duplicate(true), "stats": stats.duplicate(),
		"route_threat": rt, "route_traffic": tr, "route_value": rv, "region_weather": rw, "taken_names": tn,
		"next_party": next_party, "next_faction": next_faction, "world_x0": world_x0, "world_w": world_w,
	}.merged({"way_watch": SimBelow.watch_to_dict(self)} if not way_watch.is_empty() else {})

static func from_dict(d: Dictionary) -> WorldSim:
	SimData.ensure()
	var sim := WorldSim.new()
	sim.seed = int(d.seed)
	sim.t = int(d.t)
	sim.rng.seed = String(d.rng_seed).to_int()
	sim.rng.state = String(d.rng_state).to_int()
	for s in d.sites:
		sim.sites.append({"id": int(s.id), "kind": str(s.kind), "x": float(s.x), "y": float(s.y),
			"biome": str(s.biome), "band": str(s.band), "size": float(s.size)})
	for r in d.routes:
		var rr := {"id": int(r.id), "a": int(r.a), "b": int(r.b), "kind": str(r.kind),
			"length": float(r.length), "name": str(r.name), "cls": int(r.cls)}
		if r.has("trail"):
			rr["trail"] = bool(r.trail)
		if r.has("way"):
			rr["way"] = str(r.way)
		for k: String in ["top", "bottom"]:
			if r.has(k):
				rr[k] = [float(r[k][0]), float(r[k][1])]
		if r.has("path"):
			rr["path"] = (r.path as Array).duplicate(true)
		rr["crossings"] = Array(r.get("crossings", []))
		sim.routes.append(rr)
	sim.world_x0 = float(d.world_x0)
	sim.world_w = float(d.world_w)
	sim._index_sites()
	sim._index_routes()
	for sd in d.settlements:
		var s := SimSettlement.from_dict(sd)
		sim._derive_settlement(s)
		for g in SimData.good_names:     # a save from before the good existed
			if not s.stock.has(g):
				s.stock[g] = 0.0
		sim.settlements[s.id] = s
	for ld in d.lairs:
		var l := SimLair.from_dict(ld)
		l.x = sim.site_by_id[l.id].x
		l.biome = str(sim.site_by_id[l.id].get("biome", ""))
		sim.lairs[l.id] = l
	for fd in d.factions:
		var f := SimFaction.from_dict(fd)
		sim.factions[f.id] = f
	for pd in d.parties:
		var p := SimParty.from_dict(pd)
		sim.parties[p.id] = p
	for r in d.ruins:
		sim.ruins[int(r)] = true
	for e in d.chronicle:
		var ee := {}
		for k in e:
			var v: Variant = e[k]
			ee[k] = int(v) if v is float else v
		sim.chronicle.append(ee)
	for k in d.stats:
		sim.stats[k] = int(d.stats[k])
	for k in d.route_threat:
		sim.route_threat[int(k)] = float(d.route_threat[k])
	for k in d.route_traffic:
		var inner := {}
		for f in d.route_traffic[k]:
			inner[int(f)] = float(d.route_traffic[k][f])
		sim.route_traffic[int(k)] = inner
	for k in d.get("route_value", {}):
		var inner := {}
		for f in d.route_value[k]:
			inner[int(f)] = float(d.route_value[k][f])
		sim.route_value[int(k)] = inner
	for k in d.region_weather:
		sim.region_weather[int(k)] = float(d.region_weather[k])
	for n in d.taken_names:
		sim.taken_names[n] = true
	sim.next_party = int(d.next_party)
	sim.next_faction = int(d.next_faction)
	SimBelow.watch_from_dict(sim, d.get("way_watch", {}))
	return sim
