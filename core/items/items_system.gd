## The items system (HostSystem.ITEMS): inventory, equipment, bonding, sparks, the edit flow
## (digging gives the tile's item, placing takes it), loot on the ground and loot tables.
## Player state lives in the Character record (inventory, equipment, sparks) and is saved
## with it; drops are world state (save_world). Messages: ItemsCodec. Contract and surface:
## docs/tracks/items.md.
##
## Calls other systems make (guard with host.system(HostSystem.ITEMS) and has_method):
##   gear_mods(e) -> Array        wielded(e) -> Dictionary     outfit(e, c := null)
##   apply_sparks(e, stats, out)  tags(e) -> Dictionary
##   give(entity_id, item) -> Dictionary (leftover)            drop(pos, items, from := 0)
##   on_kill(victim)              refresh(e)
class_name ItemsSystem
extends HostSystem

## Seconds at a campfire to bond an item.
const BOND_TIME := 2.0
## Tiles from the body's box within which a campfire or shrine counts as near.
const STATION_RANGE := 3
## Base pickup radius (tiles, from the body's box); the Magnet spark and affixes add.
const PICKUP := 1.25
## Drop visibility and stats checks run every this many ticks.
const VIEW_EVERY := 10
const CHECK_EVERY := 30
const CAMPFIRE := 64
const SHRINE := 66

var host: WorldHost
var drops := Drops.new()
var rng := RandomNumberGenerator.new()
## entity id -> {drop id: true}: drops that player's client has been told of.
var _known := {}
## entity id -> {index, item, left}
var _bonding := {}
## entity id -> signature of the last STARS sent
var _sig := {}
## entity id -> the MoveStats object last given to e.stats
var _applied := {}
## entity id -> tags (gear + sparks), refreshed with the gear
var _tags := {}
## Queued drop messages per entity id: {add: [], gone: [], moved: []}
var _out := {}
## Entities inside rules.refresh (re-entry guard).
var _refreshing := {}

func sys_id() -> int:
	return HostSystem.ITEMS

func attach(h: WorldHost) -> void:
	host = h
	Items.ensure()
	Sparks.data()
	Loot.data()
	rng.seed = hash("loot:%d" % h.world.world_seed)

func save_world() -> Dictionary:
	return drops.to_dict()

func load_world(d: Dictionary) -> void:
	drops.load_dict(d)

## State lives in the Character record; nothing extra per player.
func save_player(_e: HostEntity) -> Dictionary:
	return {}

func load_player(e: HostEntity, _d: Dictionary) -> void:
	if e.character != null and not e.character.inventory.kit_given:
		give_kit(e.character)

func entity_added(_h: WorldHost, e: HostEntity) -> void:
	if not e.is_player() or e.character == null:
		return
	_known[e.id] = {}
	refresh(e)
	_send_slots(e, true)
	_view(e)
	_flush()

func entity_removed(_h: WorldHost, e: HostEntity) -> void:
	_known.erase(e.id)
	_bonding.erase(e.id)
	_sig.erase(e.id)
	_applied.erase(e.id)
	_tags.erase(e.id)
	_out.erase(e.id)

# --- the starting kit -------------------------------------------------------------------

## A new character's kit: the class's SRD default weapon and armour worn (iron where metal),
## and torches, a campfire, two healing potions, a bed, two ropes and supplies on hotbar slots
## 2-7; slot 1 stays empty and selected (the attack slot: Inventory.ATTACK_SLOT), so a left
## click fights. No blocks (M4): digging gives rubble to place.
static func give_kit(ch: Character) -> void:
	var g: Dictionary = Character.DEFAULTS.get(ch.class_slug, {}).get("gear", Character.FALLBACK_GEAR)
	var eq := ch.equipment
	if String(g.get("weapon", "")) != "":
		eq.put("main_hand", _plain(String(g["weapon"])))
	if String(g.get("armor", "")) != "":
		eq.put("armor", _plain(String(g["armor"])))
	if bool(g.get("shield", false)):
		eq.put("off_hand", _plain("shield"))
	var inv := ch.inventory
	inv.add(Items.make("tile:torch", 10))
	inv.add(Items.make("tile:campfire", 1))
	inv.add(Items.make_magic("potions-of-healing", 0).merged({"count": 2}, true))
	inv.add(Items.make("tile:bed", 1))
	inv.add(Items.make("tile:rope", 2))
	inv.add(Items.make("supplies", 12))
	inv.selected = Inventory.ATTACK_SLOT
	inv.kit_given = true

