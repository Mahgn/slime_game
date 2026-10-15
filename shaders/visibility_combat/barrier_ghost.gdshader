shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_disabled;

uniform float reveal_amount : hint_range(0.0, 1.0) = 0.0;
uniform float focus_amount : hint_range(0.0, 1.0) = 0.0;
uniform bool stone_surface = true;
uniform vec4 base_color : source_color = vec4(0.16, 0.20, 0.19, 1.0);
varying vec3 world_at;
varying vec4 tint;

// Authored facility sediment and vertex tint. Real mesh geometry supplies the
// courses, joints and chamfers; there is no wireframe or diagonal hatch grid.
float hash(vec3 p) { return fract(sin(dot(p,vec3(7.13,3.71,9.27)))*157.31); }
float noise(vec3 p) {
    vec3 c=floor(p); vec3 f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(mix(hash(c),hash(c+vec3(1,0,0)),f.x),mix(hash(c+vec3(0,1,0)),hash(c+vec3(1,1,0)),f.x),f.y),mix(mix(hash(c+vec3(0,0,1)),hash(c+vec3(1,0,1)),f.x),mix(hash(c+vec3(0,1,1)),hash(c+vec3(1,1,1)),f.x),f.y),f.z);
}

void vertex() {
    world_at=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
    tint=COLOR;
}

void fragment() {
    float sediment=noise(world_at*vec3(5.0,15.0,5.0));
    float pits=smoothstep(0.66,0.91,noise(world_at*44.0));
    vec3 stone=tint.rgb*(0.84+sediment*0.20-pits*0.06);
    ALBEDO=stone_surface ? stone : base_color.rgb;
    ROUGHNESS=0.95;
    // Focus reinforces the whole wall softly while leaving combat visible.
    float opacity=stone_surface ? mix(0.075,0.17,focus_amount) : mix(0.12,0.22,focus_amount);
    ALPHA=reveal_amount*opacity;
}
