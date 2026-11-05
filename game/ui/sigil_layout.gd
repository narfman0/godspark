## Where the constellation's stars are drawn. Kindled stars keep the grid spot the host gave
## them (Constellation._spot: from the character's name and kindling order, mirrored in STARS),
## nudged by a small jitter hashed from the name so the drawing is not stuck to a grid. Empty
## slots are faint rings at the spots the next stars will take (the same _spot rule, run
## ahead on a copy), so each character's drawing is its own and stable.
##
##   var lay := SigilLayout.layout("ann", con.kindled, con.slots, Vector2(400, 400))
##   lay.stars[i], lay.ghosts[j], lay.lines (pairs of star indices)
##   SigilLayout.image(sigil, 64)        # the holy-symbol texture
class_name SigilLayout
extends RefCounted

const GRID := Constellation.GRID
const JITTER := 0.28    ## of a grid cell

## Map a grid spot to a point in a box of `size` (with a margin), jittered by name.
static func to_point(at: Vector2i, name: String, size: Vector2) -> Vector2:
	var h := hash("%s|%d|%d" % [name, at.x, at.y])
	var j := Vector2(float(h & 0xff) / 255.0 - 0.5, float((h >> 8) & 0xff) / 255.0 - 0.5) * JITTER
	var cell := (size * 0.86) / GRID
	return size * 0.07 + (Vector2(at) + Vector2(0.5, 0.5) + j) * cell

## {stars: [Vector2], ghosts: [Vector2], lines: [[a, b]], cells: [Vector2i]} for a box of `size`.
static func layout(name: String, kindled: Array, slots: int, size: Vector2) -> Dictionary:
	var stars: Array = []
	var cells: Array = []
	var lines: Array = []
	for i in kindled.size():
		var at: Array = kindled[i]["at"]
		var cell := Vector2i(int(at[0]), int(at[1]))
		cells.append(cell)
		stars.append(to_point(cell, name, size))
		if i > 0:
			lines.append([i - 1, i])
	var ghosts: Array = []
	if slots > kindled.size():
		var con := Constellation.new()
		con.salt = name
		for k: Dictionary in kindled:
			con.kindled.append({"id": k["id"], "rank": k.get("rank", 0), "at": k["at"]})
		for n in range(kindled.size(), slots):
			var at2: Array = con._spot(n)
			con.kindled.append({"id": "_ghost%d" % n, "rank": 0, "at": at2})
			ghosts.append(to_point(Vector2i(int(at2[0]), int(at2[1])), name, size))
	return {"stars": stars, "ghosts": ghosts, "lines": lines, "cells": cells}

## The smallest distance between any two points (stars and ghosts).
static func min_gap(lay: Dictionary) -> float:
	var pts: Array = (lay["stars"] as Array) + (lay["ghosts"] as Array)
	var best := INF
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			best = minf(best, (pts[i] as Vector2).distance_to(pts[j]))
	return best

## A small drawing of a sigil ({stars: [Vector2i], lines}) in a disc of radius r at c (HUD).
static func draw_small(ci: CanvasItem, sigil: Dictionary, c: Vector2, r: float, slots := 0) -> void:
	var stars: Array = sigil.get("stars", [])
	if stars.is_empty():
		# no star yet: a faint ring for each open slot hint
		for i in mini(slots, 3):
			var a := TAU * i / 3.0 - PI * 0.5
			ci.draw_arc(c + Vector2(cos(a), sin(a)) * r * 0.45, 3.0, 0, TAU, 10, Color(UiTheme.STARLIGHT, 0.35), 1.0, true)
		return
	var pts: Array = []
	for s: Vector2i in stars:
		pts.append(c + (Vector2(s) + Vector2(0.5, 0.5) - Vector2(GRID, GRID) * 0.5) / (GRID * 0.5) * r)
	for l: Array in sigil.get("lines", []):
		ci.draw_line(pts[l[0]], pts[l[1]], Color(UiTheme.STARLIGHT, 0.75), 1.5, true)
	for p: Vector2 in pts:
		UiTheme.star(ci, p, 4.5, 1.6, UiTheme.STARLIGHT, 4, Color(0, 0, 0, 0))

## The sigil as an image (white strokes on transparent): the character's holy symbol.
static func image(sigil: Dictionary, size := 64) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var stars: Array = sigil.get("stars", [])
	var pts: Array = []
	for s: Vector2i in stars:
		pts.append((Vector2(s) + Vector2(0.5, 0.5)) / GRID * (size * 0.8) + Vector2.ONE * size * 0.1)
	for l: Array in sigil.get("lines", []):
		_line(img, pts[l[0]], pts[l[1]], Color(1, 0.95, 0.75, 0.9))
	for p: Vector2 in pts:
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if absi(dx) + absi(dy) <= 2:
					var q := Vector2i(p) + Vector2i(dx, dy)
					if q.x >= 0 and q.y >= 0 and q.x < size and q.y < size:
						img.set_pixelv(q, Color(1, 1, 0.9, 1))
	return img

static func _line(img: Image, a: Vector2, b: Vector2, col: Color) -> void:
	var n := maxi(1, ceili(a.distance_to(b)))
	for i in n + 1:
		var p := Vector2i(a.lerp(b, float(i) / n))
		if p.x >= 0 and p.y >= 0 and p.x < img.get_width() and p.y < img.get_height():
			img.set_pixelv(p, col)
