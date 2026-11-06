## A scripted client for smoke tests: joins, waits for its area, walks, jumps, digs `digs`
## tiles, places `places` blocks, checks its partial world against the host, leaves,
## rejoins (expecting to come back where it left), checks again and says a final BYE.
## Prints one "BOT ..." line per milestone and the client NETCHECK lines.
## With `rules=1` on the command line (the host needs `cheats`), it first runs the rules
## scenario after joining: debug XP to `rules_level=N` (default 24) with auto answers, a
## campfire and a short rest, a bed and a long rest (waiting for the other bot), then
## `rules_role=down` gets downed, is revived by the `rules_role=revive` bot, dies and
## respawns at its bed. On rejoin it checks the level survived. Lines: "BOT <name> rules ...".
##
##   var bot := BotClient.new(); bot.address = "127.0.0.1"; bot.port = 24650
##   bot.bot_name = "bot1"; bot.finished.connect(...); add_child(bot)
class_name BotClient
extends Node

signal finished(ok: bool)

var address := "127.0.0.1"
var port := NetSession.DEFAULT_PORT
var bot_name := "bot"
var digs := 3
var places := 3
var rejoin := true
## Walking direction: +1 right, -1 left.
var dir := 1
## Seconds to wait before connecting (to join late, after others have edited).
var delay := 0.0
## SRD class for a new character ("" = the host's default).
var bot_class := ""
## Fight first: after joining, walk at the nearest monster and attack it (CombatClient)
## until no live monster is in sight, then go on as usual. Prints "BOT <name> fight ...".
var fight := false
## fight=2: a world where the director keeps spawning: the fight ends after 40 s if this bot
## has killed something, instead of failing.
var fight_soft := false
## A rest interrupted by monsters (director worlds): fight them, then go back to this phase.
var _resume := ""
var _resumes := 0
var _home := Vector2.ZERO
var _join_pos := Vector2.INF
var _kills := 0
var _clear_t := 0.0
var _fight_hooked := false

var session: NetSession
var input := PlayerInput.new()
var errors := PackedStringArray()
var dug := 0
var placed := 0
var refused := 0
var phase := "wait"
var _t := 0.0
var _target := Vector2i(-1, -1)
var _target_t := 0.0
var _tried := {}
var _left_at := Vector2.ZERO
var _check_line := ""
var _check_ok := false
var _check_tag := ""
var _done := false
var _wood := 0
## Rules scenario (rules=1): see the header.
var rules_mode := false
var rules_level := 24
var rules_role := ""
var _rules_evs: Array = []
var _rules_other := 0
var _rules_corr := 0
var _rules_asked := false

func _ready() -> void:
	_wood = TileDefs.id("rubble")     # what digging gives (M4)
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		match kv[0]:
			"rules":
				rules_mode = kv.size() < 2 or kv[1] != "0"
			"rules_level":
				rules_level = int(kv[1]) if kv.size() > 1 else rules_level
			"rules_role":
				rules_role = kv[1] if kv.size() > 1 else ""
			"fight":
				fight_soft = kv.size() > 1 and kv[1] == "2"

func _say(s: String) -> void:
	print("BOT %s %s" % [bot_name, s])

func _fail(why: String) -> void:
	errors.append("%s: %s" % [phase, why])
	_say("FAIL %s: %s" % [phase, why])
	_finish()

func _finish() -> void:
	if _done:
		return
	_done = true
	_say("done ok=%s dug=%d placed=%d refused=%d corrections=%d" % [errors.is_empty(), dug, placed, refused,
			cw().corrections if cw() != null else -1])
	if session != null and session.client_ep != null and session.client_ep.phase != ClientEndpoint.Phase.CLOSED:
		session.leave(Protocol.Why.FINAL if errors.is_empty() else Protocol.Why.LEAVING)
	finished.emit(errors.is_empty())

func _connect() -> void:
	session = NetSession.new()
	session.input_source = func() -> PlayerInput: return input
	session.player_class = bot_class
	add_child(session)
	session.client_closed.connect(_on_closed)
	var err := session.start_client(address, port, bot_name)
	if err != OK:
		_fail("connect error %d" % err)
		return
	session.client_ep.check_result.connect(_on_check)

func _on_closed(reason: int, text: String) -> void:
	if phase != "leave" and not _done:
		_fail("disconnected (%s: %s)" % [Protocol.Why.find_key(reason), text])

func _on_check(tag: String, ok: bool, line: String) -> void:
	print(line)
	_check_tag = tag
	_check_ok = ok
	_check_line = line

