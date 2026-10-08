shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

void fragment() {
    float radius = length((UV - 0.5) * 2.0);
    float feather = 1.0 - smoothstep(0.25, 1.0, radius);
    ALBEDO = COLOR.rgb;
    ALPHA = COLOR.a * feather;
}
