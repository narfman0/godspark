## Fast resolver for fights nobody watches. Each side is {slug: count}. Rounds are
## resolved per stack, not per creature: expected attacks with binomial-sized variance,
## hit chance from attack bonus vs AC, and damage applied to the weakest creature first with
## overkill wasted (BattleSimulator's targeting). Sides act in a random order each round;
## the second side swings with the average of its numbers before and after the first
## side's blows, which approximates interleaved initiative. A side routs once its lost hit
## points reach its break fraction; the winner gets one pursuit volley at half strength.
## Calibrated against the addon's BattleSimulator (docs/tracks/sim.md).
class_name SimCombat
extends RefCounted

## Stack layout (an Array per slug): [slug, count, hp, ac, bonus, dmg, attacks, wounded_hp,
## count at round start, count at fight start]
const SLUG := 0
const N := 1
const HP := 2
const AC := 3
const BONUS := 4
const DMG := 5
const ATT := 6
const W := 7
const START := 8
const ORIG := 9

## Dice variance of one hit's damage, as a coefficient of variation.
const DMG_CV := 0.35

## opts: a_break, b_break (fraction of hit points lost that makes a side flee; 1.0 fights
## to the death), b_ac (AC bonus for side b, e.g. walls), b_hp (hit point multiplier for b),
## a_ambush (a free first volley at this strength, 0..1), max_rounds, compat (one attack
## with the first weapon's first damage part, like BattleSimulator).
## Returns {winner: "a" | "b" | "draw", rounds, a_dead: {slug: n}, b_dead: {slug: n},
## a_left: {slug: n}, b_left: {slug: n}}.
static func resolve(rng: RandomNumberGenerator, a: Dictionary, b: Dictionary, opts := {}) -> Dictionary:
	SimData.ensure()
	var compat: bool = opts.get("compat", false)
	var sa := _stacks(a, compat, 0, 1.0)
	var sb := _stacks(b, compat, int(opts.get("b_ac", 0)), float(opts.get("b_hp", 1.0)))
	var a_break: float = opts.get("a_break", 1.0)
	var b_break: float = opts.get("b_break", 1.0)
	var max_rounds: int = opts.get("max_rounds", 20)
	var a_hp0 := _hp(sa)
	var b_hp0 := _hp(sb)
	var winner := "draw"
	var rounds := 0
	var ambush: float = opts.get("a_ambush", 0.0)
	if ambush > 0.0 and a_hp0 > 0.0 and b_hp0 > 0.0:
		_volley(rng, sa, sb, ambush, false)
	while rounds < max_rounds:
		if _hp(sa) <= 0.0 or _hp(sb) <= 0.0:
			break
		rounds += 1
		if rng.randf() < 0.5:
			_volley(rng, sa, sb, 1.0, false)
			_volley(rng, sb, sa, 1.0, true)
		else:
			_volley(rng, sb, sa, 1.0, false)
			_volley(rng, sa, sb, 1.0, true)
		var a_lost := 1.0 - _hp(sa) / a_hp0 if a_hp0 > 0.0 else 1.0
		var b_lost := 1.0 - _hp(sb) / b_hp0 if b_hp0 > 0.0 else 1.0
		var a_out := a_lost >= a_break - 1e-9
		var b_out := b_lost >= b_break - 1e-9
		if a_out and b_out:
			# Both break: the one that lost the larger share runs.
			if a_lost / a_break >= b_lost / b_break:
				b_out = false
			else:
				a_out = false
		if b_out:
			winner = "a"
			if _hp(sb) > 0.0:
				_volley(rng, sa, sb, 0.5, false)
			break
		if a_out:
			winner = "b"
			if _hp(sa) > 0.0:
				_volley(rng, sb, sa, 0.5, false)
			break
	if winner == "draw":
		if _hp(sb) <= 0.0 and _hp(sa) > 0.0:
			winner = "a"
		elif _hp(sa) <= 0.0 and _hp(sb) > 0.0:
			winner = "b"
	return {"winner": winner, "rounds": rounds, "a_dead": _dead(sa), "b_dead": _dead(sb),
		"a_left": _left(sa), "b_left": _left(sb)}

