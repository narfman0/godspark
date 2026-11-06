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
## Deals scenario (deals=1, host with cheats and Life): see _deals_step.
var deals_mode := false
var _dn := {}           # request kind -> last answer word ("" until answered)
var _dv := {}           # scenario values (coin before, listing, quest id ...)

## Deals: do the message for real, along the road and back, instead of the complete cheat.
var deals_walk := false

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
			"deals":
				deals_mode = kv.size() < 2 or kv[1] != "0"
			"deals_walk":
				deals_mode = true
				deals_walk = kv.size() < 2 or kv[1] != "0"

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
				if phase == "rejoin" and deals_mode and _dv.has("state") and _t < 8.0 and (_quest_mirror(String(_dv["quest"])).is_empty() \
						or _life() == null or _life().factions.is_empty() or (cw().system(HostSystem.ITEMS) as ItemsClient).coin() == 0):
					return      # wait for QUESTS, FACTIONS and SLOTS
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
					if deals_mode and not _deals_rejoin():
						return
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
				elif deals_mode:
					_deals_start()
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
		"d_goto", "d_talk", "d_shop", "d_buy", "d_give", "d_sell", "d_keeper", "d_ktalk", "d_quests", "d_accept", "d_complete", "d_turn", "d_report", "d_walk":
			_deals_step()
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
	var lc := cw().system(HostSystem.LIFE)
	var live := cw().remotes.values().any(func(r: ClientWorld.RemoteEntity) -> bool:
		return r.kind != HostEntity.Kind.PLAYER and r.max_hp > 0 and r.hp > 0 \
			and not (lc != null and bool(lc.call("is_person", r.id))))
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
	# there is, not more than was dug. A town built on deep paving can give none at all: wait
	# a moment for what was dug to arrive, then go on.
	var ic := c.system(HostSystem.ITEMS) as ItemsClient
	if ic != null and ic.live and placed + ic.held_tiles(_wood) < places:
		places = maxi(1 if _t < 3.0 else 0, placed + ic.held_tiles(_wood))
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
				var spot := c.world.get_fg(floori(c.body.pos.x), floori(c.body.pos.y))
				if c.body.pos.distance_to(at) > 1.0 and not spot in [TileDefs.id("bed"), TileDefs.id("campfire"), TileDefs.id("shrine")]:
					_fail("rules: respawned at %s, not a rest spot; bed at %s" % [c.body.pos, bed])
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

# --- deals scenario (deals=1) -----------------------------------------------------------------

func _deals() -> DealsClient:
	return cw().system(HostSystem.DEALS) as DealsClient if cw() != null else null

func _life() -> LifeClient:
	return cw().system(HostSystem.LIFE) as LifeClient if cw() != null else null

func _deals_start() -> void:
	var dc := _deals()
	if dc == null or _life() == null:
		_fail("deals: no deals or life client system")
		return
	dc.note.connect(func(op: int, _ok: bool, word: String) -> void: _dn[op] = word)
	_dv["role"] = "merchant"
	_go("d_goto")

## Ask the host (a cheat) to stand us beside the nearest `role`; retried until the town shows.
func _ask(kind: int, d: Dictionary) -> void:
	_dn.erase(kind)
	if kind == DealsCodec.Msg.CHEAT:
		_deals().cheat(d)

func _person_near(role: String) -> int:
	var lc := _life()
	var best := 0
	var bd := 6.0
	for id: int in lc.people:
		var p: Dictionary = lc.people[id]
		var r: ClientWorld.RemoteEntity = cw().remotes.get(id)
		if r != null and String(p.get("role", "")) == role and bool(p.get("talk", false)):
			var d := r.pos.distance_to(cw().body.pos)
			if d < bd:
				bd = d
				best = id
	return best

func _slot_of(base: String) -> int:
	var it := cw().system(HostSystem.ITEMS) as ItemsClient
	for i in Inventory.SIZE:
		if String(it.item(i).get("base", "")) == base:
			return i
	return -1

func _count_of(base: String) -> int:
	var it := cw().system(HostSystem.ITEMS) as ItemsClient
	return it.inventory.count_base(base)

