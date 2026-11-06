## Pure decisions and words behind the living-world screens (dialogue, shop, quest log,
## standing, banners, plates), kept apart so tests can check them without a window. Inputs are
## the client mirrors' plain dictionaries (DealsClient, LifeClient); nothing here sends.
class_name DealsLogic
extends RefCounted

## Patron tiers (data/deals/prices.json `patron`; DealsPatron) and Life's standing bands.
const TIERS := [25, 50, 75]
const HOSTILE_AT := -40
const FRIENDLY_AT := 30
const ROLE_WORDS := {"keeper": "innkeeper", "townsfolk": "townsfolk", "smith": "smith", "merchant": "merchant",
	"priest": "priest", "guard": "guard", "escort": "caravan guard", "drover": "drover", "raider": "raider", "wagon": "wagon"}
const STATE_WORDS := {
	"besieged": ["Besieged", "An army sits outside the gate."],
	"raided": ["Lately raided", "Doors are mended and tempers are short."],
	"war": ["At war", "The talk is all of the war."],
	"hungry": ["Hungry", "Bread is dear and the children are thin."],
	"caravan_due": ["Expecting a caravan", "Eyes on the road: a caravan is due."],
	"prosperous": ["Prosperous", "Fat purses and fresh paint."],
	"quiet": ["Quiet", "Nothing much happens, and everyone likes it that way."],
}
const TIER_WORDS := {"hamlet": "hamlet", "village": "village", "town": "town", "city": "city"}

# --- people ---------------------------------------------------------------------------------

static func role_word(role: String) -> String:
	return String(ROLE_WORDS.get(role, role))

## The mark over a person who talks: "turn_in" (work of yours to hand in here), "work" (work on
## offer today), "patron", "shop", "smith", or "". `quests` the player's log, `atlas_site` the
## ATLAS site, `patrons` DealsClient.patrons.
static func role_mark(person: Dictionary, quests: Array, atlas_site: Dictionary, patrons: Dictionary) -> String:
	if not bool(person.get("talk", false)) or String(person.get("kind", "")) != "settlement":
		return ""
	var role := String(person.get("role", ""))
	var sid := int(person.get("of", -1))
	for q: Dictionary in quests:
		if int(q.get("site", -2)) == sid and String(q.get("giver", "keeper")) == role and String(q.get("state", "")) == "ready":
			return "turn_in"
		if int(q.get("site", -2)) == sid and String(q.get("giver", "keeper")) == role and String(q.get("state", "")) == "active" \
				and String(q.get("kind", "")) in ["recover", "relief"]:
			return "turn_in"
	if role in (atlas_site.get("work", []) as Array):
		return "work"
	if role in ["keeper", "priest"]:
		var p: Dictionary = patrons.get(String(person.get("faction", "")), {})
		if int(p.get("tier", 0)) >= 1 and not bool(p.get("suspended", false)):
			return "patron"
	if role == "merchant":
		return "shop"
	if role == "smith":
		return "smith"
	return ""

## "Dunton the Merchant", or "Ada, smith" (the role once).
static func person_label(person: Dictionary) -> String:
	var nm := String(person.get("name", ""))
	var r := role_word(String(person.get("role", "")))
	if nm == "":
		return r.capitalize()
	return nm if nm.to_lower().contains(r.to_lower()) else "%s, %s" % [nm, r]

## First letter up, the rest as it is.
static func cap(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1)

## A chronicle line split into its date and its news: ["Year 1, spring", "first caravan ..."]
## (the news capitalised); no date: ["", text].
static func rumour_parts(text: String) -> Array:
	var i := text.find(": ")
	if text.begins_with("Year ") and i > 0 and i < 30:
		var rest := text.substr(i + 2)
		return [text.substr(0, i), rest.substr(0, 1).to_upper() + rest.substr(1)]
	return ["", text]

## How long ago a rumour's event was: "today", "yesterday", "5 days ago".
static func ago(t: int, now_h: float) -> String:
	var days := floori((now_h - t) / WorldSim.DAY_H)
	if days <= 0:
		return "today"
	return "yesterday" if days == 1 else "%d days ago" % days

