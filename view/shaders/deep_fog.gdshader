// Fog of the deep (view/below_look.gd): a sheet just in front of the walls, behind the actors and
// the dressing, so they stand against it. Colour and density by region from gs_below_fog; thin where
// the dark is, gathering where the light field is lit, in slow banks. Motes drift through it, each
// region its own way: x, y their drift (tiles a second), z how many, w how much they twinkle.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

#include "res://view/shaders/light.gdshaderinc"

global uniform sampler2D gs_noise : filter_linear_mipmap, repeat_enable;
global uniform sampler2D gs_below_fog : filter_linear, repeat_disable;

uniform float ambient = 0.0;
uniform vec4 motes = vec4(0.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 tile = wpos.xy / gs_tile_m;
	vec4 f = texture(gs_below_fog, gs_light_uv(tile));
	if (f.a < 0.004) {
		discard;
	}
	vec3 fog = f.rgb / f.a;
	float lit = clamp(gs_curve(gs_levels(tile).x), 0.0, 1.0);
	// Banks: long and low, drifting, a second look across them.
	float a = texture(gs_noise, tile * vec2(0.009, 0.03) + TIME * vec2(0.0035, 0.0009)).r;
	float b = texture(gs_noise, tile * vec2(0.021, 0.05) - TIME * vec2(0.0021, 0.0)).g;
	float bank = smoothstep(0.25, 0.8, a * 0.65 + b * 0.35);
	float d = f.a * (ambient + lit * 0.4) * (0.6 + 0.65 * bank);
	// Motes: a point in some cells of a drifting grid.
	float m = 0.0;
	if (motes.z > 0.0) {
		vec2 mp = tile * 0.9 - TIME * motes.xy * 0.9 + vec2(sin(TIME * 0.27 + tile.y * 0.31) * 0.35, 0.0);
		vec2 cell = floor(mp);
		vec2 q = fract(mp) - (vec2(gs_hash(cell), gs_hash(cell + 7.1)) * 0.6 + 0.2);
		m = smoothstep(0.06, 0.0, length(q)) * step(1.0 - motes.z, gs_hash(cell + 3.3));
		m *= 1.0 - motes.w + motes.w * (0.5 + 0.5 * sin(TIME * 2.3 + gs_hash(cell) * 40.0));
		m *= smoothstep(0.02, 0.25, lit);
	}
	if (d + m < 0.002) {
		discard;
	}
	ALBEDO = fog * (0.5 + lit * 0.9) + fog * m * 1.6;
	ALPHA = clamp(d + m, 0.0, 0.7);
}
