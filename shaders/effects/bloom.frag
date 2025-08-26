// Single-pass approximate bloom (brighten around bright spots)
extern number strength; // 0..1
extern number threshold; // 0..1

vec4 effect(vec4 color, Image texture, vec2 uv, vec2 sc) {
    vec2 px = 1.5 / love_ScreenSize.xy;
    vec4 sum = vec4(0.0);
    for (int j=-1;j<=1;j++){
        for (int i=-1;i<=1;i++){
            vec4 s = Texel(texture, uv + px * vec2(float(i), float(j)));
            float b = max(max(s.r,s.g),s.b);
            s.rgb *= step(threshold, b);
            sum += s;
        }
    }
    vec4 bloom = sum / 9.0;
    vec4 orig = Texel(texture, uv);
    vec4 outc = orig + bloom * strength;
    outc.rgb = clamp(outc.rgb, 0.0, 1.0);
    return outc * color;
}

