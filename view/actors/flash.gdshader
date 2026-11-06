// A creature struck: the whole body lit by `flash` for a moment, whatever the light on it.
shader_type spatial;
render_mode unshaded, depth_draw_never, blend_mix, shadows_disabled;

instance uniform vec4 flash : source_color = vec4(0.0);

void fragment() {
	ALBEDO = flash.rgb;
	ALPHA = flash.a;
}
