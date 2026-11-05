## M2 end to end: every system installed, two players over the loopback on a small generated
## world play the whole M2 loop and every side agrees. A fighter and a wizard fight a ranked
## pack (the director's own spawn path) with attack and spell intents; XP and levels, loot
## picked up, a weapon equipped that the next attack uses, a ring bonded at a campfire, a
## spark kindled at a shrine (host and client MoveStats identical), a short rest on Hit Point
## Dice, a long rest in bed that passes the night, a player downed by a monster, hit while
## down (a failed death save), revived by the other; then save, stop, load, rejoin, and all
## of it persisted. Each failure here was an integration bug (docs/tracks/m2-integration.md).
extends RefCounted

const Rig := preload("res://tests/net_rig.gd")
const Ev := CombatCodec.Ev
const Down := RulesCodec.Down
const SAVE_DIR := "user://test_m2_e2e"

var t: TestLog
var rig: Rig
var floor_y := 0
var cx := 0
## Per client: events described, ids whose HP was seen at 0, rest events, downed events.
var seen: Array = [[], []]
var zero_hp: Array = [{}, {}]
var rests: Array = [[], []]
var downs: Array = [[], []]
var levels: Array = [[], []]
var xp_in: Array = [0, 0]
var gone_drops: Array = [[], []]
var kit_count := 0

func run(t_: TestLog) -> void:
	t = t_
	var world := _arena_world()
	rig = Rig.new(world, 0.03)
	Systems.install_host(rig.host)
	var ms: MonstersSystem = rig.host.system(HostSystem.MONSTERS)
	ms.director_enabled = 0               # the story spawns its own packs
	ms.lairs_enabled = false
	var rules: RulesSystem = rig.host.system(HostSystem.RULES)
	rules.xp_rate = 10.0
	_join(["ann", "bob"], ["fighter", "wizard"])
	var ok := _ready()
	t.check(ok, "both players joined with every system")
	if not ok:
		return
	kit_count = _bag_count(0)
	_fight(t)
	_loot_and_gear(t)
	_spark(t)
	_mirrors(t)
	_rests(t)
	_downed(t)
	_persist(t)

# --- setup ---------------------------------------------------------------------------------

## A generated world (dev-sized, seed 5) with a flat open arena dug at the middle of the
## surface: 118 columns between stone walls, floor of dirt, 16 rows of air above.
func _arena_world() -> TileWorld:
	var w := WorldGen.generate(1024, 512, 5)
	cx = w.width / 2
	var surf: Array = w.meta.get("surface", [])
	floor_y = int(surf[cx]) if surf.size() == w.width else w.height / 2
	for x in range(cx - 60, cx + 60):
		for y in range(floor_y - 4, floor_y):
			w.set_fg(x, y, TileDefs.id("dirt"))
		for y in range(floor_y, floor_y + 16):
			w.set_fg(x, y, TileDefs.AIR)
			w.set_bg(x, y, 0)
	# walls at both ends: nobody chases or flees off into the caves
	for x in [cx - 61, cx - 60, cx + 59, cx + 60]:
		for y in range(floor_y, floor_y + 16):
			w.set_fg(x, y, TileDefs.id("stone"))
	return w

func _join(names: Array, classes: Array) -> void:
	for i in names.size():
		var c := rig.add_client(names[i])
		c.player_class = classes[i]
		var k := i
		c.welcomed.connect(func(cw: ClientWorld) -> void: _install(cw, k))

func _install(cw: ClientWorld, i: int) -> void:
	Systems.install_client(cw)
	var cc: CombatClient = cw.system(HostSystem.COMBAT)
	cc.event.connect(func(ev: Dictionary) -> void:
		seen[i].append(CombatCodec.describe(ev))
		if int(ev["kind"]) == Ev.DAMAGE and int(ev.get("hp", 1)) <= 0:
			zero_hp[i][int(ev["dst"])] = true)
	var rc: RulesClient = cw.system(HostSystem.RULES)
	rc.rest_event.connect(func(ev: Dictionary) -> void: rests[i].append(ev))
	rc.downed_changed.connect(func(id: int, st: int, s: int, f: int) -> void: downs[i].append([id, st, s, f]))
	rc.leveled.connect(func(lv: int, _r: int) -> void: levels[i].append(lv))
	rc.xp_gained.connect(func(n: int, _s: String) -> void: xp_in[i] += n)
	var ic: ItemsClient = cw.system(HostSystem.ITEMS)
	ic.drop_removed.connect(func(id: int, by: int) -> void: gone_drops[i].append([id, by]))