func _deals_step() -> void:
	var dc := _deals()
	var items := cw().system(HostSystem.ITEMS) as ItemsClient
	match phase:
		"d_goto", "d_keeper":
			if not _dn.has(DealsCodec.Msg.CHEAT) and _t > 0.2 and not _dv.has("asked"):
				_dv["asked"] = true
				_ask(DealsCodec.Msg.CHEAT, {"op": "goto", "role": _dv["role"]})
			elif _dn.has(DealsCodec.Msg.CHEAT):
				_dv.erase("asked")
				if _dn[DealsCodec.Msg.CHEAT] == "ok":
					_dn.erase(DealsCodec.Msg.CHEAT)
					_go("d_talk" if phase == "d_goto" else "d_ktalk")
				else:
					_dn.erase(DealsCodec.Msg.CHEAT)     # the town is not shown yet: ask again
			if _t > 20.0:
				_fail("deals: never stood beside a %s" % _dv["role"])
		"d_talk", "d_ktalk":
			if _t > 0.6 and not dc.talking() and not _dv.has("talk_sent"):
				_dv["talk_sent"] = true
				get_tree().create_timer(1.0).timeout.connect(func() -> void: _dv.erase("talk_sent"))
				var id := _person_near(String(_dv["role"]))
				if id != 0:
					dc.talk(id)
			if dc.talking():
				_say("deals talk %s, %s: \"%s\"" % [dc.conversation["name"], dc.conversation["role"], dc.conversation["line"]])
				if phase == "d_talk":
					dc.choose("rumours")
					dc.choose("shop")
					_go("d_shop")
				else:
					dc.choose("quests")
					_go("d_quests")
			elif _t > 10.0:
				_fail("deals: could not talk to the %s (%s)" % [_dv["role"], _dn.get(DealsCodec.Msg.TALK_TO, "no answer")])
		"d_shop":
			if dc.shopping():
				var rope := {}
				for l: Dictionary in dc.shop["listings"]:
					if String(l["item"]["base"]) == "tile:rope" and int(l["n"]) > 0:
						rope = l
				if rope.is_empty():
					_fail("deals: no rope on the shelves")
					return
				_dv["rope"] = rope
				_ask(DealsCodec.Msg.CHEAT, {"op": "coin", "n": 200})
				_go("d_buy")
			elif _t > 5.0:
				_fail("deals: the shop never opened")
		"d_buy":
			if not _dv.has("coin0") and _dn.get(DealsCodec.Msg.CHEAT, "") == "ok" and _t > 0.5:
				_dv["coin0"] = items.coin()
				_dv["ropes0"] = _count_of("tile:rope")
				_dn.erase(DealsCodec.Msg.BUY)
				dc.buy(String(_dv["rope"]["id"]), 1)
			if _dn.has(DealsCodec.Msg.BUY) and _t > 1.0:
				if _dn[DealsCodec.Msg.BUY] != "ok":
					_fail("deals: buy refused: " + String(_dn[DealsCodec.Msg.BUY]))
					return
				if items.coin() == int(_dv["coin0"]) - int(_dv["rope"]["price"]) and _count_of("tile:rope") == int(_dv["ropes0"]) + 1:
					_say("deals bought a rope for %d coin (coin %d -> %d)" % [int(_dv["rope"]["price"]), int(_dv["coin0"]), items.coin()])
					_ask(DealsCodec.Msg.CHEAT, {"op": "give", "base": "ore:iron", "n": 6})
					_go("d_give")
			if _t > 8.0:
				_fail("deals: the rope never arrived (coin %d, ropes %d)" % [items.coin(), _count_of("tile:rope")])
		"d_give":
			if _slot_of("ore:iron") >= 0:
				_dv["coin1"] = items.coin()
				_dn.erase(DealsCodec.Msg.SELL)
				dc.sell(_slot_of("ore:iron"), 6)
				_go("d_sell")
			elif _t > 5.0:
				_fail("deals: the ore never arrived")
		"d_sell":
			if _dn.has(DealsCodec.Msg.SELL):
				if _dn[DealsCodec.Msg.SELL] != "ok":
					_fail("deals: sale refused: " + String(_dn[DealsCodec.Msg.SELL]))
					return
				if _slot_of("ore:iron") < 0 and items.coin() > int(_dv["coin1"]):
					_say("deals sold 6 iron ore for %d coin" % (items.coin() - int(_dv["coin1"])))
					dc.leave()
					_dv["role"] = "keeper"
					_dn.erase(DealsCodec.Msg.CHEAT)
					_go("d_keeper")
			if _t > 6.0:
				_fail("deals: the sale never showed")
		"d_quests":
			var offers: Array = dc.conversation.get("offers", []) if dc.talking() else []
			if dc.talking() and (dc.conversation.get("view", "") == "quests" or _t > 1.5):
				var pick := {}
				for q: Dictionary in offers:
					if String(q["kind"]) in ["message", "bounty", "hunt"] and String(q["state"]) == "offered":
						pick = q
						break
				if pick.is_empty():
					if _dv["role"] == "keeper":
						dc.leave()
						_dv["role"] = "guard"
						_dn.erase(DealsCodec.Msg.CHEAT)
						_go("d_keeper")     # try the guards' bounties
						return
					_fail("deals: no message or bounty offered (%s)" % ", ".join(offers.map(func(q: Dictionary) -> String: return q["kind"])))
					return
				_dv["quest"] = String(pick["id"])
				_dn.erase(DealsCodec.Msg.ACCEPT)
				dc.accept(String(pick["id"]))
				_go("d_accept")
			elif _t > 5.0:
				_fail("deals: no work list")
		"d_accept":
			var q := _quest_mirror(String(_dv["quest"]))
			if not q.is_empty() and String(q["state"]) == "active":
				_say("deals accepted %s: %s" % [q["title"], q["goal"]])
				if deals_walk and _walk_start(q):
					dc.leave()
					_go("d_walk")
				else:
					_ask(DealsCodec.Msg.CHEAT, {"op": "complete", "q": _dv["quest"]})
					_go("d_complete")
			elif _t > 5.0:
				_fail("deals: accepting gave %s" % _dn.get(DealsCodec.Msg.ACCEPT, "no answer"))
		"d_walk":
			_walk_step()
		"d_complete":
			var q := _quest_mirror(String(_dv["quest"]))
			if not q.is_empty() and String(q["state"]) == "ready":
				_dv["coin2"] = items.coin()
				_dn.erase(DealsCodec.Msg.TURN_IN)
				dc.turn_in(String(_dv["quest"]))
				_go("d_turn")
			elif _t > 5.0:
				_fail("deals: the quest never became ready (%s)" % _dn.get(DealsCodec.Msg.CHEAT, "no answer"))
		"d_turn":
			var q := _quest_mirror(String(_dv["quest"]))
			if not q.is_empty() and String(q["state"]) == "done" and _t > 1.0:
				var lc := _life()
				var f := String(q.get("faction", ""))
				_say("deals turned in %s: done, coin %d -> %d, standing %d" % [q["title"], int(_dv["coin2"]), items.coin(), lc.standing(f)])
				dc.leave()
				_ask(DealsCodec.Msg.CHEAT, {"op": "report"})
				_go("d_report")
			elif _dn.get(DealsCodec.Msg.TURN_IN, "ok") != "ok":
				_fail("deals: turn in refused: " + String(_dn[DealsCodec.Msg.TURN_IN]))
			elif _t > 6.0:
				_fail("deals: the quest was never done")
		"d_report":
			if _dn.get(DealsCodec.Msg.CHEAT, "") == "ok" and _t > 1.0:
				_dv["state"] = _deals_state()
				print("DEALSCHECK client name=%s %s" % [bot_name, _dv["state"]])
				_go("walk")
			elif _t > 5.0:
				_fail("deals: no report")

