## The M4 interface (headless: logic, not pixels): the words and decisions behind the dialogue,
## shop, quest log, map and standing screens; input routing with a conversation open; the
## atlas on the wire; and every new screen built against a mirrored client (loopback host and
## client, every system, a generated world with towns and people).
extends RefCounted

const Rig := preload("res://tests/net_rig.gd")

func run(t: TestLog) -> void:
	Items.ensure()
	_people_words(t)
	_prices(t)
	_quests(t)
	_standing(t)
	_bearing(t)
	_input(t)
	_live(t)

func _people_words(t: TestLog) -> void:
	t.eq(DealsLogic.talk_prompt({"name": "Dunton", "role": "merchant"}), "E: talk to Dunton, merchant", "talk prompt")
	t.eq(DealsLogic.talk_prompt({"name": "Dunton the Merchant", "role": "merchant"}), "E: talk to Dunton the Merchant", "the role once")
	t.eq(DealsLogic.person_label({"name": "Ada", "role": "keeper"}), "Ada, innkeeper", "keeper reads as innkeeper")
	var p := {"talk": true, "kind": "settlement", "role": "merchant", "of": 4, "faction": "2"}
	t.eq(DealsLogic.role_mark(p, [], {}, {}), "shop", "a merchant sells")
	t.eq(DealsLogic.role_mark(p, [], {"work": ["merchant"]}, {}), "work", "work on offer beats the shop")
	var ready := [{"site": 4, "giver": "merchant", "state": "ready", "kind": "escort"}]
	t.eq(DealsLogic.role_mark(p, ready, {"work": ["merchant"]}, {}), "turn_in", "work to hand in beats everything")
	var k := {"talk": true, "kind": "settlement", "role": "keeper", "of": 4, "faction": "2"}
	t.eq(DealsLogic.role_mark(k, [], {}, {"2": {"tier": 1, "suspended": false}}), "patron", "a patron's keeper")
	t.eq(DealsLogic.role_mark(k, [], {}, {"2": {"tier": 1, "suspended": true}}), "", "a suspended patron shows nothing")
	t.eq(DealsLogic.role_mark({"talk": false, "kind": "settlement", "role": "merchant"}, [], {}, {}), "", "no mark on who will not talk")
	t.eq(DealsLogic.party_plate("caravan", "the Tarnby League", "Marstead", ""), "Caravan of the Tarnby League, bound for Marstead", "caravan plate")
	t.eq(DealsLogic.party_plate("raid", "the Web of Phyxquor", "Marstead", ""), "Raiders of the Web of Phyxquor", "raiders keep their aim to themselves")
	t.eq(DealsLogic.place_line({"culture": "halfling", "tier": "town", "pop": 633}), "a halfling town of 633 souls", "place line")
	t.eq(DealsLogic.place_line({"culture": "elf", "tier": "village", "pop": 90}), "an elf village of 90 souls", "an before vowels")
	t.eq(DealsLogic.state_line({"state": ["hungry", "war"]})[0], "Hungry", "the most pressing state")
	t.eq(DealsLogic.state_line({})[0], "Quiet", "no state: quiet")
	t.eq(DealsLogic.rumour_parts("Year 1, spring: first caravan arrives"), ["Year 1, spring", "First caravan arrives"], "rumour date split")
	t.eq(DealsLogic.rumour_parts("plain news"), ["", "plain news"], "no date")

func _prices(t: TestLog) -> void:
	var food := Items.make("trade:luxuries", 1)
	var v := float(Items.value(food))
	var cheap := {"item": food, "n": 10, "price": roundi(v * 1.25 * 0.6)}
	var sword := Items.make("longsword", 1)
	var dear := {"item": sword, "n": 2, "price": roundi(float(Items.value(sword)) * 1.25 * 2.0)}
	t.eq(DealsLogic.listing_ratio({"item": Items.make("torch", 1), "n": 5, "price": 2}, DealsLogic.price_mods(0, false, 0)), -1.0,
		"a two-coin torch says nothing about the market")
	var none := DealsLogic.price_mods(0, false, 0)
	t.check(DealsLogic.listing_ratio(cheap, none) <= 0.8, "cheap food reads cheap")
	var mood := DealsLogic.price_mood([cheap, dear], none)
	t.check(mood.contains("Plentiful") and mood.contains("Scarce"), "price mood names plenty and scarcity (%s)" % mood)
	var liked := DealsLogic.price_mods(50, true, 1)
	var m2 := DealsLogic.price_mood([], liked)
	t.check(m2.contains("10% off") and m2.contains("Bond") and m2.contains("patron"), "standing, Bond and patron in the mood (%s)" % m2)
	t.check(DealsLogic.price_mood([], DealsLogic.price_mods(-40, false, 0)).contains("8% on"), "disliked: dearer")
	t.check(DealsLogic.price_mood([], none).contains("Fair"), "nothing to say: fair")
	t.check(DealsLogic.price_mood([], none, "smith").contains("bare"), "an empty rack says why")
	t.check(DealsLogic.purse_line(100, 600).contains("poor town"), "a poor town pays little")
	t.check(DealsLogic.purse_line(4000, 600).contains("rich"), "a rich town pays well")
	t.check(DealsLogic.purse_line(1000, 100).contains("250"), "one sale's cap is a quarter of the purse")
	t.check(DealsLogic.thin_line([], {"state": ["hungry"]}, "store").contains("hungry"), "thin shelves from hunger")
	t.eq(DealsLogic.thin_line([{"n": 20}], {"state": ["hungry"]}, "store"), "", "full shelves need no excuse")

