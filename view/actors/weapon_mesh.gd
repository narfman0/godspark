## A weapon as a node ready for a hand: its mesh from data/looks.json "weapons" scaled to
## length_m (metres, its long side), the origin at the grip; a plain bar when the row or the
## file is missing, so a fresh checkout still shows what is being swung.
class_name WeaponMesh
extends RefCounted

## row: Looks.weapon(slug). k: the body's size against a 1.8 m one.
static func build(row: Dictionary, k := 1.0) -> Node3D:
	var path := String(row.get("path", ""))
	var inst: Node3D = GltfCache.instance(path) if path != "" else null
	if inst == null:
		return _bar(row, k)
	LitMaterials.apply(inst)
	var box := GltfCache.visible_aabb(inst)
	var long := maxf(box.size.x, maxf(box.size.y, box.size.z))
	var scale := float(row.get("length_m", 0.9)) * k / maxf(long, 0.0001)
	var broad := scale * float(Looks.table().get("weapons", {}).get("thick", 1.0))
	inst.scale *= Vector3(broad if box.size.x < long else scale, broad if box.size.y < long else scale, broad if box.size.z < long else scale)
	return inst

static func _bar(row: Dictionary, k: float) -> Node3D:
	var p: Dictionary = Looks.table().get("weapons", {}).get("primitive", {})
	var len_m := float(row.get("length_m", p.get("length_m", 0.9))) * k
	var w := float(p.get("width_m", 0.07)) * k
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(w, len_m, w)
	mi.mesh = box
	mi.position.y = len_m * 0.45
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.from_string(String(p.get("color", "#8d8f96")), Color.GRAY)
	mi.material_override = LitMaterials.lit_for(mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var root := Node3D.new()
	root.add_child(mi)
	return root
