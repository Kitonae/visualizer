uniform float time;
uniform vec2 resolution;

float hash11(float p)
{
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

float sdSegment(in vec2 p, in vec2 a, in vec2 b)
{
    vec2 pa = p - a;
    vec2 ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

float columns(vec2 uv, float zoom) {
    uv *= zoom;

    vec2 cv = vec2(fract(uv.x) - 0.5, uv.y);

    float m = 0.0;
    for (int i = -1; i < 2; ++i) {
        float fi = float(i);
        float cid = floor(uv.x) + fi;

        float height = max(hash11(4.0 * hash11(cid)), 0.1) * zoom;
        float speed = hash11(height) * 8.0 + zoom * 0.5;

        vec2 offset = vec2(0.0, mod(time * speed, 4.0 * zoom) - 2.0 * zoom);
        m += 0.01 / sdSegment(cv, vec2(fi, height) + offset, vec2(fi, -height) + offset);
    }

    return m;
}

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
{
    vec2 uv = (2.0 * screen_coords - resolution) / resolution.y;
    
    // Remove the y-flip to make stars fall downward
    // uv.y *= -1.0;

    float m = 0.0;
    float p = 1.0;
    float zoom = 0.8;
    int amount_layers = 6;
    for (int i = 1; i < amount_layers; ++i) {
        float fi = float(i);

        m += columns(uv + vec2(hash11(4.0 * hash11(fi)), 0.0), zoom) * p;

        p *= 0.77;
        zoom *= 3.0;
    }

    float grad = smoothstep(-1.0, 5.0, uv.y);

    vec3 col = sin(vec3(1.0, 2.0, 3.0) + uv.y + time) * 0.3 + 0.6;
    return vec4(col * (m + grad), 1.0);
}
