## The living world's scripted tour (main.gd option world_tour=DIR, offline host with cheats,
## windowed): arrive in the spawn town, talk to a merchant, hear rumours, buy a rope and sell
## ore, take work from the keeper, the quest log and the map, a caravan on the road, a raid met
## by guards, a hand-in, a patron tier and its gift. A screenshot per beat into DIR. Scene
## setting goes through Deals' and Life's cheats or host_call; everything the player does goes
## through the client systems as a click would.
##
##   tools/soft_godot.sh --resolution 1280x720 -- offline cheats class=fighter gen=dev seed=3 \
##       world=/tmp/x world_tour=/tmp/claude-1000/godspark-m4ui timeout=400 [tour=journey]
## tour=deep (gen=dev seed=4 suits it: a drow city and a deep dwarf hold): the toll at a drow city's
## gate, its street by lamplight, the deep dwarf hold, a deep gnome warren (the hold refounded by a
## cheat: no generated world has deep gnomes until the crystal caverns are made), any warren, and
## the map with the deep settlements' names.
## tour=below (gen=dev seed=4: its drow city has a way up): a raid from below climbing its cave
## mouth, the ambush on a surface road (a pass road where the raiders can reach one), the watch the
## town posts at the mouth, a roper in the dark, an aboleth in a lake dug for it (no generated world
## has a deep lake until the deep biomes land), a purple worm's tunnel (docs/tracks/raids-below.md).
class_name WorldTour
extends UiTour

var dc: DealsClient
var lc: LifeClient
var items: ItemsClient
var quest_id := ""

func steps() -> void:
	dc = cw.system(HostSystem.DEALS) as DealsClient
	lc = cw.system(HostSystem.LIFE) as LifeClient
	items = cw.system(HostSystem.ITEMS) as ItemsClient
	if "tour=map" in OS.get_cmdline_user_args():
		await map_only()
		return
	if "tour=deep" in OS.get_cmdline_user_args():
		await deep()
		return
	if "tour=below" in OS.get_cmdline_user_args():
		await below()
		return
	pres.rig.zoom = 1.6
	await host(func(h: WorldHost) -> void:
		var ds := h.system(HostSystem.DEALS) as DealsSystem
		var full := DealsCodec.write({"t": h.sim.t, "sites": ds.atlas_sites(), "routes": ds.atlas_routes(), "seen": [0], "all": true})
		print("TOUR atlas on join %d B, sites only %d B, %d sites, %d routes" % [full.size(),
			DealsCodec.write({"t": 0, "sites": ds.atlas_sites()}).size(), ds.atlas_sites().size(), ds.atlas_routes().size()]))
	# the arrival banner: show it again for the picture (it rose while the world loaded)
	ui.deals_ui._bannered.clear()
	ui.deals_ui._at = -1
	await wait(1.5)
	await shot("01_arrival")
	await talk_to("merchant")
	await shot("02_talk_prompt")
	await open_talk()
	await shot("03_dialogue")
	await talk_to("keeper")
	await talk_role("keeper")
	ui.deals_ui.choose("rumours")
	await wait(0.8)
	await shot("04_rumours")
	await more()

