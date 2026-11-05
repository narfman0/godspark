## Ropes: anchoring rules, length, reeling in, falling when the anchor goes, climbing with the
## real controller, the host's edit flow, two clients agreeing over the loopback, persistence.
extends RefCounted

const Rig := preload("res://tests/net_rig.gd")
const DT := 1.0 / 60.0

func run(t: TestLog) -> void:
	_rules(t)
	_climb(t)
	_host(t)
	_net(t)
	_persist(t)

## Flat ground (top at 64), no background walls, a 1-wide ledge column... and a shaft 3 wide,
## 40 deep at x 100..102 with rock on both sides.
static func shaft_world() -> TileWorld:
	var w := TileWorld.new(256, 128, 3)
	var stone := TileDefs.id("stone")
	for x in 256:
		for y in 64:
			w.set_fg(x, y, stone, true)
	for x in range(100, 103):
		for y in range(24, 64):
			w.set_fg(x, y, TileDefs.AIR, true)
	return w

func _rules(t: TestLog) -> void:
	var w := shaft_world()
	var rope := TileDefs.id("rope")
	t.eq(Rope.anchor_cell(w, Vector2i(99, 63)), Vector2i(99, 62), "aimed at rock: tied under it")
	t.eq(Rope.anchor_cell(w, Vector2i(100, 63)), Vector2i(100, 63), "aimed at air: that cell")
	t.check(Rope.can_anchor(w, 100, 63), "beside the shaft's rock wall: held")
	t.check(not Rope.can_anchor(w, 101, 63), "in the middle of the shaft: nothing to hold")
	t.check(not Rope.can_anchor(w, 101, 70), "in open air above ground: nothing to hold")
	t.check(not Rope.can_anchor(w, 99, 63), "not inside rock")
	w.set_fg(101, 66, TileDefs.id("platform"), true)
	t.check(Rope.can_anchor(w, 101, 65), "under a walkway: held")
	w.set_fg(101, 66, TileDefs.AIR, true)
	w.set_bg(101, 70, 2, true)
	t.check(Rope.can_anchor(w, 101, 70), "on a background wall: held")
	w.set_bg(101, 70, 0, true)
	# length: to the floor, or LENGTH
	w.set_fg(100, 63, rope, true)
	var cells := Rope.unroll(w, Vector2i(100, 63))
	t.eq(cells.size(), Rope.length() - 1, "a 40-deep shaft: the rope is %d long" % Rope.length())
	t.eq(Rope.run_of(w, Vector2i(100, 50)).size(), Rope.length(), "run_of finds the whole rope")
	t.eq(Rope.top_of(w, Vector2i(100, 40)), Vector2i(100, 63), "its top is the anchor")
	w.set_bg(100, 63 - Rope.length(), 2, true)
	t.check(not Rope.can_anchor(w, 100, 63 - Rope.length()), "no second rope tied straight under the first")
	w.set_bg(100, 63 - Rope.length(), 0, true)
	t.eq(Rope.remove(w, Vector2i(100, 45)), Vector2i(100, 63), "remove takes it all")
	t.eq(Rope.run_of(w, Vector2i(100, 50)).size(), 0, "nothing left")
	var short := shaft_world()
	for x in range(100, 103):
		short.set_fg(x, 54, TileDefs.id("stone"), true)    # a floor 9 down
	short.set_fg(102, 63, rope, true)
	t.eq(Rope.unroll(short, Vector2i(102, 63)).size() + 1, 9, "it stops on a floor: 9 long, rows 55..63")
	t.eq(short.get_fg(102, 55), rope, "down to the floor")
	t.eq(short.get_fg(102, 54), TileDefs.id("stone"), "not through it")
	# loose after a change
	short.set_fg(103, 63, TileDefs.AIR, true)
	t.eq(Rope.loose_after(short, 103, 63), [Vector2i(102, 63)] as Array[Vector2i], "its rock dug: the anchor is loose")

