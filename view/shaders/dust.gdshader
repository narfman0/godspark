// Dust in a sunlit shaft under cover: slanted rays and drifting motes, added over the cells where
// the sky field is lit and both sides of it, `width` tiles away, are dark: a hole down into a cave,
// a narrow gap. Open air and a cave mouth get none (one side of them is lit). A sheet just in
// front of the walls (WorldLights), behind the actors; rock in front of it hides it.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

#include "res://view/shaders/light.gdshaderinc"

global uniform sampler2D gs_noise : filter_linear_mipmap, repeat_enable;

uniform float strength = 0.3;
uniform float rays = 1.0;
uniform float motes = 1.0;
uniform float width = 5.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float gs_sky_frac(vec2 t) {
	return texture(gs_light_sky, gs_light_uv(t)).r * (255.0 / GS_FULL);
}

void fragment() {
	vec2 tile = wpos.xy / gs_tile_m;
	float c = gs_sky_frac(tile);
	float side = max(gs_sky_frac(tile + vec2(width, 0.0)), gs_sky_frac(tile - vec2(width, 0.0)));
	float shaft = smoothstep(0.3, 0.9, c) * (1.0 - smoothstep(0.2, 0.65, side));
	if (shaft < 0.002) {
		discard;
	}
	// Rays: streaks leaning with the light, drifting down slowly.
	vec2 rp = vec2(tile.x * 0.11 + tile.y * 0.03, tile.y * 0.006 - TIME * 0.004);
	float r = smoothstep(0.42, 0.85, texture(gs_noise, rp).r);
	// Motes: a point in some cells of a drifting grid, twinkling.
	vec2 mp = tile * 2.2 + vec2(sin(TIME * 0.31 + tile.y * 0.37) * 0.7, -TIME * 0.22);
	vec2 cell = floor(mp);
	vec2 f = fract(mp) - (vec2(gs_hash(cell), gs_hash(cell + 7.1)) * 0.6 + 0.2);
	float m = smoothstep(0.075, 0.0, length(f)) * step(0.6, gs_hash(cell + 3.3));
	float twinkle = 0.55 + 0.45 * sin(TIME * 1.7 + gs_hash(cell) * 40.0);
	vec3 col = gs_sky_tint.rgb * gs_curve(gs_sun);
	ALBEDO = col * shaft * strength * (rays * (0.25 + 0.75 * r) + motes * m * twinkle * 2.5);
}
