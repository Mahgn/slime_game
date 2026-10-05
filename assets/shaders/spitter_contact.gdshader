shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float radius = dot(p, p);
	ALBEDO = vec3(0.055, 0.043, 0.060);
	ALPHA = exp(-radius * 3.5) * (1.0 - smoothstep(0.64, 1.0, radius)) * 0.26;
}
