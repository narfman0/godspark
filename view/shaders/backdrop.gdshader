// Far plane behind the terrain: sky where the sky field reaches (open air), dark rock where
// it does not (caves without a background wall).
shader_type spatial;
render_mode unshaded, cull_disabled;

#include "res://view/shaders/light.gdshaderinc"

uniform vec3 sky_top : source_color = vec3(0.35, 0.55, 0.85);
uniform vec3 sky_low : source_color = vec3(0.7, 0.8, 0.9);
uniform vec3 rock : source_color = vec3(0.05, 0.045, 0.05);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 tile = wpos.xy / gs_tile_m;
	vec2 l = gs_levels(tile);
	vec3 sky = mix(sky_low, sky_top, clamp(1.0 - SCREEN_UV.y, 0.0, 1.0));
	vec3 cave = rock * GS_TORCH_TINT * gs_curve(l.x) * 0.6;
	ALBEDO = mix(cave, sky, smoothstep(0.08, 0.45, l.y));
}
