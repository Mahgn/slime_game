shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 slime_color : source_color = vec4(0.20, 0.86, 0.72, 1.0);
uniform float cubeness : hint_range(0.0, 1.0) = 0.72;
uniform float wobble : hint_range(0.0, 0.25) = 0.05;
uniform float gloss : hint_range(0.0, 1.0) = 0.72;

void vertex() {
    vec3 unit = normalize(VERTEX);
    vec3 cube = sign(unit) * pow(abs(unit), vec3(0.48));
    VERTEX = mix(unit, cube, cubeness) * 0.78;
    VERTEX.y += sin(TIME * 2.8 + unit.x * 4.0 + unit.z * 2.5) * wobble;
    NORMAL = normalize(mix(unit, sign(unit) * pow(abs(unit), vec3(1.5)), cubeness * 0.45));
}

void fragment() {
    ALBEDO = slime_color.rgb;
    ROUGHNESS = mix(0.86, 0.08, gloss);
    SPECULAR = mix(0.35, 0.9, gloss);
    float rim = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 3.0);
    EMISSION = slime_color.rgb * (0.04 + rim * 0.22);
}
