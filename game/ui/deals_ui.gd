## The living world's glue on the interface side (replaces the Deals stopgap): who can be
## talked to here (the in-world prompt over them; E talks), the dialogue panel, number keys in
## a conversation, the words for every Deals answer, rumours heard (and which are marked on the
## map), quest outcomes (a hand-in celebrates; endings the player did not cause arrive as a
## note), standing toasts and patron tier notes. Reads DealsClient and LifeClient; every action
## is a DealsClient request.
class_name DealsUi
extends RefCounted

const RANGE := 4.0

var gu: GameUi
var dc: DealsClient
var lc: LifeClient
var dialogue: DialoguePanel
## The person E would talk to now (0: none), for the prompt over their head.
var target := 0
## Rumour ids the player unticked "mark on map" for.
var unmarked := {}
## Rumours with a place heard since the map was last opened (the map button pulses).
var fresh_marks := 0
## The quest pinned to the HUD tracker ("" none; the first under way is pinned by itself).
var pinned := ""
## faction -> [[delta, why]] standing moves heard this session (newest last, at most 6)
var history := {}
var _qstate := {}
var _q_init := false
var _turning_in := {}
var _ptier := {}
var _p_init := false
var _stand := {}
var _at := -1
var _at_t := 0.0
## site id -> msec of its last banner (no repeat within a minute)
var _bannered := {}

func attach(g: GameUi) -> void:
	gu = g
	dc = gu.cw.system(HostSystem.DEALS) as DealsClient
	lc = gu.cw.system(HostSystem.LIFE) as LifeClient
	if dc == null:
		return
	dialogue = DialoguePanel.new()
	dialogue.setup(gu, self)
	gu.root.add_child(dialogue)
	dialogue.layout(gu.vsize())
	dc.talk_changed.connect(_on_talk)
	dc.shop_changed.connect(_on_shop)
	dc.quests_changed.connect(_on_quests)
	dc.rumour_heard.connect(_on_rumours)
	dc.note.connect(_on_note)
	dc.patron_changed.connect(_on_patrons)
	gu.screen_changed.connect(func(n: String, _open: bool) -> void:
		if n == "shop":
			dialogue.refresh())
	if lc != null:
		lc.standing_changed.connect(_on_standing)
		lc.factions_changed.connect(func() -> void:
			for f: String in lc.factions:
				_stand[f] = lc.standing(f))
		for f: String in lc.factions:
			_stand[f] = lc.standing(f)
	_on_quests(dc.quests)

func talking() -> bool:
	return dc != null and dc.talking()

## The nearest person who talks within RANGE tiles, or 0.
func nearest() -> int:
	if lc == null:
		return 0
	var best := 0
	var bd := RANGE
	var me := gu.cw.body.center()
	var fx: Variant = gu.presenter.get("fx") if gu.presenter != null else null
	var active: Dictionary = fx.plates.active if fx != null and fx.plates != null else {}
	var now := Time.get_ticks_msec()
	for id: int in lc.people:
		if not bool(lc.people[id].get("talk", false)):
			continue
		var r: ClientWorld.RemoteEntity = gu.cw.remotes.get(id)
		if r == null or now - int(active.get(id, -100000)) < 6000:
			continue      # gone, or busy fighting: no talk now
		var d := (r.pos + Vector2(0, r.size.y * 0.5)).distance_to(me)
		if d <= bd:
			bd = d
			best = id
	return best

## ContextPrompts asks: someone to talk to here? Sets `target` (the prompt is drawn over them
## by PeopleMarks) and acts on E.
func prompt(e_down: bool) -> bool:
	target = 0
	if dc == null or dc.talking():
		return false
	var id := nearest()
	if id == 0:
		return false
	target = id
	gu.hud.prompt = {}
	if e_down:
		dc.talk(id)
	return true

func choose(id: String) -> void:
	if id.begins_with("turn_in:"):
		_turning_in[id.trim_prefix("turn_in:")] = true
	dc.choose(id)

