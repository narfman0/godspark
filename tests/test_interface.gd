## The interface track's logic (headless: no pixels): tooltip text, choice validation, the
## constellation layout, icon categories, the floating-number pool, the input mapping, and
## every screen built against a mirrored client over the loopback harness and fed state.
extends RefCounted

const Rig := preload("res://tests/net_rig.gd")

func run(t: TestLog) -> void:
	Items.ensure()
	_tooltips(t)
	_choices(t)
	_constellation(t)
	_icons(t)
	_numbers(t)
	_input(t)
	_telegraph_shapes(t)
	_quick(t)
	_screens(t)

func _tooltips(t: TestLog) -> void:
	var sword := {"base": "longsword", "count": 1, "material": "silver", "quality": "fine", "affixes": ["embers:2", "mole"]}
	var s := ItemText.plain(sword)
	t.check(s.begins_with("Fine Silver Longsword of Embers"), "tooltip title is the generated name (%s)" % s.get_slice("\n", 0))
	t.check(s.contains("1d8 slashing"), "base damage shown")
	t.check(s.contains("1d6 fire on every hit"), "affix in plain words")
	t.check(s.contains("Dig") and s.contains("faster"), "dig affix as words")
	t.check(s.contains("Silvered"), "material perk as words")
	var ring := Items.make_magic("ring-of-protection")
	var rs := ItemText.plain(ring, {"class": "fighter"})
	t.check(rs.contains("Needs bonding at a campfire"), "unbonded magic says it needs bonding")
	t.check(rs.contains("+1 AC"), "ring's AC")
	ring["bonded"] = true
	t.check(ItemText.plain(ring).contains("Bonded to you"), "bonded state")
	t.check(ItemText.plain(Items.make_magic("potions-of-healing")).contains("Drink: heal 2d4+2"), "potion use")
	var cmp := ItemText.compare({"base": "plate-armor", "count": 1}, {"base": "chain-mail", "count": 1})
	t.check(cmp.has("+2 base AC"), "comparison with what is worn (%s)" % [cmp])
	t.check(ItemText.plain(Items.spark_item("fleet", 1)).contains("Run 20% faster"), "spark effect in words")
	t.eq(ItemText.lines({}), [], "empty item: no lines")

func _choices(t: TestLog) -> void:
	var ch := {"key": "1:cantrips", "kind": "spell", "label": "Cantrips", "count": 2,
		"options": [{"id": "fire-bolt", "name": "Fire Bolt"}, {"id": "ray-of-frost", "name": "Ray of Frost"}, {"id": "light", "name": "Light"}]}
	var p := ChoiceLogic.toggle([], "fire-bolt", 2)
	p = ChoiceLogic.toggle(p, "light", 2)
	t.eq(p, ["fire-bolt", "light"], "toggle adds up to the count")
	t.eq(ChoiceLogic.toggle(p, "ray-of-frost", 2), ["fire-bolt", "ray-of-frost"], "a pick past the count replaces the latest")
	t.eq(ChoiceLogic.toggle(p, "light", 2), ["fire-bolt"], "toggle removes")
	t.eq(ChoiceLogic.validate(ch, ["fire-bolt", "light"]), "", "a full answer is valid")
	t.check(ChoiceLogic.validate(ch, ["fire-bolt"]).begins_with("Pick 2"), "too few is refused")
	t.check(ChoiceLogic.validate(ch, ["light", "light"]).contains("twice"), "duplicates are refused")
	t.check(ChoiceLogic.validate(ch, ["light", "wish"]) != "", "unknown option refused")
	t.check(ChoiceLogic.validate(ch, []) != "", "empty refused")
	var asi := {"key": "4:asi", "kind": "asi", "label": "ASI", "count": 1,
		"options": [{"id": "ability-score-improvement"}, {"id": "grappler"}, {"id": "alert"}]}
	t.check(ChoiceLogic.validate(asi, ["ability-score-improvement", "str"]) != "", "ASI needs two abilities")
	t.eq(ChoiceLogic.validate(asi, ChoiceLogic.answer_for(asi, ["ability-score-improvement"], ["str", "str"])), "", "ASI +2 to one ability")
	t.eq(ChoiceLogic.validate(asi, ["alert"]), "", "a plain feat")
	t.check(ChoiceLogic.validate(asi, ["grappler"]) != "", "Grappler needs str or dex")
	t.check(ChoiceLogic.option_text(ch, {"id": "fire-bolt"}).contains("Cantrip"), "spell text from the SRD")
	var kn: String = Knacks.all()[0]["id"]
	t.check(ChoiceLogic.knack_line(kn, {}) != "", "a knack line without deeds")
	var d: Dictionary = Knacks.def(kn).get("deeds", {})
	if not d.is_empty():
		var c: String = d.keys()[0]
		t.check(ChoiceLogic.knack_line(kn, {c: 412}).contains("412"), "the deed count shows on the card")

