## The look below (docs/tracks/look-below.md): which dressing grows in which region, primitives for
## a world with no art, the tint and fog maps, glowing props in the picture's light only, and the
## rule that hides what combat marks Invisible.
extends RefCounted

const Rig := preload("res://tests/net_rig.gd")
const FUNGAL_Y := 40

func run(t: TestLog) -> void:
	_rows(t)
	_matches(t)
	_scatter(t)
	_drow(t)
	_worlds_unmoved(t)
	_tint(t)
	_fog(t)
	_props(t)
	_unseen_rule(t)
	_unseen_body(t)
	_unseen_on_the_wire(t)
	_presenter(t)

## A test world: stone with an open hall, its left half a fungal region floored in mycelium, its
## right half crystal, one drow house at the far right.
static func hall() -> TileWorld:
	var w := TileWorld.make_test(256, 96)
	var stone := TileDefs.id("stone")
	var mycelium := TileDefs.id("mycelium")
	var geode := TileDefs.id("geode_floor")
	for x in 256:
		for y in 96:
			var air := y >= FUNGAL_Y and y < FUNGAL_Y + 26
			w.set_fg(x, y, TileDefs.AIR if air else stone, true)
		w.set_fg(x, FUNGAL_Y - 1, mycelium if x < 128 else geode, true)
	w.meta["biomes"] = [
		{"biome": "fungal", "band": "deeps", "x0": 0, "x1": 127, "y0": 0, "y1": 95, "name": "the Test Groves"},
		{"biome": "crystal", "band": "deeps", "x0": 128, "x1": 255, "y0": 0, "y1": 95, "name": "the Test Vaults"}]
	return w

func _rows(t: TestLog) -> void:
	var rows := RegionDressing.rows()
	t.check(rows.size() >= 25, "the regions have their own rows (%d)" % rows.size())
	var seen := {}
	var bad := []
	for r: Dictionary in rows:
		var d: Dictionary = r["def"]
		for b: String in d["where"].get("biomes", []):
			seen[b] = true
			if BelowLook.row(b).is_empty():
				bad.append("%s: region %s has no look" % [r["id"], b])
		for n: String in d["where"].get("on", []):
			if TileDefs.id(n) < 0:
				bad.append("%s: no tile %s" % [r["id"], n])
		var m := PrimMesh.build(d.get("prim"))
		if m.is_empty() or float(m["top"]) <= 0.0:
			bad.append("%s: no primitive to draw" % r["id"])
		if Dressing.id(r["id"]) < 0:
			bad.append("%s: no id" % r["id"])
	t.eq(bad, [], "every below row names real regions and tiles and draws with no art")
	for b: String in ["fungal", "crystal", "deep_lake", "magma", "underdark"]:
		t.check(seen.has(b), "%s has dressing" % b)
	# what stood invisible with no art now stands: the drow kit, the cave rows
	var kits: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/places/kits.json"))["kits"]
	var missing := []
	for role: String in ["bed", "well", "statue", "post_shrine", "throne", "table", "chair", "barrel", "counter"]:
		var id := String(kits["drow"].get(role, kits["human"].get(role, "")))
		if PrimMesh.build(DressingView.defs().get(id, {}).get("prim")).is_empty():
			missing.append("%s: %s" % [role, id])
	t.eq(missing, [], "a drow city's pieces have primitives")
	var parts := DressingView.parts_of(DressingView.defs()["shroom_tall"])
	t.check(not parts.is_empty() and (parts["parts"] as Array).size() >= 1, "a row with no model draws its primitive")
	t.eq(DressingView.parts_of({"footprint": [1, 1]}), {}, "a row with neither draws nothing")

