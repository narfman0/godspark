## The host half of one feature area (rules, combat, items, monsters). M2 tracks reach the
## host and the wire only through systems, so they never edit WorldHost or the protocol.
## Every hook runs on the host thread (inside a tick, a join or a save); none may block.
## Override what you need; the defaults do nothing.
##
##   class MySystem extends HostSystem:
##       func sys_id() -> int: return HostSystem.RULES
##       func handle(host, e, kind, data): host.send_sys(sys_id(), 1, data, e.id)
##   host.add_system(MySystem.new())
##
## Ids are wire bytes (u8): keep them stable. Each system defines its own message kinds
## (u8) and payload layouts in its own codec file. Saved dictionaries go through JSON:
## numbers come back as floats.
class_name HostSystem
extends RefCounted

const RULES := 1
const COMBAT := 2
const ITEMS := 3
const MONSTERS := 4

## Unique per system, 1..255.
func sys_id() -> int:
	return 0

## Added to `host` (before any entity_added for it).
func attach(_host: WorldHost) -> void:
	pass

## Every host tick, after movement and digs.
func tick(_host: WorldHost) -> void:
	pass

## A player or monster appeared (players: after load_player).
func entity_added(_host: WorldHost, _e: HostEntity) -> void:
	pass

## It is going (still in host.entities; players: after save_player).
func entity_removed(_host: WorldHost, _e: HostEntity) -> void:
	pass

## A SYS message for this system from the client that owns `e`.
func handle(_host: WorldHost, _e: HostEntity, _kind: int, _data: PackedByteArray) -> void:
	pass

## This system's part of a player record (JSON-safe), stored under its id.
func save_player(_e: HostEntity) -> Dictionary:
	return {}

## Called on join with what save_player returned last time ({} for a new player).
func load_player(_e: HostEntity, _d: Dictionary) -> void:
	pass

## This system's world state (JSON-safe), saved in host.json under its id.
func save_world() -> Dictionary:
	return {}

func load_world(_d: Dictionary) -> void:
	pass
