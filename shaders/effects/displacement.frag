// Displacement using a simple procedural pattern
extern number amount; // pixels
extern number time;   // seconds

float hash(vec2 p){ return fract(sin(dot(p, vec2(41.31,289.97))) * 43758.5453); }
float noise(vec2 p){
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = hash(i);
    float b = hash(i + vec2(1.0,0.0));
    float c = hash(i + vec2(0.0,1.0));
    float d = hash(i + vec2(1.0,1.0));
    vec2 u = f*f*(3.0-2.0*f);
    return mix(a,b,u.x)+ (c-a)*u.y*(1.0-u.x) + (d-b)*u.x*u.y;
}

vec4 effect(vec4 color, Image texture, vec2 uv, vec2 sc) {
    vec2 n = vec2(noise(uv*8.0+time*0.2), noise(uv*8.0 - time*0.2));
    vec2 o = (n - 0.5) * (amount / max(love_ScreenSize.x, love_ScreenSize.y));
    return Texel(texture, uv + o) * color;
}

