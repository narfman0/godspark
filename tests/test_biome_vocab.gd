## One biome vocabulary (data/biomes.json): every table names only canonical ids, and a table
## that doesn't is caught. Sites on a generated world take the biome under them.
extends RefCounted

const RETIRED := ["plains", "grassland", "mountains", "alpine", "snow", "arctic", "cavern"]

func run(t: TestLog) -> void:
	_ids(t)
	_scan_detects(t)
	_tables(t)
	_data_tree(t)
	_generated(t)
	_mountain_habitat(t)
	_sites(t)

func _ids(t: TestLog) -> void:
	t.check(BiomeIds.ids().size() >= 15, "the vocabulary is loaded")
	for id: String in ["meadow", "forest", "mountain", "desert", "swamp", "tundra", "coast", "caves", "underdark"]:
		t.check(BiomeIds.has(id), "%s is canonical" % id)
	for id: String in RETIRED:
		t.check(not BiomeIds.has(id), "%s is gone" % id)

## The checker itself: a made-up table with a bad id in each shape gets caught.
func _scan_detects(t: TestLog) -> void:
	var bad := {"a": {"biomes": {"plains": 1, "meadow": 2}}, "b": [{"biome": "marsh"}, {"biomes": ["bog", "forest"]}]}
	var got := unknown_ids(bad)
	got.sort()
	t.eq(got, ["bog", "marsh", "plains"], "the scan finds bad ids as dict keys, values and list items")
	t.eq(unknown_ids({"biomes": ["meadow"], "biome": "caves"}), [], "the scan passes good ids")

func _tables(t: TestLog) -> void:
	# worldgen's rows
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/worldgen/biomes.json"))
	for o: Dictionary in data["climate"]["orders"]:
		t.eq(unknown_ids({"biomes": o["biomes"]}), [], "order %s names canonical ids" % o["name"])
	var rows: Array = []
	for row: Dictionary in data["biomes"]:
		rows.append(String(row["name"]))
		t.check(BiomeIds.has(row["name"]), "worldgen row %s is canonical" % row["name"])
	var made := Array(BiomeIds.generated("surface"))
	made.sort()
	rows.sort()
	t.eq(rows, made, "worldgen's rows are exactly the surface biomes marked generated")
	# the sim's capacities
	SimData.ensure()
	var sim_rows: Array = []
	for id: String in SimData.biomes:
		if not id.begins_with("_"):
			sim_rows.append(id)
	t.eq(unknown_ids({"biomes": sim_rows}), [], "data/sim/biomes.json has canonical rows")
	for id: String in BiomeIds.generated():
		t.check(SimData.biomes.has(id), "the sim has capacities for generated biome %s" % id)
	t.eq(unknown_ids({"biomes": SimData.biomes["_band_default"].values()}), [], "the sim's band defaults are canonical")
	# the stand-alone layout
	t.eq(unknown_ids({"biomes": WorldSim.SYNTH_SURFACE + WorldSim.SYNTH_DEEP}), [], "the sim's stand-alone layout is canonical")
	# habitats and spawning
	t.eq(unknown_ids(Ecology.habitats()), [], "habitats.json is canonical")
	var sp: Dictionary = Ecology.spawning()
	var fb: Dictionary = sp["biome_fallback"].duplicate()
	fb.erase("_doc")
	t.eq(unknown_ids({"biomes": fb.keys()}), [], "biome_fallback keys are canonical")
	for k: String in fb:
		t.eq(unknown_ids({"biomes": fb[k]}), [], "biome_fallback %s is canonical" % k)
	t.eq(unknown_ids({"biomes": sp["band_biome"].values()}), [], "band_biome is canonical")

## Every data file: anything under a "biome" or "biomes" key anywhere (places, dressing, cultures,
## whatever comes next). The two tables whose rows are biomes are checked above.
func _data_tree(t: TestLog) -> void:
	var files := _json_files("res://data")
	t.check(files.size() > 15, "the scan reads the data tree (%d files)" % files.size())
	for f: String in files:
		if f in ["res://data/biomes.json", "res://data/worldgen/biomes.json", "res://data/sim/biomes.json"]:
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(f))
		t.eq(unknown_ids(parsed), [], "%s names canonical biomes" % f)

func _json_files(dir: String) -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".json"):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_json_files(dir + "/" + d))
	return out

## Ids under "biome" / "biomes" keys anywhere in a JSON value that aren't canonical.
func unknown_ids(v: Variant) -> Array:
	var out: Array = []
	_walk(v, out)
	return out

func _walk(v: Variant, out: Array) -> void:
	if v is Array:
		for e: Variant in v:
			_walk(e, out)
	elif v is Dictionary:
		for k: Variant in v:
			if k == "biome" or k == "biomes":
				_names(v[k], out)
			else:
				_walk(v[k], out)

func _names(v: Variant, out: Array) -> void:
	if v is String:
		if not BiomeIds.has(v) and not v in out:
			out.append(v)
	elif v is Array:
		for e: Variant in v:
			_names(e, out)
	elif v is Dictionary:
		for k: Variant in v:
			_names(String(k), out)

## A world's strip and sites speak the vocabulary too.
func _generated(t: TestLog) -> void:
	var w := WorldGen.generate(1024, 512, 5)
	t.eq(unknown_ids(w.meta["sites"]), [], "site biomes are canonical")
	t.eq(unknown_ids({"biomes": w.meta["biomes"].map(func(s: Dictionary) -> String: return s["biome"])}), [], "strip is canonical")

## Mountains read as hills: every generated surface biome has creatures to spawn, by day and
## by night, and the mountain's are the hills'.
func _mountain_habitat(t: TestLog) -> void:
	var srd := WorldHost.shared_srd()
	for id: String in BiomeIds.generated("surface"):
		for night: bool in [false, true]:
			var n := Ecology.roster(srd, "surface", id, night, 0.0, 3.0).size()
			t.check(n > 0, "%s has a %s roster (%d kinds)" % [id, "night" if night else "day", n])
	var hills := Ecology.roster(srd, "surface", "hills", true, 0.0, 30.0).map(func(r: Dictionary) -> String: return r["slug"])
	var mountain := Ecology.roster(srd, "surface", "mountain", true, 0.0, 30.0).map(func(r: Dictionary) -> String: return r["slug"])
	t.eq(mountain, hills, "the mountain reads as hills")

## A site's biome is the ground it stands on, and the sim takes that same biome.
func _sites(t: TestLog) -> void:
	for sd: int in [4, 5, 9]:
		var w := WorldGen.generate(1024, 512, sd)
		var sim := WorldSim.from_meta(w.meta, sd)
		var seen := {}
		for s: Dictionary in w.meta["sites"]:
			var want := "caves" if s["band"] == "caves" else "underdark"
			if s["band"] in ["surface", "sky"]:
				for seg: Dictionary in w.meta["biomes"]:
					if int(s["x"]) >= int(seg["x0"]) and int(s["x"]) <= int(seg["x1"]):
						want = seg["biome"]
			t.eq(s["biome"], want, "seed %d: site %d has the biome under it" % [sd, s["id"]])
			t.eq(sim.site_by_id[int(s["id"])].biome, want, "seed %d: the sim's site %d agrees" % [sd, s["id"]])
			if s["band"] == "surface":
				seen[s["biome"]] = true
		t.check(seen.size() >= 2, "seed %d: surface sites stand in different biomes (%s)" % [sd, seen.keys()])