func cw() -> ClientWorld:
	return session.client_world() if session != null else null

func _go(p: String) -> void:
	phase = p
	_t = 0.0
	input = PlayerInput.new()
	if session != null:
		session.input_source = func() -> PlayerInput: return input

func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	input.jump_pressed = false
	match phase:
		"wait":
			if _t >= delay:
				_connect()
				_go("join")
		"join", "rejoin":
			var c := cw()
			if c != null and c.area_ready():
				var ep := session.client_ep
				var objs := 0
				for k: Vector2i in c.loaded:
					objs += c.world.chunk_at(k.x, k.y).object_count()
				_say_vitals()
				_say("%s area_ms=%d welcome_ms=%d chunks=%d pos=%.2f,%.2f objects=%d clock=%s chronicle=%d" % [phase,
						roundi(ep.area_at * 1000.0), roundi(ep.welcome_at * 1000.0), c.loaded.size(), c.body.pos.x,
						c.body.pos.y, objs, WorldClock.describe(c.hours()), c.chronicle.size()])
				if phase == "join":
					_join_pos = c.body.pos
				if phase == "join" and fight:
					_go("fight")
					return
				if phase == "rejoin":
					if rules_mode:
						var lv := _rules().level() if _rules() != null else -1
						if lv != rules_level:
							_fail("rules: came back at level %d, left at %d" % [lv, rules_level])
							return
						_say("rules rejoin ok level=%d knacks=%d" % [lv, (_rules().sheet["knacks"] as Array).size()])
					if c.body.pos.distance_to(_left_at) > 0.6:
						_fail("came back at %s, left at %s" % [c.body.pos, _left_at])
						return
					_go("settle_final")
				elif rules_mode:
					_rules_start()
				else:
					_go("walk")
			elif _t > 15.0:
				_fail("no area after 15 s")
		"fight":
			_fight_step(delta)
		"walk":
			input.move_x = dir
			if _t > 1.0:
				_go("jump")
				input.jump = true
				input.jump_pressed = true
		"jump":
			input.jump = _t < 0.25
			if _t > 0.5 and cw().body.on_floor:
				_go("dig")
			elif _t > 4.0:
				_fail("never landed")
		"dig":
			_dig_step()
		"place":
			_place_step()
		"settle_pre", "settle_final":
			if cw().body.on_floor and absf(cw().body.vel.x) < 0.01 and _t > 0.6:
				var tag := "pre" if phase == "settle_pre" else "final"
				_check_tag = ""
				session.client_ep.request_check(tag)
				_go("check_" + tag)
			elif _t > 5.0:
				_fail("never settled")
		"check_pre", "check_final":
			if _check_tag != "":
				if not _check_ok:
					_fail("check %s mismatch" % _check_tag)
					return
				if phase == "check_final":
					_say_vitals()
					_finish()
				elif rejoin:
					_left_at = cw().body.pos
					_go("leave")
					session.leave()
				else:
					_go("settle_final")
			elif _t > 5.0:
				_fail("no check answer")
		"r_back", "r_level", "r_fire", "r_short", "r_bed", "r_sleep", "r_down", "r_dead", "r_up", "r_revive", "r_wait":
			_rules_step()
		"leave":
			if _t > 0.8:
				session.queue_free()
				session = null
				_connect()
				_go("rejoin")

func _fight_step(delta: float) -> void:
	var cc := cw().system(HostSystem.COMBAT) as CombatClient
	if cc == null:
		_fail("no combat client")
		return
	if not _fight_hooked:
		_fight_hooked = true
		cc.event.connect(func(ev: Dictionary) -> void:
			if int(ev["kind"]) == CombatCodec.Ev.DEATH:
				_kills += 1)
	input = cc.fight_step(input)
	var live := cw().remotes.values().any(func(r: ClientWorld.RemoteEntity) -> bool:
		return r.kind != HostEntity.Kind.PLAYER and r.max_hp > 0 and r.hp > 0)
	_clear_t = 0.0 if live else _clear_t + delta
	if _clear_t > 1.0 or _t > 40.0:
		var dmg := cc.events_log.filter(func(ev: Dictionary) -> bool:
			return int(ev["kind"]) == CombatCodec.Ev.DAMAGE and int(ev["src"]) == cw().my_id)
		var rc := _rules()
		var ic := cw().system(HostSystem.ITEMS) as ItemsClient
		var held := 0
		if ic != null:
			for k in Inventory.SIZE:
				held += Items.count(ic.item(k)) if not ic.item(k).is_empty() else 0
		_say("fight killed=%d attacks=%d hits=%d hp=%d/%d level=%d xp=%d items=%d coin=%d %s" % [_kills, cc.sent, dmg.size(),
			cw().hp, cw().max_hp, rc.level() if rc != null else -1, int(rc.sheet.get("xp", -1)) if rc != null else -1,
			held, ic.coin() if ic != null else -1, "done" if not live else "timeout"])
		if live and not (fight_soft and _kills > 0):
			_fail("monsters still standing after 40 s")
			return
		input = PlayerInput.new()
		if _resume != "":
			_say("fight over, back to %s" % _resume)
			_recover(_rules())
			_rules_asked = false
			_go("r_back")
		elif rules_mode and fight_soft:
			# the fight scattered the bots: both go back to where they joined to camp together
			_recover(_rules())
			_home = _join_pos
			_resume = "start"
			_go("r_back")
		elif rules_mode:
			_rules_start()
		else:
			_go("walk")

