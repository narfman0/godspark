// Chunk terrain: lit by the sun and lamps through the tile light field (lit.gdshaderinc), so an
// unlit cave is black and a torch throws shadows on its walls.
// Natural ground (kinds 3, 4) reads as terrain: its colour comes from the material map, a texture
// of one texel per tile that filtering blends across neighbours, sampled through a noise warp so
// borders wander instead of following the grid, then broken up by strata and grain in world
// space. Nothing in it knows a tile's edge. Built things (kinds 0, 2) keep their per-tile
// colour and grout.
shader_type spatial;
render_mode cull_back;

#include "res://view/shaders/lit.gdshaderinc"

global uniform sampler2D gs_noise : filter_linear_mipmap, repeat_enable;
global uniform sampler2D gs_mat : filter_linear, repeat_enable;
// The ground line per column of the light rectangle (WorldView._fill_surface); gs_surface_on 0: none.
global uniform sampler2D gs_surface : filter_linear, repeat_disable;
global uniform float gs_surface_on;
// The deep lake (view/below_look.gd): x0, x1, surface and bed rows, and the colour of its light.
global uniform vec4 gs_lake;
global uniform vec4 gs_lake_glow : source_color;

// The material map's size in tiles: it wraps, so a tile's texel is its coordinate modulo this.
const vec2 GS_MAT_SIZE = vec2(512.0, 256.0);

varying vec3 wpos;
varying vec3 wnrm;
varying vec2 info;
varying vec2 face_uv;

// Water's edges on whole rows (the surface among them) ride a slow swell, so a lake's surface is not
// a ruler line. Every water vertex on a row moves by the same function of x, so the sheet's tiles
// stay joined; under the surface the rock in front hides the rest.
float water_swell(float x) {
	return 0.06 * sin(x * 0.55 + TIME * 0.9) + 0.035 * sin(x * 1.7 - TIME * 1.6) + 0.02 * sin(x * 3.1 + TIME * 2.3);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (UV2.y > 4.5) {
		float ty = wpos.y / gs_tile_m;
		if (abs(ty - round(ty)) < 0.01) {
			float dy = water_swell(wpos.x / gs_tile_m) * gs_tile_m;
			VERTEX.y += dy;
			wpos.y += dy;
		}
	}
	wnrm = NORMAL;
	info = UV2;
	face_uv = UV;
}

// The sky's light on the ground's front face (the cut-away), reaching further down than the light
// field does: the field stops at the first tile of rock, and a hard black line under the grass is
// the block-game look. The share falls off with depth under the ground line (gs_surface, the world's
// surface before anything was built on it) over about 24 rows, on front faces only, and only where
// the field has run out: a cave's own faces and walls take the field alone, so a cave stays dark.
// The ground line, not the sky field over the face, so a house or a tree on the ground casts no dark
// shape twenty rows down into it. With no ground line (an old world) the sky field some rows up is
// read instead. `sun` is how much of the sun the face takes: the same fade, so the sun's shading
// does not stop at the first row of tiles in steps.
vec3 ground_light(vec2 tile, vec2 lv, bool front, out float sun) {
	vec3 L = gs_light_lv(lv, tile);
	sun = 0.0;
	if (!front || L.g > 0.3) {
		return L;
	}
	float s;
	if (gs_surface_on > 0.5) {
		float top = texture(gs_surface, vec2((tile.x - gs_light_rect.x) / gs_light_rect.z, 0.5)).r;
		s = 1.0 - smoothstep(2.0, 26.0, top - tile.y);
	} else {
		s = texture(gs_light_sky, gs_light_uv(tile + vec2(0.0, 9.0))).r * 0.55
			+ texture(gs_light_sky, gs_light_uv(tile + vec2(0.0, 20.0))).r * 0.45;
		s = min(s * (255.0 / GS_FULL), 1.0);
	}
	sun = smoothstep(0.25, 0.95, s) * 0.8;
	return max(L, gs_sky_tint.rgb * gs_curve(s * gs_sun) * 0.62);
}