## Number keys while a conversation is open (1-9 options, 0 farewell). True when handled.
func input(event: InputEvent) -> bool:
	if not talking() or not dialogue.visible or not event is InputEventKey:
		return false
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return k.keycode >= KEY_0 and k.keycode <= KEY_9      # swallow releases too
	if k.keycode == KEY_0 or k.keycode == KEY_KP_0:
		dc.leave()
		return true
	var i := DealsLogic.option_index(k.keycode)
	if i < 0:
		return false
	var opts: Array = dc.conversation.get("options", [])
	if i < opts.size():
		choose(String(opts[i]["id"]))
	return true

func layout(vs: Vector2) -> void:
	if dialogue != null:
		dialogue.layout(vs)

# --- words ---------------------------------------------------------------------------------------

func faction_name(fid: String) -> String:
	if lc == null:
		return ""
	return String(lc.factions.get(fid, {}).get("name", ""))

func site_label(sid: int) -> String:
	var n := dc.site_name(sid)
	return n if n != "" else "somewhere"

## "Merchant of Dunton, the Tarnby League"
func speaker_line(c: Dictionary) -> String:
	var role := DealsLogic.role_word(String(c.get("role", ""))).capitalize()
	var f := faction_name(String(c.get("faction", "")))
	var sid := int(c.get("site", -1))
	var p: Dictionary = lc.person(int(c.get("id", 0))) if lc != null else {}
	if String(p.get("kind", "")) == "party":
		return "%s with a %s" % [role, DealsLogic.party_plate(String(p.get("party", "")), f, dc.site_name(int(p.get("dest", -1))), "").to_lower()]
	var town := dc.site_name(sid)
	var s := role
	if town != "":
		s += " of " + town
	if f != "":
		s += ", " + f
	return s

## "Dunton: a halfling town of 633 souls"
func town_line(sid: int) -> String:
	var s: Dictionary = dc.sites.get(sid, {})
	if s.is_empty():
		return ""
	return "%s: %s" % [String(s.get("name", "")), DealsLogic.place_line(s)]

func town_state(sid: int) -> String:
	var s: Dictionary = dc.sites.get(sid, {})
	if s.is_empty():
		return ""
	var sl := DealsLogic.state_line(s)
	return "%s. %s" % [sl[0], sl[1]]

func patron_summary(fid: String) -> String:
	var p: Dictionary = dc.patrons.get(fid, {})
	var v := lc.standing(fid) if lc != null else 0
	var t := int(p.get("tier", DealsLogic.tier_of(v)))
	if bool(p.get("suspended", false)):
		return "Your patronage is suspended: standing %d, under the first tier (%d)." % [v, DealsLogic.TIERS[0]]
	if t <= 0:
		return "Standing %d. They take patrons from %d." % [v, DealsLogic.TIERS[0]]
	var next := "the top tier" if t >= 3 else "tier %d at %d" % [t + 1, DealsLogic.TIERS[t]]
	return "Tier %d, standing %d (%s next). Prices %d%% off, a free bed in their inns%s. Gifts given: %d of 3." % [t, v, next,
		5 * t, ", their patron work" if t >= 2 else "", int(p.get("given", 0))]

# --- arriving at places ------------------------------------------------------------------------------

## Twice a second: entering a settlement shows its banner (name, what it is, whose, its
## state); a ruin or lair whose name you know shows on approach.
func tick_places(dt: float) -> void:
	_at_t -= dt
	if _at_t > 0.0 or dc == null or dc.sites.is_empty():
		return
	_at_t = 0.5
	var meta: Dictionary = gu.cw.world.meta
	var me := gu.cw.body.center()
	var here := -1
	var known := MapLogic.discovered(dc.seen, dc.rumours, dc.quests)
	for s: Dictionary in meta.get("sites", []):
		var sid := int(s["id"])
		var kind := String(s["kind"])
		if kind == "settlement":
			if MapLogic.at_site(meta, sid, me, 4.0):
				here = sid
				break
		elif absf(me.x - float(s["x"])) < 40.0 and absf(me.y - float(s["y"])) < 24.0 and known.has(sid) and dc.site_name(sid) != "":
			here = sid
			break
	if here == _at:
		return
	_at = here
	if here < 0:
		return
	var now := Time.get_ticks_msec()
	if now - int(_bannered.get(here, -100000)) < 60000:
		return
	_bannered[here] = now
	gu.hud.place_banner(place_banner(here))

