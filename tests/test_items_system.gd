## The items system on a host: kit, inventory and equipment rules, bonding, the edit flow,
## drops, loot, sparks at a shrine, crafting, persistence.
extends RefCounted

var host: WorldHost
var sys: ItemsSystem

func _fresh() -> void:
	host = WorldHost.new(TileWorld.make_test())
	sys = ItemsSystem.new()
	host.add_system(sys)

func _ticks(n: int) -> void:
	for i in n:
		host.tick()
	host.drain()

func run(t: TestLog) -> void:
	_kit(t)
	_inventory(t)
	_equipment(t)
	_bonding(t)
	_edit_flow(t)
	_drops(t)
	_loot(t)
	_shrine(t)
	_use_and_craft(t)
	_persistence(t)
	_with_rules(t)

## A stand-in rules system: refresh rebuilds the combatant and asks items to dress it, the
## way the contract says (and calls back into items.refresh, which must not loop).
class FakeRules extends HostSystem:
	var calls := 0
	var host: WorldHost
	func sys_id() -> int:
		return HostSystem.RULES
	func attach(h: WorldHost) -> void:
		host = h
	func refresh(e: HostEntity) -> void:
		calls += 1
		e.combatant = e.character.make_combatant(host.srd)
		var items: HostSystem = host.system(HostSystem.ITEMS)
		items.call("outfit", e)
		items.call("refresh", e)
		e.stats = e.character.move_stats(e.combatant)     # unsparked: items puts the sparks back

func _with_rules(t: TestLog) -> void:
	host = WorldHost.new(TileWorld.make_test())
	var rules := FakeRules.new()
	host.add_system(rules)
	sys = ItemsSystem.new()
	host.add_system(sys)
	var e := host.add_player("ruled", 1)
	t.check(rules.calls >= 1, "items.refresh goes through rules.refresh when it exists")
	e.character.sparks.slots = 1
	e.character.sparks.kindle({"id": "fleet", "rank": 1})
	var n := rules.calls
	sys.refresh(e)
	t.eq(rules.calls, n + 1, "once per refresh (no loop)")
	t.check(is_equal_approx(e.stats.run_speed, MoveStats.player().run_speed * 1.2), "the sparks end up on e.stats")
	t.eq(e.combatant.weapon.slug, "longsword", "and the gear on the combatant")

func _kit(t: TestLog) -> void:
	_fresh()
	var e := host.add_player("ann", 1)
	var ch := e.character
	t.eq(ch.equipment.at("main_hand"), {"base": "longsword", "count": 1, "material": "iron"}, "fighter kit: iron longsword")
	t.eq(String(ch.equipment.at("armor").get("base")), "chain-mail", "chain mail")
	t.eq(String(ch.equipment.at("off_hand").get("base")), "shield", "and a shield")
	t.check(ch.inventory.at(0).is_empty() and ch.inventory.selected == Inventory.ATTACK_SLOT, "hotbar 1: the empty attack slot, selected")
	t.eq(String(ch.inventory.at(1)["base"]), "tile:torch", "hotbar 2: torches")
	t.eq(String(ch.inventory.at(2)["base"]), "tile:campfire", "hotbar 3: a campfire")
	t.eq(int(ch.inventory.at(3)["count"]), 2, "hotbar 4: two healing potions")
	t.eq(String(ch.inventory.at(4)["base"]), "tile:bed", "hotbar 5: a bed")
	t.eq(ch.inventory.at(5), {"base": "tile:rope", "count": 2}, "hotbar 6: two ropes")
	t.eq(String(ch.inventory.at(6)["base"]), "supplies", "hotbar 7: supplies")
	t.eq(ch.inventory.count_base("tile:wood"), 0, "no blocks in the kit")
	ch.inventory.add(Items.make("gem", 1))
	t.check(ch.inventory.at(0).is_empty(), "new loot never lands in the attack slot")
	t.eq(e.combatant.weapon.slug, "longsword", "the wielded weapon is the combatant's")
	t.eq(e.combatant.armor_class, 19, "chain mail + shield + Defense: AC 19 as before")
	var w := host.add_player("wiz", 2, {"class": "wizard"})
	t.eq(String(w.character.equipment.at("main_hand")["base"]), "quarterstaff", "wizard: a quarterstaff")
	t.check(not w.character.equipment.at("main_hand").has("material"), "a wooden staff has no metal")
	t.check(w.character.equipment.is_empty_slot("armor"), "and no armour")

