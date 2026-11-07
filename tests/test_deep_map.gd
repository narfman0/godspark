## Names and the map (M6 track deep, item 5): underground regions are named from the setting's
## tables, carry their bounds to the map's labels and to a client's META (with the lake, lava
## pools and sinkholes in short), and a player who walks into one has seen it: Deals' atlas
## sends it, the save keeps it, and the world map draws only regions seen.
extends RefCounted

func run(t: TestLog) -> void:
	var w := WorldGen.generate_named("dev", 2)
	_names(t, w)
	_labels(t, w)
	_wire(t, w)
	_seen(t, w)

func _names(t: TestLog, w: TileWorld) -> void:
	var d := RegionNames.data()
	for b: String in ["underdark", "fungal", "crystal", "deep_lake", "magma"]:
		t.check((d["region"] as Dictionary).has(b), "the names have a table for the %s" % b)
	var seen := {}
	for r: Dictionary in BiomeIds.regions(w.meta):
		var n := String(r.get("name", ""))
		t.check(n.begins_with("the ") and not seen.has(n), "%s is named, once (%s)" % [r["biome"], n])
		seen[n] = true
	var other := WorldGen.generate_named("dev", 2)
	t.eq(BiomeIds.regions(other.meta).map(func(r: Dictionary) -> String: return r["name"]), BiomeIds.regions(w.meta).map(func(r: Dictionary) -> String: return r["name"]),
		"the same seed names them the same")

func _labels(t: TestLog, w: TileWorld) -> void:
	var labels := MapLogic.land_labels(w.meta)
	var deep := labels.filter(func(l: Dictionary) -> bool: return l.has("band"))
	t.eq(deep.size(), BiomeIds.regions(w.meta).size(), "a label per underground region")
	for l: Dictionary in deep:
		var row: Dictionary = w.meta["biomes"][int(l["i"])]
		t.eq(row["name"], l["name"], "a label knows its row in meta.biomes (%s)" % l["name"])
		t.check(int(l["y"]) >= int(row["y0"]) and int(l["y"]) <= int(row["y1"]), "and sits at its depth")

func _wire(t: TestLog, w: TileWorld) -> void:
	var bytes := Protocol.meta(w.meta)
	var m := Protocol.decode(bytes)
	var meta: Dictionary = m.get("meta", m)
	t.check(bytes.size() < 96 * 1024, "META stays small with the underground in it (%d bytes)" % bytes.size())
	t.eq(BiomeIds.regions(meta).size(), BiomeIds.regions(w.meta).size(), "the regions reach a client")
	var d: Dictionary = meta.get("descent", {})
	t.eq(int(d.get("lake", {}).get("x0", -1)), int(w.meta["descent"]["lake"]["x0"]), "and the lake")
	t.eq((d.get("lava", []) as Array).size(), (w.meta["descent"]["lava"] as Array).size(), "and the lava")
	t.eq((d.get("sinkholes", []) as Array).size(), (w.meta["descent"]["sinkholes"] as Array).size(), "and the sinkholes")
	var lr := int(d.get("lake", {}).get("region", -1))
	t.eq(String(meta["biomes"][lr]["biome"]) if lr >= 0 else "", "deep_lake", "the lake names its region's row")

## A player at the nadir floor has seen the magma: the atlas says so, and a save keeps it.
func _seen(t: TestLog, w: TileWorld) -> void:
	var host := WorldHost.new(w)
	var deals := DealsSystem.new()
	host.add_system(deals)
	var p := host.add_player("delver", 2, {"class": "fighter"})
	var nf: Array = w.meta["descent"]["nadir"]
	p.body.pos = Vector2(float(nf[0]) + 0.5, float(nf[1]))
	for i in 40:
		host.tick()
	var ri := BiomeIds.region_index(w.meta, p.body.pos.x, p.body.pos.y)
	t.eq(String(w.meta["biomes"][ri]["biome"]), "magma", "the nadir floor is in the magma")
	t.check((deals.seen_regions.get(p.id, {}) as Dictionary).has(ri), "the player has seen it")
	var saved := deals.save_player(p)
	t.check(int(ri) in (saved.get("regions", []) as Array).map(func(v: Variant) -> int: return int(v)), "a save keeps it")
	var again := DealsSystem.new()
	again.load_player(p, saved)
	t.check((again.seen_regions.get(p.id, {}) as Dictionary).has(ri), "and a load brings it back")
	var dc := DealsClient.new()
	dc.handle(DealsCodec.Msg.ATLAS, DealsCodec.write({"t": 0, "seen": [], "regions": [ri]}))
	t.check(dc.seen_regions.has(ri), "a client told of it keeps it for the map")
	var labels := MapLogic.land_labels(w.meta).filter(func(l: Dictionary) -> bool: return l.has("band") and dc.seen_regions.has(int(l["i"])))
	t.eq(labels.size(), 1, "so the map draws that region's label and no other underground one")