## The banner's words for a site.
func place_banner(sid: int) -> Dictionary:
	var a: Dictionary = dc.sites.get(sid, {})
	var kind := String(a.get("kind", ""))
	if kind == "settlement" and a.has("tier") and not bool(a.get("ruin", false)):
		var f := faction_name(String(a.get("faction", "")))
		var sl := DealsLogic.state_line(a)
		var st := "%s. %s" % [sl[0], sl[1]] if String(sl[0]) != "Quiet" else String(sl[1])
		return {"name": String(a.get("name", "")), "line": DealsLogic.cap(DealsLogic.place_line(a)) + (", " + f if f != "" else ""),
			"state": st, "color": Emblems.culture_color(String(a.get("culture", ""))), "kind": "settlement"}
	if kind == "lair":
		return {"name": String(a.get("name", "")), "line": "A lair. Something lives here%s." % (", and it is not small" if bool(a.get("apex", false)) else ""),
			"state": "Tread softly, or don't.", "color": UiTheme.VERMILION, "kind": "lair"}
	if kind == "portal":
		return {"name": String(a.get("name", "The portal")), "line": "The way to elsewhere.", "state": "", "color": UiTheme.PLUM, "kind": "portal"}
	return {"name": String(a.get("name", "")), "line": "Ruins. Someone lived here once.", "state": "", "color": UiTheme.PARCH_DEEP, "kind": "ruin"}

## The host's own arrival note ("Millburrow, a halfling town of 633 souls"): the banner says it.
func is_arrival_note(t: String) -> bool:
	for sid: int in dc.sites:
		var n := String(dc.sites[sid].get("name", ""))
		if n != "" and t.begins_with(n + ", a"):
			return true
	return false

# --- marks on the map -------------------------------------------------------------------------------

func is_marked(rid: int) -> bool:
	return not unmarked.has(rid)

func set_marked(rid: int, on: bool) -> void:
	if on:
		unmarked.erase(rid)
	else:
		unmarked[rid] = true
	var m: Control = gu.screens.get("map")
	if m != null and m.has_method("refresh"):
		m.call("refresh")

# --- events -----------------------------------------------------------------------------------------

func _on_talk(c: Dictionary) -> void:
	if not c.is_empty():
		gu.hud.talk_hint_fading = true      # they found talking: let the hint go
	if c.is_empty():
		if gu.is_open("shop"):
			gu.close("shop")
		var why := String(dc.closed.get("why", ""))
		var line := String(dc.closed.get("line", ""))
		if why != "" and why != "left":
			gu.toast("%s. %s" % [UiCopy.TALK_CLOSED.get(why, why.capitalize()), line], 3.0, UiTheme.BLOOD_DARK)
		elif line != "":
			gu.toast(line, 1.8)
	dialogue.refresh()
	var ch: Variant = gu.presenter.get("chronicle") if gu.presenter != null else null
	if ch != null and (ch as Object).has_method("set_quiet"):
		ch.call("set_quiet", not c.is_empty())

func _on_shop(s: Dictionary) -> void:
	if not s.is_empty() and gu.factories.has("shop"):
		gu.open("shop")
	elif s.is_empty() and gu.is_open("shop"):
		gu.close("shop")
	dialogue.refresh()

func _on_rumours(list: Array) -> void:
	if list.size() > 12:
		return          # the whole list on join
	for r: Dictionary in list:
		if int(r.get("site", -1)) >= 0:
			fresh_marks += 1
	if not list.is_empty():
		gu.toast("Heard %d new thing%s. Marked on the map [M]." % [list.size(), "" if list.size() == 1 else "s"], 3.0, UiTheme.SKY.darkened(0.4))