// The lake's water gives a faint light of its own: nothing on the shore reaches it. Brightest at
// the surface, where a line of it shimmers, thinning toward the bed, with slow drifting sparks.
vec3 lake_light(vec2 tile) {
	if (tile.x < gs_lake.x || tile.x > gs_lake.y + 1.0 || tile.y > gs_lake.z + 2.0) {
		return vec3(0.0);
	}
	float d = max(gs_lake.z + 1.0 - tile.y, 0.0);
	float sway = texture(gs_noise, tile * vec2(0.03, 0.05) + TIME * vec2(0.008, -0.004)).r;
	float veil = texture(gs_noise, tile * vec2(0.012, 0.07) - TIME * vec2(0.005, 0.0)).g;
	float glow = (0.012 + 0.13 * exp(-d / 3.5)) * (0.4 + 1.2 * sway) + 0.05 * smoothstep(0.55, 0.8, veil) * exp(-d / 9.0);
	// The surface: a soft band, not a line, broken into glints where the swell catches the light.
	float glint = smoothstep(0.45, 0.85, texture(gs_noise, vec2(tile.x * 0.11 + TIME * 0.03, tile.y * 0.02)).b);
	glow += exp(-d * 1.1) * (0.18 + 0.3 * sway + 0.45 * glint);
	vec2 mp = tile * 0.8 + vec2(TIME * 0.04, sin(TIME * 0.2 + tile.x * 0.13) * 0.4);
	vec2 c = floor(mp);
	vec2 q = fract(mp) - (vec2(gs_hash(c), gs_hash(c + 7.1)) * 0.6 + 0.2);
	glow += smoothstep(0.07, 0.0, length(q)) * step(0.93, gs_hash(c + 3.3)) * (0.5 + 0.5 * sin(TIME * 1.6 + gs_hash(c) * 40.0));
	return gs_lake_glow.rgb * glow;
}

// The lake's light on the rock round it: its bed, its shores and the rock over it take a faint glow
// of the water's colour within a few tiles, since the water's own light (lake_light) is not in the
// field. Multiplies the albedo.
vec3 lake_rock(vec2 tile) {
	if (gs_lake.y < gs_lake.x) {
		return vec3(0.0);
	}
	float dx = max(gs_lake.x - tile.x, tile.x - gs_lake.y - 1.0);
	float dy = max(gs_lake.w - tile.y, tile.y - gs_lake.z - 1.0);
	float d = max(max(dx, 0.0), max(dy, 0.0));
	return gs_lake_glow.rgb * 0.16 * (1.0 - smoothstep(0.0, 6.0, d));
}

// Detail at the scale of a tile and under, so natural ground does not read as an airbrush at zoom 1:
// a mottled grain, a sparse network of fine cracks, and a relief from the grain's slope against the
// key light (screen derivatives, so it costs no extra reads). x: the albedo's factor, y: the light's.
vec2 rock_detail(vec2 tile, float cracks) {
	float g1 = texture(gs_noise, tile * 0.062 + vec2(0.13, 0.71)).a;
	vec2 r = vec2(tile.x * 0.8 - tile.y * 0.6, tile.x * 0.6 + tile.y * 0.8);
	float g2 = texture(gs_noise, r * 0.027 + vec2(0.41, 0.07)).a;
	float g3 = texture(gs_noise, tile * vec2(0.05, 0.065) + vec2(0.77, 0.29)).b;
	float h = g1 * 0.65 + g2 * 0.35;
	vec2 dt = vec2(dFdx(tile.x), dFdy(tile.y));
	vec2 grad = vec2(dFdx(h), dFdy(h)) / max(abs(dt), vec2(1e-4)) * sign(dt);
	float relief = clamp(dot(grad, vec2(-0.35, 0.6)) * 0.22, -0.22, 0.22);
	float crack = smoothstep(0.022, 0.004, abs(g3 - 0.5)) * cracks;
	return vec2((0.86 + 0.28 * h) * (1.0 - 0.35 * crack), 1.0 + relief);
}