## The road from the quest's town to its target (the atlas path, every 8th cell), or false.
func _walk_start(q: Dictionary) -> bool:
	_dv["from"] = Vector2i(cw().body.pos)
	var to := int(q.get("target_site", -1))
	var from := int(q.get("site", -1))
	for r: Dictionary in _deals().routes:
		if (int(r["a"]) == from and int(r["b"]) == to) or (int(r["a"]) == to and int(r["b"]) == from):
			var path: Array = (r["path"] as Array).duplicate()
			if int(r["a"]) != from:
				path.reverse()
			_dv["path"] = path
			_dv["wi"] = 0
			_dv["back"] = false
			_dv["bx"] = cw().body.pos.x
			_dv["bt"] = 0.0
			_say("deals walking the %s to %d: %d points" % [r.get("name", "road"), to, path.size()])
			return true
	# no stored road (a trail): straight across country
	var w: Variant = q.get("where")
	if w is Array and (w as Array).size() == 2:
		var a := Vector2i(cw().body.pos)
		var b := Vector2i(int(w[0]), int(w[1]))
		var path: Array = []
		for k in range(1, 1 + maxi(1, absi(b.x - a.x) / 8)):
			var n := maxi(1, absi(b.x - a.x) / 8)
			path.append(Vector2i(a.x + (b.x - a.x) * k / n, a.y + (b.y - a.y) * k / n))
		_dv["path"] = path
		_dv["wi"] = 0
		_dv["back"] = false
		_dv["bx"] = cw().body.pos.x
		_dv["bt"] = 0.0
		_say("deals walking across country to %s: %d points" % [b, path.size()])
		return true
	return false