## The toast for rumours just heard: "Heard 2 new things." or, when none is news in the world,
## "Heard 2 old stories."
static func heard_text(list: Array, now_h: float) -> String:
	if list.is_empty():
		return ""
	var n := list.filter(func(r: Dictionary) -> bool: return DealsTalk.is_news(float(r["t"]), now_h)).size()
	if n > 0:
		return "Heard %d new thing%s." % [n, "" if n == 1 else "s"]
	return "Heard %d old stor%s." % [list.size(), "y" if list.size() == 1 else "ies"]

## The context prompt over the nearest person: "E: talk to Dunton, merchant".
static func talk_prompt(person: Dictionary) -> String:
	var nm := String(person.get("name", ""))
	var r := role_word(String(person.get("role", "")))
	if nm != "" and nm.to_lower().contains(r.to_lower()):
		return "E: talk to %s" % nm
	return "E: talk to %s, %s" % [nm, r] if nm != "" else "E: talk to the %s" % r

## A road party's plate: "Caravan of the Tarnby League, bound for Marstead".
static func party_plate(kind: String, faction_name: String, dest_name: String, home_name: String) -> String:
	var k: String = {"caravan": "Caravan", "raid": "Raiders", "army": "Army", "patrol": "Patrol", "settlers": "Settlers",
		"migrants": "Migrants", "expedition": "Expedition", "pack": "Hunting pack"}.get(kind, kind.capitalize())
	var s: String = k
	if faction_name != "":
		s += " of " + faction_name
	if kind in ["raid", "army", "pack"]:
		return s
	if dest_name != "":
		s += ", bound for " + dest_name
	elif home_name != "":
		s += ", out of " + home_name
	return s

# --- places -------------------------------------------------------------------------------------

## "a halfling town of 633 souls"
static func place_line(site: Dictionary) -> String:
	var c := String(site.get("culture", ""))
	var tier := String(TIER_WORDS.get(String(site.get("tier", "")), "settlement"))
	var pop := int(site.get("pop", 0))
	var a := "%s %s" % [c, tier] if c != "" else tier
	var art := "an" if a.substr(0, 1).to_lower() in ["a", "e", "i", "o", "u"] else "a"
	if pop > 0:
		return "%s %s of %d souls" % [art, a, pop]
	return "%s %s" % [art, a]

## The most pressing state and a line about it: ["Hungry", "Bread is dear ..."].
static func state_line(site: Dictionary) -> Array:
	var st: Array = site.get("state", [])
	var k := String(st[0]) if not st.is_empty() else "quiet"
	return STATE_WORDS.get(k, ["", ""])

# --- standing ---------------------------------------------------------------------------------

## Patron tier for a standing (0 none, 1-3).
static func tier_of(standing: int) -> int:
	var t := 0
	for i in TIERS.size():
		if standing >= int(TIERS[i]):
			t = i + 1
	return t

## A word for where a standing sits.
static func standing_word(v: int) -> String:
	if v <= HOSTILE_AT:
		return "Hated"
	if v < -10:
		return "Distrusted"
	if v < 10:
		return "A stranger"
	if v < int(TIERS[0]):
		return "Known"
	return ["Patron's friend", "Patron's friend", "Trusted of the patron", "Champion of the house"][tier_of(v)]

## How a faction's guards take you: friendly, wary or hostile (Life's stance by standing).
static func guards_word(v: int) -> String:
	if v <= HOSTILE_AT:
		return "hostile"
	if v >= FRIENDLY_AT:
		return "friendly"
	return "wary"

## Is a change worth a toast? Moves of 3 or more, or any change of band.
static func standing_toast(old: int, now: int) -> bool:
	return absi(now - old) >= 3 or tier_of(old) != tier_of(now) or guards_word(old) != guards_word(now)

## "Standing with the Tarnby League +10 (a raid wiped out)"
static func standing_text(faction_name: String, delta: int, why: String) -> String:
	var w := why.replace("_", " ")
	return "%s %s%d%s" % [cap(faction_name) if faction_name != "" else "A faction", "+" if delta >= 0 else "", delta, "  (%s)" % w if w != "" and w != "cheat" else ""]

# --- prices ---------------------------------------------------------------------------------------

## What modifies prices for this player with this faction, as a fraction of the buy price
## (negative: cheaper): standing, Bond and patron tiers (prices.json).
static func price_mods(standing: int, bonded: bool, patron_tier: int) -> Dictionary:
	return {"standing": -0.002 * standing, "bond": -0.05 if bonded else 0.0, "patron": -0.05 * patron_tier}

