shader_type spatial;
varying vec3 wood_at;
varying vec3 wood_normal;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 c=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(c),hash(c+vec2(1,0)),f.x),mix(hash(c+vec2(0,1)),hash(c+vec2(1,1)),f.x),f.y);
}
void vertex() { wood_at=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; wood_normal=MODEL_NORMAL_MATRIX*NORMAL; }
void fragment() {
	vec3 n=abs(wood_normal);
	vec2 p=wood_at.xy;
	if(n.x>n.z && n.x>n.y) p=wood_at.zy;
	if(n.y>n.x && n.y>n.z) p=wood_at.xz;
	vec2 cell=floor(p/vec2(0.65,1.7));
	vec2 knot_at=(cell+vec2(0.2+hash(cell)*0.6,0.3+hash(cell+4.1)*0.4))*vec2(0.65,1.7);
	vec2 knot=(p-knot_at)*vec2(1.0,0.27);
	float warp=noise(p*vec2(3.0,0.65))*0.22+sin(p.y*2.3)*0.028;
	float knot_pull=exp(-dot(knot,knot)*95.0)*step(0.55,hash(cell+8.0));
	float rings=sin((p.x+warp+knot_pull*0.15)*125.0);
	float fibers=smoothstep(0.58,0.85,noise(vec2(p.x*110.0+warp*60.0,p.y*2.5)));
	float wear=noise(p*vec2(4.0,0.6));
	vec3 timber=COLOR.rgb*(0.86+wear*0.18+rings*0.035-fibers*0.07-knot_pull*0.20);
	ALBEDO=timber;
	ROUGHNESS=0.87+fibers*0.07;
}
