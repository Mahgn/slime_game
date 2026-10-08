shader_type spatial;
varying vec3 world_at;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 c=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(c),hash(c+vec2(1,0)),f.x),mix(hash(c+vec2(0,1)),hash(c+vec2(1,1)),f.x),f.y);
}
void vertex() {
	world_at=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}
void fragment() {
	vec2 p=world_at.xz;
	float broad=noise(p*0.58);
	vec2 warped=p+vec2(noise(p*0.72),noise(p*0.66+9.2))*0.35;
	float strata=noise(warped*vec2(6.0,1.7));
	float split=smoothstep(0.23,0.35,strata);
	float facets=noise(warped*4.7);
	float grain=noise(p*27.0);
	vec3 rock=mix(vec3(0.135,0.155,0.138),vec3(0.235,0.24,0.195),broad);
	ALBEDO=rock*(0.70+facets*0.32+grain*0.16)*(0.86+split*0.14);
	ROUGHNESS=1.0;
}
