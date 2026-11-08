// Per-tile light from LightEngine, shared by terrain, backdrop and actor shaders.
// WorldView fills the two R8 textures (one texel per tile, raw levels) around the camera and
// sets gs_light_rect = (origin x, origin y, width, height) in tiles.
// The fields have mipmaps (WorldView._refill_light): gs_face_levels reads them blurred.
global uniform sampler2D gs_light_block : filter_linear_mipmap, repeat_disable;
global uniform sampler2D gs_light_sky : filter_linear_mipmap, repeat_disable;
// Which tiles block light (255) and which are open, one texel per tile, wrapping at
// GS_SOLID_SIZE like the material map, with mipmaps (WorldView._write_solid).
global uniform sampler2D gs_solid : filter_linear_mipmap, repeat_enable;
// The deep regions' rock glow (view/below_look.gd rock_bytes): colour premultiplied by strength,
// over the light rectangle; clear in the plain underdark and on the surface.
global uniform sampler2D gs_below_rock : filter_linear, repeat_disable;
global uniform vec4 gs_light_rect;
global uniform float gs_sun;
global uniform vec4 gs_sky_tint;
global uniform float gs_tile_m;
// What colours the block light (view/below_look.gd): premultiplied colour and how much of the light
// a tinted tile's, over the light rectangle; the own carried light (x, y, radius tiles, on), near
// which it keeps its own colour.
global uniform sampler2D gs_below_tint : filter_linear, repeat_disable;
global uniform vec4 gs_own_lamp;
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

// The block light's colour at a point: torchlight, unless a tinted tile lights it.
vec3 gs_block_tint(vec2 tile) {
	vec4 t = texture(gs_below_tint, gs_light_uv(tile));
	float a = smoothstep(0.0, 0.08, t.a);
	if (gs_own_lamp.z > 0.0) {
		a *= smoothstep(0.3, 0.9, distance(tile, gs_own_lamp.xy) / gs_own_lamp.z);
	}
	return mix(GS_TORCH_TINT, t.rgb / max(t.a, 0.01), a);
}

// A cubic B-spline read in four filtered reads: the reads' uvs (xz, yz, xw, yw) of a texture
// `size` texels across at texel coordinate p (texel centres at whole numbers), and the weights to
// mix them with (out a). Bilinear filtering has a crease at every texel centre, which dim light
// shows as a grid of squares, as steps along the edge of a lit pocket, or as a faint straight line
// where a smoothstep sharpens it. The spline is smooth across them.
vec4 gs_cubic_uv(vec2 p, vec2 size, out vec2 a) {
	vec2 f = fract(p);
	p -= f;
	vec4 n = vec4(1.0, 2.0, 3.0, 4.0);
	vec4 sx = (n - f.x) * (n - f.x) * (n - f.x);
	vec4 sy = (n - f.y) * (n - f.y) * (n - f.y);
	vec4 wx = vec4(sx.x, sx.y - 4.0 * sx.x, sx.z - 4.0 * sx.y + 6.0 * sx.x, 0.0);
	wx.w = 6.0 - wx.x - wx.y - wx.z;
	vec4 wy = vec4(sy.x, sy.y - 4.0 * sy.x, sy.z - 4.0 * sy.y + 6.0 * sy.x, 0.0);
	wy.w = 6.0 - wy.x - wy.y - wy.z;
	vec4 s = vec4(wx.x + wx.y, wx.z + wx.w, wy.x + wy.y, wy.z + wy.w);
	a = vec2(s.x / (s.x + s.y), s.z / (s.z + s.w));
	return (p.xxyy + vec4(-0.5, 1.5, -0.5, 1.5) + vec4(wx.y, wx.w, wy.y, wy.w) / s) / size.xxyy;
}

