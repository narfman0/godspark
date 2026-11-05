## The items system over the loopback net: the client mirror, honest place prediction and
## rollback, drops seen and picked up once, sparks mirrored into the client's movement.
extends RefCounted

const Rig := preload("res://tests/net_rig.gd")

func run(t: TestLog) -> void:
	var world := TileWorld.make_test(512, 128)
	var rig := Rig.new(world, 0.05)
	var sys := ItemsSystem.new()
	rig.host.add_system(sys)
	var mid := world.width / 2
	var ground := world.height / 2
	var cs: Array = []
	for n: String in ["ann", "bob"]:
		var c := rig.add_client(n)
		var ic := ItemsClient.new()
		cs.append(ic)
		c.welcomed.connect(func(cw: ClientWorld) -> void: cw.add_system(ic))
	var ai: ItemsClient = cs[0]
	var bi: ItemsClient = cs[1]
	var ready := func() -> bool:
		return rig.cw(0) != null and rig.cw(1) != null and rig.cw(0).area_ready() and rig.cw(1).area_ready() and ai.live and bi.live
	var ok := rig.until(ready, 5.0)
	t.check(ok >= 0.0, "both clients join and hear from the items system")
	var ann := rig.cw(0)
	var he := rig.host_entity(0)
	t.eq(ai.item(0), {"base": "tile:wood", "count": 30}, "mirror: the kit's wood on hotbar 1")
	t.eq(String(ai.item(Equipment.index_of("main_hand"))["base"]), "longsword", "mirror: the longsword in hand")
	t.eq(ai.selected_tile(), TileDefs.id("wood"), "the selected hotbar slot places wood")
	t.eq(ann.place_tile, TileDefs.id("wood"), "and the client places it")
	var a := _props(ann.stats)
	t.eq(a, _props(MoveStats.player()), "no sparks: the client's move stats are MoveStats.player()")

	# dig: the item arrives
	var tx := floori(ann.body.pos.x) + 2
	rig.inputs[0].dig = true
	rig.inputs[0].target = Vector2i(tx, ground - 1)
	t.check(rig.until(func() -> bool: return ai.inventory.count_base("tile:dirt") == 1, 3.0) >= 0.0, "dug grass shows up as dirt in the mirror")
	rig.inputs[0].dig = false
	rig.run(0.1)
	# place: consumed
	rig.inputs[0].place = true
	rig.inputs[0].place_tile = 0
	rig.inputs[0].target = Vector2i(tx, ground - 1)
	t.check(rig.until(func() -> bool: return ai.inventory.count_base("tile:wood") == 29, 2.0) >= 0.0, "placing wood uses one")
	rig.inputs[0].place = false
	rig.run(0.2)
	t.eq(rig.cw(1).world.get_fg(tx, ground - 1), TileDefs.id("wood"), "bob sees the wood")
	t.check(rig.in_sync(0) and rig.in_sync(1), "worlds in sync")
	# no item: not predicted, not sent
	var pred := ann.predicted
	rig.inputs[0].place = true
	rig.inputs[0].place_tile = TileDefs.id("stone")
	rig.inputs[0].target = Vector2i(tx + 1, ground)
	rig.run(0.3)
	rig.inputs[0].place = false
	t.eq(ann.predicted, pred, "no stone held: the client predicts nothing")
	t.eq(ann.world.get_fg(tx + 1, ground), TileDefs.AIR, "and shows nothing")
	# a stale mirror: the client thinks it has stone, the host knows better; rollback
	ai.inventory.slots[20] = Items.make("tile:stone", 1)
	var rb := ann.rolled_back
	rig.run(0.05)
	rig.inputs[0].place = true
	var shown := rig.until(func() -> bool: return ann.world.get_fg(tx + 1, ground) == TileDefs.id("stone"), 0.5)
	t.check(shown >= 0.0, "a stale mirror predicts the place")
	rig.inputs[0].place = false
	t.check(rig.until(func() -> bool: return ann.rolled_back > rb, 1.0) >= 0.0, "the host refuses it (NO_ITEM) and it rolls back")
	t.eq(ann.world.get_fg(tx + 1, ground), TileDefs.AIR, "the cell is air again")
	rig.run(0.2)
	t.check(rig.in_sync(0) and rig.in_sync(1), "hashes match after the rollback")
	ai.inventory.slots[20] = {}
	# the last of a stack: a second place right after is not predicted
	he.character.inventory.put(25, Items.make("tile:ladder", 1))
	sys._send_slots(he)
	rig.run(0.3)
	t.eq(ai.held_tiles(TileDefs.id("ladder")), 1, "one ladder held")
	rig.inputs[0].place_tile = TileDefs.id("ladder")
	rig.inputs[0].place = true
	rig.inputs[0].target = Vector2i(tx + 1, ground)
	rig.frame()
	t.eq(ai.held_tiles(TileDefs.id("ladder")), 0, "the predicted place reserves it")
	rig.inputs[0].target = Vector2i(tx + 1, ground + 1)
	var p0 := ann.predicted
	rig.frame()
	t.eq(ann.predicted, p0, "a second ladder is not predicted")
	rig.inputs[0].place = false
	rig.run(0.4)
	t.eq(ai.inventory.count_base("tile:ladder"), 0, "the host took the ladder")
	t.eq(rig.cw(1).world.get_fg(tx + 1, ground), TileDefs.id("ladder"), "and placed it")
	t.check(rig.in_sync(0) and rig.in_sync(1), "in sync")
	t.eq(ann.corrections, 0, "no corrections so far")

	# drops: both see it; one picks it up
	var added := [0, 0]
	var removed := [[], []]
	ai.drop_added.connect(func(_id: int, _p: Vector2, _it: Dictionary) -> void: added[0] += 1)
	bi.drop_added.connect(func(_id: int, _p: Vector2, _it: Dictionary) -> void: added[1] += 1)
	ai.drop_removed.connect(func(id: int, by: int) -> void: removed[0].append([id, by]))
	bi.drop_removed.connect(func(id: int, by: int) -> void: removed[1].append([id, by]))
	var spot := Vector2(float(mid) - 20.5, ground + 4)
	sys.drop(spot, [Items.make("gem", 3)])
	rig.run(0.2)
	t.check(added[0] >= 1 and added[1] >= 1, "both clients see the drop")
	t.eq(ai.drops_in_view().size(), 1, "ann knows one drop")
	rig.run(1.0)
	t.check(absf(ai.drops_in_view()[0]["pos"].y - ground) < 0.01, "on the client it lies on the ground too")
	var bob_e := rig.host_entity(1)
	bob_e.body.pos = Vector2(spot.x, ground)
	rig.cw(1).body.pos = bob_e.body.pos
	t.check(rig.until(func() -> bool: return not removed[0].is_empty() and not removed[1].is_empty(), 2.0) >= 0.0, "picked up: both hear it is gone")
	t.eq(removed[0][0][1], bob_e.id, "picked up by bob")
	t.check(rig.until(func() -> bool: return bi.inventory.count_base("gem") == 3, 1.0) >= 0.0, "bob's mirror has the gems")
	t.eq(ai.inventory.count_base("gem"), 0, "ann has none")

	# sparks: kindle by request at a shrine; the client moves with the same stats
	world.set_fg(floori(he.body.pos.x) - 3, floori(he.body.pos.y), TileDefs.id("shrine"))
	he.character.inventory.put(30, Items.spark_item("fleet", 2))
	sys._send_slots(he)
	rig.run(0.3)
	var notes: Array = []
	ai.note.connect(func(op: int, okk: bool, w: String) -> void: notes.append([op, okk, w]))
	ai.kindle(30)
	t.check(rig.until(func() -> bool: return ai.constellation.size() == 1, 1.0) >= 0.0, "kindled: the mirror shows the star")
	t.eq(notes.filter(func(n: Array) -> bool: return n[0] == ItemsCodec.K.KINDLE)[0][1], true, "the host said ok")
	t.eq(_props(ann.stats), _props(he.stats), "client and host move stats are the same")
	t.check(ann.stats.run_speed > MoveStats.player().run_speed * 1.25, "Fleet III on the client")
	t.check(ai.item(30).is_empty(), "the spark left the inventory")
	rig.inputs[0].move_x = 1.0
	rig.run(1.5)
	rig.inputs[0].move_x = -1.0
	rig.run(1.5)
	rig.inputs[0].move_x = 0.0
	rig.run(0.3)
	t.eq(ann.corrections, 0, "running with Fleet III is never corrected")
	t.check(rig.in_sync(0) and rig.in_sync(1), "still in sync")
	# select a hotbar slot
	ai.select_hotbar(1)
	t.eq(ann.place_tile, TileDefs.id("torch"), "selecting hotbar 2 places torches")
	rig.run(0.2)
	t.eq(he.character.inventory.selected, 1, "the host knows the selection")
	# move and equip through requests
	ai.move(1, 15)
	t.check(rig.until(func() -> bool: return not ai.item(15).is_empty(), 1.0) >= 0.0, "move a stack to the bag")
	ai.unequip("off_hand")
	t.check(rig.until(func() -> bool: return ai.item(Equipment.index_of("off_hand")).is_empty(), 1.0) >= 0.0, "unequip the shield")
	t.check(he.combatant.equipment.shield == null, "the host combatant has no shield")

func _props(s: MoveStats) -> Dictionary:
	var out := {}
	for p: Dictionary in s.get_property_list():
		if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out[p["name"]] = s.get(p["name"])
	return out
