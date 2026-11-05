## Headless scripted fights for tuning data/combat.json and checking build-to-build ratios.
##   godot --headless -s res://tools/arena.gd -- build=fighter:5 vs=goblin-warrior:6 [seeds=1..20]
##       [weapon=greatsword] [kite=1] [time=60] [ac=15] [spread=3]
##   vs=dummy[:N]   a target that never fights back (100000 hit points, AC from ac=), for
##                  sustained damage; the run lasts time= seconds
##   report=spells | report=monsters   what the combat machine supports from the addon
## The hero walks at the nearest monster and attacks on cooldown (kite=1 with a ranged
## weapon: keeps 10-20 tiles away). Monsters use CombatBrain. Prints per-seed lines and a
## summary: win rate, time to kill, hero damage per second, damage taken per second, and the
## SRD's expected damage per round for the build (attacks x hit chance x average damage)
## so ratios between builds can be compared with the SRD's.
extends SceneTree

var opts := {}

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s := a.trim_prefix("--")
		var i := s.find("=")
		opts[s.substr(0, i) if i >= 0 else s] = s.substr(i + 1) if i >= 0 else "1"
	if opts.has("report"):
		_report(String(opts["report"]))
		quit(0)
		return
	var build := String(opts.get("build", "fighter:1")).split(":")
	var cls := build[0]
	var level := int(build[1]) if build.size() > 1 else 1
	var vs := String(opts.get("vs", "goblin-warrior:1")).split(":")
	var slug := vs[0]
	var count := int(vs[1]) if vs.size() > 1 else 1
	var seeds := _seeds(String(opts.get("seeds", "1..10")))
	var limit := float(opts.get("time", 60 if slug == "dummy" else 120))
	var wins := 0
	var ttk := 0.0
	var dealt := 0.0
	var taken := 0.0
	var secs := 0.0
	var swings := 0
	var hits := 0
	var rolls := 0
	var srd_dpr := 0.0
	for sd: int in seeds:
		var r := _fight(cls, level, slug, count, sd, limit)
		srd_dpr = r["srd_dpr"]
		print("seed %d: %s in %.1f s, hero dealt %d (%.1f/s), took %d (%.1f/s), swings %d, hits %d/%d, hp %d/%d" % [sd,
			"WIN" if r["win"] else ("LOSS" if r["lost"] else "TIME"), r["t"], r["dealt"], r["dealt"] / maxf(r["t"], 0.01),
			r["taken"], r["taken"] / maxf(r["t"], 0.01), r["swings"], r["hits"], r["rolls"], r["hp"], r["max_hp"]])
		if r["win"]:
			wins += 1
			ttk += r["t"]
		dealt += r["dealt"]
		taken += r["taken"]
		secs += r["t"]
		swings += r["swings"]
		hits += r["hits"]
		rolls += r["rolls"]
	print("ARENA %s:%d (%s) vs %s x%d, %d seeds: win %d%%, time to kill %s, hero dps %.2f, taken dps %.2f, swings/s %.2f, hit rate %.0f%%, SRD DPR %.2f (dps/DPR %.2f)" % [
		cls, level, opts.get("weapon", "default"), slug, count, seeds.size(), roundi(100.0 * wins / seeds.size()),
		"%.1f s" % (ttk / wins) if wins > 0 else "-", dealt / maxf(secs, 0.01), taken / maxf(secs, 0.01),
		swings / maxf(secs, 0.01), 100.0 * hits / maxi(rolls, 1), srd_dpr, (dealt / maxf(secs, 0.01)) / maxf(srd_dpr, 0.01)])
	quit(0)

static func _seeds(spec: String) -> Array:
	if ".." in spec:
		var p := spec.split("..")
		return range(int(p[0]), int(p[1]) + 1)
	return [int(spec)]

static func flat_world() -> TileWorld:
	var w := TileWorld.new(256, 64, 1)
	var stone := TileDefs.id("stone")
	for x in w.width:
		for y in 20:
			w.set_fg(x, y, stone, true)
	return w

