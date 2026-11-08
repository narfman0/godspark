## In-world feedback (view/fx/), a child of WorldView: floating numbers, nameplates, wind-up
## telegraphs and the spell aiming preview, drops on the ground, projectiles, swings and their
## contacts (SwingFx), the target highlight, hit flashes and the hit-stop on actors, and the
## sigil flash over the own character when a spark fires (a dash, an air jump, a glide). Reads
## the client world and its systems; owns no game state. Every tunable: data/combat.json "feel".
##
## The target highlight: CombatClient.target_at(aim), the host's own choice of what the next
## blow touches, outlines that creature and draws the arc that must reach it (its hit point bar
## shows only while hurt and recently hit or healed: Nameplates.show_rule).
##
## Projectiles: the combat client's PROJECTILE events carry pos, vel and gravity; they are
## stepped here until their IMPACT (or a wall, or 4 s).
class_name FxView
extends Node3D

const PROJ_LIFE := 4.0

var cw: ClientWorld
var view: WorldView
var overlay: CanvasLayer
var numbers: FloatingNumbers
var plates: Nameplates
var telegraphs: Telegraphs
var drops: DropsView
var swings: SwingFx
var srd: SRDContent
## What the next swing would land on: {id, reach} from CombatClient.target_at.
var target := {}
## Actors this client cannot see (UnseenRule GONE): no plate, no target ring. id -> true.
var unseen := {}
## Where the aim is, when a script holds it (Vector2.INF: the mouse).
var aim_override := Vector2.INF
## Monsters winding up: id -> [seconds in, seconds of wind-up].
var windups := {}
var _rimmed := {}
var _crit := {}
## pid -> {pos, vel, g, node, t}
var projectiles := {}
var _sigil: Sprite3D
var _sigil_t := -1.0
var _was := {}
var _areas := {}
## Microseconds per frame spent here (the tour reports it).
var frame_usec := PackedInt32Array()
var _proj_mats := {}
var _proj_mesh: BoxMesh

func setup(client: ClientWorld, v: WorldView) -> void:
	cw = client
	view = v
	overlay = CanvasLayer.new()
	overlay.layer = 4
	add_child(overlay)
	plates = Nameplates.new()
	plates.fx = self
	overlay.add_child(plates)
	numbers = FloatingNumbers.new()
	numbers.fx = self
	overlay.add_child(numbers)
	telegraphs = Telegraphs.new()
	add_child(telegraphs)
	swings = SwingFx.new()
	add_child(swings)
	drops = DropsView.new()
	add_child(drops)
	drops.setup(cw.system(HostSystem.ITEMS) as ItemsClient)
	_proj_mesh = BoxMesh.new()
	_proj_mesh.size = Vector3(0.7, 0.1, 0.1) * K.TILE_M
	_sigil = Sprite3D.new()
	_sigil.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sigil.shaded = false
	_sigil.no_depth_test = true
	_sigil.pixel_size = 0.018
	_sigil.modulate = Color(1, 0.9, 0.6, 0)
	_sigil.visible = false
	add_child(_sigil)
	var items := cw.system(HostSystem.ITEMS) as ItemsClient
	if items != null:
		items.constellation_changed.connect(_refresh_sigil)
		_refresh_sigil()
	var mons := cw.system(HostSystem.MONSTERS)
	if mons != null and mons.has_signal("monster_info"):
		# shown names ("Lantern-Eater"), not ids ("lantern_eater")
		mons.connect("monster_info", func(id: int, inf: Dictionary) -> void:
			plates.set_info(id, {"rank": inf.get("rank", ""), "affixes": inf.get("names", inf.get("affixes", []))}))
		# what the client already heard before this view existed (a join, a rebuilt view)
		for id: int in mons.get("infos"):
			plates.set_info(id, {"rank": mons.get("infos")[id].get("rank", ""), "affixes": mons.get("infos")[id].get("names", [])})

func _refresh_sigil() -> void:
	var items := cw.system(HostSystem.ITEMS) as ItemsClient
	if items == null:
		return
	_sigil.texture = ImageTexture.create_from_image(SigilLayout.image(items.sigil(), 64))