func _on_note(op: int, ok: bool, word: String) -> void:
	if ok:
		match op:
			DealsCodec.Msg.ACCEPT:
				gu.toast("Taken on. It's in your log [J].", 2.5, UiTheme.MOSS.darkened(0.4))
			DealsCodec.Msg.SERVICE:
				gu.toast("Paid. Done.", 2.0)
			DealsCodec.Msg.ABANDON:
				gu.toast("Abandoned. Word gets around.", 2.5, UiTheme.BLOOD_DARK)
		return
	gu.toast(UiCopy.deals_refusal(word), 2.8, UiTheme.BLOOD_DARK)

func _on_quests(qs: Array) -> void:
	var now := {}
	for q: Dictionary in qs:
		var id := String(q.get("id", ""))
		var st := String(q.get("state", ""))
		now[id] = st
		var old := String(_qstate.get(id, ""))
		if not _q_init or old == st:
			continue
		if st == "done" and old in ["active", "ready"]:
			if _turning_in.has(id) or old == "ready":
				_celebrate(q)
			else:
				gu.toast("%s: done. %s" % [q.get("title", ""), "Paid where it ended."], 4.0, UiTheme.MOSS.darkened(0.4))
		elif old != "":
			var note := DealsLogic.outcome_note(q, old)
			if note != "":
				gu.toast(note, 5.0, UiTheme.INK if st == "ready" else UiTheme.BLOOD_DARK)
		_turning_in.erase(id)
	_qstate = now
	_q_init = true
	if not (String(now.get(pinned, "")) in ["active", "ready"]):
		pinned = ""
		for q: Dictionary in qs:
			if String(q.get("state", "")) in ["active", "ready"]:
				pinned = String(q["id"])
				break
	var log_s: Control = gu.screens.get("quests")
	if log_s != null and log_s.visible and log_s.has_method("refresh"):
		log_s.call("refresh")

func _celebrate(q: Dictionary) -> void:
	var r: Dictionary = q.get("reward", {})
	gu.hud.banner("Done!", String(q.get("title", "")))
	gu.toast("Paid: %s." % DealsLogic.reward_text(r), 4.0, UiTheme.GOLD.darkened(0.45))
	if bool(r.get("item", false)):
		gu.toast("And a piece from their smith, in your pack.", 4.0, UiTheme.SKY.darkened(0.3))

func _on_patrons(p: Dictionary) -> void:
	for f: String in p:
		var t := int(p[f]["tier"])
		var sus := bool(p[f]["suspended"])
		var old: int = _ptier.get(f, -1)
		var eff := 0 if sus else t
		_ptier[f] = eff
		if not _p_init or old == eff:
			continue
		var nm := String(p[f].get("name", faction_name(f)))
		if eff > old and old >= 0:
			gu.hud.banner("Patron, tier %d" % eff, "%s takes you in. A gift waits with their keeper or priest." % nm)
		elif eff < old:
			gu.hud.banner("Patronage lost", "%s no longer counts you a friend. Gifts given stay given." % nm)
	_p_init = true

func _on_standing(f: String, v: int, why: String) -> void:
	var old: int = _stand.get(f, 0)
	_stand[f] = v
	if v != old:
		var h: Array = history.get(f, [])
		h.append([v - old, why if why != "" else "no reason given"])
		history[f] = h.slice(maxi(0, h.size() - 6))
	if DealsLogic.standing_toast(old, v):
		var col := UiTheme.MOSS.darkened(0.4) if v > old else UiTheme.BLOOD_DARK
		gu.toast("Standing: " + DealsLogic.standing_text(faction_name(f), v - old, why), 3.0, col)
	var s: Control = gu.screens.get("standing")
	if s != null and s.visible and s.has_method("refresh"):
		s.call("refresh")
