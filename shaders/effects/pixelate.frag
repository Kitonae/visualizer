// Pixelation post-process for LÖVE
// Quantizes UVs to a pixel grid of size `pixel_size` (in screen pixels)

extern number pixel_size; // >= 1.0

vec4 effect(vec4 color, Image texture, vec2 uv, vec2 sc) {
    float s = max(1.0, pixel_size);
    vec2 size = love_ScreenSize.xy;
    vec2 q = floor(uv * size / s) * s / size;
    vec4 c = Texel(texture, q);
    return c * color;
}

