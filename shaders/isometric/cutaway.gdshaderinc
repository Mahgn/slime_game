// Whole authored sections fade together only during a floor transition.
// At rest every surface is fully solid or fully absent.
uniform float cutaway_amount : hint_range(0.0, 1.0) = 0.0;

float cutaway_dither(vec2 pixel) {
    vec2 p = mod(floor(pixel), 4.0);
    vec2 lo = mod(p, 2.0);
    vec2 hi = floor(p / 2.0);
    float a = 2.0 * lo.x + 3.0 * lo.y - 4.0 * lo.x * lo.y;
    float b = 2.0 * hi.x + 3.0 * hi.y - 4.0 * hi.x * hi.y;
    return (a * 4.0 + b + 0.5) / 16.0;
}
