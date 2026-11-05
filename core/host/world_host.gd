## The authoritative game loop. Owns the TileWorld, every entity, tile edits and (later)
## dice, loot and the sim. Pure core: no nodes, no sockets. The net layer feeds it client
## messages (add_player, submit_state, request_dig, request_place) and drains `outbox`
## each tick; single-player is the same object with one local client.
##
##   var host := WorldHost.new(TileWorld.make_test())
##   var p := host.add_player("ann", peer_id)
##   host.request_dig(p.id, 1, x, y)
##   host.tick()                        # 1 / K.TICK_HZ
##   for ev in host.drain(): ...        # {type: Ev.TILE, ...}
class_name WorldHost
extends RefCounted

## Why an edit was refused. OK = 0 means accepted.
enum Reason { OK, OUT_OF_BOUNDS, OUT_OF_REACH, NOTHING_THERE, UNBREAKABLE, OCCUPIED,
		NO_ANCHOR, BLOCKED, BAD_TILE, NO_ENTITY }
## Outbox event types. Every event is a Dictionary with "type" and the fields below.
##   TILE         x, y, layer, value                    (any tile change, from tile_changed)
##   JOIN         id                                     (an entity appeared)
##   LEAVE        id                                     (an entity is gone)
##   CORRECT      id, owner, epoch, pos, vel, why        (a client's state was refused)
##   EDIT_RESULT  id, owner, req, reason, x, y, tile     (tile = the cell's fg id now)
##   CHRONICLE    lines: PackedStringArray               (new world-history lines)
##   OBJECTS      cx, cy                                 (a chunk's dressing list changed)
##   SYS          sys, kind, data, to, near?             (a system message: to = an entity id
##                                                        or ALL; near: Vector2, players whose
##                                                        interest area covers it)
enum Ev { TILE, JOIN, LEAVE, CORRECT, EDIT_RESULT, CHRONICLE, OBJECTS, SYS }
## send_sys target: every player.
const ALL := -1
## What submit_state decided.
enum StateCheck { OK, STALE, NO_ENTITY, OUT_OF_BOUNDS, TOO_FAST, IN_SOLID }

## Host-sim seconds of extra travel time allowed beyond the wall-clock gap between two
## client states (packets bunch up).
const STATE_SLACK := 0.25
## Tiles of extra travel allowed on each axis per state.
const MOVE_MARGIN := 1.5
## Speed bound multiplier over the body's fastest mode.
const SPEED_MULT := 1.25
## A client's box may overlap solid tiles by this much (float noise at contacts).
const SOLID_SLOP := 0.05
## Most time (us) one tick may spend catching the sim up with the clock. At least one sim
## hour is stepped per tick when behind, so the sim always makes progress.
const SIM_BUDGET_US := 2000
## Lines of history a joining player is sent.
const CHRONICLE_ON_JOIN := 5

var world: TileWorld
var tick_count := 0
## id -> HostEntity, insertion ordered (deterministic iteration).
var entities := {}
## Offline player records by name: {name, pos: [x, y]}. Online players are written back
## on leave and on save.
var records := {}
var outbox: Array[Dictionary] = []
## Seeded from the world seed; installed as the addon's Dice.rng.
var rng := RandomNumberGenerator.new()
var spawn := Vector2.ZERO
## Seam for world saving until Track A's WorldSave lands: func(world: TileWorld, dir: String)
## -> Error. Empty: save() writes players only.
var world_saver := Callable()
## Game time. Advances one tick per tick; saved with the world (host.json).
var clock := WorldClock.new()
## Set when the clock jumped (sleep), so the net layer tells clients at once.
var clock_jumped := false
## The living world (null for worlds without sites, like the test world). Its hour 0 is
## clock hour `sim_origin`; it follows the clock, a budget per tick.
var sim: WorldSim
var sim_origin := 0
## Chronicle entries already turned into CHRONICLE events.
var chronicle_sent := 0
## Per tick that stepped the sim: microseconds spent (for HOSTSTATS and tests).
var sim_usec := PackedInt32Array()
## Systems by id, in the order added (HostSystem).
var systems := {}
## World state of systems not added yet, from load_state: id (String) -> Dictionary.
var _pending_world := {}
## The class a player gets when it has no saved character and asks for none.
var default_class := "fighter"
var _next_id := 1