func _fight(cls: String, level: int, slug: String, count: int, sd: int, limit: float) -> Dictionary:
	var host := WorldHost.new(flat_world())
	host.rng.seed = hash("arena:%d" % sd)
	var combat := CombatSystem.new()
	host.add_system(combat)
	combat.record = true
	var hero := host.add_player("hero", 1, {"class": cls})
	var srd := host.srd
	var ch := hero.character
	while ch.level < level:
		ch.gain_level()
	ch.auto_choices(srd)
	ch.hp = ch.max_hp()
	hero.combatant = ch.make_combatant(srd)
	var c := hero.combatant
	if opts.has("weapon"):
		c.weapon = srd.make_weapon(String(opts["weapon"]))
		c.is_proficient_with_weapon = true
		if c.kit != null and not c.weapon.slug in c.kit.weapon_masteries and c.kit.weapon_masteries.size() > 0:
			c.kit.weapon_masteries[0] = c.weapon.slug
		var props := CombatTempo.weapon_props(srd, c.weapon)
		if "two_handed" in props or "versatile" in props:
			c.equipment.shield = null
	hero.stats = ch.move_stats(c)
	hero.body.pos = Vector2(60.5, 20)
	var monsters: Array[HostEntity] = []
	var spread := float(opts.get("spread", 3))
	for i in count:
		var m: HostEntity
		if slug == "dummy":
			m = host.add_srd_monster("ogre", Vector2(66.5 + spread * i, 20), null)
			m.combatant.stats.max_hp = 100000
			m.combatant.stats.current_hp = 100000
			m.combatant.equipment.natural_ac = int(opts.get("ac", 15))
		else:
			m = host.add_srd_monster(slug, Vector2(72.5 + spread * i, 20), CombatBrain.new())
		monsters.append(m)
	var hb := hero.body.duplicate_body()
	var seq := 0
	var dealt := 0
	var taken := 0
	var hits := 0
	var rolls := 0
	var swings := 0
	var kite := opts.has("kite") and c.weapon != null and c.weapon.is_ranged()
	var reach := K.ft(CombatTempo.reach_ft(srd, c.weapon))
	var t := 0.0
	var lost := false
	var target_ac := 0
	while t < limit:
		var foe: HostEntity = null
		var bd := 1e9
		for m in monsters:
			if host.entities.has(m.id) and m.combatant.current_hp > 0 and absf(m.body.pos.x - hb.pos.x) < bd:
				bd = absf(m.body.pos.x - hb.pos.x)
				foe = m
		if foe == null:
			break
		target_ac = foe.combatant.armor_class
		var inp := PlayerInput.new()
		var dx := foe.body.pos.x - hb.pos.x
		var g := HitShapes.gap(hb.rect(), foe.body.rect())
		if kite:
			if g < 10.0:
				inp.move_x = -signf(dx)
			elif g > 20.0:
				inp.move_x = signf(dx)
		elif g > reach * 0.8:
			inp.move_x = signf(dx)
		hb.facing = 1 if dx >= 0.0 else -1
		if (kite and g <= 30.0) or g <= reach:
			combat.start_attack(hero, -1, foe.body.rect().get_center())
		inp = combat.filter_input(hero, inp)
		for k in 2:
			PlayerController.step(host.world, hb, inp, hero.stats, 1.0 / 60.0)
			seq += 1
		host.submit_state(hero.id, hero.epoch, seq, hb.pos, hb.vel, HostEntity.body_flags(hb))
		if hero.body.pos.distance_to(hb.pos) > 0.01:
			hb = hero.body.duplicate_body()   # corrected (respawn, push)
		host.tick()
		host.drain()
		t += 1.0 / K.TICK_HZ
		for ev: Dictionary in combat.recorded:
			var k := int(ev["kind"])
			if k == CombatCodec.Ev.DAMAGE:
				if int(ev["src"]) == hero.id:
					dealt += int(ev["amount"])
				if int(ev["dst"]) == hero.id:
					taken += int(ev["amount"])
			elif int(ev["src"]) == hero.id and k in [CombatCodec.Ev.HIT, CombatCodec.Ev.CRIT, CombatCodec.Ev.MISS]:
				rolls += 1
				if k != CombatCodec.Ev.MISS:
					hits += 1
			elif k == CombatCodec.Ev.SWING and int(ev["src"]) == hero.id:
				swings += 1
			elif k == CombatCodec.Ev.DOWNED and int(ev["dst"]) == hero.id:
				lost = true
		combat.recorded.clear()
		if lost:
			break
	var win := not lost and slug != "dummy" and monsters.all(func(m: HostEntity) -> bool: return m.combatant.current_hp <= 0)
	return {"win": win, "lost": lost, "t": t, "dealt": dealt, "taken": taken, "swings": swings,
		"hits": hits, "rolls": rolls, "hp": c.current_hp, "max_hp": c.stats.max_hp,
		"srd_dpr": srd_dpr(c, target_ac if target_ac > 0 else int(opts.get("ac", 15)), srd)}

