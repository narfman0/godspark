## Game time for one world, in whole host ticks so it never drifts. One day lasts
## K.DAY_SECONDS real seconds (20 minutes), so a game hour is 50 s and 1500 ticks. The host
## advances it one tick per tick; clients mirror it from CLOCK messages. Pure core.
##
##   var clock := WorldClock.new()            # day 0, 08:00
##   clock.advance(1); clock.sleep(6.0)       # one tick; six game hours at once
##   clock.hours(); clock.hour_of_day(); WorldClock.sun_at(clock.hours())
class_name WorldClock
extends RefCounted

const HOURS_PER_DAY := 24
## Host ticks per game hour.
const TICKS_PER_HOUR := K.TICK_HZ * K.DAY_SECONDS / HOURS_PER_DAY
## A new world starts on day 0 at this hour.
const START_HOUR := 8
## Rules sun at night: the sky field times this is level 3 at most, which is Darkness
## (below LightEngine.DIM_MIN = 5). SRD 5.2.1: darkness covers the outdoors at night, even
## most moonlit nights. The view draws night brighter than the rules say (see WorldView).
const MOON := 0.04
## Dawn runs DAWN.x..DAWN.y hours, dusk DUSK.x..DUSK.y (smoothstep between night and day).
const DAWN := Vector2(5.0, 7.0)
const DUSK := Vector2(17.5, 19.5)

var ticks := START_HOUR * TICKS_PER_HOUR

func advance(n := 1) -> void:
	ticks += n

## Jump ahead by game hours (sleeping, debugging).
func sleep(h: float) -> void:
	ticks += maxi(0, roundi(h * TICKS_PER_HOUR))

## Game hours since the world began.
func hours() -> float:
	return float(ticks) / TICKS_PER_HOUR

## Whole game hours since the world began.
func whole_hours() -> int:
	return ticks / TICKS_PER_HOUR

func day() -> int:
	return ticks / (TICKS_PER_HOUR * HOURS_PER_DAY)

func hour_of_day() -> float:
	return fposmod(hours(), HOURS_PER_DAY)

func sun() -> float:
	return sun_at(hours())

## The rules sun factor (LightEngine.sun) at a time: 1 by day, MOON by night, smooth
## through dawn and dusk.
static func sun_at(h: float) -> float:
	var t := fposmod(h, HOURS_PER_DAY)
	var day_f := smoothstep(DAWN.x, DAWN.y, t) * (1.0 - smoothstep(DUSK.x, DUSK.y, t))
	return MOON + (1.0 - MOON) * day_f

## "Day 3, 14:05"
static func describe(h: float) -> String:
	var d := floori(h / HOURS_PER_DAY)
	var t := fposmod(h, HOURS_PER_DAY)
	return "Day %d, %02d:%02d" % [d, floori(t), floori(fmod(t, 1.0) * 60.0)]

func to_dict() -> Dictionary:
	return {"ticks": ticks}

func from_dict(d: Dictionary) -> void:
	ticks = int(d.get("ticks", ticks))