func actor_added(id: int, look: Dictionary) -> void:
	# our nameplates replace the actors' own (the HUD names the own player)
	var a := view.get_actor(id)
	if a != null and a.nameplate != null:
		a.nameplate.visible = false
	if look.has("rank"):
		plates.set_info(id, {"rank": String(look["rank"])})

func actor_removed(id: int) -> void:
	plates.forget(id)
	windups.erase(id)
	_rimmed.erase(id)

## Where an entity's feet are and how big it is (tiles).
func actor_box(id: int) -> Array:
	if id == cw.my_id:
		return [cw.view_pos(), cw.body.size]
	var r: ClientWorld.RemoteEntity = cw.remotes.get(id)
	if r == null:
		return []
	return [r.pos, r.size]

func _head(id: int) -> Vector2:
	var b := actor_box(id)
	return Vector2.INF if b.is_empty() else (b[0] as Vector2) + Vector2(0, (b[1] as Vector2).y)

## The middle of an actor's box, tiles (Vector2.INF: not here).
func actor_center(id: int) -> Vector2:
	var b := actor_box(id)
	return Vector2.INF if b.is_empty() else (b[0] as Vector2) + Vector2(0, (b[1] as Vector2).y * 0.5)

## Where a blow from `src` lands on `dst`: the side of the box that faces it, at chest height.
func _contact_at(src: int, dst: int) -> Vector2:
	var c := actor_center(dst)
	var from := actor_center(src)
	if c == Vector2.INF or from == Vector2.INF:
		return c
	var half := (actor_box(dst)[1] as Vector2) * 0.5
	return Vector2(clampf(from.x, c.x - half.x, c.x + half.x), c.y)

func _size(key: String) -> int:
	return int(SwingFx.feel().get("number_size", {}).get(key, 22))

func _mark(src: int, dst: int, kind: int) -> void:
	var at := _contact_at(src, dst)
	if at != Vector2.INF:
		swings.mark(at, kind)

func _flash_on(id: int, crit: bool) -> void:
	var a := view.get_actor(id)
	if a == null:
		return
	var f := SwingFx.feel()
	a.flash(SwingFx.color("crit_flash" if crit else "flash"), float(f.get("crit_flash_s" if crit else "flash_s", 0.12)))

func _hit_stop(kind: int, src: int, dst: int) -> void:
	var s := HitStop.seconds(kind, src, cw.my_id)
	if s <= 0.0:
		return
	swings.hold(src, s)
	for id: int in [src, dst]:
		var a := view.get_actor(id)
		if a != null:
			a.hold(s)

