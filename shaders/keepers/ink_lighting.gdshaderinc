// Included only in a private shader variant of the facility's opaque materials.
// Original resources are retained for exact restoration in modes 0 and 1.
uniform float ink_light_gain = 1.22;
uniform float ink_graphic = 0.0;
uniform float ink_hatching = 0.0;
varying vec3 ink_world_position;
varying vec3 ink_world_normal;

float ink_stroke(float coordinate) {
	float width = clamp(fwidth(coordinate) * 0.65, 0.025, 0.32);
	return 1.0 - smoothstep(0.035, 0.035 + width, abs(fract(coordinate) - 0.5));
}

void light() {
	float n = max(dot(NORMAL, LIGHT), 0.0);
	float band = 0.18 + 0.37 * smoothstep(0.20, 0.26, n) + 0.45 * smoothstep(0.66, 0.72, n);
	float graphic_band = 0.10 + 0.34 * smoothstep(0.30, 0.32, n) + 0.56 * smoothstep(0.72, 0.74, n);
	band = mix(band, graphic_band, ink_graphic);
	if (ink_hatching > 0.0) {
		vec3 normal_weights = abs(ink_world_normal);
		vec2 paper = normal_weights.y > max(normal_weights.x, normal_weights.z) ? ink_world_position.xz : (normal_weights.x > normal_weights.z ? ink_world_position.zy : ink_world_position.xy);
		float stroke = ink_stroke(dot(paper, vec2(7.0, 4.0)));
		float crossing = ink_stroke(dot(paper, vec2(-5.0, 7.0)));
		float shade = 1.0 - smoothstep(0.50, 0.95, n);
		float deep_shade = 1.0 - smoothstep(0.15, 0.44, n);
		band *= 1.0 - max(stroke * shade, crossing * deep_shade) * ink_hatching * 0.70;
	}
	float attenuation = ATTENUATION;
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * band * attenuation * ink_light_gain / PI;
	vec3 halfway = normalize(LIGHT + VIEW);
	float highlight = smoothstep(0.91, 0.97, dot(NORMAL, halfway));
	SPECULAR_LIGHT += LIGHT_COLOR * highlight * pow(1.0 - ROUGHNESS, 2.0) * attenuation * 0.22;
}
