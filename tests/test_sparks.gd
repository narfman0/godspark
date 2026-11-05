## Sparks: the constellation's rules, THE RULE (no spark changes an attack roll, AC, save DC
## or damage die), movement unchanged without sparks and changed with them.
extends RefCounted

func run(t: TestLog) -> void:
	_constellation(t)
	_the_rule(t)
	_no_spark_identical(t)
	_with_sparks(t)
	_host_accepts_sparked_moves(t)

func _constellation(t: TestLog) -> void:
	t.eq(LevelTrack.spark_slots(1), 1, "level 1: one spark slot")
	t.eq(LevelTrack.spark_slots(3), 2, "level 3: two")
	t.eq(LevelTrack.spark_slots(100), 40, "level 100: forty")
	var c := Constellation.new()
	c.salt = "ann"
	c.slots = 2
	t.check(c.kindle({"id": "fleet", "rank": 0}), "kindle into a free slot")
	t.eq(c.kindle_refusal({"id": "fleet", "rank": 2}), "duplicate", "the same spark twice is refused")
	t.check(c.kindle({"id": "spring", "rank": 1}), "a second spark")
	t.eq(c.kindle_refusal({"id": "otter", "rank": 0}), "full", "no third with two slots")
	t.eq(c.kindle_refusal({"id": "nonsense", "rank": 0}), "unknown", "unknown spark refused")
	var at0: Array = c.kindled[0]["at"]
	var old := c.swap(0, {"id": "fleet", "rank": 2})
	t.eq(old, {"id": "fleet", "rank": 0}, "swap returns the old spark")
	t.eq(c.kindled[0]["rank"], 2, "and the new rank is kindled")
	t.eq(c.kindled[0]["at"], at0, "the star keeps its place")
	t.eq(c.swap_refusal(1, {"id": "fleet", "rank": 0}), "duplicate", "swap cannot duplicate another star")
	var s := c.sigil()
	t.eq((s["stars"] as Array).size(), 2, "sigil: a star per spark")
	t.eq(s["lines"], [[0, 1]], "joined in kindling order")
	t.check(s["stars"][0] != s["stars"][1], "stars on distinct spots")
	var back := Constellation.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	t.eq(back.to_dict(), c.to_dict(), "constellation round trip through JSON")

## Every spark, every rank, on a fighter (melee) and a wizard (spells): the combatant's
## numbers are the same as with nothing kindled.
func _the_rule(t: TestLog) -> void:
	var host := WorldHost.new(TileWorld.make_test())
	var sys := ItemsSystem.new()
	host.add_system(sys)
	var changed := 0
	var checked := 0
	var tag_bad := 0
	for cls: String in ["fighter", "wizard"]:
		var e := host.add_player("rule_" + cls, 1, {"class": cls})
		e.character.level = 30
		e.character.sparks.slots = 40
		sys.refresh(e)
		var base := _numbers(e.combatant)
		for id: String in Sparks.ids():
			for rank in Sparks.RANKS:
				e.character.sparks.kindled.clear()
				e.character.sparks.kindle({"id": id, "rank": rank})
				sys.refresh(e)
				checked += 1
				if _numbers(e.combatant) != base:
					changed += 1
					print("  spark %s %d changed %s -> %s" % [id, rank, base, _numbers(e.combatant)])
				var out := {}
				Sparks.apply(e.character.sparks.list(), MoveStats.player(), out)
				for k: String in out:
					if k in ["attack", "ac", "save", "spell_dc", "spell_attack", "damage", "dice"]:
						tag_bad += 1
		# all of them at once, too
		e.character.sparks.kindled.clear()
		for id: String in Sparks.ids():
			e.character.sparks.kindle({"id": id, "rank": 2})
		sys.refresh(e)
		t.eq(_numbers(e.combatant), base, "%s: every spark at rank III kindled at once changes nothing" % cls)
	t.eq(changed, 0, "THE RULE: %d spark-ranks change no attack bonus, AC, save, DC or damage die" % checked)
	t.eq(tag_bad, 0, "no spark writes a combat tag")

func _numbers(c: Combatant) -> Array:
	var saves: Array = []
	for i in 6:
		saves.append(c.stats.saving_throw_bonus(i as SRD.Ability))
	var w := c.weapon
	return [c.attack_modifier(), c.armor_class, saves, c.kit.spell_save_dc(c) if c.kit != null else -1,
			c.stats.spell_attack_mod, c.stats.spell_dc_bonus,
			[w.die_count, w.die_sides, w.damage_type] if w != null else [], c.bonus_damage, c.hit_riders.duplicate(true)]

func _props(s: MoveStats) -> Dictionary:
	var out := {}
	for p: Dictionary in s.get_property_list():
		if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out[p["name"]] = s.get(p["name"])
	return out

