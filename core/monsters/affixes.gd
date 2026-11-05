## Elite and champion affixes (data/ecology/affixes.json), acting through real time, tiles and
## other systems, never through attack bonus, AC or save DCs:
##   frenzied       combat.set_pace: what follows the wind-up is faster (the telegraph is kept)
##   shielded       a ward of temporary hit points broken first, regrown out of combat
##   splitting      on death, two smaller minions of its kind
##   tunnelling     digs soft tiles to reach you (its paths go through them; NavFollow digs)
##   lantern_eater  eats lit torches near it (tiles turned to air)
##   tethered       half of each hit is passed to a packmate nearby
##   gilded         sheds coin when hit (items.drop)
##   magnetic       pulls loot on the ground to itself (the items system's drops)
##   howling        on first sighting calls more of its pack (the director, off-screen)
##   thorned        melee attackers take 1d6 piercing (combat.damage)
##   skittering     runs faster
class_name Affixes
extends RefCounted

static var _tethering := false

static func def(id: String) -> Dictionary:
	return Ecology.affixes().get(id, {})

static func tick(sys: MonstersSystem, e: HostEntity, b: MonsterBrain, dt: float, combat: Variant) -> void:
	var rec: Dictionary = b.rec
	var af: Array = rec["affixes"]
	var h := sys.host
	if "shielded" in af:
		var in_fight: bool = combat != null and combat.has_method("in_combat") and combat.in_combat(e)
		rec["calm_t"] = 0.0 if in_fight else float(rec["calm_t"]) + dt
		var d := def("shielded")
		if float(rec["calm_t"]) >= float(d.get("regen_after_s", 6.0)) and e.combatant.stats.temp_hp < int(rec["ward_max"]):
			var add := maxi(1, roundi(int(rec["ward_max"]) * float(d.get("regen_per_s", 0.2)) * dt))
			e.combatant.stats.temp_hp = mini(int(rec["ward_max"]), e.combatant.stats.temp_hp + add)
	rec["fx_t"] = float(rec["fx_t"]) + dt
	if "lantern_eater" in af and float(rec["fx_t"]) >= float(def("lantern_eater").get("every_s", 1.5)):
		_eat_lights(sys, e, int(def("lantern_eater").get("radius", 6)))
	if "magnetic" in af and int(h.tick_count) % maxi(1, roundi(float(def("magnetic").get("every_s", 0.5)) * K.TICK_HZ)) == 0:
		_pull_loot(sys, e)
	if "howling" in af and not rec["howled"] and b.target_id != 0:
		rec["howled"] = true
		var calls: Array = def("howling").get("calls", [2, 4])
		var n := sys.rng.randi_range(int(calls[0]), int(calls[1]))
		sys.stats["howls"] += sys.director.call_pack(e, b, n)
	if float(rec["fx_t"]) >= 1.5:
		rec["fx_t"] = 0.0

## A hit landed on a monster with affixes (before combat's 0 HP check).
static func on_damage(sys: MonstersSystem, e: HostEntity, b: MonsterBrain, dealt: int, src: int) -> void:
	var af: Array = b.rec["affixes"]
	if af.is_empty():
		return
	var h := sys.host
	var combat := h.system(HostSystem.COMBAT)
	var attacker := h.entity(src)
	if "tethered" in af and not _tethering and e.combatant.current_hp > -dealt:
		var mate := _mate(sys, e, b, float(def("tethered").get("range", 24)))
		if mate != null and combat != null:
			var share := int(floor(dealt * float(def("tethered").get("share", 0.5))))
			if share > 0:
				_tethering = true
				e.combatant.stats.current_hp = mini(e.combatant.stats.max_hp, e.combatant.stats.current_hp + share)
				combat.call("damage", src, mate, share, "force", {"what": "tether"})
				_tethering = false
				sys.stats["tether"] += 1
	if "gilded" in af and not _tethering:
		var items := h.system(HostSystem.ITEMS)
		var d := def("gilded")
		if items != null and items.has_method("drop") and int(b.rec["coins"]) < int(d.get("max_coins", 60)):
			var r: Array = d.get("coin_per_hit", [1, 6])
			var n := mini(sys.rng.randi_range(int(r[0]), int(r[1])), int(d.get("max_coins", 60)) - int(b.rec["coins"]))
			b.rec["coins"] = int(b.rec["coins"]) + n
			items.call("drop", e.body.center(), [{"base": "coin", "count": n}], e.id)
			sys.stats["coins"] += n
	if "thorned" in af and attacker != null and attacker.is_player() and combat != null and not _tethering:
		var d2 := def("thorned")
		if HitShapes.gap(e.body.rect(), attacker.body.rect()) <= float(d2.get("reach", 3.0)):
			var dice := SRDContent.parse_dice(String(d2.get("dice", "1d6")))
			var n2 := Dice.roll_nd(int(dice.get("count", 1)), int(dice.get("sides", 6)))
			_tethering = true
			combat.call("damage", e.id, attacker, n2, String(d2.get("dtype", "piercing")), {"what": "thorns"})
			_tethering = false
			sys.stats["thorns"] += 1

