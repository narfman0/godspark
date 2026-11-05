## A scripted tour of the interface for verification without a human (main.gd option
## ui_tour=DIR, on an offline host with cheats). It drives the game and the UI through their
## states and saves a screenshot of each to DIR, then quits. Setting the scene (items, a
## shrine, monsters) goes to the host through session.host_call, as a test harness would;
## everything the player does goes through the client systems like a real click.
##
##   tools/soft_godot.sh -- offline cheats gen=dev seed=3 world=/tmp/x ui_tour=/tmp/shots
class_name UiTour
extends Node

var dir := ""
var main: Node
var session: NetSession
var pres: ViewPresenter
var ui: GameUi
var cw: ClientWorld
var shots: Array[String] = []
var only := ""
var fight_usec := PackedInt32Array()

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	_run.call_deferred()

func wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := dir.path_join(name + ".png")
	img.save_png(path)
	shots.append(path)
	print("TOUR shot ", path)

func host(f: Callable) -> void:
	session.host_call(f)
	await wait(0.15)

func me_host(h: WorldHost) -> HostEntity:
	for e: HostEntity in h.entities.values():
		if e.kind == HostEntity.Kind.PLAYER:
			return e
	return null

func _run() -> void:
	while pres == null or pres.ui == null or pres.cw == null or not pres.cw.area_ready():
		pres = main.get("presenter") as ViewPresenter
		await wait(0.2)
	ui = pres.ui
	cw = pres.cw
	await wait(4.0)
	await steps()
	print("TOUR done: %d shots" % shots.size())
	main.call("_quit", 0)

## The tour itself; each step leaves the screen in a state and takes a picture.
func steps() -> void:
	await shot("01_hud")
