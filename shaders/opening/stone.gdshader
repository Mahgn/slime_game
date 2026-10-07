shader_type spatial;
render_mode cull_back;
uniform vec4 stone_color : source_color = vec4(0.48, 0.43, 0.34, 1.0);
varying vec3 stone_position;
varying vec3 stone_normal;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() {
    stone_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    stone_normal = MODEL_NORMAL_MATRIX * NORMAL;
}
void fragment() {
    vec3 n = abs(normalize(stone_normal));
    vec2 p = n.y > 0.6 ? stone_position.xz : (n.x > n.z ? stone_position.zy : stone_position.xy);
    vec2 grid = p / vec2(0.78, 0.52);
    grid.x += mod(floor(grid.y), 2.0) * 0.5;
    vec2 cell = floor(grid);
    vec2 edge = min(fract(grid), 1.0 - fract(grid));
    float mortar = smoothstep(0.010, 0.045, min(edge.x, edge.y));
    float grain = hash(floor(p * 36.0));
    float variation = 0.90 + hash(cell) * 0.16 + (grain - 0.5) * 0.035;
    ALBEDO = stone_color.rgb * variation * mix(0.59, 1.0, mortar);
    ROUGHNESS = 0.94;
}
