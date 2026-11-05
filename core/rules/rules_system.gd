## The rules system on the host (HostSystem.RULES): experience and the 100-level track, SRD
## choices, Knacks and deeds, short and long rests, downed, death and respawn. It mirrors each
## character to its owner (CHAR) and downed states to everyone near (DOWNED); the wire format
## is RulesCodec. Contract and numbers: docs/tracks/rules.md.
##
## Calls other systems make (host thread):
##   rules.on_kill(victim, killers)        XP to living players near the victim, kill deeds
##   rules.award_xp(entity_id, n)          XP from anything else (quests, debug)
##   rules.add_deed(entity_id, counter, n) a deed counter (Knacks lists them)
##   rules.refresh(e)                      rebuild the combatant and move stats (gear, sparks)
##   rules.player_dropped(e, crit := false)   a player hit 0 HP, or was hit while down
##   rules.heal(e, amount) -> int          healing that also gets a downed player up
##   rules.is_downed(e) / is_dead(e) -> bool
##   rules.bond(entity_id, key) -> int     Bond strength (0: none), keys "people:dwarf", "beast:wolf"
##   rules.proficiencies(entity_id)        {skills, tools, languages} from Knacks
##   rules.extras(e) -> Dictionary         what items.apply_sparks put in `out` at the last refresh
## Calls it makes, all guarded: items.gear_mods(e), items.apply_sparks(e, stats, out),
## combat.in_combat(e).
class_name RulesSystem
extends HostSystem

const Down := RulesCodec.Down
const Resting := RulesCodec.Resting
const RestEv := RulesCodec.RestEv
const K := RulesCodec.K

## Players within this many tiles of a kill (body centres) get its XP in full.
const XP_RANGE := 24.0
## XP multiplier by monster rank (HostEntity meta "rank"); meta "xp_mult" overrides it and
## meta "xp" replaces the stat block's XP.
const RANK_XP := {"minion": 0.25, "standard": 1.0, "elite": 2.0, "champion": 4.0, "boss": 6.0}
const SHORT_REST_SECONDS := 5.0
## A campfire (bed) tile this many tiles from the body's cells.
const CAMPFIRE_RANGE := 3
const BED_RANGE := 2
## No living monster within this many tiles to start or keep a short or long rest.
const HOSTILE_RADIUS := 12.0
## Moving this far from where a short rest started interrupts it.
const REST_MOVE := 0.6
## SRD: one Long Rest per 24 hours (from the start of the last one).
const LONG_REST_EVERY_HOURS := 24.0
## The night ends at this hour of the day.
const WAKE_HOUR := 6.0
const SAVE_SECONDS := 4.0
const STABLE_SECONDS := 3.0
const RESPAWN_SECONDS := 10.0
const REVIVE_SECONDS := 2.0
## Reviver and downed player body centres at most this far apart (tiles).
const REVIVE_REACH := 3.0
## A downed body may drift this far (tiles) before the host puts it back; it may fall.
const DOWNED_SLIP := 0.3
## Respawn: the nearest shrine within this many tiles of where you died.
const SHRINE_SEARCH := 96
## Ticks between sheet checks (sent only when something but current HP changed).
const SYNC_EVERY := 15

var host: WorldHost
## Accept DEBUG messages (host started with the `cheats` option; tests set it).
var cheats := false
## Tests: d20 results to use before rolling Dice.
var test_d20: Array = []
var _p := {}               ## entity id -> PState
var _campfire := -1
var _bed := -1
var _shrine := -1
var _surface := PackedInt32Array()
var _old_fg := {}          ## Vector2i -> fg id before this tick's change
var _ob_ref: Array = []
var _ob_i := 0

## Per-player rules state (host only; the persistent parts go through save_player).
class PState extends RefCounted:
	var offers: Array = []         ## open Knack offers [{level, options: [id]}]
	var boon_open := false
	var boon := ""
	var bonds := {}                ## key -> strength
	var mark := {}                 ## deeds at the last Knack offer
	var rest_at := -1.0e9          ## game hours when the last long rest started
	var down := 0                  ## RulesCodec.Down
	var save_t := 0.0
	var stable_t := 0.0
	var dead_t := 0.0
	var anchor := Vector2.ZERO     ## where a downed body lies
	var died_at := Vector2.ZERO
	var resting := 0               ## RulesCodec.Resting
	var rest_t := 0.0
	var rest_pos := Vector2.ZERO
	var bed_cell := Vector2i.ZERO
	var revive_target := 0
	var revive_t := 0.0
	var last_hp := -1
	var last_pos := Vector2.ZERO
	var has_pos := false
	var frac := {}                 ## deed counter -> fractional part not yet counted
	var sent_sig := PackedByteArray()
	var sent_choices := {}
	var waiting := PackedStringArray()
	var pending: Array = []
	var pending_ok := false
	var dirty := true
	var extras := {}

func _init() -> void:
	cheats = cmdline_cheats()

## True when the process was started with `cheats` (or cheats=1) after `--`.
static func cmdline_cheats() -> bool:
	for a in OS.get_cmdline_user_args():
		var s := a.trim_prefix("--")
		if s == "cheats" or s == "cheats=1":
			return true
	return false

func sys_id() -> int:
	return HostSystem.RULES

func attach(h: WorldHost) -> void:
	host = h
	TileDefs.ensure()
	_campfire = TileDefs.id("campfire")
	_bed = TileDefs.id("bed")
	_shrine = TileDefs.id("shrine")
	var surf: Variant = h.world.meta.get("surface")
	if surf is Array and (surf as Array).size() == h.world.width:
		_surface = PackedInt32Array(surf)
	else:
		_surface = h.world.scan_surface()
	h.world.tile_changed.connect(_on_tile_changed)

func _on_tile_changed(x: int, y: int, layer: int, old: int, _now: int) -> void:
	if layer == TileWorld.Layer.FG:
		_old_fg[Vector2i(x, y)] = old

func _ps(e: HostEntity) -> PState:
	return _p.get(e.id) if e != null else null

# --- hooks --------------------------------------------------------------------------

