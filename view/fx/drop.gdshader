// A dropped item: its icon on a small card, lit like everything else by the tile light, with
// a glint for sparks and magic items (they also glow a little in the dark).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

#include "res://view/shaders/light.gdshaderinc"

uniform sampler2D icon : source_color, filter_linear;
instance uniform vec4 glint : source_color = vec4(0.0, 0.0, 0.0, 0.0);
instance uniform float phase = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 t = texture(icon, UV);
	if (t.a < 0.4) {
		discard;
	}
	vec3 L = gs_light_at(wpos.xy / gs_tile_m);
	vec3 lit = t.rgb * (L + vec3(0.03));
	// a glint: a bright band sweeping across every couple of seconds
	float band = 1.0 - smoothstep(0.0, 0.12, abs(fract(TIME * 0.45 + phase) * 2.2 - 0.6 - (UV.x + UV.y) * 0.5));
	vec3 g = glint.rgb * glint.a * (0.35 + band * 1.4);
	ALBEDO = lit + g * t.a;
}
