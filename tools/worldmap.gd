## Writes a PNG of a generated world: tiles by colour, background walls darker, sky above
## the surface, sites, route paths (rough ones red) and places (street, building outlines) on top. One pixel per tile up to 2048 wide; larger worlds
## are sampled down. Prints stage timings and a site/route summary.
##   godot --headless -s res://tools/worldmap.gd -- seed=1 size=dev out=/tmp/map.png
##   (also: w=1024 h=512 instead of size, crop=x0,y0,x1,y1 for a 1:1 detail view)
extends SceneTree

const SITE_COLORS := {
	"settlement": Color(1.0, 0.95, 0.3),
	"lair": Color(0.95, 0.15, 0.15),
	"ruin": Color(0.75, 0.4, 1.0),
	"portal": Color(1.0, 0.2, 0.9),
}
const DEEP_TOWN := Color(0.2, 1.0, 1.0)
const ROUTE_COLORS := {"road": Color(1.0, 0.85, 0.2), "deep_road": Color(1.0, 0.5, 0.1)}
const ROUGH := Color(1.0, 0.2, 0.2)
const KIND_COLORS := {"home": Color(0.95, 0.85, 0.6), "smithy": Color(1.0, 0.4, 0.1), "market": Color(1.0, 0.9, 0.2),
	"tavern": Color(0.9, 0.5, 0.9), "shrine": Color(0.7, 0.8, 1.0), "gate": Color(0.6, 0.6, 0.6), "hall": Color(1.0, 0.3, 0.3),
	"store": Color(0.4, 0.9, 0.5), "ruin": Color(0.5, 0.4, 0.4)}
const SKY_TOP := Color(0.35, 0.55, 0.85)
const SKY_LOW := Color(0.7, 0.82, 0.95)
const VOID := Color(0.06, 0.05, 0.08)

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var seed_value := int(args.get("seed", "1"))
	var size: Vector2i = WorldGen.SIZES.get(args.get("size", "dev"), WorldGen.SIZES["dev"])
	if args.has("w"):
		size = Vector2i(int(args["w"]), int(args["h"]))
	var out: String = args.get("out", "user://worldmap.png")
	var world := WorldGen.generate(size.x, size.y, seed_value)
	print("generated %dx%d seed %d in %d ms" % [size.x, size.y, seed_value, WorldGen.last_timings["total"]])
	print("  stages (ms): ", WorldGen.last_timings)
	var img := render(world, args.get("crop", ""))
	var err := img.save_png(out)
	print("wrote ", out, " (", img.get_width(), "x", img.get_height(), ") err=", err)
	_summary(world)
	quit(0 if err == OK else 1)