func load_player(e: HostEntity, d: Dictionary) -> void:
	var ps := PState.new()
	_p[e.id] = ps
	var ch := e.character
	if ch == null:
		return
	ps.mark = ch.deeds.duplicate()
	if d.is_empty():
		return
	for o: Variant in d.get("offers", []):
		if o is Dictionary:
			ps.offers.append({"level": int(o.get("level", 0)), "options": Array(o.get("options", [])).map(func(x: Variant) -> String: return String(x))})
	ps.boon_open = bool(d.get("boon_open", false))
	ps.boon = String(d.get("boon", ""))
	var bonds: Variant = d.get("bonds", {})
	if bonds is Dictionary:
		for k: String in bonds:
			ps.bonds[k] = int(bonds[k])
	if d.get("mark") is Dictionary:
		ps.mark = Character._ints(d["mark"])
	ps.rest_at = float(d.get("rest_at", -1.0e9))
	var c := e.combatant
	if c != null:
		_restore_spent(c, Array(d.get("slots_spent", [])), Dictionary(d.get("uses_spent", {})))
		var down := int(d.get("down", Down.UP))
		if down == Down.DEAD:
			ps.down = Down.DEAD
			c.stats.current_hp = 0
			c.death_saves.is_dead = true
			ps.died_at = e.body.pos
		elif (down == Down.DOWNED or down == Down.STABLE) and c.stats.current_hp <= 0:
			ps.down = down
			ps.anchor = e.body.pos
			c.death_saves.successes = int(d.get("succ", 0))
			c.death_saves.failures = int(d.get("fail", 0))
			c.death_saves.is_stable = down == Down.STABLE
			c.conditions.add(SRD.Condition.UNCONSCIOUS)

func save_player(e: HostEntity) -> Dictionary:
	var ps := _ps(e)
	if ps == null:
		return {}
	var d := {"v": 1, "offers": ps.offers.duplicate(true), "boon_open": ps.boon_open, "boon": ps.boon,
		"bonds": ps.bonds.duplicate(), "mark": ps.mark.duplicate(), "rest_at": ps.rest_at, "down": ps.down}
	var c := e.combatant
	if c != null:
		d["succ"] = c.death_saves.successes
		d["fail"] = c.death_saves.failures
		var sp := _spent(c)
		d["slots_spent"] = sp[0]
		d["uses_spent"] = sp[1]
		if e.character != null:
			e.character.slots_left = _slots_left(c)
			e.character.uses_left = _uses_left(c)
	return d

func entity_added(_h: WorldHost, e: HostEntity) -> void:
	if not e.is_player() or e.character == null:
		return
	if not _p.has(e.id):
		load_player(e, {})
	var ps := _ps(e)
	refresh(e)
	ps.last_hp = e.combatant.stats.current_hp if e.combatant != null else -1
	if ps.down != Down.UP:
		_send_down(e)
	for o: HostEntity in host.entities.values():
		var ops := _ps(o)
		if o != e and ops != null and ops.down != Down.UP and o.combatant != null:
			host.send_sys(sys_id(), K.DOWNED, RulesCodec.encode_downed(o.id, ops.down,
					o.combatant.death_saves.successes, o.combatant.death_saves.failures), e.id)
	_sync(e, true)

func entity_removed(_h: WorldHost, e: HostEntity) -> void:
	_p.erase(e.id)
	for ps: PState in _p.values():
		if ps.revive_target == e.id:
			ps.revive_target = 0

func handle(_h: WorldHost, e: HostEntity, kind: int, data: PackedByteArray) -> void:
	if _ps(e) == null:
		return
	match kind:
		K.ANSWER:
			var m := RulesCodec.decode_answer(data)
			if m.is_empty():
				return
			var why := answer(e, m["key"], m["answer"])
			if why != "":
				_note(e, "answer refused: " + why)
		K.KNACK:
			var m := RulesCodec.decode_str(data)
			if m.is_empty():
				return
			var why := pick_knack(e, m["text"])
			if why != "":
				_note(e, "knack refused: " + why)
		K.REST_SHORT:
			var why := start_short_rest(e)
			if why != "":
				_rest_msg(e, RestEv.SHORT_STOP, 0, 0, why)
		K.REST_LONG:
			var why := start_long_rest(e)
			if why != "":
				_rest_msg(e, RestEv.BED_STOP, 0, 0, why)
		K.STAND:
			stand(e, "stood up")
		K.REVIVE:
			var id := RulesCodec.decode_id(data)
			if id >= 0:
				var why := revive(e, id)
				if why != "":
					_note(e, "revive refused: " + why)
		K.RESPAWN:
			if not respawn(e):
				_note(e, "respawn refused: you are not dead")
		K.DEBUG:
			var m := RulesCodec.decode_debug(data)
			if m.is_empty():
				return
			if not cheats:
				_note(e, "cheats are off")
				return
			debug(e, int(m["op"]), int(m["n"]))

func tick(h: WorldHost) -> void:
	_scan_edits()
	var players := []
	for e: HostEntity in h.entities.values():
		if e.is_player() and _p.has(e.id) and e.combatant != null:
			players.append(e)
	for e: HostEntity in players:
		_tick_player(e)
	_tick_beds(players)
	var periodic := h.tick_count % SYNC_EVERY == 0
	for e: HostEntity in players:
		var ps := _ps(e)
		if ps != null and (ps.dirty or periodic):
			_sync(e)

# --- experience and levels -------------------------------------------------------------

## XP for a kill: the victim's stat block XP times its rank multiplier, in full to every
## player (not dead) within XP_RANGE of it and to the killers; kill deeds for each of them.
func on_kill(victim: HostEntity, killers: Array = []) -> void:
	if victim == null or victim.is_player():
		return
	var slug := String(victim.look.get("slug", ""))
	var row := host.srd.pack.get_row("monster", slug) if slug != "" else {}
	var xp := int(row.get("data", {}).get("xp", 0))
	if victim.has_meta("xp"):
		xp = int(victim.get_meta("xp"))
	var total := roundi(xp * xp_mult(victim))
	var ctype := String(row.get("data", {}).get("type", "")) if row.get("data", {}).get("type") != null else ""
	if ctype == "" and slug.begins_with("swarm-"):
		ctype = "beast"
	var beast := Knacks.beast_kind(slug)
	var at := victim.body.center() if victim.body != null else Vector2.ZERO
	for e: HostEntity in host.entities.values():
		var ps := _ps(e)
		if not e.is_player() or ps == null or ps.down == Down.DEAD:
			continue
		if not (e.id in killers) and e.body.center().distance_to(at) > XP_RANGE:
			continue
		award_xp(e.id, total, victim.name)
		add_deed(e.id, "kill", 1)
		if ctype != "":
			add_deed(e.id, "kill:" + ctype, 1)
		if beast != "":
			add_deed(e.id, "beast:" + beast, 1)

## A monster's XP multiplier: meta "xp_mult", else RANK_XP[meta "rank"], else 1.
static func xp_mult(victim: HostEntity) -> float:
	if victim.has_meta("xp_mult"):
		return float(victim.get_meta("xp_mult"))
	if victim.has_meta("rank"):
		return float(RANK_XP.get(String(victim.get_meta("rank")), 1.0))
	return 1.0

