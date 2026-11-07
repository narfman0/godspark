## Screenshot of Life on a generated world: the host runs (Life, Monsters, Combat) with a player
## in a town, then the view draws the world and every actor the host has, at their host
## positions, with guards' torches lit at night and wagons drawn as carts. Runs under
## tools/soft_godot.sh (CPU Vulkan).
##   tools/soft_godot.sh -s res://tools/life_shot.gd -- out=/tmp/x.png mode=day|night|caravan|raid
##     [seed=4] [zoom=1] [dx=0 dy=0] [ticks=600]
##   mode=crossing gen=dev seed=15 cross=pass|bridge|ford [raid=1] [along=0.5] [ticks=300]: a caravan
##     (a cheat, and so is the raid) on the first road with that crossing, `along` of the way
##     over it; raid=1 sets raiders waiting a few tiles ahead of it, in an ambush.
extends SceneTree

func _initialize() -> void:
	var o := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		o[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var size := Vector2i(1280, 720)
	DisplayServer.window_set_size(size)
	root.size = size
	var mode := String(o.get("mode", "day"))
	var w := WorldGen.generate_named(String(o["gen"]), int(o.get("seed", "4"))) if o.has("gen") else WorldGen.generate(1024, 512, int(o.get("seed", "4")))
	var host := WorldHost.new(w)
	Dice.rng = host.rng
	host.add_system(CombatSystem.new())
	var ms := MonstersSystem.new()
	ms.director_enabled = 0
	ms.lairs_enabled = false
	host.add_system(ms)
	var life := LifeSystem.new()
	host.add_system(life)
	var sid := -1
	var bd := INF
	for k: int in WorldSim._sorted_keys(host.sim.settlements):
		var s: SimSettlement = host.sim.settlements[k]
		var d := absf(s.x - host.spawn.x) + (0.0 if s.band == "surface" else 4096.0)
		if d < bd:
			bd = d
			sid = k
	var p := host.add_player("watcher", 2, {"class": "fighter"})
	p.combatant.stats.max_hp = 9999
	p.combatant.stats.current_hp = 9999
	var st: Array = Places.place(w, sid).get("street", [])
	var centre := Vector2((float(st[0]) + float(st[1])) / 2.0, float(st[2])) if st.size() >= 3 else LifeTown.site_pos(host, sid)
	p.body.pos = centre
	TileCollision.depenetrate(w, p.body)
	if mode == "night":
		host.sleep(fposmod(22.0 - host.clock.hour_of_day(), 24.0))
	var focus := centre
	var pid := -1
	if mode == "crossing":
		pid = _crossing(host, life, String(o.get("cross", "pass")), float(o.get("along", 0.5)), o.has("raid"))
		print("life_shot: caravan party %d" % pid)
	var nb := -1
	for k: int in WorldSim._sorted_keys(host.sim.settlements):
		if k != sid and not host.sim.path_between(k, sid, WorldSim.ROAD | WorldSim.DEEP | WorldSim.LINK).is_empty():
			if nb < 0 or absf(host.sim.settlements[k].x - host.sim.settlements[sid].x) < absf(host.sim.settlements[nb].x - host.sim.settlements[sid].x):
				nb = k
	if mode == "caravan" and nb >= 0:
		pid = life.cheat_party("caravan", sid, nb, 0.3)
	if mode == "raid" and nb >= 0:
		for k: int in WorldSim._sorted_keys(host.sim.settlements):   # another faction's raiders
			if host.sim.settlements[k].faction != host.sim.settlements[sid].faction \
					and not host.sim.path_between(k, sid, WorldSim.ROAD | WorldSim.DEEP | WorldSim.LINK).is_empty():
				nb = k
				break
		pid = life.cheat_party("raid", nb, sid, 0.97, 8)
	for i in int(o.get("ticks", "600")):
		if pid > 0 and mode in ["caravan", "crossing"] and host.sim.parties.has(pid):
			var pp := life.road.ground(host, life.road.party_pos(host, host.sim.parties[pid]))
			if pp != Vector2.INF:
				p.body.pos = pp + Vector2(-8, 0)
				focus = pp
		host.tick()
		host.outbox.clear()
	if mode == "raid":
		for e: HostEntity in life.actors_of(pid):
			focus = e.body.pos
			break
	if o.get("focus", "") == "guard":
		for e: HostEntity in life.actors_at(sid):
			if e.get_meta("sim")["role"] == "guard":
				focus = e.body.pos
				break
	focus += Vector2(float(o.get("dx", 0)), float(o.get("dy", 4)))
	# the view
	var light := LightEngine.new(w)
	light.sun = WorldClock.sun_at(host.clock.hours())
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.background_color = WorldView.sky_color(light.sun)
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var view := WorldView.new()
	root.add_child(view)
	view.setup(w, light)
	var rig := CameraRig.new()
	root.add_child(rig)
	rig.zoom = float(o.get("zoom", 1.0))
	rig.target = focus
	rig.snap()
	var shown := 0
	for e: HostEntity in host.entities.values():
		if e.body.pos.distance_to(focus) > 70.0:
			continue
		var look := e.look.duplicate()
		if e.is_player():
			look = {"player": "fighter", "name": e.name}
		view.add_actor(e.id, look)
		view.move_actor(e.id, e.body.pos, e.body.facing, "idle")
		if e.has_meta("torch") and light.sun < 0.5:
			light.add_light((1 << 24) + e.id, e.body.pos.x + 0.6 * e.body.facing, e.body.pos.y + 1.8, LightEngine.TORCH)
		shown += 1
	if st.size() >= 3:
		for e: HostEntity in life.actors_at(sid):
			if e.body.pos.y > float(st[2]) + 3.0:
				var b: Variant = e.brain
				print("life_shot: high %s %s at %s post %s safe %s" % [e.name, e.get_meta("sim"), e.body.pos,
					b.post if b is LifeBrain else "-", b.safe if b is LifeBrain else "-"])
	var dv := DressingView.new()
	root.add_child(dv)
	var recs: Array = []
	for cy in range(maxi(0, int(focus.y - 50) >> 5), mini(w.chunks_y - 1, int(focus.y + 50) >> 5) + 1):
		for cx in range(maxi(0, int(focus.x - 80) >> 5), mini(w.chunks_x - 1, int(focus.x + 80) >> 5) + 1):
			for r: Dictionary in Dressing.records_in(w, cx, cy):
				recs.append({"id": Dressing.name_of(r["id"]), "x": r["x"], "y": r["y"], "v": r["v"]})
	dv.set_objects(recs)
	var frames := 0
	while frames < 900:
		view.view_half = rig.visible_half_extent()
		view.set_focus(rig.pos)
		await process_frame
		frames += 1
		if frames > 5 and view.is_idle():
			break
	for i in 3:
		await RenderingServer.frame_post_draw
	var out := String(o.get("out", "/tmp/life_shot.png"))
	root.get_texture().get_image().save_png(out)
	print("life_shot: %s %s at %s, %s, %d actors drawn, life %s -> %s" % [mode, host.sim.settlements[sid].name, focus,
		WorldClock.describe(host.clock.hours()), shown, life.summary(), out])
	quit()

## A caravan on the first road with this crossing, `along` of the way over it (a cheat), and raiders
## ahead of it if asked (another). Returns the caravan's party id, or -1.
static func _crossing(host: WorldHost, life: LifeSystem, kind: String, along: float, raid: bool) -> int:
	var sim := host.sim
	var bar: Dictionary = host.world.meta["barriers"]
	for r: Dictionary in sim.routes:
		if String(r.get("kind", "")) != "road" or not kind in r.get("crossings", []) \
				or not sim.settlements.has(int(r.a)) or not sim.settlements.has(int(r.b)):
			continue
		var cells: Array = []
		for row: Dictionary in bar["ranges"]:
			if kind == "pass":
				cells.append_array(row["pass"]["path"])
		for row: Dictionary in bar["rivers"]:
			if String(row["crossing"]["kind"]) == kind:
				cells.append_array(row["crossing"]["cells"])
		var on := {}
		for q: Array in cells:
			on[Vector2i(int(q[0]), int(q[1]))] = true
		var path := Places.route_path(host.world, int(r.id))
		var hit: Array = []
		for i in path.size():
			if on.has(path[i]):
				hit.append(i)
		if hit.is_empty():
			continue
		var f := float(hit[int((hit.size() - 1) * along)]) / path.size()
		var pid := life.cheat_party("caravan", int(r.a), int(r.b), f)
		if pid > 0 and raid:
			var home := -1
			for k: int in WorldSim._sorted_keys(sim.settlements):
				var s: SimSettlement = sim.settlements[k]
				if k != int(r.a) and k != int(r.b) and (home < 0 or s.faction != sim.settlements[int(r.a)].faction):
					home = k
			var s: SimSettlement = sim.settlements[home]
			var ra := sim.new_party("raid", s.faction, s.culture, home, SimData.allocate(SimData.culture(s.culture).raiders, 5))
			ra.plan = {"mode": "route", "motive": "plunder", "leg": "out"}
			ra.target = int(r.id)
			ra.path = [int(r.a), int(r.b)] as Array[int]
			ra.leg = 0
			ra.route = int(r.id)
			ra.frac = f + 24.0 / path.size()
			ra.state = "ambush"
			ra.timer = 24.0
			ra.dest = int(r.b)
			s.out_raids += 1
		return pid
	return -1