func _quests(t: TestLog) -> void:
	t.eq(DealsLogic.time_left(100, 52.0), "2 days left", "days left")
	t.eq(DealsLogic.time_left(100, 90.5), "10 hours left", "hours left")
	t.eq(DealsLogic.time_left(100, 101.0), "out of time", "overdue")
	t.eq(DealsLogic.time_left(100, 78.0), "a day left", "about a day")
	var q := {"state": "active", "progress": {"have": 3, "need": 5, "text": ""}, "kind": "bounty", "title": "Clear the den"}
	t.eq(DealsLogic.progress_text(q), "3 of 5", "progress from counts")
	t.check(is_equal_approx(DealsLogic.progress_frac(q), 0.6), "progress fraction")
	q["progress"]["text"] = "4 of 8 with the caravan"
	t.eq(DealsLogic.progress_text(q), "4 of 8 with the caravan", "the host's progress words win")
	t.eq(DealsLogic.reward_text({"coin": 12, "standing": 3, "xp": 50, "item": true}), "12 coin, +3 standing, 50 XP, and something from the smith", "reward words")
	t.check(DealsLogic.abandon_text({"kind": "escort"}).contains("-4"), "abandoning an escort costs standing")
	t.check(DealsLogic.abandon_text({"kind": "message"}).contains("no hard"), "abandoning a message costs nothing")
	t.eq(DealsLogic.section_of({"state": "ready"}), "active", "ready work is active")
	t.eq(DealsLogic.section_of({"state": "lapsed"}), "ended", "lapsed is ended")
	t.check(DealsLogic.outcome_note({"state": "beaten", "title": "X"}, "active").contains("first"), "beaten: someone got there first")
	t.eq(DealsLogic.outcome_note({"state": "active"}, "active"), "", "no change, no note")

func _standing(t: TestLog) -> void:
	t.eq(DealsLogic.tier_of(24), 0, "under the first tier")
	t.eq(DealsLogic.tier_of(25), 1, "tier 1 at 25")
	t.eq(DealsLogic.tier_of(80), 3, "tier 3 at 75")
	t.eq(DealsLogic.guards_word(-40), "hostile", "guards hostile at -40")
	t.eq(DealsLogic.guards_word(0), "wary", "wary in between")
	t.eq(DealsLogic.guards_word(30), "friendly", "friendly from 30")
	t.check(DealsLogic.standing_toast(10, 13), "a move of 3 toasts")
	t.check(not DealsLogic.standing_toast(10, 11), "a point does not")
	t.check(DealsLogic.standing_toast(24, 25), "crossing a tier does")
	t.eq(DealsLogic.standing_word(-50), "Hated", "hated")
	t.eq(DealsLogic.standing_word(0), "A stranger", "a stranger")

func _bearing(t: TestLog) -> void:
	var b := DealsLogic.bearing(Vector2(100, 200), Vector2(300, 200))
	t.check(is_equal_approx(float(b["dist"]), 200.0) and String(b["text"]) == "200 east", "bearing east (%s)" % b["text"])
	t.check(is_equal_approx(float(b["angle"]), 0.0), "east points right")
	var d := DealsLogic.bearing(Vector2(100, 200), Vector2(80, 150))
	t.eq(String(d["text"]), "20 west, 50 below", "west and below (y is up in the world)")
	t.check(float(d["angle"]) > 0.0, "below points down the screen")
	t.eq(String(DealsLogic.bearing(Vector2(1, 1), Vector2(2, 2))["text"]), "here", "here")

func _input(t: TestLog) -> void:
	t.check(InputLogic.hotbar_keys_allowed(false, false), "number keys pick slots normally")
	t.check(not InputLogic.hotbar_keys_allowed(false, true), "not while a conversation takes them")
	t.check(not InputLogic.hotbar_keys_allowed(true, false), "not while typing")
	t.check(InputLogic.movement_allowed(false), "movement keys still work with a conversation open")
	t.eq(DealsLogic.option_index(KEY_1), 0, "1 is the first option")
	t.eq(DealsLogic.option_index(KEY_9), 8, "9 the ninth")
	t.eq(DealsLogic.option_index(KEY_0), -1, "0 is not an option (it leaves)")
	t.eq(DealsLogic.option_index(KEY_E), -1, "letters are not options")

