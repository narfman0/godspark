## Tooltip text for an item record (pure: tests read it). Lines are [text, style]; styles:
## title, sub, stat, good, bad, magic, warn, flavor. The tooltip widget colours them.
##   ItemText.lines(item, {worn: {...}, class: "fighter"})   # comparison with what is worn
##   ItemText.plain(item)                                     # one string (tests, logs)
class_name ItemText
extends RefCounted

## Item tag (data/items/affixes.json units) -> words. %s is the amount, already formatted.
const TAG_WORDS := {
	"dig_speed": "dig %s faster", "light": "carry %s more light", "pickup_radius": "pick things up %s tiles further",
	"swing_recovery": "recover from swings %s faster", "reach": "reach %s tiles further", "swim": "swim %s faster",
	"jump": "jump %s tiles higher", "climb": "climb walls", "fall_resist": "take %s less from falls",
	"knockback_resist": "%s steadier against blows", "coin_find": "find %s more coin", "drop_find": "find %s more loot",
	"dim_sight": "see %s tiles further in the dim", "ore_sense": "sense ore within %s tiles", "regen": "regain %s HP a minute",
	"thorns": "%s damage back to whoever hits you", "breath": "breathe underwater", "weight_mult": "%s lighter",
	"silvered": "silvered (hurts what silver hurts)", "sunder": "sunders stone and armour", "cast_move": "keep %s of your pace while casting",
	"price_mult": "%s better prices", "reputation_mult": "peoples warm %s faster", "beast_peace": "%s chance a beast lets you be",
}
const PERCENT_TAGS := ["dig_speed", "swing_recovery", "swim", "fall_resist", "knockback_resist", "coin_find", "drop_find",
	"weight_mult", "cast_move", "price_mult", "reputation_mult", "beast_peace"]

static var _srd: SRDContent

static func srd() -> SRDContent:
	if _srd == null:
		_srd = WorldHost.shared_srd()
	return _srd

