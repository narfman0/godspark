## The client half of Life: the player's standing with each faction (names from the sim) and
## who the people around are (role, faction, whether they talk), for the Interface and Deals
## tracks.
##
##   var lc := cw.system(HostSystem.LIFE) as LifeClient
##   lc.standing_changed.connect(func(faction, value, why): ...)
##   lc.factions -> {faction id: {id, name, culture, alive, standing}}
##   lc.standing(faction) -> int;  lc.person(entity id) -> {id, role, kind, of, faction, talk, name}
##   lc.people_at(site id) -> Array of person dicts (kind "settlement")
class_name LifeClient
extends ClientSystem

signal standing_changed(faction: String, value: int, why: String)
signal factions_changed()
signal person_added(id: int, info: Dictionary)
signal person_gone(id: int)

var cw: ClientWorld
var factions := {}
var people := {}

func sys_id() -> int:
	return HostSystem.LIFE

func attach(c: ClientWorld) -> void:
	cw = c

func handle(kind: int, data: PackedByteArray) -> void:
	var d := LifeCodec.read(data)
	match kind:
		LifeCodec.Msg.FACTIONS:
			factions = {}
			for f: Dictionary in d.get("factions", []):
				f["standing"] = int(f.get("standing", 0))
				factions[String(f["id"])] = f
			factions_changed.emit()
		LifeCodec.Msg.STANDING:
			var fid := String(d.get("faction", ""))
			var v := int(d.get("value", 0))
			if not factions.has(fid):
				factions[fid] = {"id": fid, "name": "", "culture": "", "alive": true}
			factions[fid]["standing"] = v
			standing_changed.emit(fid, v, String(d.get("why", "")))
		LifeCodec.Msg.PEOPLE:
			for p: Dictionary in d.get("people", []):
				p["id"] = int(p["id"])
				p["of"] = int(p.get("of", -1))
				people[p["id"]] = p
				person_added.emit(p["id"], p)
				_relook(p["id"])
		LifeCodec.Msg.GONE:
			for id: Variant in d.get("ids", []):
				people.erase(int(id))
				person_gone.emit(int(id))

func standing(faction: String) -> int:
	return int(factions.get(faction, {}).get("standing", 0))

## ClientWorld.add_remote asks before actor_added: guards carry a torch (the view lights it
## at night), a wagon draws a cart.
func decorate_look(id: int, look: Dictionary) -> void:
	var p: Dictionary = people.get(id, {})
	if bool(p.get("torch", false)):
		look["light"] = "torch"
	if bool(p.get("wagon", false)):
		look["wagon"] = true

## PEOPLE after the actor was added: add what it lacks and let the view rebuild it.
func _relook(id: int) -> void:
	if cw == null:
		return
	var r: Variant = cw.remotes.get(id)
	if r == null:
		return
	var look: Dictionary = r.look.duplicate()
	decorate_look(id, look)
	if look != r.look:
		r.look = look
		cw.actor_added.emit(id, look)

## One of Life's people (not a monster to hunt).
func is_person(id: int) -> bool:
	return people.has(id)

func person(id: int) -> Dictionary:
	return people.get(id, {})

func people_at(site_id: int) -> Array:
	var out: Array = []
	for id: int in people:
		var p: Dictionary = people[id]
		if p.get("kind", "") == "settlement" and int(p["of"]) == site_id:
			out.append(p)
	return out
