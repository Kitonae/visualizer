// Sepia tone
extern number strength; // 0..1

vec4 effect(vec4 color, Image texture, vec2 uv, vec2 sc) {
    vec4 c = Texel(texture, uv);
    vec3 r;
    r.r = dot(c.rgb, vec3(0.393, 0.769, 0.189));
    r.g = dot(c.rgb, vec3(0.349, 0.686, 0.168));
    r.b = dot(c.rgb, vec3(0.272, 0.534, 0.131));
    c.rgb = mix(c.rgb, r, clamp(strength,0.0,1.0));
    return c * color;
}