static func lines(item: Dictionary, ctx := {}) -> Array:
	var out: Array = []
	if item.is_empty():
		return out
	var base := String(item.get("base", ""))
	var row := Items.row(base)
	var name := ItemGen.name(item)
	var n := Items.count(item)
	out.append([name + (" x%d" % n if n > 1 else ""), "title"])
	var rar := ItemIcons.rarity(item)
	var kind := Items.kind(item)
	var sub := PackedStringArray()
	if rar != "" and rar != "fine":
		sub.append(rar.capitalize())
	sub.append(_kind_word(item, kind))
	if item.has("material"):
		sub.append(String(Items.materials().get(String(item["material"]), {}).get("name", "")))
	if item.has("quality"):
		sub.append(String(Items.quality_table().get(String(item["quality"]), {}).get("name", "")) + " make")
	out.append([" · ".join(sub), "sub"])
	# base numbers
	if kind == "weapon":
		var w := srd().make_weapon(base) if srd().pack.has_row("weapon", base) else null
		if w != null:
			var dmg := "%dd%d %s" % [w.die_count, w.die_sides, String(SRD.DamageType.find_key(w.damage_type)).to_lower()]
			if w.versatile_die_count > 0:
				dmg += " (%dd%d two-handed)" % [w.versatile_die_count, w.versatile_die_sides]
			out.append([dmg, "stat"])
			var props := PackedStringArray()
			if bool(row.get("light", false)):
				props.append("light")
			if bool(row.get("two_handed", false)):
				props.append("two-handed")
			if w.range_normal > 5:
				props.append("range %d/%d ft" % [w.range_normal, w.range_long])
			if w.mastery != "":
				props.append("mastery: " + w.mastery.capitalize())
			if not props.is_empty():
				out.append([", ".join(props), "flavor"])
	elif kind == "armor" or kind == "shield":
		if kind == "shield":
			out.append(["+2 AC", "stat"])
		elif srd().pack.has_row("armor", base):
			var a := srd().make_armor(base)
			var dex := "" if a.max_dex_bonus == 0 else (" + Dex" if a.max_dex_bonus < 0 else " + Dex (max %d)" % a.max_dex_bonus)
			out.append(["AC %d%s" % [a.base_ac, dex], "stat"])
			if a.stealth_disadvantage and not _has_mod(item, "heavy_stealth"):
				out.append(["Disadvantage on Stealth", "flavor"])
			if a.strength_requirement > 0 and not _has_mod(item, "strength_free"):
				out.append(["Needs Str %d" % a.strength_requirement, "flavor"])
	var b := Items.budget_of(item)
	if b.x != 0:
		out.append(["%+d to hit" % b.x, "good"])
	if b.y != 0 and kind != "shield":
		out.append(["%+d AC" % b.y, "good"])
	# affixes and material/quality perks in plain words
	for m: Dictionary in Items.mods(item):
		for s in mod_words(m):
			out.append([s, "good"])
	for t in tag_words(_gear_tags(item)):
		out.append([t, "good"])
	var use := Items.use_of(item)
	if use.has("heal"):
		out.append(["Drink: heal %s" % String(use["heal"]), "stat"])
	if item.has("spark"):
		var sp: Dictionary = item["spark"]
		var id := String(sp.get("id", ""))
		out.append([String(Sparks.row(id).get("text", "")), "magic"])
		out.append([spark_effect(id, int(sp.get("rank", 0))), "good"])
		out.append(["Kindle it at a shrine (K).", "flavor"])
	if item.has("magic"):
		var e := Items.magic_entry(String(item["magic"]))
		var txt := String(e.get("text", ""))
		if txt != "":
			out.append([_clip(txt, 260), "magic"])
		var status := String(e.get("status", ""))
		if status == "inert":
			out.append(["Its magic sleeps for now (not in play yet).", "flavor"])
		if Items.needs_bond(item):
			if bool(item.get("bonded", false)):
				out.append(["Bonded to you.", "magic"])
			else:
				var by := Items.bond_by(item)
				out.append(["Needs bonding at a campfire%s." % (" (%s)" % by if by != "" else ""), "warn"])
				var cls := String(ctx.get("class", ""))
				if cls != "" and not Items.can_bond(item, cls):
					out.append(["It will not bond with a %s." % cls.capitalize(), "bad"])
	# comparison with what is worn in that slot
	var worn: Dictionary = ctx.get("worn", {})
	if not worn.is_empty() and worn != item:
		out.append(["Worn: " + ItemGen.name(worn), "sub"])
		for s in compare(item, worn):
			out.append([s, "good" if s.begins_with("+") else "bad"])
	var foot := PackedStringArray()
	var wt := Items.weight(item)
	if wt > 0.0:
		foot.append("%s lb" % _num(wt * maxi(1, n)))
	var v := Items.value(item)
	if v > 0:
		foot.append("worth %d gp" % (v * maxi(1, n)))
	if not foot.is_empty():
		out.append([", ".join(foot), "flavor"])
	return out

static func plain(item: Dictionary, ctx := {}) -> String:
	return "\n".join(lines(item, ctx).map(func(l: Array) -> String: return String(l[0])))

static func _kind_word(item: Dictionary, kind: String) -> String:
	if item.has("spark"):
		return "spark"
	var sk := Items.slot_kind(item)
	match kind:
		"weapon":
			return String(Items.row(String(item["base"])).get("category", "weapon"))
		"armor":
			return "%s armour" % String(Items.row(String(item["base"])).get("armor_type", ""))
		"tile":
			return "block"
		"coin":
			return "coin"
	if sk != "":
		return sk.replace("_", " ")
	return kind if kind != "" else "thing"

static func _has_mod(item: Dictionary, key: String) -> bool:
	for m: Dictionary in Items.mods(item):
		if m.has(key):
			return true
	return false

static func _gear_tags(item: Dictionary) -> Dictionary:
	return Items.tags(item)

## ItemEffects mods other than the to-hit/AC budget, in words.
static func mod_words(m: Dictionary) -> Array:
	var out: Array = []
	if m.has("extra_damage"):
		var e: Dictionary = m["extra_damage"]
		out.append("+%s %s on every hit" % [String(e.get("dice", "")), String(e.get("type", ""))])
	for k: String in ["resist", "immune"]:
		for t: Variant in m.get(k, []):
			out.append("%s %s" % ["Resist" if k == "resist" else "Immune to", String(t)])
	if m.has("speed"):
		out.append("%+d ft speed" % int(m["speed"]))
	if m.has("save"):
		out.append("%+d to saving throws" % int(m["save"]))
	if m.has("spell_attack"):
		out.append("%+d to spell attacks" % int(m["spell_attack"]))
	if m.has("spell_dc"):
		out.append("%+d spell save DC" % int(m["spell_dc"]))
	if m.has("damage"):
		out.append("%+d damage" % int(m["damage"]))
	if m.has("unarmored_ac"):
		out.append("%+d AC without armour" % int(m["unarmored_ac"]))
	for k: String in ["ability", "set_ability"]:
		var d: Dictionary = m.get(k, {})
		for a: String in d:
			out.append(("%s %+d" if k == "ability" else "%s becomes %d") % [a.to_upper(), int(d[a])])
	if m.has("crit_immune"):
		out.append("Critical hits on you become normal hits")
	if m.has("strength_free"):
		out.append("No Strength needed")
	if m.has("heavy_stealth"):
		out.append("No Stealth disadvantage")
	return out