static func _plain(base: String) -> Dictionary:
	var it := Items.make(base)
	if Items.takes_material(base):
		it["material"] = "iron"
	return it

# --- what other systems call ----------------------------------------------------------------

## ItemEffects mods of everything e wears (unbonded magic left out).
func gear_mods(e: HostEntity) -> Array:
	return e.character.equipment.mods_list() if e != null and e.character != null else []

## The main-hand record ({} if none).
func wielded(e: HostEntity) -> Dictionary:
	return e.character.equipment.wielded() if e != null and e.character != null else {}

## Dress a combatant (e.combatant by default) in e's equipment (Equipment.dress).
func outfit(e: HostEntity, c: Combatant = null) -> void:
	if e == null or e.character == null:
		return
	e.character.equipment.dress(c if c != null else e.combatant, e.character, host.srd if host != null else WorldHost.shared_srd())

## Movement sparks onto `stats`, the rest as tags into `out` (Sparks.apply).
func apply_sparks(e: HostEntity, stats: MoveStats, out: Dictionary) -> void:
	if e != null and e.character != null:
		Sparks.apply(e.character.sparks.list(), stats, out)

## Game tags of e's worn gear and kindled sparks, summed (dig_speed, light, pickup_radius,
## swing_recovery, reach, ...: data/items/affixes.json and data/sparks.json).
func tags(e: HostEntity) -> Dictionary:
	if e == null:
		return {}
	if not _tags.has(e.id) and e.character != null:
		_tags[e.id] = _compute_tags(e)
	return _tags.get(e.id, {})

func _compute_tags(e: HostEntity) -> Dictionary:
	return Items.merge_tags([e.character.equipment.tags(), Sparks.tags(e.character.sparks.list())])

## Rebuild after gear, sparks or level change: rules.refresh when the rules system is there,
## else outfit here; then e.stats from the base speeds plus sparks (the same computation the
## client mirrors), tags, and the STARS mirror.
func refresh(e: HostEntity) -> void:
	if e == null or e.character == null:
		return
	e.character.sparks.slots = e.character.spark_slots()
	var rules := host.system(HostSystem.RULES) if host != null else null
	if rules != null and rules.has_method("refresh") and not _refreshing.has(e.id):
		_refreshing[e.id] = true      # rules.refresh may call back into items.refresh
		rules.call("refresh", e)
		_refreshing.erase(e.id)
	else:
		outfit(e)
	_tags[e.id] = _compute_tags(e)
	_apply_move(e)

## Reach and dig speed from the tags onto the entity (the owner's ItemsClient computes the
## same from its mirror: ItemsClient.edit_numbers).
func _apply_edit(e: HostEntity) -> void:
	var n := Items.edit_numbers(_tags.get(e.id, {}))
	e.edit_reach = n.x
	e.dig_power = n.y

func _base(e: HostEntity) -> Dictionary:
	var b := e.character.move_stats(e.combatant)
	return {"speeds": {"walk": roundi(b.walk), "climb": roundi(b.climb), "swim": roundi(b.swim), "fly": roundi(b.fly)},
			"size": b.size_name}

## e.stats = Sparks.move_stats(base speeds, size, kindled); STARS to the owner when it changed.
func _apply_move(e: HostEntity) -> void:
	_apply_edit(e)
	var b := _base(e)
	var kindled := e.character.sparks.list()
	e.stats = Sparks.move_stats(b["speeds"], b["size"], kindled)
	_applied[e.id] = e.stats
	var sig := [b, e.character.sparks.slots, e.character.sparks.to_dict()]
	if _sig.get(e.id) != sig:
		_sig[e.id] = sig
		host.send_sys(sys_id(), ItemsCodec.K.STARS, ItemsCodec.stars(b["speeds"], b["size"],
				e.character.sparks.slots, e.character.sparks.kindled), e.id)

## Put an item into a player's inventory. Returns what did not fit ({} when all of it did).
func give(entity_id: int, item: Dictionary) -> Dictionary:
	var e := host.entity(entity_id)
	if e == null or e.character == null:
		return item
	var left := e.character.inventory.add(item)
	_send_slots(e)
	return left