func _no_spark_identical(t: TestLog) -> void:
	var a := MoveStats.player()
	var b := Sparks.move_stats({"walk": 30}, "medium", [])
	t.eq(_props(b), _props(a), "no sparks: MoveStats identical to MoveStats.player()")
	t.eq(a.air_jumps + int(a.dash_speed) + int(a.glide_fall), 0, "spark abilities default off")
	# A long scripted run with jumps, platforms and dashes-that-are-not: bit-identical bodies.
	var w1 := TileWorld.make_test()
	var w2 := TileWorld.make_test()
	var b1 := a.make_body()
	var b2 := b.make_body()
	b1.pos = Vector2(100.5, 64)
	b2.pos = b1.pos
	var same := true
	for i in 600:
		var p := PlayerInput.new()
		p.move_x = [1.0, 0.0, -1.0, 1.0, 0.0][(i / 7) % 5]
		p.jump = (i % 50) < 20
		p.jump_pressed = (i % 50) == 0 or (i % 50) == 10
		p.dash = (i % 90) == 3
		PlayerController.step(w1, b1, p, a, 1.0 / 60.0)
		PlayerController.step(w2, b2, p, b, 1.0 / 60.0)
		same = same and b1.pos == b2.pos and b1.vel == b2.vel
	t.check(same, "no sparks: taps, double jumps and dash presses move exactly as before")

func _run(stats: MoveStats, script: Callable, steps := 240, start := Vector2(87.5, 64), world: TileWorld = null) -> Dictionary:
	var w := world if world != null else TileWorld.make_test()
	var body := stats.make_body()
	body.pos = start
	var peak := start.y
	var low_vy := 0.0
	for i in steps:
		var p := PlayerInput.new()
		script.call(i, p)
		PlayerController.step(w, body, p, stats, 1.0 / 60.0)
		peak = maxf(peak, body.pos.y)
		low_vy = minf(low_vy, body.vel.y)
	return {"pos": body.pos, "peak": peak - start.y, "low_vy": low_vy, "body": body}