## Give XP; every threshold crossed is a level with its reward. Returns levels gained.
func award_xp(entity_id: int, n: int, source := "") -> int:
	var e := host.entity(entity_id)
	var ps := _ps(e)
	if ps == null or e.character == null or n <= 0:
		return 0
	var ch := e.character
	ch.xp = mini(ch.xp + n, 0x7fffffff)
	host.send_sys(sys_id(), K.GAIN, RulesCodec.encode_gain(n, source), e.id)
	var gained := 0
	_capture(e)
	while ch.level < LevelTrack.MAX_LEVEL and ch.xp >= LevelTrack.xp_for_level(ch.level + 1):
		var r := ch.gain_level()
		gained += 1
		_apply_reward(e, r)
		host.send_sys(sys_id(), K.LEVEL, RulesCodec.encode_level(ch.level, r), e.id)
	if gained > 0:
		if ps.down != Down.UP:
			ch.hp = 0
		_write_back(e)
		refresh(e)
	else:
		ps.dirty = true
	return gained

func _apply_reward(e: HostEntity, r: int) -> void:
	var ch := e.character
	var ps := _ps(e)
	ps.pending_ok = false
	match r:
		LevelTrack.Reward.KNACK:
			var held := ch.knacks.duplicate()
			for o: Dictionary in ps.offers:
				held.append_array(o["options"])
			var opts := Knacks.offer(held, Knacks.delta(ch.deeds, ps.mark),
					Knacks.offer_seed(ch.name, ch.level, host.world.world_seed), owned_skills(e))
			ps.mark = ch.deeds.duplicate()
			if not opts.is_empty():
				ps.offers.append({"level": ch.level, "options": opts})
		LevelTrack.Reward.CLASS_LEVEL:
			_default_subclass(ch)
		LevelTrack.Reward.EPIC_BOON:
			if ps.boon == "":
				ps.boon_open = true

## SRD 5.2.1 has one subclass per class: it is taken at class level 3 without asking.
func _default_subclass(ch: Character) -> void:
	if ch.class_level() >= 3 and ch.subclass == "":
		var subs := host.srd.subclass_slugs(ch.class_slug)
		if subs.size() == 1:
			ch.subclass = subs[0]

## Skills the character is proficient in (class, background picks, Skilled, Knacks).
func owned_skills(e: HostEntity) -> Array:
	var ch := e.character
	var out: Array = ch.build.get("skills", []).duplicate()
	out.append_array(ch.resolved()["options"].get("extra_skills", []))
	for id: String in ch.knacks:
		var k := Knacks.def(id)
		if k.get("kind") == "skill":
			out.append(String(k["key"]))
	return out

# --- choices --------------------------------------------------------------------------

## Everything waiting for an answer: [{key, kind, label, count, options: [{id, name, ...}],
## class_level}]. SRD choices are keyed "<class level>:<choice id>", Knack offers
## "knack:<level>", the Epic Boon "boon", a subclass "3:subclass".
func pending(e: HostEntity) -> Array:
	var ps := _ps(e)
	if ps == null or e.character == null:
		return []
	if ps.pending_ok:
		return ps.pending
	var ch := e.character
	var out := []
	for p: Dictionary in ch.pending_choices(host.srd):
		var c: Dictionary = p["choice"]
		var opts := []
		for o: Dictionary in c.get("options", []):
			var oo := {"id": String(o["id"]), "name": String(o.get("name", o["id"])), "modelled": bool(o.get("modelled", true))}
			if o.has("level"):
				oo["level"] = int(o["level"])
			opts.append(oo)
		out.append({"key": "%d:%s" % [p["class_level"], c["id"]], "kind": String(c["kind"]),
			"label": "%s (class level %d)" % [c.get("label", c["id"]), p["class_level"]],
			"count": int(c["count"]), "options": opts, "class_level": int(p["class_level"])})
	if ch.class_level() >= 3 and ch.subclass == "":
		var subs := host.srd.subclass_slugs(ch.class_slug)
		if subs.size() > 1:
			out.append({"key": "3:subclass", "kind": "pick", "label": "Subclass", "count": 1, "class_level": 3,
				"options": subs.map(func(s: String) -> Dictionary: return {"id": s, "name": String(host.srd.subclass_row(s).get("name", s))})})
	for o: Dictionary in ps.offers:
		out.append({"key": "knack:%d" % o["level"], "kind": "knack", "label": "Knack (level %d)" % o["level"],
			"count": 1, "class_level": LevelTrack.class_level(o["level"]),
			"options": (o["options"] as Array).map(func(id: String) -> Dictionary: return {"id": id, "name": String(Knacks.def(id).get("name", id))})})
	if ps.boon_open:
		out.append({"key": "boon", "kind": "boon", "label": "Epic Boon", "count": 1, "class_level": 20,
			"options": epic_boons()})
	ps.pending = out
	ps.pending_ok = true
	return out

func epic_boons() -> Array:
	var out := []
	for r: Dictionary in host.srd.pack.rows("feat"):
		if String(r.get("data", {}).get("category", "")) == "epic_boon":
			out.append({"id": String(r["slug"]), "name": String(r["name"])})
	return out

## Answer a pending choice. Returns "" when taken, else why not.
func answer(e: HostEntity, key: String, ans: Array) -> String:
	var ps := _ps(e)
	if ps == null or e.character == null:
		return "no character"
	if key.begins_with("knack:"):
		var lvl := key.trim_prefix("knack:")
		if ans.size() != 1:
			return "pick one knack"
		for o: Dictionary in ps.offers:
			if str(o["level"]) == lvl:
				return _take_knack(e, o, String(ans[0]))
		return "no such knack offer"
	var choice := {}
	for p: Dictionary in pending(e):
		if p["key"] == key:
			choice = p
			break
	if choice.is_empty():
		return "nothing pending as " + key
	var why := validate(choice, ans)
	if why != "":
		return why
	var ch := e.character
	_capture(e)
	if key == "boon":
		ps.boon = String(ans[0])
		ps.boon_open = false
	elif key == "3:subclass":
		ch.subclass = String(ans[0])
	else:
		var cut := key.find(":")
		ch.answer_choice(int(key.substr(0, cut)), key.substr(cut + 1), ans.map(func(a: Variant) -> String: return String(a)))
	ps.pending_ok = false
	_write_back(e)
	refresh(e)
	return ""

