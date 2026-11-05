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
	await fight()

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
