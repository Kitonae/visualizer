#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 resolution;

// Custom tanh implementation for GLSL ES
vec4 tanh_vec4(vec4 x) {
    return (exp(2.0 * x) - 1.0) / (exp(2.0 * x) + 1.0);
}

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
    vec2 C = screen_coords;
    float i = 0.0;
    float d = 0.0;
    float z = fract(dot(C, sin(C))) - 0.5;
    vec4 o = vec4(0.0);
    vec4 p = vec4(0.0);
    vec4 O = vec4(0.0);
    
    vec2 r = resolution.xy;
    
    for (float iter = 0.0; iter < 77.0; iter++) {
        i = iter + 1.0;
        
        // Ray setup
        p = vec4(z * normalize(vec3(C - 0.5 * r, r.y)), 0.1 * time);
        p.z += time;
        O = p;
        
        // Apply rotation matrices (the "bug" that creates interesting patterns)
        float angle1 = 2.0 + O.z;
        mat2 rot1 = mat2(cos(angle1), -sin(angle1), sin(angle1), cos(angle1));
        p.xy = rot1 * p.xy;
        
        float angle2 = O.z + 11.0;
        mat2 rot2 = mat2(cos(angle2), -sin(angle2), sin(angle2), cos(angle2));
        p.xy = rot2 * p.xy;
        
        float angle3 = O.z + 33.0;
        mat2 rot3 = mat2(cos(angle3), -sin(angle3), sin(angle3), cos(angle3));
        p.xy = rot3 * p.xy;
        
        // Apply second set of rotations based on full O vector
        float angle4 = O.x;
        mat2 rot4 = mat2(cos(angle4), -sin(angle4), sin(angle4), cos(angle4));
        p.xy = rot4 * p.xy;
        
        float angle5 = O.y + 11.0;
        mat2 rot5 = mat2(cos(angle5), -sin(angle5), sin(angle5), cos(angle5));
        p.xy = rot5 * p.xy;
        
        float angle6 = O.z + 33.0;
        mat2 rot6 = mat2(cos(angle6), -sin(angle6), sin(angle6), cos(angle6));
        p.xy = rot6 * p.xy;
        
        // Color calculation
        O = (1.0 + sin(0.5 * O.z + length(p - O) + vec4(0.0, 4.0, 3.0, 6.0))) 
            / (0.5 + 2.0 * dot(O.xy, O.xy));
        
        // Domain repetition
        p = abs(fract(p) - 0.5);
        
        // Distance field (cylinder + planes)
        d = abs(min(length(p.xy) - 0.125, min(p.x, p.y) + 0.001)) + 0.001;
        
        // Accumulate color
        o += (O.w / d) * O;
        
        // Step forward
        z += 0.6 * d;
        
        if (i >= 77.0) break;
    }
    
    // Tone mapping
    return tanh_vec4(o / 20000.0);
}
