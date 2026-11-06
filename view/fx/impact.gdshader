// The mark a contact leaves on a creature, flat on the front plane: a burst of ink strokes for
// a hit, a bigger star and ring for a crit, a thin grey ring broken by a slash for a miss.
//   kind 0 hit, 1 crit, 2 miss
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_mix;

uniform int kind = 0;
uniform float progress = 0.0;
uniform float rays = 7.0;
uniform float phase = 0.0;
uniform vec4 color : source_color = vec4(1.0, 0.5, 0.2, 1.0);

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = atan(p.y, p.x) + phase;
	float grow = 1.0 - pow(1.0 - progress, 3.0);
	float fade = 1.0 - progress * progress;
	float v = 0.0;
	if (kind == 2) {
		float ring = 1.0 - smoothstep(0.02, 0.07, abs(r - (0.35 + 0.5 * grow)));
		float gap = smoothstep(0.1, 0.25, abs(sin(a * 2.0)));
		float cut = (1.0 - smoothstep(0.02, 0.06, abs(p.x + p.y))) * (1.0 - smoothstep(0.5, 0.7, r / max(grow, 0.05)));
		v = max(ring * gap, cut * 0.9);
	} else {
		float spike = pow(abs(cos(a * rays * 0.5)), 6.0);
		float reach = (0.35 + 0.65 * spike) * grow;
		float body = 1.0 - smoothstep(reach * 0.75, reach + 0.01, r);
		float hole = smoothstep(grow * 0.25, grow * 0.5 + 0.01, r);
		v = body * mix(1.0, hole, progress);
		if (kind == 1) {
			v = max(v, 1.0 - smoothstep(0.0, 0.06, abs(r - grow * 0.95)));
		}
	}
	vec3 core = mix(vec3(1.0, 0.98, 0.9), color.rgb, smoothstep(0.1, 0.6, r));
	ALBEDO = core;
	ALPHA = clamp(v, 0.0, 1.0) * fade * color.a;
}
