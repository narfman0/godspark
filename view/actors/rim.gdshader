// A creature's silhouette, an outline drawn as an overlay on every surface (skinned too): the
// back faces pushed out along the normals, in `rim`. rim.a 0 draws nothing.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, blend_mix, shadows_disabled;

instance uniform vec4 rim : source_color = vec4(0.0);
uniform float width_m = 0.03;

void vertex() {
	VERTEX += NORMAL * width_m / max(length(MODEL_MATRIX[0].xyz), 0.0001);
}

void fragment() {
	ALBEDO = rim.rgb;
	ALPHA = rim.a;
}