func _ready() -> bool:
	return rig.until(func() -> bool:
		for i in rig.clients.size():
			var c := rig.cw(i)
			if c == null or not c.area_ready() or rc(i) == null or rc(i).sheet.is_empty():
				return false
		return true, 10.0) >= 0.0

func he(i: int) -> HostEntity:
	return rig.host_entity(i)

func cc(i: int) -> CombatClient:
	return rig.cw(i).system(HostSystem.COMBAT) if rig.cw(i) != null else null

func rc(i: int) -> RulesClient:
	return rig.cw(i).system(HostSystem.RULES) if rig.cw(i) != null else null

func ic(i: int) -> ItemsClient:
	return rig.cw(i).system(HostSystem.ITEMS) if rig.cw(i) != null else null

func sys(id: int) -> HostSystem:
	return rig.host.system(id)

## Put player i at column x on the arena floor (host teleport; the client follows the CORRECT).
func place(i: int, x: float) -> void:
	rig.host.teleport(he(i), Vector2(x, floor_y))
	rig.run(0.2)

func monsters_alive() -> Array:
	var out := []
	for e: HostEntity in rig.host.entities.values():
		if not e.is_player():
			out.append(e)
	return out

func idle() -> void:
	for i in rig.inputs.size():
		rig.inputs[i] = PlayerInput.new()

# --- the fight ----------------------------------------------------------------------------------

