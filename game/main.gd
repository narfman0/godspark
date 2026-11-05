## Boot. Command line (after `--`):
##   (nothing) | host [port=N] [world=DIR] [name=X]   host and play locally (listen server)
##   dedicated [port=N] [world=DIR] [expect=N]          no local player; with expect=N, exit 0
##                                                      after N clients said a final BYE
##   join=ADDR[:PORT] [name=X]                          join a host
##   join=ADDR[:PORT] bot [name=X] [digs=N] [places=M] [dir=1|-1] [delay=S] [rejoin=0|1] [fight=1]
##   host modes: gen=dev|small|medium|large [seed=N] for a new world, gen=test or size=WxH
##             for the fixed test world; a world saved in world=DIR is loaded instead
##   host modes: spawn=SLUG[:N] places N (default 1) of an SRD monster near the spawn point,
##             standing still (no brain), e.g. spawn=goblin-warrior:3; spawn_dx=N: the first
##             one N tiles from the spawn point (default -24)
##   host modes: spawns=0|1 turns the monsters' spawn director off or on (default: on for
##             generated worlds, off for the fixed test world)
##   client modes: class=SLUG, the SRD class of a new character (default fighter)
##   any mode: timeout=S (exit 1 after S seconds),
##             offline (host with no ENet port: single-player), view=log (no 3D view),
##             sleep=HOURS (host: advance the world clock at start),
##             frame_delay=MS (sleep every frame: a slow renderer, for testing),
##             host_thread=0 (tick the host in the render loop instead of on its thread),
##             shot=PATH.png [shot_after=S]: save a screenshot after S seconds and quit
## Headless processes (and bots) use the log presenter; windowed ones the 3D view.
extends Node

var opts := {}
var session: NetSession
var presenter: Presenter
var local_input: LocalInput
var world_dir := ""
var _finals := 0
var _exit_code := -1
var _quit_in := -1.0
var _elapsed := 0.0
var _timeout := 0.0
var _frames := 0
var _world_loaded := false
var _shut_down := false
var _frame_delay := 0
var _worst_frame := 0.0

func _ready() -> void:
	opts = parse_args(OS.get_cmdline_user_args())
	var headless := DisplayServer.get_name() == "headless"
	if headless:
		Engine.max_fps = 120
	_timeout = float(opts.get("timeout", 0))
	_frame_delay = int(opts.get("frame_delay", 0))
	if opts.has("bot"):
		_start_bot()
	elif opts.has("join"):
		_start_join(headless)
	else:
		_start_host(headless, opts.has("dedicated"))

static func parse_args(args: PackedStringArray) -> Dictionary:
	var out := {}
	for a in args:
		var s := a.trim_prefix("--")
		var eq := s.find("=")
		if eq < 0:
			out[s] = true
		else:
			out[s.substr(0, eq)] = s.substr(eq + 1)
	return out

static func split_address(s: String) -> Array:
	var port := NetSession.DEFAULT_PORT
	var host := s
	var colon := s.rfind(":")
	if colon > 0 and s.substr(colon + 1).is_valid_int():
		host = s.substr(0, colon)
		port = int(s.substr(colon + 1))
	return [host, port]

## Where the world comes from: the saved world in `world_dir`, else a generated one
## (gen=dev|small|medium|large, seed=N), else with gen=test or size=WxH the fixed test world.
func world_source() -> TileWorld:
	var gen := String(opts.get("gen", "dev"))
	if gen == "test" or opts.has("size"):
		var size := String(opts.get("size", "1024x256")).split("x")
		var w := int(size[0]) if size.size() == 2 else 1024
		var h := int(size[1]) if size.size() == 2 else 256
		return TileWorld.make_test(w, h)
	var saved := WorldSave.load(ProjectSettings.globalize_path(world_dir))
	if saved != null:
		_world_loaded = true
		print("loaded world %dx%d seed %d from %s" % [saved.width, saved.height, saved.world_seed, world_dir])
		return saved
	var world_seed := int(opts["seed"]) if opts.has("seed") else int(Time.get_unix_time_from_system())
	var t0 := Time.get_ticks_msec()
	var world := WorldGen.generate_named(gen, world_seed)
	print("generated %s world %dx%d seed %d in %d ms" % [gen, world.width, world.height, world_seed, Time.get_ticks_msec() - t0])
	return world

## Players start at the first surface settlement site when the world has one.
static func spawn_for(world: TileWorld, fallback: Vector2) -> Vector2:
	for site: Dictionary in world.meta.get("sites", []):
		if site.get("kind") == "settlement" and site.get("band") in ["surface", "sky"]:
			return Vector2(float(site["x"]) + 0.5, float(site["y"]))
	return fallback

