## Procedural item icons (there is no icon art yet). One shape per category (blade, bow,
## armour, ring, potion, block, ore, spark ...), coloured from the material, the tile or the
## rarity, drawn in ink: a dark outline around flat colour. Rasterised once per (category,
## colour) into a small ImageTexture and cached, so the inventory, hotbar, tooltips and the
## drops on the ground all share them.
##
## To use real icons later, replace texture(): everything else asks only for a Texture2D.
##
##   ItemIcons.category({"base": "longsword"})        # "blade"
##   ItemIcons.texture(item)                           # Texture2D, 48x48
##   ItemIcons.rarity(item); ItemIcons.rarity_color(item)
class_name ItemIcons
extends RefCounted

const SIZE := 48
const OUTLINE := 0.045      ## ink outline width, in icon units (0..1)

const WOOD := Color("8a5a2b")
const STEEL := Color("b9bec6")
const BRASS := Color("d9a43b")
const FLAME := Color("ff9a2e")
const CORK := Color("a8763e")
const LINEN := Color("efe6cf")

## Ordinary materials (data/items/materials.json keys) and crafting materials.
const MATERIAL_COLORS := {
	"copper": Color("c8743c"), "iron": Color("9aa2ab"), "silver": Color("dfe4ea"),
	"mithral": Color("8fd0e8"), "adamantine": Color("5d4f7a"),
	"ingot:copper": Color("c8743c"), "ingot:iron": Color("9aa2ab"), "ingot:silver": Color("dfe4ea"),
	"ingot:mithral": Color("8fd0e8"), "ingot:adamantine": Color("5d4f7a"),
	"cloth": Color("d8cdb0"), "leather": Color("8b5a33"), "bone": Color("e8dfc6"), "ichor": Color("7bd35a"),
	"gem": Color("d14fa0"),
}
const SPARK_GROUP_COLORS := {"motion": Color("ffd75e"), "senses": Color("8fe3ff"), "tempo": Color("ff9e6b"), "bonds": Color("c69bff")}

const AXES := ["handaxe", "battleaxe", "greataxe"]
const BLUNT := ["club", "greatclub", "mace", "maul", "warhammer", "light-hammer", "morningstar", "flail", "sling"]
const POLEARMS := ["spear", "pike", "glaive", "halberd", "lance", "trident", "javelin"]
const DAGGERS := ["dagger", "dart", "sickle", "whip", "blowgun", "net"]
const BOWS := ["shortbow", "longbow"]

static var _cache := {}

## The icon category of an item record.
static func category(item: Dictionary) -> String:
	if item.is_empty():
		return "empty"
	if item.has("spark"):
		return "spark"
	var base := String(item.get("base", ""))
	if base == "coin":
		return "coin"
	if base.begins_with("tile:"):
		var t := base.trim_prefix("tile:")
		if t in ["torch", "campfire", "bed", "ladder", "platform", "shrine"]:
			return t
		if t.contains("ore"):
			return "ore"
		return "block"
	if base.begins_with("ingot:"):
		return "ingot"
	if base in ["cloth", "leather"]:
		return "cloth"
	if base == "bone":
		return "bone"
	if base == "gem":
		return "gem"
	if base == "ichor":
		return "potion"
	var row := Items.row(base)
	var k := String(row.get("kind", ""))
	if k == "weapon":
		if base in BOWS:
			return "bow"
		if base.begins_with("crossbow"):
			return "crossbow"
		if base in AXES:
			return "axe"
		if base in BLUNT:
			return "blunt"
		if base in POLEARMS:
			return "polearm"
		if base == "quarterstaff":
			return "staff"
		if base in DAGGERS:
			return "dagger"
		if base in ["musket", "pistol"]:
			return "crossbow"
		return "blade"
	if k == "shield":
		return "shield"
	if k == "armor":
		return "armor"
	var magic := String(item.get("magic", ""))
	if magic.contains("scroll"):
		return "scroll"
	if magic.begins_with("potion") or Items.use_of(item).has("heal"):
		return "potion"
	match Items.slot_kind(item):
		"ring":
			return "ring"
		"neck":
			return "amulet"
		"head":
			return "helm"
		"cloak":
			return "cloak"
		"hands":
			return "gloves"
		"belt":
			return "belt"
		"feet":
			return "boots"
		"armor":
			return "armor"
		"off_hand":
			return "wand"
		"main_hand":
			return "staff"
	var mk := Items.kind(item)
	if mk == "consumable":
		return "potion"
	if mk == "focus":
		return "wand"
	return "trinket"