func _fight(t: TestLog) -> void:
	place(0, cx + 2.0)
	place(1, cx + 8.0)
	for i in 2:
		var c := he(i).combatant
		c.stats.max_hp = 400
		c.stats.current_hp = 400
	var ms: MonstersSystem = sys(HostSystem.MONSTERS)
	var pack := ms.director.spawn_pack([
		{"slug": "goblin-warrior", "rank": "champion", "leader": true},
		{"slug": "goblin-warrior", "rank": "standard", "leader": false},
		{"slug": "goblin-warrior", "rank": "minion", "leader": false},
		{"slug": "goblin-warrior", "rank": "minion", "leader": false}], Vector2(cx - 14.0, floor_y))
	t.eq(pack.size(), 4, "the director's path spawned a pack of four")
	var ranks := pack.map(func(e: HostEntity) -> String: return String(e.get_meta("rank", "")))
	t.eq(ranks, ["champion", "standard", "minion", "minion"], "with ranks")
	var ids := pack.map(func(e: HostEntity) -> int: return e.id)
	var lvl0 := [he(0).character.level, he(1).character.level]
	var slots0 := _slots_used(1)
	var casts := 0
	var mm := false
	var took := rig.until(func() -> bool:
		rig.inputs[0] = cc(0).fight_step(PlayerInput.new())
		var target := _nearest_remote(1)
		var gap := he(0).body.pos.x - rig.cw(1).body.pos.x       # the wizard keeps up with the fighter
		rig.inputs[1] = PlayerInput.new()
		rig.inputs[1].move_x = signf(gap) if absf(gap) > 10.0 else 0.0
		if target != null and cc(1).can_attack():
			var aim: Vector2 = rig.cw(1).sample_remote(target.id).get("pos", target.pos) + Vector2(0, 1.0)
			if not mm:
				mm = cc(1).cast("magic-missile", 1, aim)
			elif cc(1).cast("fire-bolt", 0, aim):
				casts += 1
		return monsters_alive().is_empty(), 90.0)
	idle()
	rig.run(1.0)
	for m: HostEntity in monsters_alive():
		print("  left: %s %s at %s hp %s (players at %s, %s)" % [m.name, m.get_meta("rank", ""), m.body.pos, m.vitals(), he(0).body.pos, he(1).body.pos])
	t.check(took >= 0.0, "the pack is dead (%.1f s, %d monsters left)" % [took, monsters_alive().size()])
	for i in 2:
		t.check(seen[i].any(func(s: String) -> bool: return s.begins_with("SWING")), "client %d saw swings" % i)
		t.check(seen[i].any(func(s: String) -> bool: return s.begins_with("DAMAGE")), "client %d saw damage" % i)
		t.check(ids.all(func(id: int) -> bool: return zero_hp[i].has(id)), "client %d saw every pack member reach 0 HP" % i)
		t.check(ids.all(func(id: int) -> bool: return not rig.cw(i).remotes.has(id)), "client %d removed them" % i)
		t.check(xp_in[i] > 0, "client %d got XP (%d)" % [i, xp_in[i]])
	t.eq(seen[0].filter(func(s: String) -> bool: return s.begins_with("DEATH")).size(),
		seen[1].filter(func(s: String) -> bool: return s.begins_with("DEATH")).size(), "both saw the same deaths")
	t.check(ids.all(func(id: int) -> bool: return not rig.host.entities.has(id)), "the host removed them")
	t.check(seen[1].any(func(s: String) -> bool: return s.begins_with("SWING %d>" % he(1).id)), "the wizard cast (%d fire bolts, magic missile %s)" % [casts, mm])
	for i in 2:
		t.check(he(i).character.level > lvl0[i], "player %d levelled on the host (%d -> %d)" % [i, lvl0[i], he(i).character.level])
		t.check(not levels[i].is_empty() and int(rc(i).sheet.get("level", 0)) == he(i).character.level, "client %d heard the level (%s)" % [i, levels[i]])
		t.eq(int(rc(i).sheet.get("xp", -1)), he(i).character.xp, "client %d XP matches the host" % i)
	t.check(he(0).character.deeds.get("kill", 0) >= 4, "kill deeds counted (%s)" % he(0).character.deeds.get("kill", 0))
	var used := _slots_used(1)
	t.check(used > slots0, "magic missile spent a slot on the host (%d -> %d)" % [slots0, used])
	t.check(_client_slots_used(1) == used, "the wizard's sheet shows it (%d)" % _client_slots_used(1))
	t.eq(he(1).character.slots_left, RulesSystem._slots_left(he(1).combatant), "and the Character record has it")
	# the fight hit points back to normal: a refresh rebuilds from the record
	for i in 2:
		(sys(HostSystem.ITEMS) as ItemsSystem).refresh(he(i))
	rig.run(0.5)
	t.eq(rig.cw(0).max_hp, he(0).combatant.stats.max_hp, "the client's max HP follows the rebuild")

func _nearest_remote(i: int) -> ClientWorld.RemoteEntity:
	var best: ClientWorld.RemoteEntity = null
	var bd := 1e9
	for r: ClientWorld.RemoteEntity in rig.cw(i).remotes.values():
		if r.kind == HostEntity.Kind.PLAYER or (r.max_hp > 0 and r.hp <= 0):
			continue
		var d := r.pos.distance_to(rig.cw(i).body.pos)
		if d < bd:
			bd = d
			best = r
	return best

func _slots_used(i: int) -> int:
	var c := he(i).combatant
	var n := 0
	for k in 9:
		n += c.energy_slots.slots_max[k] - c.energy_slots.slots_remaining[k] if c.energy_slots != null else 0
	return n

func _client_slots_used(i: int) -> int:
	var n := 0
	for s: Array in rc(i).sheet.get("slots", []):
		n += int(s[1]) - int(s[0])
	return n

# --- loot and gear --------------------------------------------------------------------------------