static func _mate(sys: MonstersSystem, e: HostEntity, b: MonsterBrain, r: float) -> HostEntity:
	if b.pack_id == 0:
		return null
	var best: HostEntity = null
	var bd := r
	for id: int in sys.mons:
		var o: MonsterBrain = sys.mons[id]
		if id == e.id or o.pack_id != b.pack_id or o.rec["dead"]:
			continue
		var m := sys.host.entity(id)
		if m == null or m.combatant == null or m.combatant.current_hp <= 0:
			continue
		var d := m.body.pos.distance_to(e.body.pos)
		if d <= bd:
			bd = d
			best = m
	return best

static func _eat_lights(sys: MonstersSystem, e: HostEntity, r: int) -> void:
	var w := sys.host.world
	var torch := TileDefs.id("torch")
	var c := e.body.center()
	for y in range(floori(c.y) - r, floori(c.y) + r + 1):
		for x in range(floori(c.x) - r, floori(c.x) + r + 1):
			if w.get_fg(x, y) == torch and Vector2(x + 0.5, y + 0.5).distance_to(c) <= r:
				w.set_fg(x, y, TileDefs.AIR)
				sys.stats["eaten"] += 1
				return             # one torch per bite

static func _pull_loot(sys: MonstersSystem, e: HostEntity) -> void:
	var items := sys.host.system(HostSystem.ITEMS)
	if items == null:
		return
	var drops: Variant = items.get("drops")
	if drops == null:
		return
	var d := def("magnetic")
	var r := float(d.get("radius", 10))
	var c := e.body.center()
	for id: int in drops.list:
		var dr: Variant = drops.list[id]
		var off: Vector2 = c - dr.pos
		var dist := off.length()
		if dist <= r and dist > 1.0:
			dr.vel = off.normalized() * float(d.get("pull", 4.0)) + Vector2(0, 2.0)
			dr.rest = false

## Mitotic: the dead monster becomes two smaller minions of its kind.
static func split(sys: MonstersSystem, e: HostEntity, b: MonsterBrain) -> void:
	var sizes := MoveStats.SIZES
	var size := e.stats.size_name
	var i := maxi(0, sizes.find(size) - 1)
	var n := int(def("splitting").get("children", 2))
	for k in n:
		var pos := e.body.pos + Vector2((k - (n - 1) * 0.5) * 1.5, 0.3)
		var c := sys.spawn(b.slug, pos, {"rank": "minion", "size": sizes[i], "scale": 0.75, "pack": b.pack_id,
			"slot": b.slot + k + 1, "home": b.home, "group": int(b.rec["group"]), "people": String(b.rec.get("people", ""))})
		if c != null:
			var cb: MonsterBrain = c.brain
			cb.target_id = b.target_id
			cb.provoked = b.provoked.duplicate()
			cb.state = MonsterBrain.State.CHASE if b.target_id != 0 else MonsterBrain.State.IDLE
			sys.stats["split"] += 1
