shader_type spatial;
uniform vec4 tile_color : source_color = vec4(0.46,0.40,0.32,1.0);
uniform int room_style = 0;
uniform vec2 half_extent = vec2(8.0);
varying vec3 room_at;
#include "res://shaders/keepers/facility_flagstone.gdshaderinc"
void vertex() { room_at=VERTEX; }
void fragment() {
	vec2 p=room_at.xz;
	vec2 slab_size=vec2(1.24,0.87);
	vec3 tone=tile_color.rgb;
	if (room_style==0) { slab_size=vec2(0.72,0.48); tone=vec3(0.43,0.365,0.28); }
	if (room_style==1 || room_style==6) { slab_size=vec2(1.35,1.06); tone=vec3(0.34,0.405,0.355); }
	if (room_style==2) { slab_size=vec2(1.10,0.84); tone=vec3(0.38,0.40,0.34); }
	if (room_style==3 || room_style==7) { tone=vec3(0.43,0.405,0.31); }
	if (room_style==4) { slab_size=vec2(1.42,1.03); tone=vec3(0.38,0.42,0.33); }
	if (room_style==5) { slab_size=vec2(1.80,1.32); tone=vec3(0.45,0.465,0.385); }
	vec3 stone; float joint; float relief;
	dressed_floor(p+vec2(float(room_style)*7.13,3.1),slab_size,tone,stone,joint,relief);
	float perimeter=1.0-smoothstep(0.25,1.8,min(half_extent.x-abs(p.x),half_extent.y-abs(p.y)));
	float wet=0.0;
	if (room_style==1) { wet=(1.0-smoothstep(0.15,1.2,length(p/vec2(3.8,4.0)))); }
	if (room_style==2) {
		wet=1.0-smoothstep(0.25,1.0,length(vec2(abs(p.x)-1.8,p.y+2.1)/vec2(1.8,3.0)));
	}
	if (room_style==4) { wet=1.0-smoothstep(0.8,2.0,abs(p.y)); }
	if (room_style==6) { wet=1.0-smoothstep(0.1,2.0,p.x+3.3); }
	wet*=0.42+noise(p*2.2)*0.58;
	stone=mix(stone,vec3(0.19,0.255,0.21),wet*0.48);
	if (room_style==1 || room_style==4 || room_style==6) {
		float moss=perimeter*smoothstep(0.36,0.77,noise(p*1.7));
		stone=mix(stone,vec3(0.26,0.34,0.21),moss*0.52);
	} else { stone*=1.0-perimeter*0.13; }
	if (room_style==0) {
		float track=(1.0-smoothstep(0.13,0.48,abs(abs(p.x)-1.4)))*(1.0-smoothstep(3.6,4.3,abs(p.y)));
		stone=mix(stone,vec3(0.38,0.32,0.23),track*0.35);
	}
	if (room_style==5) {
		// Stone inlay follows the approach and frames the raised sluice apron.
		float approach=(1.0-smoothstep(0.045,0.085,abs(abs(p.x)-1.65)))*smoothstep(-1.0,0.0,p.y);
		float apron=1.0-smoothstep(0.045,0.085,abs(max(abs(p.x)/5.3,abs(p.y+5.7)/2.6)-1.0)*2.6);
		float inlay=max(approach,apron)*(0.70+noise(p*7.0)*0.30);
		stone=mix(stone,vec3(0.27,0.30,0.24),inlay*0.62);
	}
	ALBEDO=mix(tone*0.47,stone,joint);
	NORMAL=stone_normal(relief,NORMAL,VERTEX);
	ROUGHNESS=0.94-wet*0.23;
	AO=0.84+joint*0.16;
}
