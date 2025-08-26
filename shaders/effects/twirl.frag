// Twirl distortion around center
extern number angle;    // max twist in radians
extern number radius;   // 0..1 influence radius

vec4 effect(vec4 color, Image texture, vec2 uv, vec2 sc) {
    vec2 c = vec2(0.5);
    vec2 p = uv - c;
    float r = length(p);
    float t = smoothstep(radius, 0.0, r) * angle;
    float s = sin(t), co = cos(t);
    vec2 q = vec2(p.x * co - p.y * s, p.x * s + p.y * co) + c;
    return Texel(texture, q) * color;
}

