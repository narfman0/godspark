## XP pacing: minutes per level 1..100 from an assumed kill rate per depth band and the SRD
## XP of the monsters typical there, to tune LevelTrack.XP_SCALE toward docs/m2.md's target
## (early levels 3-6 minutes, level 50 about 20, the 90s about an hour, about 40 hours total).
##
##   godot --headless -s res://tools/xp_pacing.gd                 # at the current XP_SCALE
##   godot --headless -s res://tools/xp_pacing.gd -- scale=14     # what if
##   godot --headless -s res://tools/xp_pacing.gd -- measured     # the measured table, with
##       data/rules/xp.json's band divisors and quest XP; `flat` ignores the divisors, `fit`
##       searches for the divisors nearest the targets
##
## ASSUMPTIONS (nothing here is measured; replace with play data once the spawn director and
## combat exist): the band a player of a given level mostly fights in, kills per minute
## there, the monsters typical there (their SRD stat block XP, averaged) and the rank mix
## (minion 0.25, standard 1, elite 2, champion 4 times the XP: RulesSystem.RANK_XP). The XP
## rate is interpolated linearly in level between band anchors.
extends SceneTree

const BANDS := [
	{"band": "surface", "from": 1, "kills_per_min": 10.0,
		"monsters": ["goblin-minion", "goblin-warrior", "wolf", "giant-rat", "bandit"],
		"mix": {"minion": 0.5, "standard": 0.45, "elite": 0.05}},
	{"band": "shallow caves", "from": 10, "kills_per_min": 6.0,
		"monsters": ["skeleton", "zombie", "giant-spider", "gnoll-warrior", "dire-wolf", "bugbear-warrior"],
		"mix": {"minion": 0.4, "standard": 0.5, "elite": 0.08, "champion": 0.02}},
	{"band": "caves", "from": 25, "kills_per_min": 4.5,
		"monsters": ["ghoul", "ogre", "grick", "gibbering-mouther", "gargoyle", "owlbear", "basilisk"],
		"mix": {"minion": 0.4, "standard": 0.5, "elite": 0.08, "champion": 0.02}},
	{"band": "deeps", "from": 45, "kills_per_min": 2.3,
		"monsters": ["chuul", "roper", "otyugh", "drider", "wraith", "xorn", "troll"],
		"mix": {"minion": 0.5, "standard": 0.45, "elite": 0.05}},
	{"band": "nadir", "from": 75, "kills_per_min": 0.75,
		"monsters": ["cloaker", "aboleth", "fire-giant", "behir", "stone-giant"],
		"mix": {"minion": 0.5, "standard": 0.45, "elite": 0.05}},
]
## MEASURED (measured=1): stat-block XP per minute (rank multipliers in, XP_SCALE out) from
##   tools/spawn_sim.gd -- bands=B minutes=6 kill=hunt from=settlement   (seed 4, 1024x512)
## a hunter who kills the oldest monster the director made at least 10 s ago every 2.5 s: the
## director's supply with its lulls, capped by a brisk fight pace. Anchors by level: the
## surface by day near the spawn settlement (1), the surface at night (10), caves (25), deeps
## (45), nadir (75). M2 integration, after the balance pass.
## The hunter's 2.5 s per kill is brisk for deep creatures: deeper anchors are scaled by
## min(1, measured kills/min / (60 / fight_s)) with fight_s an ASSUMED fight length (caves 5 s,
## deeps 10 s, nadir 20 s); the result is the third column.
const MEASURED := [[1, 166.0, "surface", "surface day, near the spawn settlement (8.5 kills/min)"],
	[10, 299.6, "surface", "surface night (12.0 kills/min)"],
	[25, 4309.4 * 12.0 / 12.83, "caves", "caves (12.8 kills/min measured, 12 at 5 s a fight)"],
	[45, 9616.9 * 6.0 / 14.17, "deeps", "deeps (14.2 kills/min measured, 6 at 10 s a fight)"],
	[75, 54475.0 * 3.0 / 13.67, "nadir", "nadir (13.7 kills/min measured, 3 at 20 s a fight)"]]
## Quests in the model: two jobs an hour at about 100 XP each (data/deals/quests.json pays 40-150
## flat, undivided), so XP per minute at every level gets this much on top of the kills.
const QUEST_XP_PER_MIN := 3.3
## Targets: minutes for levels 2..5, level 50 and the 90s, and total hours.
const TARGET := {"early": 4.5, "l50": 20.0, "l90s": 60.0, "hours": 40.0}

var srd: SRDContent

