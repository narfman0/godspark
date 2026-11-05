## A scripted tour of the interface for verification without a human (main.gd option
## ui_tour=DIR, on an offline host with cheats). It drives the game and the UI through their
## states and saves a screenshot of each to DIR, then quits. Setting the scene (items, a
## shrine, monsters) goes to the host through session.host_call, as a test harness would;
## everything the player does goes through the client systems like a real click.
##
##   tools/soft_godot.sh -- offline cheats gen=dev seed=3 world=/tmp/x ui_tour=/tmp/shots
class_name UiTour
extends Node

var dir := ""
var main: Node
var session: NetSession
var pres: ViewPresenter
var ui: GameUi
var cw: ClientWorld
var shots: Array[String] = []
var only := ""
var fight_usec := PackedInt32Array()

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	_run.call_deferred()

func wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := dir.path_join(name + ".png")
	img.save_png(path)
	shots.append(path)
	print("TOUR shot ", path)

func host(f: Callable) -> void:
	session.host_call(f)
	await wait(0.15)

func me_host(h: WorldHost) -> HostEntity:
	for e: HostEntity in h.entities.values():
		if e.kind == HostEntity.Kind.PLAYER:
			return e
	return null

func _run() -> void:
	while pres == null or pres.ui == null or pres.cw == null or not pres.cw.area_ready():
		pres = main.get("presenter") as ViewPresenter
		await wait(0.2)
	ui = pres.ui
	cw = pres.cw
	await wait(4.0)
	await steps()
	print("TOUR done: %d shots" % shots.size())
	main.call("_quit", 0)

## The tour itself; each step leaves the screen in a state and takes a picture.
func steps() -> void:
	await shot("01_hud")
	await inventory()
	await levels()
	await constellation()
	await spells()
	ui.open("character")
	await wait(0.5)
	await shot("18_character_sheet")
	ui.close("character")
	await fight()
	await downed()
	await rests()

func place_tile(dx: int, tile: String) -> void:
	await host(func(h: WorldHost) -> void:
		var me := me_host(h)
		h.world.set_fg(floori(me.body.pos.x) + dx, floori(me.body.pos.y), TileDefs.AIR if tile == "air" else TileDefs.id(tile)))

## A shrine beside us; kindle the loose sparks; the sky with a star hovered.
func constellation() -> void:
	var items := cw.system(HostSystem.ITEMS) as ItemsClient
	await place_tile(3, "shrine")
	await wait(0.4)
	ui.open("constellation")
	await wait(0.3)
	for k in 4:
		for i in Inventory.SIZE:
			if items.item(i).has("spark"):
				items.kindle(i)
				break
		await wait(0.35)
	await give([Items.spark_item("mole", 2), Items.spark_item("owl", 0)])
	await wait(0.4)
	var scr := ui.screen("constellation") as ConstellationScreen
	scr.refresh()
	var loose := scr.loose_sparks()
	if not loose.is_empty():
		scr.chosen = loose[0]
	scr.refresh()
	var stars: Array = scr._lay.get("stars", [])
	if stars.size() > 1:
		var ev := InputEventMouseMotion.new()
		ev.position = stars[1]
		scr._sky_input(ev)
	await wait(0.3)
	await shot("14_constellation")
	ui.close("constellation")
	await place_tile(3, "air")
	pres.fx.flash_sigil()
	await wait(0.25)
	await shot("15_sigil_flash")

## The spell list with a slot assigned, then an area spell aimed in play.
func spells() -> void:
	var cc := cw.system(HostSystem.COMBAT) as CombatClient
	ui.open("spells")
	await wait(0.3)
	var area := {}
	for s: Dictionary in cc.spells:
		if int(s["flags"]) & CombatCodec.SPELL_AREA and int(s["flags"]) & CombatCodec.SPELL_SUPPORTED:
			area = s
	if not area.is_empty():
		ui.quick.assign(1, String(area["slug"]))
	var scr := ui.screen("spells") as SpellScreen
	scr.refresh()
	if not cc.spells.is_empty():
		scr._show(cc.spells[0], "")
	await wait(0.3)
	await shot("16_spells")
	ui.close("spells")
	if not area.is_empty():
		pres.rig.zoom = 2.0
		await wait(0.5)
		pres.aim_preview(area, cw.body.center() + Vector2(5, 0))
		await wait(0.2)
		await shot("17_aim_preview")
		pres.aim_preview({}, Vector2.ZERO)

