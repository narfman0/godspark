extends RefCounted

## Track G: the looks table, its resolver and fallbacks (no art needed: file existence is
## faked), actor bodies, dressing data and scatter, and that every referenced asset path was
## verified against the asset server (tests/data/asset_paths.txt, written by
## tools/fetch_assets.sh --index; offline).
func run(t: TestLog) -> void:
	_schema(t)
	_resolution(t)
	_forge_chain(t)
	_bodies(t)
	_forge_bodies(t)
	_dressing(t)
	_index(t)

static func _none(_p: String) -> bool:
	return false

static func _all(_p: String) -> bool:
	return true

static func _no_forge(p: String) -> bool:
	return not p.begins_with("res://assets/monsters/")

## Forge monsters only: no Synty file at all.
static func _forge_only(p: String) -> bool:
	return p.begins_with("res://assets/monsters/")

## Model files only: no reference character, no clips, no monsters.
static func _models_only(p: String) -> bool:
	return p.begins_with("res://assets/meshes/") and not p.contains("ANIMATION_")

func _schema(t: TestLog) -> void:
	var tab := Looks.table()
	t.check(tab.has("models") and tab.has("looks") and tab.has("clips"), "looks.json parses with models, looks, clips")
	var models: Dictionary = tab["models"]
	var bad := []
	for k: String in tab["looks"]:
		var row: Dictionary = tab["looks"][k]
		if row.has("model") and not models.has(row["model"]):
			bad.append(k)
		if row.has("size_name") and not row["size_name"] in Looks.SIZES:
			bad.append(k + " size_name")
	for k: String in tab["by_type"]:
		var row: Dictionary = tab["by_type"][k]
		if row.has("model") and not models.has(row["model"]):
			bad.append("by_type " + k)
	t.eq(bad, [], "every row names a known model")
	var badm := []
	for k: String in models:
		var m: Dictionary = models[k]
		if not String(m.get("path", "")).begins_with("res://assets/meshes/") or not String(m.get("set", "")) in ["", "masc", "femn"]:
			badm.append(k)
	t.eq(badm, [], "every model has a res://assets/meshes path and a known rig set")
	for s in ["masc", "femn"]:
		t.check(tab["clips"][s].has("idle") and tab["clips"][s].has("run"), "%s clips have idle and run" % s)
	t.eq(tab["by_size"].keys().size(), 6, "by_size covers the six sizes")
	var cr := Looks.creatures()
	t.eq(cr.size(), 330, "looks_creatures has all 330 SRD monsters")
	var odd := 0
	for k: String in cr:
		if not cr[k].get("size", "") in Looks.SIZES:
			odd += 1
	t.eq(odd, 0, "every creature has a known size")

