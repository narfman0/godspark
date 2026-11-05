## What a player wears: one record per body slot. No attunement cap: if it fits, it works
## (items the SRD marks as needing attunement work once bonded, see Items.magic_active).
## Saved in the Character record (Character.equipment).
##
##   var eq := Equipment.new()
##   eq.can_equip(sword, "main_hand")   # "" when allowed, else a reason word
##   eq.dress(combatant, character, srd)  # the wielded weapon, armour, shield and every worn mod
class_name Equipment
extends RefCounted

const SLOTS := ["head", "neck", "cloak", "armor", "hands", "belt", "feet", "main_hand", "off_hand",
	"ring_1", "ring_2", "ring_3", "ring_4", "ring_5", "ring_6", "ring_7", "ring_8", "ring_9", "ring_10"]
## Equipment slots continue the inventory's index space (items_client, codec): slot i of
## SLOTS is index FIRST + i.
const FIRST := Inventory.SIZE

## slot name -> record
var worn := {}
## Slot names changed since the owner last looked; the owner clears it.
var changed := {}

static func index_of(slot: String) -> int:
	var i := SLOTS.find(slot)
	return FIRST + i if i >= 0 else -1

static func slot_at(index: int) -> String:
	var i := index - FIRST
	return SLOTS[i] if i >= 0 and i < SLOTS.size() else ""

func at(slot: String) -> Dictionary:
	return worn.get(slot, {})

func is_empty_slot(slot: String) -> bool:
	return at(slot).is_empty()

## Does the slot accept this item ("" yes, else why): bad_slot, not_wearable, two_handed
## (off hand while a two-handed weapon is held), not_light (off-hand weapon and main hand must
## both be Light, as the SRD's Light property), off_hand_busy (a two-handed weapon needs a
## free off hand), stack (one at a time).
func can_equip(item: Dictionary, slot: String) -> String:
	if not slot in SLOTS:
		return "bad_slot"
	if item.is_empty() or Items.count(item) != 1:
		return "stack" if not item.is_empty() else "not_wearable"
	var kind := Items.slot_kind(item)
	if kind == "":
		return "not_wearable"
	if slot.begins_with("ring_"):
		return "" if kind == "ring" else "bad_slot"
	if slot == "off_hand":
		var main := at("main_hand")
		if not main.is_empty() and Items.is_two_handed(main):
			return "two_handed"
		if kind == "off_hand":
			return ""
		if Items.is_weapon(item) and kind == "main_hand":
			if not Items.is_light(item):
				return "not_light"
			if not main.is_empty() and Items.is_weapon(main) and not Items.is_light(main):
				return "not_light"
			return ""
		return "bad_slot"
	if slot == "main_hand":
		if kind != "main_hand":
			return "bad_slot"
		var off := at("off_hand")
		if Items.is_two_handed(item) and not off.is_empty():
			return "off_hand_busy"
		if not off.is_empty() and Items.is_weapon(off) and not Items.is_light(item):
			return "not_light"
		return ""
	return "" if kind == slot else "bad_slot"

## Put an item on (no checks: call can_equip first). Returns what was there ({} if none).
func put(slot: String, item: Dictionary) -> Dictionary:
	var old := at(slot)
	if item.is_empty():
		worn.erase(slot)
	else:
		worn[slot] = item.duplicate(true)
	changed[slot] = true
	return old

func take(slot: String) -> Dictionary:
	return put(slot, {})

## The main-hand record ({} if none).
func wielded() -> Dictionary:
	return at("main_hand")

## ItemEffects mods of everything worn (unbonded magic left out).
func mods_list() -> Array:
	var out: Array = []
	for slot: String in SLOTS:
		var it := at(slot)
		if not it.is_empty():
			out.append_array(Items.mods(it, true))
	return out

## Game tags of everything worn (Items.tags, summed).
func tags() -> Dictionary:
	var all: Array = []
	for slot: String in SLOTS:
		var it := at(slot)
		if not it.is_empty():
			all.append(Items.tags(it))
	return Items.merge_tags(all)

## Base slugs for the combatant: {weapon, armor, shield: bool, off_weapon}.
func gear_spec() -> Dictionary:
	var main := at("main_hand")
	var armor := at("armor")
	var off := at("off_hand")
	return {
		"weapon": String(main.get("base", "")) if Items.is_weapon(main) else "",
		"armor": String(armor.get("base", "")) if String(Items.row(String(armor.get("base", ""))).get("kind", "")) == "armor" else "",
		"shield": Items.is_shield(off),
		"off_weapon": String(off.get("base", "")) if Items.is_weapon(off) else "",
	}

## Put this equipment on a combatant built by Character.make_combatant: the wielded weapon
## (addon WeaponData from the base slug; proficiency per the class), the armour and shield,
## an off-hand weapon, then every worn item's mods through ItemEffects, then max hit points
## again from the level track (ItemEffects counts a CON change per class level only).
func dress(c: Combatant, ch: Character, srd: SRDContent) -> void:
	if c == null or srd == null:
		return
	var g := gear_spec()
	var w := String(g["weapon"])
	c.weapon = srd.make_weapon(w) if w != "" else null
	var protector: bool = c.kit != null and c.kit.has_feature("divine-order") and c.kit.options.get("divine_order") == "protector"
	var cd: ClassData = srd.make_class(ch.class_slug) if ch != null else null
	c.is_proficient_with_weapon = c.weapon == null or protector or (cd != null and SRDContent.is_weapon_proficient(cd, c.weapon))
	var a := String(g["armor"])
	c.equipment.armor = srd.make_armor(a) if a != "" else null
	c.equipment.shield = srd.make_armor("shield") if g["shield"] else null
	var ow := String(g["off_weapon"])
	c.equipment.off_hand = srd.make_weapon(ow) if ow != "" else null
	if c.kit != null:
		c.kit.adapt_weapon(c)
		if w != "" and not c.kit.weapon_masteries.is_empty() and not w in c.kit.weapon_masteries:
			var n: int = c.kit.weapon_masteries.size()
			var picks: Array = [w]
			for m: Variant in c.kit.weapon_masteries:
				if picks.size() < n:
					picks.append(m)
			c.kit.weapon_masteries.assign(picks)
	var old_max := c.stats.max_hp
	ItemEffects.apply(c, mods_list())
	if ch != null:
		var mx := LevelTrack.max_hp(ch.level, c.stats.hit_die, c.stats.ability_modifier(SRD.Ability.CONSTITUTION))
		c.stats.max_hp = mx
		c.stats.current_hp = clampi(c.stats.current_hp, 0 if c.stats.current_hp <= 0 else 1, mx)
		if old_max != mx and c.stats.current_hp > 0:
			c.stats.current_hp = clampi(c.stats.current_hp, 1, mx)

func to_dict() -> Dictionary:
	var out := {}
	for slot: String in SLOTS:
		if worn.has(slot):
			out[slot] = (worn[slot] as Dictionary).duplicate(true)
	return out

static func from_dict(d: Variant) -> Equipment:
	var eq := Equipment.new()
	if d is Dictionary:
		for slot: String in SLOTS:
			var rec := Items.clean(d.get(slot, {}))
			if not rec.is_empty() and Items.exists(String(rec["base"])):
				eq.worn[slot] = rec
	return eq