func _loot_and_gear(t: TestLog) -> void:
	var items: ItemsSystem = sys(HostSystem.ITEMS)
	var drops: Array = items.drops.list.values()
	t.check(not drops.is_empty(), "the pack dropped loot (%d piles; a champion always drops)" % drops.size())
	var picked := 0
	for d: Drops.Drop in drops:
		if not items.drops.list.has(d.id):
			continue
		rig.host.teleport(he(0), d.pos + Vector2(0.6, 0.0))
		if rig.until(func() -> bool: return not items.drops.list.has(d.id), 3.0) >= 0.0:
			picked += 1
	rig.run(0.5)
	t.check(picked > 0, "ann walked over the loot and picked up %d piles" % picked)
	t.check(_bag_count(0) > kit_count, "her inventory mirror holds the loot (kit %d, now %d)" % [kit_count, _bag_count(0)])
	t.check(not gone_drops[1].is_empty() and gone_drops[1].any(func(g: Array) -> bool: return g[1] == he(0).id),
		"bob saw the piles go to ann")
	# a +2 longsword: equip it through the client
	var sword := Items.make_magic("weapon-1-2-or-3", 1, "longsword")
	items.give(he(0).id, sword)
	rig.run(0.3)
	var slot := _find(0, func(it: Dictionary) -> bool: return String(it.get("magic", "")) == "weapon-1-2-or-3")
	t.check(slot >= 0, "the sword reached ann's mirror")
	var c0 := he(0).combatant
	var atk0 := c0.attack_modifier()
	ic(0).equip(slot, "main_hand")
	t.check(rig.until(func() -> bool: return String(ic(0).item(Equipment.index_of("main_hand")).get("magic", "")) == "weapon-1-2-or-3", 1.0) >= 0.0,
		"equipped: the mirror shows it in the main hand")
	var c1 := he(0).combatant
	var atk1 := c1.attack_modifier()
	t.eq(atk1, atk0 + 2, "the host combatant's attack bonus rose by 2 (%d -> %d)" % [atk0, atk1])
	# the next attack uses it
	var ms: MonstersSystem = sys(HostSystem.MONSTERS)
	var dummy := ms.spawn("goblin-warrior", Vector2(he(0).body.pos.x - 2.5, floor_y), {"rank": "elite"})
	var combat: CombatSystem = sys(HostSystem.COMBAT)
	combat.record = true
	combat.recorded.clear()
	var rolled := rig.until(func() -> bool:
		rig.inputs[0] = cc(0).fight_step(PlayerInput.new())
		return combat.recorded.any(func(ev: Dictionary) -> bool: return int(ev["src"]) == he(0).id and int(ev["kind"]) in [Ev.HIT, Ev.MISS, Ev.CRIT]), 10.0)
	idle()
	var roll: Dictionary = {}
	for ev: Dictionary in combat.recorded:
		if int(ev["src"]) == he(0).id and int(ev["kind"]) in [Ev.HIT, Ev.MISS, Ev.CRIT]:
			roll = ev
			break
	t.check(rolled >= 0.0 and int(roll.get("total_roll", 0)) - int(roll.get("d20", 0)) == atk1,
		"the next attack rolled with the new bonus (%s)" % [roll])
	combat.record = false
	rig.until(func() -> bool:
		rig.inputs[0] = cc(0).fight_step(PlayerInput.new())
		return not rig.host.entities.has(dummy.id), 20.0)
	idle()

func _bag_count(i: int) -> int:
	var n := 0
	for k in Inventory.SIZE:
		n += Items.count(ic(i).item(k)) if not ic(i).item(k).is_empty() else 0
	return n

func _find(i: int, f: Callable) -> int:
	for k in Inventory.SIZE:
		var it := ic(i).item(k)
		if not it.is_empty() and f.call(it):
			return k
	return -1

# --- sparks -----------------------------------------------------------------------------------------

func _spark(t: TestLog) -> void:
	place(1, cx + 10.0)
	var b := he(1)
	rig.host.world.set_fg(cx + 12, floor_y, TileDefs.id("shrine"))
	(sys(HostSystem.ITEMS) as ItemsSystem).give(b.id, Items.spark_item("fleet", 1))
	rig.run(0.3)
	var slot := _find(1, func(it: Dictionary) -> bool: return it.has("spark"))
	var run0 := b.stats.run_speed
	ic(1).kindle(slot)
	t.check(rig.until(func() -> bool: return ic(1).constellation.size() == 1, 1.0) >= 0.0, "kindled Fleet at the shrine")
	rig.run(0.3)
	t.check(b.stats.run_speed > run0, "host MoveStats faster (%.2f -> %.2f)" % [run0, b.stats.run_speed])
	t.eq(_props(rig.cw(1).stats), _props(b.stats), "host and client MoveStats identical")