## One SRD content set per process: building it is expensive (srd_build_usec), and it is
## read-only after that. Build it before the host thread starts (warm_srd) or the first
## join pays for it inside a tick.
static var _srd: SRDContent
static var srd_build_usec := 0
var srd: SRDContent:
	get:
		return shared_srd()

static func shared_srd() -> SRDContent:
	if _srd == null:
		var t0 := Time.get_ticks_usec()
		_srd = SRDContent.new()
		srd_build_usec = Time.get_ticks_usec() - t0
	return _srd

## Build the shared SRDContent now. Returns the build time in microseconds (0 if it existed).
static func warm_srd() -> int:
	if _srd != null:
		return 0
	shared_srd()
	return srd_build_usec

func _init(w: TileWorld) -> void:
	world = w
	rng.seed = hash("dice:%d" % w.world_seed)
	Dice.rng = rng
	spawn = find_spawn(w.width / 2)
	world.tile_changed.connect(_on_tile_changed)
	if not (w.meta.get("sites", []) as Array).is_empty():
		sim = WorldSim.from_meta(w.meta, w.world_seed)
		sim_origin = clock.whole_hours()
		chronicle_sent = sim.chronicle.size()   # founding entries are history, not news

func dt() -> float:
	return 1.0 / K.TICK_HZ

## One host step. Advances held digs and host-simulated bodies.
func tick() -> void:
	Dice.rng = rng     # rules dice are the ticking host's (one host per process in play)
	tick_count += 1
	clock.advance(1)
	if sim != null:
		_step_sim()
	var step_dt := 1.0 / MoveStats.step_hz()
	var steps := maxi(1, MoveStats.step_hz() / K.TICK_HZ)
	for e: HostEntity in entities.values():
		if e.digging():
			_advance_dig(e)
		if e.owner == HostEntity.NO_OWNER and e.brain != null:
			var inp: PlayerInput = e.brain.think(self, e, dt())
			if inp != null:
				e.input = inp
			for i in steps:
				PlayerController.step(world, e.body, e.input, e.stats, step_dt)
				e.input.jump_pressed = false
			e.flags = HostEntity.body_flags(e.body, e.digging())
	for sys: HostSystem in systems.values():
		sys.tick(self)

## Step the sim toward the clock within SIM_BUDGET_US, then queue its new chronicle lines.
func _step_sim() -> void:
	var target := clock.whole_hours() - sim_origin
	if sim.t >= target:
		return
	var t0 := Time.get_ticks_usec()
	while sim.t < target:
		sim.step(1)
		if Time.get_ticks_usec() - t0 >= SIM_BUDGET_US:
			break
	sim_usec.append(Time.get_ticks_usec() - t0)
	if sim.chronicle.size() > chronicle_sent:
		var lines := PackedStringArray()
		for i in range(chronicle_sent, sim.chronicle.size()):
			lines.append(sim.describe(sim.chronicle[i]))
		chronicle_sent = sim.chronicle.size()
		outbox.append({"type": Ev.CHRONICLE, "lines": lines})

## Sim hours still to catch up with the clock (0 when it is current or there is no sim).
func sim_behind() -> int:
	return 0 if sim == null else maxi(0, clock.whole_hours() - sim_origin - sim.t)

## The last n chronicle lines already sent (for a joining player).
func recent_chronicle(n := CHRONICLE_ON_JOIN) -> PackedStringArray:
	var out := PackedStringArray()
	if sim == null:
		return out
	for i in range(maxi(0, chronicle_sent - n), chronicle_sent):
		out.append(sim.describe(sim.chronicle[i]))
	return out

## Take this tick's events.
func drain() -> Array[Dictionary]:
	var out := outbox
	outbox = []
	return out

# --- entities ---------------------------------------------------------------------

