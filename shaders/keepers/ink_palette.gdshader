shader_type canvas_item;
render_mode unshaded;
uniform sampler2D scene_color : hint_screen_texture, repeat_disable, filter_nearest;
uniform float amount = 1.0;
uniform float dark_ink = 0.0;
uniform float saturation = 1.18;
uniform float poster_amount = 0.0;
uniform float paper_amount = 0.0;

void fragment() {
	vec3 original = textureLod(scene_color, SCREEN_UV, 0.0).rgb;
	float y = dot(original, vec3(0.2126, 0.7152, 0.0722));
	float chroma = max(original.r, max(original.g, original.b)) - min(original.r, min(original.g, original.b));
	// Broad violet shadows and warm paper light, retaining saturated gameplay FX.
	float shadow = 1.0 - smoothstep(0.10, 0.52, y);
	float paper = smoothstep(0.30, 0.80, y);
	vec3 color = mix(vec3(y), original, saturation);
	color = mix(color, y * vec3(0.82, 0.78, 1.30), shadow * mix(0.25, 0.40, dark_ink) * (1.0 - smoothstep(0.12, 0.38, chroma)));
	color *= mix(vec3(1.0), vec3(1.12, 1.025, 0.91), paper * 0.65);
	color = mix(color * 1.035 + vec3(0.005, 0.004, 0.009), (color - 0.20) * 1.07 + 0.20, dark_ink);
	if (poster_amount > 0.0) {
		// Quantize luminance, not RGB independently: preserve the hue of slime/FX.
		float luminance = max(dot(color, vec3(0.2126, 0.7152, 0.0722)), 0.001);
		float scaled = luminance * 6.0;
		float band = (floor(scaled) + smoothstep(0.44, 0.56, fract(scaled))) / 6.0;
		// Keep deep masonry shadows continuous: quantizing near-black noise
		// otherwise turns the crown into conspicuous bright islands.
		float midtones = smoothstep(0.12, 0.26, luminance) * (1.0 - smoothstep(0.66, 0.94, luminance));
		color *= mix(1.0, max(band, 0.025) / luminance, poster_amount * midtones);
	}
	float paper_y = dot(color, vec3(0.2126, 0.7152, 0.0722));
	color = mix(color, paper_y * vec3(1.14, 1.045, 0.89), paper_amount * (1.0 - smoothstep(0.20, 0.48, chroma)));
	COLOR = vec4(mix(original, clamp(color, vec3(0.0), vec3(1.0)), amount), 1.0);
}
