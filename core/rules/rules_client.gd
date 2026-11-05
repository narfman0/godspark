## The rules system on a client (HostSystem.RULES): holds the mirrored character sheet and
## everyone's downed state, and sends the player's rules requests to the host, which checks
## every one of them. The interface track builds its screens on the signals and methods below.
## Main thread; never rolls dice.
##
##   var rules: RulesClient = cw.system(HostSystem.RULES)
##   rules.sheet_changed.connect(func(s): ...)      # s: RulesCodec.encode_sheet's dictionary
##   rules.answer("4:asi", ["ability-score-improvement", "str", "con"])
##   rules.pick_knack("skill-athletics"); rules.rest_short(); rules.revive(ally_id)
##
## While the own player is downed or dead its local movement is frozen (cw.stats swapped for a
## still copy; gravity still applies) and the host holds the body in place either way.
class_name RulesClient
extends ClientSystem

## The whole sheet, on join and whenever it changes (see RulesCodec.encode_sheet for keys).
signal sheet_changed(sheet: Dictionary)
## One per level gained; reward is a LevelTrack.Reward.
signal leveled(level: int, reward: int)
## A choice is waiting: {key, kind, label, count, options: [{id, name, level?, modelled}]}.
## kind: "asi" (answer [feat, details...]), "pick", "spell", "knack", "boon".
signal choice_pending(choice: Dictionary)
## An entity's downed state changed (state: RulesCodec.Down; id may be the own player).
signal downed_changed(id: int, state: int, successes: int, failures: int)
## A rest event: {event: RulesCodec.RestEv, healed, dice, reason, names (still up)}.
signal rest_event(ev: Dictionary)
## XP gained: amount and where from.
signal xp_gained(amount: int, source: String)
## A line for the player from the host (a refused request, "bob got you up").
signal notice(text: String)
## The host's sheet numbers (SheetSummary) changed.
signal summary_changed(summary: Dictionary)
## The deed tally arrived (also in sheet["deeds"]).
signal deeds_changed(deeds: Dictionary)
## The interface preferences stored with the character arrived (on join).
signal prefs_arrived(prefs: Dictionary)

var cw: ClientWorld
## The last sheet ({} until the first CHAR).
var sheet := {}
## Open choices by key (from CHOICE; dropped when a CHAR no longer lists them).
var choices := {}
## id -> {state, successes, failures} for entities not UP.
var downed := {}
## The last rest event.
var last_rest := {}
var notices := PackedStringArray()
## The host's computed sheet numbers ({} until the first SUMMARY): SheetSummary.of.
var summary := {}
## The whole deed tally as the host counts it ({} until the first DEEDS).
var deeds := {}
## Interface preferences saved with the character ({quick: [4 slugs]}).
var prefs := {}
var _base_stats: MoveStats = null

func sys_id() -> int:
	return HostSystem.RULES

func attach(c: ClientWorld) -> void:
	cw = c

func handle(kind: int, data: PackedByteArray) -> void:
	match kind:
		RulesCodec.K.CHAR:
			var s := RulesCodec.decode_sheet(data)
			if s.is_empty():
				return
			sheet = s
			var keys := {}
			for p: Dictionary in s["pending"]:
				keys[p["key"]] = true
			for k: String in choices.keys():
				if not keys.has(k):
					choices.erase(k)
			if not deeds.is_empty():
				s["deeds"] = deeds
			_own_state(int(s["state"]))
			_own_look(String(s.get("class", "")))
			sheet_changed.emit(s)
		RulesCodec.K.DEEDS:
			var m := RulesCodec.decode_deeds(data)
			if not m.is_empty():
				deeds = m["deeds"]
				sheet["deeds"] = deeds
				deeds_changed.emit(deeds)
		RulesCodec.K.SUMMARY:
			var m := RulesCodec.decode_json(data)
			if not m.is_empty():
				summary = m
				summary_changed.emit(m)
		RulesCodec.K.PREFS:
			prefs = Character.clean_prefs(RulesCodec.decode_json(data, RulesCodec.PREFS_MAX))
			prefs_arrived.emit(prefs)
		RulesCodec.K.CHOICE:
			var c := RulesCodec.decode_choice(data)
			if not c.is_empty():
				choices[c["key"]] = c
				choice_pending.emit(c)
		RulesCodec.K.LEVEL:
			var m := RulesCodec.decode_level(data)
			if not m.is_empty():
				leveled.emit(m["level"], m["reward"])
		RulesCodec.K.DOWNED:
			var m := RulesCodec.decode_downed(data)
			if m.is_empty():
				return
			var id: int = m["id"]
			if int(m["state"]) == RulesCodec.Down.UP:
				downed.erase(id)
			else:
				downed[id] = {"state": m["state"], "successes": m["successes"], "failures": m["failures"]}
			if cw != null and id == cw.my_id:
				_own_state(int(m["state"]))
			downed_changed.emit(id, m["state"], m["successes"], m["failures"])
		RulesCodec.K.REST:
			var m := RulesCodec.decode_rest(data)
			if not m.is_empty():
				last_rest = m
				rest_event.emit(m)
		RulesCodec.K.GAIN:
			var m := RulesCodec.decode_gain(data)
			if not m.is_empty():
				xp_gained.emit(m["xp"], m["source"])
		RulesCodec.K.NOTE:
			var m := RulesCodec.decode_str(data)
			if not m.is_empty():
				notices.append(m["text"])
				if notices.size() > 20:
					notices = notices.slice(notices.size() - 20)
				notice.emit(m["text"])

