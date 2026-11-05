## The M2 seams (docs/todo.md "M2 integration / Wiring"), every system installed: reach and
## dig speed tags read by the host dig and the client's predicted dig alike; Quickhand,
## Surefoot, Featherfall in combat; healing spells and potions on a downed player through
## rules.heal; the rules rebuild ends with the whole outfit (a greataxe stays a greataxe
## after a level-up); hit points from Constitution gear survive a save; conditions that stop
## or slow a player are enforced by the host's movement check.
extends RefCounted

const Rig := preload("res://tests/net_rig.gd")
const Ev := CombatCodec.Ev

func run(t: TestLog) -> void:
	_edit_tags(t)
	_tempo(t)
	_healing_down(t)
	_outfit(t)
	_con_gear(t)
	_conditions(t)

func _host() -> WorldHost:
	var host := WorldHost.new(TileWorld.make_test(512, 128))
	Systems.install_host(host)
	(host.system(HostSystem.MONSTERS) as MonstersSystem).director_enabled = 0
	return host

func _ticks(host: WorldHost, n: int) -> void:
	for i in n:
		host.tick()

# --- reach and dig speed ----------------------------------------------------------------------

func _edit_tags(t: TestLog) -> void:
	var rig := Rig.new(TileWorld.make_test(1024, 256), 0.03)
	Systems.install_host(rig.host)
	var c := rig.add_client("ann")
	c.welcomed.connect(func(cw: ClientWorld) -> void: Systems.install_client(cw))
	rig.until(func() -> bool: return rig.cw(0) != null and rig.cw(0).area_ready(), 6.0)
	rig.run(0.5)
	var e := rig.host_entity(0)
	var cw := rig.cw(0)
	t.eq([e.edit_reach, e.dig_power], [TileEdit.REACH, 1.0], "bare: the base reach and dig speed")
	e.character.sparks.slots = 3
	e.character.sparks.kindle({"id": "longarm", "rank": 2})
	e.character.sparks.kindle({"id": "mole", "rank": 2})
	var items: ItemsSystem = rig.host.system(HostSystem.ITEMS)
	items.refresh(e)
	rig.run(0.5)
	t.eq([e.edit_reach, e.dig_power], [TileEdit.REACH + 3.0, 1.75], "Longarm III and Mole III on the host entity")
	t.eq([cw.edit_reach, cw.dig_power], [e.edit_reach, e.dig_power], "the client mirrors the same numbers")
	# a tile 6 tiles beyond the box: out of bare reach, in reach now; dug at Mole speed
	var feet := Vector2i(floori(e.body.pos.x), floori(e.body.pos.y))
	var target := Vector2i(feet.x + 7, feet.y - 1)
	var r := e.body.rect()
	var gap := float(target.x) - r.end.x
	t.check(gap > TileEdit.REACH and gap <= e.edit_reach, "the target is past bare reach (%.2f tiles)" % gap)
	var tile := rig.host.world.get_fg(target.x, target.y)
	t.check(tile != TileDefs.AIR and TileDefs.hardness[tile] >= 0.0, "something diggable there (%s)" % TileDefs.names[tile])
	var want := TileEdit.dig_time(tile, 1.75)
	var seen := {}
	cw.edit_result.connect(func(req: int, reason: int, at: Vector2i, _tile: int) -> void: seen[at] = reason)
	var t0 := -1.0
	var t_pred := -1.0
	var tt := 0.0
	rig.inputs[0] = PlayerInput.new()
	rig.inputs[0].dig = true
	rig.inputs[0].target = target
	while tt < 4.0 and not seen.has(target):
		rig.frame()
		tt += rig.frame_dt
		if t0 < 0.0 and rig.host_entity(0).digging():
			t0 = tt
		if t_pred < 0.0 and cw.world.get_fg(target.x, target.y) == TileDefs.AIR:
			t_pred = tt
	rig.inputs[0] = PlayerInput.new()
	t.eq(int(seen.get(target, -1)), WorldHost.Reason.OK, "the host dug it (reach from Longarm)")
	t.check(t_pred > 0.0 and absf(t_pred - want) < 0.12, "the client predicted it done at Mole speed (%.3f s, dig time %.3f)" % [t_pred, want])
	t.eq(cw.rolled_back, 0, "no prediction rolled back")
	# without the sparks the same reach is refused on both sides
	e.character.sparks = Constellation.from_dict({})
	e.character.sparks.salt = e.name
	items.refresh(e)
	rig.run(0.5)
	t.eq([cw.edit_reach, cw.dig_power], [TileEdit.REACH, 1.0], "unkindled: back to bare numbers on the client")
	t.eq(rig.host.dig_reason(e, target.x, target.y - 1), WorldHost.Reason.OUT_OF_REACH, "and the host refuses that far")

