shader_type spatial;
render_mode cull_back;

uniform float flow_time = 0.0;
varying float axis_position;

void vertex() {
	axis_position = VERTEX.z;
	float tail = smoothstep(0.04, 0.64, VERTEX.z);
	float pulse = sin(flow_time * 10.5 - VERTEX.z * 4.7);
	VERTEX.xy *= 1.0 + pulse * (0.052 + 0.025 * (1.0 - tail));
	VERTEX.x += tail * 0.026 * sin(flow_time * 11.0 - VERTEX.z * 9.0);
	VERTEX.y += tail * 0.015 * cos(flow_time * 9.3 - VERTEX.z * 7.5);
	float surface_wave = sin(VERTEX.z * 19.0 - flow_time * 12.0 + atan(VERTEX.y, VERTEX.x) * 2.5);
	VERTEX.xy += NORMAL.xy * surface_wave * tail * 0.012;
}


void fragment() {
	float rear = smoothstep(0.10, 0.70, axis_position);
	float crown = smoothstep(-0.65, 0.85, NORMAL.y);
	vec3 body = mix(vec3(0.045, 0.43, 0.49), vec3(0.23, 0.79, 0.65), 0.16 + crown * 0.66);
	body = mix(body, vec3(0.18, 0.70, 0.61), rear * 0.35);
	float rim = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 1.65);
	ALBEDO = (body + vec3(0.36, 0.48, 0.40) * rim * 0.18) * 0.94;
	ROUGHNESS = 0.23;
	SPECULAR = 0.62;
	RIM = 0.20;
	RIM_TINT = 0.25;
	EMISSION = body * 0.07;
}
