shader_type spatial;
render_mode blend_mix, cull_disabled, depth_prepass_alpha;

uniform float fade : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - facing, 1.35);
	float streak = exp(-pow((UV.x - 0.28) * 10.0, 2.0));
	streak *= smoothstep(0.12, 0.32, UV.y) * (1.0 - smoothstep(0.80, 0.98, UV.y));
	float wet = COLOR.a * streak;
	vec3 gel = COLOR.rgb;
	ALBEDO = gel * (0.83 + 0.15 * rim) + vec3(0.18, 0.32, 0.28) * wet;
	ROUGHNESS = mix(0.30, 0.14, COLOR.a);
	SPECULAR = 0.80;
	RIM = 0.22;
	RIM_TINT = 0.32;
	EMISSION = gel * 0.025 + vec3(0.07, 0.16, 0.13) * wet;
	ALPHA = clamp(fade, 0.0, 1.0);
}
