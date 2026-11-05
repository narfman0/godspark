## What one body (its MoveStats) can do on tiles: footprint in whole cells, modes, and the
## jumps recorded from the real controller (MonsterNav._record_jumps). Built and cached by
## MonsterNav.profile(stats).
class_name NavProfile
extends RefCounted

var key := ""
var stats: MoveStats
var w := 1.5
var h := 2.5
## Footprint in cells.
var cw := 2
var ch := 3
var step := 1
var walker := true
var climb := false
var fly := false
var swim_speed := 5.0
## Hardest tile it digs through (0: none).
var dig := 0.0
var run := 13.0
var max_speed := 13.0
## [{dl, dy, hold, delay, dir, ticks, t, asc: PackedInt32Array, desc: PackedInt32Array, xc}]:
## offsets packed with MonsterNav._pack, relative to the start node.
var jumps: Array = []
## The jumps' landing offsets, packed for the search's inner loop (same order as jumps).
var jdl := PackedInt32Array()
var jdy := PackedInt32Array()
