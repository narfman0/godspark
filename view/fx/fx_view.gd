## In-world feedback (view/fx/), a child of WorldView: floating numbers, nameplates, wind-up
## telegraphs and the spell aiming preview, drops on the ground, projectiles, hit flashes on
## actors, and the sigil flash over the own character when a spark fires (a dash, an air
## jump, a glide). Reads the client world and its systems; owns no game state.
##
## Projectiles: the combat client's PROJECTILE events carry pos, vel and gravity; they are
## stepped here until their IMPACT (or a wall, or 4 s).
class_name FxView
extends Node3D

const FLASH_S := 0.12
const PROJ_LIFE := 4.0

var cw: ClientWorld
var view: WorldView
var overlay: CanvasLayer
var numbers: FloatingNumbers
var plates: Nameplates
var telegraphs: Telegraphs
var drops: DropsView
var srd: SRDContent
## pid -> {pos, vel, g, node, t}
var projectiles := {}
## actor id -> {until (msec), geos: [[GeometryInstance3D, original tint]]}
var _flash := {}
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
	_flash.erase(id)

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

func combat_event(ev: Dictionary) -> void:
	var src := int(ev["src"])
	var dst := int(ev["dst"])
	var mine := dst == cw.my_id
	if src != 0:
		plates.touch(src)
	if dst != 0:
		plates.touch(dst)
	match int(ev["kind"]):
		CombatCodec.Ev.DAMAGE:
			var p := _head(dst)
			if p != Vector2.INF:
				numbers.spawn(dst, p, str(int(ev.get("amount", 0))), UiTheme.VERMILION.lightened(0.15) if mine else UiTheme.TEXT_LIGHT, 22)
			_start_flash(dst)
		CombatCodec.Ev.CRIT:
			var p2 := _head(dst)
			if p2 != Vector2.INF:
				numbers.spawn(dst, p2 + Vector2(0, 0.4), "Crit!", UiTheme.GOLD, 26)
		CombatCodec.Ev.MISS:
			var p3 := _head(dst)
			if p3 != Vector2.INF:
				numbers.spawn(dst, p3, "miss", Color(0.8, 0.78, 0.72), 18)
		CombatCodec.Ev.HEAL:
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
			telegraphs.cancel_from(src if int(ev["kind"]) == CombatCodec.Ev.CANCEL else dst)
		CombatCodec.Ev.PROJECTILE:
			_projectile(ev)
		CombatCodec.Ev.IMPACT:
			var pr: Dictionary = projectiles.get(int(ev.get("pid", -1)), {})
			if not pr.is_empty():
				(pr["node"] as Node3D).queue_free()
				projectiles.erase(int(ev["pid"]))

func _swing(ev: Dictionary) -> void:
	var src := int(ev["src"])
	if src == cw.my_id:
		return
	var b := actor_box(src)
	if b.is_empty():
		return
	var r: ClientWorld.RemoteEntity = cw.remotes.get(src)
	var player := r != null and r.kind == HostEntity.Kind.PLAYER
	var mode := int(ev.get("mode", 0))
	if player and mode != CombatCodec.Mode.AREA:
		return     # allies' swings are not telegraphed; their areas are
	var windup := float(ev.get("windup", 0.0))
	if windup <= 0.0 and mode != CombatCodec.Mode.AREA:
		return
	var area := spell_area(String(ev.get("what", ""))) if mode in [CombatCodec.Mode.AREA, CombatCodec.Mode.CAST] else {}
	var d := Telegraphs.for_swing(ev, b[0], b[1], area)
	telegraphs.show_shape(d, maxf(windup, 0.35), Telegraphs.ALLY_COLOR if player else Telegraphs.MONSTER_COLOR, src)

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

func _start_flash(id: int) -> void:
	var a := view.get_actor(id)
	if a == null:
		return
	var f: Dictionary = _flash.get(id, {})
	if f.is_empty():
		var geos: Array = []
		for g: GeometryInstance3D in a.find_children("*", "GeometryInstance3D", true, false):
			if g is Label3D:
				continue
			geos.append([g, g.get_instance_shader_parameter("tint")])
		f = {"geos": geos}
		for pair: Array in geos:
			var base: Variant = pair[1]
			var c: Color = base if base is Color else Color.WHITE
			(pair[0] as GeometryInstance3D).set_instance_shader_parameter("tint", Color(c.r * 2.2 + 0.4, c.g * 1.6 + 0.3, c.b * 1.5 + 0.3, 1))
	f["until"] = Time.get_ticks_msec() + int(FLASH_S * 1000)
	_flash[id] = f

func _end_flashes() -> void:
	var now := Time.get_ticks_msec()
	for id: int in _flash.keys():
		var f: Dictionary = _flash[id]
		if now < int(f.get("until", 0)):
			continue
		for pair: Array in f["geos"]:
			var g: GeometryInstance3D = pair[0]
			if is_instance_valid(g):
				if pair[1] == null:
					g.set_instance_shader_parameter("tint", Color.WHITE)
				else:
					g.set_instance_shader_parameter("tint", pair[1])
		_flash.erase(id)

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
	plates.step(cam, _hovered())
	if not _flash.is_empty():
		_end_flashes()
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

## The monster under the mouse (0: none).
func _hovered() -> int:
	var t := view.tile_at_screen(get_viewport().get_mouse_position())
	var p := Vector2(t) + Vector2(0.5, 0.5)
	for r: ClientWorld.RemoteEntity in cw.remotes.values():
		if Rect2(r.pos - Vector2(r.size.x * 0.5, 0), r.size).grow(0.5).has_point(p):
			return r.id
	return 0
