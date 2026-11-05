## A settled site: people in cohorts, stockpiles, coin, soldiers. Plain state; the rules
## that move it live in SimEconomy and SimConflict.
class_name SimSettlement
extends RefCounted

const TIERS := ["hamlet", "village", "town", "city"]
const TIER_POP := [0, 150, 600, 2000]

var id := 0                 # site id
var name := ""
var culture := ""
var faction := 0
var workers := 0            # adults who farm, cut, mine and craft
var dependants := 0         # children and elders
var soldiers := 0           # the garrison (composition: garrison())
var stock := {}             # good -> float
var wealth := 0.0
var morale := 0.7           # 0..1
var weather := 1.0          # this year's harvest factor
var tier := "hamlet"
var founded := 0            # hour
var hungry := 0             # econ ticks in a row with unmet food needs
var out_caravans := 0
var out_raids := 0
var out_other := 0          # patrols, armies, settlers, expeditions away
var tribute_to := -1        # faction paid each year, or -1
var tribute_until := 0
var besieged_by := -1       # party id of a besieging army, or -1
var last_raided := -1000000
var grievance := {}         # lair id (int) -> harm suffered from it
var shock := {}             # an open food-shock record, see SimEconomy
var price_ref := 1.0        # slow average of the food price in ordinary times
var cooldowns := {}         # decision kind -> hour it may happen again
# Derived from the site, not saved.
var cap := {}               # food/timber/ore capacity per day
var seasonal := true
var band := "surface"
var x := 0.0

func pop() -> int:
	return workers + dependants + soldiers

static func tier_for(p: int) -> String:
	var t := "hamlet"
	for i in TIERS.size():
		if p >= TIER_POP[i]:
			t = TIERS[i]
	return t

## The garrison as SRD stat blocks.
func garrison() -> Dictionary:
	return SimData.allocate(SimData.culture(culture).guards, soldiers)

func to_dict() -> Dictionary:
	var g := {}
	for k in grievance:
		g[str(k)] = grievance[k]
	return {
		"id": id, "name": name, "culture": culture, "faction": faction,
		"workers": workers, "dependants": dependants, "soldiers": soldiers,
		"stock": stock.duplicate(), "wealth": wealth, "morale": morale, "weather": weather,
		"tier": tier, "founded": founded, "hungry": hungry,
		"out_caravans": out_caravans, "out_raids": out_raids, "out_other": out_other,
		"tribute_to": tribute_to, "tribute_until": tribute_until, "besieged_by": besieged_by,
		"last_raided": last_raided, "grievance": g, "shock": shock.duplicate(true),
		"price_ref": price_ref, "cooldowns": cooldowns.duplicate(),
	}

static func from_dict(d: Dictionary) -> SimSettlement:
	var s := SimSettlement.new()
	s.id = int(d.id); s.name = d.name; s.culture = d.culture; s.faction = int(d.faction)
	s.workers = int(d.workers); s.dependants = int(d.dependants); s.soldiers = int(d.soldiers)
	for k in d.stock:
		s.stock[k] = float(d.stock[k])
	s.wealth = float(d.wealth); s.morale = float(d.morale); s.weather = float(d.weather)
	s.tier = d.tier; s.founded = int(d.founded); s.hungry = int(d.hungry)
	s.out_caravans = int(d.out_caravans); s.out_raids = int(d.out_raids); s.out_other = int(d.out_other)
	s.tribute_to = int(d.tribute_to); s.tribute_until = int(d.tribute_until)
	s.besieged_by = int(d.besieged_by); s.last_raided = int(d.last_raided)
	for k in d.grievance:
		s.grievance[int(k)] = float(d.grievance[k])
	s.price_ref = float(d.price_ref)
	for k in d.cooldowns:
		s.cooldowns[k] = int(d.cooldowns[k])
	if not (d.shock as Dictionary).is_empty():
		var sh: Dictionary = d.shock
		s.shock = {"t": int(sh.t), "price0": float(sh.price0), "maxp": float(sh.maxp),
			"imports": int(sh.imports), "migrants": int(sh.migrants), "raids": int(sh.raids)}
	return s
