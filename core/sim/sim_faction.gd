## A polity: one or more settlements under one name, with relations to the others.
class_name SimFaction
extends RefCounted

var id := 0
var name := ""
var culture := ""
var temperament := "trader"   # trader | raider | isolationist | expansionist
var relations := {}           # faction id (int) -> -100..100
var wars := {}                # faction id (int) -> {since: hour, weariness: float, losses: int}
var alive := true
var capital := -1             # site id
var partners := {}            # faction id (int) -> true once they have traded

func rel(other: int) -> float:
	return relations.get(other, 0.0)

func at_war(other: int) -> bool:
	return wars.has(other)

func to_dict() -> Dictionary:
	var r := {}
	for k in relations:
		r[str(k)] = relations[k]
	var w := {}
	for k in wars:
		w[str(k)] = wars[k].duplicate()
	return {"id": id, "name": name, "culture": culture, "temperament": temperament,
		"relations": r, "wars": w, "alive": alive, "capital": capital, "partners": _sorted(partners)}

static func _sorted(d: Dictionary) -> Array:
	var k := d.keys()
	k.sort()
	return k

static func from_dict(d: Dictionary) -> SimFaction:
	var f := SimFaction.new()
	f.id = int(d.id); f.name = d.name; f.culture = d.culture; f.temperament = d.temperament
	for k in d.relations:
		f.relations[int(k)] = float(d.relations[k])
	for k in d.wars:
		var w: Dictionary = d.wars[k]
		f.wars[int(k)] = {"since": int(w.since), "weariness": float(w.weariness), "losses": int(w.losses)}
	f.alive = bool(d.alive); f.capital = int(d.capital)
	for k in d.partners:
		f.partners[int(k)] = true
	return f