func _climb(t: TestLog) -> void:
	var w := shaft_world()
	var rope := TileDefs.id("rope")
	w.set_fg(102, 63, rope, true)
	Rope.unroll(w, Vector2i(102, 63))
	var stats := MoveStats.player()
	var b := stats.make_body()
	b.pos = Vector2(104.5, 64)
	TileCollision.update_contacts(w, b)
	var inp := func(mx: float, up: bool, down: bool, jp := false) -> PlayerInput:
		var p := PlayerInput.new()
		p.move_x = mx
		p.up = up
		p.down = down
		p.jump = jp
		p.jump_pressed = jp
		return p
	for i in 20:
		PlayerController.step(w, b, inp.call(-0.5, false, false), stats, DT)
		if floori(b.pos.x) == 102:
			break
	t.check(b.on_floor and b.pos.y == 64.0, "steps onto the rope's top from the ledge (%s)" % b.pos)
	for i in 120:
		PlayerController.step(w, b, inp.call(0.0, false, true), stats, DT)
	t.check(b.climbing and b.pos.y < 53.0 and absf(b.pos.x - 102.25) < 1e-4, "S climbs down the rope, swung in clear of the rock (%s)" % b.pos)
	var y0: float = b.pos.y
	for i in 30:
		PlayerController.step(w, b, inp.call(0.0, true, false), stats, DT)
	t.check(b.climbing and absf(b.pos.y - y0 - 30 * DT * stats.ladder_speed) < 0.01, "W climbs up it at ladder speed")
	for i in 3:
		PlayerController.step(w, b, inp.call(-1.0, true, false, i == 0), stats, DT)
	t.check(not b.climbing and b.vel.y > 0.0, "jump lets go with a jump")
	t.check(not TileCollision.overlaps_solid(w, Rect2(102, 40, 1, 1)) and TileDefs.opaque[rope] == 0, "a rope is not solid and does not block light")

func _host(t: TestLog) -> void:
	var host := WorldHost.new(shaft_world())
	host.spawn = Vector2(97.5, 64)
	var sys := ItemsSystem.new()
	host.add_system(sys)
	var e := host.add_player("climber", 1)
	var inv := e.character.inventory
	inv.add(Items.make("tile:rope", 2))
	var n0 := inv.count_base("tile:rope")
	var rope := TileDefs.id("rope")
	t.eq(host.request_place(e.id, 1, 101, 63, rope), WorldHost.Reason.NO_ANCHOR, "mid-shaft: refused")
	t.eq(host.request_place(e.id, 2, 100, 63, rope), WorldHost.Reason.OK, "beside the wall: placed")
	t.eq(Rope.run_of(host.world, Vector2i(100, 63)).size(), Rope.length(), "and unrolled to its length")
	t.eq(inv.count_base("tile:rope"), n0 - 1, "one rope item used")
	host.drain()
	t.eq(host.request_place(e.id, 3, 100, 60, rope), WorldHost.Reason.OK, "a rope used on the rope reels it in")
	t.eq(Rope.run_of(host.world, Vector2i(100, 50)).size(), 0, "all of it")
	t.eq(inv.count_base("tile:rope"), n0, "the item is back")
	host.request_place(e.id, 4, 100, 63, rope)
	t.eq(host.request_dig(e.id, 5, 100, 62), WorldHost.Reason.OK, "digging a rope cell")
	for i in 10:
		host.tick()
	t.eq(Rope.run_of(host.world, Vector2i(100, 50)).size(), 0, "reels the whole rope in")
	t.eq(inv.count_base("tile:rope"), n0, "for one item")
	# the anchor's rock dug: the rope falls and drops as an item
	host.request_place(e.id, 6, 100, 63, rope)
	host.world.set_fg(99, 63, TileDefs.AIR)     # someone digs the rock it was tied beside
	t.eq(Rope.run_of(host.world, Vector2i(100, 50)).size(), 0, "a rope whose hold is dug falls")
	var seen := 0
	for d: Drops.Drop in sys.drops.list.values():
		if String(d.item.get("base", "")) == "tile:rope":
			seen += 1
	t.eq(seen, 1, "and lies on the ground as one rope item")
	# a monster that climbs uses it: nav plans down the rope (a ladder edge)
	host.world.set_fg(99, 63, TileDefs.id("stone"))
	host.request_place(e.id, 7, 100, 63, rope)
	var prof := MonsterNav.profile(MoveStats.from_srd({"walk": 30}, "small"))
	var s := MonsterNav.start(host.world, prof, Vector2(97.5, 64), Vector2(100.5, 34), Vector2i(1, 1), false)
	while not s.step(100000):
		pass
	var path := s.result()
	t.check(path != null and path.counts().has(MonsterNav.Edge.LADDER), "a monster's path goes down the rope (%s)" % (path.describe() if path != null else "none"))

