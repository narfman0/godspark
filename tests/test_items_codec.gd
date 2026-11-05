## ItemsCodec round trips and malformed input.
extends RefCounted

func run(t: TestLog) -> void:
	var recs := [
		{"base": "tile:wood", "count": 30},
		{"base": "longsword", "count": 1, "material": "mithral", "quality": "fine", "affixes": ["embers:2", "gleaming"],
			"magic": "weapon-1-2-or-3", "tier": 2},
		Items.make_magic("ring-of-protection").merged({"bonded": true}, true),
		Items.spark_item("skyhook", 2),
		Items.make_magic("potions-of-healing", 3).merged({"count": 7}, true),
	]
	var entries: Array = []
	for i in recs.size():
		entries.append([i * 11, recs[i]])
	entries.append([Equipment.index_of("ring_10"), {}])
	var m := ItemsCodec.read_slots(ItemsCodec.slots(123456, 7, entries))
	t.eq(m["coin"], 123456, "SLOTS: coin")
	t.eq(m["selected"], 7, "SLOTS: selected")
	t.eq(m["entries"], entries, "SLOTS: entries and records")
	var full: Array = []
	for i in Inventory.SIZE + Equipment.SLOTS.size():
		full.append([i, recs[1]])
	var big := ItemsCodec.slots(0, 0, full)
	t.check(big.size() < WorldHost.SYS_MAX, "a full SLOTS of rich records fits a SYS message (%d B)" % big.size())
	t.eq(ItemsCodec.read_slots(big)["entries"].size(), full.size(), "and decodes")
	var kindled := [{"id": "fleet", "rank": 2, "at": [8, 8]}, {"id": "silver_tongue", "rank": 0, "at": [10, 6]}]
	var s := ItemsCodec.read_stars(ItemsCodec.stars({"walk": 35, "climb": 0, "swim": 10, "fly": 0}, "medium", 9, kindled))
	t.eq(s, {"speeds": {"walk": 35, "climb": 0, "swim": 10, "fly": 0}, "size": "medium", "slots": 9, "kindled": kindled}, "STARS round trip")
	var drops := [{"id": 70000, "pos": Vector2(12.5, 64.0), "vel": Vector2(-3.0, 6.0), "item": recs[1]},
		{"id": 2, "pos": Vector2(1.0, 2.0), "vel": Vector2.ZERO, "item": recs[0]}]
	t.eq(ItemsCodec.read_drops(ItemsCodec.drops(drops)), drops, "DROPS round trip")
	t.eq(ItemsCodec.read_gone(ItemsCodec.gone([[5, 0], [70000, 3]])), [[5, 0], [70000, 3]], "GONE round trip")
	var mv := [{"id": 9, "pos": Vector2(3.25, 4.5), "vel": Vector2(0, -2)}]
	t.eq(ItemsCodec.read_moved(ItemsCodec.moved(mv)), mv, "MOVED round trip")
	t.eq(ItemsCodec.read_note(ItemsCodec.note(ItemsCodec.K.BOND, false, "no_campfire")),
			{"op": ItemsCodec.K.BOND, "ok": false, "word": "no_campfire"}, "NOTE round trip")
	t.eq(ItemsCodec.read_bonding(ItemsCodec.bonding(55, 1999)), {"index": 55, "ms": 1999}, "BONDING round trip")
	t.eq(ItemsCodec.read_drop_req(ItemsCodec.drop_req(12, 600)), {"index": 12, "n": 600}, "DROP request round trip")
	t.eq(ItemsCodec.read_craft(ItemsCodec.craft("campfire", 3)), {"recipe": "campfire", "times": 3}, "CRAFT round trip")
	# malformed input never crashes and decodes to empty
	var bad := ItemsCodec.slots(1, 2, entries)
	t.eq(ItemsCodec.read_slots(bad.slice(0, bad.size() - 3)), {}, "truncated SLOTS: {}")
	var bd := ItemsCodec.drops(drops)
	t.eq(ItemsCodec.read_drops(bd.slice(0, 10)), [], "truncated DROPS: []")
	t.eq(ItemsCodec.read_stars(PackedByteArray([1, 2])), {}, "short STARS: {}")
	t.eq(ItemsCodec.read_gone(PackedByteArray([5, 0, 1])), [], "short GONE: []")
	t.eq(ItemsCodec.read_note(PackedByteArray()), {}, "empty NOTE: {}")
	# a host fed garbage SYS messages shrugs
	var host := WorldHost.new(TileWorld.make_test())
	var sys := ItemsSystem.new()
	host.add_system(sys)
	var e := host.add_player("fuzz", 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var before := e.character.to_dict()
	for i in 400:
		var junk := PackedByteArray()
		for j in rng.randi_range(0, 6):
			junk.append(rng.randi_range(0, 255))
		var kind: int = [ItemsCodec.K.MOVE, ItemsCodec.K.USE, ItemsCodec.K.SELECT, ItemsCodec.K.BOND, ItemsCodec.K.KINDLE,
				ItemsCodec.K.SWAP, ItemsCodec.K.CRAFT, 99][i % 8]
		host.receive_sys(e.id, HostSystem.ITEMS, kind, junk)
	t.check(e.character.inventory.to_dict()["slots"].size() >= 1, "garbage requests leave a sane inventory")
	var total := 0
	for x: Dictionary in e.character.inventory.filled():
		total += Items.count(x["item"])
	for s2: String in Equipment.SLOTS:
		total += Items.count(e.character.equipment.at(s2))
	var total0 := 0
	for x: Array in before["inventory"]["slots"]:
		total0 += int(x[1]["count"])
	for s3: String in before["equipment"]:
		total0 += int(before["equipment"][s3]["count"])
	t.eq(total, total0, "and no item is made or lost by shuffling")
