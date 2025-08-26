// 5x5 box blur post-process for LÖVE with adjustable radius
// radius is in pixels; larger radius increases the sample spacing

extern number strength; // 0.0 (off) .. 1.0 (full)
extern number radius;   // >= 1.0, sample spacing in screen pixels

vec4 effect(vec4 color, Image texture, vec2 uv, vec2 sc) {
    vec2 px = max(1.0, radius) / love_ScreenSize.xy;
    vec4 sum = vec4(0.0);

    // 5x5 kernel
    for (int j = -2; j <= 2; j++) {
        for (int i = -2; i <= 2; i++) {
            sum += Texel(texture, uv + px * vec2(float(i), float(j)));
        }
    }
    vec4 blurred = sum / 25.0;

    vec4 orig = Texel(texture, uv);
    vec4 outc = mix(orig, blurred, clamp(strength, 0.0, 1.0));
    return outc * color;
}
