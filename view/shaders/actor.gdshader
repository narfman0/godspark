// Placeholder actors: a tint, simple face shading, lit by the per-tile light textures.
shader_type spatial;
render_mode unshaded;

#include "res://view/shaders/light.gdshaderinc"

instance uniform vec4 tint : source_color = vec4(0.8, 0.8, 0.8, 1.0);

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 L = gs_light_at(wpos.xy / gs_tile_m);
	ALBEDO = tint.rgb * (L * gs_face_shade(wnrm) + vec3(0.004));
}
