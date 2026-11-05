## Monsters denning at a site: they get hungry, prey on passers-by and nearby settlements,
## breed when fed. An apex lair (a dragon) demands tribute.
class_name SimLair
extends RefCounted

var id := 0               # site id
var name := ""
var kind := ""            # lairs.json id
var family := "surface"   # surface | caves | deeps | portal
var monsters := {}        # slug -> count
var hunger := 0.3         # 0 fed .. 1 starving
var apex := false
var grow := ""
var max_n := 1
var hunger_rate := 1.0
var out := 0              # hunting packs away
var x := 0.0              # derived from the site

func count() -> int:
	return SimData.count(monsters)

func to_dict() -> Dictionary:
	return {"id": id, "name": name, "kind": kind, "family": family, "monsters": monsters.duplicate(),
		"hunger": hunger, "apex": apex, "grow": grow, "max": max_n, "hunger_rate": hunger_rate, "out": out}

static func from_dict(d: Dictionary) -> SimLair:
	var l := SimLair.new()
	l.id = int(d.id); l.name = d.name; l.kind = d.kind; l.family = d.family
	for k in d.monsters:
		l.monsters[k] = int(d.monsters[k])
	l.hunger = float(d.hunger); l.apex = bool(d.apex); l.grow = d.grow; l.max_n = int(d.max)
	l.hunger_rate = float(d.hunger_rate); l.out = int(d.out)
	return l
