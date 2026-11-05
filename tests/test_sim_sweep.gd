## Invariants over a small seed sweep: the sim stays sane and interesting.
extends RefCounted

const SEEDS := [3, 8, 11, 17, 21, 26]

func run(t: TestLog) -> void:
	var n_raids := 0
	var n_grew := 0
	var n_declined := 0
	var n_fell := 0
	var n_collapsed := 0
	var n_shock := 0
	var sigs := {}
	for seed in SEEDS:
		var h := SimHealth.run(seed, 100, 20)
		t.eq(h.bad, 0, "seed %d: no negative stocks or populations" % seed)
		t.check(h.trade_done > 0, "seed %d: caravans complete trades" % seed)
		t.check(not h.exploded, "seed %d: no unbounded growth (max %d from %d)" % [seed, h.pop_max, h.pop0])
		if h.ambushes + h.raids > 0: n_raids += 1
		if h.grew: n_grew += 1
		if h.declined: n_declined += 1
		if h.fell_any: n_fell += 1
		if h.collapsed: n_collapsed += 1
		if h.shock_seen: n_shock += 1
		sigs[h.sig] = true
	var n := SEEDS.size()
	t.check(n_raids >= n - 1, "raids happen in nearly every world (%d/%d)" % [n_raids, n])
	t.check(n_grew >= n / 2, "settlements grow in most worlds (%d/%d)" % [n_grew, n])
	t.check(n_declined >= n / 2, "settlements decline in most worlds (%d/%d)" % [n_declined, n])
	t.check(n_fell >= 2, "some worlds see a settlement fall (%d/%d)" % [n_fell, n])
	t.check(n_collapsed <= 1, "few worlds collapse (%d/%d)" % [n_collapsed, n])
	t.check(n_shock >= n / 2, "food shocks visibly propagate in most worlds (%d/%d)" % [n_shock, n])
	t.eq(sigs.size(), n, "every seed tells a different history")