## Win probability estimate without rolling: compares Lanchester strengths.
static func odds(a: Dictionary, b: Dictionary, b_ac := 0, b_hp := 1.0) -> float:
	var pa := SimData.group_power(a)
	var pb := SimData.group_power(b) * sqrt(b_hp) * (1.0 + 0.08 * b_ac)
	if pa + pb <= 0.0:
		return 0.5
	var r := pa / maxf(pb, 0.001)
	# Lanchester square law: strength ratio r gives a near-certain win well before r = 2.
	return clampf(1.0 / (1.0 + pow(r, -3.0)), 0.0, 1.0)

static func _stacks(side: Dictionary, compat: bool, ac_bonus: int, hp_mult: float) -> Array:
	var out: Array = []
	var keys := side.keys()
	keys.sort()
	for slug in keys:
		var n := int(side[slug])
		if n <= 0:
			continue
		var m := SimData.monster(slug)
		var hp := maxf(float(m.hp) * hp_mult, 1.0)
		var dmg: float = m.dmg1 if compat else m.dmg
		var bonus: int = m.bonus1 if compat else m.bonus
		var att: int = 1 if compat else m.attacks
		out.append([slug, n, hp, int(m.ac) + ac_bonus, bonus, dmg, att, hp, n, n])
	# Weakest first: BattleSimulator always swings at the lowest current hit points.
	out.sort_custom(func(x, y): return x[HP] < y[HP] or (x[HP] == y[HP] and x[SLUG] < y[SLUG]))
	return out

static func _hp(stacks: Array) -> float:
	var t := 0.0
	for s in stacks:
		if s[N] > 0:
			t += (s[N] - 1) * s[HP] + s[W]
	return t

## One side's attacks against the other. second: this side acts after the other one this
## round, so it swings with the mean of its numbers before and after those blows.
static func _volley(rng: RandomNumberGenerator, att: Array, tgt: Array, strength: float, second: bool) -> void:
	for s in att:
		var n: float = s[N]
		if second:
			n = (s[N] + s[START]) * 0.5
		if n <= 0.0 or s[DMG] <= 0.0:
			continue
		var attacks: float = n * s[ATT] * strength
		var ac := _first_ac(tgt)
		if ac < 0:
			return
		var p := clampf((21.0 + s[BONUS] - ac) / 20.0, 0.05, 0.95)
		var hits := attacks * p
		var cv := sqrt(((1.0 - p) + DMG_CV * DMG_CV) / maxf(hits, 0.25))
		attacks *= maxf(0.0, 1.0 + rng.randfn(0.0, minf(cv, 1.0)))
		_apply(attacks, s[BONUS], s[DMG], tgt)
	# Mark the start count for the next round's "second" average.
	for s in att:
		s[START] = s[N]

static func _first_ac(stacks: Array) -> int:
	for s in stacks:
		if s[N] > 0:
			return s[AC]
	return -1

static func _apply(attacks: float, bonus: int, dmg: float, tgt: Array) -> void:
	for s in tgt:
		if attacks <= 0.0:
			return
		if s[N] <= 0:
			continue
		var p := clampf((21.0 + bonus - s[AC]) / 20.0, 0.05, 0.95)
		# A natural 20 doubles the dice: about +5% of attacks deal roughly half again.
		var d := dmg * (1.0 + 0.05 * 0.6 / p)
		var need: float = ceilf(s[W] / d) / p
		if attacks < need:
			s[W] -= attacks * p * d
			if s[W] <= 0.0:
				s[N] -= 1
				s[W] = s[HP]
			return
		attacks -= need
		s[N] -= 1
		s[W] = s[HP]
		if s[N] <= 0:
			continue
		var per_kill: float = ceilf(s[HP] / d) / p
		var kills := mini(s[N], int(floor(attacks / per_kill)))
		s[N] -= kills
		attacks -= kills * per_kill
		if s[N] <= 0:
			continue
		s[W] -= attacks * p * d
		if s[W] <= 0.0:
			s[N] -= 1
			s[W] = s[HP]
		return

static func _dead(stacks: Array) -> Dictionary:
	var out := {}
	for s in stacks:
		var lost: int = s[ORIG] - s[N]
		if lost > 0:
			out[s[SLUG]] = lost
	return out

static func _left(stacks: Array) -> Dictionary:
	var out := {}
	for s in stacks:
		if s[N] > 0:
			out[s[SLUG]] = s[N]
	return out