# --- requests (all checked on the host) ------------------------------------------------

## Answer a pending choice by key ("4:asi", "3:subclass", "knack:4", "boon").
func answer(choice_id: String, ans: Array) -> void:
	_send(RulesCodec.K.ANSWER, RulesCodec.encode_answer(choice_id, ans))

## Pick a knack from an open offer.
func pick_knack(id: String) -> void:
	_send(RulesCodec.K.KNACK, RulesCodec.encode_str(id))

## Start a short rest (5 s standing at a campfire).
func rest_short() -> void:
	_send(RulesCodec.K.REST_SHORT, PackedByteArray())

## Lie down in a bed nearby for a long rest.
func rest_long() -> void:
	_send(RulesCodec.K.REST_LONG, PackedByteArray())

## Stop resting.
func stand() -> void:
	_send(RulesCodec.K.STAND, PackedByteArray())

## Hold revive on a downed ally (call again with 0, or revive_stop(), to let go). The host
## counts the hold while you stay in reach.
func revive(target_id: int) -> void:
	_send(RulesCodec.K.REVIVE, RulesCodec.encode_id(target_id))

func revive_stop() -> void:
	revive(0)

## Wake at your bed, a shrine or the spawn now (only when dead).
func respawn() -> void:
	_send(RulesCodec.K.RESPAWN, PackedByteArray())

## Debug (the host must run with `cheats`): op is RulesCodec.Debug.
## Store interface preferences with the character on the host ({quick: [4 slugs]}).
func set_prefs(p: Dictionary) -> void:
	prefs = Character.clean_prefs(p)
	_send(RulesCodec.K.SET_PREFS, RulesCodec.encode_json(prefs, RulesCodec.PREFS_MAX))

func debug(op: int, n := 0) -> void:
	_send(RulesCodec.K.DEBUG, RulesCodec.encode_debug(op, n))

# --- reads ------------------------------------------------------------------------------

func level() -> int:
	return int(sheet.get("level", 0))

func is_downed(id := -1) -> bool:
	return downed.has(cw.my_id if id < 0 and cw != null else id)

## No digging or placing while down (ClientSystem.allow_edit; the host refuses them too).
func allow_edit() -> bool:
	return not is_downed()

func state_of(id: int) -> int:
	return int(downed.get(id, {}).get("state", RulesCodec.Down.UP))

func pending_keys() -> Array:
	return (sheet.get("pending", []) as Array).map(func(p: Dictionary) -> String: return p["key"])

func _send(kind: int, data: PackedByteArray) -> void:
	if cw != null:
		cw.send_sys(sys_id(), kind, data)

var _look_class := ""

## New MoveStats for the own player (items: sparks): applied now, or when it gets up.
func adopt_stats(s: MoveStats) -> void:
	if _base_stats != null:
		_base_stats = s
	elif cw != null:
		cw.stats = s

## The own body is drawn by class (looks.json "player:<class>"): re-add it once the class is
## known (setup() adds it before any sheet).
func _own_look(cls: String) -> void:
	if cw == null or cls == "" or cls == _look_class or cw.body == null:
		return
	_look_class = cls
	cw.actor_added.emit(cw.my_id, {"kind": "player", "size": cw.stats.size, "color": Color(0.85, 0.75, 0.55),
			"name": cw.player_name, "own": true, "slug": "player:" + cls})

## Freeze local movement while down or dead; restore it when up.
func _own_state(state: int) -> void:
	if cw == null or cw.stats == null:
		return
	if state != RulesCodec.Down.UP and _base_stats == null:
		_base_stats = cw.stats
		cw.stats = still(cw.stats)
	elif state == RulesCodec.Down.UP and _base_stats != null:
		cw.stats = _base_stats
		_base_stats = null

## A copy of `s` that cannot run, jump, climb, swim or fly (it still falls).
static func still(s: MoveStats) -> MoveStats:
	var m: MoveStats = MoveStats.from_srd({"walk": 0}, s.size_name)
	m.run_speed = 0.0
	m.ground_accel = 0.0
	m.air_accel = 0.0
	m.turn_accel = 0.0
	m.jump_velocity = 0.0
	m.ladder_speed = 0.0
	m.ladder_side_speed = 0.0
	m.climb_speed = 0.0
	m.swim_speed = 0.0
	m.swim_accel = 0.0
	m.fly_speed = 0.0
	m.burrow_speed = 0.0
	return m