## Top of the ground near column x: the spot a Medium body stands on.
func find_spawn(x: int) -> Vector2:
	var top := 0
	for cx in range(x - 1, x + 2):
		for y in range(world.height - 1, -1, -1):
			if world.is_solid(cx, y):
				top = maxi(top, y + 1)
				break
	return Vector2(x + 0.5, top)

## A player joins: its saved record (position, character, systems' parts) or a new level-1
## character of opts.class (default_class when missing or not an SRD class).
func add_player(player_name: String, owner: int, opts := {}) -> HostEntity:
	var e := HostEntity.new()
	e.id = _alloc_id()
	e.kind = HostEntity.Kind.PLAYER
	e.name = player_name
	e.owner = owner
	var rec: Dictionary = records.get(player_name, {})
	var saved: Variant = rec.get("character")
	e.character = Character.from_dict(saved) if saved is Dictionary else null
	if e.character == null:
		var cls := String(opts.get("class", ""))
		if not Character.HIT_DIE.has(cls):
			cls = default_class
		e.character = Character.create(player_name, cls, [], [], "", "", srd)
	e.character.name = player_name
	e.combatant = e.character.make_combatant(srd)
	e.stats = e.character.move_stats(e.combatant)
	e.body = e.stats.make_body()
	e.body.pos = spawn
	e.look = {"kind": "player", "size": e.stats.size, "color": Color(0.85, 0.75, 0.55),
			"slug": "player:" + e.character.class_slug}
	if rec.has("pos"):
		var p := Vector2(float(rec["pos"][0]), float(rec["pos"][1]))
		if world.in_bounds(floori(p.x), floori(p.y)):
			e.body.pos = p
	# Someone built where they left (or the spawn is in rock): step out to the nearest gap.
	if _in_solid(e.body):
		TileCollision.depenetrate(world, e.body)
		if _in_solid(e.body):
			e.body.pos = spawn
	TileCollision.update_contacts(world, e.body)
	e.flags = HostEntity.body_flags(e.body)
	e.last_state_tick = tick_count
	entities[e.id] = e
	outbox.append({"type": Ev.JOIN, "id": e.id})
	var sysrec: Dictionary = rec.get("systems", {})
	for sys: HostSystem in systems.values():
		sys.load_player(e, sysrec.get(str(sys.sys_id()), {}))
		sys.entity_added(self, e)
	return e

## A host-simulated creature, driven by `brain` (null: it stands still). `combatant` (may be
## null) carries its rules state and hit points.
func add_monster(stats: MoveStats, pos: Vector2, brain: Object, look := {}, combatant: Combatant = null) -> HostEntity:
	var e := HostEntity.new()
	e.id = _alloc_id()
	e.kind = HostEntity.Kind.MONSTER
	e.name = String(look.get("name", "monster"))
	e.stats = stats
	e.body = stats.make_body()
	e.body.pos = pos
	TileCollision.depenetrate(world, e.body)
	e.brain = brain
	e.look = look if not look.is_empty() else {"kind": "monster", "size": stats.size, "color": Color(0.6, 0.2, 0.2)}
	e.combatant = combatant
	entities[e.id] = e
	outbox.append({"type": Ev.JOIN, "id": e.id})
	for sys: HostSystem in systems.values():
		sys.entity_added(self, e)
	return e

## An SRD monster from its stat block (srd.make_monster): body size and movement from its
## size and speeds, standing on the ground near `pos`. Null for an unknown slug.
func add_srd_monster(slug: String, pos: Vector2, brain: Object = null) -> HostEntity:
	var row: Dictionary = srd.pack.get_row("monster", slug)
	if row.is_empty():
		return null
	var c := srd.make_monster(slug)
	if c == null:
		return null
	var stats := MoveStats.from_srd(monster_speeds(row.get("data", {})), monster_size(row.get("data", {})))
	var look := {"kind": "monster", "slug": slug, "name": String(row.get("name", slug)), "size": stats.size,
			"color": Color(0.6, 0.2, 0.2)}
	return add_monster(stats, pos, brain, look, c)

## SRD size word of a stat block for bodies: "medium or small" -> "medium"; swarms (no
## size) are Medium.
static func monster_size(d: Dictionary) -> String:
	var s: Variant = d.get("size")
	return String(s).split(" ")[0].to_lower() if s is String and s != "" else "medium"