## A listing's price over what it would cost at the good's base price (1.0 = ordinary), with
## the player's modifiers taken out. -1 when there is nothing to compare with.
static func listing_ratio(l: Dictionary, mods: Dictionary) -> float:
	var it: Dictionary = l.get("item", {})
	var v := float(Items.value(it)) if not it.is_empty() else 0.0
	if v * 1.25 < 6.0:
		return -1.0       # a coin or two: rounding says more than the market does
	var m := 1.0 + float(mods.get("standing", 0.0)) + float(mods.get("bond", 0.0)) + float(mods.get("patron", 0.0))
	m = clampf(m, 0.6, 2.0)
	return float(l.get("price", 0)) / (v * 1.25 * m)

## The line under a shop's goods that says why prices are what they are.
static func price_mood(listings: Array, mods: Dictionary, kind := "store") -> String:
	var cheap: Array = []
	var dear: Array = []
	for l: Dictionary in listings:
		var r := listing_ratio(l, mods)
		if r < 0.0:
			continue
		var nm := ItemGen.name(l["item"]).to_lower()
		if r <= 0.8:
			cheap.append(nm)
		elif r >= 1.3:
			dear.append(nm)
	var parts: Array = []
	if kind == "smith":
		if listings.is_empty():
			parts.append("The rack is bare: no ore, or no smith worth the name.")
		elif dear.size() > cheap.size():
			parts.append("Ore is dear here, and the rack shows it.")
		elif cheap.size() > 0:
			parts.append("Ore is plentiful; the smith is in a generous mood.")
	else:
		if not cheap.is_empty():
			parts.append("Plentiful here: %s." % _list(cheap))
		if not dear.is_empty():
			parts.append("Scarce, and priced like it: %s." % _list(dear))
	var st := float(mods.get("standing", 0.0))
	if st <= -0.01:
		parts.append("They like you: %d%% off." % roundi(-st * 100))
	elif st >= 0.01:
		parts.append("They don't like you: %d%% on." % roundi(st * 100))
	if float(mods.get("bond", 0.0)) < 0.0:
		parts.append("Your Bond with their people takes 5% off.")
	if float(mods.get("patron", 0.0)) < 0.0:
		parts.append("A patron's friend: %d%% off." % roundi(-float(mods["patron"]) * 100))
	if parts.is_empty():
		parts.append("Fair prices, as these things go.")
	return " ".join(parts)

static func _list(a: Array) -> String:
	var b := a.slice(0, 3)
	var s := ", ".join(PackedStringArray(b))
	if a.size() > 3:
		s += " and more"
	return s

## The town's purse and what it means for a seller.
static func purse_line(wealth: int, pop: int) -> String:
	var cap := int(wealth * 0.25)
	var per := float(wealth) / maxf(1.0, float(pop))
	var mood := "a poor town pays little" if per < 0.5 else ("a rich town pays well" if per >= 3.0 else "it pays fairly")
	return "Their purse: %d coin, %s. One sale fetches %d at most." % [wealth, mood, cap]

## Why a shelf is thin, from the town's state: "" when it is not.
static func thin_line(listings: Array, site: Dictionary, kind: String) -> String:
	var st: Array = site.get("state", [])
	var n := 0
	for l: Dictionary in listings:
		n += int(l.get("n", 0))
	if not listings.is_empty() and n > 3:
		return ""
	if "hungry" in st:
		return "Thin shelves: the town is hungry and keeps what it has."
	if "raided" in st or "besieged" in st:
		return "Thin shelves: the raiders took the best of it."
	if kind == "smith":
		return "A thin rack: there is little ore to work."
	return "Thin shelves: little to spare this season." if listings.is_empty() or n <= 3 else ""

# --- quests ---------------------------------------------------------------------------------------

const QUEST_STATE := {"offered": "On offer", "active": "Under way", "ready": "Ready to hand in", "done": "Done",
	"failed": "Failed", "lapsed": "Lapsed", "beaten": "Beaten to it", "abandoned": "Abandoned"}
## What abandoning costs (DealsSystem: escorts -4, defence -3 standing).
const ABANDON_COST := {"escort": 4, "defend": 3}

static func state_word(q: Dictionary) -> String:
	return String(QUEST_STATE.get(String(q.get("state", "")), String(q.get("state", "")).capitalize()))

