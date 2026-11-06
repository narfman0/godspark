## The living world's scripted tour (main.gd option world_tour=DIR, offline host with cheats,
## windowed): arrive in the spawn town, talk to a merchant, hear rumours, buy a rope and sell
## ore, take work from the keeper, the quest log and the map, a caravan on the road, a raid met
## by guards, a hand-in, a patron tier and its gift. A screenshot per beat into DIR. Scene
## setting goes through Deals' and Life's cheats or host_call; everything the player does goes
## through the client systems as a click would.
##
##   tools/soft_godot.sh --resolution 1280x720 -- offline cheats class=fighter gen=dev seed=3 \
##       world=/tmp/x world_tour=/tmp/claude-1000/godspark-m4ui timeout=400 [tour=journey]
class_name WorldTour
extends UiTour

var dc: DealsClient
var lc: LifeClient
var items: ItemsClient
var quest_id := ""

func steps() -> void:
	dc = cw.system(HostSystem.DEALS) as DealsClient
	lc = cw.system(HostSystem.LIFE) as LifeClient
	items = cw.system(HostSystem.ITEMS) as ItemsClient
	pres.rig.zoom = 1.6
	await host(func(h: WorldHost) -> void:
		var ds := h.system(HostSystem.DEALS) as DealsSystem
		var full := DealsCodec.write({"t": h.sim.t, "sites": ds.atlas_sites(), "routes": ds.atlas_routes(), "seen": [0], "all": true})
		print("TOUR atlas on join %d B, sites only %d B, %d sites, %d routes" % [full.size(),
			DealsCodec.write({"t": 0, "sites": ds.atlas_sites()}).size(), ds.atlas_sites().size(), ds.atlas_routes().size()]))
	# the arrival banner: show it again for the picture (it rose while the world loaded)
	ui.deals_ui._bannered.clear()
	ui.deals_ui._at = -1
	await wait(1.5)
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

## Later beats.
## `tour=journey` on the command line runs only the journey's beats after the arrival.
func more() -> void:
	if "tour=journey" in OS.get_cmdline_user_args():
		await journey()
		return
	await trade()
	await work()
	await road()
	await journey()
	await hand_in()
	await patron()

## What the end-to-end story walks through, as pictures: an escort beside its wagon on the road,
## raiders met at the gate, a rope down from the town's edge, stairs in a cavern, and a deep
## settlement seen from the deep road's end. Positions are scene setting (teleports).
func journey() -> void:
	var town := home_town()
	var info := {}
	pres.rig.zoom = 1.2
	await host(func(h: WorldHost) -> void:
		var life := h.system(HostSystem.LIFE) as LifeSystem
		var me := me_host(h)
		me.combatant.stats.max_hp = 900
		me.combatant.stats.current_hp = 900
		var to := -1
		for e: Array in h.sim.adj.get(town, []):
			if h.sim.settlements.has(int(e[0])):
				to = int(e[0])
				break
		var pid := life.cheat_party("caravan", town, to, 0.4, 6) if to >= 0 else -1
		info["pid"] = pid
		if pid > 0:
			var pos := life.road.party_pos(h, h.sim.parties[pid])
			info["pos"] = pos
			h.teleport(me, pos + Vector2(4.0, 3.0))
			TileCollision.depenetrate(h.world, me.body))
	print("TOUR escort party %s at %s" % [info.get("pid", -1), info.get("pos", "-")])
	await wait(5.0)
	await host(func(h: WorldHost) -> void:
		var life := h.system(HostSystem.LIFE) as LifeSystem
		var p: SimParty = h.sim.parties.get(int(info.get("pid", -1)))
		if p != null:
			var me := me_host(h)
			h.teleport(me, life.road.party_pos(h, p) + Vector2(5.0, 3.0))
			TileCollision.depenetrate(h.world, me.body))
	await wait(2.0)
	await shot("23_escort_road")
	# raiders at the gate
	await host(func(h: WorldHost) -> void:
		(h.system(HostSystem.LIFE) as LifeSystem).schedule("raid", 0.2, town)
		var me := me_host(h)
		h.teleport(me, MapLogic.site_xy(h.world.meta, town) + Vector2(4, 1))
		TileCollision.depenetrate(h.world, me.body))
	await wait(5.0)
	await host(func(h: WorldHost) -> void:
		var life := h.system(HostSystem.LIFE) as LifeSystem
		var me := me_host(h)
		for id: int in life.actors:
			var x := h.entity(id)
			if x != null and String(life.actors[id].get("role", "")) == "raider":
				h.teleport(me, x.body.pos + Vector2(5.0, 1.0))
				TileCollision.depenetrate(h.world, me.body)
				info["raider"] = x.body.pos
				break)
	print("TOUR raider at %s" % info.get("raider", "-"))
	await wait(1.5)
	await shot("24_raid_at_gate")
	# a rope near the town, the nearest stair flight below, and a deep settlement
	await host(func(h: WorldHost) -> void:
		var near := MapLogic.site_xy(h.world.meta, town)
		var rope := _tile_near(h, "rope", near, false)
		var stairs := _tile_near(h, "stairs_r", near, true)
		info["rope"] = rope
		info["stairs"] = stairs
		var deep := -1
		for sid: int in WorldSim._sorted_keys(h.sim.settlements):
			if (h.sim.settlements[sid] as SimSettlement).band != "surface":
				deep = sid
				break
		info["deep"] = deep
		if rope != Vector2i(-1, -1):
			var me := me_host(h)
			h.teleport(me, Vector2(rope.x + 0.5, rope.y)))
	print("TOUR rope %s, stairs %s, deep settlement %s" % [info.get("rope"), info.get("stairs"), info.get("deep")])
	await wait(0.8)
	await shot("25_rope_descent")
	await host(func(h: WorldHost) -> void:
		var c: Vector2i = info["stairs"]
		if c != Vector2i(-1, -1):
			var me := me_host(h)
			h.teleport(me, Vector2(c.x + 0.5, c.y + 1.0))
			TileCollision.depenetrate(h.world, me.body))
	await wait(1.5)
	await shot("26_cavern_stairs")
	await host(func(h: WorldHost) -> void:
		var sid := int(info["deep"])
		if sid >= 0:
			var me := me_host(h)
			var st: Array = Places.place(h.world, sid).get("street", [])
			var at := Vector2(float(st[0]) + 4.0, float(st[2])) if st.size() == 3 else MapLogic.site_xy(h.world.meta, sid) + Vector2(0, 2)
			h.teleport(me, at)
			TileCollision.depenetrate(h.world, me.body))
	await wait(4.0)
	await shot("27_deep_settlement")
	pres.rig.zoom = 1.6

