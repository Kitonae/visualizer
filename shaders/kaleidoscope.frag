/* Kaleidoscope shader - converted from Shadertoy to LÖVE2D
   Original animation by creative coding tutorial
   Video URL: https://youtu.be/f4s1h2YETNY
   Palette function: https://iquilezles.org/articles/palettes/
*/


extern float time;
extern vec2 resolution;
extern vec3 palette_a;
extern vec3 palette_b;
extern vec3 palette_c;
extern vec3 palette_d;


// Color palette function
vec3 palette(float t) {
    vec3 a = palette_a;
    vec3 b = palette_b;
    vec3 c = palette_c;
    vec3 d = palette_d;
    return a + b * cos(6.28318 * (c * t + d));
}

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
    // Convert screen coordinates to UV coordinates centered at origin
    vec2 uv = (screen_coords * 2.0 - resolution.xy) / resolution.y;
    vec2 uv0 = uv;
    vec3 finalColor = vec3(0.0);
    
    // Create kaleidoscope effect with multiple iterations
    for (float i = 0.0; i < 4.0; i++) {
        // Scale and repeat the UV coordinates
        uv = fract(uv * 1.5) - 0.5;

        // Calculate distance with exponential falloff
        float d = length(uv) * exp(-length(uv0));

        // Generate color using palette function
        vec3 col = palette(length(uv0) + i * 0.4 + time * 0.4);

        // Create animated sine wave pattern
        d = sin(d * 8.0 + time) / 8.0;
        d = abs(d);

        // Apply power curve for intensity
        d = pow(0.01 / d, 1.2);

        finalColor += col * d;
    }
        
    return vec4(finalColor, 1.0);
}