func _constellation(t: TestLog) -> void:
	var con := Constellation.new()
	con.salt = "ann"
	con.slots = 40
	for id: String in Sparks.ids():
		con.kindle({"id": id, "rank": 1})
	var a := SigilLayout.layout("ann", con.kindled, 40, Vector2(440, 440))
	var b := SigilLayout.layout("ann", con.kindled, 40, Vector2(440, 440))
	t.eq(a, b, "layout is deterministic")
	t.eq((a["stars"] as Array).size() + (a["ghosts"] as Array).size(), 40, "40 slots: stars plus empty rings")
	t.check(SigilLayout.min_gap(a) >= 12.0, "no overlapping stars at 40 slots (min gap %.1f px)" % SigilLayout.min_gap(a))
	for p: Vector2 in (a["stars"] as Array) + (a["ghosts"] as Array):
		if not Rect2(Vector2.ZERO, Vector2(440, 440)).has_point(p):
			t.check(false, "star inside the sky (%s)" % p)
	var bob := Constellation.new()
	bob.salt = "bob"
	bob.slots = 5
	for id: String in Sparks.ids().slice(0, 5):
		bob.kindle({"id": id, "rank": 0})
	var c := SigilLayout.layout("bob", bob.kindled, 5, Vector2(440, 440))
	var a5 := SigilLayout.layout("ann", con.kindled.slice(0, 5), 5, Vector2(440, 440))
	t.check(c["stars"] != a5["stars"], "two characters draw differently")
	t.eq((c["lines"] as Array).size(), 4, "lines join stars in kindling order")
	var img := SigilLayout.image(bob.sigil(), 64)
	t.eq(img.get_size(), Vector2i(64, 64), "sigil exports as an image")

func _icons(t: TestLog) -> void:
	var cases := {"longsword": "blade", "shortbow": "bow", "greataxe": "axe", "mace": "blunt", "quarterstaff": "staff",
		"chain-mail": "armor", "shield": "shield", "tile:dirt": "block", "tile:iron_ore": "ore", "tile:torch": "torch",
		"ingot:iron": "ingot", "coin": "coin", "gem": "gem"}
	for base: String in cases:
		t.eq(ItemIcons.category({"base": base, "count": 1}), cases[base], "icon for %s" % base)
	t.eq(ItemIcons.category(Items.make_magic("ring-of-protection")), "ring", "icon for a ring")
	t.eq(ItemIcons.category(Items.make_magic("potions-of-healing")), "potion", "icon for a potion")
	t.eq(ItemIcons.category(Items.make_magic("cloak-of-protection")), "cloak", "icon for a cloak")
	t.eq(ItemIcons.category(Items.spark_item("fleet", 0)), "spark", "icon for a spark")
	t.eq(ItemIcons.category({}), "empty", "empty slot")
	t.eq(ItemIcons.color({"base": "tile:dirt", "count": 1}), TileDefs.colors[TileDefs.id("dirt")], "a block shows its tile colour")
	t.eq(ItemIcons.rarity(Items.make_magic("ring-of-protection")), "rare", "magic rarity")
	var tex := ItemIcons.texture({"base": "longsword", "count": 1})
	t.eq(tex.get_size(), Vector2(ItemIcons.SIZE, ItemIcons.SIZE), "icon texture size")
	t.check(ItemIcons.texture({"base": "longsword", "count": 1}) == tex, "icons are cached")
	var img := ItemIcons.render("ring", Color.RED)
	t.check(img.get_pixel(24, 24).a < 0.1 and img.get_pixel(24, 10).a > 0.5, "the ring is drawn (gem filled, hole empty)")

func _numbers(t: TestLog) -> void:
	var pool := NumberPool.new(40)
	for i in 100:
		pool.acquire(i % 7)
	t.eq(pool.live(), 40, "a horde never takes more than the cap")
	var p2 := NumberPool.new(8)
	var r0 := p2.acquire(5)
	var r1 := p2.acquire(5)
	t.eq([int(r0["row"]), int(r1["row"])], [0, 1], "numbers on one target stack")
	p2.step(NumberPool.LIFE + 0.1)
	t.eq(p2.live(), 0, "numbers expire")
	t.eq(int(p2.acquire(5)["row"]), 0, "and the stack resets")

