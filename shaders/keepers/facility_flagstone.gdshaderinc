// Metric flagstone bond: variable courses and occasional large paired stones.
float hash(vec2 p) { return fract(sin(dot(p,vec2(7.13,3.71)))*157.31); }
float noise(vec2 p) {
	vec2 c=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(c),hash(c+vec2(1,0)),f.x),mix(hash(c+vec2(0,1)),hash(c+vec2(1,1)),f.x),f.y);
}
vec3 stone_normal(float height,vec3 normal,vec3 position) {
	vec3 dx=dFdx(position),dy=dFdy(position);
	vec3 rx=cross(dy,normal),ry=cross(normal,dx);
	return normalize(normal-(dFdx(height)*rx+dFdy(height)*ry)/(dot(dx,rx)+0.0000001));
}
void dressed_floor(vec2 p,vec2 scale,vec3 tone,out vec3 stone,out float joint,out float relief) {
	float band=floor(p.y/(scale.y*2.0));
	float split_y=scale.y*(0.78+hash(vec2(band,91.0))*0.44);
	float py=mod(p.y,scale.y*2.0);
	float upper=step(split_y,py);
	float row=band*2.0+upper;
	float tile_h=mix(split_y,2.0*scale.y-split_y,upper);
	float v=(py-upper*split_y)/tile_h;
	float px=(p.x+hash(vec2(row,17))*scale.x)/(2.0*scale.x);
	float group=floor(px);
	float split_x=0.34+hash(vec2(group,row))*0.32;
	if(hash(vec2(group,row)+3.91)>0.83) split_x=1.0;
	float right=step(split_x,fract(px));
	float tile_w=mix(split_x,1.0-split_x,right)*scale.x*2.0;
	float u=(fract(px)-right*split_x)*scale.x*2.0/tile_w;
	vec2 cell=vec2(group*2.0+right,row);
	vec2 uv=vec2(u,v);
	vec2 edge=min(uv,1.0-uv)*vec2(tile_w,tile_h);
	float distance_to_edge=min(edge.x,edge.y);
	float chips=smoothstep(0.62,0.84,noise(p*8.0+cell))*0.039+noise(p*27.0)*0.005;
	joint=smoothstep(0.006,0.020,distance_to_edge-chips);
	float bevel=(1.0-smoothstep(0.018,0.065,distance_to_edge-chips))*joint;
	float variation=hash(cell+5.7);
	float sediment=noise(p*4.5+cell*2.0)*0.65+noise(p*17.0)*0.35;
	stone=tone*(0.77+variation*0.30+sediment*0.10);
	stone=mix(stone,stone*vec3(1.07,1.015,0.91),hash(cell+2.1)*0.55);
	stone*=1.0+bevel*0.16;
	float pits=smoothstep(0.73,0.94,noise(p*75.0));
	stone*=1.0-pits*0.05;
	float crack=abs(uv.y-(0.17+hash(cell+8.0)*0.46+uv.x*(hash(cell+4.2)-0.5)*0.9+sin(uv.x*17.0+variation*8.0)*0.028));
	float fissure=(1.0-smoothstep(0.0018,0.0065,crack))*step(0.83,hash(cell+14.0));
	fissure*=smoothstep(0.08,0.25,uv.x)*(1.0-smoothstep(0.80,0.97,uv.x));
	stone*=1.0-fissure*0.26;
	relief=joint*0.013+sediment*0.007-pits*0.0003-fissure*0.002;
}
