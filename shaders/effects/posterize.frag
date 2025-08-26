// Posterization
extern number levels;   // >= 2
extern number strength; // 0..1 mix

vec4 effect(vec4 color, Image texture, vec2 uv, vec2 sc) {
    vec4 c = Texel(texture, uv);
    float L = max(2.0, levels);
    vec3 q = floor(c.rgb * L) / (L - 1.0);
    c.rgb = mix(c.rgb, q, clamp(strength, 0.0, 1.0));
    return c * color;
}

