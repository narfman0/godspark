## The client half of the monsters system: each monster's rank, affixes and body, for the
## interface and the view. Entities and hit points already replicate (ENT_ADD, VITALS); this
## adds what they lack. When INFO arrives for an actor the client has, the actor is re-added
## with the full look (slug or people, rank, scale) through ClientWorld.actor_added, so the
## existing view builds the right body (forge model, Synty people, or a primitive).
##
##   var mc := cw.system(HostSystem.MONSTERS) as MonstersClient
##   mc.monster_info.connect(func(id, info): ...)  # {rank, slug, people, scale, flags, affixes, names}
##   mc.info_of(id) -> Dictionary
class_name MonstersClient
extends ClientSystem

signal monster_info(id: int, info: Dictionary)
signal monster_gone(id: int)

var cw: ClientWorld
var infos := {}
var _relooking := false

func sys_id() -> int:
	return HostSystem.MONSTERS

func attach(c: ClientWorld) -> void:
	cw = c
	cw.actor_added.connect(_on_actor)

func handle(kind: int, data: PackedByteArray) -> void:
	match kind:
		MonstersCodec.Msg.INFO:
			for d: Dictionary in MonstersCodec.read_info(data):
				var names: Array = []
				for a: String in d["affixes"]:
					names.append(String(Ecology.affixes().get(a, {}).get("name", a)))
				d["names"] = names
				infos[int(d["id"])] = d
				monster_info.emit(int(d["id"]), d)
				if cw.remotes.has(int(d["id"])):
					_relook(int(d["id"]))
		MonstersCodec.Msg.GONE:
			for id: int in MonstersCodec.read_gone(data):
				infos.erase(id)
				monster_gone.emit(id)

func info_of(id: int) -> Dictionary:
	return infos.get(id, {})

## The look the view should build for a monster with INFO.
func look_of(id: int) -> Dictionary:
	var d: Dictionary = infos.get(id, {})
	var r: Variant = cw.remotes.get(id)
	var look := {"kind": "monster", "rank": d.get("rank", "standard"), "scale": d.get("scale", 1.0)}
	if r != null:
		look["name"] = r.name
		look["size"] = r.size
	if String(d.get("people", "")) != "":
		look["people"] = d["people"]
	if String(d.get("slug", "")) != "":
		look["slug"] = d["slug"]
	return look

func _on_actor(id: int, _look: Dictionary) -> void:
	if not _relooking and infos.has(id):
		_relook(id)

func _relook(id: int) -> void:
	_relooking = true
	cw.actor_added.emit(id, look_of(id))
	_relooking = false
