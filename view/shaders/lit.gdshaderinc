// Lit surfaces (terrain, actors, dressing). Godot's lights draw direction and shadow: the sun
// (or moon) and the lamp pool of view/world_lights.gd. The tile light field (light.gdshaderinc)
// says where they may shine: the sun only where the sky field reaches, a lamp only where the block
// field does, so an unlit cave stays black whatever the shadow maps miss, and light never crosses
// a wall. A flat share of the field's own light is drawn as emission (the fill), so a lit place
// is never pitch black in a shadow, and Darkvision's grey rides on it.
//
// In fragment(): set ALBEDO, then GS_MASKS(cell) with the tile whose light the surface shows,
// then EMISSION = gs_fill(ALBEDO, L) (+ gs_dark_sight). The light() here does the rest.
#include "res://view/shaders/light.gdshaderinc"

// x: fill (share of the field drawn flat), y: toon (0 smooth .. 1 two bands), z: wrap (how far
// round a surface a light reaches), w: lamp shine (specular share on actors).
global uniform vec4 gs_lit;

varying float gs_m_sun;
varying float gs_m_lamp;

// The masks from the field at a tile: each 0 where its field is dark, 1 from about Dim up.
#define GS_MASKS(cell) { vec2 gs_l_ = gs_levels(cell); gs_m_sun = smoothstep(0.03, 0.4, gs_l_.y); gs_m_lamp = smoothstep(0.03, 0.4, gs_l_.x); }
// The same from levels already read (gs_levels or gs_face_levels).
#define GS_MASKS_LV(lv) { gs_m_sun = smoothstep(0.03, 0.4, (lv).y); gs_m_lamp = smoothstep(0.03, 0.4, (lv).x); }

vec3 gs_fill(vec3 albedo, vec3 L) {
	return albedo * L * gs_lit.x;
}

// Stylised diffuse: a wrapped Lambert snapped toward two soft bands by gs_lit.y.
float gs_diffuse(vec3 n, vec3 l) {
	float w = clamp((dot(n, l) + gs_lit.z) / (1.0 + gs_lit.z), 0.0, 1.0);
	float bands = smoothstep(0.06, 0.16, w) * 0.45 + smoothstep(0.48, 0.58, w) * 0.55;
	return mix(w, bands, gs_lit.y);
}

void light() {
	float m = LIGHT_IS_DIRECTIONAL ? gs_m_sun : gs_m_lamp;
	if (m > 0.001) {
		DIFFUSE_LIGHT += m * gs_diffuse(NORMAL, LIGHT) * ATTENUATION * LIGHT_COLOR / PI;
#ifdef GS_SHINE
		vec3 h = normalize(VIEW + LIGHT);
		float gloss = 1.0 - ROUGHNESS;
		float s = pow(max(dot(NORMAL, h), 0.0), mix(6.0, 80.0, gloss)) * gloss * gs_lit.w;
		SPECULAR_LIGHT += m * smoothstep(0.25, 0.4, s) * ATTENUATION * LIGHT_COLOR / PI;
#endif
	}
}
