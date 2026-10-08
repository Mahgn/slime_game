shader_type spatial;
render_mode unshaded, fog_disabled, depth_test_disabled, depth_draw_never, cull_back, shadows_disabled;

uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform float silhouette_opacity = 0.72;
uniform vec4 silhouette_color : source_color = vec4(0.31, 0.64, 0.55, 1.0);
uniform float gel_time = 0.0;
uniform float gel_energy = 0.0;
uniform vec2 gel_motion = vec2(0.0);
uniform float crawl_phase = 0.0;
uniform float crawl_amount = 0.0;

void vertex() {
    // Match the accepted v5 body's vertex deformation, including its sole.
    float sole = 1.0 - smoothstep(-0.28, -0.04, VERTEX.y);
    float rear = smoothstep(0.02, 0.34, VERTEX.z);
    float front = smoothstep(0.02, 0.34, -VERTEX.z);
    float rear_stroke = max(sin(crawl_phase), 0.0);
    float front_stroke = max(-sin(crawl_phase), 0.0);
    VERTEX.y += sole * crawl_amount * (0.120 * rear * rear_stroke + 0.070 * front * front_stroke);
    VERTEX.z += sole * crawl_amount * (0.120 * rear * rear_stroke - 0.070 * front * front_stroke);
    VERTEX.x += sign(VERTEX.x) * sole * crawl_amount * 0.070 * rear * rear_stroke * smoothstep(0.14, 0.34, abs(VERTEX.x));
    float crown = smoothstep(-0.27, 0.35, VERTEX.y);
    float wave_x = sin(gel_time * 8.2 + VERTEX.y * 8.0 + VERTEX.z * 3.5);
    float wave_z = cos(gel_time * 7.4 + VERTEX.y * 6.0 + VERTEX.x * 4.0);
    VERTEX.x += crown * (gel_motion.x * 0.075 + wave_x * gel_energy * 0.052);
    VERTEX.z += crown * (gel_motion.y * 0.075 + wave_z * gel_energy * 0.043);
    VERTEX.y += sin(gel_time * 9.0 + VERTEX.x * 5.0 + VERTEX.z * 3.0) * gel_energy * 0.023 * crown;
}

void fragment() {
    float depth = texture(scene_depth, SCREEN_UV).r;
    #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
    #else
    vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
    #endif
    vec4 surface = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
    float surface_depth = -surface.z / surface.w;
    // Uncovered body pixels keep their original material. A small bias avoids
    // self-highlighting from the protruding eyes and the animated surface.
    if (-VERTEX.z - surface_depth < 0.12) {
        discard;
    }
    ALBEDO = silhouette_color.rgb;
    ALPHA = silhouette_opacity;
}