## `tour=deep`: the peoples below (docs/tracks/peoples-below.md).
func deep() -> void:
	var info := {}
	await host(func(h: WorldHost) -> void:
		for sid: int in WorldSim._sorted_keys(h.sim.settlements):
			var s: SimSettlement = h.sim.settlements[sid]
			if s.band == "surface" or Places.place(h.world, sid).is_empty():
				continue
			if not info.has(s.culture):
				info[s.culture] = sid
		var me := me_host(h)
		me.combatant.stats.max_hp = 900
		me.combatant.stats.current_hp = 900
		me.character.inventory.coin = 400
		me.character.inventory.changed[-1] = true)
	print("TOUR deep settlements by people: %s" % [info])
	pres.rig.zoom = 1.1
	if info.has("drow"):
		var city := int(info["drow"])
		# at the gate: the guard wants the toll
		await host(func(h: WorldHost) -> void:
			var life := h.system(HostSystem.LIFE) as LifeSystem
			var span := life.town_span(city)
			var st: Array = Places.place(h.world, city)["street"]
			info["gate"] = Vector2(span.x + 3.5, float(st[2]))
			info["mid"] = Vector2((span.x + span.y) / 2.0 + 0.5, float(st[2]))
			var me := me_host(h)
			h.teleport(me, info["mid"])
			TileCollision.depenetrate(h.world, me.body))
		await wait(3.0)
		await host(func(h: WorldHost) -> void:
			var life := h.system(HostSystem.LIFE) as LifeSystem
			var me := me_host(h)
			h.teleport(me, info["gate"])
			TileCollision.depenetrate(h.world, me.body)
			for e: HostEntity in life.actors_at(city):     # a guard comes to the gate
				if String(e.get_meta("sim")["role"]) == "guard":
					h.teleport(e, info["gate"] + Vector2(3.0, 0.0))
					TileCollision.depenetrate(h.world, e.body)
					info["guard"] = e.id
					break)
		await wait(1.5)
		await shot("30_drow_gate")
		if info.has("guard"):
			await talk_role("guard")
			await wait(0.6)
			await shot("31_toll_asked")
			ui.deals_ui.choose("toll")
			await wait(0.8)
			await shot("32_toll_paid")
			dc.leave()
			await wait(0.4)
		# the street by lamplight
		await host(func(h: WorldHost) -> void:
			var me := me_host(h)
			h.teleport(me, info["mid"])
			TileCollision.depenetrate(h.world, me.body))
		await wait(3.0)
		await shot("33_drow_street")
		pres.rig.zoom = 1.6
		await wait(1.0)
		await shot("34_drow_street_wide")
		pres.rig.zoom = 1.1
	for c: String in ["deep_dwarf", "kobold", "goblinoid"]:
		if not info.has(c):
			continue
		var sid := int(info[c])
		# come in from nearby, as a walker would: a long jump straight in leaves the view's light
		# behind for a while (seen on the CPU renderer)
		await host(func(h: WorldHost) -> void:
			var me := me_host(h)
			h.teleport(me, MapLogic.site_xy(h.world.meta, sid) + Vector2(300.0, 0.0))
			TileCollision.depenetrate(h.world, me.body))
		await wait(3.0)
		await host(func(h: WorldHost) -> void:
			var me := me_host(h)
			var span := (h.system(HostSystem.LIFE) as LifeSystem).town_span(sid)
			var st: Array = Places.place(h.world, sid)["street"]
			h.teleport(me, Vector2((span.x + span.y) / 2.0 + 0.5, float(st[2])))
			TileCollision.depenetrate(h.world, me.body))
		await wait(8.0)          # a long way from the last: the chunks and their light come in
		await shot("35_%s" % c)
	# a deep gnome warren: the hold refounded by deep gnomes (a cheat)
	var hold := int(info.get("deep_dwarf", info.get("kobold", info.get("goblinoid", -1))))
	if hold >= 0:
		await host(func(h: WorldHost) -> void:
			var me := me_host(h)
			h.teleport(me, MapLogic.site_xy(h.world.meta, hold) + Vector2(400.0, 0.0))
			TileCollision.depenetrate(h.world, me.body))
		await wait(2.0)
		await host(func(h: WorldHost) -> void:
			refound(h, hold, "deep_gnome")
			var me := me_host(h)
			var span := (h.system(HostSystem.LIFE) as LifeSystem).town_span(hold)
			var st: Array = Places.place(h.world, hold)["street"]
			h.teleport(me, Vector2((span.x + span.y) / 2.0 + 0.5, float(st[2])))
			TileCollision.depenetrate(h.world, me.body))
		await wait(4.0)
		await shot("36_deep_gnome_warren")
	# the map: the deep settlements, seen, with their names
	ui.open("map")
	await wait(0.8)
	var m := ui.screen("map") as WorldMapScreen
	m.zoom = m._fit * 1.8
	var focus := cw.body.center()
	var deep_xy: Array = []
	for c: String in info:
		if c in ["drow", "deep_dwarf", "kobold", "goblinoid", "deep_gnome"]:
			deep_xy.append(MapLogic.site_xy(cw.world.meta, int(info[c])))
	if not deep_xy.is_empty():
		focus = Vector2.ZERO
		for v: Vector2 in deep_xy:
			focus += v / deep_xy.size()
	m.origin = MapLogic.origin_for(focus, m.world_size(), m.zoom, WorldMapScreen.MAP_RECT.size)
	m._clamp()
	m.canvas.queue_redraw()
	await wait(0.5)
	await shot("37_map_deep")
	ui.close("map")

## Go to `at` as a walker comes: first 240 tiles off, then in (a long jump straight in leaves the
## view's light and chunks behind for a while on the CPU renderer).
func _come_to(at: Vector2, settle := 6.0) -> void:
	await host(func(h: WorldHost) -> void:
		var me := me_host(h)
		h.teleport(me, at + Vector2(240.0, 0.0))
		TileCollision.depenetrate(h.world, me.body))
	await wait(2.5)
	await host(func(h: WorldHost) -> void:
		var me := me_host(h)
		h.teleport(me, at)
		TileCollision.depenetrate(h.world, me.body))
	await wait(settle)

