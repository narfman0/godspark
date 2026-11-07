## Pictures of combat for verification without a human (main.gd option combat_tour=DIR, on an
## offline host with cheats and host_thread=0, windowed). The host ticks in the render loop, so
## Engine.time_scale slows the whole game and a software renderer can catch a 60 ms moment.
## Setting the scene (where a goblin stands, its AC) goes to the host through session.host_call;
## what the player does goes through the keys and the combat client.
##
##   tools/soft_godot.sh -- offline cheats gen=dev seed=3 world=/tmp/cf pack=goblin-warrior \
##       host_thread=0 combat_tour=DIR [combat_zoom=3.5] [combat_weapon=greataxe]
class_name CombatTour
extends Node

const SLOW := 0.12

var dir := ""
var main: Node
var session: NetSession
var pres: ViewPresenter
var cw: ClientWorld
var cc: CombatClient
var foe_id := 0
var shots := 0
var _events: Array = []

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	_run.call_deferred()

func wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout

func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	shots += 1
	print("TOUR shot ", name)

func _host(f: Callable) -> void:
	session.host_call(f)
	await wait(0.2)

func _foe(h: WorldHost) -> HostEntity:
	var best: HostEntity = null
	for e: HostEntity in h.entities.values():
		if not e.is_player() and e.combatant != null and String(e.look.get("slug", "")) != "" and (best == null or e.id < best.id):
			best = e
	return best

## The foe stands `dx` tiles from the hero, has no brain and this armour class.
func _stage(dx: float, ac: int) -> void:
	var f := func(h: WorldHost) -> void:
		var hero := cw.my_id
		var me := h.entity(hero)
		var foe := _foe(h)
		foe_id = foe.id
		foe.brain = null
		foe.body.pos = h.find_spawn(int(me.body.pos.x + dx))
		foe.body.pos.x = me.body.pos.x + dx
		foe.combatant.stats.max_hp = 500
		foe.combatant.stats.current_hp = 500
		foe.combatant.bonus_ac = 0
		foe.combatant.bonus_ac = ac - foe.combatant.armor_class
		for o: HostEntity in h.entities.values():
			if o != foe and not o.is_player() and o.combatant != null and String(o.look.get("slug", "")) != "":
				o.brain = null
				o.body.pos.x = me.body.pos.x + 300.0
	await _host(f)
	await wait(0.4)

func _aim() -> Vector2:
	return pres.fx.actor_center(foe_id)

func _run() -> void:
	while pres == null or pres.ui == null or pres.cw == null or not pres.cw.area_ready():
		pres = main.get("presenter") as ViewPresenter

		await wait(0.3)
	cw = pres.cw
	cc = cw.system(HostSystem.COMBAT) as CombatClient
	cc.event.connect(func(ev: Dictionary) -> void: _events.append(ev))
	print("TOUR ready, %d fps" % Engine.get_frames_per_second())
	await wait(3.0)
	var opts: Dictionary = main.get("opts")
	if opts.has("combat_weapon"):
		var slug := String(opts["combat_weapon"])
		session.host_call(func(h: WorldHost) -> void:
			var e := h.entity(cw.my_id)
			e.character.equipment.put("main_hand", Items.make(slug))
			e.character.equipment.changed["main_hand"] = true
			var ms: Variant = h.system(HostSystem.ITEMS)
			ms.call("outfit", e))
		await wait(0.5)
	pres.rig.zoom = float(main.get("opts").get("combat_zoom", 3.5))
	await _stage(3.2, 1)
	print("TOUR staged, %d fps, foe %d" % [Engine.get_frames_per_second(), foe_id])
	pres.fx.aim_override = _aim()
	await wait(0.6)
	await shot("01_target")
	await _contact("02_swing_contact", 1)
	await _result("03_hit", CombatCodec.Ev.DAMAGE, 1)
	await _result("04_miss", CombatCodec.Ev.MISS, 40)
	await _result("05_crit", CombatCodec.Ev.CRIT, 1)
	await _roll()
	await _telegraph()
	await _running()
	await _cast()
	print("TOUR done: %d shots" % shots)
	main.call("_quit", 0)

func _wait_free() -> void:
	Engine.time_scale = 1.0
	await wait(0.9)

## The own swing at its contact: from the SWING, the layer's clock reaches the wind-up.
func _contact(name: String, ac: int) -> void:
	await _stage(3.2, ac)
	await _wait_free()
	pres.fx.aim_override = _aim()
	Engine.time_scale = SLOW
	var windup := -1.0
	_events.clear()
	cc.attack(_aim())
	var a := pres.view.get_actor(cw.my_id)
	for i in 400:
		await get_tree().process_frame
		for ev: Dictionary in _events:
			if int(ev["kind"]) == CombatCodec.Ev.SWING:
				windup = float(ev["windup"])
		if windup > 0.0 and a.kind == "synty" and (a.visual as CharacterVisual).layer.t >= windup - 0.02:
			break
	await shot(name)
	print("TOUR %s: windup %.2f layer t %.3f" % [name, windup, (a.visual as CharacterVisual).layer.t if a.kind == "synty" else -1.0])
	Engine.time_scale = 1.0