func _inventory(t: TestLog) -> void:
	var inv := Inventory.new()
	t.eq(inv.add(Items.make("tile:dirt", 1500)), {}, "1500 dirt fits")
	t.check(inv.at(Inventory.ATTACK_SLOT).is_empty(), "nothing lands in the attack slot (hotbar 1)")
	t.eq(inv.at(1)["count"], 999, "a stack holds 999")
	t.eq(inv.at(2)["count"], 501, "the rest starts the next")
	inv.add(Items.make("tile:dirt", 100))
	t.eq(inv.at(2)["count"], 601, "more tops up the open stack")
	inv.add(Items.coin(55))
	t.eq(inv.coin, 55, "coin is a number")
	t.eq(inv.at(3), {}, "coin takes no slot")
	t.check(inv.move(2, 5) and inv.at(5)["count"] == 601 and inv.at(2).is_empty(), "move to an empty slot")
	inv.put(6, Items.make("tile:dirt", 500))
	inv.move(6, 5)
	t.eq([inv.at(5)["count"], inv.at(6)["count"]], [999, 102], "move onto a stack merges up to the cap")
	inv.put(7, Items.make("tile:stone", 3))
	inv.move(7, 6)
	t.eq([inv.at(6)["base"], inv.at(7)["base"]], ["tile:stone", "tile:dirt"], "different things swap")
	var got := inv.take(6, 2)
	t.eq([got["count"], inv.at(6)["count"]], [2, 1], "take part of a stack")
	var c0 := inv.count_base("tile:dirt")
	t.check(inv.remove_base("tile:dirt", 1000) and inv.count_base("tile:dirt") == c0 - 1000, "remove_base takes across stacks")
	t.check(not inv.remove_base("tile:dirt", 99999) and inv.count_base("tile:dirt") == c0 - 1000, "and refuses more than held")
	var full := Inventory.new()
	for i in Inventory.SIZE:
		full.put(i, Items.make("longsword"))
	t.eq(full.add(Items.make("dagger")), Items.make("dagger"), "full: the leftover comes back")
	t.eq(full.add(Items.make("tile:wood", 5)), Items.make("tile:wood", 5), "full: tiles too")
	var old := Inventory.from_dict({"slots": [[0, {"base": "tile:wood", "count": 30}]], "selected": 0, "kit": true})
	t.check(old.at(0).is_empty() and Items.count(old.at(old.slots.find(old.slots.filter(func(x: Dictionary) -> bool: return not x.is_empty())[0]))) == 30,
		"an older save: the slot-1 item moves out of the attack slot")
	var rt := Inventory.from_dict(JSON.parse_string(JSON.stringify(inv.to_dict())))
	t.eq(rt.to_dict(), inv.to_dict(), "inventory round trip through JSON")
	inv.selected = 6
	t.eq(inv.tile_slot(TileDefs.id("stone")), 6, "placing takes the selected slot when it holds the tile")
	t.eq(inv.tile_slot(TileDefs.id("dirt")), inv.slots.find(inv.slots.filter(func(x: Dictionary) -> bool: return String(x.get("base", "")) == "tile:dirt")[0]), "else the first stack of it")
	t.eq(inv.tile_slot(TileDefs.id("torch")), -1, "none held")

