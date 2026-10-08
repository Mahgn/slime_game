shader_type spatial;
render_mode cull_back;

void fragment() {
    float grain = sin(UV.x * 96.0 + sin(UV.y * 3.9) * 1.8);
    float fine_grain = sin(UV.x * 233.0 + sin(UV.y * 6.5));
    ALBEDO = COLOR.rgb * (0.96 + grain * 0.030 + fine_grain * 0.015);
    ROUGHNESS = 0.90;
}
