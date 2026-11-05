## The fast resolver: deterministic under a seed, integral losses, sensible strength order.
extends RefCounted

func _wins(a: Dictionary, b: Dictionary, n: int, seed: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var w := 0
	for i in n:
		if SimCombat.resolve(rng, a, b).winner == "a":
			w += 1
	return float(w) / n

func run(t: TestLog) -> void:
	var r1 := RandomNumberGenerator.new(); r1.seed = 5
	var r2 := RandomNumberGenerator.new(); r2.seed = 5
	var x := SimCombat.resolve(r1, {"bandit": 6, "bandit-captain": 1}, {"guard": 7})
	var y := SimCombat.resolve(r2, {"bandit": 6, "bandit-captain": 1}, {"guard": 7})
	t.eq(x, y, "same seed, same fight")
	for k in x.a_dead:
		t.check(x.a_dead[k] is int and x.a_dead[k] >= 0, "losses are whole creatures")
	t.check(SimData.count(x.a_dead) + SimData.count(x.a_left) == 7, "dead + left = side size")
	t.check(_wins({"ogre": 3}, {"commoner": 6}, 200, 1) > 0.95, "three ogres beat six commoners")
	t.check(_wins({"guard": 4}, {"guard": 12}, 200, 2) < 0.05, "4 guards lose to 12")
	var even := _wins({"guard": 8}, {"guard": 8}, 400, 3)
	t.check(even > 0.35 and even < 0.65, "mirror match is near even (%.2f)" % even)
	t.check(_wins({"young-red-dragon": 1}, {"guard": 10}, 100, 4) > 0.9, "a young dragon beats ten guards")
	t.check(SimCombat.odds({"guard": 12}, {"guard": 4}) > 0.9, "odds favour the bigger side")
	t.check(SimCombat.odds({"guard": 4}, {"guard": 4}, 3) < 0.5, "walls help the defender")
	var rout := SimCombat.resolve(r1, {"guard": 10}, {"bandit": 10}, {"a_break": 0.3, "b_break": 0.3})
	t.check(SimData.count(rout.a_left) > 0 and SimData.count(rout.b_left) > 0 or rout.winner != "draw", "breaking sides leave survivors")
