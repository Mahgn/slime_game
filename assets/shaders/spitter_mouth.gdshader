shader_type spatial;
render_mode diffuse_burley, specular_disabled, shadows_disabled;

uniform vec4 lip_color : source_color = vec4(0.30, 0.21, 0.25, 1.0);
uniform float open_amount = 0.0;
uniform float cavity = 0.0;

void vertex() {
	// Ring coordinates move the lip centerline; the tube keeps its thickness.
	vec2 radial = COLOR.rg * 2.0 - 1.0;
	VERTEX.y += radial.x * 0.073 * open_amount;
	VERTEX.x -= radial.y * 0.028 * open_amount;
}

void fragment() {
	ALBEDO = mix(lip_color.rgb, vec3(0.018, 0.012, 0.019), cavity);
	ROUGHNESS = 0.86;
	SPECULAR = 0.0;
}