func _resolution(t: TestLog) -> void:
	# Nothing fetched: everything is a primitive, named and sized.
	var p := Looks.resolve({"player": "fighter", "name": "Ash"}, _none)
	t.eq(p["body"], "primitive", "no art: the player is a primitive")
	t.eq(p["key"], "player:fighter", "player key resolves")
	t.check(p["nameplate"] and p["name"] == "Ash", "primitive carries a nameplate with the name")
	var old := Looks.resolve({"kind": "hero", "size": Vector2(1.2, 1.8), "color": Color(0.85, 0.3, 0.25)}, _none)
	t.eq(old["body"], "primitive", "old {kind, size, color} form: primitive")
	t.eq(old["size"], Vector2(1.2, 1.8), "old form keeps its size")
	t.eq(old["color"], Color(0.85, 0.3, 0.25), "old form keeps its colour")
	t.eq(old["name"], "hero", "old form: kind is the name")
	var ab := Looks.resolve({"slug": "aboleth"}, _no_forge)
	t.eq(ab["body"], "primitive", "unlisted aberration with no type model: primitive even with every Synty file")
	t.eq(ab["size"], Vector2(2.5, 3.5), "slug size from the registry: large box")
	t.eq(ab["name"], "Aboleth", "SRD name from the registry")
	t.eq(ab["color"], Color.from_string("#8a7fd0", Color.WHITE), "by_type colour")
	# Order: a slug's own Synty row, then forge, then by_type, then primitive.
	t.eq(Looks.resolve({"slug": "owlbear"}, _all)["body"], "forge", "no row of its own: forge wins when synced")
	t.eq(Looks.resolve({"slug": "goblin-warrior"}, _all)["body"], "synty", "a slug with its own row (goblin): Synty first")
	t.eq(Looks.resolve({"slug": "goblin-warrior"}, _forge_only)["body"], "forge", "its own row without Synty files: forge")
	var g := Looks.resolve({"slug": "goblin-warrior"}, _no_forge)
	t.check(g["body"] == "synty" and g["model"] == "goblin", "no forge: the Synty stand-in")
	t.eq(g["size"], Vector2(1.0, 1.75), "goblin-warrior is small")
	t.eq(Looks.resolve({"slug": "goblin-warrior"}, _none)["body"], "primitive", "nothing fetched: primitive")
	# Key chains
	var d := Looks.resolve({"people": "elf:drow:raider"}, _all)
	t.check(d["body"] == "synty" and d["model"] == "dark_elf", "people:elf:drow:raider -> dark elf")
	t.eq(Looks.resolve({"people": "people:elf:drow:priest"}, _all)["key"], "people:elf:drow:priest", "prefixed people key")
	t.eq(Looks.resolve({"people": "elf:drow:nonesuch"}, _all)["key"], "people:elf:drow", "unknown role falls back to the lineage")
	t.eq(Looks.resolve({"people": "elf:moon:guard"}, _all)["key"], "people:elf", "unknown lineage falls back to the species")
	t.eq(Looks.resolve({"people": "goblin"}, _all)["size"], Vector2(1.0, 1.75), "row size_name: people:goblin is small")
	t.eq(Looks.resolve({"player": "artificer"}, _all)["key"], "player", "unknown class: the player row")
	# by_type for an unlisted slug
	var ml := Looks.resolve({"slug": "mummy-lord"}, _no_forge)
	t.check(ml["body"] == "synty" and ml["model"] == "skeleton", "unlisted undead: by_type skeleton")
	t.check(ml["nameplate"], "a by_type stand-in shows its name")
	# Humanoids need the reference character and an idle clip, static models do not
	t.eq(Looks.resolve({"people": "human:guard"}, _models_only)["body"], "primitive", "humanoid without clips: primitive, not a T-pose")
	t.eq(Looks.resolve({"slug": "wolf"}, _models_only)["body"], "synty", "static Synty animal needs only its model")
	# Heights
	t.eq(Looks.resolve({"people": "halfling"}, _all)["height_m"], 0.95, "row height wins")
	t.eq(Looks.resolve({"slug": "ogre"}, _no_forge)["height_m"], 2.5, "by_size height for a large stand-in")
	t.eq(Looks.resolve({"people": "human:guard", "scale": 1.1}, _all)["height_m"], 1.8 * 1.1, "look scale multiplies")

