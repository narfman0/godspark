## What a swing looks like and that looks are all it is: the tempo classes' clips land their
## contact on the data's wind-up, combos read as different moves, the highlight names the
## creature the host then hits, the telegraph is the shape the host tests, and the hit-stop
## never reaches a simulation tick. Clips and meshes are checked when the art is fetched; a
## fresh checkout still has a weapon and a swing on a primitive.
extends RefCounted

const Rig := preload("res://tests/net_rig.gd")
const Combat := preload("res://tests/test_combat.gd")
const Ev := CombatCodec.Ev
const STEP := 1.0 / 60.0

func run(t: TestLog) -> void:
	_data(t)
	_contact_on_windup(t)
	_combos(t)
	_modes(t)
	await _clip_on_a_body(t)
	_forge_clips(t)
	_primitive(t)
	_telegraph_shape(t)
	_hit_stop_numbers(t)
	_hit_stop_never_ticks(t)
	_highlight_and_timing(t)

func _data(t: TestLog) -> void:
	var sw := SwingPlan.conf()
	var moves: Dictionary = sw["moves"]
	var clips: Dictionary = sw["clips"]
	for m: String in moves:
		for part: String in ["pre", "post"]:
			t.check(clips.has(String(moves[m][part][0])), "%s %s names a clip" % [m, part])
		t.check(float(moves[m]["pre"][1]) <= float(moves[m]["pre"][2]) and float(moves[m]["post"][1]) <= float(moves[m]["post"][2]), "%s runs forward" % m)
	for cls: String in CombatTempo.section("weapon_tempo"):
		if not cls.begins_with("_"):
			t.check((sw["tempo"] as Dictionary).has(cls), "tempo class %s has moves" % cls)
	for cls: String in sw["tempo"]:
		for m: String in sw["tempo"][cls]:
			t.check(moves.has(m), "%s names the move %s" % [cls, m])
	t.check(not Looks.weapon("Longsword").is_empty() and Looks.weapon("Longsword") == Looks.weapon("longsword"), "a shown name finds the row")
	t.check(not Looks.weapon("War Pick").is_empty(), "with its spaces")
	t.eq(Looks.weapon("Bite"), {}, "a stat block's bite has none")

## Every tempo class, at the numbers of data/combat.json: at the wind-up the clip stands at the
## move's contact, and the plan ends with the action.
func _contact_on_windup(t: TestLog) -> void:
	var tempos := CombatTempo.section("weapon_tempo").duplicate()
	var cast: Dictionary = CombatTempo.cast_tempo("action")
	tempos["cast"] = cast
	var moves: Dictionary = SwingPlan.conf()["moves"]
	for cls: String in tempos:
		if cls.begins_with("_"):
			continue
		var w := float(tempos[cls]["windup"])
		var total := w + float(tempos[cls]["recovery"])
		var ev := {"tempo": cls, "mode": CombatCodec.Mode.CAST if cls == "cast" else 0, "swings": 1, "windup": w, "gap": 0.0, "total": total}
		var plan := SwingPlan.build(ev)
		var m: Dictionary = moves[String(SwingPlan.chain(cls, int(ev["mode"]))[0])]
		var at := SwingPlan.at(plan, w - 1e-5)
		t.eq(at["clip"], String(m["pre"][0]), "%s: the wind-up plays its clip" % cls)
		t.check(absf(float(at["time"]) - float(m["pre"][2])) < 1e-3, "%s: contact at %.2f s, clip time %.3f of %.3f" % [cls, w, at["time"], m["pre"][2]])
		var after := SwingPlan.at(plan, w + 1e-4)
		t.check(absf(float(after["time"]) - float(m["post"][1])) < 1e-2, "%s: from there the recovery" % cls)
		t.check(absf(SwingPlan.length(plan) - total) < 1e-6, "%s: the plan lasts the action" % cls)
		t.check(absf(float(SwingPlan.at(plan, 0.0)["time"]) - float(m["pre"][1])) < 1e-6, "%s: it starts at the move's start" % cls)
	t.eq(SwingPlan.at([], 0.0), {}, "no plan, no clip")