func combat_event(ev: Dictionary) -> void:
	var src := int(ev["src"])
	var dst := int(ev["dst"])
	var mine := dst == cw.my_id
	match int(ev["kind"]):
		CombatCodec.Ev.DAMAGE:
			plates.changed(dst)
			var crit := bool(_crit.get(dst, false))
			_crit.erase(dst)
			var p := _head(dst)
			if p != Vector2.INF:
				numbers.spawn(dst, p, str(int(ev.get("amount", 0))), SwingFx.color("crit") if crit else (UiTheme.VERMILION.lightened(0.15) if mine else UiTheme.TEXT_LIGHT), _size("crit" if crit else "hit"))
			_flash_on(dst, crit)
		CombatCodec.Ev.HIT:
			swings.result(src, SwingFx.color("hit"))
			_mark(src, dst, SwingFx.Mark.HIT)
			_hit_stop(CombatCodec.Ev.HIT, src, dst)
		CombatCodec.Ev.CRIT:
			_crit[dst] = true
			swings.result(src, SwingFx.color("crit"), 1.0)
			_mark(src, dst, SwingFx.Mark.CRIT)
			_hit_stop(CombatCodec.Ev.CRIT, src, dst)
			var p2 := _head(dst)
			if p2 != Vector2.INF:
				numbers.spawn(dst, p2 + Vector2(0, float(SwingFx.feel().get("crit_label_rise", 1.4))), "Crit!", SwingFx.color("crit"), _size("crit_label"))
		CombatCodec.Ev.MISS:
			swings.result(src, SwingFx.color("miss"), 0.25)
			_mark(src, dst, SwingFx.Mark.MISS)
			var p3 := _head(dst)
			if p3 != Vector2.INF:
				numbers.spawn(dst, p3, "miss", SwingFx.color("miss"), _size("miss"))
		CombatCodec.Ev.WHIFF:
			swings.result(src, SwingFx.color("miss"), 0.2)
			var p6 := _head(dst) if dst != 0 else Vector2.INF
			if p6 != Vector2.INF:
				numbers.spawn(dst, p6, "dodged", SwingFx.color("slash"), _size("dodged"))
		CombatCodec.Ev.HEAL:
			plates.changed(dst)
			var p4 := _head(dst)
			if p4 != Vector2.INF and int(ev.get("amount", 0)) > 0:
				numbers.spawn(dst, p4, "+%d" % int(ev["amount"]), UiTheme.MOSS.lightened(0.3), 22)
		CombatCodec.Ev.SAVE:
			var p5 := _head(dst)
			if p5 != Vector2.INF:
				numbers.spawn(dst, p5, "saved" if bool(ev.get("saved", false)) else "failed save",
					UiTheme.SKY.lightened(0.3) if bool(ev.get("saved", false)) else UiTheme.PLUM.lightened(0.3), 17)
		CombatCodec.Ev.SWING:
			_swing(ev)
		CombatCodec.Ev.CANCEL, CombatCodec.Ev.DEATH:
			var who := src if int(ev["kind"]) == CombatCodec.Ev.CANCEL else dst
			telegraphs.cancel_from(who)
			swings.cancel(who)
			windups.erase(who)
		CombatCodec.Ev.PROJECTILE:
			_projectile(ev)
		CombatCodec.Ev.IMPACT:
			var pr: Dictionary = projectiles.get(int(ev.get("pid", -1)), {})
			if not pr.is_empty():
				(pr["node"] as Node3D).queue_free()
				projectiles.erase(int(ev["pid"]))

func _swing(ev: Dictionary) -> void:
	var src := int(ev["src"])
	var b := actor_box(src)
	if b.is_empty():
		return
	var mine := src == cw.my_id
	var r: ClientWorld.RemoteEntity = cw.remotes.get(src)
	var player := mine or (r != null and r.kind == HostEntity.Kind.PLAYER)
	var mode := int(ev.get("mode", 0))
	var windup := float(ev.get("windup", 0.0))
	if mode == CombatCodec.Mode.MELEE:
		_slashes(ev, b[1], player, mine)
	if not player and windup > 0.0:
		windups[src] = [SwingPlan.HEAD_START, windup]
	if player and mode != CombatCodec.Mode.AREA and not (mine and mode == CombatCodec.Mode.MELEE):
		return     # allies' swings are not telegraphed; their areas are, and the own arc
	if windup <= 0.0 and mode != CombatCodec.Mode.AREA:
		return
	var area := spell_area(String(ev.get("what", ""))) if mode in [CombatCodec.Mode.AREA, CombatCodec.Mode.CAST] else {}
	var d := Telegraphs.for_swing(ev, b[0], b[1], area)
	var col := Telegraphs.SWING_COLOR if mine else (Telegraphs.ALLY_COLOR if player else Telegraphs.MONSTER_COLOR)
	telegraphs.show_shape(d, windup - SwingPlan.HEAD_START if windup > 0.0 else 0.35, col, src, mine and mode == CombatCodec.Mode.MELEE)

## A melee swing's sweeps, one for each contact, each the other way across the arc.
func _slashes(ev: Dictionary, box: Vector2, player: bool, mine: bool) -> void:
	var src := int(ev["src"])
	var f := SwingFx.feel()
	var c := actor_center(src)
	var dir := HitShapes.aim_dir(c, ev.get("aim", c), 1)
	var reach := K.ft(float(ev.get("reach_ft", 5.0)))
	var tempo := String(ev.get("tempo", "plain"))
	var width := float(f.get("slash_width", {}).get(tempo, 0.5))
	var tint := SwingFx.color("slash") if player else SwingFx.color("slash_foe")
	if player and not mine:
		tint.a = 0.6
	for i in maxi(1, int(ev.get("swings", 1))):
		var at := float(ev.get("windup", 0.0)) + float(ev.get("gap", 0.0)) * i
		swings.slash(src, maxf(0.0, at - SwingPlan.HEAD_START - float(f.get("slash_lead_s", 0.06))), dir, reach, Telegraphs.arc_half(), box * 0.5, -1.0 if i % 2 == 1 else 1.0, width, tint)