// Built walls (cobble, dressed stone, the drow's dark wall: kind 2) as laid stone: staggered courses
// with mortar between, each stone its own shade and a lighter upper edge, cobbles small and round,
// so a wall reads as masonry and not as a grid of tile-sized squares. The albedo's factor.
float masonry(vec2 tile, float id) {
	bool cobble = abs(id - 9.0) < 0.5;
	vec2 size = cobble ? vec2(0.62, 0.42) : vec2(1.0, 0.5);
	vec2 p = tile / size;
	float row = floor(p.y);
	p.x += fract(row * 0.5) + (cobble ? gs_hash(vec2(row, 5.0)) * 0.6 : 0.0);
	vec2 c = floor(p);
	vec2 q = (fract(p) - 0.5) * size;
	float r = cobble ? 0.13 : 0.03;
	vec2 b = abs(q) - (size * 0.5 - vec2(0.035) - r);
	float sd = length(max(b, 0.0)) + min(max(b.x, b.y), 0.0) - r;
	float inside = 1.0 - smoothstep(-0.025, 0.01, sd);
	float h = gs_hash(c + id * 7.31);
	float top = clamp(q.y / (size.y * 0.5), -1.0, 1.0) * 0.1;
	return mix(0.42, 0.78 + 0.34 * h + top, inside);
}

// Drow masonry (tile dark_stone, id 101; wall dark_wall, id 43): a spider's web cut into the stone
// every few tiles, a thread of the fae lamps' light in each cut, so a city reads from across a cavern
// by nothing but its own lines. The web's radial lines and rings, 0..1.
float drow_web(vec2 tile) {
	vec2 cell = floor(tile / 9.0);
	vec2 p = tile - (cell + 0.5) * 9.0 - (vec2(gs_hash(cell), gs_hash(cell + 3.1)) - 0.5) * 1.5;
	float r = length(p);
	float a = (atan(p.y, p.x) + 3.14159) / 6.28318;
	float spoke = abs(fract(a * 8.0) - 0.5) / 8.0 * 6.28318 * r;
	float ring = abs(fract(r * 0.62) - 0.5) / 0.62;
	float lines = max(1.0 - smoothstep(0.015, 0.075, spoke), (1.0 - smoothstep(0.02, 0.07, ring)) * step(0.6, r));
	return lines * (1.0 - smoothstep(3.1, 4.2, r));
}

// Lava (tile id 120, ids are stable): a slow flow of heat under dark plates of crust.
vec3 lava_light(vec2 tile) {
	vec2 p = tile * vec2(0.045, 0.1);
	float a = texture(gs_noise, p + TIME * vec2(0.011, 0.003)).r;
	float b = texture(gs_noise, p * 2.6 - TIME * vec2(0.012, -0.005)).g;
	float heat = smoothstep(0.32, 0.72, a * 0.6 + b * 0.4);
	vec3 c = mix(vec3(0.5, 0.045, 0.008), vec3(1.6, 0.38, 0.03), heat);
	c = mix(c, vec3(2.6, 1.35, 0.3), smoothstep(0.7, 0.95, heat));
	return c;
}