## The chain after the user's ruling (2026-11-08, docs/plan.md "Decisions"): keep Synty as
## much as possible. A slug with its own Synty row keeps it; forge for slugs with no row of
## their own (over by_type) and for looks.json forge.forge_first; forge as the fallback when the
## Synty files are missing; never forge for people / player looks or quarantined slugs.
func _forge_chain(t: TestLog) -> void:
	t.eq(Looks.resolve({"slug": "owlbear"}, _all)["body"], "forge", "a creature with no row: forge when synced")
	var ogre := Looks.resolve({"slug": "ogre"}, _all)
	t.check(ogre["body"] == "synty" and ogre["model"] == "giant", "a slug's own Synty row beats forge (ogre -> giant)")
	t.eq(Looks.resolve({"slug": "ogre"}, _forge_only)["body"], "forge", "its own row without Synty files: forge")
	t.eq(Looks.resolve({"slug": "ogre"}, _none)["body"], "primitive", "nothing fetched: primitive")
	var hob := Looks.resolve({"slug": "hobgoblin-warrior"}, _all)
	t.check(hob["body"] == "synty" and hob["model"] == "goblin_knight", "a tinted stand-in row is kept too (hobgoblin -> goblin knight)")
	t.eq(hob["tint"], Color.from_string("#d08060", Color.WHITE), "and keeps its tint")
	var hobf := Looks.resolve({"slug": "hobgoblin-warrior"}, _forge_only)
	t.eq(hobf["tint"], Color.WHITE, "a forge body does not take its stand-in row's tint")
	t.eq(hobf["model"], "", "a forge plan names no Synty model")
	var ml := Looks.resolve({"slug": "mummy-lord"}, _all)
	t.eq(ml["body"], "forge", "no row of its own: forge beats the by_type stand-in (undead -> skeleton)")
	# forge_first: the committed list (stand-ins that are plainly wrong)
	var ff: Dictionary = Looks.table()["forge"]["forge_first"]
	t.check(ff.has("goat") and ff.has("polar-bear"), "forge_first holds the goat on its side and the brown polar bear")
	t.eq(Looks.resolve({"slug": "polar-bear"}, _all)["body"], "forge", "a forge_first slug: forge over its row")
	t.eq(Looks.resolve({"slug": "polar-bear"}, _all)["tint"], Color.WHITE, "without the row's tint")
	var pb := Looks.resolve({"slug": "polar-bear"}, _no_forge)
	t.check(pb["body"] == "synty" and pb["model"] == "bear", "a forge_first slug with no forge body: its Synty row")
	t.check(ff.size() <= 12, "forge_first stays short (%d)" % ff.size())
	# Every other slug with its own row stays Synty with every file there.
	var rows: Dictionary = Looks.table()["looks"]
	var cr0 := Looks.creatures()
	var lost := []
	for k: String in rows:
		if cr0.has(k) and not ff.has(k) and Looks.resolve({"slug": k}, _all)["body"] != "synty":
			lost.append(k)
	t.eq(lost, [], "every SRD slug with its own row (not forge_first) draws Synty when its files are there")
	var gd := Looks.resolve({"slug": "guard"}, _all)
	t.check(gd["body"] == "synty" and gd["model"] == "soldier", "a humanoid NPC row stays Synty when its files are there")
	t.eq(Looks.resolve({"slug": "guard"}, _forge_only)["body"], "forge", "a humanoid NPC without Synty files takes the forge body")
	t.eq(Looks.resolve({"slug": "guard"}, _none)["body"], "primitive", "a humanoid NPC with nothing fetched: primitive")
	t.eq(Looks.resolve({"slug": "vampire-familiar"}, _all)["body"], "forge", "a humanoid with no row of its own: forge over by_type")
	t.eq(Looks.resolve({"people": "human:guard"}, _forge_only)["body"], "primitive", "a people look never takes a forge body")
	t.eq(Looks.resolve({"people": "human:guard", "slug": "guard"}, _all)["body"], "synty", "people + slug: Synty person")
	t.eq(Looks.resolve({"player": "fighter", "slug": "knight"}, _forge_only)["body"], "primitive", "a player look never takes a forge body")
	t.eq(Looks.resolve({"slug": "giant-spider", "people": "elf:drow:guard"}, _all)["body"], "forge", "a drow escort's spider (people key, not a humanoid) is a forge spider")
	t.eq(Looks.resolve({"slug": "player:fighter"}, _all)["body"], "synty", "a non-SRD slug never looks for a forge body")
	t.eq(Looks.resolve({"slug": "ogre", "no_forge": true}, _all)["body"], "synty", "no_forge skips the forge link")
	# forge_first and the quarantine, injected (the committed lists change as the forge improves)
	var had := ff.has("ogre")
	ff["ogre"] = "test"
	t.eq(Looks.resolve({"slug": "ogre"}, _all)["body"], "forge", "forge_first: the forge body first")
	t.eq(Looks.resolve({"slug": "ogre"}, _no_forge)["body"], "synty", "forge_first without a forge body: the Synty row")
	if not had:
		ff.erase("ogre")
	var q := Looks.quarantine()
	var hadq := q.has("ogre")
	q["ogre"] = {"reason": "test"}
	t.eq(Looks.resolve({"slug": "ogre"}, _all)["body"], "synty", "quarantined: the next link")
	t.eq(Looks.resolve({"slug": "ogre"}, _forge_only)["body"], "primitive", "quarantined with no Synty: primitive")
	if not hadq:
		q.erase("ogre")
	var hado := q.has("owlbear")
	q["owlbear"] = {"reason": "test"}
	t.check(Looks.resolve({"slug": "owlbear"}, _all)["body"] != "forge", "quarantined, no row: never the forge body")
	if not hado:
		q.erase("owlbear")
	# The committed lists name real creatures.
	var cr := Looks.creatures()
	var odd := []
	for k: String in ff:
		if not cr.has(k):
			odd.append(k)
	for k: String in q:
		if not cr.has(k):
			odd.append(k)
	t.eq(odd, [], "forge_first and data/forge_quarantine.json name SRD slugs")
	for k: String in ff:
		if not Looks.table()["looks"].has(k) or String(ff[k]) == "":
			odd.append(k)
	t.eq(odd, [], "every forge_first slug has a Synty row it overrides, and a reason")

