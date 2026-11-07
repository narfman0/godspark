## Keeps the places in the tiles in step with the sim (host thread, inside WorldHost.tick).
## Once a second it compares each settlement site's place with the sim: a new settlement on a
## laid-out site is a founding (the hamlet's lots are built in the founder's style), a tier
## change builds or ruins lots (PlaceBuilder.changes_for), a settlement that is gone
## (abandoned, sacked and emptied) turns every built lot into a ruin. A change is applied
## only while no player is within VIEW of the place; until then it waits, and it is applied
## as soon as the place is out of every player's view (a long sleep may apply many at once).
## Writes go through TileWorld.set_fg / set_bg, so clients get TILE events and saves follow;
## dressing in a changed lot is replaced and announced with OBJECTS. meta.places is updated.
##
##   host.places_keeper.update(host)     # WorldHost calls it every tick; it works once a second
##   host.places_keeper.applied          # changes applied so far: [{site, tier, lots}]
class_name PlaceKeeper
extends RefCounted

## Tiles beyond a place's rect a player can see (half a screen and then some).
const VIEW := Vector2i(70, 45)

var applied: Array = []
## Player entity id -> the site whose place it is in (-1 outside), for arrival notices.
var where := {}
## Arrival notices sent: [{id, site, text}] (the last 20).
var arrivals: Array = []
var waiting := {}        ## site id -> true while a change waits for players to leave
var _tick := 0

func update(host: WorldHost) -> void:
	_tick += 1
	if host.sim == null or _tick % K.TICK_HZ != 0:
		return
	var all := Places.all(host.world)
	if all.is_empty():
		return
	_arrivals(host)
	for key: String in all:
		var place: Dictionary = all[key]
		var sid := int(key)
		var s: SimSettlement = host.sim.settlements.get(sid)
		var tier := s.tier if s != null else ""
		var founding := s != null and String(place.get("tier", "")) == "" and _all_empty_or_ruined(place)
		if tier == String(place.get("tier", "")) and PlaceBuilder.changes_for(place, tier).is_empty():
			waiting.erase(sid)
			continue
		if _seen(host, place):
			waiting[sid] = true
			continue
		waiting.erase(sid)
		apply(host, sid, tier, s.culture if founding else "")

## Bring site sid's place to a tier now (culture: restyle it first, for a founding).
func apply(host: WorldHost, sid: int, tier: String, culture := "") -> int:
	var place: Dictionary = Places.place(host.world, sid)
	if place.is_empty():
		return 0
	if culture != "" and culture != place.get("culture", ""):
		place["culture"] = culture
		var site: Dictionary = host.sim.site_by_id.get(sid, {}) if host.sim != null else {}
		place["style"] = PlaceStyles.style_for(culture, String(site.get("band", "surface")))
	place["tier"] = tier
	var changes := PlaceBuilder.changes_for(place, tier)
	for ch: Array in changes:
		var i: int = ch[0]
		_clear_objects(host, PlaceBuilder.lot_rect(place, i))
		var wr := PlaceBuilder.set_lot(place, i, ch[1], host.world.world_seed)
		_write(host, wr)
		_clear_objects(host, PlaceBuilder.lot_rect(place, i))   # the new template's envelope
		_add_objects(host, wr["objects"])
	PlaceBuilder.refresh_buildings(place)
	applied.append({"site": sid, "tier": tier, "lots": changes.size()})
	return changes.size()

