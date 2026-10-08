shader_type spatial;
uniform vec4 tile_color : source_color = vec4(0.46,0.40,0.32,1.0);
uniform float furnace = 1.0;
varying vec3 room_at;
#include "res://shaders/keepers/facility_flagstone.gdshaderinc"
void vertex() { room_at=VERTEX; }
void fragment() {
	vec2 p=room_at.xz;
	vec3 stone; float joint; float relief;
	dressed_floor(p+vec2(furnace*13.7,3.1),vec2(1.12,0.82),tile_color.rgb,stone,joint,relief);
	// Broad soot and ash footprints around the hearth and fuel stock only.
	float hearth=1.0-smoothstep(0.1,1.1,length((p-vec2(-5.4,-2.7))/vec2(4.0,2.9)));
	float bin=1.0-smoothstep(0.2,1.1,length((p-vec2(-7.1,3.7))/vec2(2.9,4.0)));
	float ash=clamp((hearth*0.65+bin*0.5)*(0.7+noise(p*3.1)*0.5),0.0,0.75)*furnace;
	stone=mix(stone,vec3(0.16,0.145,0.115),ash);
	// Water/oil staining radiates from the boiler base, leaving the hazards clear.
	float wet=(1.0-smoothstep(2.4,4.2,length(p-vec2(-0.7,0))))*(1.0-furnace);
	wet*=0.45+noise(p*2.3)*0.45;
	stone=mix(stone,vec3(0.18,0.24,0.19),wet*0.45);
	ALBEDO=mix(tile_color.rgb*0.47,stone,joint);
	NORMAL=stone_normal(relief,NORMAL,VERTEX);
	ROUGHNESS=0.94-wet*0.22;
	AO=0.82+joint*0.18;
}