func _dig_step() -> void:
	var c := cw()
	if dug >= digs:
		_go("place")
		return
	if _t > 30.0:
		_fail("dug only %d of %d" % [dug, digs])
		return
	if _target.x >= 0:
		_target_t += get_process_delta_time()
		if c.world.get_fg(_target.x, _target.y) == TileDefs.AIR:
			dug += 1
			_target = Vector2i(-1, -1)
		elif _target_t > 4.0:
			refused += 1
			_target = Vector2i(-1, -1)
	if _target.x < 0:
		_target = _pick(func(x: int, y: int) -> bool:
			return TileEdit.can_dig(c.world, c.body, x, y), [2, 3, 4, -2, -3], [-1, -2, -3])
		_target_t = 0.0
	input.dig = _target.x >= 0
	input.target = _target

func _place_step() -> void:
	var c := cw()
	# Digging in a town gives back road and building tiles, not rubble: place what rubble
	# there is (at least one), not more than was dug.
	var ic := c.system(HostSystem.ITEMS) as ItemsClient
	if ic != null and ic.live and placed + ic.held_tiles(_wood) < places:
		places = maxi(1, placed + ic.held_tiles(_wood))
	if placed >= places:
		input.place = false
		_target = Vector2i(-1, -1)
		_go("settle_pre")
		return
	if _t > 20.0:
		_fail("placed only %d of %d" % [placed, places])
		return
	if _target.x >= 0:
		_target_t += get_process_delta_time()
		if c.world.get_fg(_target.x, _target.y) == _wood:
			placed += 1
			_target = Vector2i(-1, -1)
		elif _target_t > 2.0:
			refused += 1
			_target = Vector2i(-1, -1)
	if _target.x < 0:
		_target = _pick(func(x: int, y: int) -> bool:
			var others := [c.body]
			for r: ClientWorld.RemoteEntity in c.remotes.values():
				var b := Body.new()
				b.size = r.size
				b.pos = r.pos
				others.append(b)
			return TileEdit.can_place(c.world, c.body, x, y, _wood, others), [-2, -3, -4, 2, 3, 4], [0, 1, 2])
		_target_t = 0.0
	input.place = _target.x >= 0
	input.place_tile = _wood
	input.target = _target

## One line: own hit points and every remote entity with its hit points, e.g.
## "BOT bot1 vitals me=12/12 sees 2: 1 Goblin Warrior monster 10/10, 3 bot2 player 12/12".
func _say_vitals() -> void:
	var c := cw()
	if c == null:
		return
	var seen := PackedStringArray()
	for r: ClientWorld.RemoteEntity in c.remotes.values():
		seen.append("%d %s %s %s" % [r.id, r.name, "player" if r.kind == HostEntity.Kind.PLAYER else "monster",
				"%d/%d" % [r.hp, r.max_hp] if r.max_hp > 0 else "-"])
	_say("vitals me=%d/%d sees %d: %s" % [c.hp, c.max_hp, seen.size(), ", ".join(seen)])

## First untried cell (relative to the feet, x offsets times `dir`) that passes ok(x, y).
func _pick(ok: Callable, dxs: Array, dys: Array) -> Vector2i:
	var c := cw()
	var fx := floori(c.body.pos.x)
	var fy := roundi(c.body.pos.y)
	for dy: int in dys:
		for dx: int in dxs:
			var at := Vector2i(fx + dx * dir, fy + dy)
			if not _tried.has(at) and ok.call(at.x, at.y):
				_tried[at] = true
				return at
	return Vector2i(-1, -1)

# --- rules scenario (rules=1) -------------------------------------------------------