func _combos(t: TestLog) -> void:
	var tempo := CombatTempo.weapon_tempo("plain")
	var tl := CombatTempo.timeline(tempo, 3)
	var ev := {"tempo": "plain", "mode": 0, "swings": 3, "windup": tl["windup"], "gap": tl["gap"], "total": tl["total"]}
	var plan := SwingPlan.build(ev)
	var moves: Dictionary = SwingPlan.conf()["moves"]
	var names: Array = SwingPlan.chain("plain", 0)
	for i in 3:
		var c: float = tl["contacts"][i]
		var at := SwingPlan.at(plan, c - 1e-5)
		var m: Dictionary = moves[String(names[i])]
		t.eq(at["clip"], String(m["pre"][0]), "swing %d is its own move" % i)
		t.check(absf(float(at["time"]) - float(m["pre"][2])) < 1e-3, "swing %d lands on contact %d" % [i, i])
	t.check(SwingPlan.at(SwingPlan.build(ev, 1), 0.0)["clip"] != SwingPlan.at(plan, 0.0)["clip"], "a held attack carries on along the chain")
	t.check(SwingPlan.clips_of("plain").size() >= 3, "the clips a class needs are known ahead")

func _modes(t: TestLog) -> void:
	t.eq(SwingPlan.chain("monster", CombatCodec.Mode.RANGED), SwingPlan.chain("bow", 0), "a stat block's shot draws a bow")
	t.eq(SwingPlan.chain("plain", CombatCodec.Mode.THROW), SwingPlan.chain("thrown", 0), "a thrown blade throws")
	t.eq(SwingPlan.chain("monster", CombatCodec.Mode.SAVE_ACTION), SwingPlan.chain("cast", 0), "a breath or a spell casts")
	t.check(SwingPlan.single("roll", 0.4).size() == 1, "the roll is one segment over its time")
	t.eq(SwingPlan.length(SwingPlan.single("roll", 0.4)), 0.4, "of the roll's length")

## With the art: the real retargeted clip on a real skeleton, stepped as a frame would be.
func _clip_on_a_body(t: TestLog) -> void:
	var def: Dictionary = Looks.table()["models"]["knight"]
	if not GltfCache.exists(String(def["path"])) or not GltfCache.exists(String(SwingPlan.conf()["clips"]["light_a"])):
		t.check(true, "no art fetched: the clip check is skipped")
		return
	var cv := CharacterVisual.new()
	t.check(cv.setup(def, Looks.table().get("clips", {}), 1.8), "the knight loads")
	for cls: String in ["plain", "heavy"]:
		var tempo := CombatTempo.weapon_tempo(cls)
		var w := float(tempo["windup"])
		var ev := {"tempo": cls, "mode": 0, "swings": 1, "windup": w, "gap": 0.0, "total": w + float(tempo["recovery"])}
		var plan := SwingPlan.build(ev)
		t.check(cv.swing(plan, 0.0, 0.0), "%s swings" % cls)
		var at := SwingPlan.at(plan, w - 1e-5)
		var row: Array = cv.layer.clips[String(at["clip"])]
		var a: Animation = row[2]
		var hand := cv.skeleton.find_bone("Hand_R")
		var tr := -1
		for r: Array in row[0]:
			if int(r[0]) == hand:
				tr = int(r[1])
		cv.step(w - 1e-5, false)
		var want: Quaternion = a.rotation_track_interpolate(tr, float(at["time"]))
		t.check(cv.skeleton.get_bone_pose_rotation(hand).angle_to(want) < 0.02, "%s: at the wind-up the hand stands at the clip's contact" % cls)
		cv.layer.stop()
		cv.step(1.0, false)
		t.check(not cv.layer.active(), "%s: and it lets go" % cls)
	cv.set_weapon("longsword")
	t.check(cv.find_children("*", "MeshInstance3D", true, false).size() > 1, "the weapon is in the hand")
	var ok := true
	for cls: String in ["plain", "light", "heavy", "versatile_two", "bow", "thrown", "unarmed"]:
		for c: String in SwingPlan.clips_of(cls):
			ok = ok and cv.load_swing_clip(c)
	t.check(ok, "every clip of every class retargets onto the knight")
	cv.free()
	GltfCache.clear()