func _net(t: TestLog) -> void:
	var world := shaft_world()
	var rig := Rig.new(world, 0.05)
	rig.host.spawn = Vector2(97.5, 64)
	var sys := ItemsSystem.new()
	rig.host.add_system(sys)
	var cs: Array = []
	for n: String in ["ann", "bob"]:
		var c := rig.add_client(n)
		var ic := ItemsClient.new()
		cs.append(ic)
		c.welcomed.connect(func(cw: ClientWorld) -> void: cw.add_system(ic))
	var ai: ItemsClient = cs[0]
	var ready := func() -> bool:
		return rig.cw(0) != null and rig.cw(1) != null and rig.cw(0).area_ready() and rig.cw(1).area_ready() and ai.live
	t.check(rig.until(ready, 5.0) >= 0.0, "two clients join")
	var he := rig.host_entity(0)
	he.character.inventory.put(25, Items.make("tile:rope", 2))
	sys._send_slots(he)
	rig.run(0.3)
	var rope := TileDefs.id("rope")
	rig.inputs[0].place_tile = rope
	rig.inputs[0].target = Vector2i(99, 63)        # aimed at the rock lip: tied under it
	rig.inputs[0].place = true
	rig.frame()
	rig.inputs[0].place = false
	t.eq(rig.cw(0).world.get_fg(99, 62), TileDefs.id("stone"), "aimed at rock with rock under it: nothing (tied cell is rock)")
	rig.inputs[0].target = Vector2i(100, 63)
	rig.inputs[0].place = true
	rig.frame()
	t.eq(rig.cw(0).world.get_fg(100, 63), rope, "ann sees the anchor at once (predicted)")
	rig.inputs[0].place = false
	rig.run(0.5)
	t.eq(Rope.run_of(rig.cw(0).world, Vector2i(100, 63)).size(), Rope.length(), "ann sees the whole rope")
	t.eq(Rope.run_of(rig.cw(1).world, Vector2i(100, 63)).size(), Rope.length(), "bob sees the whole rope")
	t.check(rig.in_sync(0) and rig.in_sync(1), "worlds in sync")
	t.eq(ai.inventory.count_base("tile:rope"), 1, "one rope left in ann's mirror")
	rig.inputs[0].target = Vector2i(100, 62)
	rig.inputs[0].place = true
	rig.frame()
	rig.inputs[0].place = false
	rig.run(0.5)
	t.eq(Rope.run_of(rig.cw(1).world, Vector2i(100, 63)).size(), 0, "ann reels it in: bob sees it gone")
	t.eq(ai.inventory.count_base("tile:rope"), 2, "and ann has both ropes")
	t.check(rig.in_sync(0) and rig.in_sync(1), "still in sync")
	t.eq(rig.cw(0).rolled_back, 0, "nothing rolled back")

func _persist(t: TestLog) -> void:
	var w := shaft_world()
	w.set_fg(100, 63, TileDefs.id("rope"), true)
	Rope.unroll(w, Vector2i(100, 63), -1, true)
	var dir := "user://test_rope_world"
	t.eq(WorldSave.save(w, dir), OK, "saved")
	var back := WorldSave.load(dir)
	t.check(back != null and Rope.run_of(back, Vector2i(100, 63)).size() == Rope.length(), "the rope comes back with the world")
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