static func progress_text(q: Dictionary) -> String:
	var p: Dictionary = q.get("progress", {})
	var t := String(p.get("text", ""))
	if t != "":
		return t
	var need := int(p.get("need", 0))
	if need > 1:
		return "%d of %d" % [mini(int(p.get("have", 0)), need), need]
	return "done, go back" if String(q.get("state", "")) == "ready" else "under way"

static func progress_frac(q: Dictionary) -> float:
	var p: Dictionary = q.get("progress", {})
	if String(q.get("state", "")) in ["ready", "done"]:
		return 1.0
	return clampf(float(p.get("have", 0)) / maxf(1.0, float(p.get("need", 1))), 0.0, 1.0)

## Time left in game days from sim hours: "3 days left", "a day left", "hours left", "overdue".
static func time_left(due_h: int, now_h: float) -> String:
	var left := float(due_h) - now_h
	if due_h <= 0:
		return ""
	if left <= 0.0:
		return "out of time"
	if left < 20.0:
		return "%d hour%s left" % [maxi(1, ceili(left)), "" if ceili(left) == 1 else "s"]
	var d := roundi(left / 24.0)
	return "a day left" if d <= 1 else "%d days left" % d

static func reward_text(r: Dictionary) -> String:
	var parts: Array = []
	if int(r.get("coin", 0)) > 0:
		parts.append("%d coin" % int(r["coin"]))
	if int(r.get("standing", 0)) > 0:
		parts.append("+%d standing" % int(r["standing"]))
	if int(r.get("xp", 0)) > 0:
		parts.append("%d XP" % int(r["xp"]))
	if bool(r.get("item", false)):
		parts.append("and something from the smith")
	return ", ".join(PackedStringArray(parts)) if not parts.is_empty() else "thanks, mostly"

static func abandon_text(q: Dictionary) -> String:
	var n := int(ABANDON_COST.get(String(q.get("kind", "")), 0))
	if n > 0:
		return "Abandon it: -%d standing with them. People were counting on you." % n
	return "Abandon it: no hard feelings, officially."

## Log sections: offered / active / ended.
static func section_of(q: Dictionary) -> String:
	var s := String(q.get("state", ""))
	if s == "offered":
		return "offered"
	if s in ["active", "ready"]:
		return "active"
	return "ended"

## The words for an ending the player did not cause (state changed while they were away or
## someone else did it): "" when the player did it.
static func outcome_note(q: Dictionary, old_state: String) -> String:
	var s := String(q.get("state", ""))
	if s == old_state:
		return ""
	match s:
		"beaten":
			return "%s: someone got there first. You get a little for your trouble." % q.get("title", "")
		"failed":
			return "%s: it went wrong. %s" % [q.get("title", ""), "The town is lost." if String(q.get("kind", "")) == "siege" else "Word came down the road."]
		"lapsed":
			return "%s: lapsed. The moment passed." % q.get("title", "")
		"ready":
			return "%s: done. Go back to %s." % [q.get("title", ""), "be paid"]
	return ""

# --- direction ------------------------------------------------------------------------------------

## From `from` to `to` (tiles): {angle (radians, screen: y down), dist (tiles), text}.
static func bearing(from: Vector2, to: Vector2) -> Dictionary:
	var d := to - from
	var dist := d.length()
	var horiz := "here"
	if absf(d.x) >= 4.0:
		horiz = "%d tiles east" % roundi(d.x) if d.x > 0 else "%d tiles west" % roundi(-d.x)
	var vert := ""
	if absf(d.y) >= 8.0:
		vert = "%d %s" % [roundi(absf(d.y)), "up" if d.y > 0 else "down"]
	var text := horiz
	if vert != "":
		text = vert if horiz == "here" else "%s, %s" % [horiz, vert]
	if dist < 4.0:
		text = "here"
	return {"angle": atan2(-d.y, d.x), "dist": dist, "text": text}

## A number-key option choice in a dialogue: index from 1-9 (0 is "leave"), or -1.
static func option_index(keycode: int) -> int:
	if keycode >= KEY_1 and keycode <= KEY_9:
		return keycode - KEY_1
	if keycode >= KEY_KP_1 and keycode <= KEY_KP_9:
		return keycode - KEY_KP_1
	return -1