## A generated world over the loopback: the atlas arrives, people show, a conversation opens
## and the dialogue takes the number keys; the new screens build.
func _live(t: TestLog) -> void:
	var world := WorldGen.generate(1024, 512, 4)
	var rig := Rig.new(world, 0.0)
	Systems.install_host(rig.host)
	var ms: Variant = rig.host.system(HostSystem.MONSTERS)
	if ms != null:
		ms.set("director_enabled", 0)
		ms.set("lairs_enabled", false)
	var c := rig.add_client("ann")
	c.welcomed.connect(func(cw: ClientWorld) -> void: Systems.install_client(cw))
	var ok := rig.until(func() -> bool: return c.cw != null and c.cw.area_ready(), 10.0)
	t.check(ok >= 0.0, "client joined the generated world")
	var cw := rig.cw(0)
	var dc := cw.system(HostSystem.DEALS) as DealsClient
	var lc := cw.system(HostSystem.LIFE) as LifeClient
	rig.until(func() -> bool: return lc.people.size() > 4, 6.0)
	t.check(not dc.sites.is_empty(), "the atlas arrived: %d sites" % dc.sites.size())
	t.check(not dc.routes.is_empty() and not (dc.routes[0]["path"] as Array).is_empty(), "route paths arrived")
	var named := 0
	for sid: int in dc.sites:
		if String(dc.sites[sid].get("kind", "")) == "settlement" and dc.site_name(sid) != "":
			named += 1
	t.check(named > 0, "settlements have names (%d)" % named)
	rig.run(1.5)
	t.check(not dc.seen.is_empty(), "the spawn town counts as seen")
	t.check(lc.people.size() > 4, "Life shows the town's people (%d)" % lc.people.size())
	var tree := Engine.get_main_loop() as SceneTree
	var gu := GameUi.new()
	tree.root.add_child(gu)
	gu.attach(cw, null)
	t.check(gu.deals_ui != null and gu.marks != null, "DealsUi and the people marks built")
	var who := 0
	for id: int in lc.people:
		if bool(lc.people[id].get("talk", false)) and cw.remotes.has(id):
			who = id
			break
	t.check(who != 0, "someone to talk to")
	var me := rig.host_entity(0)
	var x := rig.host.entity(who)
	if x != null:
		me.body.pos = x.body.pos + Vector2(1.5, 0)
		TileCollision.depenetrate(rig.host.world, me.body)
		rig.host.teleport(me, me.body.pos)
	rig.run(0.6)
	gu.prompts.tick(0.05)
	t.check(gu.deals_ui.target != 0, "the talk prompt finds a person within reach")
	dc.talk(who)
	rig.until(func() -> bool: return dc.talking(), 3.0)
	t.check(dc.talking() and gu.deals_ui.dialogue.visible, "talking: the dialogue shows")
	t.check(gu.number_keys_taken(), "the number keys belong to the dialogue")
	t.check(not gu.screen_open(), "the dialogue is not a screen: the world keeps its clicks")
	t.check(gu.deals_ui.dialogue.opts.get_child_count() >= 2, "options as buttons")
	var ev := InputEventKey.new()
	ev.keycode = KEY_1
	ev.pressed = true
	t.check(gu.deals_ui.input(ev), "1 picks the first option")
	rig.until(func() -> bool: return String(dc.conversation.get("view", "")) == "rumours", 3.0)
	t.eq(String(dc.conversation.get("view", "")), "rumours", "the first option is the news")
	var ev0 := InputEventKey.new()
	ev0.keycode = KEY_0
	ev0.pressed = true
	t.check(gu.deals_ui.input(ev0), "0 leaves")
	rig.until(func() -> bool: return not dc.talking(), 3.0)
	t.check(not dc.talking() and not gu.deals_ui.dialogue.visible, "the conversation ends and the panel goes")
	t.check(not gu.number_keys_taken(), "number keys back to the hotbar")
	_screens(t, gu, rig)
	gu.queue_free()
	tree.root.remove_child(gu)

## Every new screen opens and closes headless (filled in as the screens land).
func _screens(t: TestLog, gu: GameUi, rig: Rig) -> void:
	for n: String in ["shop", "quests", "map", "standing", "help"]:
		if not gu.factories.has(n):
			continue
		gu.open(n)
		var s := gu.screen(n)
		t.check(s != null and s.visible, "%s screen opens" % n)
		rig.run(0.1)
		gu.hud.tick(0.05)
		gu.close(n)
		t.check(not s.visible, "%s screen closes" % n)
