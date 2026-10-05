shader_type spatial;
render_mode diffuse_burley, specular_disabled, shadows_disabled;

uniform vec4 skin_color : source_color = vec4(0.34, 0.22, 0.28, 1.0);
uniform vec4 belly_color : source_color = vec4(0.58, 0.48, 0.35, 1.0);
uniform float belly_amount = 0.0;
uniform vec3 skin_origin = vec3(0.0);
uniform float charge_amount = 0.0;
uniform float hit_amount = 0.0;
uniform float mouth_open = 0.0;
uniform float breath_amount = 0.0;
uniform float throat_amount = 0.0;
uniform mat4 head_pose = mat4(1.0);
uniform vec3 head_pivot = vec3(0.0, -0.035, -0.17);
uniform bool limb_enabled = false;
uniform vec3 limb_rest = vec3(0.0, -0.30, -0.10);
uniform vec3 limb_target = vec3(0.0, -0.30, -0.10);
uniform vec3 limb_bend = vec3(0.0);
varying vec3 local_pos;
varying float skin_ao;

float hash_skin(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float skin_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash_skin(cell), hash_skin(cell + vec3(1, 0, 0)), f.x),
		mix(hash_skin(cell + vec3(0, 1, 0)), hash_skin(cell + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash_skin(cell + vec3(0, 0, 1)), hash_skin(cell + vec3(1, 0, 1)), f.x),
		mix(hash_skin(cell + vec3(0, 1, 1)), hash_skin(cell + vec3(1, 1, 1)), f.x), f.y), f.z);
}

vec3 deform(vec3 p) {
	if (limb_enabled) {
		float t = clamp(p.y / limb_rest.y, 0.0, 1.0);
		return p + (limb_target - limb_rest) * t + sin(t * 3.141593) * limb_bend;
	}
	if (belly_amount < 0.5) { return p; }
	vec3 original = p;
	float cheek = exp(-pow((abs(p.x) - 0.37) * 6.8, 2.0) - pow((p.y + 0.055) * 6.2, 2.0));
	cheek *= 1.0 - smoothstep(-0.26, 0.015, p.z);
	p += vec3(sign(p.x) * 0.092, -0.022, -0.050) * cheek * charge_amount;
	float jaw = exp(-pow(p.x * 4.3, 2.0) - pow((p.y + 0.075) * 8.0, 2.0));
	jaw *= 1.0 - smoothstep(-0.39, -0.23, p.z);
	p.x *= 1.0 - jaw * mouth_open * 0.30;
	p.y += sign(p.y + 0.075) * jaw * mouth_open * 0.068;
	float throat = exp(-pow(p.x * 4.5, 2.0) - pow((p.y + 0.27) * 7.0, 2.0));
	throat *= 1.0 - smoothstep(-0.28, 0.08, p.z);
	p.z -= throat * (breath_amount * 0.012 + throat_amount * 0.035);
	p.y -= throat * throat_amount * 0.009;
	float head_weight = smoothstep(-0.35, -0.15, original.y) * (1.0 - smoothstep(-0.22, 0.22, original.z));
	vec3 head_point = (head_pose * vec4(p - head_pivot, 1.0)).xyz;
	return mix(p, head_point, head_weight);
}

void vertex() {
	local_pos = VERTEX + skin_origin;
	skin_ao = COLOR.r;
	// Recompute the bent surface normal too, so highlights/shading follow tissue.
	vec3 n = normalize(NORMAL);
	vec3 tangent = normalize(cross(n, abs(n.y) < 0.9 ? vec3(0, 1, 0) : vec3(1, 0, 0)));
	vec3 bitangent = cross(n, tangent);
	vec3 p = deform(VERTEX);
	NORMAL = normalize(cross(deform(VERTEX + tangent * 0.002) - p,
		deform(VERTEX + bitangent * 0.002) - p));
	VERTEX = p;
}

void fragment() {
	float crown = smoothstep(-0.48, 0.34, local_pos.y);
	vec3 skin = skin_color.rgb * mix(vec3(0.79, 0.79, 0.85), vec3(1.12, 1.04, 0.98), crown);
	float broad = skin_noise(local_pos * 5.0 + vec3(4.2, 1.3, 7.8));
	float fine = skin_noise(local_pos * 92.0);
	float freckles = smoothstep(0.67, 0.85, skin_noise(local_pos * 38.0));
	float belly = (1.0 - smoothstep(-0.36, -0.17, local_pos.z));
	belly *= 1.0 - smoothstep(-0.10, 0.10, local_pos.y);
	belly *= 1.0 - smoothstep(0.28, 0.49, abs(local_pos.x));
	belly *= belly_amount;
	skin *= mix(0.93, 1.08, broad);
	skin = mix(skin, belly_color.rgb * mix(0.88, 1.03, broad), belly);
	skin *= 1.0 - freckles * (1.0 - belly * 0.8) * 0.14;
	float mouth_curve = pow(local_pos.x / 0.251, 2.0);
	float inside_mouth = smoothstep(-0.570 + mouth_curve * 0.114, -0.545 + mouth_curve * 0.114, local_pos.z);
	inside_mouth *= 1.0 - smoothstep(0.020, 0.047, abs(local_pos.y + 0.075 - mouth_curve * 0.024));
	inside_mouth *= 1.0 - smoothstep(0.23, 0.275, abs(local_pos.x));
	skin = mix(skin, vec3(0.022, 0.012, 0.020), inside_mouth * belly_amount);
	// Fine grain supplements sculpted folds, without a stony camouflage pattern.
	float height = fine * 0.00042 + freckles * 0.00035;
	vec3 dx = dFdx(VERTEX);
	vec3 dy = dFdy(VERTEX);
	vec3 tx = cross(dy, NORMAL);
	vec3 ty = cross(NORMAL, dx);
	float det = dot(dx, tx);
	NORMAL = normalize(max(abs(det), 0.000000000001) * NORMAL - sign(det) * (dFdx(height) * tx + dFdy(height) * ty));
	ALBEDO = mix(skin * mix(0.70, 1.0, skin_ao), vec3(0.94, 0.75, 0.54), hit_amount * 0.65);
	AO = skin_ao;
	ROUGHNESS = 0.90;
	SPECULAR = 0.0;
}