func _bodies(t: TestLog) -> void:
	var mat := ShaderMaterial.new()
	var a := ActorBody.build({"slug": "owlbear"}, mat, _none)
	t.eq(a.kind, "primitive", "ActorBody: primitive with no art")
	t.check(a.nameplate != null and a.nameplate.text == "Owlbear", "ActorBody: nameplate")
	t.eq(a.size, Vector2(2.5, 3.5), "ActorBody: box from the registry size")
	a.update(Vector2(10, 20), -1, "run", Vector2(-8, 0))
	t.eq(a.position, Vector3(10, 20, 0) * K.TILE_M, "feet at the Body's position")
	a.snap_facing()
	t.check(a.turn.rotation.y < 0.0, "facing left yaws toward -X")
	a.update(Vector2(10, 20), 0, "dead")
	t.eq(a.state, "death", "dead is death")
	t.check(absf(a.visual.rotation.z - PI * 0.5) < 1e-4, "a dead primitive lies down")
	a.free()
	var b := Body.for_size("medium")
	t.eq(ActorBody.state_for(b), "fall", "airborne, not rising: fall")
	b.on_floor = true
	t.eq(ActorBody.state_for(b), "idle", "standing: idle")
	b.vel = Vector2(5, 0)
	t.eq(ActorBody.state_for(b), "run", "moving: run")
	b.climbing = true
	t.eq(ActorBody.state_for(b), "climb", "on a ladder: climb")
	b.climbing = false
	b.on_floor = false
	b.vel = Vector2(0, 10)
	t.eq(ActorBody.state_for(b), "jump", "rising: jump")
	# WorldView API stays compatible (whatever is fetched here).
	var world := TileWorld.make_test()
	var view := WorldView.new()
	view.setup(world, LightEngine.new(world))
	var n := view.add_actor(3, {"kind": "goblin", "size": Vector2(1.2, 1.8), "color": Color.GREEN})
	t.check(n is ActorBody and n.get_meta("size") == Vector2(1.2, 1.8), "add_actor returns the body with its size")
	view.move_actor(3, Vector2(5, 6), 1)
	view.move_actor(3, Vector2(5, 6), 1, "attack", Vector2.ZERO)
	t.eq(view.get_actor(3).position, Vector3(5, 6, 0) * K.TILE_M, "move_actor places it")
	view.remove_actor(3)
	t.eq(view.get_actor(3), null, "remove_actor")
	view.free()

## A forge body that cannot load falls back; with art fetched, a real one is checked too.
func _forge_bodies(t: TestLog) -> void:
	var mat := ShaderMaterial.new()
	# An SRD slug the forge has no animated body for yet; has_file claims it is synced.
	var cr := Looks.creatures()
	var slug := "xorn"
	ActorBody.forge_failed.erase(slug)
	var a := ActorBody.build({"slug": slug}, mat, func(p: String) -> bool: return p.begins_with("res://assets/monsters/xorn/") or (not p.begins_with("res://assets/monsters/") and FileAccess.file_exists(p)))
	t.check((a.kind != "forge" or ForgeMonster.is_synced(slug)) and a.visual != null, "a forge body that fails to load falls back (%s)" % a.kind)
	t.check(ActorBody.forge_failed.has(slug) or ForgeMonster.is_synced(slug), "the failure is remembered for later actors")
	t.check(cr.has(slug), "xorn is an SRD slug")
	a.free()
	ActorBody.forge_failed.erase(slug)
	for s: String in ["owlbear", "polar-bear"]:     # no row of its own; forge_first: forge first
		if not ForgeMonster.is_synced(s) or Looks.quarantine().has(s):
			t.check(true, "%s not synced: forge body checks skipped" % s)
			continue
		var b := ActorBody.build({"slug": s}, mat)
		t.eq(b.kind, "forge", "%s: forge body" % s)
		var m := b.visual as ForgeMonster
		t.check(m.has_clip("idle") and m.move_clip() != "", "%s: idle and a move clip" % s)
		var g := m.ground_speed()
		t.check(g > 0.1 and g < 5.0, "%s: walk ground speed measured (%.2f m/s)" % [s, g])
		var box := GltfCache.visible_aabb(b)
		t.check(box.size.y <= b.size.y * K.TILE_M * 1.15 + 0.01, "%s: no taller than 1.15x its box (%.2f m)" % [s, box.size.y])
		t.check(absf(box.position.y) < 0.15, "%s: feet near the ground (%.3f)" % [s, box.position.y])
		var mps := maxf(0.8 * g * m.scale.x, 0.3)     # (under 0.25 m/s a body stands)
		var slow: Array = b.forge_clip_speed("run", Vector2(mps / K.TILE_M, 0))
		t.check(slow[0] == "walk" and absf(float(slow[1]) - clampf(mps / (g * m.scale.x), ActorBody.FORGE_SPEED_MIN, ActorBody.FORGE_SPEED_MAX)) < 0.01,
			"%s: the walk plays at body speed / ground speed (%.2f m/s -> %.2fx)" % [s, mps, float(slow[1])])
		t.eq(b.forge_clip_speed("run", Vector2(100, 0))[1], ActorBody.FORGE_SPEED_MAX, "%s: a fast body clamps the walk speed" % s)
		t.eq(b.forge_clip_speed("idle", Vector2.ZERO)[0], "idle", "%s: standing: idle" % s)
		b.free()

