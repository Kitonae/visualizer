// Directional (motion) blur
extern number strength; // 0..1 mix
extern number radius;   // sample spacing in pixels
extern number angle;    // radians

vec4 effect(vec4 color, Image texture, vec2 uv, vec2 sc) {
    vec2 dir = vec2(cos(angle), sin(angle));
    vec2 px = max(1.0, radius) / love_ScreenSize.xy;

    const int S = 9;
    int halfS = (S-1)/2;
    vec4 sum = vec4(0.0);
    for (int i = -halfS; i <= halfS; i++) {
        sum += Texel(texture, uv + dir * px * float(i));
    }
    vec4 blurred = sum / float(S);
    vec4 orig = Texel(texture, uv);
    return mix(orig, blurred, clamp(strength, 0.0, 1.0)) * color;
}