func _initialize() -> void:
	srd = SRDContent.new()
	var opts := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		opts[kv[0]] = kv[1] if kv.size() > 1 else ""
	var anchors := []
	if opts.has("measured"):
		print("XP pacing (MEASURED XP/min from spawn_sim kill=hunt; LevelTrack.XP_SCALE = %s)" % LevelTrack.XP_SCALE)
		var div: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/rules/xp.json"))["band_divisor"]
		if opts.has("flat"):
			div = {}
		var sc := float(opts.get("scale", LevelTrack.XP_SCALE))
		if opts.has("fit"):
			div = _fit(sc)
			print("best divisors: %s" % div)
		for m: Array in MEASURED:
			var d := float(div.get(m[2], 1.0))
			anchors.append([int(m[0]), float(m[1]) / d + QUEST_XP_PER_MIN])
			print("  from level %2d: %8.1f XP/min / %.1f + quests %.1f  %s" % [m[0], m[1], d, QUEST_XP_PER_MIN, m[3]])
		print("")
		_report(anchors, sc, true)
		quit()
		return
	print("XP pacing (ASSUMED kill rates and monster mix; LevelTrack.XP_SCALE = %s)" % LevelTrack.XP_SCALE)
	print("%-14s %5s %9s %10s %8s  monsters" % ["band", "from", "kills/min", "XP/kill", "XP/min"])
	for b: Dictionary in BANDS:
		var xp := 0.0
		for m: String in b["monsters"]:
			xp += srd.monster_xp(m)
		xp /= (b["monsters"] as Array).size()
		var mult := 0.0
		for r: String in b["mix"]:
			mult += float(b["mix"][r]) * float(RulesSystem.RANK_XP[r])
		var rate := float(b["kills_per_min"]) * xp * mult
		anchors.append([int(b["from"]), rate])
		print("%-14s %5d %9.2f %10.0f %8.0f  %s (SRD avg %d XP)" % [b["band"], b["from"], b["kills_per_min"], xp * mult, rate,
				", ".join(b["monsters"]), roundi(xp)])
	var scale := float(opts.get("scale", LevelTrack.XP_SCALE))
	var best := _best(anchors)
	print("")
	_report(anchors, scale, true)
	print("")
	print("Best single scale against the targets (log error): %.1f" % best)
	_report(anchors, best, false)
	quit()

## Divisors for caves, deeps and nadir nearest the targets at a scale (log error).
static func _fit(sc: float) -> Dictionary:
	var best := {}
	var be := INF
	for c in range(10, 120, 5):
		for d in range(10, 150, 5):
			for n in range(10, 400, 5):
				var div := {"caves": c / 10.0, "deeps": d / 10.0, "nadir": n / 10.0}
				var anchors := []
				for m: Array in MEASURED:
					anchors.append([int(m[0]), float(m[1]) / float(div.get(m[2], 1.0)) + QUEST_XP_PER_MIN])
				var e := _score(anchors, sc)
				if e < be:
					be = e
					best = div
	return best

## XP per minute at a level (linear between band anchors, flat past the last).
static func rate_at(anchors: Array, level: int) -> float:
	for i in anchors.size() - 1:
		var a: Array = anchors[i]
		var b: Array = anchors[i + 1]
		if level >= int(a[0]) and level < int(b[0]):
			return lerpf(a[1], b[1], float(level - int(a[0])) / (int(b[0]) - int(a[0])))
	return anchors[-1][1]

## Minutes to reach each level 2..100 at XP_SCALE `scale`: [m2, m3, ... m100].
static func minutes(anchors: Array, scale: float) -> Array:
	var out := []
	for lvl in range(2, LevelTrack.MAX_LEVEL + 1):
		var need := float(LevelTrack.xp_for_level(lvl) - LevelTrack.xp_for_level(lvl - 1)) / LevelTrack.XP_SCALE * scale
		out.append(need / rate_at(anchors, lvl - 1))
	return out

static func _score(anchors: Array, scale: float) -> float:
	var m := minutes(anchors, scale)
	var early: float = (m[0] + m[1] + m[2] + m[3]) / 4.0
	var l90 := 0.0
	for i in range(88, 98):
		l90 += m[i]
	var total := 0.0
	for x: float in m:
		total += x
	var err := 0.0
	for p: Array in [[early, TARGET["early"]], [m[48], TARGET["l50"]], [l90 / 10.0, TARGET["l90s"]], [total / 60.0, TARGET["hours"]]]:
		err += pow(log(p[0] / p[1]), 2)
	return err

static func _best(anchors: Array) -> float:
	var best := 1.0
	var be := INF
	for i in range(5, 1200):
		var s := i / 10.0
		var e := _score(anchors, s)
		if e < be:
			be = e
			best = s
	return best

static func _report(anchors: Array, scale: float, full: bool) -> void:
	var m := minutes(anchors, scale)
	var total := 0.0
	for x: float in m:
		total += x
	print("XP_SCALE %.1f: total %.1f hours" % [scale, total / 60.0])
	if full:
		for row in range(0, 100, 10):
			var line := PackedStringArray()
			for lvl in range(maxi(2, row + 1), row + 11):
				line.append("%3d:%5.1f" % [lvl, m[lvl - 2]])
			print("  " + " ".join(line))
	var l90 := 0.0
	for i in range(88, 98):
		l90 += m[i]
	print("  levels 2-5: %.1f-%.1f min (target 3-6), level 50: %.1f (target ~20), levels 90-99: %.1f avg (target ~60), level 100: %.1f" % [
			minf(minf(m[0], m[1]), minf(m[2], m[3])), maxf(maxf(m[0], m[1]), maxf(m[2], m[3])), m[48], l90 / 10.0, m[98]])
	var cum := 0.0
	var marks := PackedStringArray()
	for lvl in range(2, 101):
		cum += m[lvl - 2]
		if lvl in [10, 25, 50, 75, 100]:
			marks.append("L%d %.1fh" % [lvl, cum / 60.0])
	print("  time to reach: " + ", ".join(marks))