static func render(world: TileWorld, crop := "") -> Image:
	TileDefs.ensure()
	var g := WorldGen.grids(world)
	var fg: PackedByteArray = g[0]
	var bg: PackedByteArray = g[1]
	var surf: Array = world.meta.get("surface", [])
	var W := world.width
	var H := world.height
	var x0 := 0
	var y0 := 0
	var x1 := W - 1
	var y1 := H - 1
	var k := maxi(1, ceili(W / 2048.0))
	if crop != "":
		var p := crop.split(",")
		x0 = int(p[0]); y0 = int(p[1]); x1 = int(p[2]); y1 = int(p[3])
		k = 1
	var ow := (x1 - x0 + 1) / k
	var oh := (y1 - y0 + 1) / k
	# Colour lookup tables, 3 bytes per id.
	var tile_rgb := PackedByteArray()
	tile_rgb.resize(256 * 3)
	var wall_rgb := PackedByteArray()
	wall_rgb.resize(256 * 3)
	for i in TileDefs.colors.size():
		var col := TileDefs.colors[i]
		tile_rgb[i * 3] = col.r8; tile_rgb[i * 3 + 1] = col.g8; tile_rgb[i * 3 + 2] = col.b8
	for i in TileDefs.wall_colors.size():
		var col := TileDefs.wall_colors[i].darkened(0.35)
		wall_rgb[i * 3] = col.r8; wall_rgb[i * 3 + 1] = col.g8; wall_rgb[i * 3 + 2] = col.b8
	var sky := PackedByteArray()
	sky.resize(H * 3)
	for y in H:
		var col := SKY_LOW.lerp(SKY_TOP, float(y) / H)
		sky[y * 3] = col.r8; sky[y * 3 + 1] = col.g8; sky[y * 3 + 2] = col.b8
	var rgb := PackedByteArray()
	rgb.resize(ow * oh * 3)
	var o := 0
	for oy in oh:
		var y := y1 - oy * k
		for ox in ow:
			var x := x0 + ox * k
			var i := x + y * W
			var id := fg[i]
			if id != 0:
				rgb[o] = tile_rgb[id * 3]; rgb[o + 1] = tile_rgb[id * 3 + 1]; rgb[o + 2] = tile_rgb[id * 3 + 2]
			elif bg[i] != 0:
				var wid := bg[i]
				rgb[o] = wall_rgb[wid * 3]; rgb[o + 1] = wall_rgb[wid * 3 + 1]; rgb[o + 2] = wall_rgb[wid * 3 + 2]
			elif surf.is_empty() or y > int(surf[x]):
				rgb[o] = sky[y * 3]; rgb[o + 1] = sky[y * 3 + 1]; rgb[o + 2] = sky[y * 3 + 2]
			else:
				rgb[o] = VOID.r8; rgb[o + 1] = VOID.g8; rgb[o + 2] = VOID.b8
			o += 3
	var img := Image.create_from_data(ow, oh, false, Image.FORMAT_RGB8, rgb)
	var to_px := func(x: float, y: float) -> Vector2i:
		return Vector2i(int((x - x0) / k), int((y1 - y) / k))
	var sites := {}
	for s: Dictionary in world.meta.get("sites", []):
		sites[int(s["id"])] = s
	for r: Dictionary in world.meta.get("routes", []):
		var a: Dictionary = sites[int(r["a"])]
		var b: Dictionary = sites[int(r["b"])]
		var col: Color = ROUTE_COLORS.get(r["kind"], Color.WHITE)
		if r.get("rough", false):
			col = ROUGH
		var path: Array = r.get("path", [])
		if path.size() >= 2:   # the stored feet-cell path, drawn a little above the ground
			for i in range(1, path.size()):
				_line(img, to_px.call(path[i - 1][0], path[i - 1][1] + 1), to_px.call(path[i][0], path[i][1] + 1), col)
		else:
			_line(img, to_px.call(a["x"], a["y"] + 2), to_px.call(b["x"], b["y"] + 2), col)
	# places: the street (white) and each building's outline (by kind)
	for key: String in world.meta.get("places", {}):
		var pl: Dictionary = world.meta["places"][key]
		var st: Array = pl.get("street", [])
		if st.size() == 3:
			_line(img, to_px.call(st[0], st[2] - 1), to_px.call(st[1], st[2] - 1), Color.WHITE)
		for bld: Dictionary in pl.get("buildings", []):
			var rc: Array = bld["rect"]
			var kc: Color = KIND_COLORS.get(bld["kind"], Color.WHITE)
			var p0: Vector2i = to_px.call(rc[0], rc[1])
			var p1: Vector2i = to_px.call(int(rc[0]) + int(rc[2]) - 1, int(rc[1]) + int(rc[3]) - 1)
			for e: Array in [[p0, Vector2i(p1.x, p0.y)], [Vector2i(p0.x, p1.y), p1], [p0, Vector2i(p0.x, p1.y)], [Vector2i(p1.x, p0.y), p1]]:
				_line(img, e[0], e[1], kc)
	for s: Dictionary in sites.values():
		var col: Color = SITE_COLORS.get(s["kind"], Color.WHITE)
		if s["kind"] == "settlement" and s["band"] != "surface":
			col = DEEP_TOWN
		var p: Vector2i = to_px.call(s["x"], s["y"] + 2)
		var r := 4 if k == 1 else 3
		img.fill_rect(Rect2i(p.x - r - 1, p.y - r - 1, 2 * r + 3, 2 * r + 3), Color.BLACK)
		img.fill_rect(Rect2i(p.x - r, p.y - r, 2 * r + 1, 2 * r + 1), col)
	return img

static func _line(img: Image, a: Vector2i, b: Vector2i, col: Color) -> void:
	var n := maxi(absi(b.x - a.x), absi(b.y - a.y))
	for i in n + 1:
		var t := float(i) / maxf(1.0, n)
		var x := roundi(lerpf(a.x, b.x, t))
		var y := roundi(lerpf(a.y, b.y, t))
		for d: Vector2i in [Vector2i.ZERO, Vector2i(0, 1)]:
			if x + d.x >= 0 and y + d.y >= 0 and x + d.x < img.get_width() and y + d.y < img.get_height():
				img.set_pixel(x + d.x, y + d.y, col)

func _summary(world: TileWorld) -> void:
	var m := world.meta
	print("bands: ", m["bands"])
	print("biomes: ", m["biomes"])
	for s: Dictionary in m["sites"]:
		print("  site ", s)
	for r: Dictionary in m["routes"]:
		print("  route ", r)