## Loot on the ground at pos (tile units): each record becomes a drop that falls.
func drop(pos: Vector2, items: Array, from := 0) -> void:
	for it: Variant in items:
		if it is Dictionary and not (it as Dictionary).is_empty() and Items.count(it) > 0:
			var v := Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(4.0, 8.0))
			_spawn(it, pos, v, from)

## Roll the victim's loot and drop it where it died. Rank from the entity's meta (meta.rank
## or look.rank: minion, standard, elite, champion, boss), type and CR from its SRD slug,
## spark rank from the depth band; Scavenger and drop_find/coin_find tags of the nearest
## player within 24 tiles count.
func on_kill(victim: HostEntity) -> Array:
	if victim == null or victim.body == null:
		return []
	var slug := String(victim.look.get("slug", ""))
	var info := Loot.victim_info(slug if not slug.begins_with("player") else "", rank_of(victim),
			Loot.depth_band(victim.body.pos.y, host.world.height), host.srd)
	var best := 24.0 * 24.0
	for p: HostEntity in host.entities.values():
		if p.is_player() and p.character != null:
			var d2 := p.body.center().distance_squared_to(victim.body.center())
			if d2 <= best:
				best = d2
				var t := tags(p)
				info["drop_find"] = float(t.get("drop_find", 0.0))
				info["coin_find"] = float(t.get("coin_find", 0.0))
	var items := Loot.roll(rng, info)
	drop(victim.body.center(), items)
	_flush()
	return items

static func rank_of(e: HostEntity) -> String:
	var meta: Variant = e.get("meta")
	if meta is Dictionary and (meta as Dictionary).has("rank"):
		return String(meta["rank"])
	return String(e.look.get("rank", "standard"))

# --- the edit flow ------------------------------------------------------------------------

func allow_place(_h: WorldHost, e: HostEntity, tile_id: int) -> bool:
	if not e.is_player() or e.character == null:
		return true
	return e.character.inventory.tile_slot(tile_id) >= 0

func tile_edited(_h: WorldHost, e: HostEntity, x: int, y: int, old: int, now: int) -> void:
	if not e.is_player() or e.character == null:
		return
	var inv := e.character.inventory
	if now == TileDefs.AIR:
		var base := Items.tile_drop(old)
		if base != "":
			var left := inv.add(Items.make(base, 1))
			if not left.is_empty():
				_spawn(left, Vector2(x + 0.5, y), Vector2(0, 2), 0)
	else:
		inv.take(inv.tile_slot(now), 1)
	_send_slots(e)     # before the EDIT_RESULT: a client never sees its place confirmed with the item still there

# --- client requests ----------------------------------------------------------------------

func handle(_h: WorldHost, e: HostEntity, kind: int, data: PackedByteArray) -> void:
	if not e.is_player() or e.character == null:
		return
	if kind != ItemsCodec.K.SELECT and kind != ItemsCodec.K.MOVE and _down(e):
		_note(e, kind, "down")       # no drinking, dropping, bonding or kindling while down
		_send_slots(e)
		_flush()
		return
	match kind:
		ItemsCodec.K.MOVE:
			if data.size() >= 2:
				_note(e, kind, move_item(e, data[0], data[1]))
		ItemsCodec.K.USE:
			if data.size() >= 1:
				_note(e, kind, use_item(e, data[0]))
		ItemsCodec.K.DROP:
			var d := ItemsCodec.read_drop_req(data)
			if not d.is_empty():
				_note(e, kind, drop_item(e, int(d["index"]), int(d["n"])))
		ItemsCodec.K.SELECT:
			if data.size() >= 1 and data[0] < Inventory.HOTBAR:
				e.character.inventory.selected = data[0]
				e.character.inventory.changed[-1] = true
		ItemsCodec.K.BOND:
			if data.size() >= 1:
				_note(e, kind, start_bond(e, data[0]))
		ItemsCodec.K.KINDLE:
			if data.size() >= 1:
				_note(e, kind, kindle(e, data[0]))
		ItemsCodec.K.SWAP:
			if data.size() >= 2:
				_note(e, kind, swap_spark(e, data[0], data[1]))
		ItemsCodec.K.CRAFT:
			var c := ItemsCodec.read_craft(data)
			if not c.is_empty():
				_note(e, kind, craft(e, String(c["recipe"]), int(c["times"])))
	_send_slots(e)
	_flush()

