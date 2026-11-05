## How a body moves: SRD speeds (ft per round) turned into real-time platformer numbers
## (tiles, seconds) using the tunables in data/movement.json.
##
##   var s := MoveStats.from_srd({"walk": 30, "climb": 30}, "medium")   # a giant-spider-ish walker
##   var p := MoveStats.player()                                        # walk 30, Medium
##
## Walk 30 ft is the baseline run speed (`run.tiles_per_s_per_30ft`); every mode scales
## linearly with its SRD speed. A mode with speed 0 is absent, except that anyone can use a
## ladder and anyone can swim: without a swim speed a body swims at half its walk speed
## (the SRD "costs double" rule).
class_name MoveStats
extends RefCounted

const PATH := "res://data/movement.json"
const SIZES: PackedStringArray = ["tiny", "small", "medium", "large", "huge", "gargantuan"]

static var _data := {}

# SRD speeds, ft per round. 0 = none.
var walk := 30.0
var climb := 0.0
var swim := 0.0
var fly := 0.0
var burrow := 0.0
var hover := false
var size_name := "medium"
var size := Vector2(1.5, 2.5)
## Automatic step-up height, whole tiles.
var step_tiles := 1

# Derived, tiles and seconds.
var run_speed := 13.0
var ground_accel := 110.0
var ground_friction := 140.0
var turn_accel := 220.0
var air_accel := 55.0
var air_friction := 12.0
var gravity := 81.25
var jump_velocity := 32.5
var fall_gravity_mult := 1.25
var release_cut := 0.45
var terminal_fall := 40.0
var coyote_time := 0.1
var buffer_time := 0.12
var ladder_speed := 7.0
var ladder_side_speed := 4.0
## Wall climbing speed; 0 = cannot climb walls (ladders still work).
var climb_speed := 0.0
var climb_jump_mult := 0.8
var swim_speed := 5.0
var swim_threshold := 0.5
var water_gravity := 20.0
var buoyancy := 17.0
var water_drag := 3.0
var swim_accel := 40.0
var max_sink := 4.0
## Deceleration (t/s^2) of a body entering water faster than it can swim down.
var water_brake := 150.0
var stroke_mult := 1.0
var leap_below := 0.85
var leap_mult := 0.75
## Flying speed; 0 = cannot fly.
var fly_speed := 0.0
var fly_accel := 60.0
## Tiles per second of burrowing. Not used yet: see PlayerController (burrow is a stub).
var burrow_speed := 0.0

static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _data

## Fixed controller step rate (Hz) from data/movement.json.
static func step_hz() -> int:
	return int(data()["step_hz"])

## Collision box (tiles) for an SRD size name; case-insensitive, unknown sizes read as medium.
static func size_of(size_name_in: String) -> Vector2:
	var row := _size_row(size_name_in)
	return Vector2(float(row["w"]), float(row["h"]))

static func _size_row(size_name_in: String) -> Dictionary:
	var sizes: Dictionary = data()["sizes"]
	var key := size_name_in.to_lower()
	return sizes.get(key, sizes["medium"])

static func player() -> MoveStats:
	return from_srd({"walk": 30}, "medium")

## speeds: SRD speeds in ft per round, keyed walk/climb/swim/fly/burrow (hover: bool), as in
## monster-forge's registry. Missing keys mean 0, except walk which defaults to 30.
static func from_srd(speeds: Dictionary, size_name_in := "medium") -> MoveStats:
	var s := MoveStats.new()
	var d := data()
	s.walk = float(speeds.get("walk", 30))
	s.climb = float(speeds.get("climb", 0))
	s.swim = float(speeds.get("swim", 0))
	s.fly = float(speeds.get("fly", 0))
	s.burrow = float(speeds.get("burrow", 0))
	s.hover = bool(speeds.get("hover", false))
	s.size_name = size_name_in.to_lower() if d["sizes"].has(size_name_in.to_lower()) else "medium"
	var row := _size_row(s.size_name)
	s.size = Vector2(float(row["w"]), float(row["h"]))
	s.step_tiles = int(row.get("step", 1))

	var run: Dictionary = d["run"]
	s.run_speed = s.walk / 30.0 * float(run["tiles_per_s_per_30ft"])
	s.ground_accel = float(run["ground_accel"])
	s.ground_friction = float(run["ground_friction"])
	s.turn_accel = float(run["turn_accel"])
	s.air_accel = float(run["air_accel"])
	s.air_friction = float(run["air_friction"])

	var jump: Dictionary = d["jump"]
	var h := float(jump["height"])
	var t := float(jump["time_to_apex"])
	s.gravity = 2.0 * h / (t * t)
	s.jump_velocity = 2.0 * h / t
	s.fall_gravity_mult = float(jump["fall_gravity_mult"])
	s.release_cut = float(jump["release_cut"])
	s.terminal_fall = float(jump["terminal_fall"])
	s.coyote_time = float(jump["coyote"])
	s.buffer_time = float(jump["buffer"])

	var ladder: Dictionary = d["ladder"]
	s.ladder_speed = float(ladder["speed"])
	s.ladder_side_speed = float(ladder["side_speed"])

	var climb_d: Dictionary = d["climb"]
	s.climb_speed = s.climb / 30.0 * float(climb_d["tiles_per_s_per_30ft"])
	s.climb_jump_mult = float(climb_d["jump_off_mult"])
	if s.climb > 0.0:
		s.ladder_speed = maxf(s.ladder_speed, s.climb_speed)

	var sw: Dictionary = d["swim"]
	var swim_ft := s.swim if s.swim > 0.0 else s.walk * 0.5
	s.swim_speed = swim_ft / 30.0 * float(sw["tiles_per_s_per_30ft"])
	s.swim_threshold = float(sw["threshold"])
	s.water_gravity = float(sw["gravity"])
	s.buoyancy = float(sw["buoyancy"])
	s.water_drag = float(sw["drag"])
	s.swim_accel = float(sw["accel"])
	s.max_sink = float(sw["max_sink"])
	s.water_brake = float(sw["brake"])
	s.stroke_mult = float(sw["stroke_mult"])
	s.leap_below = float(sw["leap_below"])
	s.leap_mult = float(sw["leap_mult"])

	var fl: Dictionary = d["fly"]
	s.fly_speed = s.fly / 30.0 * float(fl["tiles_per_s_per_30ft"])
	s.fly_accel = float(fl["accel"])

	s.burrow_speed = s.burrow / 30.0 * float(run["tiles_per_s_per_30ft"])
	return s

## A Body of this stats' size.
func make_body() -> Body:
	var b := Body.new()
	b.size = size
	return b
