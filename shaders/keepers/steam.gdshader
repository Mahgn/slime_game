shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float steam_time = 0.0;
uniform float strength = 0.65;
varying float seed;

float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p), f=fract(p);
	f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void vertex() { seed = MODEL_MATRIX[3].x*0.7+MODEL_MATRIX[3].z*0.3; }
void fragment() {
	float height=1.0-UV.y;
	vec2 flow=vec2(UV.x*4.0+seed,height*3.5-steam_time*2.0);
	float billow=noise(flow)+noise(flow*2.1)*0.35;
	float sway=sin(height*7.0-steam_time*3.0+seed)*0.055*height;
	float width=mix(0.19,0.47,height);
	float edge=1.0-smoothstep(width*0.35,width,abs(UV.x-0.5+sway));
	float ends=smoothstep(0.0,0.07,height)*(1.0-smoothstep(0.48,1.0,height));
	ALBEDO=mix(vec3(0.52,0.64,0.62),vec3(0.83,0.89,0.85),billow*0.65);
	ALPHA=edge*ends*smoothstep(0.14,0.9,billow)*strength;
}
