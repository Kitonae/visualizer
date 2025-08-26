// Grayscale
extern number strength; // 0..1

vec4 effect(vec4 color, Image texture, vec2 uv, vec2 sc) {
    vec4 c = Texel(texture, uv);
    float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
    c.rgb = mix(c.rgb, vec3(g), clamp(strength, 0.0, 1.0));
    return c * color;
}

