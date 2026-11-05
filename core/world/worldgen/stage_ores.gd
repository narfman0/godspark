## Stage "ores": random-walk veins from data/worldgen/ores.json, each in its depth range,
## overwriting only the listed host rock (never air, roads or bedrock).
extends RefCounted

const GenContext := preload("gen_context.gd")
const PATH := "res://data/worldgen/ores.json"

static func run(c: GenContext, rng: RandomNumberGenerator) -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	for ore: Dictionary in data["ores"]:
		var id := TileDefs.id(ore["tile"])
		var host := PackedByteArray()
		host.resize(256)
		for name: String in ore["replace"]:
			host[TileDefs.id(name)] = 1
		var depth: Array = ore["depth"]
		var y_top := int(c.h * (1.0 - float(depth[0])))
		var y_bot := maxi(1, int(c.h * (1.0 - float(depth[1]))))
		var area := float(c.w * (y_top - y_bot))
		var veins := int(area / 10000.0 * float(ore["veins"]))
		var size: Array = ore["size"]
		for v in veins:
			var x := rng.randi_range(0, c.w - 1)
			var y := rng.randi_range(y_bot, y_top)
			if y > c.ground[x] - 6:
				continue
			var n := rng.randi_range(int(size[0]), int(size[1]))
			for k in n:
				for d: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1)]:
					var px := x + d.x
					var py := y + d.y
					if px >= 0 and px < c.w and py >= 1 and py < c.h:
						var i := px + py * c.w
						if host[c.fg[i]] != 0:
							c.fg[i] = id
				match rng.randi_range(0, 3):
					0: x += 1
					1: x -= 1
					2: y += 1
					_: y -= 1
