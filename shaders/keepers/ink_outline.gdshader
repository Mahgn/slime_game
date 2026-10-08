shader_type spatial;
render_mode unshaded, fog_disabled, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled;

uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec4 ink : source_color = vec4(0.035, 0.025, 0.060, 1.0);
uniform float width_pixels = 1.4;
uniform float strength = 0.85;
uniform float crease_strength = 0.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float view_depth(vec2 uv, mat4 inverse_projection) {
	float z = textureLod(scene_depth, uv, 0.0).r;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, z) * 2.0 - 1.0;
	#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, z);
	#endif
	vec4 p = inverse_projection * vec4(ndc, 1.0);
	return -p.z / p.w;
}

void fragment() {
	// Second differences reject the constant depth slope of the isometric floor.
	// No colour edges: tile joints, noise and hazard colours never become ink.
	vec2 px = width_pixels / VIEWPORT_SIZE;
	float c = view_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	float l = view_depth(SCREEN_UV - vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	float r = view_depth(SCREEN_UV + vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	float u = view_depth(SCREEN_UV - vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	float d = view_depth(SCREEN_UV + vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	float curvature = max(abs(l + r - 2.0 * c), abs(u + d - 2.0 * c));
	float outside = max(c - min(min(l, r), min(u, d)), 0.0);
	float edge = smoothstep(0.065, 0.16, curvature) * smoothstep(0.025, 0.095, outside);
	// Extra internal form lines are restricted to geometry, never colour noise.
	edge = max(edge, crease_strength * smoothstep(0.12, 0.40, curvature));
	ALBEDO = ink.rgb;
	ALPHA = edge * strength;
}