## Open floor cells of the deep roads (their feet-cell paths), fraction k along all of them.
static func deep_cell(h: WorldHost, k: float) -> Vector2:
	var cells: Array = []
	for rid: int in WorldSim._sorted_keys(h.sim.route_by_id):
		if int(h.sim.route_by_id[rid].cls) == WorldSim.DEEP:
			cells.append_array(Places.route_path(h.world, rid))
	if cells.is_empty():
		return Vector2.INF
	var c: Vector2i = cells[clampi(int(k * cells.size()), 0, cells.size() - 1)]
	return Vector2(c.x + 0.5, c.y)

## `tour=below`: raids from below and the deep life (docs/tracks/raids-below.md).
func below() -> void:
	var info := {}
	await host(func(h: WorldHost) -> void:
		var me := me_host(h)
		me.combatant.stats.max_hp = 2000
		me.combatant.stats.current_hp = 2000
		var sim := h.sim
		for rid: int in WorldSim._sorted_keys(sim.route_by_id):
			var rr: Dictionary = sim.route_by_id[rid]
			var deep := SimBelow.deep_end(sim, rid)
			if int(rr.cls) == WorldSim.LINK and sim.settlements.has(deep) and SimBelow.pull(sim.settlements[deep].culture) > 1.0:
				info["city"] = deep
				info["way"] = rid
		if not info.has("city"):
			return
		# a world just begun has sent no caravans yet: give its roads the trade a year would
		for rid: int in WorldSim._sorted_keys(sim.route_by_id):
			var rr: Dictionary = sim.route_by_id[rid]
			if int(rr.cls) == WorldSim.ROAD and sim.settlements.has(int(rr.a)) and not sim.route_value.has(rid):
				sim.route_value[rid] = {sim.settlements[int(rr.a)].faction: 3000.0}
				sim.route_traffic[rid] = {sim.settlements[int(rr.a)].faction: 8.0}
		var city: SimSettlement = sim.settlements[int(info["city"])]
		city.soldiers = maxi(city.soldiers, 60)
		var life := h.system(HostSystem.LIFE) as LifeSystem
		info["mouth"] = life.below.mouth(h, int(info["way"]))
		info["raid"] = life.cheat_below(int(info["city"]), -1, "way", 0.9, 8)
		# the way the raid took, and a stretch of it with ground (a sinkhole's link has real cells
		# on its rope and at its ends)
		var climbing: SimParty = sim.parties.get(int(info["raid"]))
		if climbing != null:
			info["way"] = SimBelow.way_of(climbing)
			info["mouth"] = life.below.mouth(h, int(info["way"]))
			for k in 40:
				climbing.frac = (k + 0.5) / 40.0
				var q := life.road.party_pos(h, climbing)
				if q.distance_to(info["mouth"]) > 6.0 and q.distance_to(info["mouth"]) < 40.0 and life.monsters(h).director._stand_near(h, q, "") != Vector2.INF:
					break
		print("TOUR below: city %s, way %s, mouth %s, raid %d" % [city.name, sim.route_name(int(info["way"])), info["mouth"], int(info["raid"])]))
	if not info.has("city"):
		print("TOUR below: no raiding city with a way up")
		return
	pres.rig.zoom = 1.3
	# the raid climbing out of the mouth
	await host(func(h: WorldHost) -> void:
		var me := me_host(h)
		var life := h.system(HostSystem.LIFE) as LifeSystem
		var p: SimParty = h.sim.parties.get(int(info["raid"]))
		var at: Vector2 = info["mouth"]
		if p != null and life.road.party_pos(h, p) != Vector2.INF:
			at = (at + life.road.party_pos(h, p)) * 0.5
		h.teleport(me, at + Vector2(-10.0, 3.0))
		TileCollision.depenetrate(h.world, me.body))
	await wait(5.0)
	await shot("40_raid_climbing")
	await wait(4.0)
	await shot("41_raid_out_of_the_mouth")
	# the ambush on a surface road, a pass road where they can reach one
	await host(func(h: WorldHost) -> void:
		var sim := h.sim
		var life := h.system(HostSystem.LIFE) as LifeSystem
		var targets := SimBelow.targets(sim, sim.settlements[int(info["city"])], true)
		var road := -1
		for tg: Dictionary in targets:
			var rr: Dictionary = sim.route_by_id[int(tg["route"])]
			if not (sim.settlements.has(int(rr.a)) and sim.settlements.has(int(rr.b))):
				continue
			if road < 0 or ("pass" in (tg["crossings"] as Array) and not "pass" in (sim.route_by_id[road].get("crossings", []) as Array)):
				road = int(tg["route"])
		if road < 0:
			return
		info["road"] = road
		var rr: Dictionary = sim.route_by_id[road]
		var pid := life.cheat_below(int(info["city"]), road, "road", 0.5, 8)
		var cid := life.cheat_party("caravan", int(rr.a), int(rr.b), 0.42, 4)
		info["ambush"] = pid
		var p: SimParty = sim.parties.get(pid)
		if p != null:
			info["ambush_at"] = life.road.party_pos(h, p) + Vector2(-14.0, 3.0)
			p.held = true            # it waits for the picture to come in
		print("TOUR below: ambush on %s (%s), raid %d, caravan %d" % [sim.route_name(road), "+".join(rr.get("crossings", [])), pid, cid]))
	if info.has("ambush_at"):
		await _come_to(info["ambush_at"], 4.0)
		await host(func(h: WorldHost) -> void:
			var p: SimParty = h.sim.parties.get(int(info["ambush"]))
			if p != null:
				p.held = false)
	await wait(2.0)
	await shot("42_ambush_waiting")
	await wait(10.0)
	await shot("43_ambush_fight")
	# the watch at the mouth
	await host(func(h: WorldHost) -> void:
		var sim := h.sim
		var town := SimBelow.surface_end(sim, int(info["way"]))
		if sim.settlements.has(town):
			sim.settlements[town].soldiers = maxi(sim.settlements[town].soldiers, 40)
			SimBelow.post_watch(sim, town, int(info["way"]))
		var me := me_host(h)
		h.teleport(me, Vector2(info["mouth"]) + Vector2(-8.0, 3.0))
		TileCollision.depenetrate(h.world, me.body))
	await wait(5.0)
	await shot("44_watch_at_mouth")
	# the deep life: a dark stretch of the deeps by the city
	await host(func(h: WorldHost) -> void:
		var ms := h.system(HostSystem.MONSTERS) as MonstersSystem
		var combat := h.system(HostSystem.COMBAT) as CombatSystem
		var me := me_host(h)
		var spot := Vector2.INF
		for k in 40:
			var at := deep_cell(h, 0.1 + k * 0.02)
			if at != Vector2.INF and combat.sight.field_category(at + Vector2(0, 1)) == LightEngine.Category.DARK:
				spot = at
				break
		if spot == Vector2.INF:
			return
		info["dark"] = spot
		var e := ms.spawn("roper", spot, {"home": spot})
		info["roper"] = e.id if e != null else -1
		print("TOUR below: a roper waits at %s, hidden %s" % [spot, combat.is_hidden(e) if e != null else false]))
	if info.has("dark"):
		pres.rig.zoom = 1.0
		await _come_to(Vector2(info["dark"]) + Vector2(-12.0, 1.0), 6.0)
		await shot("45_roper_in_the_dark")
		await host(func(h: WorldHost) -> void:
			var me := me_host(h)
			h.teleport(me, Vector2(info["dark"]) + Vector2(-4.0, 1.0))
			TileCollision.depenetrate(h.world, me.body))
		await wait(2.5)
		await shot("46_roper_springs")
	# the aboleth: a lake dug in the deeps, a lair site beside it made its sea
	await host(func(h: WorldHost) -> void:
		var sim := h.sim
		var w := h.world
		var c := MapLogic.site_xy(h.world.meta, int(info["city"]))
		var ms := h.system(HostSystem.MONSTERS) as MonstersSystem
		var floor := deep_cell(h, 0.75)
		if floor == Vector2.INF:
			return
		var x0 := floori(floor.x) - 18
		var y0 := floori(floor.y)
		var water := TileDefs.id("water")
		for x in range(x0, x0 + 36):
			for y in range(y0 - 7, y0):
				if Burrow.natural(w.get_fg(x, y)) or w.get_fg(x, y) == TileDefs.AIR:
					w.set_fg(x, y, water)
		# a lair site near: an aboleth sea there, with its thralls
		# a lair site to hold it (dev worlds have few below): the nearest one, moved to the lake
		var lid := -1
		var bd := INF
		for s: Dictionary in sim.sites:
			if String(s.kind) in ["lair", "ruin"] and not sim.settlements.has(int(s.id)):
				var d := absf(float(s.x) - floor.x) + (0.0 if SimData.band_family(String(s.band)) == "deeps" else 100000.0)
				if d < bd:
					bd = d
					lid = int(s.id)
		if lid < 0:
			print("TOUR below: no lair site for the aboleth")
			return
		sim.site_by_id[lid]["band"] = "deeps"
		var site: Dictionary = sim.site_by_id[lid]
		site["x"] = floor.x
		site["y"] = floor.y
		site["biome"] = "deep_lake"
		var l := SimLair.new()
		l.id = lid
		l.kind = "aboleth"
		l.family = "deeps"
		l.name = "Glimmerdeep Sea"
		l.apex = true
		l.monsters = {"aboleth": 1, "chuul": 1, "warrior-infantry": 2, "scout": 1}
		l.max_n = 4
		l.hunger = 0.3
		l.x = floor.x
		l.biome = "deep_lake"
		sim.lairs[lid] = l
		(ms.lairs as LairLink).fold(h, lid)
		# lamps along the shore and over the water, to see it by
		for x in range(x0 - 6, x0 + 44, 6):
			if h.world.get_fg(x, y0 + 3) == TileDefs.AIR:
				h.world.set_fg(x, y0 + 3, TileDefs.id("torch"))
		info["lake"] = floor
		print("TOUR below: a lake at %s, lair %d made an aboleth sea" % [floor, lid]))
	if info.has("lake"):
		pres.rig.zoom = 1.7
		await _come_to(Vector2(info["lake"]) + Vector2(-20.0, 2.0), 8.0)
		await shot("47_aboleth_lair")
		await host(func(h: WorldHost) -> void:
			var me := me_host(h)
			h.teleport(me, Vector2(info["lake"]) + Vector2(-3.0, 3.0))
			TileCollision.depenetrate(h.world, me.body))
		await wait(4.0)
		await shot("47b_aboleth_rises")
	# a purple worm's tunnel through the rock
	await host(func(h: WorldHost) -> void:
		var ms := h.system(HostSystem.MONSTERS) as MonstersSystem
		var me := me_host(h)
		var at := deep_cell(h, 0.4)
		if at == Vector2.INF:
			return
		# room for its body where it starts (a cheat for the picture): from there it digs its own
		for x in range(floori(at.x) - 4, floori(at.x) + 5):
			for y in range(floori(at.y), floori(at.y) + 8):
				if Burrow.natural(h.world.get_fg(x, y)):
					h.world.set_fg(x, y, TileDefs.AIR)
		var e := ms.spawn("purple-worm", at, {"home": at})
		if e == null:
			return
		var b := e.brain as MonsterBrain
		b.burrow.cap = 2000             # a picture can't wait out its minutes
		b._wander_to = at + Vector2(-60.0, -8.0)
		b._wander_at = 1.0e9
		b._enter(MonsterBrain.State.WANDER)
		b.hostility = "neutral"
		info["worm"] = e.id
		info["worm_at"] = at
		h.world.set_fg(floori(at.x) + 10, floori(at.y) + 1, TileDefs.id("torch"))
		h.teleport(me, at + Vector2(14.0, 2.0))
		TileCollision.depenetrate(h.world, me.body))
	if info.has("worm"):
		pres.rig.zoom = 1.6
		await wait(25.0)
		await host(func(h: WorldHost) -> void:
			var e := h.entity(int(info["worm"]))
			var me := me_host(h)
			if e != null:
				print("TOUR below: the worm dug %d tiles, at %s" % [(e.brain as MonsterBrain).burrow.dug, e.body.pos])
				# torches down its tunnel, to see it by
				var a: Vector2 = info["worm_at"]
				for x in range(floori(minf(a.x, e.body.pos.x)), floori(maxf(a.x, e.body.pos.x)) + 1, 7):
					for y in range(floori(minf(a.y, e.body.pos.y)) - 4, floori(maxf(a.y, e.body.pos.y)) + 8):
						if h.world.get_fg(x, y) == TileDefs.AIR and h.world.is_solid(x, y - 1):
							if h.world.get_fg(x, y + 3) == TileDefs.AIR:
								h.world.set_fg(x, y + 3, TileDefs.id("torch"))
							break
				h.teleport(me, (e.body.pos + Vector2(info["worm_at"])) * 0.5 + Vector2(0.0, 1.0))
				TileCollision.depenetrate(h.world, me.body))
		await wait(3.0)
		await shot("48_purple_worm_tunnel")