static func tag_words(tags: Dictionary) -> Array:
	var out: Array = []
	for k: String in tags:
		var v := float(tags[k])
		if v == 0.0 or not TAG_WORDS.has(k):
			continue
		var amt := ("%d%%" % roundi(v * 100.0)) if k in PERCENT_TAGS else _num(v)
		var s := String(TAG_WORDS[k])
		var s2 := s % amt if s.contains("%s") else s
		out.append(s2.left(1).to_upper() + s2.substr(1))
	return out

## A spark's effect at a rank, in words.
static func spark_effect(id: String, rank: int) -> String:
	var eff := Sparks.effect(id, rank)
	var mv: Dictionary = eff.get("move", {})
	var parts := PackedStringArray()
	if mv.has("run_mult"):
		parts.append("run %d%% faster" % roundi((float(mv["run_mult"]) - 1.0) * 100.0))
	if mv.has("jump_add"):
		parts.append("jump %s tiles higher" % _num(float(mv["jump_add"])))
	if mv.has("air_jumps"):
		parts.append("%d extra jump%s in the air" % [int(mv["air_jumps"]), "" if int(mv["air_jumps"]) == 1 else "s"])
	if mv.has("dash_speed"):
		parts.append("dash every %ss (Shift or double tap)" % _num(float(mv.get("dash_cooldown", 1.0))))
	if mv.has("glide_fall"):
		parts.append("hold jump to fall at most %s tiles/s" % _num(float(mv["glide_fall"])))
	if mv.has("climb_speed") or mv.has("climb_mult"):
		parts.append("cling and climb walls at %s tiles/s" % _num(snappedf(Sparks.climb_of(mv), 0.1)))
	if mv.has("swim_mult"):
		parts.append("swim %d%% faster" % roundi((float(mv["swim_mult"]) - 1.0) * 100.0))
	for t in tag_words(eff.get("tags", {})):
		parts.append(t.to_lower())
	var s := ", ".join(parts)
	return s.left(1).to_upper() + s.substr(1)

## What changes if `item` replaces `worn`: ["+1 AC", "-2 to hit"...].
static func compare(item: Dictionary, worn: Dictionary) -> Array:
	var a := Items.budget_of(item)
	var b := Items.budget_of(worn)
	var out: Array = []
	if a.x != b.x:
		out.append("%+d to hit" % (a.x - b.x))
	if a.y != b.y:
		out.append("%+d AC" % (a.y - b.y))
	if Items.kind(item) == "armor" and Items.kind(worn) == "armor" and srd().pack.has_row("armor", String(item["base"])) and srd().pack.has_row("armor", String(worn["base"])):
		var d := srd().make_armor(String(item["base"])).base_ac - srd().make_armor(String(worn["base"])).base_ac
		if d != 0:
			out.append("%+d base AC" % d)
	if Items.kind(item) == "weapon" and Items.kind(worn) == "weapon" and srd().pack.has_row("weapon", String(item["base"])) and srd().pack.has_row("weapon", String(worn["base"])):
		var wa := srd().make_weapon(String(item["base"]))
		var wb := srd().make_weapon(String(worn["base"]))
		var avg := wa.die_count * (wa.die_sides + 1) * 0.5 - wb.die_count * (wb.die_sides + 1) * 0.5
		if absf(avg) >= 0.5:
			out.append("%s average damage" % ("%+.1f" % avg))
	return out

static func _num(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v

static func _clip(s: String, n: int) -> String:
	s = s.replace("\n", " ")
	return s if s.length() <= n else s.substr(0, n).rsplit(" ", true, 1)[0] + "..."
