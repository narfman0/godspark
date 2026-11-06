## What an actor's body does for a SWING event, as a list of clip segments on the swing's own
## clock. Pure: data/looks.json "swings" names the moves and data/combat.json the tempo; this
## only lays them out, so the clip's visible contact falls exactly on the host's contact.
##
##   var plan := SwingPlan.build({"tempo": "plain", "mode": 0, "swings": 2, "windup": 0.2,
##       "gap": 0.2, "total": 0.6})
##   # [{clip, from, to, start, dur}...]; SwingPlan.at(plan, 0.2) -> {clip, time} at the contact
##
## A move in looks.json: {"pre": [clip, from_s, contact_s], "post": [clip, contact_s, to_s]}.
## "pre" is stretched over the wind-up (for a combo's follow-up: over the gap), "post" over
## what is left of the action. Times inside a clip come from tools/clip_probe.gd: the sword tip
## is fastest at the contact. Synty's combo files are sections of one long take (their first
## second is a hold, the ReturnToIdle files show no swing at all), so from_s matters.
class_name SwingPlan
extends RefCounted

## A body that has nothing to show for this long (an instant cast) still shows it.
const MIN_POST := 0.2
## A swing's event goes out with the tick after the one that started the host's clock, so
## the view's clock starts this far in: the contact then falls on the HIT that reports it.
const HEAD_START := 1.0 / K.TICK_HZ

static func conf() -> Dictionary:
	return Looks.table().get("swings", {})

## The moves a swing cycles through: the tempo's row, or what its mode says for a body swung by
## the stat block (a monster's "tempo" says nothing about a bow or a spell).
static func chain(tempo: String, mode: int) -> Array:
	var key := tempo
	match mode:
		CombatCodec.Mode.THROW:
			key = "thrown"
		CombatCodec.Mode.CAST, CombatCodec.Mode.AREA, CombatCodec.Mode.SAVE_ACTION:
			key = "cast"
		CombatCodec.Mode.RANGED:
			if tempo == "monster":
				key = "bow"
	var rows: Dictionary = conf().get("tempo", {})
	return rows.get(key, rows.get("plain", []))

## Segments for a SWING event's fields. first: which move of the chain opens (consecutive
## actions walk along it, so held attacks do not repeat one swing).
static func build(ev: Dictionary, first := 0) -> Array:
	var moves: Dictionary = conf().get("moves", {})
	var names := chain(String(ev.get("tempo", "plain")), int(ev.get("mode", 0)))
	var out: Array = []
	if names.is_empty():
		return out
	var windup := float(ev.get("windup", 0.0))
	var total := float(ev.get("total", 0.0))
	var gap := float(ev.get("gap", 0.0))
	var n := maxi(1, int(ev.get("swings", 1)))
	for i in n:
		var m: Dictionary = moves.get(String(names[(first + i) % names.size()]), {})
		if m.is_empty():
			continue
		var contact := windup + gap * i
		var lead := windup if i == 0 else gap
		var pre: Array = m["pre"]
		if lead > 0.0:
			out.append({"clip": String(pre[0]), "from": float(pre[1]), "to": float(pre[2]), "start": contact - lead, "dur": lead})
		if i == n - 1:
			var post: Array = m["post"]
			out.append({"clip": String(post[0]), "from": float(post[1]), "to": float(post[2]), "start": contact,
				"dur": maxf(total - contact, MIN_POST)})
	return out

## One segment, for the roll and the flinch: a named move's whole span over `dur`.
static func single(move: String, dur: float) -> Array:
	var m: Dictionary = conf().get("moves", {}).get(move, {})
	if m.is_empty():
		return []
	var pre: Array = m["pre"]
	var post: Array = m["post"]
	if String(pre[0]) != String(post[0]):
		return []
	return [{"clip": String(pre[0]), "from": float(pre[1]), "to": float(post[2]), "start": 0.0, "dur": dur}]

## When the plan ends, swing seconds.
static func length(plan: Array) -> float:
	return 0.0 if plan.is_empty() else float(plan[-1]["start"]) + float(plan[-1]["dur"])

## The clip and its time at swing second t: {clip, time}, or {} past the end.
static func at(plan: Array, t: float) -> Dictionary:
	if plan.is_empty() or t > length(plan) + 1e-6:
		return {}
	var seg: Dictionary = plan[0]
	for s: Dictionary in plan:
		if t + 1e-6 >= float(s["start"]):
			seg = s
	return {"clip": seg["clip"], "time": lerpf(float(seg["from"]), float(seg["to"]),
		clampf((t - float(seg["start"])) / maxf(float(seg["dur"]), 1e-4), 0.0, 1.0))}

## The clips a tempo class can need (to load them ahead of the first swing).
static func clips_of(tempo: String, mode := 0) -> PackedStringArray:
	var out := PackedStringArray()
	var moves: Dictionary = conf().get("moves", {})
	for name: Variant in chain(tempo, mode):
		var m: Dictionary = moves.get(String(name), {})
		for part: String in ["pre", "post"]:
			if m.has(part) and not String(m[part][0]) in out:
				out.append(String(m[part][0]))
	return out

## The longest stretch of a clip the moves use: [from, to] seconds (a clip's long opening hold
## is never sampled when it is retargeted).
static func span(clip: String) -> Vector2:
	var out := Vector2(INF, -INF)
	for m: Dictionary in conf().get("moves", {}).values():
		for part: String in ["pre", "post"]:
			var row: Array = m[part]
			if String(row[0]) == clip:
				out = Vector2(minf(out.x, float(row[1])), maxf(out.y, float(row[2])))
	return out
