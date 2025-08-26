// Sobel edge detection
extern number strength; // 0..1 mix

vec4 effect(vec4 color, Image texture, vec2 uv, vec2 sc) {
    vec2 px = 1.0 / love_ScreenSize.xy;
    float sx[9];
    float sy[9];
    sx[0]=-1.0; sx[1]=0.0; sx[2]=1.0; sx[3]=-2.0; sx[4]=0.0; sx[5]=2.0; sx[6]=-1.0; sx[7]=0.0; sx[8]=1.0;
    sy[0]=-1.0; sy[1]=-2.0; sy[2]=-1.0; sy[3]=0.0; sy[4]=0.0; sy[5]=0.0; sy[6]=1.0; sy[7]=2.0; sy[8]=1.0;

    vec3 s = vec3(0.0);
    vec3 t = vec3(0.0);
    int k = 0;
    for (int j=-1;j<=1;j++){
        for (int i=-1;i<=1;i++){
            vec3 c = Texel(texture, uv + px * vec2(float(i), float(j))).rgb;
            float g = dot(c, vec3(0.299,0.587,0.114));
            s += g * sx[k];
            t += g * sy[k];
            k++;
        }
    }
    float mag = clamp(length(s)+length(t), 0.0, 1.0);
    vec4 orig = Texel(texture, uv);
    vec3 edge = vec3(mag);
    vec3 mixed = mix(orig.rgb, edge, clamp(strength, 0.0, 1.0));
    return vec4(mixed, orig.a) * color;
}