func _props(s: MoveStats) -> Dictionary:
	var out := {}
	for p: Dictionary in s.get_property_list():
		if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out[p["name"]] = s.get(p["name"])
	return out

# --- mirrors the interface reads --------------------------------------------------------------

func _mirrors(t: TestLog) -> void:
	rig.run(2.5)      # DEEDS are rate-limited
	for i in 2:
		t.eq(rc(i).deeds.get("kill", -1), he(i).character.deeds.get("kill", -2), "client %d: the host's deed tally (kills)" % i)
		t.eq(rc(i).sheet.get("deeds", {}).get("kill", -1), he(i).character.deeds.get("kill", -2), "client %d: and in the sheet" % i)
		var s: Dictionary = rc(i).summary
		t.eq(int(s.get("ac", -1)), he(i).combatant.armor_class, "client %d: the summary's AC is the host's" % i)
		t.eq(int(s.get("attacks", [{}])[0].get("to_hit", -99)), he(i).combatant.attack_modifier(), "client %d: and the to-hit" % i)
		t.eq((s.get("skills", []) as Array).size(), SRD.Skill.size(), "client %d: every skill" % i)
	# temporary hit points
	he(0).combatant.stats.temp_hp = 7
	rig.run(0.3)
	t.eq(int(cc(0).status.get("temp_hp", -1)), 7, "temporary hit points mirrored")
	he(0).combatant.stats.temp_hp = 0
	# a refused cast says why
	var why: Array = []
	cc(1).refused.connect(func(_k: int, w: String) -> void: why.append(w))
	rig.cw(1).send_sys(HostSystem.COMBAT, CombatCodec.Msg.CAST, CombatCodec.cast("wish", 9, he(1).body.center(), -1.0))
	rig.run(0.3)
	t.check(why.size() == 1 and String(why[0]) != "", "the host's refusal came back: %s" % [why])
	# quick spells and the hotbar selection live on the host with the character
	rc(1).set_prefs({"quick": ["magic-missile", "fire-bolt", "", ""]})
	ic(1).select_hotbar(2)
	rig.run(0.3)
	t.eq(he(1).character.prefs.get("quick", []), ["magic-missile", "fire-bolt", "", ""], "quick spells stored on the host")
	t.eq(he(1).character.inventory.selected, 2, "and the hotbar selection")

# --- rests --------------------------------------------------------------------------------------------