## SRD speeds of a stat block for MoveStats.from_srd (walk 0 stays 0: a fish has none).
static func monster_speeds(d: Dictionary) -> Dictionary:
	var out := {"walk": 0}
	var spd: Variant = d.get("speed", {})
	if spd is Dictionary:
		for k: String in ["walk", "climb", "swim", "fly", "burrow"]:
			if spd.has(k):
				out[k] = int(spd[k])
		out["hover"] = bool(spd.get("hover", false))
	return out

func remove_entity(id: int) -> void:
	var e: HostEntity = entities.get(id)
	if e == null:
		return
	if e.is_player():
		_store_record(e)
	for sys: HostSystem in systems.values():
		sys.entity_removed(self, e)
	entities.erase(id)
	outbox.append({"type": Ev.LEAVE, "id": id})

func entity(id: int) -> HostEntity:
	return entities.get(id)

func player_named(player_name: String) -> HostEntity:
	for e: HostEntity in entities.values():
		if e.is_player() and e.name == player_name:
			return e
	return null

func player_count() -> int:
	var n := 0
	for e: HostEntity in entities.values():
		if e.is_player():
			n += 1
	return n

func bodies() -> Array:
	var out := []
	for e: HostEntity in entities.values():
		out.append(e.body)
	return out

# --- systems ------------------------------------------------------------------------

## Add a feature system. Its saved world state (if load_state already ran) is handed to it,
## then attach, then entity_added (with load_player for players) for everyone already here.
func add_system(sys: HostSystem) -> void:
	var id := sys.sys_id()
	assert(id > 0 and id <= 255 and not systems.has(id), "system id %d taken or out of range" % id)
	systems[id] = sys
	if _pending_world.has(str(id)):
		sys.load_world(_pending_world[str(id)])
		_pending_world.erase(str(id))
	sys.attach(self)
	for e: HostEntity in entities.values():
		if e.is_player():
			sys.load_player(e, records.get(e.name, {}).get("systems", {}).get(str(id), {}))
		sys.entity_added(self, e)

func system(sys_id: int) -> HostSystem:
	return systems.get(sys_id)

## Queue a SYS message: to one entity's owner (a player's id) or to every player (ALL).
## False (and nothing sent) if the payload is over Protocol's cap.
func send_sys(sys_id: int, kind: int, data: PackedByteArray, to_entity := ALL) -> bool:
	if data.size() > SYS_MAX:
		push_warning("SYS %d/%d: %d bytes is over the cap" % [sys_id, kind, data.size()])
		return false
	outbox.append({"type": Ev.SYS, "sys": sys_id, "kind": kind, "data": data, "to": to_entity})
	return true

## Queue a SYS message for every player whose interest area covers `pos` (tile units).
func send_sys_near(sys_id: int, kind: int, data: PackedByteArray, pos: Vector2) -> bool:
	if data.size() > SYS_MAX:
		push_warning("SYS %d/%d: %d bytes is over the cap" % [sys_id, kind, data.size()])
		return false
	outbox.append({"type": Ev.SYS, "sys": sys_id, "kind": kind, "data": data, "to": ALL, "near": pos})
	return true

## A SYS message from the client owning entity `id`. False if no such system or entity
## (the caller logs it; it is never fatal).
func receive_sys(id: int, sys_id: int, kind: int, data: PackedByteArray) -> bool:
	var sys: HostSystem = systems.get(sys_id)
	var e: HostEntity = entities.get(id)
	if sys == null or e == null:
		return false
	sys.handle(self, e, kind, data)
	return true

## Largest SYS payload (bytes); the same as Protocol.MAX_SYS (core cannot name net/).
const SYS_MAX := 32768

# --- client-owned movement ----------------------------------------------------------

