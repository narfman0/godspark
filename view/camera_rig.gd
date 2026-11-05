## Side-on perspective camera: narrow FOV so the world reads almost flat while block sides
## and bevels still show depth. Follows `target` (tile units) with exponential smoothing.
##
##   var rig := CameraRig.new()
##   add_child(rig)
##   rig.target = player_pos; rig.zoom = 1.5
##   view.view_half = rig.visible_half_extent()
class_name CameraRig
extends Node3D

const T := K.TILE_M

## Vertical field of view, degrees.
@export var fov := 28.0
## Tiles visible top to bottom at zoom 1.
@export var tiles_tall := 36.0
## Higher follows faster.
@export var smoothing := 8.0
var target := Vector2.ZERO
var zoom := 1.0:
	set(value):
		zoom = clampf(value, 0.3, 4.0)
## Where the camera currently looks, tile units (lags target).
var pos := Vector2.ZERO
var camera: Camera3D

func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = fov
	camera.near = 0.5
	camera.far = 3000.0
	add_child(camera)
	camera.make_current()
	_place()

## Jump to the target with no smoothing.
func snap() -> void:
	pos = target
	_place()

func distance() -> float:
	var h := tiles_tall / zoom * T
	return h * 0.5 / tan(deg_to_rad(fov) * 0.5) + ChunkMesher.FRONT * T

## Half the visible area on the blocks' front plane, in tiles.
func visible_half_extent() -> Vector2:
	var vp := get_viewport()
	var aspect := 16.0 / 9.0
	if vp != null:
		var s := vp.get_visible_rect().size
		if s.y > 0:
			aspect = s.x / s.y
	var half_h := tiles_tall / zoom * 0.5
	return Vector2(half_h * aspect, half_h)

func _process(delta: float) -> void:
	pos = pos.lerp(target, 1.0 - exp(-smoothing * delta))
	_place()

func _place() -> void:
	if camera != null:
		camera.position = Vector3(pos.x * T, pos.y * T, distance())
