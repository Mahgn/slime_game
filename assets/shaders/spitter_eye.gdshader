shader_type spatial;
render_mode diffuse_burley, shadows_disabled;

uniform float blink_amount = 0.0;
uniform vec2 gaze = vec2(0.0);
uniform vec4 lid_color : source_color = vec4(0.34, 0.22, 0.28, 1.0);
varying vec3 eye_pos;

void vertex() { eye_pos = VERTEX; }

void fragment() {
	vec2 p = eye_pos.xy;
	float arch = sqrt(max(0.0, 1.0 - p.x * p.x));
	float top = arch * (0.84 - blink_amount * 1.68) + p.x * 0.06;
	float bottom = -arch * 0.77 + blink_amount * 0.07;
	float opening = smoothstep(bottom - 0.035, bottom + 0.035, p.y) * (1.0 - smoothstep(top - 0.035, top + 0.035, p.y));
	vec2 iris_p = p - gaze;
	float angle = atan(iris_p.y, iris_p.x);
	float radius = length(iris_p);
	float fibers = sin(angle * 39.0 + sin(angle * 17.0) * 2.3 + radius * 28.0) * 0.5 + 0.5;
	vec3 iris = mix(vec3(0.48, 0.32, 0.13), vec3(0.64, 0.46, 0.21), smoothstep(0.12, 0.66, radius));
	iris *= 0.95 + fibers * 0.10;
	iris *= 1.0 - smoothstep(0.72, 0.95, radius) * 0.65;
	float pupil_shape = pow(iris_p.x / 0.57, 2.0) + pow(iris_p.y / 0.28, 2.0);
	float pupil = 1.0 - smoothstep(0.80, 1.15, pupil_shape);
	iris = mix(iris, vec3(0.028, 0.024, 0.021), pupil);
	float reflection = exp(-pow((p.x + 0.22) * 9.0, 2.0) - pow((p.y - 0.26) * 13.0, 2.0));
	iris = mix(iris, vec3(0.76, 0.81, 0.72), reflection * 0.42);
	float rim = smoothstep(0.0, 0.11, abs(p.y - top)) * smoothstep(0.0, 0.07, abs(p.y - bottom));
	vec3 lid = lid_color.rgb * mix(0.70, 1.06, p.y * 0.5 + 0.5);
	ALBEDO = mix(lid, iris * mix(0.60, 1.0, rim), opening);
	ROUGHNESS = mix(0.90, 0.31, opening);
	SPECULAR = opening * 0.28;
}