func _matches(t: TestLog) -> void:
	var defs := DressingView.defs()
	t.check(RegionDressing.matches(defs["shroom_tall"], "fungal", "mycelium"), "a mushroom on a fungal floor")
	t.check(not RegionDressing.matches(defs["shroom_tall"], "crystal", "mycelium"), "not in the crystal")
	t.check(not RegionDressing.matches(defs["shroom_tall"], "fungal", "slate"), "nor on bare slate")
	t.check(RegionDressing.matches(defs["basalt_spire"], "magma", "ash"), "a spire in the magma")
	t.check(RegionDressing.matches(defs["moss_curtain"], "deep_lake", "lake_stone"), "moss over the lake")
	t.check(not RegionDressing.matches(defs["moss_curtain"], "fungal", "lake_stone"), "only over the lake")
	t.check(RegionDressing.matches(defs["drow_spire"], "fungal", "dark_stone") and RegionDressing.matches(defs["drow_spire"], "magma", "dark_stone"),
		"a drow spire stands wherever a city does")
	t.check(not RegionDressing.backed(defs["drow_spire"], "dark_wall"), "not in a room")
	t.check(RegionDressing.backed(defs["drow_spire"], ""), "on a roof")
	t.check(RegionDressing.backed(defs["drow_globe"], "dark_wall") and not RegionDressing.backed(defs["drow_globe"], ""), "a hung globe is indoors")
	t.check(RegionDressing.on_gap(7, 1), "no gap: every column")
	var hits := 0
	for x in range(0, 900):
		hits += 1 if RegionDressing.on_gap(x, 9) else 0
	t.eq(hits, 100, "a gap of 9 is one column in 9")
	t.eq(RegionDressing.chance(defs["shroom_tall"], "fungal", false), RegionDressing.density("fungal"), "a cell tries at the region's density")
	t.check(RegionDressing.chance(defs["shard_hang"], "crystal", true) < RegionDressing.density("crystal"), "a ceiling less")
	t.eq(RegionDressing.chance(defs["drow_spire"], "underdark", false), 1.0, "a row's own chance beats it")

func _scatter(t: TestLog) -> void:
	var w := hall()
	var rd := RegionDressing.new(w)
	var cy := FUNGAL_Y >> 5
	var recs: Array = []
	for cx in w.chunks_x:
		recs.append_array(rd.records_in(cx, cy))
		recs.append_array(rd.records_in(cx, (FUNGAL_Y + 25) >> 5))
	t.check(recs.size() > 80, "the hall is dressed (%d)" % recs.size())
	var bad := 0
	var by := {"fungal": {}, "crystal": {}}
	for r: Dictionary in recs:
		var d: Dictionary = DressingView.defs()[r["id"]]
		var fp: Array = d["footprint"]
		var biome := "fungal" if int(r["x"]) < 128 else "crystal"
		by[biome][r["id"]] = true
		var ceiling := String(d["anchor"]) == "ceiling"
		var sup := int(r["y"]) + int(fp[1]) if ceiling else int(r["y"]) - 1
		if not w.is_solid(r["x"], sup) or not biome in d["where"]["biomes"]:
			bad += 1
		for dy in int(fp[1]):
			if w.is_solid(r["x"], int(r["y"]) + dy):
				bad += 1
	t.eq(bad, 0, "everything stands on what holds it, clear of the rock, in its own region")
	t.check(by["fungal"].has("shroom_tall") or by["fungal"].has("shroom_giant"), "a forest's tall mushrooms (%s)" % [by["fungal"].keys()])
	t.check(not (by["fungal"] as Dictionary).has("shard_tall"), "no crystal among them")
	t.check((by["crystal"] as Dictionary).has("shard_tall") or (by["crystal"] as Dictionary).has("shard_giant"), "crystal has its shards")
	# deterministic, and it follows the tiles
	var again := RegionDressing.new(hall())
	var a: Array = rd.records_in(1, cy).duplicate()
	t.eq(again.records_in(1, cy), a, "the same tiles give the same dressing")
	t.check(not a.is_empty(), "(a chunk with some)")
	var r0: Dictionary = a[0]
	for r: Dictionary in a:
		if String(DressingView.defs()[r["id"]]["anchor"]) == "ground":
			r0 = r
			break
	w.set_fg(r0["x"], int(r0["y"]) - 1, TileDefs.AIR, true)
	t.check(w.get_fg(r0["x"], int(r0["y"]) - 1) == TileDefs.AIR, "(the floor dug)")
	w.tile_changed.emit(r0["x"], int(r0["y"]) - 1, TileWorld.Layer.FG, 0, 0)
	var left: Array = rd.records_in(1, cy)
	t.check(not r0 in left, "dig out the floor and the mushroom goes")
	# above the regions there is nothing to scan
	var w2 := hall()
	for s: Dictionary in w2.meta["biomes"]:
		s["y1"] = 10
	w2.meta["bands"] = {"caves": [0, 20]}
	var rd2 := RegionDressing.new(w2)
	t.eq(rd2.records_in(1, 3), [], "over the regions and the caves: nothing")

