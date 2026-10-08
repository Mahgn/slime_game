shader_type spatial;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
void fragment() {
	vec2 thread=UV*vec2(210.0,92.0);
	float filter_strength=1.0-smoothstep(0.5,1.8,max(fwidth(thread.x),fwidth(thread.y)));
	float weave=sin(thread.x*6.283)*sin(thread.y*6.283)*filter_strength;
	float slub=hash(floor(UV*vec2(83.0,49.0)));
	float seam=1.0-smoothstep(0.008,0.025,abs(UV.x-0.065));
	float stain=(1.0-smoothstep(0.0,0.2,UV.y))*(0.08+slub*0.06);
	ALBEDO=COLOR.rgb*(0.91+slub*0.08+weave*0.055-stain-seam*0.06);
	ROUGHNESS=0.98;
}
