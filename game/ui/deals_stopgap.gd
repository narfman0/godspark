## STOPGAP until the Interface track builds the dialogue, shop and quest screens: talk, trade
## and take work with the keyboard. E near a person (the context prompt says "E: talk to
## <name>, <role>") opens the conversation; a plain parchment panel lists what can be done by
## number, and the same text goes to the log:
##   talking:  1-9 pick an option;  0 or Esc leave
##   shop:     1-9 buy one of a listing;  Shift+1-9 sell one of the n-th sellable stack;
##             Ctrl+1-9 sell the whole stack;  0 back to the talk
##   work:     1-9 take the n-th offer;  0 back
## Every request goes to DealsClient (validated on the host). The Interface track replaces
## this file and its three call sites (GameUi.attach / _unhandled_input, ContextPrompts.tick).
class_name DealsStopgap
extends RefCounted

const RANGE := 4.0

var gu: GameUi
var dc: DealsClient
var lc: LifeClient
var panel: PanelContainer
var label: Label
var _sell_slots: Array = []

func attach(g: GameUi) -> void:
	gu = g
	dc = gu.cw.system(HostSystem.DEALS) as DealsClient
	lc = gu.cw.system(HostSystem.LIFE) as LifeClient
	if dc == null:
		return
	panel = PanelContainer.new()
	panel.name = "deals_stopgap"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = Vector2(24, 120)
	panel.custom_minimum_size = Vector2(560, 0)
	panel.visible = false
	label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(540, 0)
	panel.add_child(label)
	gu.root.add_child(panel)
	dc.talk_changed.connect(func(_c: Dictionary) -> void: _redraw(true))
	dc.shop_changed.connect(func(_s: Dictionary) -> void: _redraw(true))
	dc.quests_changed.connect(func(_q: Array) -> void: _redraw(false))
	dc.rumour_heard.connect(func(list: Array) -> void:
		for r: Dictionary in list:
			gu.toast("Heard: " + String(r.get("text", "")), 4.0))
	dc.note.connect(func(_op: int, ok: bool, word: String) -> void:
		if not ok:
			gu.toast("Deals: " + word, 2.5, UiTheme.BLOOD_DARK))
	dc.patron_changed.connect(func(p: Dictionary) -> void:
		for f: String in p:
			if int(p[f]["tier"]) > 0:
				gu.toast("Patron tier %d with %s" % [int(p[f]["tier"]), p[f]["name"]], 3.0, UiTheme.PLUM))

## The nearest person who talks within RANGE tiles, or 0.
func nearest() -> int:
	if lc == null:
		return 0
	var best := 0
	var bd := RANGE
	var me := gu.cw.body.center()
	for id: int in lc.people:
		if not bool(lc.people[id].get("talk", false)):
			continue
		var r: ClientWorld.RemoteEntity = gu.cw.remotes.get(id)
		if r == null:
			continue
		var d := (r.pos + Vector2(0, r.size.y * 0.5)).distance_to(me)
		if d <= bd:
			bd = d
			best = id
	return best

## ContextPrompts asks: is there someone to talk to here? Sets the prompt and acts on E.
func prompt(e_down: bool) -> bool:
	if dc == null or dc.talking():
		return false
	var id := nearest()
	if id == 0:
		return false
	var p := lc.person(id)
	gu.hud.prompt = {"text": "E: talk to %s, %s" % [String(p.get("name", "")), String(p.get("role", ""))], "sub": "Talk, trade, news and work."}
	if e_down:
		dc.talk(id)
	return true