## A client reports its player's state. Accepted states move the host's copy of the body.
## Refused ones (too far for the time elapsed, out of the world, inside solid tiles) put the
## body back where it was last accepted and emit a CORRECT event with a new epoch; states
## from the old epoch are then ignored as STALE until the client has applied the correction.
## `seq` is the client's 60 Hz step counter.
func submit_state(id: int, epoch: int, seq: int, pos: Vector2, vel: Vector2, flags: int) -> StateCheck:
	var e: HostEntity = entities.get(id)
	if e == null:
		return StateCheck.NO_ENTITY
	if epoch != e.epoch or seq <= e.last_seq:
		return StateCheck.STALE
	var host_gap := float(tick_count - e.last_state_tick) / K.TICK_HZ + STATE_SLACK
	var gap := host_gap
	if e.last_seq >= 0:
		gap = minf(float(seq - e.last_seq) / MoveStats.step_hz(), host_gap)
	var verdict := _check_move(e, pos, gap)
	if verdict != StateCheck.OK:
		e.corrections += 1
		e.epoch = (e.epoch + 1) & 0xffff
		e.body.vel = Vector2.ZERO
		e.last_seq = seq
		e.last_state_tick = tick_count
		outbox.append({"type": Ev.CORRECT, "id": id, "owner": e.owner, "epoch": e.epoch,
				"pos": e.body.pos, "vel": Vector2.ZERO, "why": verdict})
		return verdict
	e.body.pos = pos
	e.body.vel = vel
	e.flags = flags
	HostEntity.apply_flags(e.body, flags)
	e.last_seq = seq
	e.last_state_tick = tick_count
	e.states_accepted += 1
	return StateCheck.OK

func _check_move(e: HostEntity, pos: Vector2, gap: float) -> StateCheck:
	if not (is_finite(pos.x) and is_finite(pos.y)):
		return StateCheck.OUT_OF_BOUNDS
	var hw := e.body.size.x * 0.5
	if pos.x - hw < 0.0 or pos.x + hw > world.width or pos.y < 0.0 or pos.y + e.body.size.y > world.height:
		return StateCheck.OUT_OF_BOUNDS
	var s := e.stats
	var horiz := maxf(maxf(s.run_speed, s.fly_speed), maxf(s.swim_speed, s.ladder_side_speed)) * SPEED_MULT
	var up := maxf(maxf(s.jump_velocity, s.fly_speed), maxf(s.ladder_speed, maxf(s.climb_speed, s.swim_speed))) * SPEED_MULT
	var down := maxf(s.terminal_fall, s.fly_speed) * SPEED_MULT
	var d := pos - e.body.pos
	if absf(d.x) > horiz * gap + MOVE_MARGIN + s.step_tiles:
		return StateCheck.TOO_FAST
	if d.y > up * gap + MOVE_MARGIN + s.step_tiles or -d.y > down * gap + MOVE_MARGIN + s.step_tiles:
		return StateCheck.TOO_FAST
	var probe := e.body.duplicate_body()
	probe.pos = pos
	if _in_solid(probe):
		return StateCheck.IN_SOLID
	return StateCheck.OK

func _in_solid(b: Body) -> bool:
	return TileCollision.overlaps_solid(world, b.rect().grow(-SOLID_SLOP))

# --- tile edits ---------------------------------------------------------------------

## Start (or retarget) a held dig. Checked now and again every tick; completes after
## TileEdit.dig_time and emits EDIT_RESULT with reason OK, or with the reason it stopped.
func request_dig(id: int, req: int, x: int, y: int) -> Reason:
	var e: HostEntity = entities.get(id)
	if e == null:
		return Reason.NO_ENTITY
	var why := dig_reason(e, x, y)
	if why != Reason.OK:
		_result(e, req, why, x, y)
		e.dig_target = HostEntity.NO_DIG
		return why
	if e.dig_target != Vector2i(x, y):
		e.dig.reset()
	e.dig_target = Vector2i(x, y)
	e.dig_req = req
	return Reason.OK

## The client let go of the dig button.
func stop_dig(id: int) -> void:
	var e: HostEntity = entities.get(id)
	if e != null:
		e.dig_target = HostEntity.NO_DIG
		e.dig.reset()

func request_place(id: int, req: int, x: int, y: int, tile_id: int) -> Reason:
	var e: HostEntity = entities.get(id)
	if e == null:
		return Reason.NO_ENTITY
	var why := place_reason(e, x, y, tile_id)
	if why == Reason.OK:
		world.set_fg(x, y, tile_id)
	_result(e, req, why, x, y)
	return why

