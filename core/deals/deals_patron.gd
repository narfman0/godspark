## Patronage: at rising standing with a faction (data/deals/prices.json `patron.tiers`) its
## hall or temple takes a player on. Each tier brings a gift once (a made-to-order piece of
## gear from the town's smith, a quality step above its rack; then SRD magic items by rarity),
## better prices and a free bed; from `work_tier`, harder work. Falling below the first tier
## suspends it. Pure functions; DealsSystem records what was given.
##
##   DealsPatron.tier(standing) -> int
##   DealsPatron.gift(sim, seed, sid, faction, tier, player_name, level, wielded) -> {item, why}
class_name DealsPatron
extends RefCounted

static func cfg() -> Dictionary:
	return Deals.prices()["patron"]

static func tier(standing: int) -> int:
	var n := 0
	for th: Variant in cfg()["tiers"]:
		if standing >= int(th):
			n += 1
	return n

static func is_patron_role(role: String) -> bool:
	return (cfg()["roles"] as Dictionary).has(role)

## The gift for reaching tier `t` (1-based) with a faction, given at settlement sid.
## wielded: the player's main-hand item (the piece follows its kind), level: the player's.
static func gift(sim: WorldSim, world_seed: int, sid: int, faction: String, t: int, player_name: String, level: int, wielded: Dictionary) -> Dictionary:
	var gifts: Array = cfg()["gift"]
	var g: Dictionary = gifts[clampi(t - 1, 0, gifts.size() - 1)]
	var s: SimSettlement = sim.settlements.get(sid)
	var town := s.name if s != null else "the town"
	var fname := sim.faction_name(int(faction)) if faction.is_valid_int() else faction
	if String(g["kind"]) == "gear" and s != null:
		var base := String(wielded.get("base", ""))
		if base == "" or not Items.row(base).get("kind", "") in ["weapon", "armor", "shield"]:
			base = ""
		var day := Deals.day(sim)
		var rack := DealsShop.rack(sim, world_seed, sid, day, {})
		var best := DealsShop.best_quality(rack)
		var item := DealsShop.piece(sim, world_seed, sid, day, 1000 + Deals.h([player_name, faction, t]) % 1000, 1, false, base,
			clampi(level, 1, 100))
		var order := Items.quality_order()
		if order.find(String(item.get("quality", "common"))) <= best:
			item["quality"] = order[mini(best + 1, order.size() - 1)]
		return {"item": item, "why": "Made to order by the smith of %s, for a friend of %s." % [town, fname]}
	var pool: Array = cfg()["pools"].get(String(g.get("rarity", "uncommon")), [])
	var slug := String(Deals.pick(pool, [world_seed, "patron", faction, t, player_name]))
	var item := Items.make_magic(slug, 0)
	if item.is_empty():
		item = Items.make_magic("potions-of-healing", 1)
	var what := "%s rarity" % String(g.get("rarity", ""))
	return {"item": item, "why": "From the treasury of %s, %s: %s, for standing by them." % [fname, what, Items.magic_entry(slug).get("name", slug)]}