## Is `ans` a valid answer to `choice` (as pending() gives it)? "" if so.
static func validate(choice: Dictionary, ans: Array) -> String:
	var ids := (choice["options"] as Array).map(func(o: Dictionary) -> String: return String(o["id"]))
	if ans.is_empty():
		return "empty answer"
	for a: Variant in ans:
		if not a is String:
			return "answers are ids"
	if choice["kind"] == "asi":
		var feat := String(ans[0])
		if not feat in ids:
			return "%s is not an option" % feat
		var rest := ans.slice(1)
		match feat:
			"ability-score-improvement":
				if rest.size() != 2 or not rest.all(func(a: String) -> bool: return a in SRDProgression.ABILITIES):
					return "an Ability Score Improvement names two abilities (the same one twice for +2)"
			"grappler":
				if rest.size() != 1 or not rest[0] in ["str", "dex"]:
					return "Grappler raises str or dex"
			"skilled":
				if rest.size() < 1 or rest.size() > 3 or not rest.all(func(a: String) -> bool: return SRDContent.skill_from(a) >= 0):
					return "Skilled names up to three skills"
			_:
				if not rest.is_empty():
					return "%s takes no details" % feat
		return ""
	if ans.size() != int(choice["count"]):
		return "pick %d" % int(choice["count"])
	var seen := {}
	for a: String in ans:
		if not a in ids:
			return "%s is not an option" % a
		if seen.has(a):
			return "%s twice" % a
		seen[a] = true
	return ""

## Pick a knack from the oldest open offer that has it. "" when taken, else why not.
func pick_knack(e: HostEntity, id: String) -> String:
	var ps := _ps(e)
	if ps == null:
		return "no character"
	for o: Dictionary in ps.offers:
		if id in o["options"]:
			return _take_knack(e, o, id)
	return "%s is not on offer" % id

func _take_knack(e: HostEntity, offer: Dictionary, id: String) -> String:
	var ps := _ps(e)
	if not id in offer["options"]:
		return "%s is not on offer" % id
	var k := Knacks.def(id)
	if k.is_empty():
		return "unknown knack " + id
	if id in e.character.knacks:
		return "already known"
	e.character.knacks.append(id)
	if k.get("kind") == "bond":
		ps.bonds[String(k["key"])] = maxi(1, int(ps.bonds.get(String(k["key"]), 0)))
	ps.offers.erase(offer)
	ps.pending_ok = false
	refresh(e)
	return ""

## Answer everything open with the addon's auto answers and each class's preferences (Knacks
## and boons: the first option). For bots, tests and the DEBUG AUTO op. Returns how many.
func auto_answer(e: HostEntity) -> int:
	var ps := _ps(e)
	if ps == null or e.character == null:
		return 0
	_capture(e)
	var n := e.character.auto_choices(host.srd)
	_default_subclass(e.character)
	_write_back(e)
	while not ps.offers.is_empty():
		var o: Dictionary = ps.offers[0]
		if _take_knack(e, o, String(o["options"][0])) != "":
			ps.offers.pop_front()
		n += 1
	if ps.boon_open:
		var b := epic_boons()
		ps.boon = String(b[0]["id"]) if not b.is_empty() else ""
		ps.boon_open = false
		n += 1
	ps.pending_ok = false
	refresh(e)
	return n

# --- the combatant ----------------------------------------------------------------------

## Rebuild e's combatant from its character (Knack skills, then gear from the items system),
## max HP from the level track with CON after gear, current HP and Hit Point Dice kept,
## spent slots and uses carried over, death saves and conditions kept; recompute MoveStats
## (items.apply_sparks) onto e.stats, and resync the owner.
func refresh(e: HostEntity) -> void:
	var ch := e.character if e != null else null
	if ch == null:
		return
	var old := e.combatant
	var spent := [[], {}]
	if old != null:
		_capture(e)
		spent = _spent(old)
	_default_subclass(ch)
	var c := ch.make_combatant(host.srd)
	if c == null:
		return
	for id: String in ch.knacks:
		var k := Knacks.def(id)
		if k.get("kind") == "skill":
			var sk := SRDContent.skill_from(String(k["key"]))
			if sk >= 0 and not c.stats.is_skill_proficient(sk as SRD.Skill):
				c.stats.set_skill_proficiency(sk as SRD.Skill, true)
	var items := host.system(HostSystem.ITEMS)
	if items != null and items.has_method("gear_mods"):
		var mods: Variant = items.call("gear_mods", e)
		if mods is Array and not (mods as Array).is_empty():
			ItemEffects.apply(c, mods)
	c.stats.max_hp = LevelTrack.max_hp(ch.level, c.stats.hit_die, c.stats.ability_modifier(SRD.Ability.CONSTITUTION))
	c.stats.current_hp = clampi(ch.hp, 0, c.stats.max_hp)
	c.stats.hit_dice_remaining = clampi(ch.hit_dice_left, 0, ch.hit_dice_max())
	if old != null:
		_restore_spent(c, spent[0], spent[1])
		c.death_saves = old.death_saves
		c.conditions = old.conditions
		c.effects = old.effects
		c.stats.temp_hp = old.stats.temp_hp
	e.combatant = c
	var stats := ch.move_stats(c)
	var ps := _ps(e)
	var out := {}
	if items != null and items.has_method("apply_sparks"):
		items.call("apply_sparks", e, stats, out)
	e.stats = stats
	if ps != null:
		ps.extras = out
		ps.pending_ok = false
		ps.dirty = true
		ps.last_hp = c.stats.current_hp

## Combatant HP and Hit Point Dice into the character record (gear CON may raise the max
## above Character.max_hp: the level-track max of the combatant bounds it here).
func _capture(e: HostEntity) -> void:
	var c := e.combatant
	if c == null or e.character == null:
		return
	e.character.hp = clampi(c.stats.current_hp, 0, c.stats.max_hp)
	e.character.hit_dice_left = clampi(c.stats.hit_dice_remaining, 0, e.character.hit_dice_max())

## The character record's HP and Hit Point Dice onto the current combatant (after a level or
## an answer changed them), so the next refresh keeps them.
func _write_back(e: HostEntity) -> void:
	var c := e.combatant
	if c == null:
		return
	c.stats.max_hp = maxi(c.stats.max_hp, e.character.max_hp())
	c.stats.current_hp = e.character.hp
	c.stats.hit_dice_remaining = e.character.hit_dice_left

## [slots spent per level (9), {resource: uses spent}]
static func _spent(c: Combatant) -> Array:
	var slots := []
	for i in 9:
		slots.append(c.energy_slots.slots_max[i] - c.energy_slots.slots_remaining[i] if c.energy_slots != null else 0)
	var uses := {}
	if c.kit != null:
		for k: String in c.kit.resources:
			var r: Dictionary = c.kit.resources[k]
			uses[k] = int(r["max"]) - int(r["current"])
	return [slots, uses]

static func _restore_spent(c: Combatant, slots: Array, uses: Dictionary) -> void:
	if c.energy_slots != null:
		for i in mini(9, slots.size()):
			c.energy_slots.slots_remaining[i] = clampi(c.energy_slots.slots_max[i] - int(slots[i]), 0, c.energy_slots.slots_max[i])
	if c.kit != null:
		for k: String in uses:
			if c.kit.resources.has(k):
				var r: Dictionary = c.kit.resources[k]
				r["current"] = clampi(int(r["max"]) - int(uses[k]), 0, int(r["max"]))