## The SRD's expected weapon damage per round (one Attack action, no bonus actions):
## attacks x (P(hit) x average damage + P(crit) x average extra dice).
static func srd_dpr(c: Combatant, ac: int, srd: SRDContent) -> float:
	var w := c.weapon
	var bonus := c.attack_modifier()
	var crit_on := c.kit.crit_threshold() if c.kit != null else 20
	var p_crit := (21 - crit_on) / 20.0
	var p_hit := clampf((21 - (ac - bonus)) / 20.0, p_crit, 0.95)
	var two := w != null and "versatile" in CombatTempo.weapon_props(srd, w) and c.equipment.shield == null
	var dice := 0.0
	var mod := 0.0
	if w == null:
		mod = 1 + c.stats.ability_modifier(SRD.Ability.STRENGTH)
	else:
		var n := w.versatile_die_count if two and w.versatile_die_count > 0 else w.die_count
		var s := w.versatile_die_sides if two and w.versatile_die_count > 0 else w.die_sides
		dice = n * (s + 1) / 2.0
		mod = w._damage_mod(c.stats) + c.bonus_damage
		if c.kit != null and c.kit.has_style("dueling") and not two and not w.is_ranged():
			mod += 2
	var n_att := c.kit.attacks_per_action() if c.kit != null else 1
	return n_att * (p_hit * (dice + mod) + p_crit * dice)

func _report(what: String) -> void:
	var srd := WorldHost.shared_srd()
	if what == "spells":
		var ok := 0
		var by_shape := {}
		var refused := {}
		var partial := PackedStringArray()
		for row: Dictionary in srd.pack.rows("spell"):
			var ab := srd.make_spell(String(row["slug"]))
			var why := CombatSystem.spell_support(ab)
			if why == "":
				ok += 1
				var sh := CombatSystem.spell_shape(ab)
				by_shape[sh] = int(by_shape.get(sh, 0)) + 1
				if SRDContent.TAG_PARTIAL in ab.tags:
					partial.append(String(row["slug"]))
			else:
				var key := why.get_slice(" (", 0) if not why.begins_with("casting time") else "casting time (not action / bonus / reaction)"
				if not refused.has(key):
					refused[key] = PackedStringArray()
				refused[key].append(String(row["slug"]))
		print("SPELLS %d resolve through the shapes: %s" % [ok, by_shape])
		print("  of those, partial in the addon (damage works, a rider does not): %d" % partial.size())
		for k: String in refused:
			print("  refused %d: %s: %s" % [refused[k].size(), k, ", ".join(refused[k].slice(0, 12)) + (" ..." if refused[k].size() > 12 else "")])
	elif what == "monsters":
		var n := 0
		var multi := 0
		var multi_missing := PackedStringArray()
		var attacks := 0
		var saves := 0
		var unsup := {}
		var no_attack := PackedStringArray()
		for row: Dictionary in srd.pack.rows("monster"):
			n += 1
			var m := MonsterMoves.of(srd, String(row["slug"]))
			for a: Dictionary in m["actions"]:
				if a["kind"] == "save":
					saves += 1
				else:
					attacks += 1
			for u: String in m["unsupported"]:
				unsup[u] = int(unsup.get(u, 0)) + 1
			var has_multi := (row["data"].get("actions", []) as Array).any(func(a: Dictionary) -> bool: return a.get("name") == "Multiattack")
			if has_multi:
				if (m["multi"] as Array).is_empty():
					multi_missing.append(String(row["slug"]))
				else:
					multi += 1
			if int(m["default"]) < 0:
				no_attack.append(String(row["slug"]))
		var keys := unsup.keys()
		keys.sort_custom(func(x: String, y: String) -> bool: return unsup[x] > unsup[y])
		print("MONSTERS %d: %d attack actions and %d save actions supported; Multiattack parsed for %d, not for %d (%s)" % [
			n, attacks, saves, multi, multi_missing.size(), ", ".join(multi_missing.slice(0, 10))])
		print("  no attack action at all: %d (%s)" % [no_attack.size(), ", ".join(no_attack.slice(0, 10))])
		print("  unsupported actions: %d kinds, %d uses; most common: %s" % [keys.size(), unsup.values().reduce(func(x, y): return x + y, 0),
			", ".join(keys.slice(0, 15).map(func(k: String) -> String: return "%s (%d)" % [k, unsup[k]]))])
