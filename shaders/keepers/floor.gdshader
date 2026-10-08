shader_type spatial;
render_mode cull_back;

uniform vec4 tile_color : source_color = vec4(0.49, 0.48, 0.40, 1.0);
varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = MODEL_NORMAL_MATRIX * NORMAL;
}

void fragment() {
    vec2 p = world_pos.xz;
    vec2 grid = p / vec2(0.90, 0.60);
    grid.x += mod(floor(grid.y), 2.0) * 0.5;
    vec2 cell = floor(grid);
    vec2 tile_uv = fract(grid);
    vec2 edge = min(tile_uv, 1.0 - tile_uv);
    float joint = smoothstep(0.005, 0.023, min(edge.x, edge.y));
    float tile_variation = 0.94 + hash(cell) * 0.14;
    float grain = hash(floor(p * 75.0)) * 0.015;
    vec3 stone = tile_color.rgb * (tile_variation + grain);
    float stain = sin(p.x * 0.57 + sin(p.y * 0.83)) * cos(p.y * 0.36);
    stone *= 0.96 + stain * 0.035;
    // Occasional hairline fractures stay much quieter than the tile joints.
    float crack_y = 0.23 + tile_uv.x * 0.48 + hash(cell + 8.2) * 0.18;
    float crack = (1.0 - smoothstep(0.003, 0.011, abs(tile_uv.y - crack_y)));
    crack *= smoothstep(0.08, 0.20, tile_uv.x) * (1.0 - smoothstep(0.68, 0.88, tile_uv.x));
    crack *= step(0.90, hash(cell + 11.3));
    stone *= 1.0 - crack * 0.12;
    ALBEDO = mix(tile_color.rgb * 0.66, stone, joint);
    if (abs(normalize(world_normal).y) < 0.7) {
        ALBEDO *= 0.61;
    }
    ROUGHNESS = 0.91;
}
