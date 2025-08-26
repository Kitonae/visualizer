// Radial blur from screen center
extern number strength; // 0..1
extern number radius;   // pixels step size

vec4 effect(vec4 color, Image texture, vec2 uv, vec2 sc) {
    vec2 center = vec2(0.5);
    vec2 toCenter = center - uv;
    float dist = length(toCenter) + 1e-6;
    vec2 dir = toCenter / dist;
    vec2 px = max(1.0, radius) / love_ScreenSize.xy;

    const int S = 9;
    vec4 sum = vec4(0.0);
    for (int i = 0; i < S; i++) {
        float t = (float(i) / float(S-1)) - 0.5; // [-0.5, 0.5]
        sum += Texel(texture, uv + dir * px * t * love_ScreenSize.x);
    }
    vec4 blurred = sum / float(S);
    vec4 orig = Texel(texture, uv);
    return mix(orig, blurred, clamp(strength, 0.0, 1.0)) * color;
}

