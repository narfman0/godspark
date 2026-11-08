## Walk, run and sprint playback (ActorBody): the gait whose playback is nearest its authored
## speed at the body's speed, held against flicker, so feet stay planted at the pace. The Synty
## speeds are the measured ones (tools/gait_strip.gd sweep=1); forge bodies with a run clip run
## (checked when one is synced; the suite also runs with no art).
extends RefCounted

func run(t: TestLog) -> void:
	_synty(t)
	_forge(t)

func _synty(t: TestLog) -> void:
	var w: Array = ActorBody.synty_gait(ActorBody.WALK_MPS)
	t.check(w[0] == "walk" and is_equal_approx(float(w[1]), 1.0), "a walk at the walk's own speed plays at 1x (%s)" % [w])
	var pace := MoveStats.pace() * K.TILE_M
	var r: Array = ActorBody.synty_gait(pace)
	t.check(r[0] == "run" and float(r[1]) >= ActorBody.SYNTY_SPEED_MIN and float(r[1]) <= ActorBody.SYNTY_SPEED_MAX,
		"a walk-30 run at the pace (%.2f m/s) plays the run at %.2fx" % [pace, float(r[1])])
	var s: Array = ActorBody.synty_gait(ActorBody.SPRINT_MPS)
	t.check(s[0] == "sprint" and is_equal_approx(float(s[1]), 1.0), "a sprint at 6 m/s plays at 1x")
	# across the walk/run crossover (sqrt(1.2 x 1.8) = 1.47 m/s) the held gait stays a while
	t.eq(ActorBody.synty_gait(1.6, "walk")[0], "walk", "a walk held at 1.6 m/s stays a walk")
	t.eq(ActorBody.synty_gait(1.6, "")[0], "run", "picked fresh at 1.6 m/s it is a run")
	t.eq(ActorBody.synty_gait(1.4, "run")[0], "run", "a run held at 1.4 m/s stays a run")
	t.eq(ActorBody.synty_gait(1.0, "run")[0], "walk", "and at 1.0 m/s gives way to the walk")

func _forge(t: TestLog) -> void:
	var mat := StandardMaterial3D.new()
	var runner := ""
	for slug: String in ["kobold-warrior", "bearded-devil", "ettin", "werewolf"]:
		if ForgeMonster.is_synced(slug) and not Looks.quarantine().has(slug):
			runner = slug
			break
	if runner == "":
		t.check(true, "no forge body with a run clip synced: forge gait checks skipped")
		return
	var a := ActorBody.build({"slug": runner}, mat)
	if a.kind != "forge" or not (a.visual as ForgeMonster).has_clip("run"):
		t.check(true, "%s is not a forge body with a run here: skipped" % runner)
		a.free()
		return
	var g: Dictionary = a.forge_gaits()
	t.check(float(g.get("walk", 0.0)) > 0.05 and float(g.get("run", 0.0)) > float(g["walk"]),
		"%s: walk and run ground speeds measured, the run faster (%s)" % [runner, g])
	var slow: Array = a.forge_clip_speed("run", Vector2(float(g["walk"]) / K.TILE_M, 0))
	t.check(slow[0] == "walk" and absf(float(slow[1]) - 1.0) < 0.01, "%s: at the walk's own speed it walks at 1x (%s)" % [runner, slow])
	var fast: Array = a.forge_clip_speed("run", Vector2(float(g["run"]) / K.TILE_M, 0))
	t.check(fast[0] == "run" and absf(float(fast[1]) - 1.0) < 0.01, "%s: at the run's own speed it runs at 1x (%s)" % [runner, fast])
	(a.visual as ForgeMonster).play("run", 1.0)
	t.eq((a.visual as ForgeMonster).current_clip, "run", "%s: play(\"run\") plays its run clip" % runner)
	t.check(a.forge_natural(MoveStats.pace()) > 0.0, "%s: a measured gait at the pace" % runner)
	a.free()
