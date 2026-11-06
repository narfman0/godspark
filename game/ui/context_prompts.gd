## What E does here, and the prompts that say so: rest at a campfire (hold E, a ring fills over
## the 5 s; the reason when refused), sleep in a bed (who is still awake), kindle at a shrine
## (opens the constellation), revive a downed ally (hold E), and, when down, the death-save
## overlay; when dead, the respawn prompt (nothing is lost). Also the night-passing fade when
## the clock jumps. Pickup is automatic and needs no key. All requests go to RulesClient.
class_name ContextPrompts
extends RefCounted

const SHORT_REST_S := 5.0
const REVIVE_S := 2.0
const SAVE_EVERY := 4.0

var gu: GameUi
var _rest_t0 := -1.0
var _revive := 0
var _revive_t := 0.0
var _awake: Array = []
var _refusal := ""
var _refusal_t := 0.0
var _down_t := 0.0
var _last_hours := -1.0
var _holding_rest := false
var _e_prev := false

func attach(g: GameUi) -> void:
	gu = g
	if gu.rules == null:
		return
	gu.rules.rest_event.connect(_on_rest)
	gu.rules.downed_changed.connect(func(id: int, _s: int, _a: int, _b: int) -> void:
		if id == gu.cw.my_id:
			_down_t = 0.0)

func _on_rest(ev: Dictionary) -> void:
	match int(ev.get("event", -1)):
		RulesCodec.RestEv.SHORT_START:
			_rest_t0 = 0.0
		RulesCodec.RestEv.SHORT_DONE:
			_rest_t0 = -1.0
			gu.toast("Rested: +%d hit points, %d Hit Point Di%s spent." % [int(ev.get("healed", 0)), int(ev.get("dice", 0)), "e" if int(ev.get("dice", 0)) == 1 else "ce"], 3.5, UiTheme.MOSS.darkened(0.4))
		RulesCodec.RestEv.SHORT_STOP:
			_rest_t0 = -1.0
			_refuse("Can't rest: " + String(ev.get("reason", "")))
		RulesCodec.RestEv.BED_WAIT:
			_awake = ev.get("names", [])
		RulesCodec.RestEv.BED_DONE:
			_awake = []
			gu.toast("Morning. You wake whole, every Hit Point Die back.", 4.0, UiTheme.MOSS.darkened(0.4))
		RulesCodec.RestEv.BED_STOP:
			_awake = []
			var why := String(ev.get("reason", ""))
			if why != "":
				_refuse("Out of bed: " + why)

func _refuse(t: String) -> void:
	_refusal = t
	_refusal_t = 3.0
	gu.toast(t, 3.0, UiTheme.BLOOD_DARK)

## Per frame: decide the prompt, the downed overlay, and act on E.
func tick(dt: float) -> void:
	var cw := gu.cw
	var hud := gu.hud
	var rules := gu.rules
	_refusal_t -= dt
	# the night passing: the clock jumped forward
	var h := cw.hours()
	if _last_hours >= 0.0 and h - _last_hours > 0.5:
		hud.night(h - _last_hours)
	_last_hours = h
	if rules == null:
		hud.prompt = {}
		return
	var e_held := not gu.text_focus() and Input.is_action_pressed("interact")
	var e_down := e_held and not _e_prev
	_e_prev = e_held
	var me := cw.my_id
	var st := rules.state_of(me)
	# down, stable or dead
	if st != RulesCodec.Down.UP:
		_down_t += dt
		var d: Dictionary = rules.downed.get(me, {})
		if st == RulesCodec.Down.DEAD:
			hud.downed = {"dead": true, "title": "Dead", "line": "Nothing is lost: your pack and your stars wait for you.",
				"sub": "Press E to wake at your bed (or the nearest shrine)."}
			if e_down:
				rules.respawn()
		else:
			hud.downed = {"title": "Down!" if st == RulesCodec.Down.DOWNED else "Stable",
				"line": "A death save every 4 s. An ally can hold E to haul you up." if st == RulesCodec.Down.DOWNED else "Breathing. You'll come round in a moment.",
				"successes": int(d.get("successes", 0)), "failures": int(d.get("failures", 0)),
				"next": SAVE_EVERY - fmod(_down_t, SAVE_EVERY) if st == RulesCodec.Down.DOWNED else -1.0}
		hud.prompt = {}
		return
	hud.downed = {}
	var resting := int(rules.sheet.get("resting", RulesCodec.Resting.NONE))
	# resting by a fire
	if resting == RulesCodec.Resting.SHORT or _rest_t0 >= 0.0:
		if _rest_t0 < 0.0:
			_rest_t0 = 0.0
		_rest_t0 += dt
		hud.prompt = {"text": "Resting by the fire...", "sub": "Keep still. Moving or getting hit ends it.", "progress": _rest_t0 / SHORT_REST_S}
		if _holding_rest and not e_held and _rest_t0 < SHORT_REST_S - 0.2:
			rules.stand()
			_rest_t0 = -1.0
		if resting != RulesCodec.Resting.SHORT and _rest_t0 > SHORT_REST_S + 1.0:
			_rest_t0 = -1.0
		if not e_held:
			_holding_rest = false
		return
	if resting == RulesCodec.Resting.BED:
		var sub := "Sleep comes when everyone is abed."
		if not _awake.is_empty():
			sub = ("%s is still awake." % _awake[0]) if _awake.size() == 1 else "Still awake: %s." % ", ".join(_awake)
		hud.prompt = {"text": "Tucked in.  E: get up", "sub": sub, "color": UiTheme.NIGHT}
		if e_down:
			rules.stand()
		return
	# a downed ally within reach
	var ally := Nearby.downed_ally(cw, rules, 3.0)
	if ally != 0:
		var nm := (cw.remotes[ally] as ClientWorld.RemoteEntity).name.capitalize()
		if e_held:
			if _revive != ally:
				_revive = ally
				_revive_t = 0.0
				rules.revive(ally)
			_revive_t += dt
		elif _revive != 0:
			rules.revive_stop()
			_revive = 0
		hud.prompt = {"text": "Hold E to haul %s up" % nm, "sub": "Stay close for two breaths.", "progress": _revive_t / REVIVE_S if _revive != 0 else -1.0, "color": UiTheme.VERMILION}
		return
	elif _revive != 0:
		rules.revive_stop()
		_revive = 0
	# someone to talk to (Deals): the prompt is drawn over them (PeopleMarks)
	if gu.deals_ui != null and gu.deals_ui.prompt(e_down):
		return
	# stations
	if Nearby.has(cw, Nearby.CAMPFIRE, 3):
		var sub2 := _refusal if _refusal_t > 0.0 else "Short rest: spend Hit Point Dice to heal."
		hud.prompt = {"text": "Hold E to rest by the fire", "sub": sub2}
		if e_down:
			rules.rest_short()
			_holding_rest = true
		return
	if Nearby.has(cw, Nearby.BED, 2):
		hud.prompt = {"text": "E: sleep", "sub": _refusal if _refusal_t > 0.0 else "A long rest. The night passes when everyone sleeps."}
		if e_down:
			rules.rest_long()
		return
	if Nearby.has(cw, Nearby.SHRINE, 3):
		hud.prompt = {"text": "E: kindle sparks at the shrine", "sub": "Open your constellation.", "color": UiTheme.PLUM}
		if e_down:
			gu.open("constellation")
		return
	hud.prompt = {}