## "spark", an SRD rarity for magic items, "fine" for ordinary gear with affixes, else "".
static func rarity(item: Dictionary) -> String:
	if item.has("spark"):
		return "spark"
	if item.has("magic"):
		return Items.rarity_of(String(item["magic"]), int(item.get("tier", 0)))
	if not (item.get("affixes", []) as Array).is_empty():
		return "fine"
	return ""

static func rarity_color(item: Dictionary) -> Color:
	return UiTheme.RARITY.get(rarity(item), UiTheme.INK_SOFT)

## The icon's main colour: a block's tile colour, a material's, a spark's group, a magic item's rarity.
static func color(item: Dictionary) -> Color:
	var cat := category(item)
	if item.has("spark"):
		var g := String(Sparks.row(String(item["spark"].get("id", ""))).get("group", "motion"))
		return SPARK_GROUP_COLORS.get(g, UiTheme.GOLD)
	var base := String(item.get("base", ""))
	if base.begins_with("tile:"):
		var tid := Items.tile_of(item)
		if tid > 0 and tid < TileDefs.colors.size():
			return TileDefs.colors[tid]
		return UiTheme.PARCH_DEEP
	if MATERIAL_COLORS.has(base):
		return MATERIAL_COLORS[base]
	if cat == "coin":
		return BRASS
	if cat == "potion":
		var u := Items.use_of(item)
		return UiTheme.VERMILION if u.has("heal") else Color("6fb0d8")
	if item.has("magic") and not cat in ["blade", "axe", "blunt", "polearm", "dagger", "armor", "shield", "bow", "crossbow"]:
		return UiTheme.RARITY.get(rarity(item), UiTheme.PLUM)
	if item.has("material"):
		return MATERIAL_COLORS.get(String(item["material"]), STEEL)
	match cat:
		"armor":
			return Color("9a6b3e") if not Items.takes_material(base) else STEEL
		"shield", "staff", "bow", "crossbow":
			return WOOD.lightened(0.15)
	return STEEL

## Whether drops and slots show a glint: sparks and magic items.
static func glints(item: Dictionary) -> bool:
	return item.has("spark") or item.has("magic")

## The cached icon texture for an item.
static func texture(item: Dictionary) -> Texture2D:
	var cat := category(item)
	var c := color(item)
	var key := "%s|%s" % [cat, c.to_html(false)]
	var tex: Texture2D = _cache.get(key)
	if tex == null:
		tex = ImageTexture.create_from_image(render(cat, c))
		_cache[key] = tex
	return tex

static func cache_size() -> int:
	return _cache.size()

# --- shapes -------------------------------------------------------------------------------
# A shape is a list of layers drawn back to front: [primitive, colour]. Primitives, in icon
# units (0..1, y down): ["c", centre, r] circle; ["b", centre, half, round] box; ["s", a, b, r]
# capsule; ["p", PackedVector2Array] polygon; ["r", centre, r, t] ring.

