// Foreground props in front of the play plane: dark shapes under the sky's light. Near what must
// stay seen (the player, the target) they thin out in a dither, so they never hide it. keep is
// measured on the play plane, along the eye's line through the fragment.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

#include "res://view/shaders/light.gdshaderinc"

// The sun factor for scenery: by night no less than data/lighting.json night_far.
global uniform float gs_far_sun;

global uniform vec4 gs_keep_a;
global uniform vec4 gs_keep_b;

uniform float fade = 1.0;
uniform sampler2D mask : filter_linear_mipmap, repeat_enable;
uniform bool has_mask = false;

varying vec3 wpos;
varying vec3 col;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	col = INSTANCE_CUSTOM.rgb;
}

float kept(vec2 p, vec4 keep) {
	if (keep.z <= 0.0) {
		return 1.0;
	}
	return smoothstep(0.62, 1.0, distance(p, keep.xy) / keep.z);
}

void fragment() {
	if (has_mask && texture(mask, UV).a < 0.5) {
		discard;
	}
	vec3 eye = CAMERA_POSITION_WORLD;
	vec2 on_plane = eye.xy + (wpos.xy - eye.xy) * eye.z / max(eye.z - wpos.z, 0.001);
	float a = min(kept(on_plane / gs_tile_m, gs_keep_a), kept(on_plane / gs_tile_m, gs_keep_b)) * fade;
	if (gs_hash(floor(FRAGCOORD.xy * 0.5)) >= a) {
		discard;
	}
	ALBEDO = col * gs_sky_tint.rgb * gs_curve(gs_far_sun);
}
