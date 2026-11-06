// A weapon's swing drawn flat on the front plane: a crescent that sweeps through the arc the
// host tests (attacker's box grown by the weapon's reach, +-half_deg around dir), leaving a
// fading trail. In tile units around the quad's centre.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_mix;

uniform float size = 2.0;        // reach past the box, tiles
uniform vec2 box = vec2(0.75, 1.25);  // half the attacker's box
uniform float extent = 3.0;      // half the quad, tiles
uniform vec2 dir = vec2(1.0, 0.0);
uniform float half_deg = 70.0;
uniform float progress = 0.0;    // 0..1 across the arc
uniform float side = 1.0;        // which way it sweeps
uniform float fade = 1.0;
uniform float width = 0.6;       // the crescent's share of the reach
uniform vec4 color : source_color = vec4(1.0, 0.95, 0.77, 1.0);

void fragment() {
	vec2 p = (vec2(UV.x, 1.0 - UV.y) * 2.0 - 1.0) * extent;
	vec2 d = normalize(dir);
	vec2 n = vec2(-d.y, d.x);
	float a = atan(dot(p, n), dot(p, d)) * side;
	float ha = radians(half_deg);
	float q = length(max(abs(p) - box, 0.0)) / max(size, 0.01);     // 1 at the reach
	float head = mix(-ha, ha, progress);
	float behind = head - a;
	float trail = behind >= 0.0 ? pow(clamp(1.0 - behind / (ha * 1.3), 0.0, 1.0), 2.0) : 0.0;
	float band = smoothstep(1.0 - width, 1.0 - width * 0.3, q) * (1.0 - smoothstep(0.97, 1.03, q));
	float tip = smoothstep(0.035, 0.0, abs(behind)) * step(q, 1.03) * smoothstep(1.0 - width, 1.0, q);
	float inside = step(abs(a), ha);
	float v = (trail * band + tip) * inside * fade;
	ALBEDO = mix(color.rgb, vec3(1.0), clamp(tip + trail * 0.3, 0.0, 1.0));
	ALPHA = clamp(v * 1.3, 0.0, 1.0) * color.a;
}
