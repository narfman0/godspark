## A chase at the pace, on a flat test world with the real brains and combat: a monster spawned
## 20 tiles from a standing player (seconds until its first swing), and the same monster after a
## player who runs away from 6 tiles off (walk 30, the real controller): the gap after 15 s, and
## when it first swung (its home is ahead of the chase, so the leash stays out of it). Prints one
## line per monster.
##   godot --headless -s res://tools/chase_probe.gd -- [pace=X] [ids=goblin-warrior,wolf,ogre,zombie]
extends SceneTree

const T := preload("res://tests/test_monster_brains.gd")

func _initialize() -> void:
	var o := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		o[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if o.has("pace"):
		MoveStats.pace_override = float(o["pace"])
	print("CHASE pace %.1f tiles/s per 30 ft (a walk-30 player runs %.1f)" % [MoveStats.pace(), MoveStats.player().run_speed])
	for slug in String(o.get("ids", "goblin-warrior,wolf,ogre,zombie")).split(","):
		var a := _approach(slug)
		var f := _flee(slug)
		print("  %-16s run %5.2f t/s: from 20 tiles to its first swing %5.1f s | after a fleeing player from 6 tiles: gap %5.1f tiles at 15 s, first swing %s" % [
			slug, a["run"], a["swing"], f["gap"], "%.1f s" % f["swing"] if f["swing"] >= 0.0 else "never"])
	quit()

func _approach(slug: String) -> Dictionary:
	var r := T.rig(7, T.world(512))
	var p := T.hero(r, 100.5)
	p.combatant.stats.max_hp = 9999
	p.combatant.stats.current_hp = 9999
	var m: HostEntity = r["ms"].spawn(slug, Vector2(120.5, T.GROUND), {"brain": "bruiser"})
	var host: WorldHost = r["host"]
	for i in K.TICK_HZ * 30:
		host.tick()
		host.drain()
		if (m.brain as MonsterBrain).attacks > 0:
			return {"run": m.stats.run_speed, "swing": float(i + 1) / K.TICK_HZ}
	return {"run": m.stats.run_speed, "swing": -1.0}

func _flee(slug: String) -> Dictionary:
	var r := T.rig(7, T.world(1024))
	var p := T.hero(r, 300.5)
	p.combatant.stats.max_hp = 9999
	p.combatant.stats.current_hp = 9999
	# home ahead of the chase, so the leash (48 tiles) never calls it back inside the probe
	var m: HostEntity = r["ms"].spawn(slug, Vector2(294.5, T.GROUND), {"brain": "bruiser", "home": Vector2(330.5, T.GROUND)})
	(m.brain as MonsterBrain).target_id = p.id
	(m.brain as MonsterBrain).state = MonsterBrain.State.CHASE
	var host: WorldHost = r["host"]
	var inp := PlayerInput.new()
	inp.move_x = 1.0
	var first := -1.0
	for i in K.TICK_HZ * 15:
		for s in MoveStats.step_hz() / K.TICK_HZ:
			PlayerController.step(host.world, p.body, inp, p.stats, 1.0 / MoveStats.step_hz())
		host.tick()
		host.drain()
		if first < 0.0 and (m.brain as MonsterBrain).attacks > 0:
			first = float(i + 1) / K.TICK_HZ
	return {"gap": p.body.pos.x - m.body.pos.x - (p.body.size.x + m.body.size.x) * 0.5, "swing": first}