func _drow(t: TestLog) -> void:
	var w := hall()
	var dark := TileDefs.id("dark_stone")
	for x in range(40, 70):
		for y in range(FUNGAL_Y, FUNGAL_Y + 8):
			var shell := y == FUNGAL_Y + 7 or y == FUNGAL_Y or x == 40 or x == 69
			w.set_fg(x, y, dark if shell else TileDefs.AIR, true)
			if not shell:
				w.set_bg(x, y, TileDefs.wall_id("dark_wall"), true)
	var rd := RegionDressing.new(w)
	var recs: Array = []
	for cx in range(0, 4):
		for cy in range(0, 3):
			recs.append_array(rd.records_in(cx, cy))
	var spire := 0
	var inside := 0
	var out := 0
	for r: Dictionary in recs:
		var id := String(r["id"])
		if id == "drow_spire":
			spire += 1
		if id in ["drow_spire", "drow_finial"] and w.get_bg(r["x"], r["y"]) == TileDefs.wall_id("dark_wall"):
			out += 1
		if id in ["drow_globe", "drow_banner"]:
			inside += 1
	t.check(spire > 0, "spires on a drow roof (%d)" % spire)
	t.eq(out, 0, "none of them in a room")
	t.check(inside > 0, "hung globes and banners in the room (%d)" % inside)

## The below rows live in the view: a generated world has none in its records, and its deep
## cities are dressed from their tiles.
func _worlds_unmoved(t: TestLog) -> void:
	var world := WorldGen.generate_named("dev", 4)
	var below := 0
	var regions := 0
	for cy in world.chunks_y:
		for cx in world.chunks_x:
			for r: Dictionary in Dressing.records_in(world, cx, cy):
				var d := Dressing.def(r["id"])
				below += 1 if String(d.get("where", {}).get("band", "")) == "below" else 0
	var rd := RegionDressing.new(world)
	var kinds := {}
	for cy in world.chunks_y:
		for cx in world.chunks_x:
			for r: Dictionary in rd.records_in(cx, cy):
				kinds[r["id"]] = int(kinds.get(r["id"], 0)) + 1
				regions += 1
	t.eq(below, 0, "worldgen placed no below row")
	t.check(regions > 200, "the scatter dresses a generated world (%d)" % regions)
	t.check(kinds.has("drow_spire"), "its drow city has spires (%s)" % [kinds.keys()])

func _tint(t: TestLog) -> void:
	var rect := Rect2i(0, 0, 64, 64)
	var cap := {"x": 20, "y": 20, "color": Color(0.2, 1.0, 0.7), "tint": true, "level": 0.6, "reach": 12.0}
	var torch := {"x": 50, "y": 50, "color": Color(1.0, 0.6, 0.3), "tint": false, "level": 1.0, "reach": 15.0}
	var b := BelowLook.tint_bytes([torch], rect, 4)
	t.eq(b.count(0), b.size(), "torches alone: the map stays clear, the surface is as it was")
	b = BelowLook.tint_bytes([cap], rect, 4)
	var at := func(x: int, y: int) -> Color:
		var i := (x / 4 + y / 4 * 16) * 4
		return Color(b[i] / 255.0, b[i + 1] / 255.0, b[i + 2] / 255.0, b[i + 3] / 255.0)
	var near: Color = at.call(20, 20)
	t.check(near.a > 0.3, "a cap tints the cell it is in (%.2f)" % near.a)
	t.check(near.g > near.r * 2.0, "in its own colour (%s)" % near)
	t.eq((at.call(60, 60) as Color).a, 0.0, "not past its reach")
	var mixed := BelowLook.tint_bytes([cap, torch], rect, 4)
	t.check(mixed[(50 / 4 + 50 / 4 * 16) * 4] > mixed[(50 / 4 + 50 / 4 * 16) * 4 + 2], "among tinted lights a torch keeps its own warmth")
	var pool: Array = []
	for x in range(10, 50):
		for y in range(10, 14):
			pool.append({"x": x, "y": y, "color": Color(1.0, 0.3, 0.1), "tint": true, "level": 1.0, "reach": 12.0})
	var us := Time.get_ticks_usec()
	BelowLook.tint_bytes(pool, rect, 4)
	t.check(Time.get_ticks_usec() - us < 40000, "a lava pool's 160 tiles cost little (%d us)" % (Time.get_ticks_usec() - us))
	t.eq(BelowLook.tile_light("glow_cap")["tint"], true, "glow caps tint")
	t.eq(BelowLook.tile_light("lamp")["tint"], false, "a town's lamp does not")
	for n: String in ["glow_cap", "crystal_cluster", "lumen_moss", "lava", "fae_lamp"]:
		t.check(TileDefs.id(n) >= 0 and bool(BelowLook.tile_light(n)["tint"]), "%s has its colour" % n)

