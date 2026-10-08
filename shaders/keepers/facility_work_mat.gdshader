shader_type spatial;
uniform vec4 cloth_color : source_color = vec4(0.22,0.25,0.19,1.0);
uniform vec2 mat_size = vec2(4.0,2.0);
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 c=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(c),hash(c+vec2(1,0)),f.x),mix(hash(c+vec2(0,1)),hash(c+vec2(1,1)),f.x),f.y);
}
void fragment() {
	vec2 p=UV*mat_size;
	vec2 edge=min(UV,1.0-UV)*mat_size;
	float distance_to_edge=min(edge.x,edge.y);
	float hem=1.0-smoothstep(0.035,0.055,distance_to_edge);
	float stripe=smoothstep(0.12,0.13,distance_to_edge)*(1.0-smoothstep(0.17,0.18,distance_to_edge));
	float weave=sin(p.x*260.0)*sin(p.y*260.0)*0.025;
	float wear=noise(p*2.5)*0.12+noise(p*15.0)*0.04;
	vec3 base=cloth_color.rgb*(0.93+wear+weave);
	ALBEDO=mix(base,base*0.55,hem);
	ALBEDO=mix(ALBEDO,vec3(0.40,0.37,0.26),stripe*0.60);
	ROUGHNESS=1.0;
}