func _rules() -> RulesClient:
	return cw().system(HostSystem.RULES) as RulesClient if cw() != null else null

func _rules_start() -> void:
	var rc := _rules()
	if rc == null:
		_fail("rules: no rules client system")
		return
	rc.rest_event.connect(func(ev: Dictionary) -> void: _rules_evs.append(ev))
	rc.notice.connect(func(text: String) -> void: _say("rules notice: " + text))
	_recover(rc)
	rc.debug(RulesCodec.Debug.LEVEL, rules_level)
	rc.debug(RulesCodec.Debug.AUTO)
	_go("r_level")

func _rules_rest_ev(ev: int) -> Dictionary:
	for e: Dictionary in _rules_evs:
		if int(e["event"]) == ev:
			return e
	return {}

## Place `tile` next to the feet (dx * dir, else the nearest free spot beside it, on
## uneven ground after a fight) until the world shows it. True when there.
func _rules_place(tile: int, dx: int) -> bool:
	var c := cw()
	var fx := floori(c.body.pos.x)
	var fy := floori(c.body.pos.y)
	var at := Vector2i(fx + dx * dir, fy)
	for k in [dx, -dx, dx + 1, -dx - 1, dx + 2, -dx - 2]:
		for dy in [0, 1, -1]:
			var cell := Vector2i(fx + k * dir, fy + dy)
			if c.world.get_fg(cell.x, cell.y) == tile:
				input.place = false
				return true
	var found := false
	for k in [dx, -dx, dx + 1, -dx - 1, dx + 2, -dx - 2, dx + 3, -dx - 3]:
		for dy in [0, 1]:
			var cell := Vector2i(fx + k * dir, fy + dy)
			if not found and TileEdit.can_place(c.world, c.body, cell.x, cell.y, tile, [c.body], c.edit_reach):
				at = cell
				found = true
	input.move_x = 0.0 if found else float(dir)      # nowhere to put it here: walk on a little
	input.place = fmod(_t, 0.4) < 0.2      # press, hold, release, press again
	input.place_tile = tile
	input.target = at
	return false

## A fight may have left the bot down (cheats heal it) or dead (it respawns).
func _recover(rc: RulesClient) -> void:
	if rc.state_of(cw().my_id) == RulesCodec.Down.DEAD:
		rc.respawn()
	elif rc.is_downed():
		rc.debug(RulesCodec.Debug.HEAL, 9999)

## Waits for the other bot are longer on director worlds (it may be fighting).
func _patience() -> float:
	return 3.0 if fight_soft else 1.0

## fight=2 (director worlds): monsters broke a rest; fight them and come back to `resume`.
func _defend(reason: String, resume: String) -> bool:
	if not fight_soft or _resumes >= 5 or not reason in ["enemies nearby", "in combat", "hurt"]:
		return false
	_resumes += 1
	_rules_evs.clear()
	_resume = resume
	_home = cw().body.pos
	_say("rules %s: fighting first" % reason)
	_go("fight")
	return true

