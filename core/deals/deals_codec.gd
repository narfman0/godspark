## SYS layouts of Deals (HostSystem.DEALS). Low-rate messages, so each payload is one UTF-8
## JSON object, as Life's are (numbers come back as floats; DealsClient converts). Item
## records inside are plain item dictionaries (Items record format).
##
## Host -> client (to the one player concerned):
##   TALK (1):    {open, id, name, role, site, faction, line, view, options: [{id, label}],
##                 rumours?: [rumour], offers?: [quest]}       or {open: false, why}
##   SHOP (2):    {open, kind (store | smith), site, town, listings: [{id, item, n, price}],
##                 sell: {"<slot>": price}, wealth}             or {open: false}
##   QUESTS (3):  {quests: [quest]}                             the player's whole log
##   RUMOUR (4):  {rumours: [rumour], all: bool}                newly heard (all: the full list)
##   PATRON (5):  {patrons: {faction: {tier, standing, given, suspended, name}}}
##   NOTE (6):    {op, ok, word}                                the answer to a request
##   ATLAS (7):   {t, sites?: [site], routes?: [route], seen?: [site id], regions?: [index in meta.biomes], all?}   what the map
##                and place banners show (Interface): on join everything (all: true), then
##                sites when their names, tiers, states or work change, seen when the player
##                first stands at a site. site: {id, kind, name, culture?, tier?, pop?,
##                faction?, state?: [situation], work?: [giver roles], lair?, apex?, ruin?};
##                route: {id, a, b, kind, name, path: [[x, y]] every 8th feet cell}
## Client -> host:
##   TALK_TO (64) {e}   CHOOSE (65) {o}   LEAVE (66) {}   BUY (67) {l, n}   SELL (68) {s, n}
##   SERVICE (69) {id}  ACCEPT (70) {q}   ABANDON (71) {q}   TURN_IN (72) {q}
##   CHEAT (79) {op, ...}   only when the host runs with `cheats`
## rumour: {id, text, kind, t, site, dir, dist, tiles}; quest: see DealsQuests.
class_name DealsCodec
extends RefCounted

enum Msg { TALK = 1, SHOP = 2, QUESTS = 3, RUMOUR = 4, PATRON = 5, NOTE = 6, ATLAS = 7,
	TALK_TO = 64, CHOOSE = 65, LEAVE = 66, BUY = 67, SELL = 68, SERVICE = 69, ACCEPT = 70, ABANDON = 71,
	TURN_IN = 72, CHEAT = 79 }

static func write(d: Dictionary) -> PackedByteArray:
	return JSON.stringify(d).to_utf8_buffer()

static func read(data: PackedByteArray) -> Dictionary:
	var v: Variant = JSON.parse_string(data.get_string_from_utf8())
	return v if v is Dictionary else {}

## JSON numbers back to ints in an item record (count, tier, spark rank).
static func item(v: Variant) -> Dictionary:
	return Items.clean(v)

## JSON floats back to ints where a quest has ints.
static func quest(v: Variant) -> Dictionary:
	if not v is Dictionary:
		return {}
	var q: Dictionary = (v as Dictionary).duplicate(true)
	for k: String in ["site", "day", "due", "ended_at"]:
		if q.has(k):
			q[k] = int(q[k])
	var t: Dictionary = q.get("target", {})
	for k: String in t:
		if t[k] is float:
			t[k] = int(t[k])
	var r: Dictionary = q.get("reward", {})
	for k: String in ["coin", "standing", "xp"]:
		if r.has(k):
			r[k] = int(r[k])
	var p: Dictionary = q.get("progress", {})
	for k: String in ["have", "need"]:
		if p.has(k):
			p[k] = int(p[k])
	return q