// gs_levels through the spline: for large open surfaces (walls). A wall's light reaches about a
// tile further across a thin rock wall, faintly, which the rock's face in front hides.
vec2 gs_levels_smooth(vec2 tile) {
	vec2 a;
	vec4 o = gs_cubic_uv(tile - gs_light_rect.xy - 0.5, gs_light_rect.zw, a);
	vec2 s0 = vec2(textureLod(gs_light_block, o.xz, 0.0).r, textureLod(gs_light_sky, o.xz, 0.0).r);
	vec2 s1 = vec2(textureLod(gs_light_block, o.yz, 0.0).r, textureLod(gs_light_sky, o.yz, 0.0).r);
	vec2 s2 = vec2(textureLod(gs_light_block, o.xw, 0.0).r, textureLod(gs_light_sky, o.xw, 0.0).r);
	vec2 s3 = vec2(textureLod(gs_light_block, o.yw, 0.0).r, textureLod(gs_light_sky, o.yw, 0.0).r);
	return mix(mix(s3, s2, a.x), mix(s1, s0, a.x), a.y) * (255.0 / GS_FULL);
}

// Light colour from levels (as gs_levels) at a point in tile units.
vec3 gs_light_lv(vec2 l, vec2 tile) {
	vec3 lb = gs_block_tint(tile) * gs_curve(l.x) * 1.4;
	vec3 ls = gs_sky_tint.rgb * gs_curve(l.y * gs_sun);
	return max(lb, ls) + 0.35 * min(lb, ls);
}

// Light colour at a point in tile units.
vec3 gs_light_at(vec2 tile) {
	return gs_light_lv(gs_levels(tile), tile);
}

const vec2 GS_SOLID_SIZE = vec2(512.0, 256.0);

// The levels a face of solid ground shows, seen in section (a front face). The field holds nothing
// inside rock (no opaque tile gives or passes light), so such a face read at its own tile is black
// with a rim of filtered spill that steps along the tile grid. It shows the mean light of the open
// cells near it instead, fading over a tile or two into the rock: the field and the solid map
// read at the same coarser mip levels, the one divided by the other's open share. Two levels summed
// (2 and 8 tiles across) make a rounder kernel than either: one alone shows its boxes as blotches
// inside a thick ledge and as steps along a diagonal. Both maps line up with the world's grid
// (WorldView), so nothing shifts as the camera moves. A ledge between two lit rooms reads as lit
// stone; rock far from any open cell stays black. Levels as gs_levels.
vec2 gs_face_levels(vec2 tile) {
	vec2 uv = gs_light_uv(tile);
	vec2 suv = tile / GS_SOLID_SIZE;
	float open = 2.0 - textureLod(gs_solid, suv, 1.0).r - textureLod(gs_solid, suv, 3.0).r;
	vec2 l = vec2(textureLod(gs_light_block, uv, 1.0).r + textureLod(gs_light_block, uv, 3.0).r,
		textureLod(gs_light_sky, uv, 1.0).r + textureLod(gs_light_sky, uv, 3.0).r);
	return l / max(open, 0.04) * smoothstep(0.2, 1.0, open) * (255.0 / GS_FULL);
}

// A faint glow of a deep region's own colour on rock and walls near where its light is: the mean
// block light over about 16 tiles (mip level 4) says how near, gs_below_rock how much and what
// colour. None in the plain underdark or with no light about, so the dark there stays black; it is
// the picture's, not the rules'. Multiplies the albedo.
vec3 gs_deep_glow(vec2 tile) {
	vec2 uv = gs_light_uv(tile);
	vec4 r = texture(gs_below_rock, uv);
	if (r.a < 0.004) {
		return vec3(0.0);
	}
	// Levels 4 and 5 (16 and 32 tiles) averaged, through a soft knee: bilinear filtering creases each
	// level at its texel centres, and a sharp curve (a smoothstep) drew one as a faint straight line
	// across the fungal fog. Two levels halve each crease; the knee does not sharpen them.
	float far = (textureLod(gs_light_block, uv, 4.0).r + textureLod(gs_light_block, uv, 5.0).r) * (0.5 * 255.0 / GS_FULL);
	return r.rgb * min(far / (far + 0.06) * 1.3, 1.0);
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
