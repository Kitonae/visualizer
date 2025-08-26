// Chromatic aberration (RGB split)
extern number amount; // 0..5 pixels

vec4 effect(vec4 color, Image texture, vec2 uv, vec2 sc) {
    float a = amount / max(love_ScreenSize.x, love_ScreenSize.y);
    vec2 p = uv - 0.5;
    float r = length(p);
    vec2 o = normalize(p) * a * r; // more at edges
    vec3 col;
    col.r = Texel(texture, uv + o).r;
    col.g = Texel(texture, uv).g;
    col.b = Texel(texture, uv - o).b;
    return vec4(col, Texel(texture, uv).a) * color;
}