static func shape(cat: String, m: Color) -> Array:
	var d := m.darkened(0.35)
	var l := m.lightened(0.35)
	var V := func(x: float, y: float) -> Vector2: return Vector2(x, y)
	match cat:
		"blade":
			return [[["s", V.call(0.14, 0.86), V.call(0.27, 0.73), 0.05], WOOD], [["c", V.call(0.12, 0.88), 0.065], BRASS],
				[["p", PackedVector2Array([V.call(0.3, 0.62), V.call(0.78, 0.14), V.call(0.88, 0.12), V.call(0.86, 0.22), V.call(0.38, 0.70)])], m],
				[["s", V.call(0.2, 0.56), V.call(0.44, 0.80), 0.045], d]]
		"dagger":
			return [[["s", V.call(0.22, 0.80), V.call(0.34, 0.68), 0.05], WOOD],
				[["p", PackedVector2Array([V.call(0.38, 0.56), V.call(0.74, 0.22), V.call(0.80, 0.20), V.call(0.78, 0.27), V.call(0.44, 0.62)])], m],
				[["s", V.call(0.30, 0.52), V.call(0.48, 0.70), 0.045], d]]
		"axe":
			return [[["s", V.call(0.28, 0.9), V.call(0.62, 0.14), 0.045], WOOD],
				[["p", PackedVector2Array([V.call(0.5, 0.2), V.call(0.8, 0.08), V.call(0.9, 0.3), V.call(0.84, 0.48), V.call(0.56, 0.36)])], m]]
		"blunt":
			return [[["s", V.call(0.22, 0.86), V.call(0.56, 0.4), 0.05], WOOD], [["c", V.call(0.64, 0.3), 0.19], m],
				[["c", V.call(0.58, 0.24), 0.06], l]]
		"polearm":
			return [[["s", V.call(0.14, 0.92), V.call(0.7, 0.28), 0.04], WOOD],
				[["p", PackedVector2Array([V.call(0.62, 0.3), V.call(0.88, 0.08), V.call(0.72, 0.4)])], m]]
		"staff":
			return [[["s", V.call(0.24, 0.92), V.call(0.66, 0.2), 0.05], WOOD], [["c", V.call(0.7, 0.16), 0.11], m],
				[["c", V.call(0.67, 0.13), 0.04], l]]
		"wand":
			return [[["s", V.call(0.24, 0.82), V.call(0.66, 0.32), 0.04], WOOD], [["p", _star_pts(V.call(0.72, 0.26), 0.17, 0.07, 4)], m]]
		"bow":
			var arc: Array = []
			for i in 6:
				var a0 := -1.15 + 2.3 * i / 6.0
				var a1 := -1.15 + 2.3 * (i + 1) / 6.0
				arc.append([["s", V.call(0.22 + cos(a0) * 0.42, 0.5 + sin(a0) * 0.42), V.call(0.22 + cos(a1) * 0.42, 0.5 + sin(a1) * 0.42), 0.05], m])
			return [[["s", V.call(0.39, 0.12), V.call(0.39, 0.88), 0.012], UiTheme.INK]] + arc
		"crossbow":
			return [[["s", V.call(0.2, 0.62), V.call(0.84, 0.42), 0.06], WOOD],
				[["s", V.call(0.6, 0.16), V.call(0.72, 0.84), 0.045], m], [["s", V.call(0.62, 0.18), V.call(0.62, 0.84), 0.012], UiTheme.INK]]
		"armor":
			return [[["p", PackedVector2Array([V.call(0.3, 0.14), V.call(0.42, 0.2), V.call(0.58, 0.2), V.call(0.7, 0.14), V.call(0.88, 0.3),
				V.call(0.76, 0.44), V.call(0.72, 0.86), V.call(0.28, 0.86), V.call(0.24, 0.44), V.call(0.12, 0.3)])], m],
				[["s", V.call(0.5, 0.36), V.call(0.5, 0.78), 0.02], d]]
		"shield":
			return [[["p", PackedVector2Array([V.call(0.18, 0.16), V.call(0.82, 0.16), V.call(0.8, 0.52), V.call(0.5, 0.9), V.call(0.2, 0.52)])], m],
				[["c", V.call(0.5, 0.44), 0.11], d], [["c", V.call(0.47, 0.41), 0.04], l]]
		"helm":
			return [[["p", _half_disc(V.call(0.5, 0.62), 0.34)], m], [["b", V.call(0.5, 0.66), V.call(0.4, 0.07), 0.03], d],
				[["b", V.call(0.5, 0.48), V.call(0.04, 0.16), 0.0], d]]
		"ring":
			return [[["r", V.call(0.5, 0.6), 0.24, 0.07], BRASS], [["p", _star_pts(V.call(0.5, 0.3), 0.15, 0.1, 6)], m]]
		"amulet":
			return [[["r", V.call(0.5, 0.36), 0.26, 0.025], BRASS], [["p", PackedVector2Array([V.call(0.5, 0.48), V.call(0.68, 0.68), V.call(0.5, 0.9), V.call(0.32, 0.68)])], m]]
		"cloak":
			return [[["p", PackedVector2Array([V.call(0.4, 0.12), V.call(0.6, 0.12), V.call(0.86, 0.88), V.call(0.14, 0.88)])], m],
				[["c", V.call(0.5, 0.2), 0.12], d], [["s", V.call(0.4, 0.4), V.call(0.3, 0.84), 0.02], d], [["s", V.call(0.6, 0.4), V.call(0.7, 0.84), 0.02], d]]
		"gloves":
			return [[["b", V.call(0.5, 0.62), V.call(0.22, 0.24), 0.08], m], [["s", V.call(0.34, 0.4), V.call(0.34, 0.16), 0.06], m],
				[["s", V.call(0.48, 0.38), V.call(0.48, 0.12), 0.06], m], [["s", V.call(0.62, 0.4), V.call(0.62, 0.16), 0.06], m],
				[["s", V.call(0.74, 0.62), V.call(0.86, 0.44), 0.06], m], [["b", V.call(0.5, 0.84), V.call(0.24, 0.06), 0.02], d]]
		"belt":
			return [[["b", V.call(0.5, 0.5), V.call(0.44, 0.1), 0.03], m], [["r", V.call(0.5, 0.5), 0.13, 0.04], BRASS]]
		"boots":
			return [[["p", PackedVector2Array([V.call(0.3, 0.14), V.call(0.58, 0.14), V.call(0.58, 0.6), V.call(0.88, 0.7), V.call(0.88, 0.86), V.call(0.3, 0.86)])], m],
				[["b", V.call(0.44, 0.2), V.call(0.16, 0.06), 0.02], d]]
		"potion":
			return [[["c", V.call(0.5, 0.62), 0.26], m], [["b", V.call(0.5, 0.3), V.call(0.08, 0.12), 0.02], LINEN.darkened(0.1)],
				[["b", V.call(0.5, 0.16), V.call(0.1, 0.05), 0.02], CORK], [["c", V.call(0.42, 0.54), 0.06], l]]
		"scroll":
			return [[["b", V.call(0.5, 0.5), V.call(0.3, 0.26), 0.02], LINEN], [["s", V.call(0.2, 0.2), V.call(0.2, 0.8), 0.07], LINEN.darkened(0.15)],
				[["s", V.call(0.8, 0.2), V.call(0.8, 0.8), 0.07], LINEN.darkened(0.15)], [["s", V.call(0.34, 0.38), V.call(0.66, 0.38), 0.015], m],
				[["s", V.call(0.34, 0.52), V.call(0.62, 0.52), 0.015], m]]
		"block", "shrine":
			return [[["b", V.call(0.5, 0.52), V.call(0.34, 0.34), 0.05], m], [["b", V.call(0.5, 0.24), V.call(0.3, 0.05), 0.02], l],
				[["s", V.call(0.3, 0.5), V.call(0.44, 0.5), 0.015], d], [["s", V.call(0.56, 0.7), V.call(0.7, 0.7), 0.015], d]]
		"ore":
			return [[["b", V.call(0.5, 0.52), V.call(0.34, 0.34), 0.05], Color("6d6a66")], [["c", V.call(0.36, 0.4), 0.09], m],
				[["c", V.call(0.62, 0.36), 0.07], m.lightened(0.15)], [["c", V.call(0.56, 0.66), 0.1], m]]
		"ingot":
			return [[["p", PackedVector2Array([V.call(0.24, 0.4), V.call(0.76, 0.4), V.call(0.9, 0.72), V.call(0.1, 0.72)])], m],
				[["b", V.call(0.5, 0.45), V.call(0.22, 0.03), 0.0], l]]
		"gem":
			return [[["p", PackedVector2Array([V.call(0.3, 0.26), V.call(0.7, 0.26), V.call(0.86, 0.42), V.call(0.5, 0.86), V.call(0.14, 0.42)])], m],
				[["p", PackedVector2Array([V.call(0.34, 0.3), V.call(0.5, 0.3), V.call(0.42, 0.42)])], l]]
		"cloth":
			return [[["b", V.call(0.5, 0.58), V.call(0.36, 0.22), 0.06], m], [["c", V.call(0.2, 0.58), 0.18], d], [["c", V.call(0.2, 0.58), 0.06], m]]
		"bone":
			return [[["s", V.call(0.26, 0.74), V.call(0.74, 0.26), 0.07], m], [["c", V.call(0.2, 0.72), 0.09], m], [["c", V.call(0.28, 0.82), 0.09], m],
				[["c", V.call(0.72, 0.18), 0.09], m], [["c", V.call(0.82, 0.28), 0.09], m]]
		"coin":
			return [[["c", V.call(0.4, 0.62), 0.24], m.darkened(0.1)], [["c", V.call(0.6, 0.42), 0.24], m], [["r", V.call(0.6, 0.42), 0.14, 0.02], d]]
		"spark":
			return [[["p", _star_pts(V.call(0.5, 0.5), 0.44, 0.13, 4)], m], [["c", V.call(0.5, 0.5), 0.09], Color(1, 1, 0.95)]]
		"torch":
			return [[["s", V.call(0.4, 0.88), V.call(0.56, 0.4), 0.05], WOOD],
				[["p", PackedVector2Array([V.call(0.58, 0.08), V.call(0.74, 0.32), V.call(0.62, 0.44), V.call(0.46, 0.4), V.call(0.46, 0.26)])], FLAME]]
		"campfire":
			return [[["s", V.call(0.14, 0.86), V.call(0.84, 0.66), 0.06], WOOD], [["s", V.call(0.16, 0.66), V.call(0.86, 0.86), 0.06], WOOD.darkened(0.15)],
				[["p", PackedVector2Array([V.call(0.5, 0.1), V.call(0.72, 0.46), V.call(0.62, 0.68), V.call(0.38, 0.68), V.call(0.28, 0.46)])], FLAME]]
		"bed":
			return [[["b", V.call(0.5, 0.62), V.call(0.4, 0.14), 0.03], m], [["b", V.call(0.24, 0.48), V.call(0.12, 0.08), 0.04], LINEN],
				[["b", V.call(0.12, 0.6), V.call(0.04, 0.26), 0.02], WOOD], [["b", V.call(0.88, 0.7), V.call(0.04, 0.16), 0.02], WOOD]]
		"ladder":
			return [[["s", V.call(0.3, 0.1), V.call(0.3, 0.9), 0.04], WOOD], [["s", V.call(0.7, 0.1), V.call(0.7, 0.9), 0.04], WOOD],
				[["s", V.call(0.3, 0.3), V.call(0.7, 0.3), 0.03], WOOD.lightened(0.1)], [["s", V.call(0.3, 0.5), V.call(0.7, 0.5), 0.03], WOOD.lightened(0.1)],
				[["s", V.call(0.3, 0.7), V.call(0.7, 0.7), 0.03], WOOD.lightened(0.1)]]
		"platform":
			return [[["b", V.call(0.5, 0.44), V.call(0.42, 0.08), 0.02], m], [["s", V.call(0.2, 0.52), V.call(0.2, 0.8), 0.03], WOOD],
				[["s", V.call(0.8, 0.52), V.call(0.8, 0.8), 0.03], WOOD]]
	# trinket: a tied pouch
	return [[["c", V.call(0.5, 0.62), 0.28], m], [["p", PackedVector2Array([V.call(0.36, 0.18), V.call(0.64, 0.18), V.call(0.56, 0.38), V.call(0.44, 0.38)])], m],
		[["s", V.call(0.38, 0.38), V.call(0.62, 0.38), 0.03], d]]

