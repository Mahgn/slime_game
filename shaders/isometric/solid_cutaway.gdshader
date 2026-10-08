shader_type spatial;
render_mode cull_back;
#include "res://shaders/isometric/cutaway.gdshaderinc"

uniform vec4 base_color : source_color = vec4(1.0);
uniform float roughness = 0.9;
uniform vec4 emission_color : source_color = vec4(0.0);
void fragment() {
    if (cutaway_dither(FRAGCOORD.xy) < cutaway_amount) {
        discard;
    }
    ALBEDO = base_color.rgb;
    ROUGHNESS = roughness;
    EMISSION = emission_color.rgb;
}
