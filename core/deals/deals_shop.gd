## Shops and smiths from the sim: what a settlement's store has on its shelves (its sim stocks
## at its sim prices) and what its smith has on the rack (ItemGen pieces whose kinds come
## from the culture, quality from tier and wealth, material and number from ore and tools),
## and what it pays for things. Pure functions: racks come from a hash of (world seed, site,
## day); nothing here changes the sim (DealsSystem moves the goods through
## WorldSim.player_trade).
##
##   DealsShop.shelves(sim, sid) -> [{id, item, n, each, good, units}]
##   DealsShop.rack(sim, seed, sid, day, sold) -> [{id, item, n, each, good, units}]
##   DealsShop.buy_mult(mods) / sell_mult(mods)   mods: {standing, bond, price_mult, patron}
##   DealsShop.sell_each(sim, sid, item) -> int     before mods; 0 = they will not buy it
class_name DealsShop
extends RefCounted

static func _p() -> Dictionary:
	return Deals.prices()

## A store sells here: a market or store building (or, in a world without places, a merchant).
static func has_store(world: TileWorld, sid: int) -> bool:
	if Places.place(world, sid).is_empty():
		return true
	return not Places.buildings(world, sid, "market").is_empty() or not Places.buildings(world, sid, "store").is_empty()

static func has_smithy(world: TileWorld, sid: int) -> bool:
	return Places.place(world, sid).is_empty() or not Places.buildings(world, sid, "smithy").is_empty()

static func has_building(world: TileWorld, sid: int, kind: String) -> bool:
	return Places.place(world, sid).is_empty() or not Places.buildings(world, sid, kind).is_empty()

## The good's local price over its base price.
static func good_factor(s: SimSettlement, good: String) -> float:
	return SimEconomy.price(s, good) / float(SimData.goods[good]["base"])

# --- the store ---------------------------------------------------------------------------

## The store's shelves: each row the tier carries, as many as the stock spares (what is above
## `keep` of the town's own target), priced from the good's local price.
static func shelves(sim: WorldSim, sid: int) -> Array:
	var s: SimSettlement = sim.settlements.get(sid)
	var out: Array = []
	if s == null:
		return out
	var P := _p()
	var rows: Array = P["shelves"]
	for i in rows.size():
		var row: Dictionary = rows[i]
		if not s.tier in (row.get("tiers", []) as Array):
			continue
		var good := String(row["good"])
		var units := float(row.get("units", 1.0))
		var spare := float(s.stock.get(good, 0.0)) - float(P["keep"]) * SimEconomy.target(s, good)
		var n := mini(int(row.get("max", 99)), floori(maxf(0.0, spare) / units))
		var item := Items.make_magic(String(row["base"]), 0) if bool(row.get("magic", false)) else Items.make(String(row["base"]))
		item["count"] = 1
		var each: float
		if String(row["base"]).begins_with("trade:"):
			each = SimEconomy.price(s, good) * units
		else:
			each = float(row.get("value", Items.value(item))) * good_factor(s, good)
		out.append({"id": "s%d" % i, "item": item, "n": n, "each": maxi(1, ceili(each * float(P["buy_markup"]))),
			"good": good, "units": units})
	return out

# --- the smith ---------------------------------------------------------------------------

## The smith's rack for a game day: pieces of `rank` quality made with ItemGen from the
## culture's kinds; `sold` ({piece index: true}) are gone for the day.
static func rack(sim: WorldSim, world_seed: int, sid: int, day: int, sold: Dictionary) -> Array:
	var out: Array = []
	var s: SimSettlement = sim.settlements.get(sid)
	if s == null:
		return out
	var P := _p()
	var S: Dictionary = P["smith"]
	var ore := float(s.stock.get("ore", 0.0))
	var opp := float(S["ore_per_piece"])
	var ore_f := clampf(ore / maxf(1.0, SimEconomy.target(s, "ore")), 0.25, 1.25)
	var tools_f := clampf(float(s.stock.get("tools", 0.0)) / maxf(1.0, SimEconomy.target(s, "tools")), 0.5, 1.1)
	var pieces := roundi(float(S["pieces"].get(s.tier, 2)) * ore_f * tools_f)
	var scrap := ore < opp
	pieces = 1 if scrap else clampi(pieces, 1, floori(ore / opp))
	var price_f := clampf(good_factor(s, "ore"), 0.75, 1.5)
	for k in pieces:
		if sold.has(k) or sold.has(str(k)):
			continue
		var item := piece(sim, world_seed, sid, day, k, 0, scrap)
		out.append({"id": "r%d" % k, "item": item, "n": 1, "each": maxi(1, ceili(Items.value(item) * price_f * float(P["buy_markup"]))),
			"good": "" if scrap else "ore", "units": 0.0 if scrap else opp})
	return out