func _with_sparks(t: TestLog) -> void:
	var plain := MoveStats.player()
	var fleet := Sparks.move_stats({"walk": 30}, "medium", [{"id": "fleet", "rank": 2}])
	t.check(is_equal_approx(fleet.run_speed, plain.run_speed * 1.3), "Fleet III: run speed x1.3")
	var hop := func(i: int, p: PlayerInput) -> void:
		p.jump = i >= 2 and i < 80
		p.jump_pressed = i == 2
	var spring := Sparks.move_stats({"walk": 30}, "medium", [{"id": "spring", "rank": 2}])
	var h0 := float(_run(plain, hop)["peak"])
	var h1 := float(_run(spring, hop)["peak"])
	t.check(absf(h1 - h0 - 3.0) < 0.35, "Spring III: about 3 tiles higher (%.2f vs %.2f)" % [h1, h0])
	var sky := Sparks.move_stats({"walk": 30}, "medium", [{"id": "skyhook", "rank": 2}])
	var triple := func(i: int, p: PlayerInput) -> void:
		p.jump = (i >= 2 and i < 26) or (i >= 26 and i < 50) or (i >= 50 and i < 80)
		p.jump_pressed = i == 2 or i == 26 or i == 50 or i == 74
	var ps := float(_run(plain, triple)["peak"])
	var ss := float(_run(sky, triple)["peak"])
	t.check(ss > ps + 6.0, "Skyhook III: two air jumps climb far higher (%.2f vs %.2f)" % [ss, ps])
	var sky1 := Sparks.move_stats({"walk": 30}, "medium", [{"id": "skyhook", "rank": 0}])
	var s1 := float(_run(sky1, triple)["peak"])
	t.check(s1 > ps + 2.0 and s1 < ss - 2.0, "Skyhook I: one air jump (%.2f)" % s1)
	var dash := Sparks.move_stats({"walk": 30}, "medium", [{"id": "dash", "rank": 1}])
	var tap2 := func(i: int, p: PlayerInput) -> void:
		p.move_x = 1.0 if (i < 3 or (i >= 8 and i < 40)) else 0.0
	var dx0 := float(_run(plain, tap2, 60)["pos"].x)
	var dx1 := float(_run(dash, tap2, 60)["pos"].x)
	t.check(dx1 - dx0 > 2.0, "Dash: a double tap darts ahead (%.2f tiles further)" % (dx1 - dx0))
	var slow_tap := func(i: int, p: PlayerInput) -> void:
		p.move_x = 1.0 if (i < 3 or (i >= 30 and i < 40)) else 0.0
	t.eq(_run(dash, slow_tap, 60)["pos"], _run(plain, slow_tap, 60)["pos"], "Dash: taps further apart than the window do nothing")
	var press := func(i: int, p: PlayerInput) -> void:
		p.dash = i == 5 or i == 10
	var pr: Body = _run(dash, press, 30)["body"]
	t.check(pr.pos.x > 87.5 + 3.0, "Dash: PlayerInput.dash triggers it facing right")
	t.check(pr.dash_cd > 0.0, "and the cooldown is running (second press ignored)")
	# Featherfall: walk off a high ledge holding jump.
	var w := TileWorld.make_test()
	for x in range(80, 101):
		for y in range(64, 84):
			w.set_fg(x, y, TileDefs.id("stone"), true)
	var off := func(i: int, p: PlayerInput) -> void:
		p.move_x = 1.0 if i < 20 else 0.0
		p.jump = true
	var glide := Sparks.move_stats({"walk": 30}, "medium", [{"id": "featherfall", "rank": 2}])
	var g0 := _run(plain, off, 70, Vector2(99.0, 84), w)
	var w2 := TileWorld.make_test()
	for x in range(80, 101):
		for y in range(64, 84):
			w2.set_fg(x, y, TileDefs.id("stone"), true)
	var g1 := _run(glide, off, 70, Vector2(99.0, 84), w2)
	t.check(float(g1["low_vy"]) >= -4.0 - 1e-3 and float(g0["low_vy"]) < -10.0,
			"Featherfall III: holding jump falls at most 4 t/s (%.2f vs %.2f)" % [g1["low_vy"], g0["low_vy"]])
	var gecko := Sparks.move_stats({"walk": 30}, "medium", [{"id": "gecko", "rank": 1}])
	t.eq(gecko.climb_speed, 5.0, "Gecko II: climbs walls at 5 t/s")
	var w3 := TileWorld.make_test()
	for y in range(64, 80):
		w3.set_fg(103, y, TileDefs.id("stone"), true)
	var climb := func(i: int, p: PlayerInput) -> void:
		p.move_x = 1.0
		p.up = true
	t.check(float(_run(gecko, climb, 120, Vector2(100.5, 64), w3)["peak"]) > 5.0, "Gecko: up a wall")
	t.check(float(_run(plain, climb, 120, Vector2(100.5, 64), w3)["peak"]) < 1.0, "without Gecko: not")
	var otter := Sparks.move_stats({"walk": 30}, "medium", [{"id": "otter", "rank": 2}])
	t.check(is_equal_approx(otter.swim_speed, plain.swim_speed * 1.8), "Otter III: swim x1.8")
	var tg := Sparks.tags([{"id": "magnet", "rank": 1}, {"id": "mole", "rank": 0}, {"id": "lantern", "rank": 2}])
	t.eq(tg, {"pickup_radius": 4.0, "dig_speed": 0.25, "light": 12.0}, "senses and motion tags")

## The host checks a client's moves against the sparked stats: a dashing, triple-jumping,
## fleet-footed player is never corrected.
func _host_accepts_sparked_moves(t: TestLog) -> void:
	var host := WorldHost.new(TileWorld.make_test())
	var sys := ItemsSystem.new()
	host.add_system(sys)
	var e := host.add_player("dasher", 1)
	e.character.level = 20
	e.character.sparks.slots = 10
	for k: Dictionary in [{"id": "dash", "rank": 2}, {"id": "skyhook", "rank": 2}, {"id": "fleet", "rank": 2}, {"id": "spring", "rank": 2}]:
		e.character.sparks.kindle(k)
	sys.refresh(e)
	t.check(e.stats.dash_speed > 0.0 and e.stats.air_jumps == 2, "host stats carry the sparks")
	var stats := Sparks.move_stats({"walk": 30}, "medium", e.character.sparks.list())
	var body := stats.make_body()
	body.pos = e.body.pos
	var seq := 0
	var bad := 0
	for i in 600:
		var p := PlayerInput.new()
		p.move_x = 1.0 if (i % 120) < 3 or ((i % 120) >= 8 and (i % 120) < 100) else -1.0
		p.jump = (i % 40) < 25
		p.jump_pressed = (i % 40) == 0 or (i % 40) == 12 or (i % 40) == 24
		p.dash = (i % 45) == 20
		PlayerController.step(host.world, body, p, stats, 1.0 / 60.0)
		seq += 1
		if seq % 2 == 0:
			host.tick_count += 1
			if host.submit_state(e.id, e.epoch, seq, body.pos, body.vel, HostEntity.body_flags(body)) != WorldHost.StateCheck.OK:
				bad += 1
	t.eq(bad, 0, "no corrections for 10 s of sparked movement at 30 Hz states")
	t.eq(e.corrections, 0, "corrections stay 0")
