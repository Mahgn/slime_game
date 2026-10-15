shader_type spatial;
render_mode diffuse_burley;

uniform vec4 base_color : source_color = vec4(1.0);
uniform bool use_vertex_color = true;
uniform float surface_roughness = 0.9;
uniform float surface_metallic = 0.0;
uniform vec4 emitted_color : source_color = vec4(0.0);

void fragment() {
	ALBEDO = base_color.rgb * (use_vertex_color ? COLOR.rgb : vec3(1.0));
	ROUGHNESS = surface_roughness;
	METALLIC = surface_metallic;
	EMISSION = emitted_color.rgb;
}
