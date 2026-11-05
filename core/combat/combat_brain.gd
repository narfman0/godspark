## The one reference brain (the Monsters track writes the real ones): walk toward the
## nearest player it can see, stand still through a readable wind-up, attack, back off
## briefly, repeat. Uses a Recharge breath (save action with an area) when ready and a
## target is inside it. No navigation: it walks straight and jumps when blocked.
##
##   host.add_srd_monster("goblin-warrior", pos, CombatBrain.new())
class_name CombatBrain
extends RefCounted

enum State { SEEK, BACKOFF }

var state := State.SEEK
var t := 0.0
var target_id := 0
var _was_busy := false

func think(host: WorldHost, e: HostEntity, dt: float) -> PlayerInput:
	var inp := PlayerInput.new()
	var combat := host.system(HostSystem.COMBAT) as CombatSystem
	if combat == null:
		return inp
	t += dt
	if not combat.can_act(e):
		return combat.filter_input(e, inp)
	var b := CombatTempo.section("brain")
	var foe := combat.nearest_foe(e, float(b.get("sight_tiles", 32.0)))
	if combat.busy(e):
		_was_busy = true
		if foe != null:
			e.body.facing = 1 if foe.body.pos.x >= e.body.pos.x else -1
		return combat.filter_input(e, inp)       # stand through the wind-up and recovery
	if _was_busy:
		_was_busy = false
		state = State.BACKOFF
		t = 0.0
	if foe == null:
		return combat.filter_input(e, inp)
	target_id = foe.id
	var dx := foe.body.pos.x - e.body.pos.x
	if state == State.BACKOFF:
		if t < float(b.get("backoff_s", 0.6)):
			inp.move_x = -signf(dx) * 0.6
			return combat.filter_input(e, inp)
		state = State.SEEK
	var aim := foe.body.rect().get_center()
	var acts := combat.actions_of(e)
	for i in acts.size():          # a breath weapon that is ready and would reach
		var act: Dictionary = acts[i]
		if act["kind"] == "save" and MonsterSpells.save_action_ready(e.combatant, act["save"]) \
				and e.body.rect().get_center().distance_to(aim) <= K.ft(float(act.get("reach_ft", 5.0))) \
				and combat.start_attack(e, i, aim):
			return combat.filter_input(e, inp)
	if foe in combat.targets_in_reach(e) and combat.start_attack(e, -1, aim):
		return combat.filter_input(e, inp)
	inp.move_x = signf(dx) if absf(dx) > 0.3 else 0.0
	if e.body.on_wall and e.body.on_floor and inp.move_x != 0.0 and signi(e.body.wall_dir) == signi(int(inp.move_x)):
		inp.jump = true
		inp.jump_pressed = true
	return combat.filter_input(e, inp)