func _input(t: TestLog) -> void:
	t.eq(InputLogic.primary_action({}), "attack", "empty slot attacks")
	t.eq(InputLogic.primary_action({"base": "longsword", "count": 1}), "attack", "a weapon attacks")
	t.eq(InputLogic.primary_action({"base": "tile:wood", "count": 30}), "place", "a block places")
	t.eq(InputLogic.primary_action({"base": "tile:campfire", "count": 1}), "place", "a campfire places")
	t.eq(InputLogic.primary_action(Items.make_magic("potions-of-healing")), "use", "a potion is drunk")
	t.eq(InputLogic.primary_action(Items.make_magic("ring-of-protection")), "attack", "a ring in hand: swing the weapon")
	t.check(not InputLogic.world_click_allowed(true, false), "a click with a screen open never reaches the world")
	t.check(not InputLogic.world_click_allowed(false, true), "a click on the HUD never reaches the world")
	t.check(InputLogic.world_click_allowed(false, false), "a click on the world does")
	t.eq(InputLogic.wheel_target(false, false), "zoom", "plain wheel zooms")
	t.eq(InputLogic.wheel_target(true, false), "hotbar", "Ctrl+wheel picks a slot")
	t.eq(InputLogic.wheel_target(false, true), "hotbar", "wheel over the hotbar picks a slot")
	t.eq(InputLogic.next_hotbar(9, 1), 0, "hotbar wraps forward")
	t.eq(InputLogic.next_hotbar(0, -1), 9, "and back")
	t.eq(InputLogic.hotbar_index(10), 9, "key 0 is slot 10")
	t.check(InputLogic.movement_allowed(false) and not InputLogic.movement_allowed(true), "only a text field takes the movement keys")
	t.eq(InventoryScreen.click_plan(-1, 3, false), "pick", "click picks up")
	t.eq(InventoryScreen.click_plan(3, 7, true), "move", "click puts down")
	t.eq(InventoryScreen.click_plan(3, 3, false), "cancel", "click on itself puts it back")

func _telegraph_shapes(t: TestLog) -> void:
	var melee := Telegraphs.for_swing({"mode": CombatCodec.Mode.MELEE, "aim": Vector2(14, 11)}, Vector2(10, 10), Vector2(1.5, 2.5))
	t.eq(int(melee["shape"]), Telegraphs.Shape.ARC, "a melee swing telegraphs an arc")
	t.check(absf(float(melee["size"]) - (0.75 + Telegraphs.MELEE_REACH)) < 0.01, "reach from the box edge")
	var ball := Telegraphs.area_shape({"shape": SRD.AoEShape.SPHERE, "size_ft": 20, "range_ft": 150}, Vector2(0, 0), Vector2(10, 0))
	t.eq(int(ball["shape"]), Telegraphs.Shape.CIRCLE, "a sphere is a circle")
	t.eq(ball["origin"], Vector2(10, 0), "at the aim point in range")
	var cone := Telegraphs.area_shape({"shape": SRD.AoEShape.CONE, "size_ft": 15, "range_ft": 0}, Vector2(0, 0), Vector2(10, 0))
	t.eq(cone["origin"], Vector2.ZERO, "a self cone starts at the caster")
	t.check(absf(float(cone["size"]) - K.ft(15)) < 0.01, "size in tiles")

func _quick(t: TestLog) -> void:
	var q := QuickSlots.new()
	var spells := [{"slug": "fire-bolt", "name": "Fire Bolt", "level": 0, "flags": CombatCodec.SPELL_SUPPORTED | CombatCodec.SPELL_DAMAGE},
		{"slug": "light", "name": "Light", "level": 0, "flags": 0},
		{"slug": "magic-missile", "name": "Magic Missile", "level": 1, "flags": CombatCodec.SPELL_SUPPORTED}]
	t.eq(String(q.spell_for(0, spells)["slug"]), "fire-bolt", "default slot 1: the first castable spell")
	t.eq(String(q.spell_for(1, spells)["slug"]), "magic-missile", "default slot 2 skips unsupported ones")
	q.slugs = ["magic-missile", "", "", ""]
	t.eq(String(q.spell_for(1, spells)["slug"]), "fire-bolt", "assigned spells leave the defaults")
	var st := {"action": 0.0, "bonus": 0.0, "reaction": 0.0, "flags": 0, "slots": [[0, 2], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0]]}
	t.eq(QuickSlots.why_not(spells[2], st), "no slot left", "greyed: no slot")
	t.eq(QuickSlots.why_not(spells[0], st), "", "a cantrip needs none")
	t.eq(QuickSlots.why_not(spells[1], st), "not in play yet", "unsupported spells say so")
	st["action"] = 0.4
	t.eq(QuickSlots.why_not(spells[0], st), "busy", "on cooldown")

