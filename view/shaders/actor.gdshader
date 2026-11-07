// Placeholder actors: a tint, lit by the sun and lamps through the tile light field.
shader_type spatial;

#include "res://view/shaders/lit.gdshaderinc"

instance uniform vec4 tint : source_color = vec4(0.8, 0.8, 0.8, 1.0);

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 tile = wpos.xy / gs_tile_m;
	vec3 L = gs_light_at(tile);
	ALBEDO = tint.rgb;
	ROUGHNESS = 0.8;
	GS_MASKS(tile);
	EMISSION = gs_fill(tint.rgb, L * gs_face_shade(wnrm)) + gs_dark_sight(tint.rgb, L, tile);
}
