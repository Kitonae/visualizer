// Lens barrel/pincushion distortion
extern number amount; // negative for barrel, positive for pincushion

vec4 effect(vec4 color, Image texture, vec2 uv, vec2 sc) {
    vec2 p = uv * 2.0 - 1.0;
    float r2 = dot(p, p);
    vec2 distorted = p * (1.0 + amount * r2);
    vec2 st = (distorted + 1.0) * 0.5;
    vec4 c = Texel(texture, st);
    return c * color;
}