func _fog(t: TestLog) -> void:
	var meta := {"biomes": [
		{"biome": "meadow", "x0": 0, "x1": 200},
		{"biome": "fungal", "band": "deeps", "x0": 0, "x1": 99, "y0": 0, "y1": 99},
		{"biome": "magma", "band": "deeps", "x0": 100, "x1": 200, "y0": 0, "y1": 99}]}
	var rect := Rect2i(0, 0, 200, 160)
	var b := BelowLook.fog_bytes(meta, rect, 8)
	var at := func(x: int, y: int) -> Color:
		var i := (x / 8 + y / 8 * 25) * 4
		return Color(b[i] / 255.0, b[i + 1] / 255.0, b[i + 2] / 255.0, b[i + 3] / 255.0)
	var f: Color = at.call(40, 40)
	var m: Color = at.call(140, 40)
	t.check(f.a > 0.3 and m.a > 0.3, "the regions have fog")
	t.check(f.b > f.r, "the fungal fog is violet (%s)" % f)
	t.check(m.r > m.b * 3.0, "the magma's red (%s)" % m)
	t.eq((at.call(40, 140) as Color).a, 0.0, "the surface has none")
	t.check(BiomeIds.regions({"biomes": [{"biome": "meadow", "x0": 0, "x1": 9}]}).is_empty(), "(a world with no regions)")
	var clear := BelowLook.fog_bytes({"biomes": [{"biome": "meadow", "x0": 0, "x1": 9}]}, rect, 8)
	t.eq(clear.count(0), clear.size(), "and no fog at all")
	t.check(float(BelowLook.row("underdark").get("ambient", 1.0)) == 0.0, "the plain underdark keeps its dark")

func _props(t: TestLog) -> void:
	var w := hall()
	var light := LightEngine.new(w)
	var view := WorldView.new()
	view.setup(w, light)
	view.view_half = Vector2(30, 20)
	view.set_focus(Vector2(60, FUNGAL_Y + 5))
	view._refill_light()
	var dv := DressingView.new()
	view.add_child(dv)
	dv.set_objects([{"id": "shroom_tall", "x": 60, "y": FUNGAL_Y}, {"id": "shroom_mid", "x": 70, "y": FUNGAL_Y}, {"id": "puffballs", "x": 74, "y": FUNGAL_Y}])
	t.eq(view.below.props.size(), 2, "the glowing rows are lights, the puffballs are not")
	t.eq(int(dv.counts.get("shroom_tall", 0)), 1, "a primitive row is drawn with no art")
	t.check(light.level_at(60, FUNGAL_Y + 5) == 0, "(dark, before)")
	for i in 4:
		view.below._process(1.0 / 30.0)
	t.check(view.below.props_settled(), "the field takes them, a few a frame")
	t.check(light.block_at(60, FUNGAL_Y + 5) > 20, "a tall mushroom lights the picture's field (%d)" % light.block_at(60, FUNGAL_Y + 5))
	t.eq(view.below.lit_props().size(), 2, "and they are lamps too")
	t.check(view.lights.candidates().size() >= 2, "for WorldLights")
	var other := LightEngine.new(w)
	t.eq(other.block_at(60, FUNGAL_Y + 5), 0, "no other engine sees them: the host's rules never do")
	dv.set_objects([])
	for i in 4:
		view.below._process(1.0 / 30.0)
	t.eq(light.block_at(60, FUNGAL_Y + 5), 0, "gone with their records")
	view.free()

func _unseen_rule(t: TestLog) -> void:
	var S := UnseenRule.Show
	t.eq(UnseenRule.show(false, false, false, false), S.SEEN, "a creature in plain sight")
	t.eq(UnseenRule.show(true, false, false, false), S.GONE, "an Invisible creature is gone")
	t.eq(UnseenRule.show(true, true, true, false), S.FAINT, "you keep sight of yourself")
	t.eq(UnseenRule.show(true, false, true, false), S.FAINT, "and of the party")
	t.eq(UnseenRule.show(true, false, false, true), S.FAINT, "See Invisibility shows it, faintly")
	t.check(UnseenRule.sees_invisible(["bless", "concentration:see-invisibility"]), "by its effect id")
	t.check(not UnseenRule.sees_invisible(["bless"]), "not by another's")