static func _slots_left(c: Combatant) -> Array:
	var out := []
	if c.energy_slots != null:
		for i in 9:
			out.append(c.energy_slots.slots_remaining[i])
	return out

static func _uses_left(c: Combatant) -> Dictionary:
	var out := {}
	if c.kit != null:
		for k: String in c.kit.resources:
			out[k] = int(c.kit.resources[k]["current"])
	return out

# --- deeds ------------------------------------------------------------------------------

func add_deed(entity_id: int, counter: String, n := 1) -> void:
	var e := host.entity(entity_id)
	if e != null and e.character != null:
		Knacks.add_deed(e.character.deeds, counter, n)

func _acc(e: HostEntity, ps: PState, counter: String, amount: float) -> void:
	if amount <= 0.0:
		return
	var f := float(ps.frac.get(counter, 0.0)) + amount
	var whole := floori(f + 1e-6)
	ps.frac[counter] = maxf(0.0, f - whole)
	if whole > 0:
		Knacks.add_deed(e.character.deeds, counter, whole)

## Tiles dug and placed this tick, by kind, from the host's edit results.
func _scan_edits() -> void:
	var ob := host.outbox
	if not is_same(ob, _ob_ref):
		_ob_ref = ob
		_ob_i = 0
	while _ob_i < ob.size():
		var ev: Dictionary = ob[_ob_i]
		_ob_i += 1
		if int(ev["type"]) != WorldHost.Ev.EDIT_RESULT or int(ev["reason"]) != WorldHost.Reason.OK:
			continue
		var tile := int(ev["tile"])
		if tile == TileDefs.AIR:
			var old := int(_old_fg.get(Vector2i(int(ev["x"]), int(ev["y"])), -1))
			if old > 0:
				add_deed(int(ev["id"]), "dig:" + TileDefs.names[old], 1)
		elif tile < TileDefs.names.size():
			add_deed(int(ev["id"]), "place:" + TileDefs.names[tile], 1)
	_old_fg.clear()

func _deeds_move(e: HostEntity, ps: PState, dt: float) -> void:
	var pos := e.body.pos
	if not ps.has_pos:
		ps.last_pos = pos
		ps.has_pos = true
		return
	var d := pos - ps.last_pos
	ps.last_pos = pos
	if d.length() > 4.0:
		return      # a teleport, not travel
	var f := e.flags
	if f & HostEntity.F_SWIM:
		_acc(e, ps, "swim", d.length())
	elif f & (HostEntity.F_CLIMB | HostEntity.F_CLING):
		_acc(e, ps, "climb", maxf(0.0, d.y))
	elif f & HostEntity.F_FLOOR:
		_acc(e, ps, "run", absf(d.x))
	elif d.y < 0.0:
		_acc(e, ps, "fall", -d.y)
	var sx := clampi(floori(pos.x), 0, _surface.size() - 1) if not _surface.is_empty() else -1
	if sx >= 0 and pos.y < _surface[sx] - 2:
		_acc(e, ps, "underground:" + depth_band(pos.y), dt)

## The depth band at height y for deeds: the world's meta bands (caves, deeps, nadir), with
## "shallows" for underground in the surface band, and "caves" for worlds without bands.
func depth_band(y: float) -> String:
	var bands: Variant = host.world.meta.get("bands")
	if bands is Dictionary:
		for name: String in bands:
			var b: Array = bands[name]
			if y >= float(b[0]) and y <= float(b[1]) + 1.0:
				return "shallows" if name == "surface" or name == "sky" else name
	return "caves"

# --- rests ------------------------------------------------------------------------------

## Start a short rest: standing within CAMPFIRE_RANGE of a campfire, no hostile monster within
## HOSTILE_RADIUS, not in combat, not down. "" when started, else why not.
func start_short_rest(e: HostEntity) -> String:
	var ps := _ps(e)
	if ps == null:
		return "no character"
	if ps.down != Down.UP:
		return "you are down"
	if ps.resting == Resting.SHORT:
		return ""
	if find_tile_near(e, _campfire, CAMPFIRE_RANGE) == NONE:
		return "no campfire within %d tiles" % CAMPFIRE_RANGE
	var why := _unsafe(e)
	if why != "":
		return why
	ps.resting = Resting.SHORT
	ps.rest_t = 0.0
	ps.rest_pos = e.body.pos
	ps.last_hp = e.combatant.stats.current_hp     # only damage from now on interrupts
	ps.dirty = true
	_rest_msg(e, RestEv.SHORT_START)
	return ""

## Lie down in a bed for a long rest: a bed within BED_RANGE, not down, nothing hostile near,
## at most once per LONG_REST_EVERY_HOURS. The night passes when every living player is in bed.
func start_long_rest(e: HostEntity) -> String:
	var ps := _ps(e)
	if ps == null:
		return "no character"
	if ps.down != Down.UP:
		return "you are down"
	if ps.resting == Resting.BED:
		return ""
	var cell := find_tile_near(e, _bed, BED_RANGE)
	if cell == NONE:
		return "no bed within %d tiles" % BED_RANGE
	if not long_rest_ready(e):
		return "you slept less than a day ago"
	var why := _unsafe(e)
	if why != "":
		return why
	ps.resting = Resting.BED
	ps.last_hp = e.combatant.stats.current_hp
	ps.bed_cell = cell
	ps.rest_pos = e.body.pos
	ps.waiting = PackedStringArray()
	ps.dirty = true
	return ""

func long_rest_ready(e: HostEntity) -> bool:
	var ps := _ps(e)
	return ps != null and host.clock.hours() - ps.rest_at >= LONG_REST_EVERY_HOURS - 1e-6

## Stop resting (short or in bed).
func stand(e: HostEntity, why := "") -> void:
	var ps := _ps(e)
	if ps == null or ps.resting == Resting.NONE:
		return
	var ev := RestEv.SHORT_STOP if ps.resting == Resting.SHORT else RestEv.BED_STOP
	ps.resting = Resting.NONE
	ps.waiting = PackedStringArray()
	ps.dirty = true
	_rest_msg(e, ev, 0, 0, why)

func _unsafe(e: HostEntity) -> String:
	if hostile_near(e):
		return "enemies nearby"
	var combat := host.system(HostSystem.COMBAT)
	if combat != null and combat.has_method("in_combat") and bool(combat.call("in_combat", e)):
		return "in combat"
	return ""

