## In-world feedback (view/fx/): floating numbers, nameplates, wind-up telegraphs and spell
## aiming, drops on the ground, projectiles, hit flashes, the sigil flash. Reads the client
## world and its systems; owns nothing.
class_name FxView
extends Node3D

var cw: ClientWorld
var view: WorldView

func setup(client: ClientWorld, v: WorldView) -> void:
	cw = client
	view = v

func actor_added(_id: int, _look: Dictionary) -> void:
	pass

func actor_removed(_id: int) -> void:
	pass

func combat_event(_ev: Dictionary) -> void:
	pass

func aim_preview(_spell: Dictionary, _aim: Vector2) -> void:
	pass
