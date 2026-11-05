## The items system's client half: a mirror of the own inventory, equipment (with bonds),
## coin, hotbar selection and constellation, the drops in view, and requests to the host.
## The surface the Interface track builds on (docs/tracks/items.md). Every request is
## checked again on the host; answers come back as the mirror changing and a `note`.
##
## Indices: 0-9 hotbar, 10-49 bag, 50-68 equipment (Equipment.SLOTS order: head, neck,
## cloak, armor, hands, belt, feet, main_hand, off_hand, ring_1..ring_10).
##
##   var items: ItemsClient = cw.system(HostSystem.ITEMS)
##   items.inventory_changed.connect(func(idx): ...)
##   items.equip(12, "ring_3"); items.select_hotbar(2); items.kindle(15)
class_name ItemsClient
extends ClientSystem

## Slots changed (unified indices); coin and selection are re-read too.
signal inventory_changed(indices: Array)
## Equipment slot names changed.
signal equipment_changed(slots: Array)
## Kindled sparks, slots or move stats changed.
signal constellation_changed()
## A drop came into view or changed (count, after a merge or partial pickup).
signal drop_added(id: int, pos: Vector2, item: Dictionary)
## A drop went: by = the entity that picked it up, 0 = despawned or out of view.
signal drop_removed(id: int, by: int)
## The host's answer to a request: op = ItemsCodec.K kind, ok, word ("ok" or a reason).
signal note(op: int, ok: bool, word: String)
## Bonding progress: the index being bonded, ms left (0 = finished or stopped).
signal bonding(index: int, ms_left: int)

## Seconds a predicted place keeps its item reserved without an answer.
const PENDING_TIMEOUT := 4.0

var cw: ClientWorld
## True once the host's items system has spoken (until then places are not gated).
var live := false
var inventory := Inventory.new()
var equipment := Equipment.new()
var constellation := Constellation.new()
## Base speeds (ft) and size the host mirrors; with the kindled sparks they give cw.stats.
var speeds := {"walk": 30}
var size_name := "medium"
var drops := Drops.new()
## req -> {tile, t}: places predicted and not yet answered (their items are spoken for).
var _pending := {}
var _time := 0.0

func sys_id() -> int:
	return HostSystem.ITEMS

func attach(c: ClientWorld) -> void:
	cw = c
	Items.ensure()
	Sparks.data()
	if not cw.edit_result.is_connected(_on_result):
		cw.edit_result.connect(_on_result)

func handle(kind: int, data: PackedByteArray) -> void:
	match kind:
		ItemsCodec.K.SLOTS:
			var m := ItemsCodec.read_slots(data)
			if m.is_empty():
				return
			live = true
			inventory.coin = int(m["coin"])
			inventory.selected = int(m["selected"])
			var idx: Array = []
			var eqs: Array = []
			for en: Array in m["entries"]:
				var i := int(en[0])
				var rec: Dictionary = en[1]
				if i < Inventory.SIZE:
					inventory.slots[i] = rec
				else:
					var s := Equipment.slot_at(i)
					if s == "":
						continue
					if rec.is_empty():
						equipment.worn.erase(s)
					else:
						equipment.worn[s] = rec
					eqs.append(s)
				idx.append(i)
			inventory.changed.clear()
			equipment.changed.clear()
			_update_place_tile()
			inventory_changed.emit(idx)
			if not eqs.is_empty():
				equipment_changed.emit(eqs)
		ItemsCodec.K.STARS:
			var m := ItemsCodec.read_stars(data)
			if m.is_empty():
				return
			live = true
			speeds = m["speeds"]
			size_name = String(m["size"])
			constellation = Constellation.from_dict({"kindled": m["kindled"]})
			constellation.slots = int(m["slots"])
			if cw != null:
				cw.stats = move_stats()
			constellation_changed.emit()
		ItemsCodec.K.DROPS:
			for d: Dictionary in ItemsCodec.read_drops(data):
				var dr: Drops.Drop = drops.list.get(int(d["id"]))
				if dr == null:
					dr = Drops.Drop.new()
					dr.id = int(d["id"])
					drops.list[dr.id] = dr
				dr.pos = d["pos"]
				dr.vel = d["vel"]
				dr.item = d["item"]
				dr.rest = false
				drop_added.emit(dr.id, dr.pos, dr.item)
		ItemsCodec.K.GONE:
			for g: Array in ItemsCodec.read_gone(data):
				if drops.list.erase(int(g[0])):
					drop_removed.emit(int(g[0]), int(g[1]))
		ItemsCodec.K.MOVED:
			for d: Dictionary in ItemsCodec.read_moved(data):
				var dr: Drops.Drop = drops.list.get(int(d["id"]))
				if dr != null:
					dr.pos = d["pos"]
					dr.vel = d["vel"]
					dr.rest = false
		ItemsCodec.K.NOTE:
			var n := ItemsCodec.read_note(data)
			if not n.is_empty():
				note.emit(int(n["op"]), bool(n["ok"]), String(n["word"]))
		ItemsCodec.K.BONDING:
			var b := ItemsCodec.read_bonding(data)
			if not b.is_empty():
				bonding.emit(int(b["index"]), int(b["ms"]))