## A cheat for pictures: a deep settlement taken over by another people, its town rebuilt in their
## style and shown again.
static func refound(h: WorldHost, sid: int, culture: String) -> void:
	var s: SimSettlement = h.sim.settlements[sid]
	var f := h.sim._new_faction(culture)
	f.capital = sid
	s.culture = culture
	s.faction = f.id
	h.sim._derive_settlement(s)
	var life := h.system(HostSystem.LIFE) as LifeSystem
	life.town.fold(h, sid)
	var place := Places.place(h.world, sid)
	for lot: Dictionary in place["lots"]:
		if String(lot["state"]) == "built":
			lot["state"] = "empty"
	h.places_keeper.apply(h, sid, s.tier, culture)

## `tour=map`: the land on the map, the whole world, then the middle of it close to.
func map_only() -> void:
	await wait(1.0)
	await shot("00_spawn")
	ui.open("map")
	await wait(0.8)
	var m := ui.screen("map") as WorldMapScreen
	m.zoom = m._fit
	m._clamp()
	m.canvas.queue_redraw()
	await wait(0.4)
	await shot("01_map_whole")
	m.zoom = m._fit * 4.0
	m.origin = MapLogic.origin_for(cw.body.center(), m.world_size(), m.zoom, WorldMapScreen.MAP_RECT.size)
	m._clamp()
	m.canvas.queue_redraw()
	await wait(0.4)
	await shot("02_map_close")
	ui.close("map")

