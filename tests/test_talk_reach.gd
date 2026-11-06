## If the prompt says you can talk, you can talk: the client's prompt (DealsClient.nearest_person)
## against what the host answers, over a loopback, and the bug that started it: RemoteEntity.pos
## moved only when a presenter ran, so a client with no view (the rig, a bot) walked up to where
## a person had been when first seen and was told "far".
extends RefCounted

const Rig := preload("res://tests/net_rig.gd")

var t: TestLog
var rig: Rig

func run(t_: TestLog) -> void:
	t = t_
	var w := WorldGen.generate(1024, 512, 4)
	rig = Rig.new(w, 0.03)
	Systems.install_host(rig.host)
	(rig.host.system(HostSystem.MONSTERS) as MonstersSystem).director_enabled = 0
	(rig.host.system(HostSystem.RULES) as RulesSystem).cheats = true
	var c := rig.add_client("ann")
	c.player_class = "fighter"
	c.welcomed.connect(func(cw: ClientWorld) -> void: Systems.install_client(cw))
	rig.until(func() -> bool: return rig.cw(0) != null and rig.cw(0).area_ready(), 10.0)
	rig.run(4.0)
	var who := _someone()
	t.check(who != 0, "someone to talk to")
	if who == 0:
		return
	_follows(who)
	_lag(who)
	_wall(who)
	_fight(who)
	_hostile(who)

func dc() -> DealsClient:
	return rig.cw(0).system(HostSystem.DEALS)

func lc() -> LifeClient:
	return rig.cw(0).system(HostSystem.LIFE)

func me() -> HostEntity:
	return rig.host_entity(0)

func _someone() -> int:
	var best := 0
	var bd := INF
	for id: int in lc().people:
		var x := rig.host.entity(id)
		if bool(lc().people[id].get("talk", false)) and x != null and rig.cw(0).remotes.has(id) \
				and String(lc().people[id].get("role", "")) in ["keeper", "merchant", "smith", "priest"]:
			var d := x.body.pos.distance_to(me().body.pos)
			if d < bd:
				bd = d
				best = id
	return best

## Beside a person, who may be on their way somewhere: only the moment after counts.
func _stand_by(who: int, dx: float) -> void:
	var x := rig.host.entity(who)
	rig.host.teleport(me(), x.body.pos + Vector2(dx, 0.5))
	TileCollision.depenetrate(rig.host.world, me().body)
	rig.run(0.25)

## What the host answers to a talk, now. "" is yes.
func _answer(who: int) -> String:
	dc().last_note.erase(DealsCodec.Msg.TALK_TO)
	dc().talk(who)
	rig.until(func() -> bool: return dc().last_note.has(DealsCodec.Msg.TALK_TO), 2.0)
	var word := String(dc().last_note.get(DealsCodec.Msg.TALK_TO, "no answer"))
	if dc().talking():
		dc().leave()
		rig.run(0.3)
	return "" if word == "ok" else word

## The cause. No presenter runs here, as in a bot: the remote still follows the host.
func _follows(who: int) -> void:
	var x := rig.host.entity(who)
	var r: ClientWorld.RemoteEntity = rig.cw(0).remotes[who]
	var at0 := r.pos
	var post: Vector2 = (x.brain as LifeBrain).post
	x.body.pos += Vector2(6.0, 0.0)
	(x.brain as LifeBrain).post = x.body.pos
	rig.run(0.6)
	t.check(r.pos.distance_to(x.body.pos) < 1.0, "a client with no view knows where a person is now (%s, host %s, first seen %s)" % [r.pos, x.body.pos, at0])
	_stand_by(who, 1.5)
	t.eq(dc().nearest_person(), who, "the nearest person: the prompt finds them there")
	t.eq(_answer(who), "", "and the host agrees")
	(x.brain as LifeBrain).post = post
	rig.run(3.0)

## The request and the walking travel the same road: running at a person, E the moment the
## prompt shows is heard when the host's copy has caught up, up to a quarter second each way.
func _lag(who: int) -> void:
	for lat: float in [0.03, 0.25]:
		rig.hub.latency = lat
		var x := rig.host.entity(who)
		rig.host.teleport(me(), x.body.pos + Vector2(-16.0, 0.5))
		TileCollision.depenetrate(rig.host.world, me().body)
		rig.run(1.0)
		var inp := PlayerInput.new()
		inp.move_x = 1.0
		rig.inputs[0] = inp
		var seen := rig.until(func() -> bool: return dc().would_talk(who), 4.0)
		var host_d := me().body.center().distance_to(x.body.center())
		var word := _answer(who) if seen >= 0.0 else "the prompt never showed"
		rig.inputs[0] = PlayerInput.new()
		rig.run(0.5)
		t.eq(word, "", "running up at %.0f ms: the prompt showed (host's copy then %.1f tiles off) and the talk opened" % [lat * 1000.0, host_d])
	rig.hub.latency = 0.03
	rig.run(0.5)

## A wall between: near enough, and the host says no_sight, so no prompt.
func _wall(who: int) -> void:
	var x := rig.host.entity(who)
	var world := rig.host.world
	_stand_by(who, -3.0)
	var bx := floori(x.body.pos.x) - 2
	var fy := floori(x.body.pos.y)
	var was := {}
	for y in range(fy - 1, fy + 12):
		var c := Vector2i(bx, y)
		was[c] = world.get_fg(c.x, c.y)
		world.set_fg(c.x, c.y, TileDefs.id("stone"))
	rig.run(0.6)
	t.eq(_answer(who), "no_sight", "behind a wall the host refuses")
	t.check(not dc().would_talk(who), "so the prompt does not show")
	for c: Vector2i in was:
		world.set_fg(c.x, c.y, int(was[c]))
	rig.run(0.6)
	_stand_by(who, -3.0)
	t.check(dc().would_talk(who), "wall down, prompt back")

## A swing in the last five seconds: the host says fight until it has passed.
func _fight(who: int) -> void:
	_stand_by(who, 2.0)
	var cc: CombatClient = rig.cw(0).system(HostSystem.COMBAT)
	cc.attack(rig.cw(0).body.center() + Vector2(3, 0))
	rig.until(func() -> bool: return cc.in_fight(rig.cw(0).my_id), 2.0)
	t.eq(_answer(who), "fight", "just after a swing the host refuses")
	t.check(not dc().would_talk(who), "and the prompt does not show")
	var passed := rig.until(func() -> bool: return not cc.in_fight(rig.cw(0).my_id), 8.0)
	t.check(passed >= 0.0, "the fight passes (%.1f s)" % passed)
	_stand_by(who, 2.0)
	t.check(dc().would_talk(who), "the prompt comes back")
	t.eq(_answer(who), "", "and the host agrees")

## Hostile by standing: the client knows the number.
func _hostile(who: int) -> void:
	var life: LifeSystem = rig.host.system(HostSystem.LIFE)
	var f := String(lc().people[who].get("faction", ""))
	life.add_standing(me().id, f, -100, "test")
	_stand_by(who, 2.0)
	t.check(not dc().would_talk(who), "a foe by standing: no prompt")
	t.eq(_answer(who), "hostile", "and the host will not talk")
	life.add_standing(me().id, f, 100, "test")
	_stand_by(who, 2.0)
	t.check(dc().would_talk(who), "made up: the prompt is back")
