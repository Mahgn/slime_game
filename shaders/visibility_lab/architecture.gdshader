shader_type spatial;
render_mode cull_back;

uniform vec4 base_color : source_color = vec4(0.42, 0.43, 0.46, 1.0);
uniform float roughness = 0.9;
uniform vec4 emission_color : source_color = vec4(0.0);
uniform float cutaway_amount = 0.0;
uniform vec3 camera_right = vec3(1.0, 0.0, 0.0);
uniform vec3 camera_up = vec3(0.0, 1.0, 0.0);
uniform float pixels_per_meter = 55.0;
uniform int style = 0;
uniform bool patterned = true;
varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

float coverage(vec2 p) {
    ivec2 q = ivec2(mod(floor(p), 4.0));
    int b[16] = int[](0,8,2,10,12,4,14,6,3,11,1,9,15,7,13,5);
    return (float(b[q.x + q.y * 4]) + 0.5) / 16.0;
}

void fragment() {
    // One world projection for all assembly parts and the shadow pass. No TIME.
    vec2 screen_plane = vec2(dot(world_position,camera_right),dot(world_position,camera_up));
    if (cutaway_amount > coverage(screen_plane * pixels_per_meter)) discard;
    vec3 color = base_color.rgb;
    if (patterned) {
        vec2 uv = abs(world_normal.y) > 0.6 ? world_position.xz : vec2(abs(world_normal.x) > 0.6 ? world_position.z : world_position.x, world_position.y);
        float row = floor(uv.y / 0.38);
        vec2 brick = fract(vec2(uv.x / 1.15 + mod(row,2.0)*0.5,uv.y / 0.38));
        float seam = min(min(brick.x,1.0-brick.x),min(brick.y,1.0-brick.y));
        if (style == 0) color *= mix(0.38,1.0,smoothstep(0.009,0.035,seam));
        else {
            float plank = abs(fract(uv.x / 0.32)-0.5);
            color *= mix(0.38,1.0,1.0-smoothstep(0.46,0.49,plank));
            color *= 0.94 + 0.06*sin(uv.x*73.0 + sin(uv.y*5.0)*0.6);
        }
    }
    ALBEDO = color;
    ROUGHNESS = roughness;
    EMISSION = emission_color.rgb;
}