## Later beats. `tour=journey` on the command line runs only the journey's beats after the arrival.
func more() -> void:
	if "tour=journey" in OS.get_cmdline_user_args():
		await journey()
		return
	await trade()
	await work()
	await road()
	await journey()
	await hand_in()
	await patron()

## What the end-to-end story walks through, as pictures: an escort beside its wagon on the road,
## raiders met at the gate, a rope down from the town's edge, stairs in a cavern, and a deep
## settlement seen from the deep road's end. Positions are scene setting (teleports).
func journey() -> void:
	var town := home_town()
	var info := {}
	pres.rig.zoom = 1.2
	await host(func(h: WorldHost) -> void:
		var life := h.system(HostSystem.LIFE) as LifeSystem
		var me := me_host(h)
		me.combatant.stats.max_hp = 900
		me.combatant.stats.current_hp = 900
		var to := -1
		for e: Array in h.sim.adj.get(town, []):
			if h.sim.settlements.has(int(e[0])):
				to = int(e[0])
				break
		var pid := life.cheat_party("caravan", town, to, 0.4, 6) if to >= 0 else -1
		info["pid"] = pid
		if pid > 0:
			var pos := life.road.party_pos(h, h.sim.parties[pid])
			info["pos"] = pos
			h.teleport(me, pos + Vector2(4.0, 3.0))
			TileCollision.depenetrate(h.world, me.body))
	print("TOUR escort party %s at %s" % [info.get("pid", -1), info.get("pos", "-")])
	await wait(5.0)
	await host(func(h: WorldHost) -> void:
		var life := h.system(HostSystem.LIFE) as LifeSystem
		var p: SimParty = h.sim.parties.get(int(info.get("pid", -1)))
		if p != null:
			var me := me_host(h)
			h.teleport(me, life.road.party_pos(h, p) + Vector2(5.0, 3.0))
			TileCollision.depenetrate(h.world, me.body))
	await wait(2.0)
	await shot("23_escort_road")
	# raiders at the gate
	await host(func(h: WorldHost) -> void:
		(h.system(HostSystem.LIFE) as LifeSystem).schedule("raid", 0.2, town)
		var me := me_host(h)
		h.teleport(me, MapLogic.site_xy(h.world.meta, town) + Vector2(4, 1))
		TileCollision.depenetrate(h.world, me.body))
	await wait(5.0)
	await host(func(h: WorldHost) -> void:
		var life := h.system(HostSystem.LIFE) as LifeSystem
		var me := me_host(h)
		for id: int in life.actors:
			var x := h.entity(id)
			if x != null and String(life.actors[id].get("role", "")) == "raider":
				h.teleport(me, x.body.pos + Vector2(5.0, 1.0))
				TileCollision.depenetrate(h.world, me.body)
				info["raider"] = x.body.pos
				break)
	print("TOUR raider at %s" % info.get("raider", "-"))
	await wait(1.5)
	await shot("24_raid_at_gate")
	# a rope near the town, the nearest stair flight below, and a deep settlement
	await host(func(h: WorldHost) -> void:
		var near := MapLogic.site_xy(h.world.meta, town)
		var rope := _tile_near(h, "rope", near, false)
		var stairs := _tile_near(h, "stairs_r", near, true)
		info["rope"] = rope
		info["stairs"] = stairs
		var deep := -1
		for sid: int in WorldSim._sorted_keys(h.sim.settlements):
			if (h.sim.settlements[sid] as SimSettlement).band != "surface":
				deep = sid
				break
		info["deep"] = deep
		if rope != Vector2i(-1, -1):
			var me := me_host(h)
			h.teleport(me, Vector2(rope.x + 0.5, rope.y)))
	print("TOUR rope %s, stairs %s, deep settlement %s" % [info.get("rope"), info.get("stairs"), info.get("deep")])
	await wait(0.8)
	await shot("25_rope_descent")
	await host(func(h: WorldHost) -> void:
		var c: Vector2i = info["stairs"]
		if c != Vector2i(-1, -1):
			var me := me_host(h)
			h.teleport(me, Vector2(c.x + 0.5, c.y + 1.0))
			TileCollision.depenetrate(h.world, me.body))
	await wait(1.5)
	await shot("26_cavern_stairs")
	await host(func(h: WorldHost) -> void:
		var sid := int(info["deep"])
		if sid >= 0:
			var me := me_host(h)
			var st: Array = Places.place(h.world, sid).get("street", [])
			var at := Vector2(float(st[0]) + 4.0, float(st[2])) if st.size() == 3 else MapLogic.site_xy(h.world.meta, sid) + Vector2(0, 2)
			h.teleport(me, at)
			TileCollision.depenetrate(h.world, me.body))
	await wait(4.0)
	await shot("27_deep_settlement")
	pres.rig.zoom = 1.6

