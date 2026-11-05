## Loot on the ground: each drop the items client knows (drop_added / drop_removed, stepped
## locally by ItemsClient) is a small tilted card with the item's icon, bobbing gently, lit
## by the tile light like the terrain; sparks and magic items carry a glint in their rarity
## colour. One material per icon texture (shared); at most CAP cards.
class_name DropsView
extends Node3D

const SHADER := preload("res://view/fx/drop.gdshader")
const CAP := 200
const CARD := 1.0    ## tiles

var items: ItemsClient
var cards := {}      ## drop id -> MeshInstance3D
var _mats := {}      ## Texture2D -> ShaderMaterial
var _quad: QuadMesh
var _t := 0.0

func _ready() -> void:
	_quad = QuadMesh.new()
	_quad.size = Vector2.ONE * CARD * K.TILE_M

func setup(it: ItemsClient) -> void:
	items = it
	if items == null:
		return
	items.drop_added.connect(_added)
	items.drop_removed.connect(_removed)
	for d: Dictionary in items.drops_in_view():
		_added(int(d["id"]), d["pos"], d["item"])

func _mat(tex: Texture2D) -> ShaderMaterial:
	var m: ShaderMaterial = _mats.get(tex)
	if m == null:
		m = ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("icon", tex)
		_mats[tex] = m
	return m

func _added(id: int, _pos: Vector2, item: Dictionary) -> void:
	var mi: MeshInstance3D = cards.get(id)
	if mi == null:
		if cards.size() >= CAP:
			return
		mi = MeshInstance3D.new()
		mi.mesh = _quad
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		cards[id] = mi
	mi.material_override = _mat(ItemIcons.texture(item))
	var g := ItemIcons.rarity_color(item) if ItemIcons.glints(item) else Color(0, 0, 0, 0)
	mi.set_instance_shader_parameter("glint", g)
	mi.set_instance_shader_parameter("phase", float(id % 17) / 17.0)

func _removed(id: int, _by: int) -> void:
	var mi: MeshInstance3D = cards.get(id)
	if mi != null:
		mi.queue_free()
		cards.erase(id)

func step(dt: float) -> void:
	if items == null:
		return
	_t += dt
	for id: int in cards:
		var d: Drops.Drop = items.drops.list.get(id)
		if d == null:
			continue
		var mi: MeshInstance3D = cards[id]
		var bob := 0.1 * sin(_t * 2.4 + id * 0.7)
		mi.position = Vector3(d.pos.x * K.TILE_M, (d.pos.y + CARD * 0.5 + 0.08 + bob) * K.TILE_M, 0.15)
		mi.rotation = Vector3(0.0, 0.35 * sin(_t * 0.9 + id), 0.12 * sin(_t * 1.3 + id * 1.7))

func count() -> int:
	return cards.size()
