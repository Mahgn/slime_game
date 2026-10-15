// Screen-anchored, time-independent coverage. No alpha sorting and no random
// value changing between frames; only the room's continuous amount changes.
uniform float wall_reveal : hint_range(0.0, 1.0) = 0.0;
uniform float wall_plinth_y = 0.18;
varying vec3 room_wall_world_position;

float room_wall_coverage(vec2 pixel) {
	vec2 p = floor(pixel);
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}