## The cell of a tile nearest a point (in the caves and below when `deep`), or (-1, -1).
func _tile_near(h: WorldHost, tile: String, at: Vector2, deep: bool) -> Vector2i:
	var id := TileDefs.id(tile)
	var w := h.world
	var best := Vector2i(-1, -1)
	var bd := INF
	var top := int(at.y) - 30 if deep else mini(w.height - 1, int(at.y) + 40)
	for y in range(top, maxi(2, int(at.y) - 260), -1):
		for x in range(maxi(0, int(at.x) - 300), mini(w.width, int(at.x) + 300), 2):
			if w.get_fg(x, y) == id:
				var d := Vector2(x, y).distance_squared_to(at)
				if d < bd:
					bd = d
					best = Vector2i(x, y)
	return best

## The spawn town's site id and faction (from the atlas: the seen settlement nearest us).
func home_town() -> int:
	var best := -1
	var bd := INF
	for sid: int in dc.seen:
		var xy := MapLogic.site_xy(cw.world.meta, sid)
		if String(dc.sites.get(sid, {}).get("kind", "")) == "settlement" and xy.distance_to(cw.body.pos) < bd:
			bd = xy.distance_to(cw.body.pos)
			best = sid
	return best

## A caravan coming up the road (Life's cheat), seen from the road; then raiders at the gate.
func road() -> void:
	var town := home_town()
	var info := {}
	await host(func(h: WorldHost) -> void:
		var life := h.system(HostSystem.LIFE) as LifeSystem
		var me := me_host(h)
		me.combatant.stats.max_hp = 400
		me.combatant.stats.current_hp = 400
		var from := -1
		for e: Array in h.sim.adj.get(town, []):
			if h.sim.settlements.has(int(e[0])):
				from = int(e[0])
				break
		var pid := life.cheat_party("caravan", from, town, 0.8, 6) if from >= 0 else -1
		info["pid"] = pid
		if pid > 0:
			var pos := life.road.party_pos(h, h.sim.parties[pid])
			h.teleport(me, pos + Vector2(-14.0, 2.0))
			TileCollision.depenetrate(h.world, me.body))
	print("TOUR caravan party %s" % info.get("pid", -1))
	await wait(4.0)
	await shot("13_caravan")
	await host(func(h: WorldHost) -> void:
		var life := h.system(HostSystem.LIFE) as LifeSystem
		life.schedule("raid", 0.2, town)
		var me := me_host(h)
		h.teleport(me, MapLogic.site_xy(h.world.meta, town) + Vector2(10, 1))
		TileCollision.depenetrate(h.world, me.body))
	await wait(1.5)
	await shot("14_raid_coming")
	await wait(6.0)
	await shot("15_raid")
	await wait(8.0)
	await shot("16_raid_met")

