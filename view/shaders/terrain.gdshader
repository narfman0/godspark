// Chunk terrain: vertex colour (later a texture array layer from UV2.x), per-tile hash
// variation, face shading, and per-tile light from the light textures. Unshaded: all light
// comes from LightEngine, so an unlit cave is black.
shader_type spatial;
render_mode unshaded, cull_back;

#include "res://view/shaders/light.gdshaderinc"

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

void fragment() {
	vec2 tile = wpos.xy / gs_tile_m;
	vec2 cell = floor(tile - wnrm.xy * 0.02);
	vec3 base = COLOR.rgb;
	float h = gs_hash(cell + info.x * 17.13);
	base *= 0.86 + 0.28 * h;
	// Faint in-tile grain so big merged faces are not perfectly flat.
	// UV is the tile coordinate on the face's own plane, so side faces do not alias.
	vec2 sub = floor(face_uv * 4.0 + 0.001);
	base *= 0.97 + 0.06 * gs_hash(sub + 3.7);
	float kind = info.y;
	if (kind > 0.5 && kind < 1.5) {
		ALBEDO = base * 2.2;  // emissive tile (torch flame)
	} else if (kind > 1.5) {
		// Background wall: darker, lit by the cell it is behind.
		ALBEDO = base * 1.35 * (gs_light_at(tile) + vec3(0.004));
	} else {
		vec3 L = gs_light_at(tile + wnrm.xy * 0.5);
		if (wnrm.z > 0.9) {
			// Grout between tiles on front faces, so single blocks read inside merged faces.
			vec2 f = abs(fract(tile) - 0.5);
			float edge = smoothstep(0.42, 0.5, max(f.x, f.y));
			base *= (1.0 - 0.22 * edge) * 0.8;
		}
		ALBEDO = base * (L * gs_face_shade(wnrm) + vec3(0.004));
	}
}
