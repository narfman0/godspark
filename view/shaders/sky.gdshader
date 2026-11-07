// The sky, the farthest layer: a gradient by the time of day and biome, clouds and stars. It
// rides with the camera at the back of the view; its clouds slide at their own pace.
shader_type spatial;
render_mode unshaded, cull_disabled;

#include "res://view/shaders/light.gdshaderinc"

global uniform sampler2D gs_noise : filter_linear, repeat_enable;

uniform vec3 sky_top : source_color = vec3(0.35, 0.55, 0.85);
uniform vec3 sky_low : source_color = vec3(0.7, 0.8, 0.9);
uniform vec3 cloud : source_color = vec3(1.0);
uniform vec2 scroll = vec2(0.0);
uniform float night = 0.0;

void fragment() {
	float up = clamp(1.0 - SCREEN_UV.y, 0.0, 1.0);
	vec3 c = mix(sky_low, sky_top, smoothstep(0.1, 0.95, up));
	vec2 aspect = vec2(VIEWPORT_SIZE.x / VIEWPORT_SIZE.y, 1.0);
	vec2 p = SCREEN_UV * aspect + scroll;
	float n = texture(gs_noise, p * vec2(0.16, 0.42) + TIME * vec2(0.0016, 0.0)).r * 0.65
		+ texture(gs_noise, p * vec2(0.5, 1.1) + TIME * vec2(0.0035, 0.0)).g * 0.35;
	float clouds = smoothstep(0.5, 0.72, n) * smoothstep(0.2, 0.55, up);
	c = mix(c, cloud, clouds * 0.75);
	if (night > 0.01) {
		vec2 cell = floor(FRAGCOORD.xy * 0.5);
		float s = gs_hash(cell + floor(scroll * 90.0));
		c += vec3(0.75, 0.8, 1.0) * step(0.9972, s) * night * (1.0 - clouds) * smoothstep(0.15, 0.6, up);
	}
	ALBEDO = c;
}
