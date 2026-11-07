## What a body carries for light, from data/looks.json "lights": a row per item slug (a hotbar
## item held, or worn gear), per effect ("effect:<what>", from combat EFFECT events) and per
## carried look ("torch": townsfolk, guards and raiders at night). Pure; the view asks it.
## Nothing here touches the rules: the host's sight (core/combat/combat_sight.gd) decides what
## a creature can see, this only decides what the picture lights.
##
##   var l := LightSources.own(items.hotbar()[items.selected()], items.equipment.worn, items.tags(), effects)
##   if not l.is_empty(): light.add_light(id, x, y, l["level"])    # l.color, l.radius (tiles)
##
## Rows: level (LightEngine strength: DIM_MIN + 5 per tile of reach, a torch 85), color (hex),
## radius (tiles the view's lamp reaches; defaults to the level's reach). "tag:light" is the glow
## of the `light` tag (a Lantern spark, glowing gear) when nothing else is held: level = its level
## plus per_point for every point; with a held light each point widens it one tile instead.
class_name LightSources
extends RefCounted

const TORCH_TINT := Color(1.0, 0.66, 0.36)

static func table() -> Dictionary:
	return Looks.table().get("lights", {})

## A row as {level, color, radius, key}; {} when the key has none.
static func row(key: String) -> Dictionary:
	var r: Variant = table().get(key)
	if not (r is Dictionary):
		return {}
	var level := clampi(int(r.get("level", LightEngine.TORCH)), 0, LightEngine.MAX)
	return {"level": level, "color": Color(String(r.get("color", "#ffa85c"))),
		"radius": float(r.get("radius", reach(level))), "key": key}

## Tiles a level reaches before it is Darkness.
static func reach(level: int) -> float:
	return maxf(0.0, float(level - LightEngine.DIM_MIN) / LightEngine.STEP)

## The row for an item record: its magic slug, then its base ({} if neither is a light).
static func of_item(item: Dictionary) -> Dictionary:
	if item.is_empty():
		return {}
	var r := row(String(item.get("magic", "")))
	return r if not r.is_empty() else row(String(item.get("base", "")))

## The own light: the strongest of the selected hotbar item, everything worn (the off hand
## among it) and the active effects, widened by the `light` tag; with none of them the tag's
## own glow; with no tag either, {}: the player lights nothing.
static func own(selected: Dictionary, worn: Dictionary, tags: Dictionary, effects: Array) -> Dictionary:
	var best := of_item(selected)
	for slot: String in worn:
		best = _stronger(best, of_item(worn[slot]))
	for what: String in effects:
		best = _stronger(best, row("effect:" + what.trim_prefix("concentration:")))
	var extra := float(tags.get("light", 0.0))
	if best.is_empty():
		if extra <= 0.0:
			return {}
		var glow := row("tag:light")
		if glow.is_empty():
			glow = {"level": LightEngine.DIM_MIN, "color": TORCH_TINT, "radius": 0.0, "key": "tag:light"}
		var per := int(table().get("tag:light", {}).get("per_point", LightEngine.STEP))
		glow["level"] = mini(LightEngine.MAX, int(glow["level"]) + roundi(extra * per))
		glow["radius"] = reach(int(glow["level"]))
		return glow
	if extra > 0.0:
		best["level"] = mini(LightEngine.MAX, int(best["level"]) + roundi(extra * LightEngine.STEP))
		best["radius"] = float(best["radius"]) + extra
	return best

## The own light from an items mirror: the selected hotbar slot, the worn gear, the tags (once
## the host has spoken), and the effects on.
static func of_items(items: ItemsClient, effects: Array) -> Dictionary:
	if items == null:
		return own({}, {}, {}, effects)
	var sel: Dictionary = items.item(items.selected()) if items.selected() >= 0 else {}
	return own(sel, items.equipment.worn, items.tags() if items.live else {}, effects)

static func _stronger(a: Dictionary, b: Dictionary) -> Dictionary:
	if b.is_empty():
		return a
	if a.is_empty() or int(b["level"]) > int(a["level"]):
		return b
	return a

## View tunables: data/lighting.json "view".
static var _view := {}
static func view() -> Dictionary:
	if _view.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/lighting.json"))
		_view = d.get("view", {}) if d is Dictionary else {}
		if _view.is_empty():
			_view = {"_": true}
	return _view

static func setting(key: String, fallback: Variant) -> Variant:
	return view().get(key, fallback)