## One piece of the rack (k), or a made-to-order piece: `up` quality steps above what the rack
## would roll, `level` for affixes (0: by tier), `base` to make ("": from the culture's kinds).
static func piece(sim: WorldSim, world_seed: int, sid: int, day: int, k: int, up := 0, scrap := false, base := "", level := 0) -> Dictionary:
	var s: SimSettlement = sim.settlements[sid]
	var S: Dictionary = _p()["smith"]
	var r := Deals.rng([world_seed, "rack", sid, day, k, up, base])
	if base == "":
		var kinds: Dictionary = S["kinds"].get(s.culture, S["kinds"]["_"])
		base = Deals.weighted(r, kinds)
	var lv := level if level > 0 else int(S["level"].get(s.tier, 5))
	var item := ItemGen.roll(r, base, lv, "standard")
	item.erase("magic")
	item.erase("tier")
	# quality: by tier, a step up for a rich town and down for a poor one, plus `up`
	var order := Items.quality_order()
	var q := Deals.weighted(r, S["quality"].get(s.tier, {"common": 1}))
	var qi := order.find(q)
	var per := s.wealth / maxf(1.0, float(s.pop()))
	if per >= float(S["rich"]):
		qi += 1
	elif per < float(S["poor"]):
		qi -= 1
	qi = clampi(qi + up, 0, order.size() - 1)
	if scrap:
		qi = 0
	item["quality"] = order[qi]
	if Items.takes_material(base):
		var mats: Dictionary = (S["materials"].get(s.tier, {"iron": 1}) as Dictionary).duplicate()
		if float(s.stock.get("ore", 0.0)) < float(S["silver_ore"]):
			mats.erase("silver")
		if not s.culture in (S["mithral_cultures"] as Array):
			mats.erase("mithral")
		if up > 0 and qi >= order.size() - 1 and s.culture in (S["mithral_cultures"] as Array) and s.tier == "city":
			mats["mithral"] = float(mats.get("mithral", 0.0)) + 20.0
		item["material"] = Deals.weighted(r, mats) if not mats.is_empty() else "iron"
		if scrap:
			item["material"] = "copper"
	else:
		item.erase("material")
	var affs: Array = item.get("affixes", [])
	var keep := 0 if qi <= 1 else (1 if qi == 2 else 2)
	if affs.size() > keep:
		affs = affs.slice(0, keep)
	if affs.is_empty():
		item.erase("affixes")
	else:
		item["affixes"] = affs
	return item

## The best quality index on the rack today (-1 when empty).
static func best_quality(list: Array) -> int:
	var best := -1
	for l: Dictionary in list:
		best = maxi(best, Items.quality_order().find(String(l["item"].get("quality", "common"))))
	return best

# --- prices --------------------------------------------------------------------------------

## The multiplier on what a player pays: standing with the faction, a Bond with the people,
## the Silver Tongue spark (tag price_mult) and patron tiers (data/deals/prices.json).
static func buy_mult(mods: Dictionary) -> float:
	var P := _p()
	var m := 1.0 - float(mods.get("standing", 0)) * float(P["standing_per_point"])
	m *= 1.0 - (float(P["bond"]) if int(mods.get("bond", 0)) >= 1 else 0.0)
	m *= 1.0 - clampf(float(mods.get("price_mult", 0.0)), 0.0, 0.5)
	m *= 1.0 - float(mods.get("patron", 0)) * float(P["patron_tier"])
	return maxf(m, float(P["buy_floor"]))

static func sell_mult(mods: Dictionary) -> float:
	var P := _p()
	var m := 1.0 + float(mods.get("standing", 0)) * float(P["standing_per_point"])
	m *= 1.0 + (float(P["bond"]) if int(mods.get("bond", 0)) >= 1 else 0.0)
	m *= 1.0 + clampf(float(mods.get("price_mult", 0.0)), 0.0, 0.5)
	m *= 1.0 + float(mods.get("patron", 0)) * float(P["patron_tier"])
	return minf(m, float(P["sell_ceiling"]))

static func price(each: int, mult: float) -> int:
	return maxi(1, roundi(each * mult))

## The sim good an item is (trade goods and ore), and how many units of it one item is.
static func good_of(item: Dictionary) -> Array:
	var row := Items.row(String(item.get("base", "")))
	if row.has("good") and not item.has("magic"):
		return [String(row["good"]), float(row.get("units", 1.0))]
	return ["", 0.0]

## What the town pays for one (before mods): trade goods and ore at the local price, gear and
## magic at a fraction of their value, other things less; 0 for the worthless (rubble) and
## for coin and sparks.
## The store's shelf row for camp gear (rope, torches, campfires: tile items sold on the
## shelves), {} for anything else. Shops buy these back at sell_camp of their list value.
static func camp_row(item: Dictionary) -> Dictionary:
	if Items.kind(item) != "tile":
		return {}
	for row: Dictionary in _p()["shelves"]:
		if String(row["base"]) == String(item.get("base", "")):
			return row
	return {}

static func sell_each(sim: WorldSim, sid: int, item: Dictionary) -> float:
	var s: SimSettlement = sim.settlements.get(sid)
	if s == null or item.is_empty():
		return 0.0
	var P := _p()
	var k := Items.kind(item)
	var camp := camp_row(item)
	if not camp.is_empty():
		return float(camp.get("value", Items.value(item))) * good_factor(s, String(camp["good"])) * float(P["sell_camp"])
	if k in ["coin", "spark", "tile"] or item.has("spark"):
		return 0.0
	var g := good_of(item)
	if String(g[0]) != "":
		return SimEconomy.price(s, String(g[0])) * float(g[1]) * float(P["sell_trade"])
	var v := float(Items.value(item))
	if v <= 0.0:
		return 0.0
	if k in ["weapon", "armor", "shield"] or item.has("magic"):
		return v * float(P["sell_gear"])
	return v * float(P["sell_other"])
