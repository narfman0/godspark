## Item catalogue, record composition and mods, the +3 budget, affixes, names, ItemGen.
extends RefCounted

func run(t: TestLog) -> void:
	Items.ensure()
	_catalogue(t)
	_mods(t)
	_budget(t)
	_affixes(t)
	_names(t)
	_gen_deterministic(t)
	_coverage(t)

func _catalogue(t: TestLog) -> void:
	var weapons: Array = JSON.parse_string(FileAccess.get_file_as_string(Items.SRD_DIR + "weapons.json"))
	var armor: Array = JSON.parse_string(FileAccess.get_file_as_string(Items.SRD_DIR + "armor.json"))
	var ok := true
	for r: Dictionary in weapons:
		ok = ok and Items.row(r["slug"]).get("kind") == "weapon"
	t.check(ok and weapons.size() == 38, "every SRD weapon is a base row (38)")
	ok = true
	for r: Dictionary in armor:
		ok = ok and String(Items.row(r["slug"]).get("kind")) in ["armor", "shield"]
	t.check(ok and armor.size() == 13, "every SRD armour is a base row (13)")
	t.eq(Items.magic_slugs().size(), 258, "every SRD magic item is known")
	t.eq(Items.row("longsword")["two_handed"], false, "longsword is not two-handed")
	t.eq(Items.row("greatsword")["two_handed"], true, "greatsword is two-handed")
	t.eq(Items.row("dagger")["light"], true, "dagger is light")
	t.eq(Items.row("shield")["slot"], "off_hand", "a shield goes in the off hand")
	# tiles
	for n: String in ["dirt", "stone", "wood", "torch", "platform", "ladder", "copper_ore", "campfire", "bed", "shrine"]:
		t.eq(Items.tile_of(Items.make("tile:" + n)), TileDefs.id(n), "tile:%s places %s" % [n, n])
	t.check(not Items.exists("tile:bedrock") and not Items.exists("tile:air"), "no item for air or bedrock")
	t.eq(Items.tile_drop(TileDefs.id("grass")), "tile:dirt", "grass drops dirt")
	t.eq(Items.tile_drop(TileDefs.id("iron_ore")), "tile:iron_ore", "ore drops ore")
	for n: String in ["torch", "platform", "ladder", "campfire", "bed", "shrine", "stone"]:
		t.eq(Items.tile_drop(TileDefs.id(n)), "tile:" + n, "%s drops itself" % n)
	t.eq(Items.tile_drop(TileDefs.id("bedrock")), "", "bedrock drops nothing")
	t.eq(Items.stack_max(Items.make("tile:dirt")), 999, "tiles stack to 999")
	t.eq(Items.stack_max(Items.make("longsword")), 1, "weapons do not stack")
	t.eq(Items.stack_max(Items.make_magic("potions-of-healing")), 20, "potions stack to 20")
	for b: String in ["ingot:iron", "cloth", "leather", "coin", "spark"]:
		t.check(Items.exists(b), "base %s exists" % b)
	# stacking identity
	var a := {"base": "longsword", "count": 1, "material": "iron"}
	t.check(Items.same_stack(a, {"base": "longsword", "count": 3, "material": "iron"}), "same record stacks")
	t.check(not Items.same_stack(a, {"base": "longsword", "count": 1, "material": "copper"}), "another material does not")
	t.check(not Items.same_stack(Items.spark_item("fleet", 0), Items.spark_item("fleet", 1)), "spark ranks differ")
	t.check(Items.same_stack({"base": "x", "count": 1, "tier": 1}, {"base": "x", "count": 2.0, "tier": 1.0}), "JSON floats compare equal")
	var c := Items.clean(JSON.parse_string(JSON.stringify({"base": "longsword", "count": 1, "tier": 2, "affixes": ["embers"], "spark": {"id": "fleet", "rank": 1}})))
	t.check(c["count"] is int and c["tier"] is int and c["spark"]["rank"] is int, "clean() makes JSON numbers ints")

