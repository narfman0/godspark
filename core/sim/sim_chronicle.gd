## Readable lines for chronicle events. Events carry the names they need, so a line can be
## written long after the places in it are gone.
class_name SimChronicle
extends RefCounted

const KIND_NOUN := {"caravan": "a caravan", "migrants": "a column of migrants", "settlers": "a band of settlers",
	"army": "an army", "expedition": "an expedition", "patrol": "a patrol", "raid": "a raiding party"}

## Events worth showing in a digest, most important first.
const WEIGHT := {"faction_fell": 10, "conquered": 9, "sacked": 9, "abandoned": 8, "war": 8, "peace": 7,
	"founded": 7, "outlaws": 6, "tribute": 6, "apex_wrath": 6, "lair_cleared": 6, "famine": 5, "siege": 5,
	"siege_broken": 5, "bad_harvest": 5, "raid": 4, "monster_raid": 4, "tier_up": 4, "tier_down": 4,
	"expedition_failed": 4, "apex_tribute": 3, "trade_opened": 3, "ambush": 3, "lair_new": 3,
	"migrants": 2, "army": 2, "siege_lifted": 2, "patrol_clash": 2, "lair_attack": 1, "lair_empty": 1, "lair_cleared_players": 6,
	"slain_by_players": 3}

static func stamp(t: int) -> String:
	var y := t / WorldSim.YEAR_H + 1
	var season: String = WorldSim.SEASONS[(t % WorldSim.YEAR_H) / WorldSim.SEASON_H]
	return "Year %d, %s" % [y, season]

static func describe(e: Dictionary) -> String:
	return "%s: %s" % [stamp(int(e.t)), line(e)]

static func _n(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if n == 1 else many]

static func _loot(e: Dictionary) -> String:
	var bits: Array = []
	if int(e.get("food", 0)) > 0: bits.append("%d food" % int(e.food))
	if int(e.get("goods", 0)) > 0: bits.append("%d goods" % int(e.goods))
	if int(e.get("coin", 0)) > 0: bits.append("%d coin" % int(e.coin))
	if int(e.get("captives", 0)) > 0: bits.append(_n(int(e.captives), "captive", "captives"))
	return " and ".join(bits) if bits.size() <= 2 else ", ".join(bits.slice(0, bits.size() - 1)) + " and " + bits[-1]