## A living monster within HOSTILE_RADIUS (meta "friendly" exempts one).
func hostile_near(e: HostEntity) -> bool:
	var at := e.body.center()
	for m: HostEntity in host.entities.values():
		if m.kind != HostEntity.Kind.MONSTER or m.combatant == null or m.has_meta("friendly"):
			continue
		if m.combatant.is_dead or m.combatant.stats.current_hp <= 0:
			continue
		if m.body.center().distance_to(at) <= HOSTILE_RADIUS:
			return true
	return false

const NONE := Vector2i(-1, -1)

## The nearest cell holding `tile_id` within `r` tiles of the body's cells, or NONE.
func find_tile_near(e: HostEntity, tile_id: int, r: int) -> Vector2i:
	var rect := e.body.rect()
	var x0 := floori(rect.position.x) - r
	var x1 := floori(rect.end.x - 0.001) + r
	var y0 := floori(rect.position.y) - r
	var y1 := floori(rect.end.y - 0.001) + r
	var best := NONE
	var bd := INF
	var c := e.body.center()
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if host.world.in_bounds(x, y) and host.world.get_fg(x, y) == tile_id:
				var d := c.distance_squared_to(Vector2(x + 0.5, y + 0.5))
				if d < bd:
					bd = d
					best = Vector2i(x, y)
	return best

func _tick_short_rest(e: HostEntity, ps: PState, hurt: bool, dt: float) -> void:
	var why := ""
	if hurt:
		why = "hurt"
	elif e.body.pos.distance_to(ps.rest_pos) > REST_MOVE:
		why = "moved"
	elif find_tile_near(e, _campfire, CAMPFIRE_RANGE) == NONE:
		why = "the campfire is gone"
	else:
		why = _unsafe(e)
	if why != "":
		stand(e, why)
		return
	ps.rest_t += dt
	if ps.rest_t < SHORT_REST_SECONDS - 1e-6:
		return
	var c := e.combatant
	var s := c.stats
	var avg := maxf(1.0, s.hit_die / 2.0 + 0.5 + s.ability_modifier(SRD.Ability.CONSTITUTION))
	var dice := mini(s.hit_dice_remaining, ceili((s.max_hp - s.current_hp) / avg))
	var res := SRDRest.short_rest_combatant(c, dice)
	ps.resting = Resting.NONE
	ps.dirty = true
	ps.last_hp = s.current_hp
	add_deed(e.id, "rest", 1)
	_capture(e)
	_rest_msg(e, RestEv.SHORT_DONE, int(res["healed"]), int(res["dice_spent"]))

func _tick_beds(players: Array) -> void:
	var living := []
	var in_bed := []
	for e: HostEntity in players:
		var ps := _ps(e)
		if ps.down == Down.DEAD:
			continue
		living.append(e)
		if ps.resting != Resting.BED:
			continue
		if e.body.pos.distance_to(ps.rest_pos) > BED_RANGE:
			stand(e, "left the bed")
		elif host.world.get_fg(ps.bed_cell.x, ps.bed_cell.y) != _bed:
			stand(e, "the bed is gone")
		else:
			in_bed.append(e)
	if in_bed.is_empty():
		return
	if in_bed.size() == living.size():
		night_passes(in_bed)
		return
	var up := PackedStringArray()
	for e: HostEntity in living:
		if not e in in_bed:
			up.append(e.name)
	for e: HostEntity in in_bed:
		var ps := _ps(e)
		if ps.waiting != up:
			ps.waiting = up
			_rest_msg(e, RestEv.BED_WAIT, 0, 0, "", Array(up))

## Everyone is in bed: the clock jumps to the next WAKE_HOUR through WorldHost.sleep (the sim
## catches up a budget per tick), and each sleeper gets an SRD long rest with all Hit Point
## Dice, and that bed becomes their respawn point.
func night_passes(sleepers: Array) -> void:
	var start := host.clock.hours()
	var hours := WAKE_HOUR - host.clock.hour_of_day()
	if hours <= 0.0:
		hours += WorldClock.HOURS_PER_DAY
	host.sleep(hours)
	for e: HostEntity in sleepers:
		var ps := _ps(e)
		var c := e.combatant
		SRDRest.long_rest_combatant(c)
		c.stats.hit_dice_remaining = e.character.hit_dice_max()
		e.character.bed = ps.bed_cell
		ps.rest_at = start
		ps.resting = Resting.NONE
		ps.waiting = PackedStringArray()
		ps.last_hp = c.stats.current_hp
		ps.dirty = true
		add_deed(e.id, "sleep", 1)
		_capture(e)
		_rest_msg(e, RestEv.BED_DONE, 0, 0, WorldClock.describe(host.clock.hours()))

func _rest_msg(e: HostEntity, ev: int, healed := 0, dice := 0, reason := "", names: Array = []) -> void:
	host.send_sys(sys_id(), K.REST, RulesCodec.encode_rest(ev, healed, dice, reason, names), e.id)

# --- downed and death -------------------------------------------------------------------

## Combat reports a player at 0 HP. Up: they go down. Already down: damage while down, one
## failed death save (two on a critical hit, SRD); a stable player starts saving again.
func player_dropped(e: HostEntity, crit := false) -> void:
	var ps := _ps(e)
	if ps == null or e.combatant == null:
		return
	match ps.down:
		Down.UP:
			_go_down(e)
		Down.DOWNED, Down.STABLE:
			var ds := e.combatant.death_saves
			if ps.down == Down.STABLE:
				ds.is_stable = false
				ps.down = Down.DOWNED
				ps.save_t = 0.0
			ds.on_damage_taken(crit)
			if ds.is_dead:
				_die(e)
			else:
				_send_down(e)

func is_downed(e: HostEntity) -> bool:
	var ps := _ps(e)
	return ps != null and ps.down != Down.UP

func is_dead(e: HostEntity) -> bool:
	var ps := _ps(e)
	return ps != null and ps.down == Down.DEAD

## Heal a player. A downed (or stable) player gets up with `amount` HP. Returns HP restored.
func heal(e: HostEntity, amount: int) -> int:
	var ps := _ps(e)
	if ps == null or e.combatant == null or amount <= 0 or ps.down == Down.DEAD:
		return 0
	var s := e.combatant.stats
	if ps.down != Down.UP:
		s.current_hp = mini(amount, s.max_hp)
		_get_up(e)
		return s.current_hp
	var got := s.heal(amount)
	ps.last_hp = s.current_hp
	ps.dirty = true
	return got