func _rules_step() -> void:
	var rc := _rules()
	var c := cw()
	match phase:
		"r_back":
			var dx := _home.x - c.body.pos.x
			input.move_x = signf(dx) if absf(dx) > 0.4 else 0.0
			input.jump = _t > 1.0 and fmod(_t, 1.0) < 0.3 and absf(c.body.vel.x) < 0.5 and absf(dx) > 0.4
			input.jump_pressed = input.jump
			if absf(dx) <= 0.4 and c.body.on_floor:
				var back := _resume
				_resume = ""
				if back == "start":
					_rules_start()
				else:
					_go(back)
			elif _t > 30.0:
				_fail("rules: could not walk back to %s (at %s)" % [_home, c.body.pos])
		"r_level":
			if rc.level() == rules_level and rc.pending_keys().is_empty():
				_say("rules level=%d class_level=%d hp=%d/%d knacks=%d" % [rc.level(), rc.sheet["class_level"],
						rc.sheet["hp"], rc.sheet["max_hp"], (rc.sheet["knacks"] as Array).size()])
				_go("r_fire")
			elif _t > 8.0:
				_fail("rules: level %d, pending %s" % [rc.level(), rc.pending_keys()])
		"r_fire":
			if _rules_place(TileDefs.id("campfire"), 2):
				rc.debug(RulesCodec.Debug.HURT, 5)
				_rules_evs.clear()
				_go("r_short")
			elif _t > 6.0:
				var ic := c.system(HostSystem.ITEMS) as ItemsClient
				var fire := TileDefs.id("campfire")
				_fail("rules: could not place a campfire (at %s, held %d, can edit %s, downed %s, frozen %s, near %s)" % [c.body.pos,
					ic.held_tiles(fire) if ic != null else -1, c._systems_allow_edit(), rc.downed, c.frozen,
					[c.world.get_fg(floori(c.body.pos.x) - 1, floori(c.body.pos.y)), c.world.get_fg(floori(c.body.pos.x) + 1, floori(c.body.pos.y)),
					c.world.get_fg(floori(c.body.pos.x), floori(c.body.pos.y) - 1)]])
		"r_short":
			if _t > (6.0 if _resumes > 0 else 0.5) and not _rules_asked:
				_rules_asked = true      # after a fight, wait out "in combat" first
				rc.rest_short()
			var done := _rules_rest_ev(RulesCodec.RestEv.SHORT_DONE)
			var stop := _rules_rest_ev(RulesCodec.RestEv.SHORT_STOP)
			if not done.is_empty():
				_say("rules short_rest healed=%d dice=%d" % [done["healed"], done["dice"]])
				_go("r_bed")
			elif not stop.is_empty():
				if not _defend(String(stop["reason"]), "r_short"):
					_fail("rules: short rest stopped: " + String(stop["reason"]))
			elif _t > (16.0 if _resumes > 0 else 10.0):
				_fail("rules: short rest never finished (%s)" % [_rules_evs])
		"r_bed":
			if _rules_place(TileDefs.id("bed"), 1):
				_rules_evs.clear()
				rc.rest_long()
				_go("r_sleep")
			elif _t > 6.0:
				_fail("rules: could not place a bed")
		"r_sleep":
			var wait := _rules_rest_ev(RulesCodec.RestEv.BED_WAIT)
			if not wait.is_empty() and not wait.has("said"):
				wait["said"] = true
				_say("rules waiting for %s" % ", ".join(wait["names"]))
			var stop := _rules_rest_ev(RulesCodec.RestEv.BED_STOP)
			if not _rules_rest_ev(RulesCodec.RestEv.BED_DONE).is_empty():
				_say("rules slept until %s bed=%s" % [WorldClock.describe(c.hours()), rc.sheet["bed"]])
				_go("r_wait")
			elif not stop.is_empty():
				if not _defend(String(stop["reason"]), "r_bed"):
					_fail("rules: long rest stopped: " + String(stop["reason"]))
			elif _t > 30.0 * _patience():
				_fail("rules: the night never passed")
		"r_wait":
			if _t > 1.0:
				if rules_role == "down":
					rc.debug(RulesCodec.Debug.HURT, 9999)
					_go("r_down")
				elif rules_role == "revive":
					_go("r_revive")
				else:
					_go("walk")
		"r_down":
			if rc.state_of(c.my_id) == RulesCodec.Down.DOWNED and not rc.has_meta("down_said"):
				rc.set_meta("down_said", true)
				_say("rules downed")
			if rc.has_meta("down_said") and rc.state_of(c.my_id) == RulesCodec.Down.UP:
				_say("rules revived hp=%d" % c.hp)
				rc.debug(RulesCodec.Debug.DIE)
				_go("r_dead")
			elif _t > 20.0 * _patience():
				_fail("rules: never revived")
		"r_dead":
			if rc.state_of(c.my_id) == RulesCodec.Down.DEAD and _rules_corr == 0:
				_rules_corr = c.corrections + 1
				rc.respawn()
			if _rules_corr > 0 and rc.state_of(c.my_id) == RulesCodec.Down.UP and c.corrections >= _rules_corr:
				var bed: Variant = rc.sheet["bed"]
				var at := Vector2(bed.x + 0.5, bed.y) if bed is Vector2i else Vector2.INF
				if c.body.pos.distance_to(at) > 1.0:
					_fail("rules: respawned at %s, bed at %s" % [c.body.pos, bed])
					return
				_say("rules respawned at bed %s hp=%d/%d" % [bed, c.hp, c.max_hp])
				_go("walk")
			elif _t > 10.0:
				_fail("rules: never respawned")
		"r_revive":
			if _rules_other == 0:
				for id: int in rc.downed:
					if int(rc.downed[id]["state"]) == RulesCodec.Down.DOWNED:
						_rules_other = id
						rc.revive(id)
			elif rc.state_of(_rules_other) == RulesCodec.Down.UP:
				var r: ClientWorld.RemoteEntity = c.remotes.get(_rules_other)
				_say("rules revived %s" % (r.name if r != null else str(_rules_other)))
				_go("walk")
			if _t > 25.0 * _patience():
				_fail("rules: no one to revive")
