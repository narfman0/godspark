## The pace knob (data/movement.json pace.tiles_per_s_per_30ft, docs/tracks/pace.md): one number
## scales every movement speed and keeps every acceleration's time; jumps do not scale; at the
## configured pace a Medium body really makes the running jumps the passages stage counts on;
## parties on screen never outrun the people walking with them.
extends RefCounted

const DT := 1.0 / 60.0
const SP := preload("res://core/world/worldgen/stage_passages.gd")
const Col := preload("res://tests/test_collision.gd")

func run(t: TestLog) -> void:
	_knob(t)
	_scales(t)
	_jump_promise(t)
	_parties(t)

func _knob(t: TestLog) -> void:
	var d: Dictionary = MoveStats.data()["pace"]
	var p := MoveStats.pace()
	t.eq(p, float(d["tiles_per_s_per_30ft"]), "the pace is the data's number")
	t.check(p >= float(d["srd_real_time"]) and p <= 6.0, "and roughly SRD: between real time (%.1f) and 30 ft per 2 s round (%.1f)" % [float(d["srd_real_time"]), p])
	t.eq(float(d["srd_real_time"]), 2.0, "SRD real time is 30 ft per 6 s round: 2 tiles a second")
	var s := MoveStats.player()
	t.eq(s.run_speed, p, "a walk-30 body runs at the pace")
	t.check(is_equal_approx(MoveStats.from_srd({"walk": 40}).run_speed, p * 40.0 / 30.0), "walk 40 runs 4/3 of it")

## The same body numbers at three paces: speeds in proportion, accelerations in proportion
## (so the times to top speed stay), jumps the same.
func _scales(t: TestLog) -> void:
	var at := {}
	for p: float in [2.0, 4.0, 13.0]:
		MoveStats.pace_override = p
		at[p] = MoveStats.from_srd({"walk": 30, "climb": 30, "fly": 60}, "medium")
	MoveStats.pace_override = 0.0
	var a: MoveStats = at[2.0]
	var b: MoveStats = at[13.0]
	var k := 13.0 / 2.0
	var ok := true
	for f: String in ["run_speed", "ground_accel", "ground_friction", "turn_accel", "air_accel", "air_friction",
			"ladder_speed", "ladder_side_speed", "climb_speed", "swim_speed", "swim_accel", "fly_speed", "fly_accel"]:
		if not is_equal_approx(float(b.get(f)), float(a.get(f)) * k):
			ok = false
			t.check(false, "%s scales with the pace (%.3f at 2, %.3f at 13)" % [f, a.get(f), b.get(f)])
	t.check(ok, "every speed and acceleration scales with the pace")
	t.check(is_equal_approx(a.jump_velocity, b.jump_velocity) and is_equal_approx(a.gravity, b.gravity) \
		and is_equal_approx(a.terminal_fall, b.terminal_fall), "jumps and falls do not")
	t.check(is_equal_approx(b.run_speed / b.ground_accel, 0.118), "top speed in 0.118 s at any pace (%.3f)" % (b.run_speed / b.ground_accel))
	# the old pace reproduces the old numbers (docs/tracks/movement.md): 13, 110, 140, 220, 55, 12
	t.check(absf(b.ground_accel - 110.0) < 0.5 and absf(b.ground_friction - 140.0) < 0.5 and absf(b.turn_accel - 220.0) < 0.5 \
		and absf(b.air_accel - 55.0) < 0.5 and absf(b.air_friction - 12.0) < 0.1, "pace 13 gives back the old accelerations (%.1f %.1f %.1f %.1f %.1f)" % [
			b.ground_accel, b.ground_friction, b.turn_accel, b.air_accel, b.air_friction])
	t.check(absf(b.climb_speed - 7.8) < 0.01 and absf(b.fly_speed - 26.0) < 0.01, "and near the old climb (8) and fly (26 for fly 60)")

## The passages stage (worldgen) joins standing spots across gaps of up to JUMP_ACROSS - 1 open
## columns with ACROSS_ROOM rows of headroom over the box, landing a row up, level or a row down.
## A pace too slow for that (3 or less with today's jump) must lower JUMP_ACROSS too.
func _jump_promise(t: TestLog) -> void:
	var gap: int = SP.JUMP_ACROSS - 1
	for dy in [1, 0, -1]:
		var ok := _crosses(MoveStats.player(), gap, SP.ACROSS_ROOM, dy)
		t.check(ok, "at pace %.1f a Medium body jumps %d open columns under %d rows of headroom, landing %+d (stage_passages.JUMP_ACROSS)" % [
			MoveStats.pace(), gap, SP.ACROSS_ROOM, dy])
	MoveStats.pace_override = 2.0
	var literal := _crosses(MoveStats.player(), gap, SP.ACROSS_ROOM, 1)
	MoveStats.pace_override = 0.0
	t.check(not literal, "at SRD real time (2.0) it cannot: that pace needs JUMP_ACROSS 3 (docs/tracks/pace.md)")

static func _crosses(st: MoveStats, gap: int, room: int, dy: int) -> bool:
	var floor_y := 10
	var world := Col.flat(128, 64, floor_y)
	for x in range(40, 40 + gap):
		for y in range(0, floor_y):
			world.set_fg(x, y, TileDefs.AIR, true)
	var land := floor_y + dy
	for x in range(40 + gap, 128):
		for y in range(mini(floor_y, land), maxi(floor_y, land)):
			world.set_fg(x, y, TileDefs.id("stone") if dy > 0 else TileDefs.AIR, true)
	var ceil_y := maxi(floor_y, land) + 3 + room
	for x in 128:
		world.set_fg(x, ceil_y, TileDefs.id("stone"), true)
	for takeoff in 90:
		var b := st.make_body()
		b.pos = Vector2(40.0 - 2.5, floor_y)
		TileCollision.update_contacts(world, b)
		for i in 240:
			var p := PlayerInput.new()
			p.move_x = 1.0
			p.jump = i >= takeoff and i < takeoff + 40
			p.jump_pressed = i == takeoff
			PlayerController.step(world, b, p, st, DT)
			if b.pos.y < minf(floor_y, land) - 0.5:
				break
			if b.on_floor and b.left() >= 40.0 + gap - 1.0 and absf(b.pos.y - land) < 0.01:
				return true
	return false

func _parties(t: TestLog) -> void:
	for kind: String in WorldSim.TRAVEL_TPS:
		t.check(WorldSim.travel_tps(kind) <= WorldSim.TRAVEL_PACE_CAP * MoveStats.pace() + 1e-6, "%s on screen at most %.2f of the pace" % [kind, WorldSim.TRAVEL_PACE_CAP])
	t.eq(WorldSim.travel_tps("raid"), 2.5, "at the default pace the cap changes nothing")
	MoveStats.pace_override = 2.0
	t.eq(WorldSim.travel_tps("raid"), 1.5, "at SRD real time people on foot walk 1.5 tiles a second")
	t.check(1.5 <= MoveStats.pace(), "under a walk-30 body's run")
	MoveStats.pace_override = 0.0
