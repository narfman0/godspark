## Bookkeeping for a capped pool of floating numbers (pure, testable): at most `cap` live at
## once; a new one takes a free slot, else replaces the oldest, so a horde never floods the
## screen. Several numbers on one target within a short window stack upward instead of
## overlapping.
class_name NumberPool
extends RefCounted

const STACK_WINDOW := 0.35   ## s: numbers on one target this close in time stack
const LIFE := 1.0

var cap := 40
## Per slot: {age, target, row} (age < 0: free).
var slots: Array = []
var now := 0.0

func _init(n := 40) -> void:
	cap = n
	for i in cap:
		slots.append({"age": -1.0, "target": 0, "row": 0, "born": 0.0})

## A slot for a new number on `target`: {index, row} (row: stacking offset 0, 1, 2 ...).
func acquire(target: int) -> Dictionary:
	var best := -1
	var oldest := -1.0
	for i in cap:
		var s: Dictionary = slots[i]
		if float(s["age"]) < 0.0:
			best = i
			break
		if float(s["age"]) > oldest:
			oldest = float(s["age"])
			best = i
	var row := 0
	for s: Dictionary in slots:
		if float(s["age"]) >= 0.0 and int(s["target"]) == target and now - float(s["born"]) < STACK_WINDOW:
			row = maxi(row, int(s["row"]) + 1)
	slots[best] = {"age": 0.0, "target": target, "row": row % 4, "born": now}
	return {"index": best, "row": row % 4}

## Advance time; slots past LIFE are freed. Returns the indices freed this step.
func step(dt: float) -> Array:
	now += dt
	var freed: Array = []
	for i in cap:
		var s: Dictionary = slots[i]
		if float(s["age"]) >= 0.0:
			s["age"] = float(s["age"]) + dt
			if float(s["age"]) > LIFE:
				s["age"] = -1.0
				freed.append(i)
	return freed

func live() -> int:
	var n := 0
	for s: Dictionary in slots:
		if float(s["age"]) >= 0.0:
			n += 1
	return n