static func line(e: Dictionary) -> String:
	match str(e.kind):
		"bad_harvest":
			return "%s ruins the harvest around %s (yield %d%%)" % [
				"rot in the fungus beds" if e.deep else "blight", e.places, int(e.pct)]
		"famine":
			return "famine in %s; food costs %d%% of its usual price" % [e.site, int(e.price_pct)]
		"tier_up":
			return "%s has grown into a %s (%d souls)" % [e.site, e.tier, int(e.pop)]
		"tier_down":
			return "%s has dwindled to a %s (%d souls)" % [e.site, e.tier, int(e.pop)]
		"abandoned":
			var why: String = {"dwindled": "is abandoned", "raided": "is abandoned after the raids",
				"sacked": "is left a burnt ruin", "burned": "burns and is abandoned"}.get(str(e.why), "is abandoned")
			return "%s %s; %s walk away (founded year %d)" % [e.site, why, _n(int(e.left), "survivor", "survivors"), int(e.founded_year)]
		"migrants":
			return "%s %s leave %s for %s" % [_n(int(e.n), "migrant", "migrants"),
				"fleeing hunger" if e.why == "hunger" else "losing hope", e.from, e.to]
		"trade_opened":
			return "first caravan from %s (%s) reaches %s (%s) with %s" % [e.from, e.a, e.to, e.b, e.good]
		"founded":
			return "settlers from %s found %s%s (%d souls)" % [e.from, e.site, " in old ruins" if e.ruin else "", int(e.n)]
		"lair_new":
			return "a %s settles at %s, now called %s" % [e.what, e.site, e.lair]
		"slain_by_players":
			return "%s killed %s of %s" % [e.by, e.who, e.site]
		"lair_cleared_players":
			return "%s cleared the %s at %s" % [str(e.get("by", "adventurers")), e.what, e.lair]
		"lair_empty":
			return "the %s at %s has died out" % [e.what, e.lair]
		"ambush":
			var who := "%s raiders from %s" % [e.raiders, e.rfrom]
			var victim: String = KIND_NOUN.get(str(e.victim), "travellers") + " from " + str(e.vfrom)
			var s := "%s ambushed %s on %s" % [who, victim, e.route]
			if e.motive == "hunger":
				s = "hungry " + s
			if e.patrol:
				s += " (a patrol stood with them)"
			if e.won:
				s += "; %s killed" % _n(int(e.killed), "defender", "defenders")
				var loot := _loot(e)
				if loot != "":
					s += ", %s taken" % loot
			else:
				s += " and were driven off; %s dead, %s lost" % [_n(int(e.killed), "defender", "defenders"), _n(int(e.lost), "raider", "raiders")]
			return s
		"patrol_clash":
			return "a patrol from %s caught %s raiders (%s) lying in wait on %s and %s; %d raiders and %d of the patrol fell" % [
				e.pfrom, e.raiders, e.rfaction, e.route, "routed them" if e.won else "was beaten back", int(e.rlost), int(e.plost)]
		"lair_attack":
			var s := "the %s of %s fell on %s from %s on %s" % [e.what, e.lair, KIND_NOUN.get(str(e.victim), "travellers"), e.vfrom, e.route]
			if e.won:
				s += "; %s killed" % _n(int(e.killed), "traveller", "travellers")
				if int(e.food) > 0:
					s += ", %d food devoured" % int(e.food)
			else:
				s += " and were beaten off (%d killed, %d monsters slain)" % [int(e.killed), int(e.slain)]
			return s
		"monster_raid":
			if e.won:
				return "the %s of %s attacked %s: %s killed, %d food devoured" % [e.what, e.lair, e.site, _n(int(e.killed), "person", "people"), int(e.food)]
			return "the %s of %s attacked %s and were repulsed (%d monsters slain, %d defenders lost)" % [e.what, e.lair, e.site, int(e.slain), int(e.killed)]
		"lair_cleared":
			return "an expedition from %s cleared the %s at %s (%d monsters slain, %d lost, %d coin of hoard)" % [
				e.from, e.what, e.lair, int(e.slain), int(e.lost), int(e.hoard)]
		"expedition_failed":
			return "an expedition from %s against the %s at %s failed; %d lost" % [e.from, e.what, e.lair, int(e.lost)]
		"raid":
			var s := "%s%s raiders from %s (%s) attacked %s" % ["hungry " if e.motive == "hunger" else "", e.raiders, e.rfrom, e.rfaction, e.site]
			if e.won:
				s += "; %s killed" % _n(int(e.killed), "defender", "defenders")
				var loot := _loot(e)
				if loot != "":
					s += ", %s carried off" % loot
			else:
				s += " and were thrown back (%d raiders and %d defenders dead)" % [int(e.lost), int(e.killed)]
			return s
		"war":
			return "%s declared war on %s" % [e.a, e.b]
		"peace":
			return "%s and %s made peace after %s (%d dead)" % [e.a, e.b, _n(int(e.years), "year", "years") if int(e.years) > 0 else "a few months", int(e.losses)]
		"army":
			return "%s marched %s from %s against %s" % [e.army, _n(int(e.n), "soldier", "soldiers"), e.from, e.site]
		"siege":
			return "%s laid siege to %s (%s)" % [e.army, e.site, e.dfaction]
		"siege_lifted":
			return "%s gave up the siege of %s" % [e.army, e.site]
		"siege_broken":
			return "%s stormed %s and was thrown back (%d attackers, %d defenders dead)" % [e.army, e.site, int(e.lost), int(e.killed)]
		"conquered":
			return "%s took %s from %s (%d defenders, %d attackers dead)" % [e.army, e.site, e.old, int(e.killed), int(e.lost)]
		"sacked":
			var s := "%s sacked %s: %s killed, %d coin taken" % [e.army, e.site, _n(int(e.killed), "person", "people"), int(e.coin)]
			if int(e.captives) > 0:
				s += ", %s led away" % _n(int(e.captives), "captive", "captives")
			return s
		"tribute":
			return "%s broke the walls of %s and made it pay tribute" % [e.army, e.site]
		"outlaws":
			var why: String = {"hunger": "driven by hunger", "tribute": "sick of paying tribute", "misery": "with nothing left to lose"}.get(str(e.why), "")
			return "%d folk of %s, %s, take to the wilds and make an outlaw camp at %s (%s)" % [int(e.n), e.from, why, e.site, e.faction]
		"faction_fell":
			return "%s is no more" % e.faction
		"apex_tribute":
			return "the %s of %s demanded tribute; %s paid %d coin" % [e.what, e.lair, e.site, int(e.coin)]
		"apex_wrath":
			return "the %s of %s fell on %s, which could not pay: %s killed, %d food burned" % [e.what, e.lair, e.site, _n(int(e.killed), "person", "people"), int(e.food)]
	return "%s %s" % [e.kind, str(e)]