func _equipment(t: TestLog) -> void:
	_fresh()
	var e := host.add_player("eq", 1)
	var ch := e.character
	var inv := ch.inventory
	# ten rings
	for i in 11:
		inv.put(10 + i, Items.make_magic("ring-of-warmth"))
	for i in 10:
		t.eq(sys.move_item(e, 10 + i, Equipment.index_of("ring_%d" % (i + 1))), "", "ring %d goes on" % (i + 1))
	t.eq(sys.use_item(e, 20), "", "an eleventh ring: use puts it on ring_1 (swap)")
	t.eq(String(inv.at(20).get("magic")), "ring-of-warmth", "and the old ring comes back")
	t.eq(ch.equipment.can_equip(Items.make("longsword"), "ring_3"), "bad_slot", "a sword is no ring")
	t.eq(ch.equipment.can_equip(Items.make_magic("ring-of-warmth"), "neck"), "bad_slot", "a ring is no amulet")
	# two-handed
	inv.put(30, Items.make("greatsword"))
	t.eq(sys.move_item(e, 30, Equipment.index_of("main_hand")), "", "greatsword in hand")
	t.check(ch.equipment.is_empty_slot("off_hand"), "the shield came off")
	t.eq(inv.count_base("shield"), 1, "into the bag")
	t.eq(inv.count_base("longsword"), 1, "and the longsword too")
	t.eq(e.combatant.weapon.slug, "greatsword", "combatant wields the greatsword")
	t.check(e.combatant.equipment.shield == null, "and has no shield")
	var shield_at := -1
	for i in Inventory.SIZE:
		if String(inv.at(i).get("base", "")) == "shield":
			shield_at = i
	t.eq(sys.move_item(e, shield_at, Equipment.index_of("off_hand")), "two_handed", "no shield with a two-handed weapon")
	# off-hand weapons: Light and Light
	inv.put(31, Items.make("shortsword"))
	inv.put(32, Items.make("dagger"))
	t.eq(sys.move_item(e, 31, Equipment.index_of("main_hand")), "", "shortsword in the main hand")
	t.eq(sys.move_item(e, 32, Equipment.index_of("off_hand")), "", "dagger in the off hand (both Light)")
	t.check(e.combatant.equipment.off_hand != null and e.combatant.equipment.off_hand.slug == "dagger", "combatant off hand: dagger")
	var ls := -1
	for i in Inventory.SIZE:
		if String(inv.at(i).get("base", "")) == "longsword":
			ls = i
	t.eq(sys.move_item(e, ls, Equipment.index_of("main_hand")), "not_light", "a longsword cannot pair with an off-hand dagger")
	t.eq(sys.move_item(e, Equipment.index_of("off_hand"), ItemsCodec.ANY), "", "unequip to the first free slot")
	t.eq(sys.move_item(e, ls, Equipment.index_of("main_hand")), "", "now the longsword goes in")
	t.eq(sys.move_item(e, shield_at, Equipment.index_of("off_hand")), "", "and the shield")
	# wielded weapon carries its mods
	var hot := {"base": "longsword", "count": 1, "material": "mithral", "affixes": ["embers"]}
	inv.put(33, hot)
	var atk := e.combatant.attack_modifier()
	sys.move_item(e, 33, Equipment.index_of("main_hand"))
	t.eq(e.combatant.attack_modifier(), atk + 1, "mithral: +1 to hit on the combatant")
	t.eq(e.combatant.hit_riders.size(), 1, "and the Embers rider")
	t.eq(sys.wielded(e), hot, "wielded() is the main-hand record")
	t.eq(sys.gear_mods(e), Items.mods(hot), "gear_mods: the worn mods")
	# max hit points from the level track with gear CON
	ch.level = 12
	e.combatant = ch.make_combatant(host.srd)
	inv.put(34, Items.make_magic("amulet-of-health").merged({"bonded": true}, true))
	sys.move_item(e, 34, Equipment.index_of("neck"))
	t.eq(e.combatant.stats.max_hp, LevelTrack.max_hp(12, 10, 4), "amulet of health: max HP re-derived from LevelTrack with CON 19")
	t.eq(sys.move_item(e, Equipment.index_of("neck"), ItemsCodec.ANY), "", "amulet off")
	t.eq(e.combatant.stats.max_hp, LevelTrack.max_hp(12, 10, 2), "and back")

