## The client half of the monsters system: each monster's rank, affixes and flags, for the
## interface. The body's look (slug or people, rank, scale) comes with ENT_ADD (protocol 7),
## so the view builds the right body when the actor is added. INFO only re-adds an actor
## whose look lacks what INFO says (an entity added by an older path), never one that has it:
## a re-add inside actor_added's own emission used to be overwritten by the outer, plainer
## look (remote monsters drew as capsules).
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

func sys_id() -> int:
	return HostSystem.MONSTERS

func attach(c: ClientWorld) -> void:
	cw = c

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
				if cw.remotes.has(int(d["id"])) and _stale(int(d["id"])):
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

## ClientWorld.add_remote asks before emitting actor_added: what INFO knows fills gaps.
func decorate_look(id: int, look: Dictionary) -> void:
	var d: Dictionary = infos.get(id, {})
	if d.is_empty():
		return
	if not look.has("slug") and not look.has("people"):
		if String(d.get("people", "")) != "":
			look["people"] = d["people"]
		if String(d.get("slug", "")) != "":
			look["slug"] = d["slug"]
	if not look.has("rank"):
		look["rank"] = d.get("rank", "standard")
	if not look.has("scale"):
		look["scale"] = d.get("scale", 1.0)

## True when the remote's current look lacks the body INFO describes.
func _stale(id: int) -> bool:
	var r: Variant = cw.remotes.get(id)
	if r == null:
		return false
	var have: Dictionary = r.look
	var want := look_of(id)
	for k: String in ["slug", "people", "rank"]:
		if want.has(k) and String(have.get(k, "")) != String(want[k]):
			return true
	return absf(float(have.get("scale", 1.0)) - float(want.get("scale", 1.0))) > 0.06

func _relook(id: int) -> void:
	var r: Variant = cw.remotes.get(id)
	if r == null:
		return
	var look: Dictionary = r.look.duplicate()
	look.merge(look_of(id), true)
	r.look = look
	cw.actor_added.emit(id, look)