## The cell of a tile nearest a point (in the caves and below when `deep`), or (-1, -1).
func _tile_near(h: WorldHost, tile: String, at: Vector2, deep: bool) -> Vector2i:
	var id := TileDefs.id(tile)
	var w := h.world
	var best := Vector2i(-1, -1)
	var bd := INF
	var top := int(at.y) - 30 if deep else mini(w.height - 1, int(at.y) + 40)
	for y in range(top, maxi(2, int(at.y) - 260), -1):
		for x in range(maxi(0, int(at.x) - 300), mini(w.width, int(at.x) + 300), 2):
			if w.get_fg(x, y) == id:
				var d := Vector2(x, y).distance_squared_to(at)
				if d < bd:
					bd = d
					best = Vector2i(x, y)
	return best

## The spawn town's site id and faction (from the atlas: the seen settlement nearest us).
func home_town() -> int:
	var best := -1
	var bd := INF
	for sid: int in dc.seen:
		var xy := MapLogic.site_xy(cw.world.meta, sid)
		if String(dc.sites.get(sid, {}).get("kind", "")) == "settlement" and xy.distance_to(cw.body.pos) < bd:
			bd = xy.distance_to(cw.body.pos)
			best = sid
	return best

## A caravan coming up the road (Life's cheat), seen from the road; then raiders at the gate.
func road() -> void:
	var town := home_town()
	var info := {}
	await host(func(h: WorldHost) -> void:
		var life := h.system(HostSystem.LIFE) as LifeSystem
		var me := me_host(h)
		me.combatant.stats.max_hp = 400
		me.combatant.stats.current_hp = 400
		var from := -1
		for e: Array in h.sim.adj.get(town, []):
			if h.sim.settlements.has(int(e[0])):
				from = int(e[0])
				break
		var pid := life.cheat_party("caravan", from, town, 0.8, 6) if from >= 0 else -1
		info["pid"] = pid
		if pid > 0:
			var pos := life.road.party_pos(h, h.sim.parties[pid])
			h.teleport(me, pos + Vector2(-14.0, 2.0))
			TileCollision.depenetrate(h.world, me.body))
	print("TOUR caravan party %s" % info.get("pid", -1))
	await wait(4.0)
	await shot("13_caravan")
	await host(func(h: WorldHost) -> void:
		var life := h.system(HostSystem.LIFE) as LifeSystem
		life.schedule("raid", 0.2, town)
		var me := me_host(h)
		h.teleport(me, MapLogic.site_xy(h.world.meta, town) + Vector2(10, 1))
		TileCollision.depenetrate(h.world, me.body))
	await wait(1.5)
	await shot("14_raid_coming")
	await wait(6.0)
	await shot("15_raid")
	await wait(8.0)
	await shot("16_raid_met")

