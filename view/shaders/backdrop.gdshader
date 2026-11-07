// Plane behind the terrain: dark rock where the sky field does not reach (caves without a
// background wall), clear where it does, so the sky and the backdrops behind it show through.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

#include "res://view/shaders/light.gdshaderinc"

uniform vec3 rock : source_color = vec3(0.05, 0.045, 0.05);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 tile = wpos.xy / gs_tile_m;
	vec2 l = gs_levels(tile);
	ALBEDO = rock * GS_TORCH_TINT * gs_curve(l.x) * 0.6;
	ALPHA = 1.0 - smoothstep(0.08, 0.45, l.y);
}