## Downed or dead (Rules): no item use, kindling, bonding or picking up.
func _down(e: HostEntity) -> bool:
	var rules := host.system(HostSystem.RULES) if host != null else null
	return rules != null and rules.has_method("is_downed") and bool(rules.call("is_downed", e))

## Refusals go to the owner as NOTE (ok = false); successes too (for UI feedback).
func _note(e: HostEntity, op: int, word: String) -> void:
	host.send_sys(sys_id(), ItemsCodec.K.NOTE, ItemsCodec.note(op, word == "", word if word != "" else "ok"), e.id)

## The record at a unified index (inventory 0-49, equipment 50-68).
static func item_at(ch: Character, index: int) -> Dictionary:
	if index < Inventory.SIZE:
		return ch.inventory.at(index)
	return ch.equipment.at(Equipment.slot_at(index))

## Move or swap between any two indices; b = ItemsCodec.ANY: to the first free bag/hotbar slot.
## "" on success, else a reason word.
func move_item(e: HostEntity, a: int, b: int) -> String:
	var ch := e.character
	var inv := ch.inventory
	var eq := ch.equipment
	var a_eq := a >= Equipment.FIRST
	if b == ItemsCodec.ANY:
		b = inv.first_free()
		if b < 0:
			return "full"
	var b_eq := b >= Equipment.FIRST
	if a < 0 or b < 0 or (a_eq and Equipment.slot_at(a) == "") or (b_eq and Equipment.slot_at(b) == ""):
		return "bad_index"
	var ia := item_at(ch, a)
	if ia.is_empty():
		return "empty"
	if not a_eq and not b_eq:
		return "" if inv.move(a, b) else "no_move"
	var gear_changed := true
	if not a_eq and b_eq:
		var slot := Equipment.slot_at(b)
		var why := eq.can_equip(ia, slot)
		if why == "off_hand_busy" and inv.first_free() >= 0:
			inv.put(inv.first_free(), eq.take("off_hand"))
			why = eq.can_equip(ia, slot)
		if why != "":
			return why
		var old := eq.put(slot, ia)
		inv.put(a, old)
	elif a_eq and not b_eq:
		var slot_a := Equipment.slot_at(a)
		var ib := inv.at(b)
		if not ib.is_empty():
			eq.take(slot_a)
			var why2 := eq.can_equip(ib, slot_a)
			if why2 != "":
				eq.put(slot_a, ia)
				return "occupied"
			eq.put(slot_a, ib)
		else:
			eq.take(slot_a)
		inv.put(b, ia)
	else:
		var sa := Equipment.slot_at(a)
		var sb := Equipment.slot_at(b)
		var ib2 := eq.at(sb)
		eq.take(sa)
		eq.take(sb)
		var why3 := eq.can_equip(ia, sb)
		if why3 == "" and not ib2.is_empty():
			eq.put(sb, ia)
			why3 = eq.can_equip(ib2, sa)
			eq.take(sb)
		if why3 != "":
			eq.put(sa, ia)
			if not ib2.is_empty():
				eq.put(sb, ib2)
			return why3
		eq.put(sb, ia)
		if not ib2.is_empty():
			eq.put(sa, ib2)
	if gear_changed:
		_bonding.erase(e.id)
		refresh(e)
	return ""

## Use what is in a slot: a potion heals (and is used up); wearable gear is put on.
func use_item(e: HostEntity, index: int) -> String:
	var ch := e.character
	if index >= Inventory.SIZE:
		return "bad_index"
	var it := ch.inventory.at(index)
	if it.is_empty():
		return "empty"
	var u := Items.use_of(it)
	if u.has("heal"):
		if e.combatant == null:
			return "no_body"
		var s := e.combatant.stats
		if s.current_hp >= s.max_hp:
			return "full_hp"
		var amount := maxi(1, Loot.roll_dice(host.rng, String(u["heal"])))
		var rules := host.system(HostSystem.RULES)
		if rules != null and rules.has_method("heal"):
			rules.call("heal", e, amount)      # one healing path (it also gets a downed player up)
		else:
			s.current_hp = mini(s.max_hp, s.current_hp + amount)
		ch.inventory.take(index, 1)
		return ""
	var kind := Items.slot_kind(it)
	if kind == "":
		return "not_usable"
	var target := ""
	if kind == "ring":
		target = "ring_1"
		for i in range(1, 11):
			if ch.equipment.is_empty_slot("ring_%d" % i):
				target = "ring_%d" % i
				break
	elif kind == "main_hand" and Items.is_weapon(it) and Items.is_light(it) and not ch.equipment.is_empty_slot("main_hand") \
			and ch.equipment.is_empty_slot("off_hand") and ch.equipment.can_equip(it, "off_hand") == "":
		target = "off_hand"
	else:
		target = kind
	return move_item(e, index, Equipment.index_of(target))

