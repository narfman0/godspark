## The living world's scripted tour (main.gd option world_tour=DIR, offline host with cheats,
## windowed): arrive in the spawn town, talk to a merchant, hear rumours, buy a rope and sell
## ore, take work from the keeper, the quest log and the map, a caravan on the road, a raid met
## by guards, a hand-in, a patron tier and its gift. A screenshot per beat into DIR. Scene
## setting goes through Deals' and Life's cheats or host_call; everything the player does goes
## through the client systems as a click would.
##
##   tools/soft_godot.sh --resolution 1280x720 -- offline cheats class=fighter gen=dev seed=3 \
##       world=/tmp/x world_tour=/tmp/claude-1000/godspark-m4ui timeout=400
class_name WorldTour
extends UiTour

var dc: DealsClient
var lc: LifeClient
var items: ItemsClient

func steps() -> void:
	dc = cw.system(HostSystem.DEALS) as DealsClient
	lc = cw.system(HostSystem.LIFE) as LifeClient
	items = cw.system(HostSystem.ITEMS) as ItemsClient
	pres.rig.zoom = 1.6
	await wait(2.0)
	await shot("01_arrival")
	await talk_to("merchant")
	await shot("02_talk_prompt")
	await open_talk()
	await shot("03_dialogue")
	await talk_to("keeper")
	await talk_role("keeper")
	ui.deals_ui.choose("rumours")
	await wait(0.8)
	await shot("04_rumours")
	await more()

## Later beats (overridden as items land).
func more() -> void:
	pass

## Stand beside the nearest person of a role (Deals' goto cheat) and let the prompt settle.
func talk_to(role: String) -> void:
	if dc.talking():
		dc.leave()
		await wait(0.4)
	dc.cheat({"op": "goto", "role": role})
	await wait(1.2)
	var roles := {}
	for id: int in lc.people:
		roles[String(lc.people[id].get("role", ""))] = int(roles.get(String(lc.people[id].get("role", "")), 0)) + 1
	print("TOUR goto %s: note %s, people %s, sim_t %d" % [role, dc.last_note.get(DealsCodec.Msg.CHEAT, "?"), roles, dc.sim_t])
	if ui.deals_ui.target != 0:
		var r: ClientWorld.RemoteEntity = cw.remotes.get(ui.deals_ui.target)
		if r != null:
			cw.body.facing = 1 if r.pos.x > cw.body.pos.x else -1

## E, as the player presses it.
func open_talk() -> void:
	Input.action_press("interact")
	await wait(0.15)
	Input.action_release("interact")
	var t := 0.0
	while not dc.talking() and t < 3.0:
		await wait(0.1)
		t += 0.1
	await wait(0.4)

## Talk to the nearest person of a role (the tour's stand-in for walking up to them).
func talk_role(role: String) -> void:
	var best := 0
	var bd := INF
	for id: int in lc.people:
		var r: ClientWorld.RemoteEntity = cw.remotes.get(id)
		if r != null and String(lc.people[id].get("role", "")) == role and bool(lc.people[id].get("talk", false)):
			var d := r.pos.distance_to(cw.body.pos)
			if d < bd:
				bd = d
				best = id
	if best != 0:
		var target := best
		await host(func(h: WorldHost) -> void:
			var x := h.entity(target)
			var me := me_host(h)
			if x != null and me != null:
				h.teleport(me, x.body.pos + Vector2(1.6, 0.0))
				TileCollision.depenetrate(h.world, me.body))
		await wait(0.5)
		dc.talk(best)
	var t := 0.0
	while not dc.talking() and t < 3.0:
		await wait(0.1)
		t += 0.1
	print("TOUR talk %s (%d, %.1f tiles): %s" % [role, best, bd, "open" if dc.talking() else String(dc.last_note.get(DealsCodec.Msg.TALK_TO, "?"))])
	await wait(0.4)