func _mods(t: TestLog) -> void:
	var plain := {"base": "longsword", "count": 1, "material": "iron"}
	t.eq(Items.mods(plain), [], "plain iron longsword: no mods")
	var mith := {"base": "longsword", "count": 1, "material": "mithral"}
	t.eq(Items.budget_of(mith), Vector2i(1, 0), "mithral weapon: +1 to hit")
	var mith_armor := {"base": "chain-mail", "count": 1, "material": "mithral"}
	var m: Array = Items.mods(mith_armor)
	t.check(m.size() == 1 and m[0].get("strength_free") == true and m[0].get("heavy_stealth") == true, "mithral armour: the SRD's mithral properties")
	var adam := {"base": "plate-armor", "count": 1, "material": "adamantine"}
	t.check(Items.mods(adam)[0].get("crit_immune") == true, "adamantine armour: crits become hits")
	var fire := {"base": "longsword", "count": 1, "affixes": ["embers:2"]}
	t.eq(Items.mods(fire), [{"extra_damage": {"name": "Embers", "dice": "1d6", "type": "fire"}}], "affix tier 2 adds 1d6 fire")
	var plus := {"base": "longsword", "count": 1, "material": "iron", "magic": "weapon-1-2-or-3", "tier": 1}
	t.eq(Items.budget_of(plus), Vector2i(2, 0), "Longsword +2: +2 to hit")
	t.eq(Items.mods(plus)[-1], {"attack": 2, "damage": 2}, "and +2 damage")
	var ring := Items.make_magic("ring-of-protection")
	t.eq(ring["base"], "ring-of-protection", "a wondrous item is its own base")
	t.eq(Items.mods(ring), [{"ac": 1, "save": 1}], "ring of protection mods")
	t.eq(Items.mods(ring, true), [], "unbonded: inactive")
	ring["bonded"] = true
	t.eq(Items.mods(ring, true), [{"ac": 1, "save": 1}], "bonded: active")
	t.check(not Items.needs_bond(plus), "a +N weapon needs no bond")
	var vic := Items.make_magic("vicious-weapon", 0, "warhammer")
	t.eq(Items.mods(vic)[-1]["extra_damage"]["type"], "bludgeoning", "vicious: extra damage of the weapon's own type")
	var belt := Items.make_magic("belt-of-giant-strength", 3)
	t.eq(Items.mods(belt), [{"set_ability": {"str": 25}}], "belt tier picks the giant (fire: 25)")
	var heal := Items.make_magic("potions-of-healing", 1)
	t.eq(Items.use_of(heal), {"heal": "4d4+4"}, "greater healing heals 4d4+4")
	# tags
	var mole := {"base": "longsword", "count": 1, "material": "adamantine", "quality": "masterwork", "affixes": ["mole"]}
	t.check(is_equal_approx(float(Items.tags(mole)["dig_speed"]), 0.5 + 0.1 + 0.2), "dig_speed adds up from material, quality and affix")
	# ItemEffects accepts every composed mods list
	var srd := WorldHost.shared_srd()
	var cmb := srd.make_character("t", "fighter", 5, [16, 12, 14, 10, 10, 8], "longsword", "chain-mail", true)
	var before := cmb.attack_modifier()
	ItemEffects.apply(cmb, Items.mods(plus) + Items.mods(fire))
	t.eq(cmb.attack_modifier(), before + 2, "ItemEffects: +2 weapon adds 2 to the attack")
	t.eq(cmb.hit_riders.size(), 1, "and the affix rider")

func _budget(t: TestLog) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var worst := Vector2i.ZERO
	var over := 0
	var forbidden := 0
	var n := 4000
	for i in n:
		var rank: String = ItemGen.RANKS[i % ItemGen.RANKS.size()]
		var it := ItemGen.roll(rng, "", 1 + (i * 37) % 100, rank)
		var b := Items.budget_of(it)
		worst = Vector2i(maxi(worst.x, b.x), maxi(worst.y, b.y))
		if b.x > Items.BUDGET or b.y > Items.BUDGET:
			over += 1
		for a: Variant in it.get("affixes", []):
			for k: String in Items.affix_row(String(a)).get("mods", {}):
				if k in Items.FORBIDDEN_AFFIX_MODS:
					forbidden += 1
		if (it.get("affixes", []) as Array).size() > 3:
			over += 1
	t.eq(over, 0, "%d generated items: none over +3 to hit or AC, none with more than 3 affixes" % n)
	t.eq(forbidden, 0, "no affix touches attack, AC, saves or DCs")
	t.check(worst.x == 3 or worst.y == 3, "the budget is reached sometimes (%s)" % worst)
	# The cap holds even for a record built past it by hand.
	var silly := {"base": "longsword", "count": 1, "material": "adamantine", "magic": "weapon-1-2-or-3", "tier": 2}
	t.eq(Items.budget_of(silly), Vector2i(3, 0), "adamantine +3 longsword is trimmed to +3")
	var silly2 := {"base": "plate-armor", "count": 1, "material": "adamantine", "quality": "masterwork", "magic": "armor-1-2-or-3", "tier": 2}
	t.eq(Items.budget_of(silly2).y, 3, "+3 adamantine masterwork plate stays at +3 AC")