## Swing until an event of `kind` names the foe, then the picture on the next frames.
func _result(name: String, kind: int, ac: int) -> void:
	await _stage(3.2, ac)
	pres.fx.aim_override = _aim()
	for tries in 200:
		await _wait_free()
		Engine.time_scale = SLOW
		_events.clear()
		cc.attack(_aim())
		for i in 90:
			await get_tree().process_frame
			if _events.any(func(ev: Dictionary) -> bool: return int(ev["kind"]) == kind and (int(ev["src"]) == cw.my_id or kind == CombatCodec.Ev.DAMAGE and int(ev["dst"]) == foe_id)):
				var av := pres.view.get_actor(cw.my_id)
				print("TOUR %s layer t %.3f" % [name, (av.visual as CharacterVisual).layer.t if av.kind == "synty" else -1.0])
				await frames(1)
				await shot(name)
				print("TOUR %s after %d swings: %s" % [name, tries + 1, _events.map(func(ev: Dictionary) -> String: return CombatCodec.describe(ev))])
				Engine.time_scale = 1.0
				return
			if _events.any(func(ev: Dictionary) -> bool: return int(ev["kind"]) in [CombatCodec.Ev.HIT, CombatCodec.Ev.MISS, CombatCodec.Ev.CRIT] and int(ev["src"]) == cw.my_id):
				break
	print("TOUR %s: no such event" % name)
	Engine.time_scale = 1.0

func _roll() -> void:
	await _stage(4.0, 1)
	await _wait_free()
	pres.fx.aim_override = _aim()
	Engine.time_scale = SLOW
	await frames(1)     # a key pressed here counts as pressed in this very frame
	Input.action_press("dodge")
	await frames(1)
	Input.action_release("dodge")
	for i in 200:
		await get_tree().process_frame
		if cw.body.roll_t >= Dodge.duration() * 0.45:
			break
	await shot("06_roll_middle")
	print("TOUR roll: t %.3f hurt box %s" % [cw.body.roll_t, Dodge.hurt_rect(cw.body.rect(), cw.body.roll_t)])
	Engine.time_scale = 1.0

## A goblin's blow half a second out, and just before it lands.
func _telegraph() -> void:
	await wait(1.0)
	await _stage(2.6, 1)
	await _wait_free()
	pres.fx.aim_override = _aim()
	Engine.time_scale = SLOW
	_events.clear()
	var hero := cw.my_id
	session.host_call(func(h: WorldHost) -> void:
		var combat := h.system(HostSystem.COMBAT) as CombatSystem
		var foe := h.entity(foe_id)
		combat.now = h.tick_count / float(K.TICK_HZ)
		combat.start_attack(foe, -1, h.entity(hero).body.rect().get_center()))
	var a := pres.view.get_actor(foe_id)
	var seen := false
	for i in 300:
		await get_tree().process_frame
		if not seen and _events.any(func(ev: Dictionary) -> bool: return int(ev["kind"]) == CombatCodec.Ev.SWING):
			seen = true
			await frames(1)
			await shot("07_telegraph_early")
			print("TOUR telegraph early: %s" % str(pres.fx.windups))
		if seen and pres.fx.windups.has(foe_id) and float(pres.fx.windups[foe_id][0]) >= 0.42:
			await shot("08_telegraph_late")
			print("TOUR telegraph late: %s layer %s" % [str(pres.fx.windups), a.kind])
			break
	Engine.time_scale = 1.0

## The first spell a caster has, if it has one.
func _cast() -> void:
	var sp := cc.spell_slot(0)
	if sp.is_empty():
		return
	await _stage(6.0, 1)
	await _wait_free()
	Engine.time_scale = SLOW
	_events.clear()
	cc.cast(String(sp["slug"]), int(sp["level"]), _aim())
	for i in 300:
		await get_tree().process_frame
		if _events.any(func(ev: Dictionary) -> bool: return int(ev["kind"]) == CombatCodec.Ev.SWING):
			break
	await frames(40)
	await shot("10_cast")
	Engine.time_scale = 1.0

## Running while swinging: the legs under the blow.
func _running() -> void:
	await _stage(9.0, 1)
	await _wait_free()
	Input.action_press("move_right")
	await wait(0.45)
	Engine.time_scale = SLOW
	pres.fx.aim_override = _aim()
	cc.attack(_aim())
	var a := pres.view.get_actor(cw.my_id)
	for i in 200:
		await get_tree().process_frame
		if a.kind == "synty" and (a.visual as CharacterVisual).layer.t >= 0.16:
			break
	await shot("09_swing_running")
	Input.action_release("move_right")
	Engine.time_scale = 1.0