func _start_host(headless: bool, dedicated: bool) -> void:
	world_dir = String(opts.get("world", "user://worlds/dev"))
	var port := 0 if opts.has("offline") else int(opts.get("port", NetSession.DEFAULT_PORT))
	var local_name := "" if dedicated else String(opts.get("name", "host"))
	session = NetSession.new()
	session.threaded = String(opts.get("host_thread", "1")) != "0"
	session.player_class = String(opts.get("class", ""))
	add_child(session)
	var err := session.start_host(world_source(), port, local_name)
	if err != OK:
		printerr("could not host on port %d: %s" % [port, error_string(err)])
		_quit(1)
		return
	session.host.world_saver = WorldSave.save
	session.host.spawn = spawn_for(session.host.world, session.host.spawn)
	var n := session.host.load_players(ProjectSettings.globalize_path(world_dir))
	if _world_loaded and session.host.load_state(ProjectSettings.globalize_path(world_dir)):
		print("world clock: %s" % WorldClock.describe(session.host.clock.hours()))
	if opts.has("sleep"):
		session.host.sleep(float(opts["sleep"]))
		print("slept %s h: %s" % [opts["sleep"], WorldClock.describe(session.host.clock.hours())])
	if opts.has("spawn"):
		_spawn_monsters(String(opts["spawn"]))
	# spawns=0|1: the monsters' spawn director (default: on for generated worlds, which have
	# depth bands; off on the fixed test world)
	var ms: Variant = session.host.system(HostSystem.MONSTERS)
	if ms != null and opts.has("spawns"):
		ms.set("director_enabled", 1 if String(opts["spawns"]) != "0" else 0)
	print("hosting on port %d (%s), %d saved players in %s" % [port, "dedicated" if dedicated else "listen", n, world_dir])
	# Emitted on the host thread: handle it on the main thread.
	session.host_ep.player_left.connect(_on_player_left, CONNECT_DEFERRED)
	if not dedicated:
		_make_client_side(headless)

## spawn=SLUG[:N]: N monsters a few tiles apart, left of the spawn point. Runs before the
## host thread starts (the first _process), so it may touch the host directly.
func _spawn_monsters(spec: String) -> void:
	var parts := spec.split(":")
	var slug := parts[0]
	var n := int(parts[1]) if parts.size() > 1 and parts[1].is_valid_int() else 1
	var h := session.host
	for i in n:
		var x := clampi(int(h.spawn.x) + int(opts.get("spawn_dx", -24)) - 3 * i, 2, h.world.width - 3)
		var e := h.add_srd_monster(slug, h.find_spawn(x))
		if e == null:
			printerr("spawn: no SRD monster %s" % slug)
			return
		var v := e.vitals()
		print("spawned %s (entity %d) at %.1f,%.1f hp %d/%d" % [e.name, e.id, e.body.pos.x, e.body.pos.y, v.x, v.y])

func _start_join(headless: bool) -> void:
	var a := split_address(String(opts["join"]))
	session = NetSession.new()
	session.player_class = String(opts.get("class", ""))
	add_child(session)
	var err := session.start_client(a[0], a[1], String(opts.get("name", "player%d" % (randi() % 1000))))
	if err != OK:
		printerr("could not connect to %s:%d: %s" % [a[0], a[1], error_string(err)])
		_quit(1)
		return
	session.client_closed.connect(func(r: int, s: String) -> void:
		print("disconnected: %s %s" % [Protocol.Why.find_key(r), s])
		_quit(0 if r == Protocol.Why.LEAVING or r == Protocol.Why.SHUTDOWN else 1))
	_make_client_side(headless)

func _make_client_side(headless: bool) -> void:
	if headless or opts.get("view", "") == "log":
		presenter = LogPresenter.new()
	else:
		presenter = ViewPresenter.new()
	add_child(presenter)
	local_input = LocalInput.new()
	local_input.presenter = presenter
	add_child(local_input)
	session.input_source = local_input.read
	session.client_ready.connect(func(cw: ClientWorld) -> void:
		presenter.detach()
		presenter.attach(cw))

