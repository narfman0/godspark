## How a body moves: SRD speeds (ft per round) turned into real-time platformer numbers
## (tiles, seconds) using the tunables in data/movement.json.
##
##   var s := MoveStats.from_srd({"walk": 30, "climb": 30}, "medium")   # a giant-spider-ish walker
##   var p := MoveStats.player()                                        # walk 30, Medium
##
## The pace (`pace.tiles_per_s_per_30ft`, MoveStats.pace()) is the one knob: a walk-30 body
## runs at it, every mode speed is a share of it scaled linearly by its SRD speed, and every
## acceleration is a time to reach it. Jumps do not scale. A mode with speed 0 is absent, except that anyone can use a
## ladder and anyone can swim: without a swim speed a body swims at half its walk speed
## (the SRD "costs double" rule).
class_name MoveStats
extends RefCounted

const PATH := "res://data/movement.json"
const SIZES: PackedStringArray = ["tiny", "small", "medium", "large", "huge", "gargantuan"]

static var _data := {}
## Measuring tools only (tools/crossing.gd pace=, tools/trace_run.gd pace=, tests/test_pace.gd):
## a pace in place of the data's for this process. 0 = the data's. Never set it in the game:
## host and clients must agree on the pace.
static var pace_override := 0.0

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

# Derived, tiles and seconds (the defaults are pace 4; from_srd sets them all from the data).
var run_speed := 4.0
var ground_accel := 33.9
var ground_friction := 43.0
var turn_accel := 67.8
var air_accel := 16.9
var air_friction := 3.7
var gravity := 81.25
var jump_velocity := 32.5
var fall_gravity_mult := 1.25
var release_cut := 0.45
var terminal_fall := 40.0
var coyote_time := 0.1
var buffer_time := 0.12
## Seconds S must be held, from a press made while standing, to drop through a one-way floor.
var drop_hold := 0.1
var ladder_speed := 3.0
var ladder_side_speed := 1.6
## Wall climbing speed; 0 = cannot climb walls (ladders still work).
var climb_speed := 0.0
var climb_jump_mult := 0.8
var swim_speed := 1.5
var swim_threshold := 0.5
var water_gravity := 20.0
var buoyancy := 17.0
var water_drag := 3.0
var swim_accel := 12.0
var max_sink := 4.0
## Deceleration (t/s^2) of a body entering water faster than it can swim down.
var water_brake := 150.0
var stroke_mult := 1.0
var leap_below := 0.85
var leap_mult := 0.75
## Flying speed; 0 = cannot fly.
var fly_speed := 0.0
var fly_accel := 18.4
## Tiles per second of burrowing. Not used yet: see PlayerController (burrow is a stub).
var burrow_speed := 0.0
# Spark abilities (data/sparks.json, Sparks.apply). All off by default, so a body with no
# spark moves exactly as before.
## Extra jumps in the air (Skyhook); each at jump_velocity * air_jump_mult.
var air_jumps := 0
var air_jump_mult := 0.85
## Dash: a burst of dash_speed (tiles/s) for dash_time (s), then dash_cooldown (s) before the
## next. Triggered by PlayerInput.dash or by tapping a direction twice within dash_window (s).
## 0 = no dash.
var dash_speed := 0.0
var dash_time := 0.15
var dash_cooldown := 1.0
var dash_window := 0.25
## Featherfall: most fall speed (tiles/s) while jump is held in the air. 0 = off.
var glide_fall := 0.0

static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _data

## The pace: tiles a second a walk-30 body runs (data/movement.json pace.tiles_per_s_per_30ft).
## Code that speaks of tiles a second "at walking pace" reads it here.
static func pace() -> float:
	if pace_override > 0.0:
		return pace_override
	return float((data()["pace"] as Dictionary)["tiles_per_s_per_30ft"])

## Speed a share of the pace takes `seconds` to reach, as an acceleration (tiles/s^2).
static func _accel(share: float, seconds: float) -> float:
	return pace() * share / maxf(seconds, 0.001)

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

	var tps := pace()
	var run: Dictionary = d["run"]
	var run_mult := float(run["speed"])
	s.run_speed = s.walk / 30.0 * tps * run_mult
	s.ground_accel = _accel(run_mult, float(run["accel_s"]))
	s.ground_friction = _accel(run_mult, float(run["friction_s"]))
	s.turn_accel = _accel(run_mult, float(run["turn_s"]))
	s.air_accel = _accel(run_mult, float(run["air_accel_s"]))
	s.air_friction = _accel(run_mult, float(run["air_friction_s"]))

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
	s.drop_hold = float((d.get("drop", {}) as Dictionary).get("hold", 0.1))

	var ladder: Dictionary = d["ladder"]
	s.ladder_speed = tps * float(ladder["speed"])
	s.ladder_side_speed = tps * float(ladder["side_speed"])

	var climb_d: Dictionary = d["climb"]
	s.climb_speed = s.climb / 30.0 * tps * float(climb_d["speed"])
	s.climb_jump_mult = float(climb_d["jump_off_mult"])
	if s.climb > 0.0:
		s.ladder_speed = maxf(s.ladder_speed, s.climb_speed)

	var sw: Dictionary = d["swim"]
	var swim_ft := s.swim if s.swim > 0.0 else s.walk * 0.5
	s.swim_speed = swim_ft / 30.0 * tps * float(sw["speed"])
	s.swim_threshold = float(sw["threshold"])
	s.water_gravity = float(sw["gravity"])
	s.buoyancy = float(sw["buoyancy"])
	s.water_drag = float(sw["drag"])
	s.swim_accel = _accel(float(sw["speed"]), float(sw["accel_s"]))
	s.max_sink = float(sw["max_sink"])
	s.water_brake = float(sw["brake"])
	s.stroke_mult = float(sw["stroke_mult"])
	s.leap_below = float(sw["leap_below"])
	s.leap_mult = float(sw["leap_mult"])

	var fl: Dictionary = d["fly"]
	s.fly_speed = s.fly / 30.0 * tps * float(fl["speed"])
	s.fly_accel = _accel(float(fl["speed"]), float(fl["accel_s"]))

	s.burrow_speed = s.burrow / 30.0 * tps * float((d.get("burrow", {}) as Dictionary).get("speed", 1.0))
	return s

## A Body of this stats' size.
func make_body() -> Body:
	var b := Body.new()
	b.size = size
	return b
