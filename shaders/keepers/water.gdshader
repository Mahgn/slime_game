shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;

uniform float water_time = 0.0;
varying vec3 world_pos;

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    float a = sin(world_pos.x * 5.0 + world_pos.z * 2.1 + water_time * 0.38);
    float b = sin(world_pos.x * -2.2 + world_pos.z * 6.0 - water_time * 0.29);
    float glint = pow(max(0.0, a * b), 8.0);
    ALBEDO = vec3(0.035, 0.18, 0.19) + vec3(0.012, 0.031, 0.027) * glint;
    ROUGHNESS = 0.38;
    METALLIC = 0.12;
    ALPHA = 0.80;
}