## Throw n of a slot's stack on the ground in front of the player.
func drop_item(e: HostEntity, index: int, n: int) -> String:
	var ch := e.character
	var it: Dictionary
	if index < Inventory.SIZE:
		it = ch.inventory.take(index, maxi(1, n))
	else:
		var slot := Equipment.slot_at(index)
		if slot == "":
			return "bad_index"
		it = ch.equipment.take(slot)
		if not it.is_empty():
			refresh(e)
	if it.is_empty():
		return "empty"
	_spawn(it, e.body.center(), Vector2(e.body.facing * 5.0, 6.0), e.id)
	return ""

## Start bonding the item at an index: it must need a bond, not have one, suit the class,
## and the player must be near a campfire; it completes after BOND_TIME there (tick).
func start_bond(e: HostEntity, index: int) -> String:
	var ch := e.character
	var it := item_at(ch, index)
	if it.is_empty():
		return "empty"
	if not Items.needs_bond(it):
		return "no_bond_needed"
	if bool(it.get("bonded", false)):
		return "bonded"
	if not Items.can_bond(it, ch.class_slug):
		return "class"
	if not near_tile(e, CAMPFIRE):
		return "no_campfire"
	_bonding[e.id] = {"index": index, "item": it.duplicate(true), "left": BOND_TIME}
	host.send_sys(sys_id(), ItemsCodec.K.BONDING, ItemsCodec.bonding(index, roundi(BOND_TIME * 1000.0)), e.id)
	return ""

func _bond_tick(e: HostEntity, dt: float) -> void:
	var b: Dictionary = _bonding[e.id]
	var index := int(b["index"])
	var it := item_at(e.character, index)
	if not Items.same_stack(it, b["item"]) or not near_tile(e, CAMPFIRE):
		_bonding.erase(e.id)
		host.send_sys(sys_id(), ItemsCodec.K.BONDING, ItemsCodec.bonding(index, 0), e.id)
		_note(e, ItemsCodec.K.BOND, "interrupted")
		return
	b["left"] = float(b["left"]) - dt
	if float(b["left"]) > 1e-6:
		return
	_bonding.erase(e.id)
	it["bonded"] = true
	if index < Inventory.SIZE:
		e.character.inventory.changed[index] = true
	else:
		e.character.equipment.changed[Equipment.slot_at(index)] = true
		refresh(e)
	host.send_sys(sys_id(), ItemsCodec.K.BONDING, ItemsCodec.bonding(index, 0), e.id)
	_note(e, ItemsCodec.K.BOND, "")
	_send_slots(e)

## Kindle the spark in an inventory slot into a free star (at a shrine).
func kindle(e: HostEntity, index: int) -> String:
	var ch := e.character
	var it := ch.inventory.at(index) if index < Inventory.SIZE else {}
	if not it.has("spark"):
		return "not_a_spark"
	if not near_tile(e, SHRINE):
		return "no_shrine"
	ch.sparks.slots = ch.spark_slots()
	var why := ch.sparks.kindle_refusal(it["spark"])
	if why != "":
		return why
	ch.sparks.kindle(it["spark"])
	ch.inventory.take(index, 1)
	refresh(e)
	return ""

