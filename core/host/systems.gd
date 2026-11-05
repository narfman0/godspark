## Where the game finds its feature systems. Each M2 track puts its systems at the paths
## below (a script whose new() takes no arguments); whatever exists is installed, so tracks
## never edit this file or the boot code to plug in. Tests add systems by hand instead.
##
##   Systems.install_host(host)     # NetSession.start_host, before the host thread starts
##   Systems.install_client(cw)     # on ClientEndpoint.welcomed, before any SYS arrives
class_name Systems
extends RefCounted

## sys id -> script path of the HostSystem.
const HOST := {
	HostSystem.RULES: "res://core/rules/rules_system.gd",
	HostSystem.COMBAT: "res://core/combat/combat_system.gd",
	HostSystem.ITEMS: "res://core/items/items_system.gd",
	HostSystem.MONSTERS: "res://core/monsters/monsters_system.gd",
	HostSystem.LIFE: "res://core/life/life_system.gd",
	HostSystem.DEALS: "res://core/deals/deals_system.gd",
}
## sys id -> script path of the ClientSystem.
const CLIENT := {
	HostSystem.RULES: "res://core/rules/rules_client.gd",
	HostSystem.COMBAT: "res://core/combat/combat_client.gd",
	HostSystem.ITEMS: "res://core/items/items_client.gd",
	HostSystem.MONSTERS: "res://core/monsters/monsters_client.gd",
	HostSystem.LIFE: "res://core/life/life_client.gd",
	HostSystem.DEALS: "res://core/deals/deals_client.gd",
}

## Add every host system that exists, in id order. Returns the ids added.
static func install_host(host: WorldHost) -> Array:
	var out := []
	for id: int in HOST:
		var sys: Variant = _make(HOST[id])
		if sys is HostSystem and host.system(id) == null:
			host.add_system(sys)
			out.append(id)
	return out

static func install_client(cw: ClientWorld) -> Array:
	var out := []
	for id: int in CLIENT:
		var sys: Variant = _make(CLIENT[id])
		if sys is ClientSystem and cw.system(id) == null:
			cw.add_system(sys)
			out.append(id)
	return out

static func _make(path: String) -> Variant:
	if not ResourceLoader.exists(path):
		return null
	var script: Variant = load(path)
	return script.new() if script is GDScript and (script as GDScript).can_instantiate() else null