## Every screen built headless against a mirrored client (loopback host and client, every
## system), fed the state the tour feeds it.
func _screens(t: TestLog) -> void:
	var world := TileWorld.make_test(512, 128)
	var rig := Rig.new(world, 0.0)
	Systems.install_host(rig.host)
	var c := rig.add_client("ann")
	c.welcomed.connect(func(cw: ClientWorld) -> void: Systems.install_client(cw))
	var ok := rig.until(func() -> bool: return c.cw != null and c.cw.area_ready(), 6.0)
	t.check(ok >= 0.0, "client joined")
	rig.run(0.5)
	var cw := rig.cw(0)
	var rules := cw.system(HostSystem.RULES) as RulesClient
	var items := cw.system(HostSystem.ITEMS) as ItemsClient
	t.check(rules != null and items != null and cw.system(HostSystem.COMBAT) != null, "client systems installed")
	var me := rig.host_entity(0)
	var isys := rig.host.system(HostSystem.ITEMS) as ItemsSystem
	isys.give(me.id, Items.make_magic("ring-of-protection"))
	isys.give(me.id, Items.spark_item("fleet", 1))
	(rig.host.system(HostSystem.RULES) as RulesSystem).award_xp(me.id, LevelTrack.xp_for_level(5), "test")
	rig.run(0.5)
	var tree := Engine.get_main_loop() as SceneTree
	var gu := GameUi.new()
	tree.root.add_child(gu)
	gu.attach(cw, null)
	t.check(gu.hud != null, "HUD built")
	gu.hud.tick(0.1)
	gu.prompts.tick(0.1)
	for n: String in ["inventory", "choices", "constellation", "spells", "character"]:
		gu.open(n)
		var s := gu.screen(n)
		t.check(s != null and s.visible and gu.screen_open(), "%s screen opens" % n)
		gu.hud.tick(0.05)
		gu.close(n)
		t.check(not s.visible, "%s screen closes" % n)
	t.check(not gu.screen_open(), "no screen left open")
	gu.open("inventory")
	gu.open("character")
	t.check(gu.close_top() and gu.is_open("inventory") and not gu.is_open("character"), "Esc closes the top screen only")
	gu.close("inventory")
	# feed events: a level, a toast, damage, a downed state, a rest
	gu._on_leveled(6, LevelTrack.Reward.VIGOR)
	gu.toast("Picked up a thing")
	gu.toast("Picked up a thing")
	t.eq(gu.hud.toasts.get_child_count(), 1, "repeated toasts merge")
	gu.hud.combat_event({"kind": CombatCodec.Ev.CONDITION, "src": 0, "dst": cw.my_id, "cond": SRD.Condition.PRONE, "on": true})
	t.check(gu.hud.conditions.has("Prone"), "conditions on the own player are tracked")
	gu.prompts._on_rest({"event": RulesCodec.RestEv.BED_WAIT, "names": ["bex"]})
	t.eq(gu.prompts._awake, ["bex"], "who is still awake")
	var model := SheetModel.build("ann", rules.sheet, items.equipment, cw.stats, ItemText.srd())
	t.check(int(model.get("ac", 0)) >= 10 and (model.get("attacks", []) as Array).size() == 1, "sheet model: AC and an attack")
	t.eq((model.get("abilities", []) as Array).size(), 6, "six abilities")
	var inv := gu.screen("inventory") as InventoryScreen
	t.eq(InventoryScreen.doll_rects().size(), Equipment.SLOTS.size(), "the paper doll has every slot, ten rings")
	var rects: Array = InventoryScreen.doll_rects().values()
	var overl := false
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if (rects[i] as Rect2).intersects(rects[j]):
				overl = true
	t.check(not overl, "doll slots do not overlap")
	t.check(inv != null, "inventory built")
	gu.queue_free()
	tree.root.remove_child(gu)
