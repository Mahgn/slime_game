shader_type spatial;
render_mode diffuse_burley;

uniform vec4 base_color : source_color = vec4(0.145, 0.169, 0.145, 1.0);
varying vec3 stone_world_position;

float stone_hash(vec2 point) {
	vec3 value = fract(vec3(point.xyx) * 0.1031);
	value += dot(value, value.yzx + 33.33);
	return fract((value.x + value.y) * value.z);
}

float stone_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 blend = fract(point);
	blend = blend * blend * (3.0 - 2.0 * blend);
	return mix(mix(stone_hash(cell), stone_hash(cell + vec2(1.0, 0.0)), blend.x),
		mix(stone_hash(cell + vec2(0.0, 1.0)), stone_hash(cell + vec2(1.0)), blend.x), blend.y);
}

void vertex() {
	stone_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// The same quiet, continuous stone as the former building mass. No tile
	// grid or screen-space mask: every exposed boundary has actual side faces.
	vec2 point = stone_world_position.xz;
	float age = stone_noise(point * 0.39);
	float grain = stone_noise(point * 31.0);
	ALBEDO = base_color.rgb * (0.81 + age * 0.28 + grain * 0.035);
	ROUGHNESS = 0.95;
}