func _affixes(t: TestLog) -> void:
	var all := Items.affixes()
	t.check(all.size() >= 30, "at least 30 affixes (%d)" % all.size())
	var bad := 0
	for id: String in all:
		for tier: Dictionary in all[id]["tiers"]:
			for k: String in tier.get("mods", {}):
				if k in Items.FORBIDDEN_AFFIX_MODS:
					bad += 1
	t.eq(bad, 0, "affix data never carries to-hit, AC, save or DC mods")

func _names(t: TestLog) -> void:
	t.eq(ItemGen.name({"base": "longsword", "count": 1, "material": "iron", "quality": "fine", "affixes": ["embers"]}),
			"Fine Iron Longsword of Embers", "ordinary gear name")
	t.eq(ItemGen.name({"base": "longsword", "count": 1, "material": "iron", "quality": "common", "affixes": ["gleaming", "rime"],
			"magic": "weapon-1-2-or-3", "tier": 0}), "Gleaming Iron Longsword of Rime +1", "prefix, suffix and +N")
	t.eq(ItemGen.name(Items.make_magic("ring-of-protection")), "Ring of Protection", "SRD magic item name")
	t.eq(ItemGen.name(Items.make_magic("potions-of-healing", 2)), "Potion of Superior Healing", "potion tier")
	t.eq(ItemGen.name(Items.make_magic("flame-tongue", 0, "scimitar")), "Flame Tongue (Scimitar)", "magic weapon names its base")
	t.eq(ItemGen.name(Items.spark_item("skyhook", 2)), "Spark of Skyhook III", "spark name")
	t.eq(ItemGen.name(Items.make("tile:copper_ore")), "Copper Ore", "tile name")
	t.eq(ItemGen.name(Items.make_magic("wand-of-the-war-mage-1-2-or-3", 1)), "Wand of the War Mage +2", "wand +N")

func _gen_deterministic(t: TestLog) -> void:
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 99
	b.seed = 99
	var same := true
	for i in 200:
		same = same and ItemGen.roll(a, "", 40, "elite") == ItemGen.roll(b, "", 40, "elite")
	t.check(same, "ItemGen.roll is deterministic by seed")
	var r := RandomNumberGenerator.new()
	r.seed = 7
	var mats := {}
	for i in 300:
		var it := ItemGen.roll(r, "longsword", 2, "standard")
		mats[it.get("material", "")] = true
	t.check(not mats.has("mithral") and not mats.has("adamantine"), "level 2: no mithral or adamantine")
	var club := ItemGen.roll(r, "club", 90, "boss")
	t.check(not club.has("material"), "a club takes no metal")

func _coverage(t: TestLog) -> void:
	var works := 0
	var partial := 0
	var inert := 0
	for s: String in Items.magic_slugs():
		match String(Items.magic_entry(s).get("status", "inert")):
			"works": works += 1
			"partial": partial += 1
			_: inert += 1
	print("  magic items: %d works, %d partial, %d inert (text only)" % [works, partial, inert])
	t.check(works + partial >= 80, "at least 80 magic items have working mods (%d)" % (works + partial))
	# Every authored mods dict is accepted by ItemEffects.
	var srd := WorldHost.shared_srd()
	var c := srd.make_character("t", "wizard", 3, [8, 14, 14, 16, 12, 10], "", "", false)
	var all: Array = []
	for s: String in Items.magic_slugs():
		var e := Items.magic_entry(s)
		var tiers: Array = e.get("tiers", [{}])
		for i in maxi(1, tiers.size()):
			all.append_array(Items.mods(Items.make_magic(s, i)))
	ItemEffects.apply(c, all)
	t.check(c.stats.max_hp > 0, "ItemEffects takes every magic item's mods")
	# every worn magic item has a slot an Equipment accepts
	var eq := Equipment.new()
	var bad := 0
	for s: String in Items.magic_slugs():
		var it := Items.make_magic(s)
		var k := Items.slot_kind(it)
		if k == "":
			continue
		var slot := "ring_1" if k == "ring" else k
		if eq.can_equip(it, slot) != "":
			bad += 1
	t.eq(bad, 0, "every wearable magic item fits its slot")