## The work done (cheat) and handed in to the keeper: the celebration.
func hand_in() -> void:
	if quest_id == "":
		return
	dc.cheat({"op": "complete", "q": quest_id})
	await wait(1.0)
	for k in 15:
		await talk_role("keeper")
		if dc.talking():
			break
		await wait(2.0)
	await shot("17_hand_in_option")
	ui.deals_ui.choose("turn_in:" + quest_id)
	await wait(1.2)
	await shot("18_handed_in")

## Standing up to the first patron tier (cheat), the gift from the keeper, the standing screen.
func patron() -> void:
	var fac := String(dc.sites.get(home_town(), {}).get("faction", ""))
	dc.leave()
	await wait(0.3)
	dc.cheat({"op": "standing", "faction": fac, "n": 30})
	await wait(1.5)
	await shot("19_patron_tier")
	await talk_role("keeper")
	ui.deals_ui.choose("patron")
	await wait(1.2)
	await shot("20_patron_gift")
	dc.leave()
	await wait(0.3)
	ui.open("standing")
	await wait(0.5)
	await shot("21_standing")
	ui.close("standing")
	ui.open("help")
	await wait(0.4)
	await shot("22_help")
	ui.close("help")

## Work from the keeper: the offers in the dialogue, accepted; the log; the tracker.
func work() -> void:
	await talk_role("keeper")
	ui.deals_ui.choose("quests")
	await wait(1.0)
	await shot("08_work_offers")
	var offers: Array = dc.conversation.get("offers", [])
	var taken := ""
	for q: Dictionary in offers:
		if String(q.get("kind", "")) == "message":
			taken = String(q["id"])
	if taken == "" and not offers.is_empty():
		taken = String(offers[0]["id"])
	if taken != "":
		dc.accept(taken)
	await wait(1.0)
	quest_id = taken
	dc.leave()
	await wait(0.5)
	ui.open("quests")
	await wait(0.5)
	await shot("09_quest_log")
	ui.close("quests")
	await wait(0.4)
	await shot("10_tracker")
	ui.open("map")
	await wait(0.6)
	await shot("11_map")
	var m := ui.screen("map") as WorldMapScreen
	m.zoom_at(m._p(cw.body.center()), 1.5)
	await wait(0.3)
	var near := -1
	for sid: int in m._sites_px:
		if sid in dc.seen and (near < 0 or (m._sites_px[sid] as Vector2).distance_to(m._p(cw.body.center())) < (m._sites_px[near] as Vector2).distance_to(m._p(cw.body.center()))):
			near = sid
	var heard := -1
	for sid: int in m._sites_px:
		if not sid in dc.seen:
			heard = sid
	m.hover = heard if heard >= 0 else near
	m._card()
	m.canvas.queue_redraw()
	await wait(0.3)
	await shot("12_map_zoomed_card")
	ui.close("map")