## A spell's area for telegraphs and aiming: {shape, size_ft, range_ft} ({} if none).
func spell_area(slug: String) -> Dictionary:
	if slug == "":
		return {}
	if _areas.has(slug):
		return _areas[slug]
	var out := {}
	if srd == null:
		srd = WorldHost.shared_srd()
	if srd.pack.has_row("spell", slug):
		var ab := srd.make_spell(slug)
		out = {"shape": int(ab.area_shape), "size_ft": float(ab.area_size), "range_ft": float(ab.range_feet), "area": ab.area_size > 0}
	_areas[slug] = out
	return out

func aim_preview(spell: Dictionary, aim: Vector2) -> void:
	if spell.is_empty():
		telegraphs.set_preview({})
		return
	var me := cw.view_pos() + Vector2(0, cw.body.size.y * 0.5)
	var area := spell_area(String(spell["slug"]))
	if not area.is_empty() and bool(area.get("area", false)):
		telegraphs.set_preview(Telegraphs.area_shape(area, me, aim))
	else:
		var rng := K.ft(maxf(float(area.get("range_ft", 30)), 5.0))
		var dir := aim - me
		telegraphs.set_preview(Telegraphs.describe(Telegraphs.Shape.LINE, me, dir, minf(dir.length(), rng), 0.35))

func _projectile(ev: Dictionary) -> void:
	var pk := int(ev.get("pkind", 0))
	var mat: StandardMaterial3D = _proj_mats.get(pk)
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = [Color("8a5a2b"), Color("6d6a66"), Color("b9bec6"), Color("ffb347"), Color("c69bff")][clampi(pk, 0, 4)]
		_proj_mats[pk] = mat
	var mi := MeshInstance3D.new()
	mi.mesh = _proj_mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	projectiles[int(ev.get("pid", 0))] = {"pos": ev.get("pos", Vector2.ZERO), "vel": ev.get("vel", Vector2.ZERO),
		"g": float(ev.get("gravity", 0.0)), "node": mi, "t": 0.0}

## A spark fired on the own body: dash started, an air jump, a glide.
func _spark_fired() -> bool:
	var b := cw.body
	var fired := false
	if b.dash_left > 0.0 and float(_was.get("dash", 0.0)) <= 0.0:
		fired = true
	if b.air_jumps_left < int(_was.get("air", b.air_jumps_left)) and not b.on_floor:
		fired = true
	_was["dash"] = b.dash_left
	_was["air"] = b.air_jumps_left
	return fired

func flash_sigil() -> void:
	_sigil_t = 0.0

func _process(delta: float) -> void:
	if cw == null:
		return
	var t0 := Time.get_ticks_usec()
	var cam := get_viewport().get_camera_3d()
	numbers.step(delta, cam)
	telegraphs.step(delta)
	drops.step(delta)
	swings.step(delta, self)
	_highlight(delta)
	plates.step(cam, _hovered(), int(target.get("id", 0)))
	var own := actor_center(cw.my_id)
	if own != Vector2.INF:
		telegraphs.move_from(cw.my_id, own)
	for pid: int in projectiles.keys():
		var p: Dictionary = projectiles[pid]
		p["t"] = float(p["t"]) + delta
		var v: Vector2 = p["vel"]
		v.y -= float(p["g"]) * delta
		p["vel"] = v
		var pos: Vector2 = p["pos"] + v * delta
		p["pos"] = pos
		var node: MeshInstance3D = p["node"]
		node.position = Vector3(pos.x * K.TILE_M, pos.y * K.TILE_M, 0.1)
		node.rotation.z = atan2(v.y, v.x)
		if float(p["t"]) > PROJ_LIFE or TileDefs.solid[cw.world.get_fg(floori(pos.x), floori(pos.y))] != 0:
			node.queue_free()
			projectiles.erase(pid)
	if _spark_fired():
		flash_sigil()
	if _sigil_t >= 0.0:
		_sigil_t += delta
		var k := _sigil_t / 1.1
		var vp := cw.view_pos()
		_sigil.position = Vector3(vp.x * K.TILE_M, (vp.y + cw.body.size.y + 1.4 + k * 0.5) * K.TILE_M, 0.4)
		_sigil.modulate.a = clampf(minf(_sigil_t / 0.1, (1.1 - _sigil_t) / 0.4), 0.0, 1.0)
		_sigil.visible = true
		if _sigil_t > 1.1:
			_sigil_t = -1.0
			_sigil.visible = false
	frame_usec.append(Time.get_ticks_usec() - t0)
	if frame_usec.size() > 4000:
		frame_usec = frame_usec.slice(2000)