func _bonding(t: TestLog) -> void:
	_fresh()
	var e := host.add_player("bond", 1)
	var inv := e.character.inventory
	inv.put(10, Items.make_magic("ring-of-protection"))
	sys.move_item(e, 10, Equipment.index_of("ring_1"))
	var ac := e.combatant.armor_class
	t.eq(sys.gear_mods(e).filter(func(m: Dictionary) -> bool: return m.has("save")), [], "unbonded ring: no magic")
	var ri := Equipment.index_of("ring_1")
	t.eq(sys.start_bond(e, ri), "no_campfire", "bonding needs a campfire")
	var at := Vector2i(floori(e.body.pos.x) + 2, floori(e.body.pos.y))
	host.world.set_fg(at.x, at.y, TileDefs.id("campfire"))
	t.eq(sys.start_bond(e, ri), "", "at a campfire it starts")
	_ticks(30)
	t.check(not bool(e.character.equipment.at("ring_1").get("bonded", false)), "not yet after 1 s")
	_ticks(32)
	t.check(bool(e.character.equipment.at("ring_1").get("bonded", false)), "bonded after 2 s")
	t.eq(e.combatant.armor_class, ac + 1, "and the ring's +1 AC works")
	t.eq(sys.start_bond(e, ri), "bonded", "bonding twice is refused")
	inv.put(11, Items.make_magic("robe-of-the-archmagi"))
	t.eq(sys.start_bond(e, 11), "class", "a fighter cannot bond a robe of the archmagi")
	var w := host.add_player("wbond", 2, {"class": "wizard"})
	w.body.pos = e.body.pos
	w.character.inventory.put(11, Items.make_magic("robe-of-the-archmagi"))
	t.eq(sys.start_bond(w, 11), "", "a wizard can")
	inv.put(12, Items.make_magic("cloak-of-protection"))
	t.eq(sys.start_bond(e, 12), "", "start another")
	e.body.pos.x += 30
	_ticks(3)
	t.check(not bool(inv.at(12).get("bonded", false)), "walking away interrupts it")
	t.eq(sys.start_bond(e, 13), "empty", "nothing there")
	inv.put(13, Items.make("longsword"))
	t.eq(sys.start_bond(e, 13), "no_bond_needed", "ordinary gear needs no bond")
	# Any number of bonds.
	e.body.pos.x -= 30
	var n := 0
	for i in 10:
		var idx := Equipment.index_of("ring_%d" % (i + 1))
		inv.put(20, Items.make_magic("ring-of-protection"))
		sys.move_item(e, 20, idx)
		if sys.start_bond(e, idx) == "":
			_ticks(62)
		if bool(e.character.equipment.at("ring_%d" % (i + 1)).get("bonded", false)):
			n += 1
	t.eq(n, 10, "ten rings, ten bonds: no attunement cap")

