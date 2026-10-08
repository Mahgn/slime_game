shader_type spatial;
render_mode diffuse_burley;

varying vec3 world_point;
varying float top_face;
varying vec4 stone_tint;
// Avoid large sine hash magnitudes: on the tested Compatibility renderer they
// produced visible triangle-shaped discontinuities in the broad stone surface.
float hash(vec2 p) {
	vec3 q=fract(vec3(p.xyx)*0.1031);
	q+=dot(q,q.yzx+33.33);
	return fract((q.x+q.y)*q.z);
}
float noise(vec2 p) {
	vec2 a=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
	return mix(mix(hash(a),hash(a+vec2(1,0)),f.x),mix(hash(a+vec2(0,1)),hash(a+vec2(1,1)),f.x),f.y);
}
void vertex() {
	world_point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	top_face=abs(NORMAL.y);
	stone_tint=COLOR;
}
void fragment() {
	vec2 p=world_point.xz;
	// Continuous weathered stone, not another tiled floor. Architectural lines
	// belong only to the narrow cornice following the real building contour.
	vec2 warp=vec2(noise(p*0.61),noise(p*0.61+vec2(31.7,19.3)))-0.5;
	float age=noise(p*0.39+warp*0.7);
	float sediment=noise(p*vec2(2.2,5.1)+warp*2.6);
	float grain=noise(p*31.0+warp*4.0);
	float rim=1.0-step(0.251,stone_tint.a);
	vec2 coping_edge=min(fract(p/1.5),1.0-fract(p/1.5))*1.5;
	float coping_joint=1.0-smoothstep(0.006,0.015,min(coping_edge.x,coping_edge.y));
	float seam=coping_joint*rim*top_face;
	vec3 color=stone_tint.rgb*(0.81+age*0.28+sediment*0.13+grain*0.035-seam*0.40);
	float lichen=smoothstep(0.65,0.84,age)*top_face;
	color=mix(color,color*vec3(1.12,1.13,0.92),lichen*0.25);
	ALBEDO=color;
	float relief=(sediment*0.004+grain*0.0007-seam*0.002)*top_face;
	vec3 dx=dFdx(VERTEX),dy=dFdy(VERTEX);
	vec3 rx=cross(dy,NORMAL),ry=cross(NORMAL,dx);
	NORMAL=normalize(NORMAL-(dFdx(relief)*rx+dFdy(relief)*ry)/(dot(dx,rx)+0.0000001));
	ROUGHNESS=0.95;
}
