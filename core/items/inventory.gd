## A player's carried items: a 10-slot hotbar (slots 0-9) and a 40-slot bag (10-49), item
## records stacking when identical (Items.same_stack) up to Items.stack_max, and coin as a
## number. Saved in the Character record (Character.inventory).
##
##   var inv := Inventory.new()
##   var left := inv.add({"base": "tile:wood", "count": 30})   # {} when it all fit
##   var got := inv.take(3, 1)                                  # one off slot 3
class_name Inventory
extends RefCounted

const HOTBAR := 10
const BAG := 40
const SIZE := HOTBAR + BAG

## SIZE records; {} for an empty slot.
var slots: Array = []
var coin := 0
## Selected hotbar slot (0-9).
var selected := 0
## The starting kit was given (new characters get it once).
var kit_given := false
## Slot indices changed since the owner last looked (for sync); the owner clears it.
var changed := {}

func _init() -> void:
	slots.resize(SIZE)
	for i in SIZE:
		slots[i] = {}

func at(i: int) -> Dictionary:
	return slots[i] if i >= 0 and i < SIZE else {}

func put(i: int, item: Dictionary) -> void:
	if i < 0 or i >= SIZE:
		return
	slots[i] = item.duplicate(true) if not item.is_empty() and Items.count(item) > 0 else {}
	changed[i] = true

func is_empty_slot(i: int) -> bool:
	return at(i).is_empty()

func first_free() -> int:
	for i in SIZE:
		if slots[i].is_empty():
			return i
	return -1

## How many of `item` would fit (coin: all).
func room_for(item: Dictionary) -> int:
	if String(item.get("base", "")) == "coin":
		return Items.count(item)
	var mx := Items.stack_max(item)
	var n := 0
	for s: Dictionary in slots:
		if s.is_empty():
			n += mx
		elif Items.same_stack(s, item):
			n += maxi(0, mx - Items.count(s))
	return n

## Add a record: coin goes to `coin`; the rest tops up matching stacks, then fills empty
## slots (hotbar first). Returns what did not fit ({} when everything did).
func add(item: Dictionary) -> Dictionary:
	if item.is_empty() or Items.count(item) <= 0:
		return {}
	if String(item.get("base", "")) == "coin":
		coin += Items.count(item)
		changed[-1] = true
		return {}
	var left := Items.count(item)
	var mx := Items.stack_max(item)
	for i in SIZE:
		if left <= 0:
			break
		var s: Dictionary = slots[i]
		if not s.is_empty() and Items.same_stack(s, item) and Items.count(s) < mx:
			var n := mini(left, mx - Items.count(s))
			s["count"] = Items.count(s) + n
			left -= n
			changed[i] = true
	for i in SIZE:
		if left <= 0:
			break
		if slots[i].is_empty():
			var n := mini(left, mx)
			slots[i] = Items.with_count(item, n)
			left -= n
			changed[i] = true
	return {} if left <= 0 else Items.with_count(item, left)

## Take up to n from slot i. Returns the record taken ({} if none).
func take(i: int, n: int) -> Dictionary:
	var s := at(i)
	if s.is_empty() or n <= 0:
		return {}
	var k := mini(n, Items.count(s))
	var out := Items.with_count(s, k)
	if k >= Items.count(s):
		slots[i] = {}
	else:
		s["count"] = Items.count(s) - k
	changed[i] = true
	return out

## Move slot a onto slot b: merge when they stack, otherwise swap.
func move(a: int, b: int) -> bool:
	if a == b or a < 0 or b < 0 or a >= SIZE or b >= SIZE or slots[a].is_empty():
		return false
	var sa: Dictionary = slots[a]
	var sb: Dictionary = slots[b]
	if not sb.is_empty() and Items.same_stack(sa, sb):
		var mx := Items.stack_max(sb)
		var n := mini(Items.count(sa), mx - Items.count(sb))
		if n <= 0:
			slots[a] = sb
			slots[b] = sa
		else:
			sb["count"] = Items.count(sb) + n
			if n >= Items.count(sa):
				slots[a] = {}
			else:
				sa["count"] = Items.count(sa) - n
	else:
		slots[a] = sb
		slots[b] = sa
	changed[a] = true
	changed[b] = true
	return true

## Total count of a base.
func count_base(base: String) -> int:
	var n := 0
	for s: Dictionary in slots:
		if not s.is_empty() and String(s.get("base", "")) == base:
			n += Items.count(s)
	return n

## Remove n of a base across slots (bag first, then hotbar from the right). False (and
## nothing removed) if there are fewer.
func remove_base(base: String, n: int) -> bool:
	if count_base(base) < n:
		return false
	var left := n
	for i in range(SIZE - 1, -1, -1):
		if left <= 0:
			break
		var s: Dictionary = slots[i]
		if not s.is_empty() and String(s.get("base", "")) == base:
			left -= Items.count(take(i, left))
	return true

## The slot a place of `tile_id` takes from: the selected hotbar slot if it holds that tile,
## else the first slot that does (hotbar first); -1 if none.
func tile_slot(tile_id: int) -> int:
	if tile_id <= 0:
		return -1
	var sel := at(selected)
	if not sel.is_empty() and Items.tile_of(sel) == tile_id:
		return selected
	for i in SIZE:
		if not slots[i].is_empty() and Items.tile_of(slots[i]) == tile_id:
			return i
	return -1

## Tile id of the selected hotbar item (0 if it is not a placeable tile).
func selected_tile() -> int:
	var s := at(selected)
	return Items.tile_of(s) if not s.is_empty() else 0

## [{slot, item}] of the filled slots.
func filled() -> Array:
	var out: Array = []
	for i in SIZE:
		if not slots[i].is_empty():
			out.append({"slot": i, "item": slots[i]})
	return out

func to_dict() -> Dictionary:
	var s: Array = []
	for i in SIZE:
		if not slots[i].is_empty():
			s.append([i, slots[i].duplicate(true)])
	return {"slots": s, "coin": coin, "selected": selected, "kit": kit_given}

static func from_dict(d: Variant) -> Inventory:
	var inv := Inventory.new()
	if d is Dictionary:
		for e: Variant in d.get("slots", []):
			if e is Array and (e as Array).size() == 2:
				var i := int(e[0])
				var rec := Items.clean(e[1])
				if i >= 0 and i < SIZE and not rec.is_empty() and Items.exists(String(rec["base"])):
					inv.slots[i] = rec
		inv.coin = int(d.get("coin", 0))
		inv.selected = clampi(int(d.get("selected", 0)), 0, HOTBAR - 1)
		inv.kit_given = bool(d.get("kit", false))
	return inv