## Start (target_id > 0) or stop (0) holding revive on a downed ally. "" if accepted.
func revive(e: HostEntity, target_id: int) -> String:
	var ps := _ps(e)
	if ps == null:
		return "no character"
	if target_id == 0:
		ps.revive_target = 0
		return ""
	var t := host.entity(target_id)
	var tps := _ps(t)
	if tps == null or t == e:
		return "no one to revive"
	if ps.down != Down.UP:
		return "you are down"
	if tps.down != Down.DOWNED and tps.down != Down.STABLE:
		return "%s is not down" % t.name
	if t.body.center().distance_to(e.body.center()) > REVIVE_REACH:
		return "out of reach"
	if ps.revive_target != target_id:
		ps.revive_target = target_id
		ps.revive_t = 0.0
	return ""

## A dead player wakes at their bed (if it still stands), else the nearest shrine within
## SHRINE_SEARCH tiles of where they died, else the world spawn, rested: full HP, Hit Point
## Dice, slots and uses. False if not dead.
func respawn(e: HostEntity) -> bool:
	var ps := _ps(e)
	if ps == null or ps.down != Down.DEAD:
		return false
	var c := e.combatant
	c.death_saves.revive()
	c.conditions.remove(SRD.Condition.UNCONSCIOUS)
	SRDRest.long_rest_combatant(c)
	c.stats.hit_dice_remaining = e.character.hit_dice_max()
	ps.down = Down.UP
	ps.last_hp = c.stats.current_hp
	ps.dirty = true
	_capture(e)
	teleport(e, respawn_point(e))
	_send_down(e)
	return true

## Where e would respawn now.
func respawn_point(e: HostEntity) -> Vector2:
	var bed: Variant = e.character.bed
	if bed is Vector2i and host.world.in_bounds(bed.x, bed.y) and host.world.get_fg(bed.x, bed.y) == _bed:
		return Vector2(bed.x + 0.5, bed.y)
	var ps := _ps(e)
	var from := ps.died_at if ps != null else e.body.pos
	var fx := floori(from.x)
	var fy := floori(from.y)
	var best := NONE
	var bd := INF
	for y in range(maxi(0, fy - SHRINE_SEARCH), mini(host.world.height, fy + SHRINE_SEARCH + 1)):
		for x in range(maxi(0, fx - SHRINE_SEARCH), mini(host.world.width, fx + SHRINE_SEARCH + 1)):
			if host.world.get_fg(x, y) == _shrine:
				var d := Vector2(x + 0.5, y).distance_squared_to(from)
				if d < bd:
					bd = d
					best = Vector2i(x, y)
	if best != NONE:
		return Vector2(best.x + 0.5, best.y)
	return host.spawn

## Move a client-owned player: the host's copy jumps, the epoch is bumped and a CORRECT goes
## to its owner (the same event WorldHost.submit_state emits), so states from before are
## ignored and the client snaps there.
func teleport(e: HostEntity, pos: Vector2) -> void:
	e.body.pos = pos
	e.body.vel = Vector2.ZERO
	if TileCollision.overlaps_solid(host.world, e.body.rect().grow(-WorldHost.SOLID_SLOP)):
		TileCollision.depenetrate(host.world, e.body)
	TileCollision.update_contacts(host.world, e.body)
	e.epoch = (e.epoch + 1) & 0xffff
	e.last_state_tick = host.tick_count
	e.corrections += 1
	var ps := _ps(e)
	if ps != null:
		ps.last_pos = e.body.pos
		ps.anchor = e.body.pos
	host.outbox.append({"type": WorldHost.Ev.CORRECT, "id": e.id, "owner": e.owner, "epoch": e.epoch,
			"pos": e.body.pos, "vel": Vector2.ZERO, "why": WorldHost.StateCheck.OK})

func _d20() -> int:
	if not test_d20.is_empty():
		return int(test_d20.pop_front())
	return Dice.roll_d20()

func _go_down(e: HostEntity) -> void:
	var ps := _ps(e)
	var c := e.combatant
	ps.down = Down.DOWNED
	ps.save_t = 0.0
	ps.anchor = e.body.pos
	ps.revive_target = 0
	c.stats.current_hp = 0
	c.death_saves.revive()
	c.conditions.add(SRD.Condition.UNCONSCIOUS)
	ps.last_hp = 0
	if ps.resting != Resting.NONE:
		stand(e, "down")
	host.stop_dig(e.id)
	add_deed(e.id, "downed", 1)
	ps.dirty = true
	_send_down(e)

func _get_up(e: HostEntity) -> void:
	var ps := _ps(e)
	var c := e.combatant
	ps.down = Down.UP
	c.stats.current_hp = maxi(1, c.stats.current_hp)
	c.death_saves.revive()
	c.conditions.remove(SRD.Condition.UNCONSCIOUS)
	ps.last_hp = c.stats.current_hp
	ps.dirty = true
	_send_down(e)

func _die(e: HostEntity) -> void:
	var ps := _ps(e)
	ps.down = Down.DEAD
	ps.dead_t = 0.0
	ps.died_at = e.body.pos
	e.combatant.death_saves.is_dead = true
	e.combatant.stats.current_hp = 0
	ps.dirty = true
	_send_down(e)

func _send_down(e: HostEntity) -> void:
	var ps := _ps(e)
	var ds := e.combatant.death_saves
	var msg := RulesCodec.encode_downed(e.id, ps.down, ds.successes, ds.failures)
	host.send_sys_near(sys_id(), K.DOWNED, msg, e.body.pos)
	host.send_sys(sys_id(), K.DOWNED, msg, e.id)    # the owner always hears its own

func _tick_player(e: HostEntity) -> void:
	var ps := _ps(e)
	var c := e.combatant
	var dt := host.dt()
	_deeds_move(e, ps, dt)
	var hp := c.stats.current_hp
	if ps.down == Down.UP and hp <= 0:
		_go_down(e)
	elif (ps.down == Down.DOWNED or ps.down == Down.STABLE) and hp > 0:
		_get_up(e)       # healed by something that wrote HP directly
	var hurt := ps.last_hp >= 0 and c.stats.current_hp < ps.last_hp
	ps.last_hp = c.stats.current_hp
	match ps.down:
		Down.DOWNED, Down.STABLE:
			_hold_body(e, ps)
			if e.digging():
				host.stop_dig(e.id)
			if c.death_saves.is_dead:
				_die(e)
			elif ps.down == Down.STABLE:
				ps.stable_t += dt
				if ps.stable_t >= STABLE_SECONDS - 1e-6:
					c.stats.current_hp = 1
					_get_up(e)
			else:
				ps.save_t += dt
				if ps.save_t >= SAVE_SECONDS - 1e-6:
					ps.save_t = 0.0
					var roll := c.death_saves.roll(_d20())
					if roll == 20:
						c.stats.current_hp = 1
						_get_up(e)
					elif c.death_saves.is_dead:
						_die(e)
					else:
						if c.death_saves.is_stable:
							ps.down = Down.STABLE
							ps.stable_t = 0.0
						ps.dirty = true
						_send_down(e)
		Down.DEAD:
			_hold_body(e, ps)
			ps.dead_t += dt
			if ps.dead_t >= RESPAWN_SECONDS - 1e-6:
				respawn(e)
	if ps.down == Down.UP:
		if ps.resting == Resting.SHORT:
			_tick_short_rest(e, ps, hurt, dt)
		elif ps.resting == Resting.BED and hurt:
			stand(e, "hurt")
		if ps.revive_target != 0:
			_tick_revive(e, ps, dt)

