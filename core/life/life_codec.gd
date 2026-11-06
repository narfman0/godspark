## SYS layouts of Life (HostSystem.LIFE), host -> client only. Low-rate messages, so each
## payload is one UTF-8 JSON object (numbers come back as floats; LifeClient converts).
##   FACTIONS (1): {factions: [{id, name, culture, alive, standing}]}   on join and when the
##                 sim's factions change
##   STANDING (2): {faction, value, why, n}                             one player's change
##   PEOPLE (3):   {people: [{id, role, kind, of, faction, talk, name}]} actors Life spawned
##                 (kind settlement | party, of = site or party id)
##   GONE (4):     {ids: [id]}                                          actors removed or dead
class_name LifeCodec
extends RefCounted

enum Msg { FACTIONS = 1, STANDING = 2, PEOPLE = 3, GONE = 4 }

static func write(d: Dictionary) -> PackedByteArray:
	return JSON.stringify(d).to_utf8_buffer()

static func read(data: PackedByteArray) -> Dictionary:
	var v: Variant = JSON.parse_string(data.get_string_from_utf8())
	return v if v is Dictionary else {}
