// A wind-up telegraph or aiming preview drawn flat on the front plane: an SRD shape in tile
// units around `origin` (the quad's centre), filling up as the wind-up runs.
//   shape 0 arc (melee: radius `size`, half angle `half_deg`), 1 cone, 2 line (width `width`),
//   3 circle, 4 square (one face on the origin, extending along dir)
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_mix;

uniform int shape = 0;
uniform float size = 3.0;
uniform float extent = 3.0;      // half the quad, tiles
uniform vec2 dir = vec2(1.0, 0.0);
uniform float half_deg = 70.0;
uniform float width = 2.0;
uniform float progress = 0.0;
uniform vec4 color : source_color = vec4(0.85, 0.27, 0.17, 1.0);
uniform vec4 ink : source_color = vec4(0.1, 0.08, 0.07, 1.0);

float sd_shape(vec2 p) {
	vec2 d = normalize(dir);
	vec2 n = vec2(-d.y, d.x);
	float along = dot(p, d);
	float side = dot(p, n);
	if (shape == 3) {
		return length(p) - size;
	} else if (shape == 2) {
		vec2 q = vec2(abs(along - size * 0.5) - size * 0.5, abs(side) - width * 0.5);
		return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
	} else if (shape == 4) {
		vec2 q = vec2(abs(along - size * 0.5) - size * 0.5, abs(side) - size * 0.5);
		return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
	}
	float ha = shape == 1 ? 0.4636 : radians(half_deg);
	float a = atan(side, along);
	float r = length(p);
	float d_r = r - size;
	float d_a = (abs(a) - ha) * max(r, 0.5);
	return max(d_r, d_a);
}

void fragment() {
	vec2 p = (vec2(UV.x, 1.0 - UV.y) * 2.0 - 1.0) * extent;
	float d = sd_shape(p);
	float px = fwidth(d) * 1.2;
	float inside = 1.0 - smoothstep(-px, px, d);
	float edge = 1.0 - smoothstep(0.06, 0.06 + px, abs(d + 0.08));
	// the fill grows from the origin outward as the wind-up runs
	float grow = (shape == 2 || shape == 4) ? dot(p, normalize(dir)) / max(size, 0.01) : length(p) / max(size, 0.01);
	float filled = step(grow, progress) * inside;
	// hatching: diagonal ink strokes, like a woodcut
	float hatch = step(0.82, fract((p.x + p.y) * 1.6));
	vec3 col = mix(color.rgb, ink.rgb, hatch * 0.35);
	float a = inside * 0.16 + filled * 0.30 + edge * 0.85;
	ALBEDO = mix(col, ink.rgb, edge * 0.55);
	ALPHA = clamp(a, 0.0, 0.9) * color.a;
}