func dig_reason(e: HostEntity, x: int, y: int) -> Reason:
	if not world.in_bounds(x, y):
		return Reason.OUT_OF_BOUNDS
	var id := world.get_fg(x, y)
	if id == TileDefs.AIR:
		return Reason.NOTHING_THERE
	if TileDefs.hardness[id] < 0.0:
		return Reason.UNBREAKABLE
	if not TileEdit.in_reach(e.body, x, y):
		return Reason.OUT_OF_REACH
	return Reason.OK if TileEdit.can_dig(world, e.body, x, y) else Reason.OUT_OF_REACH

func place_reason(e: HostEntity, x: int, y: int, tile_id: int) -> Reason:
	if tile_id <= TileDefs.AIR or tile_id >= TileDefs.solid.size() or TileDefs.names[tile_id] == "" \
			or TileDefs.hardness[tile_id] < 0.0:
		return Reason.BAD_TILE
	if not world.in_bounds(x, y):
		return Reason.OUT_OF_BOUNDS
	if not TileEdit.in_reach(e.body, x, y):
		return Reason.OUT_OF_REACH
	if world.get_fg(x, y) != TileDefs.AIR:
		return Reason.OCCUPIED
	if not TileEdit.can_place(world, e.body, x, y, tile_id, []):
		return Reason.NO_ANCHOR
	if not TileEdit.can_place(world, e.body, x, y, tile_id, bodies()):
		return Reason.BLOCKED
	return Reason.OK

func _advance_dig(e: HostEntity) -> void:
	var at := e.dig_target
	var why := dig_reason(e, at.x, at.y)
	if why != Reason.OK:
		e.dig_target = HostEntity.NO_DIG
		e.dig.reset()
		_result(e, e.dig_req, why, at.x, at.y)
		return
	if e.dig.update(at, world.get_fg(at.x, at.y), dt()):
		e.dig_target = HostEntity.NO_DIG
		world.set_fg(at.x, at.y, TileDefs.AIR)
		_result(e, e.dig_req, Reason.OK, at.x, at.y)

func _result(e: HostEntity, req: int, why: Reason, x: int, y: int) -> void:
	outbox.append({"type": Ev.EDIT_RESULT, "id": e.id, "owner": e.owner, "req": req,
			"reason": why, "x": x, "y": y, "tile": world.get_fg(x, y)})

func _on_tile_changed(x: int, y: int, layer: int, old: int, now: int) -> void:
	outbox.append({"type": Ev.TILE, "x": x, "y": y, "layer": layer, "value": now})
	if layer == TileWorld.Layer.FG and TileDefs.solid[old] != TileDefs.solid[now]:
		# Dug out from under a tree, or a block put into a bush: the host decides.
		for c in Dressing.on_tile_changed(world, x, y):
			world.objects_changed.emit(c.x, c.y)
			outbox.append({"type": Ev.OBJECTS, "cx": c.x, "cy": c.y})

# --- saving -------------------------------------------------------------------------

## Jump the world clock ahead (sleeping; the sleep=HOURS option and debug keys).
func sleep(h: float) -> void:
	clock.sleep(h)
	clock_jumped = true

## World (through `world_saver`, when set), host state (clock) and players.
func save(dir: String) -> Error:
	if world_saver.is_valid():
		var err: Error = world_saver.call(world, dir)
		if err != OK:
			return err
	var e2 := save_state(dir)
	if e2 != OK:
		return e2
	return save_players(dir)

