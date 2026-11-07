// Per-tile light from LightEngine, shared by terrain, backdrop and actor shaders.
// WorldView fills the two R8 textures (one texel per tile, raw levels) around the camera and
// sets gs_light_rect = (origin x, origin y, width, height) in tiles.
global uniform sampler2D gs_light_block : filter_linear, repeat_disable;
global uniform sampler2D gs_light_sky : filter_linear, repeat_disable;
global uniform vec4 gs_light_rect;
global uniform float gs_sun;
global uniform vec4 gs_sky_tint;
global uniform float gs_tile_m;
// The own Darkvision: (x, y) tiles, radius tiles (0: none), grey strength.
global uniform vec4 gs_darkvision;

// LightEngine.SUN (= TORCH): the level that reads as full light.
const float GS_FULL = 85.0;
const vec3 GS_TORCH_TINT = vec3(1.0, 0.66, 0.36);

// Level fraction to brightness. Bright (>= 0.53) stays well lit, dim fades toward black.
float gs_curve(float l) {
	l = clamp(l, 0.0, 1.5);
	return pow(l, 1.35);
}

vec2 gs_light_uv(vec2 tile) {
	return (tile - gs_light_rect.xy) / gs_light_rect.zw;
}

// Raw levels as fractions of full light: x = block, y = sky (not scaled by sun).
vec2 gs_levels(vec2 tile) {
	vec2 uv = gs_light_uv(tile);
	return vec2(texture(gs_light_block, uv).r, texture(gs_light_sky, uv).r) * (255.0 / GS_FULL);
}

// Light colour at a point in tile units.
vec3 gs_light_at(vec2 tile) {
	vec2 l = gs_levels(tile);
	vec3 lb = GS_TORCH_TINT * gs_curve(l.x) * 1.4;
	vec3 ls = gs_sky_tint.rgb * gs_curve(l.y * gs_sun);
	return max(lb, ls) + 0.35 * min(lb, ls);
}

// Darkvision draws the dark near its owner in grey: the albedo's luminance, no colour, fading
// out at the radius and where real light already shows the colour.
vec3 gs_dark_sight(vec3 base, vec3 L, vec2 tile) {
	if (gs_darkvision.z <= 0.0) {
		return vec3(0.0);
	}
	float d = distance(tile, gs_darkvision.xy) / gs_darkvision.z;
	float k = gs_darkvision.w * (1.0 - smoothstep(0.55, 1.0, d)) * (1.0 - clamp(max(L.r, max(L.g, L.b)) * 2.5, 0.0, 1.0));
	return vec3(dot(base, vec3(0.3, 0.55, 0.15))) * k;
}

float gs_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Fixed key light for face shading: front faces read 1.0, top bevels brighter, undersides darker.
float gs_face_shade(vec3 n) {
	vec3 key = normalize(vec3(-0.35, 0.6, 0.72));
	return (0.5 + 0.5 * max(dot(n, key), 0.0)) / 0.86;
}
