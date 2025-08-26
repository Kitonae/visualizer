// Ripple distortion from center
extern number amplitude; // pixels
extern number frequency; // cycles across radius
extern number time;      // seconds
extern number speed;     // scroll speed

vec4 effect(vec4 color, Image texture, vec2 uv, vec2 sc) {
    vec2 c = vec2(0.5);
    vec2 p = uv - c;
    float r = length(p) + 1e-6;
    float wave = sin(r * frequency * 2.0 * 3.14159 - time * speed);
    float amt = (amplitude / max(love_ScreenSize.x, love_ScreenSize.y)) * wave;
    vec2 q = uv + normalize(p) * amt;
    return Texel(texture, q) * color;
}

