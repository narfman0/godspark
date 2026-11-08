## How the forge bodies' feet keep up with the pace: for every synced forge monster the game can
## place, its walk (and run) clip's planted-foot ground speed as ActorBody scales the body, the
## speeds it moves at in game (wander 0.4, a calm person 0.45, a chase 1.0 of its run, at the
## pace of data/movement.json), the playback each needs to keep its feet planted, and the gait
## and playback ActorBody.forge_clip_speed picks (clamped to FORGE_SPEED_MIN..MAX: past them the
## feet slide).
##   godot --headless -s res://tools/gait_probe.gd -- [pace=X] [only=wolf,ogre] [rows=1]
## Prints a PACEGAIT summary: how many bodies keep their feet at each speed, and the medians.
extends SceneTree

const MOVES := {"wander": 0.4, "calm": 0.45, "chase": 1.0}

func _initialize() -> void:
	var o := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		o[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if o.has("pace"):
		MoveStats.pace_override = float(o["pace"])
	var only: PackedStringArray = String(o.get("only", "")).split(",", false)
	var srd := SRDContent.new()
	var mat := StandardMaterial3D.new()
	var planted := {}
	var need := {}
	var n := 0
	var gaits := {}
	for slug: String in _slugs(only):
		var row: Dictionary = srd.pack.get_row("monster", slug)
		if row.is_empty():
			continue
		var d: Dictionary = row.get("data", {})
		var stats := MoveStats.from_srd(WorldHost.monster_speeds(d), WorldHost.monster_size(d))
		if stats.run_speed <= 0.5:
			continue
		var a := ActorBody.build({"slug": slug}, mat)
		if a.kind != "forge":
			a.free()
			continue
		n += 1
		var line := "%-24s walk %2.0f ft  run %5.2f t/s  gaits %s" % [slug, stats.walk, stats.run_speed, _gaits_text(a)]
		for k: String in MOVES:
			var v := stats.run_speed * float(MOVES[k])
			var pick: Array = a.forge_clip_speed("run", Vector2(v, 0))
			var want := a.forge_natural(v)
			var ok: bool = want > 0.0 and want >= ActorBody.FORGE_SPEED_MIN - 1e-3 and want <= ActorBody.FORGE_SPEED_MAX + 1e-3
			planted[k] = int(planted.get(k, 0)) + (1 if ok else 0)
			if want > 0.0:
				(need.get_or_add(k, []) as Array).append(want)
			gaits[String(pick[0])] = int(gaits.get(String(pick[0]), 0)) + 1
			line += "  %s %.2f m/s: %s x%.2f (wants %.2f)%s" % [k, v * K.TILE_M, pick[0], pick[1], want, "" if ok else " SLIDES"]
		if o.has("rows"):
			print(line)
		a.free()
	var med := {}
	for k: String in need:
		var arr: Array = need[k]
		arr.sort()
		med[k] = "%.2f (p10 %.2f, p90 %.2f)" % [arr[arr.size() / 2], arr[arr.size() / 10], arr[arr.size() * 9 / 10]]
	print("PACEGAIT pace %.1f: %d forge bodies; feet planted (playback %.2f-%.2f) %s; playback wanted %s; gaits picked %s" % [
		MoveStats.pace(), n, ActorBody.FORGE_SPEED_MIN, ActorBody.FORGE_SPEED_MAX, planted, med, gaits])
	quit()

func _gaits_text(a: ActorBody) -> String:
	var parts := []
	for c: String in a.forge_gaits():
		parts.append("%s %.2f m/s" % [c, float(a.forge_gaits()[c])])
	return ", ".join(parts)

func _slugs(only: PackedStringArray) -> Array:
	if not only.is_empty():
		return Array(only)
	var out := []
	var dir := DirAccess.open(ForgeMonster.ROOT)
	if dir == null:
		return out
	for f in dir.get_directories():
		if ForgeMonster.is_synced(f):
			out.append(f)
	out.sort()
	return out