## The work done (cheat) and handed in to the keeper: the celebration.
func hand_in() -> void:
	if quest_id == "":
		return
	dc.cheat({"op": "complete", "q": quest_id})
	await wait(1.0)
	for k in 15:
		await talk_role("keeper")
		if dc.talking():
			break
		await wait(2.0)
	await shot("17_hand_in_option")
	ui.deals_ui.choose("turn_in:" + quest_id)
	await wait(1.2)
	await shot("18_handed_in")

## Standing up to the first patron tier (cheat), the gift from the keeper, the standing screen.
func patron() -> void:
	var fac := String(dc.sites.get(home_town(), {}).get("faction", ""))
	dc.leave()
	await wait(0.3)
	dc.cheat({"op": "standing", "faction": fac, "n": 30})
	await wait(1.5)
	await shot("19_patron_tier")
	await talk_role("keeper")
	ui.deals_ui.choose("patron")
	await wait(1.2)
	await shot("20_patron_gift")
	dc.leave()
	await wait(0.3)
	ui.open("standing")
	await wait(0.5)
	await shot("21_standing")
	ui.close("standing")
	ui.open("help")
	await wait(0.4)
	await shot("22_help")
	ui.close("help")

## Work from the keeper: the offers in the dialogue, accepted; the log; the tracker.
func work() -> void:
	await talk_role("keeper")
	ui.deals_ui.choose("quests")
	await wait(1.0)
	await shot("08_work_offers")
	var offers: Array = dc.conversation.get("offers", [])
	var taken := ""
	for q: Dictionary in offers:
		if String(q.get("kind", "")) == "message":
			taken = String(q["id"])
	if taken == "" and not offers.is_empty():
		taken = String(offers[0]["id"])
	if taken != "":
		dc.accept(taken)
	await wait(1.0)
	quest_id = taken
	dc.leave()
	await wait(0.5)
	ui.open("quests")
	await wait(0.5)
	await shot("09_quest_log")
	ui.close("quests")
	await wait(0.4)
	await shot("10_tracker")
	ui.open("map")
	await wait(0.6)
	await shot("11_map")
	var m := ui.screen("map") as WorldMapScreen
	m.zoom_at(m._p(cw.body.center()), 1.5)
	await wait(0.3)
	var near := -1
	for sid: int in m._sites_px:
		if sid in dc.seen and (near < 0 or (m._sites_px[sid] as Vector2).distance_to(m._p(cw.body.center())) < (m._sites_px[near] as Vector2).distance_to(m._p(cw.body.center()))):
			near = sid
	var heard := -1
	for sid: int in m._sites_px:
		if not sid in dc.seen:
			heard = sid
	m.hover = heard if heard >= 0 else near
	m._card()
	m.canvas.queue_redraw()
	await wait(0.3)
	await shot("12_map_zoomed_card")
	ui.close("map")

## Buy a rope and sell ore at the merchant; the smith's rack with a tooltip.
func trade() -> void:
	dc.cheat({"op": "coin", "n": 150})
	dc.cheat({"op": "give", "base": "ore:iron", "n": 6})
	await wait(0.3)
	await talk_role("merchant")
	ui.deals_ui.choose("shop")
	await wait(1.0)
	await shot("05_shop")
	for l: Dictionary in dc.shop.get("listings", []):
		if String(l["item"].get("base", "")) == "tile:rope":
			dc.buy(String(l["id"]), 1)
	for slot: int in dc.shop.get("sell", {}):
		if String(items.item(slot).get("base", "")) == "ore:iron":
			dc.sell(slot, Items.count(items.item(slot)))
	await wait(0.35)
	await shot("06_traded")
	ui.close("shop")
	await wait(0.3)
	await talk_role("smith")
	ui.deals_ui.choose("smith")
	await wait(1.0)
	var scr := ui.screen("shop") as ShopScreen
	if scr != null and scr.goods_box.get_child_count() > 0:
		var row := scr.goods_box.get_child(0) as Control
		var ls: Array = dc.shop.get("listings", [])
		if not ls.is_empty():
			scr._tip(ls[0]["item"], row)
	await wait(0.3)
	await shot("07_smith")
	ui.close("shop")

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
	if dc.talking():
		dc.leave()
		await wait(0.4)
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
