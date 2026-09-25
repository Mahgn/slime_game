shader_type spatial;
render_mode cull_disabled;

// Body-surface colour at the attachment point; the tendril stays rigid while the v5 body crawls.
uniform vec3 attachment_pos = vec3(0.41, 0.18, -0.32);

void fragment() {
	vec3 model_pos = attachment_pos;
	float height_mix = smoothstep(-0.38, 0.38, model_pos.y);
	float radial = length(vec2(model_pos.x * 1.03, model_pos.y * 0.96));
	float inner = 1.0 - smoothstep(0.10, 0.54, radial);
	float rim = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 1.25);
	vec3 base = mix(vec3(0.045, 0.43, 0.49), vec3(0.23, 0.79, 0.65), 0.12 + height_mix * 0.69);
	base *= 1.0 - inner * 0.24;
	base *= mix(1.04, 1.0, smoothstep(0.0, 0.32, UV.x));
	ALBEDO = (base + vec3(0.36, 0.48, 0.40) * rim * 0.18) * 0.88;
	ROUGHNESS = 0.25;
	SPECULAR = 0.55;
	RIM = 0.20;
	RIM_TINT = 0.25;
	EMISSION = base * 0.08;
}