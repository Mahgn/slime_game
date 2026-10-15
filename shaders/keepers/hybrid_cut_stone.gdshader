shader_type spatial;
render_mode diffuse_burley;

varying vec3 cut_world;
varying vec3 cut_normal;

float cut_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453);
}

void vertex() {
	cut_world = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
	cut_normal = MODEL_NORMAL_MATRIX * NORMAL;
}

void fragment() {
	vec3 n = abs(cut_normal);
	bool top = n.y > max(n.x,n.z);
	vec2 p = top ? cut_world.xz : (n.x > n.z ? cut_world.zy : cut_world.xy);
	vec2 size = top ? vec2(1.35,0.82) : vec2(1.35,0.28);
	vec2 grid = p / size;
	grid.x += mod(floor(grid.y),2.0) * 0.5;
	vec2 edge = min(fract(grid),1.0-fract(grid)) * size;
	float distance_to_joint = min(edge.x,edge.y);
	float antialias = max(fwidth(distance_to_joint),0.002);
	float joint = 1.0 - smoothstep(0.006,0.006+antialias,distance_to_joint);
	float variation = cut_hash(floor(grid));
	float grain = cut_hash(floor(p * 55.0));
	vec3 stone = vec3(0.36,0.385,0.335) * (0.92 + variation*0.13 + grain*0.025);
	ALBEDO = stone * (1.0 - joint*0.24);
	ROUGHNESS = 0.95;
}
