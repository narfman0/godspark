// A backdrop: a ribbon of the world's distance or an instanced silhouette in front of it. Flat
// colour under the sky's light, faded to the biome's haze with distance and toward its foot.
// Height: a layer follows the ground under the camera (gs_anchor) and, by share k, the ground
// under itself, so a range lifts as you near it and the layers stay in view on the heights.
shader_type spatial;
render_mode unshaded, cull_disabled, world_vertex_coords, depth_draw_opaque;

#include "res://view/shaders/light.gdshaderinc"

global uniform float gs_anchor;
global uniform vec4 gs_haze;

uniform float k = 0.5;
uniform float layer_haze = 0.3;
// Props: INSTANCE_CUSTOM = (ground, r, g, b). Ribbons: UV2 = (ground, haze), COLOR the colour.
uniform bool instanced = false;
uniform sampler2D mask : filter_linear_mipmap, repeat_enable;
uniform bool has_mask = false;

varying vec4 col;
varying vec2 muv;

void vertex() {
	float ground = instanced ? INSTANCE_CUSTOM.x : UV2.x;
	VERTEX.y += (gs_anchor * (1.0 - k) + ground * k) * gs_tile_m;
	col = instanced ? vec4(INSTANCE_CUSTOM.yzw, 0.0) : vec4(COLOR.rgb, UV2.y);
	muv = UV;
}

void fragment() {
	if (has_mask && texture(mask, muv).a < 0.5) {
		discard;
	}
	vec3 lit = col.rgb * gs_sky_tint.rgb * gs_curve(gs_sun);
	ALBEDO = mix(lit, gs_haze.rgb, clamp(layer_haze + (1.0 - layer_haze) * col.a, 0.0, 1.0));
}