func _forge_clips(t: TestLog) -> void:
	if not ForgeMonster.is_synced("goblin-warrior"):
		t.check(true, "no forge art: skipped")
		return
	var m := ForgeMonster.load_monster("goblin-warrior")
	var at := m.contact_of("attack_melee")
	t.check(at > 0.0 and at < m.anim.get_animation("attack_melee").length, "the goblin's blow falls inside its clip (%.3f)" % at)
	var w := float(CombatTempo.weapon_tempo("monster")["windup"])
	t.check(m.swing("attack_melee", w, w + 0.6, 0.02, 0.1), "it swings")
	t.eq(float(SwingPlan.at(m.layer.plan, w - 1e-5)["time"]) > at - 1e-3, true, "its contact on its wind-up")
	t.eq(m.wielded(), "scimitar", "the forge says what it wields")
	m.free()

## A fresh checkout: a primitive body still swings, rolls, flinches and holds a bar.
func _primitive(t: TestLog) -> void:
	var a := ActorBody.build({"kind": "goblin", "size": Vector2(1.2, 1.8), "color": Color.GREEN}, null)
	t.eq(a.kind, "primitive", "no slug: a primitive")
	a.set_weapon("longsword")
	a.set_weapon("Some Unlisted Blade")
	a.swing({"tempo": "plain", "mode": 0, "swings": 1, "windup": 0.2, "gap": 0.0, "total": 0.6}, Vector2(-1, 0))
	t.eq(a._face, -1, "a swing turns the body to its aim")
	a._process(0.05)
	a.roll(0.4)
	a._process(0.2)
	t.check(absf(a.visual.rotation.x) > 0.1, "a tucked spin stands in for the roll")
	a.flinch()
	a.set_rim(Color.RED)
	a.flash(Color.WHITE, 0.1)
	a._process(0.2)
	a.set_rim(Color(0, 0, 0, 0))
	t.check(WeaponMesh.build({}) != null, "an unmapped weapon is a bar")
	a.free()

func _telegraph_shape(t: TestLog) -> void:
	var half := float(CombatTempo.section("melee")["arc_half_angle_deg"])
	var size := Vector2(1.5, 2.5)
	var d := Telegraphs.for_swing({"mode": CombatCodec.Mode.MELEE, "aim": Vector2(14, 11), "reach_ft": 10.0}, Vector2(10, 10), size)
	t.eq(float(d["half"]), half, "the arc's angle is the data's")
	t.check(absf(float(d["size"]) - (size.x * 0.5 + K.ft(10.0))) < 1e-4, "a pike's arc reaches ten feet past the box")
	t.eq(d["box"], size * 0.5, "from the box, as the host measures")

func _hit_stop_numbers(t: TestLog) -> void:
	var f := CombatTempo.section("feel")
	t.eq(HitStop.seconds(Ev.HIT, 5, 5), float(f["hit_stop_s"]), "the own hit stops for the data's time")
	t.check(HitStop.seconds(Ev.HIT, 5, 5) > 0.04 and HitStop.seconds(Ev.HIT, 5, 5) < 0.09, "about 60 ms")
	t.eq(HitStop.seconds(Ev.CRIT, 5, 5), float(f["crit_stop_s"]), "a crit a bit longer")
	t.eq(HitStop.seconds(Ev.HIT, 7, 5), 0.0, "another creature's hit does not stop this client")
	t.eq(HitStop.seconds(Ev.MISS, 5, 5), 0.0, "a miss does not stop")

## The same fight twice, once with every blow held on the view's side as FxView holds it: the
## same ticks, the same events, the same body positions, and the clock's rate never touched.
func _hit_stop_never_ticks(t: TestLog) -> void:
	var plain := _fight(false)
	var held := _fight(true)
	t.eq(held["ticks"], plain["ticks"], "the same number of ticks")
	t.eq(held["events"], plain["events"], "the same blows on the same ticks")
	t.eq(held["pos"], plain["pos"], "and the same bodies")
	t.check(int(held["holds"]) > 0, "the holds really ran (%d)" % held["holds"])
	t.eq(Engine.time_scale, 1.0, "time is never scaled")

