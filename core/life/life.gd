## Shared pieces of the Life track: stance values, factions of entities, its data tables, and
## seeded per-entity randomness (never the sim's generator, never the rules dice).
##
##   Life.HOSTILE / Life.NEUTRAL / Life.FRIENDLY       what LifeSystem.stance returns
##   Life.faction_of(e) -> String                       "players", a sim faction id, or "wild"
##   Life.rng_for([world seed, "town", site id, slot, generation]) -> RandomNumberGenerator
## Docs: docs/tracks/life.md.
class_name Life
extends RefCounted

const HOSTILE := 0
const NEUTRAL := 1
const FRIENDLY := 2
const NAMES := ["hostile", "neutral", "friendly"]

const STANDING_PATH := "res://data/life/standing.json"
const PEOPLE_PATH := "res://data/life/people.json"
static var _standing := {}
static var _people := {}

static func standing_cfg() -> Dictionary:
	if _standing.is_empty():
		_standing = JSON.parse_string(FileAccess.get_file_as_string(STANDING_PATH))
	return _standing

static func people_cfg() -> Dictionary:
	if _people.is_empty():
		_people = JSON.parse_string(FileAccess.get_file_as_string(PEOPLE_PATH))
	return _people

static func num(key: String, d: float) -> float:
	return float(standing_cfg().get(key, d))

## Players are "players"; Life's actors carry their sim faction id in meta `faction`; any
## other creature (lairs, the spawn director, sim monster packs) is "wild".
static func faction_of(e: HostEntity) -> String:
	if e.is_player():
		return "players"
	if e.has_meta("faction"):
		return String(e.get_meta("faction"))
	return "wild"

static func is_sim_faction(f: String) -> bool:
	return f != "players" and f != "wild" and f.is_valid_int()

## A generator seeded from a key, for sampling people and names: what a player looks at
## never advances the sim's own generator.
static func rng_for(key: Array) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(key)
	return r

## The look.people key for a person of a culture in a role ("human:guard", "elf:drow:guard",
## "goblin"); "" for monstrous peoples drawn by their stat block.
static func people_key(culture: String, role: String, slug: String, female := false) -> String:
	var c: Dictionary = SimData.cultures.get(culture, {})
	var species := String(c.get("species", ""))
	if species == "":
		return ""
	var base := species
	if String(c.get("lineage", "")) != "":
		base += ":" + String(c["lineage"])
	var lr: Dictionary = people_cfg().get("look_role", {})
	var r := String(lr.get(role, lr.get(slug, SpawnDirector._people_role(slug))))
	if culture == "bandit":
		r = SpawnDirector._people_role(slug) if role in ["raider", "guard", "escort"] else r
		if r == "raider":
			r = "bandit"
	var key := base + ":" + r
	if female and r == "commoner":
		key += ":f"
	return key
