## The 100-level track laid over the SRD's 20 class levels (docs/m2.md, "The level track").
## Pure static functions. Levels run 1..MAX_LEVEL; class level 1 at creation, class levels
## 2..20 at levels 5, 10 .. 95, and level 100 is the Epic Boon (the first step past mortal).
##
## Each band of five levels has the same beat, by level % 5:
##   1 SPARK_SLOT   2 VIGOR   3 SPARK_SLOT   4 KNACK   0 CLASS_LEVEL (EPIC_BOON at 100)
##
## Hit points and XP move between class levels in fifths (levels 1..4, the first band, in
## quarters: level 1 is exactly the SRD's class level 1). Past class level 20 (levels
## 96..100) both continue one more band as if there were a 21st class level with the last
## SRD gap: level 100 has one more class level's hit points and needs 50000 XP (times
## XP_SCALE) more than level 95.
class_name LevelTrack
extends RefCounted

const MAX_LEVEL := 100
const MAX_CLASS_LEVEL := 20
## Multiplies every XP threshold (tuned by tools/xp_pacing.gd later).
const XP_SCALE := 1.0

enum Reward { SPARK_SLOT, VIGOR, KNACK, CLASS_LEVEL, EPIC_BOON }

static func clamp_level(level: int) -> int:
	return clampi(level, 1, MAX_LEVEL)

## min(20, 1 + level / 5).
static func class_level(level: int) -> int:
	return mini(MAX_CLASS_LEVEL, 1 + clamp_level(level) / 5)

## What reaching `level` gives. Level 1 (creation) counts as a spark slot by the rhythm.
static func reward(level: int) -> Reward:
	level = clamp_level(level)
	match level % 5:
		1, 3:
			return Reward.SPARK_SLOT
		2:
			return Reward.VIGOR
		4:
			return Reward.KNACK
	return Reward.EPIC_BOON if level == MAX_LEVEL else Reward.CLASS_LEVEL

## Levels in 1..level whose reward is `r` (closed form of counting the rhythm).
static func count(level: int, r: Reward) -> int:
	level = clamp_level(level)
	match r:
		Reward.SPARK_SLOT:
			return (level + 4) / 5 + (level + 2) / 5      # % 5 == 1, % 5 == 3
		Reward.VIGOR:
			return (level + 3) / 5
		Reward.KNACK:
			return (level + 1) / 5
		Reward.CLASS_LEVEL:
			return mini(level, MAX_LEVEL - 1) / 5
		Reward.EPIC_BOON:
			return 1 if level >= MAX_LEVEL else 0
	return 0

## 40 at level 100.
static func spark_slots(level: int) -> int:
	return count(level, Reward.SPARK_SLOT)

## 20 at level 100.
static func vigor_steps(level: int) -> int:
	return count(level, Reward.VIGOR)

## 20 at level 100.
static func knacks(level: int) -> int:
	return count(level, Reward.KNACK)

## Where `level` sits between two class-level anchors: [k, num, den] meaning
## anchor k (0 = class level 1, ..., 19 = class level 20, 20 = the level-100 step past it)
## plus num/den of the way to anchor k + 1.
static func _band(level: int) -> Array:
	level = clamp_level(level)
	if level < 5:
		return [0, level - 1, 4]
	return [level / 5, level % 5, 5] if level < MAX_LEVEL else [20, 0, 5]

## Total XP to reach `level` (0 at level 1). The SRD gap between class levels c and c + 1 is
## split evenly over the levels between, times XP_SCALE.
static func xp_for_level(level: int) -> int:
	var b := _band(level)
	var k: int = b[0]
	var base := _srd_xp(k)
	var gap := _srd_xp(k + 1) - base
	return roundi((base + float(gap * int(b[1])) / int(b[2])) * XP_SCALE)

## Highest level whose threshold `xp` reaches.
static func level_for_xp(xp: int) -> int:
	var lo := 1
	var hi := MAX_LEVEL
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if xp_for_level(mid) <= xp:
			lo = mid
		else:
			hi = mid - 1
	return lo

## SRD XP for anchor k (class level k + 1); anchor 20 (level 100) repeats the last gap.
static func _srd_xp(k: int) -> int:
	var t := SRDExperience.XP_THRESHOLDS
	if k < t.size():
		return t[k]
	return t[t.size() - 1] + (t[t.size() - 1] - t[t.size() - 2]) * (k - t.size() + 1)

## SRD fixed-value hit points at a class level: hit die + CON at 1, then (die / 2 + 1 + CON)
## a level, each gain at least 1 (SRDLevelUp, make_character).
static func srd_hp(class_lvl: int, hit_die: int, con_mod: int) -> int:
	return maxi(1, hit_die + con_mod) + (class_lvl - 1) * _gain(hit_die, con_mod)

static func _gain(hit_die: int, con_mod: int) -> int:
	return maxi(1, hit_die / 2 + 1 + con_mod)

## Hit points from one Vigor step: half a hit die, rounded up.
static func vigor_hp(hit_die: int) -> int:
	return (hit_die + 1) / 2

## Max hit points at `level`: the SRD total at each class level, the next class level's gain
## spread over the levels between (floored, so never decreasing), plus Vigor.
static func max_hp(level: int, hit_die: int, con_mod: int) -> int:
	var b := _band(level)
	var k: int = b[0]
	var hp := srd_hp(k + 1, hit_die, con_mod) + _gain(hit_die, con_mod) * int(b[1]) / int(b[2])
	return hp + vigor_steps(level) * vigor_hp(hit_die)

## Hit Point Dice for rests: one per class level plus one per Vigor step.
static func hit_dice(level: int) -> int:
	return class_level(level) + vigor_steps(level)
