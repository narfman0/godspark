## Who can see whom on the host, for the SRD's unseen attacker / unseen target rules.
##
## Light: a host-side LightEngine over the host world (sun from the world clock, emissive
## tiles), built lazily on the first question and computed per chunk on demand (a cold chunk
## costs about a millisecond once; edits update incrementally). Carried lights are not in
## it: every player is assumed to carry a torch (data/combat.json "light"), applied
## analytically (bright within 8 tiles, dim to 16, with line of sight).
## Seeing: line of sight from eye to any of the target's sample points, and the target's
## cell is not Darkness for the viewer (Darkvision, from the stat block or species, turns
## Darkness within range into Dim; Blindsight and Truesight see regardless within range).
class_name CombatSight
extends RefCounted

var host: WorldHost:
	get:
		return _host.get_ref()
var _host: WeakRef
var light: LightEngine
## Microseconds spent building and computing light (first queries), for the track notes.
var light_usec := 0

func _init(h: WorldHost) -> void:
	_host = weakref(h)

## SRD light category (LightEngine.Category) at a point, with player torches.
func category_at(p: Vector2) -> int:
	var x := floori(p.x)
	var y := floori(p.y)
	if not host.world.in_bounds(x, y):
		return LightEngine.Category.BRIGHT
	var cat := _torch_category(p)
	if cat == LightEngine.Category.BRIGHT:
		return cat          # a player's torch settles it without the light engine
	if light == null:
		var t0 := Time.get_ticks_usec()
		light = LightEngine.new(host.world)
		light_usec += Time.get_ticks_usec() - t0
	light.sun = WorldClock.sun_at(host.clock.hours())
	var t1 := Time.get_ticks_usec()
	cat = maxi(cat, light.category_at(x, y))
	light_usec += Time.get_ticks_usec() - t1
	return cat

## Light from the torches players carry (analytic, with line of sight).
func _torch_category(p: Vector2) -> int:
	var cat: int = LightEngine.Category.DARK
	var lt := CombatTempo.section("light")
	var bright := float(lt.get("player_torch_bright", 8.0))
	var dim := float(lt.get("player_torch_dim", 16.0))
	for e: HostEntity in host.entities.values():
		if not e.is_player():
			continue
		var torch := e.body.pos + Vector2(0, 1.8)
		var d := torch.distance_to(p)
		if d > dim or TileCollision.raycast(host.world, torch, p)["hit"]:
			continue
		if d <= bright:
			return LightEngine.Category.BRIGHT
		cat = LightEngine.Category.DIM
	return cat

## Tiles of Darkvision (0 = none): the stat block's senses for monsters, the species table
## for players. Blindsight / Truesight are returned by senses_tiles.
func darkvision_tiles(e: HostEntity) -> float:
	return senses_tiles(e).get("darkvision", 0.0)

## {darkvision, blindsight, truesight, tremorsense} in tiles.
func senses_tiles(e: HostEntity) -> Dictionary:
	var out := {"darkvision": 0.0, "blindsight": 0.0, "truesight": 0.0, "tremorsense": 0.0}
	if e.is_player():
		if e.character != null:
			var dv: Dictionary = CombatTempo.section("darkvision_species")
			out["darkvision"] = K.ft(float(dv.get(e.character.species, 0)))
		return out
	var slug := String(e.look.get("slug", ""))
	if slug != "":
		var senses: Variant = host.srd.pack.get_row("monster", slug).get("data", {}).get("senses", {})
		if senses is Dictionary:
			for k: String in out:
				out[k] = K.ft(float(senses.get(k, 0)))
	return out

## Eye point of a body (upper middle of its box).
static func eye(e: HostEntity) -> Vector2:
	return e.body.pos + Vector2(0, e.body.size.y * 0.8)

## Can `viewer` see `target` (line of sight, light, Darkvision, Invisible)?
func can_see(viewer: HostEntity, target: HostEntity) -> bool:
	var from := eye(viewer)
	var r := target.body.rect()
	if not HitShapes.line_to(host.world, from, r):
		return false
	var dist := HitShapes.gap(viewer.body.rect(), r)
	var s := senses_tiles(viewer)
	if dist <= maxf(s["blindsight"], s["truesight"]):
		return true
	if viewer.combatant != null and viewer.combatant.conditions.has(SRD.Condition.BLINDED):
		return false
	if target.combatant != null and target.combatant.conditions.has(SRD.Condition.INVISIBLE):
		return false
	if category_at(r.get_center()) != LightEngine.Category.DARK:
		return true
	return dist <= s["darkvision"]