func _unseen_body(t: TestLog) -> void:
	var body := ActorBody.build({"slug": "roper", "kind": "monster", "size": Vector2(2, 3)}, ShaderMaterial.new())
	body.set_shown(UnseenRule.Show.GONE)
	t.check(not body.visible, "gone: the body and all under it")
	body.set_shown(UnseenRule.Show.SEEN)
	t.check(body.visible, "back in sight when it springs")
	body.set_shown(UnseenRule.Show.FAINT)
	var faint := true
	for g: GeometryInstance3D in body._surfaces():
		faint = faint and g.transparency > 0.0
	t.check(body.visible and faint, "faint: seen through")
	body.set_shown(UnseenRule.Show.SEEN)
	var clear := true
	for g: GeometryInstance3D in body._surfaces():
		clear = clear and g.transparency == 0.0
	t.check(clear, "and solid again")
	body.free()

## A client that comes into sight of a creature already Invisible hears so with ENT_ADD; one
## watching hears the change.
func _unseen_on_the_wire(t: TestLog) -> void:
	var world := hall()
	var r := Rig.new(world)
	var combat := CombatSystem.new()
	r.host.add_system(combat)
	var e := r.host.add_srd_monster("roper", Vector2(230, FUNGAL_Y))
	combat.set_hidden(e, true)
	for i in 3:
		r.host.tick()
	t.check(e.combatant.conditions.has(SRD.Condition.INVISIBLE), "(hidden before anyone is near)")
	var cc := CombatClient.new()
	var heard := {}
	cc.event.connect(_heard.bind(heard))
	var c := r.add_client("late")
	c.welcomed.connect(func(cw: ClientWorld) -> void: cw.add_system(cc))
	t.check(r.until(func() -> bool: return c.cw != null and r.host_entity(0) != null, 4.0) >= 0.0, "(joined)")
	r.run(0.5)
	t.check(not r.cw(0).remotes.has(e.id), "(out of its sight)")
	r.host.teleport(r.host_entity(0), Vector2(220, FUNGAL_Y))
	t.check(r.until(func() -> bool: return r.cw(0).remotes.has(e.id), 4.0) >= 0.0, "it comes into the client's interest")
	r.run(0.3)
	t.eq(heard.get(e.id, false), true, "and the client hears it is Invisible, though it went so long ago")
	combat.set_hidden(e, false)
	r.run(0.5)
	t.eq(heard.get(e.id, true), false, "and when it is seen again")

func _heard(ev: Dictionary, into: Dictionary) -> void:
	if int(ev.get("kind", 0)) == CombatCodec.Ev.CONDITION and int(ev.get("cond", -1)) == SRD.Condition.INVISIBLE:
		into[int(ev["dst"])] = bool(ev["on"])

func _presenter(t: TestLog) -> void:
	var world := hall()
	var r := Rig.new(world)
	var c := r.add_client("watcher")
	t.check(r.until(func() -> bool: return r.cw(0) != null and r.host_entity(0) != null, 4.0) >= 0.0, "(joined)")
	var p := ViewPresenter.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(p)
	p.attach(r.cw(0))
	p.actor_added(7, {"kind": "monster", "size": Vector2(2, 3), "name": "roper", "slug": "roper"})
	var ev := {"kind": CombatCodec.Ev.CONDITION, "src": 0, "dst": 7, "cond": SRD.Condition.INVISIBLE, "on": true}
	p.combat_event(ev)
	t.check(not p.view.get_actor(7).visible, "a CONDITION hides the body")
	t.check(p.fx.unseen.has(7), "and takes its plate and target ring")
	p.actor_added(7, {"kind": "monster", "size": Vector2(2, 3), "name": "roper", "slug": "roper"})
	t.check(not p.view.get_actor(7).visible, "a rebuilt body stays hidden")
	var off := ev.duplicate()
	off["on"] = false
	p.combat_event(off)
	t.check(p.view.get_actor(7).visible, "seen again when it springs")
	t.check(not p.fx.unseen.has(7), "with its plate")
	p.combat_event(ev)
	p.combat_event({"kind": CombatCodec.Ev.EFFECT, "src": 0, "dst": r.cw(0).my_id, "on": true, "what": "see-invisibility"})
	t.check(p.view.get_actor(7).visible, "See Invisibility shows it")
	p.actor_removed(7)
	t.check(not p._invisible.has(7), "a body gone forgets it")
	p.combat_event({"kind": CombatCodec.Ev.CONDITION, "src": 0, "dst": r.cw(0).my_id, "cond": SRD.Condition.INVISIBLE, "on": true})
	t.check(p.view.get_actor(r.cw(0).my_id).visible, "the own body stays drawn")
	p.detach()
	p.free()
	c = null