func _rests(t: TestLog) -> void:
	var a := he(0)
	place(0, cx - 4.0)
	# ann places her kit's campfire through the client (inventory and prediction)
	var camp := TileDefs.id("campfire")
	var hb := -1
	for k in Inventory.HOTBAR:
		if String(ic(0).item(k).get("base", "")) == "tile:campfire":
			hb = k
	t.check(hb >= 0, "the kit's campfire is on the hotbar")
	ic(0).select_hotbar(hb)
	rig.run(0.2)
	var at := Vector2i(cx - 7, floor_y)
	rig.inputs[0] = PlayerInput.new()
	rig.inputs[0].place = true
	rig.inputs[0].target = at
	rig.run(0.3)
	idle()
	t.eq(rig.host.world.get_fg(at.x, at.y), camp, "the campfire stands")
	# a ring that needs a bond: worn, then bonded at the campfire
	var items: ItemsSystem = sys(HostSystem.ITEMS)
	items.give(a.id, Items.make_magic("ring-of-protection"))
	rig.run(0.3)
	var rs := _find(0, func(it: Dictionary) -> bool: return String(it.get("magic", "")) == "ring-of-protection")
	ic(0).equip(rs, "ring_1")
	rig.run(0.3)
	var ac0 := a.combatant.armor_class
	ic(0).bond(Equipment.index_of("ring_1"))
	t.check(rig.until(func() -> bool: return bool(a.character.equipment.at("ring_1").get("bonded", false)), 4.0) >= 0.0, "the ring bonded at the campfire")
	rig.run(0.2)
	t.eq(a.combatant.armor_class, ac0 + 1, "and works once bonded (AC %d -> %d)" % [ac0, a.combatant.armor_class])
	# short rest on Hit Point Dice
	rig.run(5.5)        # out of combat
	var c := a.combatant
	c.stats.current_hp = maxi(1, c.stats.max_hp - 8)
	var hp0 := c.stats.current_hp
	var dice0 := c.stats.hit_dice_remaining
	rests[0].clear()
	rc(0).rest_short()
	var done := rig.until(func() -> bool: return rests[0].any(func(ev: Dictionary) -> bool: return int(ev["event"]) == RulesCodec.RestEv.SHORT_DONE), 8.0)
	t.check(done >= 0.0, "a short rest at the campfire finished (%s)" % [rests[0]])
	t.check(a.combatant.stats.current_hp > hp0 and a.combatant.stats.hit_dice_remaining < dice0,
		"healed %d -> %d on Hit Point Dice (%d -> %d)" % [hp0, a.combatant.stats.current_hp, dice0, a.combatant.stats.hit_dice_remaining])
	rig.run(0.3)
	t.eq(rig.cw(0).hp, a.combatant.stats.current_hp, "the client's HP follows")
	# long rest: both in bed, the night passes
	place(1, cx - 12.0)
	rig.host.world.set_fg(cx - 3, floor_y, TileDefs.id("bed"))
	rig.host.world.set_fg(cx - 11, floor_y, TileDefs.id("bed"))
	rig.run(0.2)
	var h0 := rig.host.clock.hours()
	var wiz_used := _slots_used(1)
	rests[0].clear()
	rests[1].clear()
	rc(0).rest_long()
	rc(1).rest_long()
	var slept := rig.until(func() -> bool:
		return rests[1].any(func(ev: Dictionary) -> bool: return int(ev["event"]) == RulesCodec.RestEv.BED_DONE), 5.0)
	t.check(slept >= 0.0, "both slept (%s)" % [rests])
	var h1 := rig.host.clock.hours()
	t.check(h1 > h0 + 1.0 and absf(rig.host.clock.hour_of_day() - RulesSystem.WAKE_HOUR) < 0.1,
		"the night passed (%.1f -> %.1f h, now %.2f o'clock)" % [h0, h1, rig.host.clock.hour_of_day()])
	rig.run(0.5)
	t.check(absf(rig.cw(1).hours() - h1) < 0.2, "the client's clock jumped too")
	t.check(he(0).character.bed is Vector2i and he(1).character.bed is Vector2i, "beds are the respawn points")
	t.eq(_slots_used(1), 0, "the long rest restored the wizard's slots (%d used before)" % wiz_used)
	rig.run(0.5)
	t.eq(_client_slots_used(1), 0, "and the sheet shows them back")
	# spend one again, so slots left are something to persist
	var cast := false
	var dummy := (sys(HostSystem.MONSTERS) as MonstersSystem).spawn("goblin-warrior", Vector2(he(1).body.pos.x - 6.0, floor_y), {"rank": "minion"})
	rig.until(func() -> bool:
		if not cast and cc(1).can_attack():
			cast = cc(1).cast("magic-missile", 1, dummy.body.center())
		return _slots_used(1) > 0, 5.0)
	rig.until(func() -> bool:
		rig.inputs[1] = PlayerInput.new()
		if not rig.host.entities.has(dummy.id):
			return true
		if cc(1).can_attack():
			cc(1).cast("fire-bolt", 0, dummy.body.center())
		return false, 10.0)
	t.check(_slots_used(1) > 0, "the wizard spent a slot after sleeping")

# --- downed and revived -------------------------------------------------------------------------------

