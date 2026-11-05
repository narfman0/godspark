## Monster looks reach a joining client (protocol 7: ENT_ADD carries slug, people, rank,
## scale): a debug-spawned goblin (no monsters INFO), a ranked champion, a people NPC; a
## monster whose INFO arrives before its ENT_ADD (INFO's reach is a chunk wider); and what a
## view connected after the systems (as the game connects it) is left holding. Before, the
## monsters client re-emitted actor_added inside the plain emission and the view kept the
## plain look: remote monsters drew as capsules.
extends RefCounted

const Rig := preload("res://tests/net_rig.gd")

func run(t: TestLog) -> void:
	var rig := Rig.new(TileWorld.make_test(2048, 256), 0.02)
	Systems.install_host(rig.host)
	var ms: MonstersSystem = rig.host.system(HostSystem.MONSTERS)
	ms.director_enabled = 0
	var views: Array = [{}, {}]
	var plays: Array = [[], []]
	for i in 2:
		var c := rig.add_client("p%d" % i)
		c.player_class = ["fighter", "wizard"][i]
		var k := i
		c.welcomed.connect(func(cw: ClientWorld) -> void:
			Systems.install_client(cw)
			# the view connects after the systems, as NetSession and main.gd do
			cw.actor_added.connect(func(id: int, look: Dictionary) -> void:
				views[k][id] = look
				plays[k].append(id)))
		if i == 0:
			rig.until(func() -> bool: return rig.cw(0) != null and rig.cw(0).area_ready(), 6.0)
	var sp := rig.host.spawn
	var gob := rig.host.add_srd_monster("goblin-warrior", sp + Vector2(-10, 0))
	var champ := ms.spawn("goblin-warrior", sp + Vector2(-16, 0), {"rank": "champion"})
	var npc_c: Combatant = rig.host.srd.make_npc("bandit", "human")
	var bandit := ms.spawn("bandit", sp + Vector2(12, 0), {"combatant": npc_c, "people": "human:raider", "name": "Bandit"})
	# INFO reaches a chunk further than ENT_ADD: a monster 3 chunks off is INFO'd first
	var wx := (Interest.chunk_of(sp).x + 3) * K.CHUNK + 0.3       # 3 chunks off, within INFO's 96 tiles
	var far := ms.spawn("wolf", Vector2(wx, sp.y), {"rank": "elite"})
	var ready := rig.until(func() -> bool:
		return rig.clients.all(func(c: ClientEndpoint) -> bool: return c.cw != null and c.cw.area_ready()), 8.0)
	t.check(ready >= 0.0, "both joined")
	for i in 2:
		rig.host.teleport(rig.host_entity(i), sp)
	rig.run(1.0)
	for i in 2:
		var v: Dictionary = views[i]
		t.eq(String(v.get(gob.id, {}).get("slug", "")), "goblin-warrior", "client %d: a debug-spawned goblin has its slug" % i)
		t.eq([v.get(champ.id, {}).get("slug"), v.get(champ.id, {}).get("rank"), v.get(champ.id, {}).get("scale")],
			["goblin-warrior", "champion", 1.3], "client %d: the champion's slug, rank and scale" % i)
		t.eq([v.get(bandit.id, {}).get("people"), v.get(bandit.id, {}).get("slug")], ["human:raider", "bandit"], "client %d: the bandit is a person" % i)
		var other := rig.host_entity(1 - i)
		t.eq(String(v.get(other.id, {}).get("slug", "")), "player:" + other.character.class_slug, "client %d: the other player by class" % i)
		t.eq(String(v.get(rig.cw(i).my_id, {}).get("slug", "")), "player:" + rig.host_entity(i).character.class_slug, "client %d: its own body by class" % i)
	var mc: MonstersClient = rig.cw(1).system(HostSystem.MONSTERS)
	t.check(not mc.info_of(far.id).is_empty() and not rig.cw(1).remotes.has(far.id), "the wolf: INFO known, not yet added")
	var builds: int = plays[1].count(champ.id)
	rig.host.teleport(rig.host_entity(1), sp + Vector2(K.CHUNK * 2.0, 0))
	rig.until(func() -> bool: return rig.cw(1).remotes.has(far.id), 4.0)
	rig.run(0.5)
	var wl: Dictionary = views[1].get(far.id, {})
	t.eq([wl.get("slug"), wl.get("rank")], ["wolf", "elite"], "INFO before ENT_ADD: the view keeps the wolf's full look")
	t.eq(plays[1].count(champ.id), builds, "and nobody's body was rebuilt for nothing")