## Down (death saves), then dead (the respawn prompt), then back up.
func downed() -> void:
	var rules := cw.system(HostSystem.RULES) as RulesClient
	if not rules.is_downed():
		rules.debug(RulesCodec.Debug.HURT, 999)
	var t := 0.0
	while not rules.is_downed() and t < 3.0:
		await wait(0.1)
		t += 0.1
	await wait(4.5)
	await shot("08_downed")
	rules.debug(RulesCodec.Debug.DIE, 0)
	await wait(0.8)
	await shot("09_dead")
	rules.respawn()
	await wait(1.5)

## A short rest at a placed campfire (hold E), then a bed and the night passing.
func rests() -> void:
	var rules := cw.system(HostSystem.RULES) as RulesClient
	pres.rig.zoom = 2.0
	await host(func(h: WorldHost) -> void:
		for e: HostEntity in h.entities.values().duplicate():
			if e.kind == HostEntity.Kind.MONSTER:
				h.remove_entity(e.id))
	await place_tile(2, "campfire")
	rules.debug(RulesCodec.Debug.HURT, 6)
	await wait(1.0)
	await shot("10_campfire_prompt")
	Input.action_press("interact")
	await wait(2.6)
	await shot("11_resting")
	await wait(3.0)
	Input.action_release("interact")
	await wait(0.3)
	await place_tile(-2, "bed")
	await place_tile(2, "air")
	await wait(0.6)
	await shot("12_bed_prompt")
	Input.action_press("interact")
	await wait(0.1)
	Input.action_release("interact")
	await wait(0.9)
	await shot("13_night_passes")
	await wait(3.0)

## Gain levels: the banner, the Knack cards, a class-level choice (ASI) half made.
func levels() -> void:
	var rules := cw.system(HostSystem.RULES) as RulesClient
	rules.debug(RulesCodec.Debug.LEVEL, 4)
	await wait(0.9)
	await shot("03_levelup_banner")
	ui.open("choices")
	await wait(0.5)
	await shot("04_knack_cards")
	var ch: Dictionary = rules.choices.get("knack:4", {})
	if not ch.is_empty():
		rules.pick_knack(String(ch["options"][0]["id"]))
	await wait(0.4)
	rules.debug(RulesCodec.Debug.LEVEL, 15)
	await wait(1.2)
	var scr := ui.screen("choices") as ChoicesScreen
	for k: String in rules.choices:
		if String(rules.choices[k].get("kind", "")) == "asi":
			scr.current = k
			scr.picked = ["ability-score-improvement"]
			scr.details = ["str"]
	scr.refresh()
	await wait(0.4)
	await shot("04b_choices_asi")
	ui.close("choices")

func give(list: Array) -> void:
	await host(func(h: WorldHost) -> void:
		var me := me_host(h)
		var items := h.system(HostSystem.ITEMS) as ItemsSystem
		for it: Dictionary in list:
			items.give(me.id, it))