func _downed(t: TestLog) -> void:
	var rules: RulesSystem = sys(HostSystem.RULES)
	var combat: CombatSystem = sys(HostSystem.COMBAT)
	var w := he(1)
	place(0, cx + 20.0)
	place(1, cx + 30.0)
	rig.run(5.5)
	he(0).combatant.stats.current_hp = he(0).combatant.stats.max_hp
	w.combatant.stats.current_hp = 1
	rules.test_d20 = [10, 10, 10, 10, 10, 10]     # death saves succeed: the story stays in control
	var gob := (sys(HostSystem.MONSTERS) as MonstersSystem).spawn("goblin-warrior", Vector2(w.body.pos.x + 3.0, floor_y), {"rank": "standard"})
	t.check(gob != null, "a goblin comes for the wizard")
	var down := rig.until(func() -> bool: return rules.is_downed(w), 30.0)
	t.check(down >= 0.0, "the wizard was downed by the goblin (%.1f s)" % down)
	rig.host.remove_entity(gob.id)
	rig.run(0.5)
	for i in 2:
		t.eq(rc(i).state_of(w.id), Down.DOWNED, "client %d sees the wizard down" % i)
	t.eq(rig.cw(1).hp, 0, "the wizard's client shows 0 HP")
	# a hit while down: one failed death save
	var f0 := w.combatant.death_saves.failures
	combat.damage(gob.id, w, 3, "slashing")
	t.eq(w.combatant.death_saves.failures, f0 + 1, "a hit while down is a failed death save (%d -> %d)" % [f0, w.combatant.death_saves.failures])
	rig.run(0.3)
	t.eq(int(rc(1).downed.get(w.id, {}).get("failures", -1)), f0 + 1, "the wizard's client shows the failure")
	t.eq(int(rc(0).downed.get(w.id, {}).get("failures", -1)), f0 + 1, "and so does the fighter's")
	# a downed player cannot act
	var swings := func() -> int: return seen[0].filter(func(s: String) -> bool: return s.begins_with("SWING %d>" % w.id)).size()
	var sw0: int = swings.call()
	rig.cw(1).send_sys(HostSystem.COMBAT, CombatCodec.Msg.CAST, CombatCodec.cast("fire-bolt", 0, w.body.center() + Vector2(5, 0), -1.0))
	rig.cw(1).send_sys(HostSystem.COMBAT, CombatCodec.Msg.ATTACK, CombatCodec.attack(w.body.center() + Vector2(2, 0), -1.0))
	rig.run(0.5)
	t.eq(swings.call(), sw0, "a downed player cannot attack or cast")
	var potion := _find(1, func(it: Dictionary) -> bool: return String(it.get("magic", "")) == "potions-of-healing")
	var pots0 := Items.count(ic(1).item(potion)) if potion >= 0 else -1
	var dirt := rig.host.world.get_fg(floori(w.body.pos.x) + 1, floor_y - 1)
	rig.inputs[1] = PlayerInput.new()
	rig.inputs[1].dig = true
	rig.inputs[1].target = Vector2i(floori(w.body.pos.x) + 1, floor_y - 1)
	rig.run(1.5)
	rig.inputs[1] = PlayerInput.new()
	rig.inputs[1].place = true
	rig.inputs[1].target = Vector2i(floori(w.body.pos.x) + 2, floor_y)
	rig.run(0.5)
	idle()
	t.eq(rig.host.world.get_fg(floori(w.body.pos.x) + 1, floor_y - 1), dirt, "a downed player cannot dig")
	t.eq(rig.host.world.get_fg(floori(w.body.pos.x) + 2, floor_y), TileDefs.AIR, "or place")
	if potion >= 0:
		ic(1).use(potion)
		rig.run(0.3)
		t.eq(Items.count(w.character.inventory.at(potion)), pots0, "or drink a potion")
	# revive: the fighter holds it for 2 s
	place(0, w.body.pos.x - 1.5)
	rc(0).revive(w.id)
	var up := rig.until(func() -> bool: return not rules.is_downed(w), 4.0)
	t.check(up >= 0.0, "the fighter revived the wizard (%.1f s)" % up)
	rig.run(0.3)
	t.check(w.combatant.stats.current_hp >= 1 and rig.cw(1).hp == w.combatant.stats.current_hp, "the wizard is up on the host and client (%d HP)" % rig.cw(1).hp)
	t.eq(rc(0).state_of(w.id), Down.UP, "the fighter's client sees the wizard up")
	rules.test_d20 = []

# --- save, stop, load, rejoin -------------------------------------------------------------------------