## Run along the path: W where it rises, S where it falls, jump when stuck; at the far end (the
## quest ready) turn round; back at the start hand it in.
func _walk_step() -> void:
	var path: Array = _dv["path"]
	var i := int(_dv["wi"])
	var body := cw().body
	var q := _quest_mirror(String(_dv["quest"]))
	if not bool(_dv["back"]) and String(q.get("state", "")) == "ready":
		_dv["back"] = true
		_say("deals walked to the far town in %.0f s" % _t)
		var back: Array = path.slice(0, i + 1)
		back.reverse()
		back.append(_dv["from"])
		_dv["path"] = back
		_dv["wi"] = 0
		return
	input = PlayerInput.new()
	if i >= path.size():
		if bool(_dv["back"]):
			_say("deals walked back in %.0f s" % _t)
			_dv["coin2"] = (cw().system(HostSystem.ITEMS) as ItemsClient).coin()
			_dn.erase(DealsCodec.Msg.TURN_IN)
			_deals().turn_in(String(_dv["quest"]))
			_go("d_turn")
		elif _t > 150.0:
			_fail("deals: the road's end is not the town")
		return
	var tgt: Vector2i = path[i]
	var dx := tgt.x + 0.5 - body.pos.x
	if absf(dx) < 3.0:
		_dv["wi"] = i + 1
	input.move_x = signf(dx)
	input.up = tgt.y > body.pos.y + 0.5
	input.down = tgt.y < body.pos.y - 3.0 and absf(dx) < 4.0
	_dv["bt"] = float(_dv["bt"]) + get_process_delta_time()
	if float(_dv["bt"]) > 0.3:
		if absf(body.pos.x - float(_dv["bx"])) < 0.3:
			input.jump = true
			input.jump_pressed = true
		_dv["bx"] = body.pos.x
		_dv["bt"] = 0.0
	if _t > 170.0:
		_fail("deals: lost on the road at %s, heading for %s" % [body.pos, tgt])

func _quest_mirror(qid: String) -> Dictionary:
	for q: Dictionary in _deals().quests:
		if String(q["id"]) == qid:
			return q
	return {}

## What both sides must agree on: coin, ropes, ore, the quest's state, standing with its faction.
func _deals_state() -> String:
	var items := cw().system(HostSystem.ITEMS) as ItemsClient
	var q := _quest_mirror(String(_dv.get("quest", "")))
	var f := String(q.get("faction", ""))
	return "coin=%d rope=%d ore=%d quest=%s standing=%d rumours=%d" % [items.coin(), _count_of("tile:rope"), _count_of("ore:iron"),
		String(q.get("state", "-")), _life().standing(f) if f != "" else 0, _deals().rumours.size()]

## After the rejoin: the quest log, coin, standing and rumours came back.
func _deals_rejoin() -> bool:
	var dc := _deals()
	if dc == null or not _dv.has("state"):
		return true
	var now := _deals_state()
	var was := String(_dv["state"])
	# coin and the rest must match what was there when it left (the walk does not trade)
	if now.get_slice(" rope=", 1) != was.get_slice(" rope=", 1) or now.get_slice(" ", 0) != was.get_slice(" ", 0):
		_fail("deals: after the rejoin %s, before %s" % [now, was])
		return false
	_say("deals rejoin ok " + now)
	return true