## Fill the pack with gear (rings, magic, affixed gear, sparks), wear six rings, show a tooltip.
func inventory() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var list: Array = [Items.make_magic("ring-of-protection"), Items.make_magic("ring-of-resistance", 2),
		Items.make_magic("ring-of-swimming"), Items.make_magic("ring-of-jumping"), Items.make_magic("ring-of-warmth"),
		Items.make_magic("ring-of-feather-falling"), Items.make_magic("cloak-of-protection"), Items.make_magic("amulet-of-health"),
		Items.make_magic("boots-of-speed"), Items.make_magic("flame-tongue", 0, "scimitar"),
		{"base": "longsword", "count": 1, "material": "silver", "quality": "fine", "affixes": ["embers:2", "mole"]},
		Items.spark_item("fleet", 1), Items.spark_item("lantern", 0), Items.spark_item("skyhook", 2), Items.spark_item("dash", 0),
		Items.make("tile:stone", 120), Items.make("ingot:iron", 6), Items.make("gem", 3)]
	for i in 4:
		list.append(ItemGen.roll(rng, "", 30, "elite"))
	await give(list)
	await wait(0.5)
	var items := cw.system(HostSystem.ITEMS) as ItemsClient
	var n := 0
	for i in Inventory.SIZE:
		var it := items.item(i)
		if Items.slot_kind(it) == "ring" and n < 6:
			n += 1
			items.equip(i, "ring_%d" % n)
			await wait(0.1)
	for i in Inventory.SIZE:
		if String(items.item(i).get("magic", "")) == "cloak-of-protection":
			items.use(i)
	await wait(0.4)
	ui.open("inventory")
	await wait(0.3)
	var inv := ui.screen("inventory") as InventoryScreen
	for i in Inventory.SIZE:
		if String(items.item(i).get("base", "")) == "longsword":
			var r := InventoryScreen.grid_rect(i)
			inv._hover = i
			inv._update_tip(i, inv.panel.position + inv.grid.position + r.get_center())
			break
	inv.refresh()
	await wait(0.3)
	await shot("02_inventory")
	ui.close("inventory")

## Spawn a small pack with the reference brain next to us, swing at them, and photograph the
## numbers, the wind-up telegraphs, the nameplates and the loot.
func fight() -> void:
	var ids: Array = []
	await host(func(h: WorldHost) -> void:
		var me := me_host(h)
		for i in 3:
			var e := h.add_srd_monster("goblin-warrior", h.find_spawn(int(me.body.pos.x) + 7 + i * 3), CombatBrain.new())
			if e != null:
				ids.append(e.id)
		var items := h.system(HostSystem.ITEMS) as ItemsSystem
		if items != null:
			items.drop(me.body.pos + Vector2(-4, 2), [Items.make_magic("ring-of-protection"), Items.spark_item("fleet", 1),
				Items.make("tile:dirt", 12), Items.coin(30)]))
	pres.rig.zoom = 2.4
	await wait(1.0)
	# the monsters client stand-in: ranks and affixes as the Monsters track will send them
	if ids.size() >= 2:
		pres.fx.plates.set_info(ids[0], {"rank": "champion", "affixes": ["Frenzied", "Gilded"]})
		pres.fx.plates.set_info(ids[1], {"rank": "elite", "affixes": ["Shielded"]})
	var cc := cw.system(HostSystem.COMBAT) as CombatClient
	var t := 0.0
	var shot_tele := false
	var shot_nums := false
	fight_usec.clear()
	while t < 14.0:
		var target: ClientWorld.RemoteEntity = null
		for r: ClientWorld.RemoteEntity in cw.remotes.values():
			if r.kind != HostEntity.Kind.PLAYER and r.hp > 0 and (target == null or r.pos.distance_to(cw.body.pos) < target.pos.distance_to(cw.body.pos)):
				target = r
		if target != null and cc != null:
			cw.body.facing = 1 if target.pos.x > cw.body.pos.x else -1
			cc.attack(target.pos + Vector2(0, 1))
		if not shot_tele and pres.fx.telegraphs.active_count() > 0:
			await wait(0.25)
			await shot("05_fight_telegraph")
			shot_tele = true
		if not shot_nums and pres.fx.numbers.pool.live() >= 2:
			await shot("06_fight_numbers")
			shot_nums = true
		await wait(0.1)
		t += 0.1
		fight_usec.append_array(ui.frame_usec.slice(-6))
	await shot("07_after_fight")