## A player who walks into a settled place hears its name, people, size and souls (a
## Rules NOTE, shown as a toast: "Millburrow, a halfling town of 633 souls").
func _arrivals(host: WorldHost) -> void:
	for e: HostEntity in host.entities.values():
		if not e.is_player():
			continue
		var sid := Places.place_at(host.world, floori(e.body.pos.x), floori(e.body.pos.y))
		var was: int = where.get(e.id, -1)
		where[e.id] = sid
		if sid < 0 or sid == was:
			continue
		var text := arrival_text(host, sid)
		if text == "":
			continue
		host.send_sys(HostSystem.RULES, RulesCodec.K.NOTE, RulesCodec.encode_str(text), e.id)
		arrivals.append({"id": e.id, "site": sid, "text": text})
		# a people that wants a toll says so at the gate (its own note: the banner takes the first)
		var life := host.system(HostSystem.LIFE)
		if life != null and life.has_method("toll_due") and int(life.call("toll_due", e, sid)) > 0:
			var toll := "The gate guards want a toll of %d coin to go further" % int(life.call("toll_due", e, sid))
			host.send_sys(HostSystem.RULES, RulesCodec.K.NOTE, RulesCodec.encode_str(toll), e.id)
			arrivals.append({"id": e.id, "site": sid, "text": toll})
		if arrivals.size() > 20:
			arrivals.pop_front()

static func arrival_text(host: WorldHost, sid: int) -> String:
	var s: SimSettlement = host.sim.settlements.get(sid) if host.sim != null else null
	if s == null:
		return ""
	var people := s.culture.replace("_", " ")
	var article := "an" if people.substr(0, 1) in ["a", "e", "i", "o", "u"] else "a"
	return "%s, %s %s %s of %d souls" % [s.name, article, people, s.tier, s.pop()]

func _all_empty_or_ruined(place: Dictionary) -> bool:
	for lot: Dictionary in place["lots"]:
		if lot["state"] == "built":
			return false
	return true

func _seen(host: WorldHost, place: Dictionary) -> bool:
	var r: Array = place["rect"]
	var box := Rect2(int(r[0]) - VIEW.x, int(r[1]) - VIEW.y, int(r[2]) + 2 * VIEW.x, int(r[3]) + 2 * VIEW.y)
	for e: HostEntity in host.entities.values():
		if e.is_player() and box.has_point(e.body.pos):
			return true
	return false

func _write(host: WorldHost, wr: Dictionary) -> void:
	var cells: PackedInt32Array = wr["cells"]
	var w := host.world
	for i in range(0, cells.size(), 4):
		var x := cells[i]
		var y := cells[i + 1]
		if not w.in_bounds(x, y):
			continue
		if cells[i + 2] >= 0 and w.get_fg(x, y) != cells[i + 2]:
			w.set_fg(x, y, cells[i + 2])
		if cells[i + 3] >= 0 and w.get_bg(x, y) != cells[i + 3]:
			w.set_bg(x, y, cells[i + 3])

## Remove every dressing record anchored in rect (the lot's old skin).
func _clear_objects(host: WorldHost, rect: Rect2i) -> void:
	var w := host.world
	for cy in range(maxi(0, rect.position.y >> 5), mini(w.chunks_y - 1, (rect.end.y - 1) >> 5) + 1):
		for cx in range(maxi(0, rect.position.x >> 5), mini(w.chunks_x - 1, (rect.end.x - 1) >> 5) + 1):
			var c := w.chunk_at(cx, cy)
			if c == null:
				continue
			var hit := false
			for i in range(c.object_count() - 1, -1, -1):
				var o := c.object_at(i)
				if rect.has_point(Vector2i(cx * K.CHUNK + o.y, cy * K.CHUNK + o.z)):
					c.remove_object(i)
					hit = true
			if hit:
				_changed(host, cx, cy)

func _add_objects(host: WorldHost, objects: Array) -> void:
	var w := host.world
	for o: Array in objects:
		var x: int = o[1]
		var y: int = o[2]
		if not w.in_bounds(x, y) or not Dressing.holds(w, o[0], x, y):
			continue
		var c := w.chunk_at(x >> 5, y >> 5)
		c.add_object(o[0], x & 31, y & 31, o[3])
		_changed(host, x >> 5, y >> 5)

func _changed(host: WorldHost, cx: int, cy: int) -> void:
	host.world.chunk_at(cx, cy).modified = true
	host.world.objects_changed.emit(cx, cy)
	host.outbox.append({"type": WorldHost.Ev.OBJECTS, "cx": cx, "cy": cy})