## dir/host.json: {format, clock}. Written atomically.
func save_state(dir: String) -> Error:
	var err := DirAccess.make_dir_recursive_absolute(dir)
	if err != OK:
		return err
	var d := {"format": 1, "clock": clock.to_dict()}
	var sysw := _pending_world.duplicate(true)     # systems not added this run keep their state
	for sys: HostSystem in systems.values():
		sysw[str(sys.sys_id())] = sys.save_world()
	if not sysw.is_empty():
		d["systems"] = sysw
	if sim != null:
		# Exact save and resume needs var_to_bytes (JSON loses float bits): docs/tracks/sim.md.
		var blob := var_to_bytes({"origin": sim_origin, "sent": chronicle_sent, "sim": sim.to_dict()})
		var sf := FileAccess.open(dir.path_join("sim.bin.tmp"), FileAccess.WRITE)
		if sf == null:
			return FileAccess.get_open_error()
		sf.store_buffer(blob.compress(FileAccess.COMPRESSION_ZSTD))
		sf.close()
		var e3 := DirAccess.rename_absolute(dir.path_join("sim.bin.tmp"), dir.path_join("sim.bin"))
		if e3 != OK:
			return e3
		d["sim_raw"] = blob.size()
	var tmp := dir.path_join("host.json.tmp")
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(d, "\t"))
	f.close()
	return DirAccess.rename_absolute(tmp, dir.path_join("host.json"))

## Read dir/host.json if present. True if it was read.
func load_state(dir: String) -> bool:
	var path := dir.path_join("host.json")
	if not FileAccess.file_exists(path):
		return false
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		return false
	clock.from_dict(d.get("clock", {}))
	var sysw: Variant = d.get("systems", {})
	if sysw is Dictionary:
		for k: String in sysw:
			var sys: HostSystem = systems.get(int(k))
			if sys != null:
				sys.load_world(sysw[k])
			else:
				_pending_world[k] = sysw[k]
	var sp := dir.path_join("sim.bin")
	if d.has("sim_raw") and FileAccess.file_exists(sp):
		var raw := FileAccess.get_file_as_bytes(sp).decompress(int(d["sim_raw"]), FileAccess.COMPRESSION_ZSTD)
		var s: Variant = bytes_to_var(raw) if raw.size() == int(d["sim_raw"]) else null
		if s is Dictionary and (s as Dictionary).get("sim") is Dictionary:
			sim = WorldSim.from_dict(s["sim"])
			sim_origin = int(s.get("origin", 0))
			chronicle_sent = mini(int(s.get("sent", 0)), sim.chronicle.size())
	return true

## One JSON file per player under dir/players/, keyed by name.
func save_players(dir: String) -> Error:
	for e: HostEntity in entities.values():
		if e.is_player():
			_store_record(e)
	var pdir := dir.path_join("players")
	var err := DirAccess.make_dir_recursive_absolute(pdir)
	if err != OK:
		return err
	for player_name: String in records:
		var f := FileAccess.open(pdir.path_join(file_key(player_name) + ".json"), FileAccess.WRITE)
		if f == null:
			return FileAccess.get_open_error()
		f.store_string(JSON.stringify(records[player_name], "\t"))
		f.close()
	return OK

## Read dir/players/*.json into records. Returns how many were read.
func load_players(dir: String) -> int:
	var pdir := dir.path_join("players")
	if not DirAccess.dir_exists_absolute(pdir):
		return 0
	var n := 0
	for f in DirAccess.get_files_at(pdir):
		if not f.ends_with(".json"):
			continue
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(pdir.path_join(f)))
		if d is Dictionary and d.has("name") and d.get("pos") is Array and (d["pos"] as Array).size() == 2:
			records[String(d["name"])] = d
			n += 1
	return n

## File-safe form of a player name.
static func file_key(player_name: String) -> String:
	var out := ""
	for ch in player_name:
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == "_" or ch == "-" else "_"
	return out if out != "" else "_"

func _store_record(e: HostEntity) -> void:
	var rec: Dictionary = records.get(e.name, {})
	rec["name"] = e.name
	rec["pos"] = [e.body.pos.x, e.body.pos.y]
	if e.character != null:
		e.character.capture(e.combatant)
		rec["character"] = e.character.to_dict()
	var sysrec: Dictionary = rec.get("systems", {})     # systems not added this run keep theirs
	for sys: HostSystem in systems.values():
		sysrec[str(sys.sys_id())] = sys.save_player(e)
	if not sysrec.is_empty():
		rec["systems"] = sysrec
	records[e.name] = rec

func _alloc_id() -> int:
	var id := _next_id
	_next_id += 1
	return id