## Number keys while a conversation is open. True when handled.
func input(event: InputEvent) -> bool:
	if dc == null or not dc.talking() or not event is InputEventKey or not (event as InputEventKey).pressed or (event as InputEventKey).echo:
		return false
	var k := event as InputEventKey
	var n := -1
	if k.keycode >= KEY_0 and k.keycode <= KEY_9:
		n = k.keycode - KEY_0
	elif k.keycode == KEY_ESCAPE:
		n = 0
	if n < 0:
		return false
	var view := String(dc.conversation.get("view", "main"))
	if n == 0:
		if view == "main" or view == "rumours" or view == "patron":
			dc.leave()
		else:
			dc.choose("rumours")    # back to the talk
		return true
	if dc.shopping() and view in ["shop", "smith"]:
		if k.shift_pressed or k.ctrl_pressed:
			if n - 1 < _sell_slots.size():
				var slot: int = _sell_slots[n - 1]
				var it := gu.items.item(slot) if gu.items != null else {}
				dc.sell(slot, Items.count(it) if k.ctrl_pressed and not it.is_empty() else 1)
		else:
			var ls: Array = dc.shop.get("listings", [])
			if n - 1 < ls.size():
				dc.buy(String(ls[n - 1]["id"]), 1)
		return true
	if view == "quests":
		var offers: Array = dc.conversation.get("offers", [])
		if n - 1 < offers.size():
			dc.accept(String(offers[n - 1]["id"]))
		return true
	var opts: Array = dc.conversation.get("options", [])
	if n - 1 < opts.size():
		dc.choose(String(opts[n - 1]["id"]))
	return true

func _redraw(log_it: bool) -> void:
	if panel == null:
		return
	panel.visible = dc.talking()
	if not dc.talking():
		if log_it and String(dc.closed.get("line", "")) != "":
			gu.toast(String(dc.closed["line"]), 2.0)
		return
	var c := dc.conversation
	var lines: Array = ["%s, %s:" % [c.get("name", ""), c.get("role", "")], "\"%s\"" % c.get("line", "")]
	var view := String(c.get("view", "main"))
	for r: Dictionary in c.get("rumours", []):
		lines.append(" - %s%s" % [r["text"], "  (%s, %s)" % [r["dist"], r["dir"]] if int(r["site"]) >= 0 else ""])
	if dc.shopping() and view in ["shop", "smith"]:
		var s := dc.shop
		lines.append("%s of %s (purse %d coin; you have %d):" % ["The rack" if s["kind"] == "smith" else "The shelves", s.get("town", ""),
			int(s.get("wealth", 0)), gu.items.coin() if gu.items != null else 0])
		var i := 1
		for l: Dictionary in s.get("listings", []):
			if i > 9:
				break
			lines.append("  %d. %s  x%d  %d coin" % [i, ItemGen.name(l["item"]), int(l["n"]), int(l["price"])])
			i += 1
		_sell_slots = []
		var sells: Dictionary = s.get("sell", {})
		var keys: Array = sells.keys()
		keys.sort()
		var parts: Array = []
		for slot: int in keys:
			if _sell_slots.size() >= 9:
				break
			_sell_slots.append(slot)
			var it := gu.items.item(slot) if gu.items != null else {}
			parts.append("Shift+%d %s %d" % [_sell_slots.size(), ItemGen.name(it) if not it.is_empty() else "slot %d" % slot, int(sells[slot])])
		if not parts.is_empty():
			lines.append("Sell (each; Ctrl = whole stack): " + ";  ".join(parts))
		lines.append("  0. back")
	elif view == "quests":
		var i := 1
		for q: Dictionary in c.get("offers", []):
			lines.append("  %d. %s  [%s]  %s  Reward: %d coin, %d standing, %d XP" % [i, q["title"], q["state"], q["why"],
				int(q["reward"]["coin"]), int(q["reward"]["standing"]), int(q["reward"]["xp"])])
			lines.append("       %s" % q["goal"])
			i += 1
		lines.append("  0. back")
	else:
		var i := 1
		for o: Dictionary in c.get("options", []):
			lines.append("  %d. %s" % [i, o["label"]])
			i += 1
	var active := dc.quests_in("active")
	if not active.is_empty():
		lines.append("Your work: " + "; ".join(active.map(func(q: Dictionary) -> String: return "%s (%s%s)" % [q["title"], q["state"],
			", " + String(q["progress"].get("text", "")) if String(q["progress"].get("text", "")) != "" else ""])))
	label.text = "\n".join(lines)
	if log_it:
		print("DEALS UI\n  " + "\n  ".join(lines))