## A downed or dead body does not move: the host puts it back if its client moved it
## (falling is allowed).
func _hold_body(e: HostEntity, ps: PState) -> void:
	var p := e.body.pos
	if p.y < ps.anchor.y and absf(p.x - ps.anchor.x) <= DOWNED_SLIP:
		ps.anchor.y = p.y
		return
	if absf(p.x - ps.anchor.x) > DOWNED_SLIP or p.y > ps.anchor.y + DOWNED_SLIP:
		teleport(e, ps.anchor)

func _tick_revive(e: HostEntity, ps: PState, dt: float) -> void:
	var t := host.entity(ps.revive_target)
	var tps := _ps(t)
	if tps == null or (tps.down != Down.DOWNED and tps.down != Down.STABLE) \
			or t.body.center().distance_to(e.body.center()) > REVIVE_REACH:
		ps.revive_target = 0
		return
	ps.revive_t += dt
	if ps.revive_t >= REVIVE_SECONDS - 1e-6:
		ps.revive_target = 0
		t.combatant.stats.current_hp = maxi(1, t.combatant.stats.current_hp)
		_get_up(t)
		add_deed(e.id, "revive", 1)
		_note(t, "%s got you up" % e.name)

# --- debug ------------------------------------------------------------------------------

## DEBUG ops (cheats only): XP n, LEVEL target, AUTO, HURT n, DIE, HEAL n.
func debug(e: HostEntity, op: int, n: int) -> void:
	var ps := _ps(e)
	var c := e.combatant
	match op:
		RulesCodec.Debug.XP:
			award_xp(e.id, n, "debug")
		RulesCodec.Debug.LEVEL:
			var need := LevelTrack.xp_for_level(LevelTrack.clamp_level(n)) - e.character.xp
			if need > 0:
				award_xp(e.id, need, "debug")
		RulesCodec.Debug.AUTO:
			auto_answer(e)
		RulesCodec.Debug.HURT:
			if ps.down == Down.UP:
				c.stats.current_hp = maxi(0, c.stats.current_hp - n)
				if c.stats.current_hp == 0:
					player_dropped(e)
			else:
				player_dropped(e)
		RulesCodec.Debug.DIE:
			if ps.down == Down.UP:
				_go_down(e)
			if ps.down != Down.DEAD:
				_die(e)
		RulesCodec.Debug.HEAL:
			heal(e, n)

# --- what other systems read -------------------------------------------------------------

func bond(entity_id: int, key: String) -> int:
	var ps: PState = _p.get(entity_id)
	return int(ps.bonds.get(key, 0)) if ps != null else 0

func proficiencies(entity_id: int) -> Dictionary:
	var out := {"skills": [], "tools": [], "languages": []}
	var e := host.entity(entity_id)
	if e == null or e.character == null:
		return out
	out["skills"] = owned_skills(e)
	for id: String in e.character.knacks:
		var k := Knacks.def(id)
		match String(k.get("kind", "")):
			"tool":
				out["tools"].append(String(k["key"]))
			"language":
				out["languages"].append(String(k["key"]))
	return out

func extras(e: HostEntity) -> Dictionary:
	var ps := _ps(e)
	return ps.extras if ps != null else {}

# --- the mirror -------------------------------------------------------------------------

## The sheet as CHAR carries it (RulesCodec.encode_sheet).
func sheet(e: HostEntity) -> Dictionary:
	var ch := e.character
	var c := e.combatant
	var ps := _ps(e)
	var scores := []
	for i in 6:
		scores.append(c.stats.get_ability(i as SRD.Ability))
	var slots := []
	for i in 9:
		slots.append([c.energy_slots.slots_remaining[i], c.energy_slots.slots_max[i]] if c.energy_slots != null else [0, 0])
	var uses := {}
	if c.kit != null:
		for k: String in c.kit.resources:
			uses[k] = [int(c.kit.resources[k]["current"]), int(c.kit.resources[k]["max"])]
	var pend := []
	for p: Dictionary in pending(e):
		pend.append({"key": p["key"], "kind": p["kind"], "label": p["label"], "count": p["count"]})
	return {"level": ch.level, "xp": ch.xp, "xp_level": LevelTrack.xp_for_level(ch.level),
		"xp_next": LevelTrack.xp_for_level(mini(ch.level + 1, LevelTrack.MAX_LEVEL)),
		"class": ch.class_slug, "subclass": ch.subclass if ch.subclass != "" else String(c.kit.subclass_slug if c.kit != null else ""),
		"species": ch.species, "background": ch.background, "class_level": ch.class_level(), "scores": scores,
		"hp": c.stats.current_hp, "max_hp": c.stats.max_hp, "hit_dice": c.stats.hit_dice_remaining,
		"hit_dice_max": ch.hit_dice_max(), "slots": slots, "uses": uses, "spark_slots": ch.spark_slots(),
		"knacks": ch.knacks.duplicate(), "bonds": ps.bonds.duplicate(), "boon": ps.boon, "pending": pend,
		"state": ps.down, "successes": c.death_saves.successes, "failures": c.death_saves.failures,
		"resting": ps.resting, "rest_ready": long_rest_ready(e), "bed": ch.bed}

## Send the owner its new choices (CHOICE) and its sheet (CHAR) when anything but current HP
## changed, or always with `force`.
func _sync(e: HostEntity, force := false) -> void:
	var ps := _ps(e)
	if ps == null or e.combatant == null or e.character == null:
		return
	var pend := pending(e)
	var keys := {}
	for p: Dictionary in pend:
		keys[p["key"]] = true
		if force or not ps.sent_choices.has(p["key"]):
			host.send_sys(sys_id(), K.CHOICE, RulesCodec.encode_choice(p), e.id)
	ps.sent_choices = keys
	var s := sheet(e)
	var bytes := RulesCodec.encode_sheet(s)
	s["hp"] = 0
	var sig := RulesCodec.encode_sheet(s)
	if force or ps.dirty or sig != ps.sent_sig:
		ps.sent_sig = sig
		host.send_sys(sys_id(), K.CHAR, bytes, e.id)
	ps.dirty = false

func _note(e: HostEntity, text: String) -> void:
	host.send_sys(sys_id(), K.NOTE, RulesCodec.encode_str(text), e.id)