func _edit_flow(t: TestLog) -> void:
	_fresh()
	var e := host.add_player("dig", 1)
	var inv := e.character.inventory
	var fx := floori(e.body.pos.x)
	var gy := floori(e.body.pos.y) - 1     # the grass row under the feet
	t.eq(host.world.get_fg(fx + 2, gy), TileDefs.id("grass"), "grass beside the feet")
	t.eq(host.request_dig(e.id, 1, fx + 2, gy), WorldHost.Reason.OK, "dig starts")
	_ticks(20)
	t.eq(host.world.get_fg(fx + 2, gy), TileDefs.AIR, "dug")
	t.eq(inv.count_base("tile:rubble"), 1, "digging grass gives rubble")
	t.eq(inv.count_base("tile:dirt"), 0, "and no dirt block")
	inv.add(Items.make("tile:rubble", 4))
	var wood := TileDefs.id("rubble")
	var before := inv.count_base("tile:rubble")
	t.eq(host.request_place(e.id, 2, fx + 2, gy, wood), WorldHost.Reason.OK, "place rubble")
	t.eq(host.world.get_fg(fx + 2, gy), wood, "a rubble tile")
	t.eq(inv.count_base("tile:rubble"), before - 1, "placing takes one rubble")
	# an old save's wood block still places
	inv.add(Items.make("tile:wood", 1))
	t.eq(host.request_place(e.id, 20, fx + 4, gy + 1, TileDefs.id("wood")), WorldHost.Reason.OK, "an old wood block still places")
	t.eq(inv.count_base("tile:wood"), 0, "and is used")
	host.drain()
	t.eq(host.request_place(e.id, 3, fx + 3, gy + 1, TileDefs.id("stone")), WorldHost.Reason.NO_ITEM, "no stone held: refused")
	t.eq(host.world.get_fg(fx + 3, gy + 1), TileDefs.AIR, "and nothing placed")
	var evs := host.drain()
	var res := evs.filter(func(ev: Dictionary) -> bool: return ev["type"] == WorldHost.Ev.EDIT_RESULT)
	t.eq(int(res[-1]["reason"]), WorldHost.Reason.NO_ITEM, "EDIT_RESULT says NO_ITEM")
	# The inventory change goes out before the result of a place.
	host.request_place(e.id, 4, fx + 3, gy + 1, wood)
	var order: Array = []
	for ev: Dictionary in host.drain():
		if ev["type"] == WorldHost.Ev.SYS and ev["kind"] == ItemsCodec.K.SLOTS:
			order.append("slots")
		elif ev["type"] == WorldHost.Ev.EDIT_RESULT:
			order.append("result")
	t.eq(order, ["slots", "result"], "SLOTS precedes the place's EDIT_RESULT")
	# The last of a stack.
	inv.put(5, Items.make("tile:stone", 1))
	t.eq(host.request_place(e.id, 5, fx - 2, gy + 1, TileDefs.id("stone")), WorldHost.Reason.OK, "place the only stone")
	t.eq(host.request_place(e.id, 6, fx - 3, gy + 1, TileDefs.id("stone")), WorldHost.Reason.NO_ITEM, "then there is none")
	# Ore gives ore.
	host.world.set_fg(fx - 2, gy - 1, TileDefs.id("copper_ore"))
	host.request_dig(e.id, 7, fx - 2, gy - 1)
	_ticks(60)
	t.eq(inv.count_base("ore:copper"), 1, "copper ore gives a copper ore trade good")
	t.eq(Items.tile_of(Items.make("ore:copper")), 0, "which does not place")
	t.check(Items.value(Items.make("ore:copper")) > 0, "and has a value to sell")
	# built things give themselves
	for n: String in ["platform", "stairs_r", "ladder", "torch", "campfire"]:
		t.eq(Items.tile_drop(TileDefs.id(n)), "tile:" + n, "digging a %s gives it back" % n)
	for n: String in ["dirt", "stone", "slate", "cobblestone", "wood", "rubble"]:
		t.eq(Items.tile_drop(TileDefs.id(n)), "tile:rubble", "digging %s gives rubble" % n)
	# Full inventory: the dug item falls to the ground.
	for i in Inventory.SIZE:
		inv.put(i, Items.make("longsword"))
	host.request_dig(e.id, 8, fx + 2, gy)
	_ticks(30)
	var found := false
	for d: Drops.Drop in sys.drops.list.values():
		found = found or String(d.item["base"]) == "tile:rubble"
	t.check(found, "full inventory: the dug rubble is on the ground")