func frame(dt: float) -> void:
	_time += dt
	if cw != null and cw.world != null and not drops.list.is_empty():
		drops.step(cw.world, dt)
	if not _pending.is_empty():
		for req: int in _pending.keys():
			if _time - float(_pending[req]["t"]) > PENDING_TIMEOUT:
				_pending.erase(req)

# --- the edit flow ------------------------------------------------------------------------

## Only places the mirror says we hold an item for (less those already predicted).
func allow_place(tile_id: int) -> bool:
	if not live:
		return true
	return held_tiles(tile_id) > 0

func placed(req: int, tile_id: int) -> void:
	if live:
		_pending[req] = {"tile": tile_id, "t": _time}

func _on_result(req: int, _reason: int, _at: Vector2i, _tile: int) -> void:
	_pending.erase(req)

## How many of a tile we can still place: held in the mirror minus predicted places.
func held_tiles(tile_id: int) -> int:
	var n := 0
	for s: Dictionary in inventory.slots:
		if not s.is_empty() and Items.tile_of(s) == tile_id:
			n += Items.count(s)
	for p: Dictionary in _pending.values():
		if int(p["tile"]) == tile_id:
			n -= 1
	return n

func _update_place_tile() -> void:
	if cw != null:
		cw.place_tile = inventory.selected_tile()

# --- reading the mirror -------------------------------------------------------------------

## The record at a unified index ({} if empty).
func item(index: int) -> Dictionary:
	return inventory.at(index) if index < Inventory.SIZE else equipment.at(Equipment.slot_at(index))

func coin() -> int:
	return inventory.coin

func selected() -> int:
	return inventory.selected

## The 10 hotbar records.
func hotbar() -> Array:
	return inventory.slots.slice(0, Inventory.HOTBAR)

## Tile id of the selected hotbar item (0 if not a placeable tile).
func selected_tile() -> int:
	return inventory.selected_tile()

## Display name of a record (ItemGen.name).
func name_of(it: Dictionary) -> String:
	return ItemGen.name(it)

## Tags of what is worn and kindled (the host computes the same for its rules).
func tags() -> Dictionary:
	return Items.merge_tags([equipment.tags(), Sparks.tags(constellation.list())])

## The MoveStats the own player moves with (also set on cw.stats when STARS arrives).
func move_stats() -> MoveStats:
	return Sparks.move_stats(speeds, size_name, constellation.list())

## The constellation drawing: {stars: [Vector2i], lines: [[a, b]]}.
func sigil() -> Dictionary:
	return constellation.sigil()

## Drops this client knows: [{id, pos, item}].
func drops_in_view() -> Array:
	var out: Array = []
	for d: Drops.Drop in drops.list.values():
		out.append({"id": d.id, "pos": d.pos, "item": d.item})
	return out

# --- requests (all checked on the host) -------------------------------------------------------

func move(slot_a: int, slot_b: int) -> void:
	_send(ItemsCodec.K.MOVE, ItemsCodec.bytes([slot_a, slot_b]))

## Put the item at `slot` on: equip_slot is an Equipment slot name or a unified index.
func equip(slot: int, equip_slot: Variant) -> void:
	var to: int = Equipment.index_of(equip_slot) if equip_slot is String else int(equip_slot)
	if to >= 0:
		move(slot, to)

## Take an equipment slot off into a bag slot (to = ItemsCodec.ANY: the first free one).
func unequip(equip_slot: Variant, to := ItemsCodec.ANY) -> void:
	var from: int = Equipment.index_of(equip_slot) if equip_slot is String else int(equip_slot)
	if from >= 0:
		move(from, to)

## Use a slot: drink a potion, or put wearable gear on.
func use(slot: int) -> void:
	_send(ItemsCodec.K.USE, ItemsCodec.bytes([slot]))

func drop(slot: int, n := 1) -> void:
	_send(ItemsCodec.K.DROP, ItemsCodec.drop_req(slot, n))

## Select a hotbar slot (0-9); shown at once, confirmed by the host.
func select_hotbar(i: int) -> void:
	if i < 0 or i >= Inventory.HOTBAR:
		return
	inventory.selected = i
	_update_place_tile()
	_send(ItemsCodec.K.SELECT, ItemsCodec.bytes([i]))
	inventory_changed.emit([])

## Bond the item at an index (inventory or equipment); needs a campfire near.
func bond(slot: int) -> void:
	_send(ItemsCodec.K.BOND, ItemsCodec.bytes([slot]))

## Kindle the spark at an inventory slot into a free star; needs a shrine near.
func kindle(slot: int) -> void:
	_send(ItemsCodec.K.KINDLE, ItemsCodec.bytes([slot]))

## Replace star i with the spark at an inventory slot; the old one comes back.
func swap_spark(i: int, slot: int) -> void:
	_send(ItemsCodec.K.SWAP, ItemsCodec.bytes([i, slot]))

## Hand-craft a recipe from data/items/recipes.json.
func craft(recipe: String, times := 1) -> void:
	_send(ItemsCodec.K.CRAFT, ItemsCodec.craft(recipe, times))

func _send(kind: int, data: PackedByteArray) -> void:
	if cw != null:
		cw.send_sys(sys_id(), kind, data)
