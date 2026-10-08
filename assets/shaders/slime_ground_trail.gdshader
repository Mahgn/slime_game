shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform float upper_floor_fade : hint_range(0.0, 1.0) = 0.0;
uniform float upper_floor_min_y = 0.20;
varying float world_height;

void vertex() {
	world_height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * (1.0 - upper_floor_fade * step(upper_floor_min_y, world_height));
}