func _start_bot() -> void:
	var a := split_address(String(opts.get("join", "127.0.0.1")))
	var bot := BotClient.new()
	bot.address = a[0]
	bot.port = a[1]
	bot.bot_name = String(opts.get("name", "bot"))
	bot.digs = int(opts.get("digs", 3))
	bot.places = int(opts.get("places", 3))
	bot.dir = 1 if int(opts.get("dir", 1)) >= 0 else -1
	bot.delay = float(opts.get("delay", 0.0))
	bot.rejoin = String(opts.get("rejoin", "1")) != "0"
	bot.bot_class = String(opts.get("class", ""))
	bot.fight = String(opts.get("fight", "0")) != "0"
	bot.finished.connect(func(ok: bool) -> void: _quit(0 if ok else 1, 0.3))
	add_child(bot)

func _on_player_left(_peer: int, player_name: String, reason: int) -> void:
	if reason != Protocol.Why.FINAL:
		return
	_finals += 1
	print("[host] %s finished (%d/%s)" % [player_name, _finals, opts.get("expect", "-")])
	if opts.has("expect") and _finals >= int(opts["expect"]):
		_quit(0, 0.3)

func _process(delta: float) -> void:
	_elapsed += delta
	_frames += 1
	if _frame_delay > 0:
		OS.delay_msec(_frame_delay)    # debug: simulate a slow renderer
	_worst_frame = maxf(_worst_frame, delta) if _frames > 10 else 0.0
	if presenter != null:
		presenter.frame(delta)
	if opts.has("shot") and _exit_code < 0 and _elapsed > float(opts.get("shot_after", 6.0)):
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png(String(opts["shot"]))
		print("screenshot %s: %s" % [opts["shot"], error_string(err)])
		_quit(0 if err == OK else 1)
	if _timeout > 0.0 and _elapsed > _timeout and _exit_code < 0:
		printerr("TIMEOUT after %.0f s" % _timeout)
		_quit(1)
	if _quit_in >= 0.0:
		_quit_in -= delta
		if _quit_in < 0.0:
			_shutdown_and_exit()

## Quit with `code` after `wait` seconds (lets the last packets go out).
func _quit(code: int, wait := 0.0) -> void:
	if _exit_code >= 0:
		return
	_exit_code = code
	_quit_in = wait

func _shutdown_and_exit() -> void:
	if _shut_down:
		return
	_shut_down = true
	print("FRAMES %d in %.1f s (%.1f fps, worst frame %.0f ms after the first 10)" % [_frames, _elapsed,
			_frames / maxf(0.001, _elapsed), _worst_frame * 1000.0])
	if session != null and session.host != null:
		session.halt_host()
		_report()
		if world_dir != "":
			var err := session.host.save(ProjectSettings.globalize_path(world_dir))
			print("saved world and players to %s: %s" % [world_dir, error_string(err)])
	if session != null:
		session.stop()
	get_tree().quit(_exit_code)

func _report() -> void:
	var ep := session.host_ep
	if ep == null:
		return
	var ticks := ep.tick_usec
	var sum := 0
	var mx := 0
	for u in ticks:
		sum += u
		mx = maxi(mx, u)
	print("HOSTSTATS ticks=%d tick_avg_us=%.1f tick_max_us=%d host_time=%.1f" % [ticks.size(), float(sum) / maxi(1, ticks.size()), mx, ep.time])
	var h := session.host
	if h.sim != null:
		var su := h.sim_usec
		var ssum := 0
		var smax := 0
		for u in su:
			ssum += u
			smax = maxi(smax, u)
		print("HOSTSTATS sim: %d ticks stepped it, avg %.0f us, max %d us; sim hour %d, %d behind, %d chronicle entries; clock %s" % [
				su.size(), float(ssum) / maxi(1, su.size()), smax, h.sim.t, h.sim_behind(), h.sim.chronicle.size(),
				WorldClock.describe(h.clock.hours())])
	var ms: Variant = h.system(HostSystem.MONSTERS)
	if ms != null:
		print("HOSTSTATS monsters: director %s, spawned %d, alive %d, packs %d, despawned %d, plans %d, lairs %s" % [
				ms.call("director_on"), ms.stats["spawned"], ms.call("alive_count"), ms.director.stats["packs"],
				ms.director.stats["despawned"], ms.stats["plans"], ms.lairs.stats])
	print("HOSTSTATS traffic by message type:\n" + ep.traffic_report())

## Debug keys on a host with a local player: F6 one game hour, F7 one game day.
func _unhandled_input(event: InputEvent) -> void:
	if session == null or session.host == null:
		return
	var h := 0.0
	if event.is_action_pressed("debug_hour"):
		h = 1.0
	elif event.is_action_pressed("debug_day"):
		h = 24.0
	if h > 0.0:
		session.host_call(func(host: WorldHost) -> void: host.sleep(h))

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _exit_code < 0:
		_quit(0)
		_shutdown_and_exit()