void fragment() {
	vec2 tile = wpos.xy / gs_tile_m;
	float kind = info.y;
	vec3 base = COLOR.rgb;
	// The cell whose light a face shows: the open cell it faces, or the tile it stands for.
	vec2 cell = tile + wnrm.xy * 0.5;
	vec3 L = vec3(0.0);
	vec2 lv = vec2(0.0);
	float shade = 1.0;
	bool glow = false;
	float cut_sun = 0.0;
	// How much of the real lights (sun, lamps) a face takes: a cut-away face of solid ground reads
	// its light from the open cells beside it (gs_face_levels) and is never in a shadow map's shade,
	// so at full strength it would glow brighter than the room it borders.
	float direct = 1.0;
	vec3 own = vec3(0.0);
	if (kind > 4.5) {
		// Water: no tiles, a slow shimmer.
		float n = texture(gs_noise, tile * 0.012 + TIME * vec2(0.006, 0.002)).r
			+ texture(gs_noise, tile * vec2(0.04, 0.02) - TIME * vec2(0.004, 0.0)).g;
		base *= 0.7 + 0.6 * n;
		cell = tile;
		lv = gs_levels(tile);
		L = gs_light_lv(lv, tile);
		own = lake_light(tile);
	} else if (kind > 3.5) {
		// A natural wall behind a cave: the wall's colour, shaded in the ground's own way.
		vec4 n = texture(gs_noise, tile * vec2(0.0035, 0.016) + vec2(0.37, 0.11));
		base *= (0.74 + 0.5 * mix(n.b, n.r, 0.45)) * 1.35;
		vec2 dtl = rock_detail(tile * 0.8 + vec2(31.0, 17.0), 0.6);
		base *= dtl.x;
		shade = dtl.y;
		cell = tile;
		lv = gs_levels_smooth(tile);
		L = gs_light_lv(lv, tile);
		own = base * (gs_deep_glow(tile) + lake_rock(tile));
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
		bool front = wnrm.z > 0.5;
		vec2 dtl = rock_detail(tile, front ? 1.0 : 0.0);
		base *= dtl.x;
		lv = front ? gs_face_levels(tile) : gs_levels(cell);
		direct = front ? 0.35 : 1.0;
		L = ground_light(cell, lv, front, cut_sun);
		shade = gs_face_shade(wnrm) * (front ? dtl.y : 1.0);
		own = base * (gs_deep_glow(tile) + lake_rock(tile));
	} else {
		vec2 c = floor(tile - wnrm.xy * 0.02);
		float h = gs_hash(c + info.x * 17.13);
		base *= 0.86 + 0.28 * h;
		// Faint in-tile grain so big merged faces are not perfectly flat.
		// UV is the tile coordinate on the face's own plane, so side faces do not alias.
		vec2 sub = floor(face_uv * 4.0 + 0.001);
		base *= 0.97 + 0.06 * gs_hash(sub + 3.7);
		if (kind > 0.5 && kind < 1.5) {
			glow = true;   // an emissive tile (a torch's flame): its own light, no other
		} else if (kind > 1.5) {
			// Background wall: laid stone, lit by the cell it is behind.
			base = COLOR.rgb * masonry(tile, info.x) * 1.35;
			cell = tile;
			lv = gs_levels_smooth(tile);
			L = gs_light_lv(lv, tile);
			own = base * gs_deep_glow(tile);
			if (abs(info.x - 43.0) < 0.5) {
				own += vec3(0.3, 0.13, 0.62) * drow_web(tile) * (0.42 + 0.14 * sin(TIME * 0.7 + tile.x * 0.11));
			}
		} else {
			lv = wnrm.z > 0.9 ? gs_face_levels(tile) : gs_levels(cell);
			direct = wnrm.z > 0.9 ? 0.35 : 1.0;
			L = gs_light_lv(lv, cell);
			shade = gs_face_shade(wnrm);
			own = base * gs_deep_glow(tile);
			if (abs(info.x - 101.0) < 0.5 && wnrm.z > 0.9) {
				own += vec3(0.3, 0.13, 0.62) * drow_web(tile) * 0.5;
			}
			if (wnrm.z > 0.9) {
				// Grout between tiles on front faces, so single blocks read inside merged faces.
				vec2 f = abs(fract(tile) - 0.5);
				float edge = smoothstep(0.42, 0.5, max(f.x, f.y));
				base *= (1.0 - 0.22 * edge) * 0.8;
			}
		}
	}
	ROUGHNESS = 0.9;
	if (glow) {
		ALBEDO = vec3(0.0);
		EMISSION = abs(info.x - 120.0) < 0.5 ? lava_light(tile) : base * 2.2;
		gs_m_sun = 0.0;
		gs_m_lamp = 0.0;
	} else {
		ALBEDO = base;
		GS_MASKS_LV(lv);
		gs_m_sun = max(gs_m_sun * direct, cut_sun);
		gs_m_lamp *= direct;
		EMISSION = gs_fill(base, L * shade) + gs_dark_sight(base, L, tile) + own;
	}
}