func _dressing(t: TestLog) -> void:
	var defs := DressingView.defs()
	t.check(defs.size() >= 8, "dressing.json has objects")
	var bad := []
	for id: String in defs:
		var d: Dictionary = defs[id]
		var fp: Array = d.get("footprint", [])
		var drawn: bool = String(d.get("model", "")).begins_with("res://assets/meshes/") or d.has("prim")
		var ok: bool = drawn and fp.size() == 2 \
			and int(fp[0]) >= 1 and int(fp[1]) >= 1 and d.get("anchor", "") in ["ground", "ceiling", "wall"] \
			and float(d.get("fit_h", 0)) > 0.0 \
			and ((float(d.get("weight", 0)) > 0.0 and d.get("where", {}).get("band", "") in ["surface", "cave", "below"])
				or d.get("where", {}).get("band", "") == "place")   # building pieces are placed, not scattered
		if not ok:
			bad.append(id)
	t.eq(bad, [], "every dressing object is well formed")
	var world := TileWorld.make_test()
	var a := DressingView.scatter(world, 0, world.width - 1, 7)
	var b := DressingView.scatter(world, 0, world.width - 1, 7)
	t.eq(a, b, "scatter is deterministic")
	t.check(a.size() > 40, "scatter places objects on the test world (%d)" % a.size())
	var clash := 0
	var cave := 0
	var cells := {}
	for r: Dictionary in a:
		var fp: Array = defs[r["id"]]["footprint"]
		if String(defs[r["id"]]["where"]["band"]) == "cave":
			cave += 1
		for dx in int(fp[0]):
			if not world.is_solid(r["x"] + dx, r["y"] - 1):
				clash += 1
			for dy in int(fp[1]):
				var c := Vector2i(r["x"] + dx, r["y"] + dy)
				if cells.has(c) or world.get_fg(c.x, c.y) != TileDefs.AIR:
					clash += 1
				cells[c] = true
	t.eq(clash, 0, "footprints are air, supported and do not overlap")
	t.check(cave > 0, "the cave pocket gets cave dressing")
	var xf := DressingView.placement(defs["bush"], 2.0, 10, 64)
	t.check(absf(xf.origin.y - 64 * K.TILE_M) < 1e-4, "ground objects stand on the tile boundary")
	t.check(xf.origin.z < 0.0, "a bush sits behind the actor plane")

func _index(t: TestLog) -> void:
	var path := "res://tests/data/asset_paths.txt"
	if not FileAccess.file_exists(path):
		t.check(true, "no tests/data/asset_paths.txt: server check skipped (run tools/fetch_assets.sh --index)")
		return
	var known := {}
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line != "" and not line.begins_with("#"):
			known[line] = true
	var refs := Looks.all_paths()
	for d: Dictionary in DressingView.defs().values():
		if d.has("model"):      # a row may be primitives alone (view/actors/prim_mesh.gd)
			refs.append(String(d["model"]))
		for v in d.get("textures", {}).values():
			if String(v).begins_with("res://"):
				refs.append(String(v))
	var missing := []
	for r in refs:
		if not known.has(r.trim_prefix("res://")):
			missing.append(r)
	t.eq(missing, [], "every model and clip path is in the server index (tests/data/asset_paths.txt; refresh: tools/fetch_assets.sh --index)")
