## Hit point bars only while they say something (Nameplates.fade and Nameplates.show_rule): a bar
## appears on a hit point change, holds, fades out, and comes back on the next change; nothing for
## a full-health creature that was never touched; names only for players, ranked foes, the one
## under the cursor; a downed player always. And arrange with unnamed bars in a crowd.
extends RefCounted

func run(t: TestLog) -> void:
	_fade(t)
	_rule(t)
	_crowd(t)
	_step(t)

func _fade(t: TestLog) -> void:
	var hold := Nameplates.HOLD_S
	var out := Nameplates.FADE_S
	t.eq(Nameplates.fade(0.0), 1.0, "right after a change: full")
	t.eq(Nameplates.fade(-0.5), 1.0, "a change stamped a moment ahead (clock order): full")
	t.eq(Nameplates.fade(hold), 1.0, "full to the end of the hold")
	t.check(absf(Nameplates.fade(hold + out * 0.5) - 0.5) < 0.001, "half way through the fade: half")
	t.eq(Nameplates.fade(hold + out), 0.0, "gone at the end of the fade")
	t.eq(Nameplates.fade(hold + out + 30.0), 0.0, "and stays gone")
	t.eq(Nameplates.fade(INF), 0.0, "never changed: nothing")
	t.check(hold + out <= 6.0 and hold >= 1.0, "a few seconds in all (%.1f s held, %.1f s fading)" % [hold, out])
	var prev := 1.0
	var ok := true
	var jump := 0.0
	for i in 101:
		var a := Nameplates.fade((hold + out) * i / 100.0)
		ok = ok and a <= prev + 1e-6 and a >= 0.0 and a <= 1.0
		jump = maxf(jump, prev - a)
		prev = a
	t.check(ok, "never rises with time, stays in 0..1")
	t.check(jump < 0.05, "no step: largest drop between samples %.3f" % jump)
	t.eq(Nameplates.fade(1.0, 0.5, 0.0), 0.0, "no fade time: off once the hold ends")

func _rule(t: TestLog) -> void:
	var R := func(hp: int, since: float, hovered := false, player := false, downed := false, ranked := false) -> Dictionary:
		return Nameplates.show_rule(hp, 20, since, hovered, player, downed, ranked)
	var none: Dictionary = R.call(20, INF)
	t.eq(none["alpha"], 0.0, "full health, never touched: no plate (targeted or in a fight alike)")
	var hit: Dictionary = R.call(12, 0.2)
	t.check(float(hit["alpha"]) == 1.0 and bool(hit["bar"]) and not bool(hit["name"]), "just hurt: a full bar, no name for an ordinary monster")
	var fading: Dictionary = R.call(12, Nameplates.HOLD_S + Nameplates.FADE_S * 0.5)
	t.check(float(fading["alpha"]) > 0.0 and float(fading["alpha"]) < 1.0 and bool(fading["bar"]), "then fading (%.2f)" % fading["alpha"])
	t.eq(R.call(12, 30.0)["alpha"], 0.0, "hurt but not hit lately: faded out")
	t.eq(R.call(12, INF)["alpha"], 0.0, "hurt when first seen, never changed since: nothing")
	var again: Dictionary = R.call(9, 0.0)
	t.eq(again["alpha"], 1.0, "hit again: back at full")
	var healed: Dictionary = R.call(20, 0.1)
	t.check(float(healed["alpha"]) == 1.0 and bool(healed["bar"]), "healed to full: the full bar shows, then fades")
	t.eq(R.call(20, 10.0)["alpha"], 0.0, "and is gone")
	var boss: Dictionary = R.call(12, 0.5, false, false, false, true)
	t.check(bool(boss["bar"]) and bool(boss["name"]), "a ranked foe's bar carries its name (and frame)")
	t.eq(R.call(20, INF, false, false, false, true)["alpha"], 0.0, "a ranked foe at full health: nothing")
	var mate: Dictionary = R.call(12, 0.5, false, true)
	t.check(bool(mate["bar"]) and bool(mate["name"]), "another player, hurt: name and bar")
	t.eq(R.call(20, INF, false, true)["alpha"], 0.0, "another player at full health: nothing")
	t.eq(R.call(12, 30.0, false, true)["alpha"], 0.0, "another player, hurt long ago: faded too")
	var down: Dictionary = R.call(0, 60.0, false, true, true)
	t.check(float(down["alpha"]) == 1.0 and bool(down["bar"]) and bool(down["name"]), "a downed player: always, at full strength")
	var look: Dictionary = R.call(20, INF, true)
	t.check(float(look["alpha"]) == 1.0 and bool(look["name"]) and not bool(look["bar"]), "under the cursor at full health: the name alone")
	var look_hurt: Dictionary = R.call(12, 30.0, true)
	t.check(float(look_hurt["alpha"]) == 1.0 and bool(look_hurt["bar"]) and bool(look_hurt["name"]), "under the cursor, hurt long ago: name and bar, full")

