// Chunk terrain, lit per tile by LightEngine (unshaded: an unlit cave is black).
// Natural ground (kinds 3, 4) reads as terrain: its colour comes from the material map, a texture
// of one texel per tile that filtering blends across neighbours, sampled through a noise warp so
// borders wander instead of following the grid, then broken up by strata and grain in world
// space. Nothing in it knows a tile's edge. Built things (kinds 0, 2) keep their per-tile
// colour and grout.
shader_type spatial;
render_mode unshaded, cull_back;

#include "res://view/shaders/light.gdshaderinc"

global uniform sampler2D gs_noise : filter_linear_mipmap, repeat_enable;
global uniform sampler2D gs_mat : filter_linear, repeat_enable;

// The material map's size in tiles: it wraps, so a tile's texel is its coordinate modulo this.
const vec2 GS_MAT_SIZE = vec2(512.0, 256.0);

varying vec3 wpos;
varying vec3 wnrm;
varying vec2 info;
varying vec2 face_uv;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = NORMAL;
	info = UV2;
	face_uv = UV;
}

// The sky's light on a face, reaching further into the ground than the light field does: the
// field stops some rows in, and a hard black edge under the grass is the block-game look. Above
// it, a share of the light a way up carries the shade on down. Only where the field has run out.
vec3 ground_light(vec2 tile) {
	vec3 L = gs_light_at(tile);
	if (L.g > 0.3) {
		return L;
	}
	float s = texture(gs_light_sky, gs_light_uv(tile + vec2(0.0, 9.0))).r * 0.55
		+ texture(gs_light_sky, gs_light_uv(tile + vec2(0.0, 20.0))).r * 0.45;
	return max(L, gs_sky_tint.rgb * gs_curve(min(s * (255.0 / GS_FULL), 1.0) * gs_sun) * 0.62);
}

void fragment() {
	vec2 tile = wpos.xy / gs_tile_m;
	float kind = info.y;
	vec3 base = COLOR.rgb;
	if (kind > 4.5) {
		// Water: no tiles, a slow shimmer.
		float n = texture(gs_noise, tile * 0.012 + TIME * vec2(0.006, 0.002)).r
			+ texture(gs_noise, tile * vec2(0.04, 0.02) - TIME * vec2(0.004, 0.0)).g;
		ALBEDO = base * (0.7 + 0.6 * n) * (gs_light_at(tile) + vec3(0.004));
	} else if (kind > 3.5) {
		// A natural wall behind a cave: the wall's colour, shaded in the ground's own way.
		vec4 n = texture(gs_noise, tile * vec2(0.0035, 0.016) + vec2(0.37, 0.11));
		base *= 0.74 + 0.5 * mix(n.b, n.r, 0.45);
		vec3 L = gs_light_at(tile);
		ALBEDO = base * 1.35 * (L + vec3(0.004)) + gs_dark_sight(base, L, tile);
	} else if (kind > 2.5) {
		// Two looks at the noise pay for everything: broad strata and a fine grain, each also
		// wandering the sampling point of the material map.
		vec4 broad = texture(gs_noise, tile * vec2(0.0035, 0.016));
		vec4 fine = texture(gs_noise, tile * vec2(0.021, 0.029));
		vec2 warp = (broad.rg - 0.5) * 3.2 + (fine.gb - 0.5) * 1.2;
		vec4 m = texture(gs_mat, (tile + warp) / GS_MAT_SIZE);
		vec3 blended = m.a > 0.02 ? pow(m.rgb / m.a, vec3(2.2)) : base;
		base = mix(base, blended, smoothstep(0.05, 0.4, m.a));
		base *= 0.62 + 0.62 * mix(broad.b, broad.r, 0.45) + 0.16 * (fine.a - 0.5);
		vec3 L = ground_light(tile + wnrm.xy * 0.5);
		ALBEDO = base * (L * gs_face_shade(wnrm) + vec3(0.004)) + gs_dark_sight(base, L, tile);
	} else {
		vec2 cell = floor(tile - wnrm.xy * 0.02);
		float h = gs_hash(cell + info.x * 17.13);
		base *= 0.86 + 0.28 * h;
		// Faint in-tile grain so big merged faces are not perfectly flat.
		// UV is the tile coordinate on the face's own plane, so side faces do not alias.
		vec2 sub = floor(face_uv * 4.0 + 0.001);
		base *= 0.97 + 0.06 * gs_hash(sub + 3.7);
		if (kind > 0.5 && kind < 1.5) {
			ALBEDO = base * 2.2;  // emissive tile (torch flame)
		} else if (kind > 1.5) {
			// Background wall: darker, lit by the cell it is behind.
			vec3 L = gs_light_at(tile);
			ALBEDO = base * 1.35 * (L + vec3(0.004)) + gs_dark_sight(base, L, tile);
		} else {
			vec3 L = gs_light_at(tile + wnrm.xy * 0.5);
			if (wnrm.z > 0.9) {
				// Grout between tiles on front faces, so single blocks read inside merged faces.
				vec2 f = abs(fract(tile) - 0.5);
				float edge = smoothstep(0.42, 0.5, max(f.x, f.y));
				base *= (1.0 - 0.22 * edge) * 0.8;
			}
			ALBEDO = base * (L * gs_face_shade(wnrm) + vec3(0.004)) + gs_dark_sight(base, L, tile);
		}
	}
}
