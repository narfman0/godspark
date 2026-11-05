## The one node that owns networking. Host role: a WorldHost plus HostEndpoint over ENet
## (and, for a listen server, a loopback link to the host's own player). Client role: a
## ClientEndpoint over ENet. Ticks the client every frame and the host at K.TICK_HZ on its
## own thread (a fixed clock: a slow frame rate never slows the world or delays a join).
## Anything else that touches the host while it runs goes through `host_call` (run on the
## host thread before the next tick) or `with_host` (main thread, holding the host lock).
## Single-player is start_host(world, 0, "name"): a host with no ENet port and one local
## client, through the same code.
##
##   var s := NetSession.new(); add_child(s)
##   s.input_source = func() -> PlayerInput: return my_input
##   s.start_host(world, 24650, "ann")     # listen server; "" for dedicated
##   s.start_client("127.0.0.1", 24650, "bob")
class_name NetSession
extends Node

signal client_ready(cw: ClientWorld)
signal client_closed(reason: int, text: String)

const DEFAULT_PORT := 24650
## The listen server's own player on the loopback link (ENet never assigns it in practice:
## its ids are random in 2..2^31-1).
const LOCAL_PEER := 0x7fffffff
## At most this many host ticks to catch up at once; a longer stall is dropped.
const MAX_TICKS_PER_FRAME := 4

var host: WorldHost
var host_ep: HostEndpoint
var client_ep: ClientEndpoint
var enet: EnetTransport
var hub: LoopbackHub
## func() -> PlayerInput for the own player; idle input if unset.
var input_source := Callable()
var log_fn := Callable()
## Tick the host on a thread (true) or in _process (false: the old render-bound way).
var threaded := true
var _host_acc := 0.0
var _idle := PlayerInput.new()
var _thread: Thread
var _thread_stop := false
var _host_lock := Mutex.new()
var _calls: Array[Callable] = []

func start_host(world: TileWorld, port: int, local_name := "", max_players := 4) -> Error:
	host = WorldHost.new(world)
	var multi := MultiTransport.new()
	if port > 0:
		enet = EnetTransport.new()
		var err := enet.listen(port, max_players)
		if err != OK:
			enet = null
			return err
		multi.add(enet)
	if local_name != "":
		hub = LoopbackHub.new()
		multi.add(hub.transport(NetTransport.SERVER))
		_make_client(hub.transport(LOCAL_PEER), local_name)
		hub.join(LOCAL_PEER)
	host_ep = HostEndpoint.new(host, multi)
	host_ep.max_players = max_players
	host_ep.log_fn = _log
	return OK

func start_client(address: String, port: int, player_name: String) -> Error:
	enet = EnetTransport.new()
	var err := enet.connect_to(address, port)
	if err != OK:
		enet = null
		return err
	_make_client(enet, player_name)
	return OK

func _make_client(t: NetTransport, player_name: String) -> void:
	client_ep = ClientEndpoint.new(t, player_name)
	client_ep.welcomed.connect(func(cw: ClientWorld) -> void: client_ready.emit(cw))
	client_ep.disconnected.connect(func(r: int, s: String) -> void: client_closed.emit(r, s))

## Run f(host: WorldHost) on the host thread just before its next tick (or at once when the
## host is not threaded). Safe from any thread.
func host_call(f: Callable) -> void:
	_host_lock.lock()
	_calls.append(f)
	_host_lock.unlock()

## Run f() on this thread while holding the host lock: no tick runs meanwhile.
func with_host(f: Callable) -> Variant:
	_host_lock.lock()
	var out: Variant = f.call()
	_host_lock.unlock()
	return out

## Stop ticking the host (joins the thread). The host can then be read and saved freely.
func halt_host() -> void:
	if _thread != null:
		_thread_stop = true
		_thread.wait_to_finish()
		_thread = null

func _host_tick() -> void:
	_host_lock.lock()
	var calls := _calls
	_calls = []
	for f in calls:
		f.call(host)
	host_ep.tick()
	_host_lock.unlock()

func _host_loop() -> void:
	var step_us := 1000000 / K.TICK_HZ
	var next := Time.get_ticks_usec()
	while not _thread_stop:
		var now := Time.get_ticks_usec()
		if now < next:
			OS.delay_usec(mini(next - now, 2000))
			continue
		_host_tick()
		next += step_us
		if Time.get_ticks_usec() - next > step_us * MAX_TICKS_PER_FRAME:
			next = Time.get_ticks_usec()   # a long stall is dropped, not caught up

func client_world() -> ClientWorld:
	return client_ep.cw if client_ep != null else null

## Leave as a client (BYE, then close).
func leave(reason := Protocol.Why.LEAVING) -> void:
	if client_ep != null:
		client_ep.leave(reason)

## Close everything: kick clients if hosting, leave if a client.
func stop() -> void:
	halt_host()
	if client_ep != null and client_ep.phase != ClientEndpoint.Phase.CLOSED:
		client_ep.leave()
	if host_ep != null:
		host_ep.shutdown()
		host_ep.transport.close()
		host_ep = null
	elif enet != null:
		enet.close()
	enet = null

func _process(delta: float) -> void:
	if hub != null:
		hub.advance(delta)
	if host_ep != null and threaded:
		if _thread == null and not _thread_stop:
			_thread = Thread.new()
			_thread.start(_host_loop, Thread.PRIORITY_HIGH)
	elif host_ep != null:
		_host_acc += delta
		var n := 0
		var step := 1.0 / K.TICK_HZ
		while _host_acc >= step and n < MAX_TICKS_PER_FRAME:
			_host_tick()
			_host_acc -= step
			n += 1
		if n == MAX_TICKS_PER_FRAME:
			_host_acc = minf(_host_acc, step)
	if client_ep != null and client_ep.phase != ClientEndpoint.Phase.CLOSED:
		var inp: PlayerInput = input_source.call() if input_source.is_valid() else _idle
		client_ep.frame(delta, inp if inp != null else _idle)

func _exit_tree() -> void:
	stop()

func _log(s: String) -> void:
	if log_fn.is_valid():
		log_fn.call(s)
	else:
		print("[host] ", s)