func _drops(t: TestLog) -> void:
	_fresh()
	var a := host.add_player("a", 1)
	var b := host.add_player("b", 2)
	var ground := float(host.world.height / 2)
	sys.drop(Vector2(60.5, ground + 10), [Items.make("tile:stone", 5)])
	var d: Drops.Drop = sys.drops.list.values()[0]
	_ticks(60)
	t.check(d.rest and is_equal_approx(d.pos.y, ground), "a drop falls and rests on the ground (%s)" % d.pos)
	sys.drop(Vector2(60.7, ground + 3), [Items.make("tile:stone", 7)])
	_ticks(60)
	t.eq(sys.drops.list.size(), 1, "an identical stack landing beside it merges")
	t.eq(Items.count(sys.drops.list.values()[0].item), 12, "into one of 12")
	sys.drop(Vector2(62.5, ground + 3), [Items.make("tile:dirt", 2)])
	_ticks(60)
	t.eq(sys.drops.list.size(), 2, "a different item does not merge")
	# dig out from under it: it falls again
	var under := Vector2i(62, int(ground) - 1)
	host.world.set_fg(under.x, under.y, TileDefs.AIR)
	_ticks(30)
	var dirt: Drops.Drop = null
	for x: Drops.Drop in sys.drops.list.values():
		if String(x.item["base"]) == "tile:dirt":
			dirt = x
	t.check(dirt != null and is_equal_approx(dirt.pos.y, ground - 1), "dug out from under, it falls into the hole")
	# two players race for one drop: exactly one gets it
	a.body.pos = Vector2(80.5, ground)
	b.body.pos = Vector2(80.5, ground)
	var wa := a.character.inventory.count_base("tile:bed")
	var wb := b.character.inventory.count_base("tile:bed")
	sys.drop(Vector2(80.5, ground + 1), [Items.make("tile:bed", 1)])
	_ticks(30)
	var ga := a.character.inventory.count_base("tile:bed") - wa
	var gb := b.character.inventory.count_base("tile:bed") - wb
	t.eq(ga + gb, 1, "two players on one drop: it is picked up once")
	t.eq(ga, 1, "by the first to touch it (entity order)")
	# Your own drop waits before you can pick it back up.
	var torches := a.character.inventory.count_base("tile:torch")
	sys.drop_item(a, a.character.inventory.tile_slot(TileDefs.id("torch")), 3)
	_ticks(10)
	t.check(sys.drops.list.size() >= 1, "a dropped stack stays on the ground a moment")
	b.body.pos.x += 40
	_ticks(90)
	t.eq(a.character.inventory.count_base("tile:torch"), torches, "then the dropper picks it back up")
	# Magnet widens the pickup radius.
	sys.drop(Vector2(a.body.pos.x + 5.0, ground + 1), [Items.make("cloth", 1)])
	_ticks(30)
	t.eq(a.character.inventory.count_base("cloth"), 0, "5 tiles away: out of reach")
	a.character.sparks.slots = 1
	a.character.sparks.kindle({"id": "magnet", "rank": 2})
	sys.refresh(a)
	_ticks(5)
	t.eq(a.character.inventory.count_base("cloth"), 1, "with Magnet III it comes")
	# Despawn.
	sys.drop(Vector2(30.5, ground + 1), [Items.make("bone", 1)])
	_ticks(2)
	var bone_id := 0
	for x: Drops.Drop in sys.drops.list.values():
		if String(x.item["base"]) == "bone":
			bone_id = x.id
			x.born -= Drops.DESPAWN
	_ticks(1)
	t.check(sys.drops.get_drop(bone_id) == null, "a drop despawns after a long time")
	# Saved with the world.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(sys.save_world()))
	var sys2 := ItemsSystem.new()
	sys2.load_world(saved)
	t.eq(sys2.drops.list.size(), sys.drops.list.size(), "drops survive save_world / load_world")
	var same := true
	var l1: Array = sys.drops.list.values()
	var l2: Array = sys2.drops.list.values()
	for i in l1.size():
		same = same and l1[i].item == l2[i].item and l1[i].pos.is_equal_approx(l2[i].pos)
	t.check(same, "with their items and places")
	sys.drop(Vector2(30.5, ground + 1), [Items.make_magic("ring-of-protection").merged({"bonded": true}, true)])
	var last: Drops.Drop = sys.drops.list.values()[-1]
	t.check(not last.item.has("bonded"), "a bond does not survive being dropped")