## Where the player is aiming, tiles (as LocalInput aims: the middle of the tile under the mouse).
func aim_point() -> Vector2:
	if aim_override != Vector2.INF:
		return aim_override
	return Vector2(view.tile_at_screen(get_viewport().get_mouse_position())) + Vector2(0.5, 0.5)

## Outlines: a monster's wind-up burns through to its blow; what the next swing would land on is
## gold in reach, pale under the aim beyond it. And, while a foe is near, the next swing's arc.
func _highlight(delta: float) -> void:
	var cc := cw.system(HostSystem.COMBAT) as CombatClient
	var aim := aim_point()
	target = cc.target_at(aim) if cc != null else {}
	if unseen.has(int(target.get("id", 0))):
		target = {}
	var want := {}
	if not target.is_empty():
		want[int(target["id"])] = SwingFx.color("target" if bool(target["reach"]) else "near")
	var from := float(SwingFx.feel().get("windup_rim_from", 0.0))
	var burn := SwingFx.color("windup")
	for id: int in windups.keys():
		var w: Array = windups[id]
		w[0] = float(w[0]) + delta
		var k := float(w[0]) / maxf(float(w[1]), 0.01)
		if k > 1.0:
			windups.erase(id)
			continue
		burn.a = clampf((k - from) / maxf(1.0 - from, 0.01), float(SwingFx.feel().get("windup_rim_min", 0.35)), 1.0)
		want[id] = burn
	for id: int in _rimmed.keys():
		if not want.has(id):
			var a := view.get_actor(id)
			if a != null:
				a.set_rim(Color(0, 0, 0, 0))
			_rimmed.erase(id)
	for id: int in want:
		var a := view.get_actor(id)
		if a != null:
			a.set_rim(want[id])
			_rimmed[id] = true
	_reach_arc(cc, aim)

func _reach_arc(cc: CombatClient, aim: Vector2) -> void:
	var f := SwingFx.feel()
	var col := Telegraphs.AIM_COLOR
	col.a = float(f.get("aim_arc_alpha", 0.3))
	var near := float(f.get("aim_arc_tiles", 6.0))
	var show := cc != null and col.a > 0.0 and float(cc.status.get("range_ft", 0)) <= 0.0 and cw.body != null and cw.body.roll_t < 0.0
	if show:
		show = false
		for r: ClientWorld.RemoteEntity in cw.remotes.values():
			if r.kind != HostEntity.Kind.PLAYER and r.max_hp > 0 and r.hp > 0 and r.pos.distance_to(cw.view_pos()) <= near \
					and (cc.in_fight(r.id) or int(target.get("id", 0)) == r.id):
				show = true
				break
	if not show:
		telegraphs.set_reach_arc({}, col)
		return
	var box := cw.body.size
	var c := actor_center(cw.my_id)
	telegraphs.set_reach_arc(Telegraphs.describe(Telegraphs.Shape.ARC, c, aim - c,
		box.x * 0.5 + K.ft(float(cc.status.get("reach_ft", 5))), 2.0, Telegraphs.arc_half(), box * 0.5), col)

## The monster under the mouse (0: none).
func _hovered() -> int:
	var p := aim_point()
	for r: ClientWorld.RemoteEntity in cw.remotes.values():
		if Rect2(r.pos - Vector2(r.size.x * 0.5, 0), r.size).grow(0.5).has_point(p):
			return r.id
	return 0
