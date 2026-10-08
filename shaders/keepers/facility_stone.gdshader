shader_type spatial;
varying vec3 world_at;
varying vec4 tint;
float hash(vec3 p) { return fract(sin(dot(p,vec3(7.13,3.71,9.27)))*157.31); }
float noise(vec3 p) {
	vec3 c=floor(p); vec3 f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(mix(hash(c),hash(c+vec3(1,0,0)),f.x),mix(hash(c+vec3(0,1,0)),hash(c+vec3(1,1,0)),f.x),f.y),mix(mix(hash(c+vec3(0,0,1)),hash(c+vec3(1,0,1)),f.x),mix(hash(c+vec3(0,1,1)),hash(c+vec3(1,1,1)),f.x),f.y),f.z);
}
void vertex() { world_at=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; tint=COLOR; }
void fragment() {
	float sediment=noise(world_at*vec3(5.0,15.0,5.0));
	float pits=smoothstep(0.66,0.91,noise(world_at*44.0));
	float salt=smoothstep(0.57,0.78,noise(world_at*vec3(3.3,6.0,3.3)));
	float run=noise(world_at*vec3(8.0,0.45,8.0));
	float damp=(1.0-smoothstep(0.05,1.0+run*0.75,world_at.y))*(0.45+run*0.55);
	float crack=abs(UV.y-(0.06+sin(UV.x*9.0+tint.a*19.0)*0.027+UV.x*(tint.a-0.5)*0.50));
	float fissure=(1.0-smoothstep(0.002,0.009,crack))*step(0.82,tint.a)*step(tint.a,0.99);
	vec3 color=tint.rgb*(0.84+sediment*0.20-pits*0.06-fissure*0.28);
	color=mix(color,vec3(0.22,0.265,0.20),damp*0.26);
	color=mix(color,color*1.22,salt*0.18*(1.0-damp));
	ALBEDO=color;
	float relief=sediment*0.007-pits*0.0004-fissure*0.002;
	vec3 dx=dFdx(VERTEX),dy=dFdy(VERTEX);
	vec3 rx=cross(dy,NORMAL),ry=cross(NORMAL,dx);
	NORMAL=normalize(NORMAL-(dFdx(relief)*rx+dFdy(relief)*ry)/(dot(dx,rx)+0.0000001));
	ROUGHNESS=0.95-damp*0.10;
}
