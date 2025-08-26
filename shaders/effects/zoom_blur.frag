// Zoom blur towards the center
extern number strength; // 0..1
extern number amount;   // 0..1 zoom amount

vec4 effect(vec4 color, Image texture, vec2 uv, vec2 sc) {
    vec2 center = vec2(0.5);
    const int S = 8;
    vec4 sum = vec4(0.0);
    for (int i = 0; i < S; i++) {
        float t = float(i) / float(S);
        vec2 suv = mix(uv, center, t * amount);
        sum += Texel(texture, suv);
    }
    vec4 blurred = sum / float(S);
    vec4 orig = Texel(texture, uv);
    return mix(orig, blurred, clamp(strength, 0.0, 1.0)) * color;
}

