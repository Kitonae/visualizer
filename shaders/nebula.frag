#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 resolution;

vec4 tanh_vec4(vec4 x) {
    return (exp(2.0 * x) - 1.0) / (exp(2.0 * x) + 1.0);
}

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
    vec2 u = screen_coords;
    float d = 0.0, a, e = 0.0, i = 0.0, s = 0.0, t = time;
    vec3 p = vec3(resolution, 0.0);
    vec4 o = vec4(0.0);

    // scale coords
    u = (u + u - resolution.xy) / resolution.y;

    // cinema bars
    if (abs(u.y) > 0.8) {
        return vec4(0.0);
    }

    // camera movement
    u += vec2(cos(t * 0.4) * 0.3, cos(t * 0.8) * 0.1);

    for (i = 0.0, o = vec4(0.0); i++ < 64.0; ) {  // Reduced iterations
        // accumulate distance
        d += s = min(0.01 + 0.4 * abs(s), e = max(0.8 * e, 0.01));

        // noise loop start, march
        p = vec3(u * d, d + t);

        // entity (orb)
        e = length(p - vec3(
            sin(sin(t * 0.2) + t * 0.4) * 4.0,
            1.0 + sin(sin(t * 1.3) + t * 0.2) * 4.0,
            12.0 + t + cos(t * 0.3) * 8.0
        )) - 0.1;

        // spin by t, twist by p.z
        float angle1 = 0.1 * t + p.z / 16.0;
        mat2 rot1 = mat2(cos(angle1), -sin(angle1), sin(angle1), cos(angle1));
        p.xy = rot1 * p.xy;

        float angle2 = 0.1 * t + p.z / 16.0 + 33.0;
        mat2 rot2 = mat2(cos(angle2), -sin(angle2), sin(angle2), cos(angle2));
        p.xy = rot2 * p.xy;

        // mirrored planes 4 units apart
        s = 4.0 - abs(p.y);

        // noise starts at .42 up to 16., grow by a+=a
        for (a = 0.42; a < 16.0; a += a) {
            // apply turbulence
            p += cos(0.4 * t + p.yzx) * 0.3;
            // apply noise
            s -= abs(dot(sin(0.1 * t + p * a), 0.2 + p - p)) / a;
        }

        // More colorful palette - red, green, blue, purple
        vec4 nebula_color = vec4(
            0.5 + 0.5 * sin(0.1 * p.z + t * 0.5 + 0.0),  // Red channel
            0.5 + 0.5 * sin(0.1 * p.z + t * 0.3 + 2.0),  // Green channel
            0.5 + 0.5 * sin(0.1 * p.z + t * 0.7 + 4.0),  // Blue channel
            1.0
        );
        
        // Add color based on distance and density - more aggressive lighting
        float density = 1.0 / (0.1 + s * s * 0.5 + e * e * 0.5);  // Larger range, less falloff
        o += nebula_color * density * 0.25;  // More aggressive accumulation
    }

    // tanh tonemap with better brightness balance
    u += (u.yx * 0.9 + 0.3 - vec2(-1.0, 0.5));
    o = tanh_vec4(o * 1.5 / max(dot(u, u), 0.001));  // Brighter overall
    return o;
}