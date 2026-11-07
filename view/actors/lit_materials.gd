## Swaps the PBR materials of a loaded model (Synty, monster-forge) for lit ones that read this
## game's tile light (view/shaders/lit.gdshaderinc): the sun and lamps shade and shadow a model
## only where the light field reaches, so it is black in an unlit cave and warm by a torch, like
## the terrain. Albedo texture and colour, vertex colour, alpha scissor (foliage), double sided
## surfaces, normal maps and roughness carry over (a stylised highlight follows the roughness);
## metal and emission are dropped. Skinning is unaffected: Godot skins before vertex().
##
##   LitMaterials.apply(model_root, Color.WHITE)   # every MeshInstance3D under it
##
## Converted materials are cached per source material, so instances of one file share them.
## The tint is an instance uniform, so it costs nothing per actor. Models cast shadows.
class_name LitMaterials
extends RefCounted

const CODE := """
shader_type spatial;
render_mode %s, depth_draw_opaque;
#define GS_SHINE
#include "res://view/shaders/lit.gdshaderinc"
%s
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo : source_color = vec4(1.0);
uniform bool has_tex = false;
uniform bool use_vcol = false;
uniform float alpha_cut = 0.5;
uniform vec4 uv_scale_offset = vec4(1.0, 1.0, 0.0, 0.0);
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool has_normal = false;
uniform float normal_scale = 1.0;
uniform float roughness = 0.85;
uniform sampler2D roughness_tex : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform bool has_rough = false;
uniform vec4 rough_channel = vec4(1.0, 0.0, 0.0, 0.0);
instance uniform vec4 tint : source_color = vec4(1.0);

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = UV * uv_scale_offset.xy + uv_scale_offset.zw;
	vec4 c = albedo;
	if (has_tex) {
		c *= texture(albedo_tex, uv);
	}
	if (use_vcol) {
		c *= COLOR;
	}
	vec3 a = c.rgb * tint.rgb;
	ALBEDO = a;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, uv).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
	float r = roughness;
	if (has_rough) {
		r *= dot(texture(roughness_tex, uv), rough_channel);
	}
	ROUGHNESS = clamp(r, 0.05, 1.0);
	vec2 tile = wpos.xy / gs_tile_m;
	vec3 L = gs_light_at(tile);
	GS_MASKS(tile);
	vec3 n = FRONT_FACING ? wnrm : -wnrm;
	EMISSION = gs_fill(a, L * gs_face_shade(n)) + gs_dark_sight(a, L, tile);
#ifdef GS_SCISSOR
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
#endif
}
"""

static var _shaders := {}     ## "cull|scissor" -> Shader
static var _converted := {}   ## source Material instance id -> ShaderMaterial

static func shader(double_sided: bool, scissor: bool) -> Shader:
	var key := "%s|%s" % [double_sided, scissor]
	if not _shaders.has(key):
		var sh := Shader.new()
		sh.code = CODE % ["cull_disabled" if double_sided else "cull_back", "#define GS_SCISSOR" if scissor else ""]
		_shaders[key] = sh
	return _shaders[key]

## A lit ShaderMaterial for a source material (BaseMaterial3D from a glTF, or anything else:
## then a plain grey). Cached.
static func lit_for(src: Material) -> ShaderMaterial:
	if src != null and _converted.has(src.get_instance_id()):
		return _converted[src.get_instance_id()]
	var double_sided := false
	var scissor := false
	var mat := ShaderMaterial.new()
	var base := src as BaseMaterial3D
	if base != null:
		double_sided = base.cull_mode == BaseMaterial3D.CULL_DISABLED
		scissor = base.transparency in [BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR,
			BaseMaterial3D.TRANSPARENCY_ALPHA, BaseMaterial3D.TRANSPARENCY_ALPHA_HASH,
			BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS]
		mat.shader = shader(double_sided, scissor)
		mat.set_shader_parameter("albedo", base.albedo_color)
		var tex := _mipmapped(base.albedo_texture)
		mat.set_shader_parameter("has_tex", tex != null)
		if tex != null:
			mat.set_shader_parameter("albedo_tex", tex)
		mat.set_shader_parameter("use_vcol", base.vertex_color_use_as_albedo)
		mat.set_shader_parameter("alpha_cut", base.alpha_scissor_threshold if base.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR else 0.5)
		mat.set_shader_parameter("uv_scale_offset", Vector4(base.uv1_scale.x, base.uv1_scale.y, base.uv1_offset.x, base.uv1_offset.y))
		var nt := _mipmapped(base.normal_texture) if base.normal_enabled else null
		mat.set_shader_parameter("has_normal", nt != null)
		if nt != null:
			mat.set_shader_parameter("normal_tex", nt)
			mat.set_shader_parameter("normal_scale", base.normal_scale)
		mat.set_shader_parameter("roughness", base.roughness)
		var rt := _mipmapped(base.roughness_texture)
		mat.set_shader_parameter("has_rough", rt != null)
		if rt != null:
			mat.set_shader_parameter("roughness_tex", rt)
			var ch := [Vector4(1, 0, 0, 0), Vector4(0, 1, 0, 0), Vector4(0, 0, 1, 0), Vector4(0, 0, 0, 1), Vector4(0.333, 0.333, 0.333, 0)]
			mat.set_shader_parameter("rough_channel", ch[clampi(base.roughness_texture_channel, 0, 4)])
	else:
		mat.shader = shader(false, false)
		mat.set_shader_parameter("albedo", Color(0.7, 0.7, 0.7))
	if src != null:
		_converted[src.get_instance_id()] = mat
	return mat

## Lit materials on every surface of every MeshInstance3D under root, and the tint.
static func apply(root: Node, tint := Color.WHITE) -> void:
	var list: Array = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		list.append(root)
	for mi: MeshInstance3D in list:
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.get_surface_override_material(s)
			if src == null:
				src = mi.mesh.surface_get_material(s)
			mi.set_surface_override_material(s, lit_for(src))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		set_tint(mi, tint)

static func set_tint(root: Node, tint: Color) -> void:
	var list: Array = root.find_children("*", "GeometryInstance3D", true, false)
	if root is GeometryInstance3D:
		list.append(root)
	for gi: GeometryInstance3D in list:
		gi.set_instance_shader_parameter("tint", tint)

## A copy of mesh with lit materials baked into its surfaces (for MultiMesh, which has no
## per-surface override).
static func lit_mesh(mesh: Mesh) -> Mesh:
	var m: Mesh = mesh.duplicate()
	for s in m.get_surface_count():
		m.surface_set_material(s, lit_for(mesh.surface_get_material(s)))
	return m

## Runtime glTF textures come without mipmaps (the importer would add them); without them the
## atlas shimmers. Cached per texture.
static var _mips := {}
static func _mipmapped(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	var id := tex.get_instance_id()
	if _mips.has(id):
		return _mips[id]
	var out := tex
	var img := tex.get_image()
	if img != null and not img.has_mipmaps():
		if img.is_compressed():
			img.decompress()
		img.generate_mipmaps()
		out = ImageTexture.create_from_image(img)
	_mips[id] = out
	return out