static func _star_pts(c: Vector2, outer: float, inner: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n * 2:
		var a := -PI * 0.5 + PI * i / n
		pts.append(c + Vector2(cos(a), sin(a)) * (outer if i % 2 == 0 else inner))
	return pts

static func _half_disc(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 13:
		var a := PI + PI * i / 12.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts

# --- rasteriser ---------------------------------------------------------------------------

static func render(cat: String, main: Color, size := SIZE) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	if cat == "empty":
		return img
	var layers := shape(cat, main)
	var px := 1.0 / size
	var aa := px * 0.9
	for y in size:
		for x in size:
			var p := Vector2((x + 0.5) * px, (y + 0.5) * px)
			var col := Color(0, 0, 0, 0)
			for layer: Array in layers:
				var d := _sdf(layer[0], p)
				if d > OUTLINE + aa:
					continue
				# outline (ink) under the fill, both anti-aliased on their edges
				var ink_a := clampf((OUTLINE + aa * 0.5 - d) / aa, 0.0, 1.0)
				col = _over(col, Color(UiTheme.INK, ink_a))
				var fill_a := clampf((-d + aa * 0.5) / aa, 0.0, 1.0)
				if fill_a > 0.0:
					var fc: Color = layer[1]
					# a little flat shading: lighter toward the top left
					fc = fc.lerp(fc.lightened(0.18), clampf(0.6 - (p.x + p.y) * 0.5, 0.0, 0.6))
					col = _over(col, Color(fc, fill_a))
			img.set_pixel(x, y, col)
	return img

static func _over(dst: Color, src: Color) -> Color:
	var a := src.a + dst.a * (1.0 - src.a)
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	var rgb := (Vector3(src.r, src.g, src.b) * src.a + Vector3(dst.r, dst.g, dst.b) * dst.a * (1.0 - src.a)) / a
	return Color(rgb.x, rgb.y, rgb.z, a)

static func _sdf(prim: Array, p: Vector2) -> float:
	match String(prim[0]):
		"c":
			return p.distance_to(prim[1]) - float(prim[2])
		"r":
			return absf(p.distance_to(prim[1]) - float(prim[2])) - float(prim[3])
		"b":
			var q: Vector2 = (p - (prim[1] as Vector2)).abs() - (prim[2] as Vector2) + Vector2.ONE * float(prim[3])
			return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - float(prim[3])
		"s":
			var a: Vector2 = prim[1]
			var b: Vector2 = prim[2]
			var pa := p - a
			var ba := b - a
			var h := clampf(pa.dot(ba) / maxf(ba.dot(ba), 1e-9), 0.0, 1.0)
			return (pa - ba * h).length() - float(prim[3])
		"p":
			return _poly_sdf(prim[1], p)
	return 1.0

static func _poly_sdf(v: PackedVector2Array, p: Vector2) -> float:
	var d := (p - v[0]).dot(p - v[0])
	var s := 1.0
	var j := v.size() - 1
	for i in v.size():
		var e := v[j] - v[i]
		var w := p - v[i]
		var b := w - e * clampf(w.dot(e) / e.dot(e), 0.0, 1.0)
		d = minf(d, b.dot(b))
		var c1 := p.y >= v[i].y
		var c2 := p.y < v[j].y
		var c3 := e.x * w.y > e.y * w.x
		if (c1 and c2 and c3) or (not c1 and not c2 and not c3):
			s = -s
		j = i
	return s * sqrt(d)
