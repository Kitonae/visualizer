// Pixel sorting-like effect (max luminance along a direction segment)
// Not a true sort, but picks the brightest sample along a ray segment.

extern number strength;   // 0..1 mix with original
extern number distance;   // max distance in pixels along the ray
extern number angle;      // direction in radians (0 = +X)
extern number threshold;  // 0..1 luminance threshold to consider samples

float luma(vec3 c){ return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

vec4 effect(vec4 color, Image texture, vec2 uv, vec2 sc) {
    vec4 orig = Texel(texture, uv);
    vec3 best = orig.rgb;
    float bestLum = luma(best);

    vec2 dir = vec2(cos(angle), sin(angle));
    vec2 px = 1.0 / love_ScreenSize.xy;

    const int S = 24; // number of samples along the ray
    vec2 stepv = dir * (distance / float(S - 1)) * px;

    vec2 pos = uv;
    for (int i = 0; i < S; i++) {
        vec3 c = Texel(texture, pos).rgb;
        float lum = luma(c);
        if (lum >= threshold && lum > bestLum) {
            bestLum = lum;
            best = c;
        }
        pos += stepv;
    }

    vec3 outc = mix(orig.rgb, best, clamp(strength, 0.0, 1.0));
    return vec4(outc, orig.a) * color;
}

