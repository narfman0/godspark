## The client half of a feature area: receives its system's SYS messages from the host and
## sends its own with cw.send_sys. Runs on the client's (main) thread. Never rolls dice.
##
##   cw.add_system(MyClient.new())     # right on ClientEndpoint.welcomed, before any SYS
class_name ClientSystem
extends RefCounted

## The same id as its HostSystem.
func sys_id() -> int:
	return 0

func attach(_cw: ClientWorld) -> void:
	pass

## A SYS message for this system from the host.
func handle(_kind: int, _data: PackedByteArray) -> void:
	pass

## Once per client frame (after the world advanced).
func frame(_dt: float) -> void:
	pass

## Edit flow (items): may the own player place `tile_id` now? False: the client neither
## predicts nor sends the place.
func allow_place(_tile_id: int) -> bool:
	return true

## Edit flow (items): the client predicted a place (request `req`) and sent it.
func placed(_req: int, _tile_id: int) -> void:
	pass