func _snapshot(e: HostEntity) -> Dictionary:
	var ch := e.character
	return {"level": ch.level, "xp": ch.xp, "inventory": ch.inventory.to_dict(), "equipment": ch.equipment.to_dict(),
		"sparks": ch.sparks.to_dict(), "slots_left": RulesSystem._slots_left(e.combatant), "deeds": ch.deeds.duplicate(),
		"knacks": ch.knacks.duplicate(), "bed": ch.bed, "hp": e.combatant.stats.current_hp, "max_hp": e.combatant.stats.max_hp,
		"ac": e.combatant.armor_class, "atk": e.combatant.attack_modifier(), "run": e.stats.run_speed,
		"prefs": ch.prefs.duplicate(true), "edit_reach": e.edit_reach}

func _persist(t: TestLog) -> void:
	var rules: RulesSystem = sys(HostSystem.RULES)
	# a Knack: level the fighter to 4 and pick one through the client
	var a := he(0)
	if a.character.level < 4:
		rules.award_xp(a.id, LevelTrack.xp_for_level(4) - a.character.xp, "test")
	rig.run(0.5)
	var knack_key := ""
	for k: String in rc(0).choices:
		if k.begins_with("knack:"):
			knack_key = k
	t.check(knack_key != "", "a Knack is offered at level 4 (%s)" % [rc(0).choices.keys()])
	if knack_key != "":
		rc(0).pick_knack(String(rc(0).choices[knack_key]["options"][0]["id"]))
		rig.run(0.5)
	t.eq(a.character.knacks.size(), 1, "the Knack was taken")
	rig.run(1.0)
	var before := [_snapshot(he(0)), _snapshot(he(1))]
	t.check(before[0]["ac"] > 0 and bool(a.character.equipment.at("ring_1").get("bonded", false)), "the bonded ring is worn before saving")
	var dir := ProjectSettings.globalize_path(SAVE_DIR)
	_rm(dir)
	# players leave (their records are written), then the world is saved
	for i in 2:
		rig.clients[i].leave() if rig.clients[i].has_method("leave") else rig.cut(i)
	rig.run(0.5)
	rig.host.world_saver = WorldSave.save
	t.eq(rig.host.save(dir), OK, "saved")
	# a new process: load the world, the host state and the players; rejoin
	var w2 := WorldSave.load(dir)
	t.check(w2 != null, "the world loads")
	if w2 == null:
		return
	rig = Rig.new(w2, 0.03)
	Systems.install_host(rig.host)
	(rig.host.system(HostSystem.MONSTERS) as MonstersSystem).director_enabled = 0
	(rig.host.system(HostSystem.MONSTERS) as MonstersSystem).lairs_enabled = false
	t.eq(rig.host.load_players(dir), 2, "two player records")
	t.check(rig.host.load_state(dir), "host state loads")
	seen = [[], []]
	_join(["ann", "bob"], ["fighter", "wizard"])
	t.check(_ready(), "both rejoined")
	rig.run(1.0)
	var after := [_snapshot(he(0)), _snapshot(he(1))]
	for snap: Dictionary in before + after:      # time spent underground keeps counting
		for k: String in snap["deeds"].keys():
			if k.begins_with("underground"):
				snap["deeds"].erase(k)
	for i in 2:
		for k: String in before[i]:
			t.eq(after[i][k], before[i][k], "player %d: %s persisted" % [i, k])
	t.check(bool(he(0).character.equipment.at("ring_1").get("bonded", false)), "the ring is still bonded")
	t.eq(int(rc(0).sheet.get("level", 0)), before[0]["level"], "the client sheet shows the level")
	t.eq(ic(1).constellation.size(), 1, "the wizard's client shows the kindled spark")
	t.eq(rc(1).prefs.get("quick", []), ["magic-missile", "fire-bolt", "", ""], "the quick spells came back to the client")
	t.eq(ic(1).selected(), 2, "and the hotbar selection")
	t.eq(rc(0).deeds.get("kill", -1), he(0).character.deeds.get("kill", -2), "the deed tally came back")
	t.eq(_props(rig.cw(1).stats), _props(he(1).stats), "and moves with it")
	_rm(dir)

func _rm(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_rm(dir.path_join(sub))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
