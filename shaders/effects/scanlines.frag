// Scanlines overlay
extern number intensity; // 0..1
extern number thickness; // line thickness in pixels

vec4 effect(vec4 color, Image texture, vec2 uv, vec2 sc) {
    vec4 c = Texel(texture, uv);
    float y = uv.y * love_ScreenSize.y;
    float line = step(0.0, sin(3.14159 * (y / max(1.0, thickness))));
    float mask = mix(1.0, 0.7, line);
    c.rgb = mix(c.rgb, c.rgb * mask, clamp(intensity, 0.0, 1.0));
    return c * color;
}

