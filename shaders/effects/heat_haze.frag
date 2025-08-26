// Heat haze / wave distortion
extern number strength; // 0..1
extern number speed;    // wave speed
extern number scale;    // wave scale
extern number time;     // passed from CPU

float n2(vec2 p){ return fract(sin(dot(p, vec2(41.13, 289.97))) * 43758.5453); }

vec4 effect(vec4 color, Image texture, vec2 uv, vec2 sc) {
    float t = time * speed;
    vec2 w = vec2(sin((uv.y + t) * 20.0), cos((uv.x - t) * 15.0));
    vec2 o = w * (scale * 0.002) * strength;
    vec4 c = Texel(texture, uv + o);
    return c * color;
}