## Put the spark in an inventory slot on star i; the old spark goes back to the inventory.
func swap_spark(e: HostEntity, star: int, index: int) -> String:
	var ch := e.character
	var it := ch.inventory.at(index) if index < Inventory.SIZE else {}
	if not it.has("spark"):
		return "not_a_spark"
	if not near_tile(e, SHRINE):
		return "no_shrine"
	var why := ch.sparks.swap_refusal(star, it["spark"])
	if why != "":
		return why
	var old_k: Dictionary = ch.sparks.kindled[star]
	var back := Items.spark_item(String(old_k["id"]), int(old_k["rank"]))
	if Items.count(it) > 1 and ch.inventory.room_for(back) < 1:
		return "full"
	var spark: Dictionary = it["spark"].duplicate()
	ch.inventory.take(index, 1)
	ch.sparks.swap(star, spark)
	var left := back
	if ch.inventory.is_empty_slot(index):
		ch.inventory.put(index, back)     # the old spark takes the new one's place
		left = {}
	else:
		left = ch.inventory.add(back)
	if not left.is_empty():
		_spawn(left, e.body.center(), Vector2(0, 4), e.id)
	refresh(e)
	return ""

## Hand-craft a recipe (data/items/recipes.json) `times` times.
func craft(e: HostEntity, recipe: String, times: int) -> String:
	var r: Dictionary = Items.recipes().get(recipe, {})
	if r.is_empty():
		return "unknown"
	var inv := e.character.inventory
	var ins: Dictionary = r["in"]
	for b: String in ins:
		if inv.count_base(b) < int(ins[b]) * times:
			return "missing"
	for b: String in ins:
		inv.remove_base(b, int(ins[b]) * times)
	var out := Items.clean(r["out"])
	out["count"] = Items.count(out) * times
	var left := inv.add(out)
	if not left.is_empty():
		_spawn(left, e.body.center(), Vector2(0, 4), e.id)
	return ""

## Is a tile of this id within STATION_RANGE tiles of e's box?
func near_tile(e: HostEntity, tile_id: int) -> bool:
	var r := e.body.rect().grow(STATION_RANGE)
	for y in range(floori(r.position.y), floori(r.end.y) + 1):
		for x in range(floori(r.position.x), floori(r.end.x) + 1):
			if host.world.in_bounds(x, y) and host.world.get_fg(x, y) == tile_id:
				return true
	return false

# --- tick ---------------------------------------------------------------------------------

func tick(h: WorldHost) -> void:
	var dt := h.dt()
	for id: int in _bonding.keys():
		var e := h.entity(id)
		if e == null:
			_bonding.erase(id)
		else:
			_bond_tick(e, dt)
	var res := drops.step(h.world, dt)
	for id: int in res["landed"]:
		var into := drops.merge(id)
		if into != 0:
			_gone(id, 0)
			_tell_add(drops.get_drop(into))
		else:
			_tell_moved(drops.get_drop(id))
	for id: int in res["woke"]:
		_tell_moved(drops.get_drop(id))
	for id: int in drops.expired():
		drops.remove(id)
		_gone(id, 0)
	if not drops.list.is_empty():
		_pickups()
	if h.tick_count % VIEW_EVERY == 0:
		for e: HostEntity in h.entities.values():
			if e.is_player() and _known.has(e.id):
				_view(e)
	if h.tick_count % CHECK_EVERY == 0:
		for e: HostEntity in h.entities.values():
			if e.is_player() and e.character != null and _known.has(e.id):
				e.character.sparks.slots = e.character.spark_slots()
				if e.stats != _applied.get(e.id) or _sig.get(e.id, [{}])[0] != _base(e) \
						or _sig.get(e.id, [{}, -1])[1] != e.character.sparks.slots:
					_tags[e.id] = _compute_tags(e)
					_apply_move(e)
	for e: HostEntity in h.entities.values():
		if e.is_player() and e.character != null:
			_send_slots(e)
	_flush()

## First to touch it gets it: players in entity order, each takes what fits.
func _pickups() -> void:
	for e: HostEntity in host.entities.values():
		if not e.is_player() or e.character == null or _down(e):
			continue
		# measured from the body's box, so loot in a dip at the feet or a step below is reached
		var box := e.body.rect()
		var r := PICKUP + float(tags(e).get("pickup_radius", 0.0))
		var r2 := r * r
		for d: Drops.Drop in drops.list.values():
			var near := Vector2(clampf(d.pos.x, box.position.x, box.end.x), clampf(d.pos.y, box.position.y, box.end.y))
			if d.pos.distance_squared_to(near) > r2 or not drops.pickable(d, e.id):
				continue
			var left := e.character.inventory.add(d.item)
			if left.is_empty():
				drops.remove(d.id)
				_gone(d.id, e.id)
			elif Items.count(left) < Items.count(d.item):
				d.item = left
				_tell_add(d)

