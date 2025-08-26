// Vignette post-process for LÖVE
// Darkens edges with adjustable strength, radius, and softness.

extern number strength; // 0..1, how much to darken edges
extern number radius;   // 0..1, vignette start radius from center
extern number softness; // 0..1, how soft the edge falloff is

vec4 effect(vec4 color, Image texture, vec2 uv, vec2 sc) {
    vec4 c = Texel(texture, uv);

    // Account for aspect ratio so the vignette is circular
    float aspect = love_ScreenSize.x / love_ScreenSize.y;
    vec2 p = uv - 0.5;
    p.x *= aspect;
    float d = length(p);

    float r = clamp(radius, 0.0, 1.2);
    float s = max(1e-4, softness);
    // Rise from 0 at center to 1 at edges over [r, r+s]
    float v = smoothstep(r, r + s, d);

    float m = 1.0 - v * clamp(strength, 0.0, 1.0);
    c.rgb *= m;
    return c * color;
}