func _loot(t: TestLog) -> void:
	var info := Loot.victim_info("goblin-warrior", "standard", "surface")
	t.eq(info["type"], "fey", "goblin: fey (SRD 5.2.1)")
	t.eq(Loot.victim_info("bandit", "standard", "surface")["type"], "humanoid", "bandit: humanoid")
	var r1 := RandomNumberGenerator.new()
	var r2 := RandomNumberGenerator.new()
	r1.seed = 5
	r2.seed = 5
	var same := true
	for i in 300:
		same = same and Loot.roll(r1, info) == Loot.roll(r2, info)
	t.check(same, "loot is deterministic by seed")
	var avg := {}
	var sparks := {}
	var champion_ok := true
	for rank: String in ItemGen.RANKS:
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var n := 0
		var sp := 0
		var inf := Loot.victim_info("goblin-warrior", rank, "caves")
		for i in 1000:
			var got := Loot.roll(rng, inf)
			var non_coin := got.filter(func(x: Dictionary) -> bool: return x["base"] != "coin")
			n += non_coin.size()
			sp += non_coin.filter(func(x: Dictionary) -> bool: return x.has("spark")).size()
			if rank == "champion" and non_coin.is_empty():
				champion_ok = false
		avg[rank] = n / 1000.0
		sparks[rank] = sp
	t.check(avg["minion"] < 0.1 and avg["minion"] < avg["standard"] and avg["standard"] < avg["elite"]
			and avg["elite"] < avg["champion"] and avg["champion"] < avg["boss"], "drops grow with rank %s" % avg)
	t.check(avg["standard"] < 0.4, "a standard kill drops under 0.4 items on average (%.2f)" % avg["standard"])
	t.eq(sparks["minion"] + sparks["standard"], 0, "minions and standard foes drop no sparks")
	t.check(sparks["elite"] > 60 and sparks["elite"] < 200, "elites: a chance of a spark (%d in 1000)" % sparks["elite"])
	t.check(champion_ok, "champions always drop a spark or an item")
	# spark rank by depth
	var deep := 0
	var shallow := 0
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 3
	for i in 2000:
		shallow += int(Loot.random_spark(rng2, "surface")["spark"]["rank"])
		deep += int(Loot.random_spark(rng2, "nadir")["spark"]["rank"])
	t.check(deep > shallow * 3, "deeper sparks have higher ranks (%d vs %d)" % [deep, shallow])
	t.eq(Loot.depth_band(10, 100), "nadir", "depth band: nadir at the bottom")
	t.eq(Loot.depth_band(70, 100), "surface", "surface band")
	# on_kill drops at the victim
	_fresh()
	host.add_player("killer", 1)
	var g := host.add_srd_monster("goblin-warrior", host.spawn + Vector2(4, 0))
	g.look["rank"] = "boss"
	var items := sys.on_kill(g)
	t.check(items.size() >= 2, "a boss goblin drops at least a spark and a magic item")
	t.eq(sys.drops.list.size(), items.size(), "on the ground where it died")
	t.eq(ItemsSystem.rank_of(g), "boss", "rank read from the entity")

func _shrine(t: TestLog) -> void:
	_fresh()
	var e := host.add_player("kin", 1)
	var ch := e.character
	var inv := ch.inventory
	inv.put(10, Items.spark_item("fleet", 0))
	inv.put(11, Items.spark_item("fleet", 2))
	inv.put(12, Items.spark_item("otter", 0))
	t.eq(sys.kindle(e, 10), "no_shrine", "kindling needs a shrine")
	host.world.set_fg(floori(e.body.pos.x) - 3, floori(e.body.pos.y), TileDefs.id("shrine"))
	var run0 := e.stats.run_speed
	t.eq(sys.kindle(e, 10), "", "kindle Fleet I at a shrine")
	t.check(inv.at(10).is_empty(), "the spark leaves the inventory")
	t.check(is_equal_approx(e.stats.run_speed, run0 * 1.1), "the host's move stats run faster")
	t.eq(sys.kindle(e, 12), "full", "level 1 has one slot")
	t.eq(sys.swap_spark(e, 0, 11), "", "swap Fleet III in")
	t.check(is_equal_approx(e.stats.run_speed, run0 * 1.3), "faster again")
	t.eq(Items.count(inv.at(11)), 1, "Fleet I came back to the inventory")
	t.eq(int(inv.at(11)["spark"]["rank"]), 0, "as Fleet I")
	ch.level = 3
	_ticks(31)
	t.eq(ch.sparks.slots, 2, "level 3: a second slot")
	t.eq(sys.kindle(e, 12), "", "Otter goes into it")
	t.check(e.stats.swim_speed > MoveStats.player().swim_speed, "and swimming is faster")
	t.eq(sys.kindle(e, 11), "full", "no third slot")