# --- drops on the wire --------------------------------------------------------------------

func _spawn(item: Dictionary, pos: Vector2, vel: Vector2, from: int) -> Drops.Drop:
	var d := drops.spawn(item, pos, vel, from)
	_tell_add(d)
	return d

func _queue(eid: int) -> Dictionary:
	if not _out.has(eid):
		_out[eid] = {"add": [], "gone": [], "moved": []}
	return _out[eid]

static func _drop_msg(d: Drops.Drop) -> Dictionary:
	return {"id": d.id, "pos": d.pos, "vel": d.vel, "item": d.item}

## Tell players who see it (or are near enough to) about a new or changed drop.
func _tell_add(d: Drops.Drop) -> void:
	if d == null:
		return
	var dc := Interest.chunk_of(d.pos)
	for e: HostEntity in host.entities.values():
		if not _known.has(e.id):
			continue
		var k: Dictionary = _known[e.id]
		if k.has(d.id) or Interest.dist(Interest.chunk_of(e.body.center()), dc) <= Interest.DEFAULT_RADIUS:
			k[d.id] = true
			_queue(e.id)["add"].append(_drop_msg(d))

func _tell_moved(d: Drops.Drop) -> void:
	if d == null:
		return
	for eid: int in _known:
		if (_known[eid] as Dictionary).has(d.id):
			_queue(eid)["moved"].append({"id": d.id, "pos": d.pos, "vel": d.vel})

func _gone(id: int, by: int) -> void:
	for eid: int in _known:
		if (_known[eid] as Dictionary).erase(id):
			_queue(eid)["gone"].append([id, by])

## Drops entering (within the interest radius) and leaving (past radius + 1) e's view.
func _view(e: HostEntity) -> void:
	var k: Dictionary = _known.get(e.id, {})
	var c := Interest.chunk_of(e.body.center())
	for d: Drops.Drop in drops.list.values():
		var dist := Interest.dist(Interest.chunk_of(d.pos), c)
		if not k.has(d.id) and dist <= Interest.DEFAULT_RADIUS:
			k[d.id] = true
			_queue(e.id)["add"].append(_drop_msg(d))
		elif k.has(d.id) and dist > Interest.DEFAULT_RADIUS + 1:
			k.erase(d.id)
			_queue(e.id)["gone"].append([d.id, 0])

## Send queued drop messages (at most 200 per message).
func _flush() -> void:
	for eid: int in _out:
		var q: Dictionary = _out[eid]
		for i in range(0, (q["add"] as Array).size(), 200):
			host.send_sys(sys_id(), ItemsCodec.K.DROPS, ItemsCodec.drops(q["add"].slice(i, i + 200)), eid)
		for i in range(0, (q["moved"] as Array).size(), 500):
			host.send_sys(sys_id(), ItemsCodec.K.MOVED, ItemsCodec.moved(q["moved"].slice(i, i + 500)), eid)
		for i in range(0, (q["gone"] as Array).size(), 1000):
			host.send_sys(sys_id(), ItemsCodec.K.GONE, ItemsCodec.gone(q["gone"].slice(i, i + 1000)), eid)
	_out.clear()

## SLOTS to the owner: the changed indices (or all of them), coin and the selected slot.
func _send_slots(e: HostEntity, all := false) -> void:
	if e == null or e.character == null:
		return
	var inv := e.character.inventory
	var eq := e.character.equipment
	if not all and inv.changed.is_empty() and eq.changed.is_empty():
		return
	var entries: Array = []
	if all:
		for i in Inventory.SIZE:
			if not inv.at(i).is_empty():
				entries.append([i, inv.at(i)])
		for s: String in Equipment.SLOTS:
			if not eq.is_empty_slot(s):
				entries.append([Equipment.index_of(s), eq.at(s)])
	else:
		for i: int in inv.changed:
			if i >= 0:
				entries.append([i, inv.at(i)])
		for s: String in eq.changed:
			entries.append([Equipment.index_of(s), eq.at(s)])
	inv.changed.clear()
	eq.changed.clear()
	host.send_sys(sys_id(), ItemsCodec.K.SLOTS, ItemsCodec.slots(inv.coin, inv.selected, entries), e.id)