# --- tempo, falls, pushes --------------------------------------------------------------------

func _tempo(t: TestLog) -> void:
	var host := _host()
	var combat: CombatSystem = host.system(HostSystem.COMBAT)
	var items: ItemsSystem = host.system(HostSystem.ITEMS)
	var e := host.add_player("fen", 2, {"class": "fighter"})
	_ticks(host, 2)
	t.check(combat.start_attack(e, -1, e.body.center() + Vector2(4, 0)), "a plain swing")
	var plain := float(combat.actor(e).seq["total"])
	_ticks(host, 60)
	e.character.sparks.slots = 3
	e.character.sparks.kindle({"id": "quickhand", "rank": 2})
	e.character.sparks.kindle({"id": "surefoot", "rank": 2})
	e.character.sparks.kindle({"id": "featherfall", "rank": 2})
	items.refresh(e)
	t.check(combat.start_attack(e, -1, e.body.center() + Vector2(4, 0)), "a Quickhand swing")
	var quick := float(combat.actor(e).seq["total"])
	var tempo := CombatTempo.weapon_tempo(CombatTempo.weapon_class(host.srd, e.combatant.weapon, e.combatant.equipment.shield == null, false))
	t.check(absf((plain - quick) - float(tempo["recovery"]) * 0.3) < 1e-4, "Quickhand III cuts the recovery by 30%% (%.3f -> %.3f s)" % [plain, quick])
	_ticks(host, 60)
	# Surefoot III: pushes do not move the player
	combat.record = true
	combat._push(combat.actor(e), e.body.center() - Vector2(2, 0), 10)
	t.eq(combat.recorded.filter(func(ev: Dictionary) -> bool: return int(ev["kind"]) == Ev.PUSH).size(), 0, "Surefoot III: no push at all")
	# Featherfall III: no fall damage; without it a 60 ft fall hurts
	var hp0 := e.combatant.current_hp
	combat._fall_damage(combat.actor(e), 60.0)
	t.eq(e.combatant.current_hp, hp0, "Featherfall III: a 60 ft fall does no damage")
	e.character.sparks = Constellation.from_dict({})
	items.refresh(e)
	e.combatant.stats.max_hp = 500
	e.combatant.stats.current_hp = 500
	combat._fall_damage(combat.actor(e), 60.0)
	t.check(e.combatant.current_hp < 500, "without it the same fall hurts (%d)" % (500 - e.combatant.current_hp))

# --- healing a downed player ------------------------------------------------------------------

func _healing_down(t: TestLog) -> void:
	var host := _host()
	var combat: CombatSystem = host.system(HostSystem.COMBAT)
	var rules: RulesSystem = host.system(HostSystem.RULES)
	var items: ItemsSystem = host.system(HostSystem.ITEMS)
	var f := host.add_player("fen", 2, {"class": "fighter"})
	var cl := host.add_player("cleo", 3, {"class": "cleric"})
	cl.character.build["spells"] = ["sacred-flame", "cure-wounds", "healing-word", "bless"]
	rules.refresh(cl)
	cl.body.pos = f.body.pos + Vector2(1.5, 0)
	_ticks(host, 2)
	combat.damage(0, f, 999, "slashing")
	_ticks(host, 1)
	t.check(rules.is_downed(f), "the fighter is down")
	combat.damage(0, f, 2, "slashing")
	t.eq(f.combatant.death_saves.failures, 1, "damage while down: one failed save")
	combat.damage(0, f, 2, "slashing", {"crit": true})
	t.eq(f.combatant.death_saves.failures, 3, "a critical hit while down: two more")
	t.check(rules.is_dead(f), "three failures: dead")
	rules.respawn(f)
	f.body.pos = cl.body.pos - Vector2(1.5, 0)
	_ticks(host, 2)
	combat.damage(0, f, 999, "slashing")
	_ticks(host, 1)
	t.check(rules.is_downed(f), "down again")
	t.eq(combat.cast(cl, "cure-wounds", 1, f.body.center()), "", "Cure Wounds on the downed fighter")
	_ticks(host, 20)
	t.check(not rules.is_downed(f) and f.combatant.current_hp > 0, "the spell got him up (%d HP)" % f.combatant.current_hp)
	_ticks(host, 2)
	t.check(combat.can_act(f), "and he can act again")
	# a potion is drunk through rules.heal
	f.combatant.stats.current_hp = 1
	var slot := f.character.inventory.slots.find(f.character.inventory.slots.filter(func(it: Variant) -> bool:
		return it is Dictionary and String((it as Dictionary).get("magic", "")) == "potions-of-healing")[0])
	t.eq(items.use_item(f, slot), "", "drink a healing potion")
	t.check(f.combatant.current_hp > 1, "healed (%d HP)" % f.combatant.current_hp)

