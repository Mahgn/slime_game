shader_type spatial;
uniform vec4 oxidation : source_color = vec4(0.20,0.31,0.25,1.0);
uniform float metalness = 0.68;
varying vec3 world_at;
varying vec3 object_at;
float hash(vec3 p) { return fract(sin(dot(p,vec3(127.1,311.7,78.3)))*43758.5453); }
float noise(vec3 p) {
	vec3 c=floor(p); vec3 f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(mix(hash(c),hash(c+vec3(1,0,0)),f.x),mix(hash(c+vec3(0,1,0)),hash(c+vec3(1,1,0)),f.x),f.y),mix(mix(hash(c+vec3(0,0,1)),hash(c+vec3(1,0,1)),f.x),mix(hash(c+vec3(0,1,1)),hash(c+vec3(1,1,1)),f.x),f.y),f.z);
}
void vertex() { world_at=(MODEL_MATRIX*vec4(VERTEX,1)).xyz; object_at=VERTEX; }
void fragment() {
	float clouds=noise(world_at*1.8)*0.65+noise(world_at*7.4)*0.35;
	float streak=noise(world_at*vec3(13.0,0.8,13.0));
	float patina=smoothstep(0.62,0.87,clouds+streak*0.15);
	float hammer=noise(world_at*48.0);
	vec3 alloy=COLOR.rgb*(0.90+clouds*0.13+hammer*0.035);
	ALBEDO=mix(alloy,oxidation.rgb,patina*0.32);
	METALLIC=mix(metalness,0.18,patina);
	ROUGHNESS=clamp(0.48+patina*0.3+hammer*0.04,0.0,1.0);
}
