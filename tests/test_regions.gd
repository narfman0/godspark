## The land's names, what reaches a client of them, the map's marks, and where a player starts.
extends RefCounted

## Forgotten Realms' places and regions, none of which may ever be drawn.
const NOT_OURS := ["Sword", "Neverwinter", "Anauroch", "Calim", "Evermoor", "Moonwood", "Spine", "Greypeak", "Graypeak",
	"Nether", "Lurkwood", "Cormanthor", "Chult", "Faer", "Waterdeep", "Baldur", "Amn", "Tethyr", "Sembia", "Thay", "Chionthar", "Dessarin"]

func run(t: TestLog) -> void:
	_tables(t)
	var w := WorldGen.generate_named("dev", 3)
	_names(t, w)
	_wire(t, w)
	_map(t, w)
	_spawn(t)

func _tables(t: TestLog) -> void:
	var d := RegionNames.data()
	for b: String in BiomeIds.generated("surface"):
		t.check((d["region"] as Dictionary).has(b), "%s has a table" % b)
	var text := JSON.stringify(d)
	for bad: String in NOT_OURS:
		var body := text.replace(d.get("_doc", ""), "")
		t.check(not bad in body, "no %s in the tables" % bad)
	var rng := RandomNumberGenerator.new()
	var taken := {}
	var seen := {}
	for i in 60:
		seen[RegionNames.region("swamp", rng, taken)] = true
	t.eq(seen.size(), 60, "names never repeat in a world, however many are drawn")

func _names(t: TestLog, w: TileWorld) -> void:
	var again := WorldGen.generate_named("dev", 3)
	var seen := {}
	var strip: Array = w.meta["biomes"]
	for i in strip.size():
		var n := String(strip[i].get("name", ""))
		t.check(n.begins_with("the "), "strip %d is named (%s)" % [i, n])
		t.eq(n, again.meta["biomes"][i]["name"], "the same seed gives the same name")
		t.check(not seen.has(n), "unique")
		seen[n] = true
	var b: Dictionary = w.meta["barriers"]
	t.check(not (b["ranges"] as Array).is_empty() and not (b["rivers"] as Array).is_empty(), "this world has a range and a river to name")
	for r: Dictionary in b["ranges"]:
		t.check(String(r.get("name", "")).begins_with("the "), "range named (%s)" % r.get("name", ""))
	for r: Dictionary in b["rivers"]:
		t.check(String(r.get("name", "")).begins_with("the River "), "river named (%s)" % r.get("name", ""))
	var other := WorldGen.generate_named("dev", 4)
	var same := 0
	for i in strip.size():
		same += 1 if strip[i]["name"] == other.meta["biomes"][i]["name"] else 0
	t.check(same < strip.size(), "another seed names them otherwise")

func _wire(t: TestLog, w: TileWorld) -> void:
	var bytes := Protocol.meta(w.meta)
	var m := Protocol.decode(bytes)
	t.check(not m.is_empty(), "META decodes (%d bytes on the wire)" % bytes.size())
	var meta: Dictionary = m.get("meta", m)
	t.eq(meta.get("barriers", {}).get("rivers", [{}])[0].get("name"), w.meta["barriers"]["rivers"][0]["name"], "barriers reach a client")
	t.eq(meta["biomes"][0]["name"], w.meta["biomes"][0]["name"], "and the regions' names")
	t.check(bytes.size() < 96 * 1024, "META stays small (%d bytes)" % bytes.size())

func _map(t: TestLog, w: TileWorld) -> void:
	var labels := MapLogic.land_labels(w.meta)
	var kinds := {}
	for l: Dictionary in labels:
		kinds[l["kind"]] = int(kinds.get(l["kind"], 0)) + 1
	t.eq(int(kinds.get("region", 0)), (w.meta["biomes"] as Array).size(), "a label per region")
	t.eq(int(kinds.get("range", 0)), (w.meta["barriers"]["ranges"] as Array).size(), "a label per range")
	t.eq(int(kinds.get("river", 0)), (w.meta["barriers"]["rivers"] as Array).size(), "a label per river")
	var cross := MapLogic.crossings(w.meta)
	var ck := {}
	for c: Dictionary in cross:
		ck[c["kind"]] = true
		t.check(String(c["name"]).contains("the "), "a crossing's name says what it crosses (%s)" % c["name"])
	t.check(ck.has("pass") and ck.has("under"), "a range's two ways across are marks")
	t.check(ck.has("bridge") or ck.has("ford"), "and a river's")
	t.eq(MapLogic.land_labels({"biomes": [{"x0": 0, "x1": 9, "biome": "meadow"}], "surface": []}), [], "an old save has none")

## The spawn is a settled town, a meadow one when any stands, nearest the middle of those.
func _spawn(t: TestLog) -> void:
	var main: Script = load("res://game/main.gd")
	var middling := 0
	var seeds := [3, 4, 5, 7]
	for sd: int in seeds:
		var w := WorldGen.generate_named("dev", sd)
		var at: Vector2 = main.spawn_for(w, Vector2.ZERO)
		t.eq(main.spawn_for(w, Vector2.ZERO), at, "seed %d: the same world, the same spawn" % sd)
		var sid := Places.street_at(w, floori(at.x))
		t.check(sid.x >= 0 and Places.place(w, sid.x)["tier"] != "", "seed %d: on a settled place's street" % sd)
		var meadow := []
		var site := {}
		for s: Dictionary in w.meta["sites"]:
			if int(s["id"]) == sid.x:
				site = s
			if s.get("biome") == "meadow" and s.get("band") == "surface" and not Places.place(w, int(s["id"])).is_empty() \
					and String(Places.place(w, int(s["id"])).get("tier", "")) != "":
				meadow.append(s)
		if not meadow.is_empty():
			t.eq(site.get("biome"), "meadow", "seed %d: a meadow town when one stands" % sd)
			for s: Dictionary in meadow:
				t.check(absf(float(site["x"]) - w.width * 0.5) <= absf(float(s["x"]) - w.width * 0.5) + 0.01, "seed %d: the one nearest the middle" % sd)
		if absf(at.x - w.width * 0.5) < w.width * 0.3:
			middling += 1
	t.check(middling >= seeds.size() - 1, "spawns lie near the middle of the world (%d of %d)" % [middling, seeds.size()])
