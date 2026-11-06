## Melee on uneven ground: a player's swing at a creature one or two tiles up or down a slope,
## a stair or a ledge connects as it does on the flat. The world is an open room with the
## ground cut to shape; the target stands still and the aim is at its middle (what the mouse
## does); a miss by the dice is a roll, a whiff is the arc not reaching it.
extends RefCounted

const Combat := preload("res://tests/test_combat.gd")

## Tile columns: heights relative to the floor row by x offset from the player.
func _ground(world: TileWorld, x0: int, y0: int, heights: Callable, tile: int, stairs := false) -> void:
	for x in range(x0 - 12, x0 + 13):
		var top: int = y0 + int(heights.call(x - x0))
		for y in range(0, top):
			world.set_fg(x, y, TileDefs.id("stone"))
		for y in range(top, 60):
			world.set_fg(x, y, TileDefs.AIR)
		if stairs and tile != 0 and int(heights.call(x - x0)) != int(heights.call(x - x0 - 1)):
			world.set_fg(x, top, tile)

func _rig() -> Dictionary:
	var host := WorldHost.new(Combat.flat_world(128))
	Dice.rng = host.rng
	host.add_system(RulesSystem.new())
	var combat := CombatSystem.new()
	host.add_system(combat)
	var p := host.add_player("cat", 2, {"class": "fighter"})
	var g := host.add_srd_monster("goblin-warrior", Vector2(60, 30))
	g.combatant.stats.max_hp = 99999          # it must outlive the test
	g.combatant.stats.current_hp = 99999
	return {"host": host, "combat": combat, "p": p, "g": g}

## Whiffs out of `n` swings with the target at (dx, its ground), attacker on its ground.
func _swings(r: Dictionary, x0: int, y0: int, heights: Callable, dx: float, n: int) -> int:
	var host: WorldHost = r["host"]
	var combat: CombatSystem = r["combat"]
	var p: HostEntity = r["p"]
	var g: HostEntity = r["g"]
	var whiffs0 := int(combat.counts["whiffs"])
	for i in n:
		p.body.pos = Vector2(x0 + 0.5, y0 + int(heights.call(0)))
		p.body.vel = Vector2.ZERO
		g.body.pos = Vector2(x0 + 0.5 + dx, y0 + int(heights.call(floori(dx + 0.5))))
		g.body.vel = Vector2.ZERO
		g.combatant.stats.current_hp = g.combatant.stats.max_hp
		p.combatant.stats.current_hp = p.combatant.stats.max_hp
		p.body.facing = 1 if dx > 0 else -1
		combat.start_attack(p, -1, g.body.rect().get_center(), false)
		for k in 45:
			host.tick()
			p.body.pos = Vector2(x0 + 0.5, y0 + int(heights.call(0)))
			g.body.pos = Vector2(x0 + 0.5 + dx, y0 + int(heights.call(floori(dx + 0.5))))
	return int(combat.counts["whiffs"]) - whiffs0

func run(t: TestLog) -> void:
	var slope := func(x: int) -> int: return x
	var fall := func(x: int) -> int: return -x
	var gentle := func(x: int) -> int: return x / 2
	var ledge := func(x: int) -> int: return 2 if x >= 1 else 0
	var step_down := func(x: int) -> int: return -2 if x >= 1 else 0
	var flat := func(_x: int) -> int: return 0
	var cases := [["flat", flat, false], ["slope up", slope, false], ["slope down", fall, false], ["gentle", gentle, false],
		["ledge up 2", ledge, false], ["ledge down 2", step_down, false], ["stairs up", slope, true], ["stairs down", fall, true]]
	var stair := TileDefs.id("stairs_r")
	for c: Array in cases:
		var r := _rig()
		var host: WorldHost = r["host"]
		var heights: Callable = c[1]
		_ground(host.world, 64, 30, heights, stair if bool(c[2]) else 0, bool(c[2]))
		var row := PackedStringArray()
		for dx: float in [1.6, 2.0, 2.6, 3.0, 3.4]:
			var rolls0 := int((r["combat"] as CombatSystem).counts["rolls"])
			row.append("%.1f:%d/4" % [dx, _swings(r, 64, 30, heights, dx, 4)])
			if dx < 2.6 and not (c[0] == "slope down" and dx > 2.6):
				t.check(int((r["combat"] as CombatSystem).counts["rolls"]) > rolls0, "%s: the swings at %.1f tiles were rolled" % [c[0], dx])
				t.eq(_swings(r, 64, 30, heights, dx, 2), 0, "%s: a swing at %.1f tiles connects" % [c[0], dx])
		print("  %-13s whiffs by distance  %s" % [c[0], " ".join(row)])
