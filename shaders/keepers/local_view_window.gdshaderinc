// One camera projection for walls, coping, mounted props AND shadow passes.
// No TIME/noise term: overlapping surfaces share the same coverage pattern.
uniform float view_window_amount = 0.0;
uniform vec3 view_window_center = vec3(0.0);
uniform vec3 view_window_right = vec3(1.0,0.0,0.0);
uniform vec3 view_window_up = vec3(0.0,1.0,0.0);
uniform vec3 view_window_back = vec3(0.0,0.7,0.7);
uniform vec3 view_window_camera = vec3(0.0);
uniform float view_window_pixel = 0.02;
uniform vec4 view_window_floor_a;
uniform vec4 view_window_floor_b;
uniform vec4 view_window_passage;
varying vec3 view_window_world;

bool view_window_in_rect(vec2 p, vec4 r) {
	return all(greaterThanEqual(p,r.xy)) && all(lessThanEqual(p,r.zw));
}

float view_window_coverage(vec3 p) {
	if (view_window_amount <= 0.0 || p.y < 0.06) { return 0.0; }
	vec3 relative = p-view_window_center;
	vec2 screen = vec2(dot(relative,view_window_right),dot(relative,view_window_up));
	float radius = length(screen/vec2(2.7,2.15));
	float aperture = smoothstep(0.0,1.0,view_window_amount);
	float coverage = 1.0-smoothstep(max(0.0,aperture-0.09),aperture,radius);
	// Reveal actual playable space, not the empty interior under the building.
	vec3 floor_point = p-view_window_back*((p.y-0.04)/view_window_back.y);
	bool floor_visible = view_window_in_rect(floor_point.xz,view_window_floor_a)
		|| view_window_in_rect(floor_point.xz,view_window_floor_b)
		|| view_window_in_rect(floor_point.xz,view_window_passage);
	return floor_visible ? coverage : 0.0;
}

float view_window_pattern(vec3 p) {
	vec3 relative = p-view_window_camera;
	vec2 pixel = vec2(dot(relative,view_window_right),dot(relative,view_window_up))/view_window_pixel;
	vec2 v = mod(floor(pixel),4.0);
	vec2 lo = mod(v,2.0), hi = floor(v/2.0);
	float a = 2.0*lo.x+3.0*lo.y-4.0*lo.x*lo.y;
	float b = 2.0*hi.x+3.0*hi.y-4.0*hi.x*hi.y;
	return (a*4.0+b+0.5)/16.0;
}