## Ordinary monsters' bars have no name: they take the compact form at once and keep the crowd
## limit; the named ones still choose first and stack.
func _crowd(t: TestLog) -> void:
	var want: Array = []
	for i in 12:
		want.append({"at": Vector2(600.0 + i * 6.0, 300.0), "tall": Nameplates.H, "named": i == 0})
	var spots := Nameplates.arrange(want, 1.0)
	var named := 0
	var bars := 0
	var top := INF
	for s: Dictionary in spots:
		if s.is_empty():
			continue
		if bool(s["bar"]):
			bars += 1
		else:
			named += 1
		top = minf(top, (s["box"] as Rect2).position.y)
	t.eq(named, 1, "only the named one has a name plate")
	t.check(not bool(spots[0]["bar"]), "and it is the first in line")
	t.check(bars >= 1 and bars < 11, "the rest are bars, capped in a crowd (%d of 11)" % bars)
	var n := 0
	for i in spots.size():
		for j in range(i + 1, spots.size()):
			if not (spots[i] as Dictionary).is_empty() and not (spots[j] as Dictionary).is_empty() \
					and (spots[i]["box"] as Rect2).intersects(spots[j]["box"]):
				n += 1
	t.eq(n, 0, "nothing drawn on top of anything")
	var most := Nameplates.H + Nameplates.GAP + Nameplates.BAR_ROWS * (Nameplates.BAR_H + Nameplates.GAP)
	t.check(300.0 - top <= most, "no tower: %.0f px above the heads, at most %.0f" % [300.0 - top, most])
	var spread: Array = []
	for i in 4:
		spread.append({"at": Vector2(200.0 + i * 200.0, 300.0), "tall": Nameplates.H, "named": false})
	var ss := Nameplates.arrange(spread, 1.0)
	var all_bars := true
	for s: Dictionary in ss:
		all_bars = all_bars and not s.is_empty() and bool(s["bar"]) and is_equal_approx((s["box"] as Rect2).end.y, 300.0)
	t.check(all_bars, "spread out, unnamed bars sit right at their heads")

func _shown(np: Nameplates) -> Array:
	var out: Array = []
	for i in Nameplates.CAP:
		if np.plates[i].visible:
			out.append(i)
	return out

## Nameplates.step on a real ClientWorld: what the screen gets as hit points change.
func _step(t: TestLog) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var world := TileWorld.make_test()
	var cw := ClientWorld.new()
	var me := Vector2(world.width / 2 + 0.5, world.height / 2)
	cw.setup(world.width, world.height, world.world_seed, 1, "ann", me, 0, 2)
	var fx := FxView.new()
	fx.cw = cw
	var np := Nameplates.new()
	np.fx = fx
	tree.root.add_child(np)
	var cam := Camera3D.new()
	tree.root.add_child(cam)
	cam.position = Vector3(me.x * K.TILE_M, me.y * K.TILE_M + 1.0, 12.0)
	cam.current = true
	cw.add_remote(5, HostEntity.Kind.MONSTER, "Wolf", Vector2(1.5, 1.2), me + Vector2(3, 0), 0, 11, 11)
	cw.add_remote(6, HostEntity.Kind.PLAYER, "Wren", Vector2(1.2, 2.2), me + Vector2(-3, 0), 0, 40, 40)
	var wolf: ClientWorld.RemoteEntity = cw.remotes[5]
	var wren: ClientWorld.RemoteEntity = cw.remotes[6]
	np.step(cam, 0, 5)
	t.eq(_shown(np).size(), 0, "step: full health, the wolf engaged, a player beside: no plate at all")
	wolf.hp = 6
	np.step(cam, 0, 5)
	var on := _shown(np)
	t.eq(on.size(), 1, "the wolf loses hit points: one plate")
	if on.size() == 1:
		var d: Dictionary = np._data[on[0]]
		t.check(int(d["id"]) == 5 and bool(d["bar"]) and not bool(d["named"]), "its short bar, no name")
		t.eq(np.plates[on[0]].modulate.a, 1.0, "at full strength")
	np.changed_at[5] = Time.get_ticks_msec() - int((Nameplates.HOLD_S + Nameplates.FADE_S * 0.5) * 1000.0)
	np.step(cam, 0, 5)
	on = _shown(np)
	t.check(on.size() == 1 and np.plates[on[0]].modulate.a > 0.2 and np.plates[on[0]].modulate.a < 0.8,
		"fading a few seconds later (%.2f)" % (np.plates[on[0]].modulate.a if on.size() == 1 else -1.0))
	np.changed_at[5] = Time.get_ticks_msec() - 20000
	np.step(cam, 0, 5)
	t.eq(_shown(np).size(), 0, "hurt, not hit for 20 s, still engaged: gone")
	np.step(cam, 5, 5)
	on = _shown(np)
	t.check(on.size() == 1 and bool(np._data[on[0]]["named"]) and np.plates[on[0]].modulate.a == 1.0, "under the cursor: name and bar")
	wolf.hp = 3
	np.step(cam, 0, 0)
	t.eq(_shown(np).size(), 1, "hit again (a new hp in the snapshot): back")
	np.changed_at[5] = Time.get_ticks_msec() - 20000
	np.changed(5)
	np.step(cam, 0, 0)
	t.eq(_shown(np).size(), 1, "a DAMAGE or HEAL event (changed) brings it back too")
	wolf.hp = 0
	np.step(cam, 0, 0)
	t.eq(_shown(np).size(), 0, "dead: no plate")
	wren.hp = 25
	np.step(cam, 0, 0)
	on = _shown(np)
	t.check(on.size() == 1 and int(np._data[on[0]]["id"]) == 6 and bool(np._data[on[0]]["named"]) and not bool(np._data[on[0]]["bar"]),
		"another player hurt: a named plate with its bar")
	np.forget(5)
	t.check(not np.changed_at.has(5) and not np.last_hp.has(5), "forget drops the timers")
	np.queue_free()
	cam.queue_free()
	fx.free()
