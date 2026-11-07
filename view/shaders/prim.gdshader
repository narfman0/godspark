// Primitive props (view/actors/prim_mesh.gd): lit like a model through the tile light field, with
// a light of their own from vertex data, so a cap's gills or a crystal's point read in the dark and
// nothing else does. COLOR.rgb is the albedo (linear), COLOR.a the glow over two. Glow breathes,
// slowly, each prop out of step with the next.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

#include "res://view/shaders/lit.gdshaderinc"

instance uniform vec4 tint : source_color = vec4(1.0);

varying vec3 wpos;
varying vec3 wnrm;
varying float glow;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	glow = COLOR.a * 2.0;
}

void fragment() {
	vec3 a = COLOR.rgb * tint.rgb;
	ALBEDO = a;
	ROUGHNESS = 0.8;
	vec2 tile = wpos.xy / gs_tile_m;
	vec3 L = gs_light_at(tile);
	GS_MASKS(tile);
	vec3 n = FRONT_FACING ? wnrm : -wnrm;
	float breath = 0.82 + 0.18 * sin(TIME * 0.9 + wpos.x * 0.7 + wpos.y * 0.21);
	EMISSION = gs_fill(a, L * gs_face_shade(n)) + gs_dark_sight(a, L, tile) + a * glow * breath * 1.6;
}
