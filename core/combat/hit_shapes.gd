## Physical hit tests on the host, in tile units: melee arcs, projectile segments, spell and
## breath areas, line of sight / line of effect and cover from TileCollision.raycast.
## Pure static functions over Rect2 boxes (Body.rect()) and the TileWorld.
##
##   HitShapes.in_arc(att.rect(), dir, K.ft(5), 70.0, target.rect())
##   HitShapes.cover(world, eye, target.rect())        # SRD.Cover from blocked sample rays
##   HitShapes.in_area(SRD.AoEShape.CONE, origin, dir, K.ft(15), 0.0, target.rect())
class_name HitShapes
extends RefCounted

const EPS := 1e-4

## Shortest distance between two boxes (0 when they touch or overlap).
static func gap(a: Rect2, b: Rect2) -> float:
	var dx := maxf(0.0, maxf(a.position.x - b.end.x, b.position.x - a.end.x))
	var dy := maxf(0.0, maxf(a.position.y - b.end.y, b.position.y - a.end.y))
	return sqrt(dx * dx + dy * dy)

## The point of `r` nearest to `p`.
static func nearest(r: Rect2, p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))

## 3x3 sample points over a box, inset 10% (cover and line of effect rays aim at these).
static func samples(r: Rect2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var inset := r.size * 0.1
	var inner := Rect2(r.position + inset, r.size - inset * 2.0)
	for j in 3:
		for i in 3:
			out.append(inner.position + Vector2(inner.size.x * i * 0.5, inner.size.y * j * 0.5))
	return out

## Unit aim direction from `from` toward `aim`; `facing` (+1/-1) when they coincide.
static func aim_dir(from: Vector2, aim: Vector2, facing: int) -> Vector2:
	var d := aim - from
	if d.length() < 0.05 or not is_finite(d.x) or not is_finite(d.y):
		return Vector2(1.0 if facing >= 0 else -1.0, 0.0)
	return d.normalized()

## Melee: is `target` within `reach` tiles of the attacker's box (box to box, as the SRD's
## "within 5 feet" between squares) and inside the arc of +-half_angle_deg around `dir`,
## measured from the attacker's centre to the nearest point of the target? Overlapping
## boxes count when the target is not behind (dot >= -0.25).
static func in_arc(att: Rect2, dir: Vector2, reach: float, half_angle_deg: float, target: Rect2) -> bool:
	if gap(att, target) > reach + EPS:
		return false
	var c := att.get_center()
	if att.intersects(target, true):
		var to := target.get_center() - c
		return to.length() < 0.05 or to.normalized().dot(dir) >= -0.25
	var min_dot := cos(deg_to_rad(half_angle_deg)) - EPS
	for p in _probe(target, c):
		var v := p - c
		if v.length() < EPS:
			return true
		if v.normalized().dot(dir) >= min_dot and gap(att, Rect2(p, Vector2.ZERO)) <= reach + EPS:
			return true
	return false

## Which of two creatures a blow lands on first: foes before bystanders, then the nearer box,
## then the nearer to the aim (touches within 0.01 tiles are level). The host orders a blow's
## touches by this and the client's target highlight names the same creature.
static func nearer_touch(foe_a: bool, gap_a: float, aim_a: float, foe_b: bool, gap_b: float, aim_b: float) -> bool:
	if foe_a != foe_b:
		return foe_a
	if absf(gap_a - gap_b) > 0.01:
		return gap_a < gap_b
	return aim_a < aim_b

## Can a straight line from `from` reach any sample point of `r` without a solid tile?
static func line_to(world: TileWorld, from: Vector2, r: Rect2) -> bool:
	for p in samples(r):
		if not TileCollision.raycast(world, from, p)["hit"]:
			return true
	return false

## Fraction (0..1) of the 3x3 sample rays from `from` to `r` that a solid tile blocks.
static func blocked_fraction(world: TileWorld, from: Vector2, r: Rect2) -> float:
	var n := 0
	var pts := samples(r)
	for p in pts:
		if TileCollision.raycast(world, from, p)["hit"]:
			n += 1
	return float(n) / pts.size()

## SRD cover of a target box against an attack from `from`: NONE, HALF (+2),
## THREE_QUARTERS (+5) or FULL (cannot be targeted), from the blocked fraction and the
## thresholds in data/combat.json "cover".
static func cover(world: TileWorld, from: Vector2, r: Rect2) -> int:
	var f := blocked_fraction(world, from, r)
	var c := CombatTempo.section("cover")
	if f >= 1.0:
		return SRD.Cover.FULL
	if f >= float(c.get("three_quarters", 0.6)):
		return SRD.Cover.THREE_QUARTERS
	if f >= float(c.get("half", 0.3)):
		return SRD.Cover.HALF
	return SRD.Cover.NONE

## First crossing of segment a->b with box r: t in [0, 1], or -1. A segment starting
## inside the box hits at 0.
static func segment_box(a: Vector2, b: Vector2, r: Rect2) -> float:
	if r.has_point(a):
		return 0.0
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	for axis in 2:
		var lo := r.position[axis]
		var hi := r.end[axis]
		if absf(d[axis]) < 1e-9:
			if a[axis] < lo or a[axis] > hi:
				return -1.0
			continue
		var ta := (lo - a[axis]) / d[axis]
		var tb := (hi - a[axis]) / d[axis]
		if ta > tb:
			var s := ta
			ta = tb
			tb = s
		t0 = maxf(t0, ta)
		t1 = minf(t1, tb)
		if t0 > t1:
			return -1.0
	return t0

## Does an SRD area overlap box r? Shapes in tile units:
##   SPHERE / CYLINDER  circle of radius `size` around `origin` (a side view of both)
##   CONE    from origin along dir, length `size`, as wide as it is far (half angle 26.6 deg)
##   LINE    from origin along dir, length `size`, width `width` (default 2 tiles = 5 ft)
##   CUBE    a square of side `size` with one face centred on origin, extending along dir
static func in_area(shape: int, origin: Vector2, dir: Vector2, size: float, width: float, r: Rect2) -> bool:
	match shape:
		SRD.AoEShape.SPHERE, SRD.AoEShape.CYLINDER:
			return nearest(r, origin).distance_to(origin) <= size + EPS
		SRD.AoEShape.CUBE:
			var c := origin + dir * size * 0.5
			return _in_square(c, dir, size, size, r)
		SRD.AoEShape.LINE:
			var w := width if width > 0.0 else K.ft(5)
			return _in_square(origin + dir * size * 0.5, dir, size, w, r)
		SRD.AoEShape.CONE:
			for p in _probe(r, origin):
				var v := p - origin
				var along := v.dot(dir)
				if along < -EPS or along > size + EPS:
					continue
				if absf(v.cross(dir)) <= along * 0.5 + EPS:
					return true
			return false
	return false

## Oriented rectangle (centre c, long axis dir, length len, width w) vs box r, by probes.
static func _in_square(c: Vector2, dir: Vector2, length: float, w: float, r: Rect2) -> bool:
	for p in _probe(r, c):
		var v := p - c
		if absf(v.dot(dir)) <= length * 0.5 + EPS and absf(v.cross(dir)) <= w * 0.5 + EPS:
			return true
	return false

## Points of r to test against a shape: a 5x5 grid plus the point nearest the shape's anchor.
static func _probe(r: Rect2, anchor: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = [nearest(r, anchor)]
	for j in 5:
		for i in 5:
			out.append(r.position + Vector2(r.size.x * i * 0.25, r.size.y * j * 0.25))
	return out

## Launch direction for a projectile of `speed` under `gravity` to pass through `to`:
## the lower of the two ballistic solutions, or straight at it when out of reach.
static func ballistic_dir(from: Vector2, to: Vector2, speed: float, gravity: float) -> Vector2:
	var d := to - from
	if gravity <= 0.0 or absf(d.x) < 0.01:
		return d.normalized() if d.length() > 0.0 else Vector2.RIGHT
	var x := absf(d.x)
	var v2 := speed * speed
	var disc := v2 * v2 - gravity * (gravity * x * x + 2.0 * d.y * v2)
	if disc < 0.0:
		return Vector2(signf(d.x), 1.0).normalized()
	var ang := atan((v2 - sqrt(disc)) / (gravity * x))
	return Vector2(cos(ang) * signf(d.x), sin(ang))

## Where a line from `from` toward `to` stops: `to`, or just before the first solid tile.
static func reach_point(world: TileWorld, from: Vector2, to: Vector2) -> Vector2:
	var hit := TileCollision.raycast(world, from, to)
	if not hit["hit"]:
		return to
	var d := (to - from).normalized()
	return Vector2(hit["point"]) - d * 0.05
