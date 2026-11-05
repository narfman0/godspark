## Boot. Command line (after `--`):
##   (nothing) | host [port=N] [world=DIR] [name=X]   host and play locally (listen server)
##   dedicated [port=N] [world=DIR] [expect=N]          no local player; with expect=N, exit 0
##                                                      after N clients said a final BYE
##   join=ADDR[:PORT] [name=X]                          join a host
##   join=ADDR[:PORT] bot [name=X] [digs=N] [places=M] [dir=1|-1] [delay=S] [rejoin=0|1]
##   any mode: timeout=S (exit 1 after S seconds), size=WxH (test world size),
##             offline (host with no ENet port: single-player), view=log (no 3D view)
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

func _ready() -> void:
	opts = parse_args(OS.get_cmdline_user_args())
	var headless := DisplayServer.get_name() == "headless"
	if headless:
		Engine.max_fps = 120
	_timeout = float(opts.get("timeout", 0))
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

## Where the world comes from. Track A's WorldSave/WorldGen replace the test world here.
func world_source() -> TileWorld:
	var size := String(opts.get("size", "1024x256")).split("x")
	var w := int(size[0]) if size.size() == 2 else 1024
	var h := int(size[1]) if size.size() == 2 else 256
	return TileWorld.make_test(w, h)

func _start_host(headless: bool, dedicated: bool) -> void:
	world_dir = String(opts.get("world", "user://worlds/dev"))
	var port := 0 if opts.has("offline") else int(opts.get("port", NetSession.DEFAULT_PORT))
	var local_name := "" if dedicated else String(opts.get("name", "host"))
	session = NetSession.new()
	add_child(session)
	var err := session.start_host(world_source(), port, local_name)
	if err != OK:
		printerr("could not host on port %d: %s" % [port, error_string(err)])
		_quit(1)
		return
	var n := session.host.load_players(ProjectSettings.globalize_path(world_dir))
	print("hosting on port %d (%s), %d saved players in %s" % [port, "dedicated" if dedicated else "listen", n, world_dir])
	session.host_ep.player_left.connect(_on_player_left)
	if not dedicated:
		_make_client_side(headless)

func _start_join(headless: bool) -> void:
	var a := split_address(String(opts["join"]))
	session = NetSession.new()
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
	if presenter != null:
		presenter.frame(delta)
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
	if session != null and session.host != null:
		_report()
		if world_dir != "":
			var err := session.host.save(ProjectSettings.globalize_path(world_dir))
			print("saved players to %s: %s" % [world_dir, error_string(err)])
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
	print("HOSTSTATS traffic by message type:\n" + ep.traffic_report())

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _exit_code < 0:
		_quit(0)
		_shutdown_and_exit()