func _use_and_craft(t: TestLog) -> void:
	_fresh()
	var e := host.add_player("pot", 1)
	var s := e.combatant.stats
	t.eq(sys.use_item(e, 3), "full_hp", "no potion at full hit points")
	s.current_hp = 1
	t.eq(sys.use_item(e, 3), "", "drink a potion")
	t.check(s.current_hp >= 5, "healed 2d4+2 (%d)" % s.current_hp)
	t.eq(int(e.character.inventory.at(3)["count"]), 1, "one potion left")
	t.eq(sys.craft(e, "platform", 3), "", "craft walkways from supplies")
	t.eq(e.character.inventory.count_base("tile:platform"), 9, "3 supplies: 9 walkway planks")
	t.eq(e.character.inventory.count_base("supplies"), 9, "the supplies are used")
	t.eq(sys.craft(e, "rope", 1), "", "a rope from supplies")
	t.eq(e.character.inventory.count_base("tile:rope"), 3, "two from the kit and one made")
	t.eq(sys.craft(e, "stairs_r", 1), "", "stairs from supplies")
	t.eq(sys.craft(e, "bed", 4), "missing", "not enough supplies for four beds")
	t.eq(sys.craft(e, "nonsense", 1), "unknown", "unknown recipe")

func _persistence(t: TestLog) -> void:
	var dir := "user://test_items_save"
	DirAccess.make_dir_recursive_absolute(dir)
	_fresh()
	var e := host.add_player("keep", 1)
	var ch := e.character
	ch.level = 3
	ch.inventory.put(12, Items.spark_item("spring", 1))
	ch.inventory.put(13, {"base": "warhammer", "count": 1, "material": "silver", "quality": "fine", "affixes": ["rime:2", "magpie"]})
	ch.inventory.coin = 321
	ch.inventory.selected = 2
	host.world.set_fg(floori(e.body.pos.x) - 3, floori(e.body.pos.y), TileDefs.id("shrine"))
	sys.kindle(e, 12)
	ch.inventory.put(14, Items.make_magic("ring-of-protection").merged({"bonded": true}, true))
	sys.move_item(e, 14, Equipment.index_of("ring_7"))
	sys.drop(host.spawn + Vector2(10, 2), [Items.make("gem", 4)])
	_ticks(40)
	var before := ch.to_dict()
	var drops_before: Dictionary = sys.save_world()
	t.eq(host.save_state(dir), OK, "host state saved")
	t.eq(host.save_players(dir), OK, "players saved")
	var world := host.world
	# quit, load, rejoin
	host = WorldHost.new(world)
	host.load_state(dir)
	host.load_players(dir)
	sys = ItemsSystem.new()
	host.add_system(sys)
	var e2 := host.add_player("keep", 1)
	t.eq(e2.character.to_dict()["inventory"], before["inventory"], "inventory, coin and selection come back")
	t.eq(e2.character.to_dict()["equipment"], before["equipment"], "equipment with its bond comes back")
	t.eq(e2.character.to_dict()["sparks"], before["sparks"], "the constellation comes back")
	t.check(not e2.character.inventory.at(1).is_empty() and e2.character.inventory.kit_given, "no second kit")
	t.eq(sys.save_world()["drops"].size(), drops_before["drops"].size(), "the drops come back")
	t.check(e2.stats.jump_velocity > MoveStats.player().jump_velocity, "sparked move stats on rejoin")
	t.eq(e2.combatant.armor_class, 20, "bonded ring of protection: AC 20 on rejoin")
	for f in DirAccess.get_files_at(dir.path_join("players")):
		DirAccess.remove_absolute(dir.path_join("players").path_join(f))
	DirAccess.remove_absolute(dir.path_join("players"))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