# --- the rebuild keeps the whole outfit -------------------------------------------------------

func _outfit(t: TestLog) -> void:
	var host := _host()
	var rules: RulesSystem = host.system(HostSystem.RULES)
	var items: ItemsSystem = host.system(HostSystem.ITEMS)
	var f := host.add_player("fen", 2, {"class": "fighter"})
	f.character.inventory.put(20, {"base": "greataxe", "count": 1, "material": "iron"})
	t.eq(items.move_item(f, 20, Equipment.index_of("main_hand")), "", "wield a greataxe")
	t.eq(f.combatant.weapon.weapon_name, "Greataxe", "the combatant swings it")
	rules.award_xp(f.id, LevelTrack.xp_for_level(5) - f.character.xp, "test")
	t.eq(f.character.level, 5, "level 5 (class level 2)")
	t.eq(f.combatant.weapon.weapon_name if f.combatant.weapon != null else "none", "Greataxe", "after the level-up rebuild it is still a greataxe")
	rules.auto_answer(f)
	t.eq(f.combatant.weapon.weapon_name if f.combatant.weapon != null else "none", "Greataxe", "and after answering choices")

# --- Constitution gear hit points survive a save ----------------------------------------------

func _con_gear(t: TestLog) -> void:
	var host := _host()
	var items: ItemsSystem = host.system(HostSystem.ITEMS)
	var w := host.add_player("wyn", 2, {"class": "wizard"})
	var bare := w.combatant.stats.max_hp
	w.character.inventory.put(20, Items.make_magic("amulet-of-health").merged({"bonded": true}, true))
	t.eq(items.move_item(w, 20, Equipment.index_of("neck")), "", "wear a bonded Amulet of Health")
	var geared := w.combatant.stats.max_hp
	t.check(geared > bare, "CON 19 raises max HP (%d -> %d)" % [bare, geared])
	w.combatant.stats.current_hp = geared
	host.remove_entity(w.id)       # writes the record
	var back := host.add_player("wyn", 2)
	t.eq([back.combatant.stats.current_hp, back.combatant.stats.max_hp], [geared, geared], "rejoined at full geared HP")

# --- conditions on the host's movement check --------------------------------------------------

func _conditions(t: TestLog) -> void:
	var host := _host()
	var combat: CombatSystem = host.system(HostSystem.COMBAT)
	var e := host.add_player("ann", 2, {"class": "fighter"})
	_ticks(host, 3)
	var seq := [0]
	var step := func(dx: float) -> WorldHost.StateCheck:
		seq[0] += 6
		host.tick()
		return host.submit_state(e.id, e.epoch, seq[0], e.body.pos + Vector2(dx, 0), Vector2.ZERO, e.flags)
	t.eq(step.call(1.0), WorldHost.StateCheck.OK, "free: a 1-tile step is fine")
	e.combatant.conditions.add(SRD.Condition.RESTRAINED)
	combat._touched[e.id] = true
	host.tick()
	t.eq(combat.move_limits(host, e).get("mult"), 0.0, "Restrained: speed 0")
	t.eq(step.call(0.2), WorldHost.StateCheck.OK, "a twitch is allowed")
	var r: WorldHost.StateCheck = step.call(0.4)
	t.eq(r, WorldHost.StateCheck.TOO_FAST, "walking off while Restrained is corrected")
	var held := e.body.pos
	for i in 5:
		step.call(0.25)
	t.check(absf(e.body.pos.x - held.x) <= WorldHost.HOLD_SLIP + 1e-4, "creeping is corrected too (%.2f)" % (e.body.pos.x - held.x))
	e.combatant.conditions.remove(SRD.Condition.RESTRAINED)
	e.combatant.conditions.add(SRD.Condition.PRONE)
	combat._touched[e.id] = true
	host.tick()
	t.eq(combat.move_limits(host, e).get("mult"), 0.5, "Prone: crawl at half speed")
	var crawl := e.stats.run_speed * 0.5 * WorldHost.SPEED_MULT / 3.0    # a third of a second at crawl
	seq[0] += 20
	for i in 5:       # (a prone creature stands after a second)
		host.tick()
	var far := host.submit_state(e.id, e.epoch, seq[0], e.body.pos + Vector2(crawl + WorldHost.MOVE_MARGIN + e.stats.step_tiles + 1.0, 0), Vector2.ZERO, e.flags)
	t.eq(far, WorldHost.StateCheck.TOO_FAST, "running at full speed while prone is corrected")
	e.combatant.conditions.remove(SRD.Condition.PRONE)
	combat._touched[e.id] = true
	host.tick()
	t.eq(combat.move_limits(host, e), {}, "no condition: no limits")