## Buy a rope and sell ore at the merchant; the smith's rack with a tooltip.
func trade() -> void:
	dc.cheat({"op": "coin", "n": 150})
	dc.cheat({"op": "give", "base": "ore:iron", "n": 6})
	await wait(0.3)
	await talk_role("merchant")
	ui.deals_ui.choose("shop")
	await wait(1.0)
	await shot("05_shop")
	for l: Dictionary in dc.shop.get("listings", []):
		if String(l["item"].get("base", "")) == "tile:rope":
			dc.buy(String(l["id"]), 1)
	for slot: int in dc.shop.get("sell", {}):
		if String(items.item(slot).get("base", "")) == "ore:iron":
			dc.sell(slot, Items.count(items.item(slot)))
	await wait(0.35)
	await shot("06_traded")
	ui.close("shop")
	await wait(0.3)
	await talk_role("smith")
	ui.deals_ui.choose("smith")
	await wait(1.0)
	var scr := ui.screen("shop") as ShopScreen
	if scr != null and scr.goods_box.get_child_count() > 0:
		var row := scr.goods_box.get_child(0) as Control
		var ls: Array = dc.shop.get("listings", [])
		if not ls.is_empty():
			scr._tip(ls[0]["item"], row)
	await wait(0.3)
	await shot("07_smith")
	ui.close("shop")

## Stand beside the nearest person of a role (Deals' goto cheat) and let the prompt settle.
func talk_to(role: String) -> void:
	if dc.talking():
		dc.leave()
		await wait(0.4)
	dc.cheat({"op": "goto", "role": role})
	await wait(1.2)
	var roles := {}
	for id: int in lc.people:
		roles[String(lc.people[id].get("role", ""))] = int(roles.get(String(lc.people[id].get("role", "")), 0)) + 1
	print("TOUR goto %s: note %s, people %s, sim_t %d" % [role, dc.last_note.get(DealsCodec.Msg.CHEAT, "?"), roles, dc.sim_t])
	if ui.deals_ui.target != 0:
		var r: ClientWorld.RemoteEntity = cw.remotes.get(ui.deals_ui.target)
		if r != null:
			cw.body.facing = 1 if r.pos.x > cw.body.pos.x else -1

## E, as the player presses it.
func open_talk() -> void:
	Input.action_press("interact")
	await wait(0.15)
	Input.action_release("interact")
	var t := 0.0
	while not dc.talking() and t < 3.0:
		await wait(0.1)
		t += 0.1
	await wait(0.4)

## Talk to the nearest person of a role (the tour's stand-in for walking up to them).
func talk_role(role: String) -> void:
	var best := 0
	var bd := INF
	for id: int in lc.people:
		var r: ClientWorld.RemoteEntity = cw.remotes.get(id)
		if r != null and String(lc.people[id].get("role", "")) == role and bool(lc.people[id].get("talk", false)):
			var d := r.pos.distance_to(cw.body.pos)
			if d < bd:
				bd = d
				best = id
	if dc.talking():
		dc.leave()
		await wait(0.4)
	if best != 0:
		var target := best
		await host(func(h: WorldHost) -> void:
			var x := h.entity(target)
			var me := me_host(h)
			if x != null and me != null:
				h.teleport(me, x.body.pos + Vector2(1.6, 0.0))
				TileCollision.depenetrate(h.world, me.body))
		await wait(0.5)
		dc.talk(best)
	var t := 0.0
	while not dc.talking() and t < 3.0:
		await wait(0.1)
		t += 0.1
	print("TOUR talk %s (%d, %.1f tiles): %s" % [role, best, bd, "open" if dc.talking() else String(dc.last_note.get(DealsCodec.Msg.TALK_TO, "?"))])
	await wait(0.4)