func _fight(hold: bool) -> Dictionary:
	var r := Combat.rig(9)
	var combat: CombatSystem = r["combat"]
	var h := Combat.hero(r)
	var g := Combat.monster(r, "goblin-warrior", 62.5, 200)
	Combat.ticks(r, 1)
	combat.record = true
	var body := ActorBody.build({"kind": "x", "size": Vector2(1.5, 2.5)}, null)
	var holds := 0
	var seen := 0
	for i in 200:
		if not combat.busy(h):
			combat.now = r["host"].tick_count / float(K.TICK_HZ)
			combat.start_attack(h, -1, Combat.center(g))
		Combat.ticks(r, 1)
		while hold and seen < combat.recorded.size():
			var ev: Dictionary = combat.recorded[seen]
			seen += 1
			var s := HitStop.seconds(int(ev["kind"]), int(ev["src"]), h.id)
			if s > 0.0:
				body.hold(s)
				holds += 1
			body._process(1.0 / K.TICK_HZ)
	body.free()
	return {"ticks": r["host"].tick_count, "pos": [h.body.pos, g.body.pos], "holds": holds,
		"events": combat.recorded.map(func(ev: Dictionary) -> String: return "%d %s" % [ev.get("t", 0), CombatCodec.describe(ev)])}

## Over the loopback: target_at names the creature the blow then lands on, and from the SWING
## on the client the contact is a wind-up less the head start away.
func _highlight_and_timing(t: TestLog) -> void:
	var rig := Rig.new(Combat.flat_world(), 0.05)
	var combat := CombatSystem.new()
	rig.host.add_system(combat)
	combat.record = true
	var cc := CombatClient.new()
	var c := rig.add_client("ann")
	c.welcomed.connect(func(cw: ClientWorld) -> void: cw.add_system(cc))
	t.check(rig.until(func() -> bool: return c.cw != null and c.cw.area_ready() and not c.cw.frozen, 6.0) >= 0.0, "joined")
	rig.run(0.5)
	var he := rig.host_entity(0)
	var near := rig.host.add_srd_monster("goblin-warrior", he.body.pos + Vector2(2.5, 0.0))
	var far := rig.host.add_srd_monster("goblin-warrior", he.body.pos + Vector2(3.5, 0.0))
	var away := rig.host.add_srd_monster("goblin-warrior", he.body.pos + Vector2(-20.0, 0.0))
	for m: HostEntity in [near, far, away]:
		m.combatant.stats.max_hp = 500
		m.combatant.stats.current_hp = 500
	rig.run(0.6)
	var cw := rig.cw(0)
	t.check(cw.remotes.has(near.id) and cw.remotes.has(away.id), "the client sees them")
	var aim := near.body.rect().get_center()
	var pick := cc.target_at(aim)
	t.eq(pick.get("id"), near.id, "the nearer of two in the arc")
	t.eq(pick.get("reach"), true, "in reach")
	var under := cc.target_at(away.body.rect().get_center())
	t.eq(under, {"id": away.id, "reach": false}, "a foe under the aim, out of reach, is named as that")
	t.eq(cc.target_at(he.body.pos + Vector2(0.0, 30.0)), {}, "nobody at all")
	var swing_at := [-1.0]
	var hit_at := [-1.0]
	var clock := [0.0]
	cc.event.connect(func(ev: Dictionary) -> void:
		if int(ev["kind"]) == Ev.SWING and int(ev["src"]) == cw.my_id:
			swing_at[0] = clock[0]
		elif int(ev["kind"]) in [Ev.HIT, Ev.MISS, Ev.CRIT, Ev.WHIFF] and int(ev["src"]) == cw.my_id and hit_at[0] < 0.0:
			hit_at[0] = clock[0])
	cc.status["action"] = 0.0
	cc.attack(aim)
	for i in 240:
		rig.frame()
		clock[0] += 1.0 / 60.0
		if hit_at[0] >= 0.0:
			break
	t.check(swing_at[0] >= 0.0 and hit_at[0] > swing_at[0], "the blow arrived")
	var w := float(CombatTempo.weapon_tempo("plain")["windup"])
	var gap: float = hit_at[0] - swing_at[0]
	t.check(absf(gap - (w - SwingPlan.HEAD_START)) <= 1.5 / K.TICK_HZ, "the view's clock meets the contact (%.3f after the SWING)" % gap)
	var dst := -1
	for ev: Dictionary in combat.recorded:
		if int(ev["kind"]) in [Ev.HIT, Ev.MISS, Ev.CRIT]:
			dst = int(ev["dst"])
			break
	t.eq(dst, near.id, "the highlighted creature is the one the host rolled against")
